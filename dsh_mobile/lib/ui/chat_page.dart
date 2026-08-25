import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../event_mux.dart';
import '../models.dart';
import 'widgets.dart';

class ChatPage extends StatefulWidget {
  final AppState state;
  final String sessionId;
  final String title;
  final String? cwd;
  const ChatPage({
    super.key,
    required this.state,
    required this.sessionId,
    required this.title,
    this.cwd,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  StreamSubscription<MuxMessage>? _sub;
  bool _loading = true;
  String? _error;
  bool _turnActive = false;
  bool _sending = false;

  late String _title;

  /// History pagination: seq of the earliest loaded event + host's hasMore.
  int? _earliestSeq;
  bool _hasMore = false;
  bool _loadingOlder = false;

  /// session.models snapshot (null until loaded / on silent failure).
  SessionModels? _models;

  /// Images staged in the composer for the next prompt.
  final List<PendingImage> _pendingImages = [];
  final ImagePicker _picker = ImagePicker();

  /// The in-progress "typing" bubble fed by assistant/chunk deltas.
  ChatMessage? _streamingBubble;

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _sub = widget.state.mux.frames.listen(_onFrame);
    _scroll.addListener(_onScroll);
    _inputFocus.addListener(() => setState(() {}));
    _loadHistory();
    _loadModels();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---- history ----

  /// Parse one history page into (messages, earliestSeq).
  (List<ChatMessage>, int?) _parsePage(Map<String, dynamic> hist) {
    final events = hist['events'];
    final msgs = <ChatMessage>[];
    int? earliest;
    if (events is List) {
      for (final entry in events) {
        if (entry is! Map) continue;
        final ev = entry['event'];
        if (ev is Map) {
          final seq = (ev['seq'] as num?)?.toInt();
          if (seq != null && (earliest == null || seq < earliest)) {
            earliest = seq;
          }
          final m = messageFromEvent(ev.cast<String, dynamic>());
          if (m != null) msgs.add(m);
        }
      }
    }
    return (msgs, earliest);
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hist = await widget.state.api.history(widget.sessionId);
      final (msgs, earliest) = _parsePage(hist);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs);
        _earliestSeq = earliest;
        _hasMore = hist['hasMore'] as bool? ?? false;
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels < 80) _loadOlder();
  }

  /// Load one older page and prepend it, keeping the scroll offset stable.
  Future<void> _loadOlder() async {
    if (_loading || _loadingOlder || !_hasMore || _earliestSeq == null) return;
    _loadingOlder = true;
    if (mounted) setState(() {});
    final oldMax =
        _scroll.hasClients ? _scroll.position.maxScrollExtent : null;
    final oldOffset = _scroll.hasClients ? _scroll.position.pixels : 0.0;
    try {
      final hist = await widget.state.api
          .history(widget.sessionId, beforeSeq: _earliestSeq);
      final (msgs, earliest) = _parsePage(hist);
      if (!mounted) return;
      setState(() {
        _messages.insertAll(0, msgs);
        if (earliest != null) _earliestSeq = earliest;
        _hasMore = hist['hasMore'] as bool? ?? false;
      });
      // Compensate for the prepended extent so the viewport does not jump.
      if (oldMax != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            final delta = _scroll.position.maxScrollExtent - oldMax;
            if (delta > 0) _scroll.jumpTo(oldOffset + delta);
          }
        });
      }
    } catch (_) {
      // Keep hasMore; the next top-scroll retries.
    } finally {
      _loadingOlder = false;
      if (mounted) setState(() {});
    }
  }

  // ---- live frames ----

  void _onFrame(MuxMessage msg) {
    final f = msg.payload;
    if (f['type'] != 'session/event' || f['sessionId'] != widget.sessionId) {
      return;
    }
    final ev = f['event'];
    if (ev is! Map) return;
    final event = ev.cast<String, dynamic>();
    switch (event['type']) {
      case 'turn/start':
        setState(() => _turnActive = true);
      case 'turn/end':
        setState(() {
          _turnActive = false;
          _streamingBubble = null;
        });
      case 'session/title':
        final data = event['data'];
        final title = data is Map ? data['title'] : null;
        if (title is String && title.isNotEmpty) {
          setState(() => _title = title);
        }
      case 'assistant/chunk':
        final delta = chunkTextFromEvent(event);
        if (delta != null) {
          setState(() {
            final bubble = _streamingBubble ??
                (_streamingBubble = ChatMessage(
                  isUser: false,
                  blocks: [const ChatBlock('')],
                  time: DateTime.now().millisecondsSinceEpoch,
                  streaming: true,
                ));
            if (!_messages.contains(bubble)) _messages.add(bubble);
            bubble.blocks[0] = ChatBlock(bubble.blocks[0].text + delta);
          });
          _scrollToBottom();
        }
      case 'user/message' || 'assistant/message':
        final m = messageFromEvent(event);
        if (m != null) {
          setState(() {
            // A finalized assistant message replaces the streaming placeholder.
            if (!m.isUser && _streamingBubble != null) {
              _messages.remove(_streamingBubble);
              _streamingBubble = null;
            }
            _messages.add(m);
          });
          _scrollToBottom();
        }
    }
  }

  // ---- models ----

  Future<void> _loadModels() async {
    try {
      final raw = await widget.state.api.sessionModels(widget.sessionId);
      if (!mounted) return;
      setState(() => _models = SessionModels.fromJson(raw));
    } catch (_) {
      // Older host without session.models: hide the affordance.
    }
  }

  String _currentModelLabel() {
    final m = _models;
    if (m == null) return '';
    for (final g in m.groups) {
      if (g.id != m.current.provider) continue;
      for (final model in g.models) {
        if (model.id == m.current.model) {
          return model.name.isEmpty ? model.id : model.name;
        }
      }
    }
    return m.current.model;
  }

  Future<void> _showModelPicker() async {
    final models = _models;
    if (models == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('模型目录未加载')));
      return;
    }
    String selProvider = models.current.provider;
    String selModel = models.current.model;
    String? selEffort = models.current.reasoningEffort;

    ModelInfo? findModel() {
      for (final g in models.groups) {
        if (g.id != selProvider) continue;
        for (final m in g.models) {
          if (m.id == selModel) return m;
        }
      }
      return null;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final selected = findModel();
          final efforts = selected?.efforts ?? const <ModelEffort>[];
          final scheme = Theme.of(ctx).colorScheme;
          final captionStyle = Theme.of(ctx)
              .textTheme
              .labelMedium
              ?.copyWith(color: scheme.outline);
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final g in models.groups) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
                            child: Text(g.name.isEmpty ? g.id : g.name,
                                style: captionStyle),
                          ),
                          for (final m in g.models)
                            Builder(builder: (ctx) {
                              final isSel =
                                  g.id == selProvider && m.id == selModel;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 3),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => setSheet(() {
                                    selProvider = g.id;
                                    selModel = m.id;
                                    selEffort = m.defaultEffort;
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainer,
                                      borderRadius:
                                          BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isSel
                                            ? scheme.primary
                                            : scheme.outlineVariant
                                                .withValues(alpha: 0.35),
                                        width: isSel ? 1.5 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                m.name.isEmpty
                                                    ? m.id
                                                    : m.name,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: Theme.of(ctx)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      fontWeight: isSel
                                                          ? FontWeight.w600
                                                          : FontWeight
                                                              .normal,
                                                    ),
                                              ),
                                              if (m.name.isNotEmpty)
                                                Text(
                                                  m.id,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(ctx)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                          color: scheme
                                                              .outline),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (isSel)
                                          Icon(Icons.check_circle,
                                              size: 20,
                                              color: scheme.primary),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                        ],
                        if (efforts.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
                            child: Text('推理强度', style: captionStyle),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            child: Wrap(
                              spacing: 8,
                              children: [
                                for (final e in efforts)
                                  ChoiceChip(
                                    label: Text(
                                        e.name.isEmpty ? e.id : e.name),
                                    selected: selEffort == e.id,
                                    selectedColor: scheme.primary,
                                    labelStyle: TextStyle(
                                      color: selEffort == e.id
                                          ? scheme.onPrimary
                                          : null,
                                    ),
                                    onSelected: (_) =>
                                        setSheet(() => selEffort = e.id),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        if (models.failureCount > 0)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
                            child: Text(
                              '${models.failureCount} 个 provider 加载失败',
                              style: Theme.of(ctx)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.outline),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('确认'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (confirmed != true) return;
    try {
      final res = await widget.state.api.selectModel(
        sessionId: widget.sessionId,
        provider: selProvider,
        model: selModel,
        reasoningEffort: selEffort,
      );
      if (!mounted) return;
      final selected = res['selected'];
      setState(() {
        final m = _models;
        if (m != null && selected is Map) {
          _models = SessionModels(
            current: ModelSelection.fromJson(
                selected.cast<String, dynamic>()),
            routable: m.routable,
            groups: m.groups,
            failureCount: m.failureCount,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('切换模型失败: $e')));
      }
    }
  }

  // ---- rename / info ----

  Future<void> _rename() async {
    final controller = TextEditingController(text: _title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '新标题'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final trimmed = title?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == _title) return;
    try {
      final accepted =
          await widget.state.api.renameSession(widget.sessionId, trimmed);
      if (!mounted) return;
      setState(() => _title = accepted.isEmpty ? trimmed : accepted);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('重命名失败: $e')));
      }
    }
  }

  void _showInfo() {
    final m = _models;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('会话信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText('sessionId:\n${widget.sessionId}'),
            if (widget.cwd != null) ...[
              const SizedBox(height: 8),
              SelectableText('cwd:\n${widget.cwd}'),
            ],
            if (m != null) ...[
              const SizedBox(height: 8),
              Text(
                  '模型: ${m.current.provider}/${m.current.model}'
                  '${m.current.reasoningEffort != null ? ' (${m.current.reasoningEffort})' : ''}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // ---- prompt ----

  Future<void> _pickImages() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 70);
      if (files.isEmpty || !mounted) return;
      final added = <PendingImage>[];
      for (final f in files) {
        added.add(PendingImage(
          bytes: await f.readAsBytes(),
          mediaType: f.mimeType ?? 'image/jpeg',
          name: f.name,
        ));
      }
      setState(() => _pendingImages.addAll(added));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('选择图片失败: $e')));
      }
    }
  }

  Future<void> _send() async {
    final content = buildPromptContent(_input.text, _pendingImages);
    if (content.isEmpty || _sending || _turnActive) return;
    setState(() => _sending = true);
    try {
      await widget.state.api.prompt(widget.sessionId, content);
      _input.clear();
      setState(() => _pendingImages.clear());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('发送失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _cancel() async {
    try {
      await widget.state.api.cancel(widget.sessionId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('停止失败: $e')));
      }
    }
  }

  /// Quick-action tap: stage the prompt in the composer (never auto-send).
  void _fillPrompt(String prompt) {
    _input.value = TextEditingValue(
      text: prompt,
      selection: TextSelection.collapsed(offset: prompt.length),
    );
    _inputFocus.requestFocus();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            onSelected: (action) {
              if (action == 'rename') _rename();
              if (action == 'info') _showInfo();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('重命名')),
              PopupMenuItem(value: 'info', child: Text('查看会话信息')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildList()),
          if (_models != null && !_models!.routable)
            Container(
              width: double.infinity,
              color: Colors.red.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.redAccent, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('当前模型路由不可用，请切换模型后再发送'),
                  ),
                ],
              ),
            ),
          if (_turnActive)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHigh,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(4),
                        bottomRight: Radius.circular(16),
                      ),
                    ),
                    child: TypingDots(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          // Quick-action chips above the composer: hidden while the keyboard
          // is up or the conversation is empty (the empty hero has its own
          // bento grid).
          if (_messages.isNotEmpty &&
              MediaQuery.of(context).viewInsets.bottom == 0)
            _buildQuickChipStrip(),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadHistory, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return _EmptyChat(onPick: _fillPrompt);
    }
    // Interleave a date separator wherever the calendar day changes.
    final items = <Object>[]; // String separator label or ChatMessage
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final prev = i > 0 ? _messages[i - 1] : null;
      if (m.time > 0 &&
          (prev == null ||
              prev.time <= 0 ||
              isDifferentDay(prev.time, m.time))) {
        items.add(dateSeparatorLabel(m.time));
      }
      items.add(m);
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      itemCount: items.length + (_loadingOlder ? 1 : 0),
      itemBuilder: (_, i) {
        if (_loadingOlder && i == 0) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('加载更早消息…'),
                ],
              ),
            ),
          );
        }
        final item = items[_loadingOlder ? i - 1 : i];
        if (item is String) return _DateSeparator(label: item);
        return _Bubble(message: item as ChatMessage);
      },
    );
  }

  /// Horizontally scrollable quick-action chips staged above the composer.
  /// Same behavior as the empty-chat bento cards: fill, never send.
  Widget _buildQuickChipStrip() {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: kQuickActions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final a = kQuickActions[i];
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _fillPrompt(a.$4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(a.$1, size: 14, color: a.$2),
                  const SizedBox(width: 5),
                  Text(a.$3,
                      style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildComposer() {
    final scheme = Theme.of(context).colorScheme;
    final modelLabel = _currentModelLabel();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _inputFocus.hasFocus
                  ? scheme.primary
                  : scheme.outlineVariant.withValues(alpha: 0.25),
              width: _inputFocus.hasFocus ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_pendingImages.isNotEmpty) _buildAttachmentStrip(),
              TextField(
                controller: _input,
                focusNode: _inputFocus,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: '发消息…',
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              Row(
                children: [
                  // Model picker chip.
                  InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _showModelPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.model_training,
                              size: 15, color: scheme.primary),
                          const SizedBox(width: 5),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 160),
                            child: Text(
                              modelLabel.isEmpty ? '选择模型' : modelLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          const Icon(Icons.expand_more, size: 15),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.image_outlined),
                    tooltip: '添加图片',
                    onPressed: _pickImages,
                  ),
                  const Spacer(),
                  // Send becomes stop while a turn is running.
                  if (_turnActive)
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(42, 42),
                      ),
                      onPressed: _cancel,
                      icon: const Icon(Icons.stop_rounded, size: 20),
                    )
                  else
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        minimumSize: const Size(42, 42),
                      ),
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Horizontal strip of staged image thumbnails, each with a remove ×.
  Widget _buildAttachmentStrip() {
    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
        itemCount: _pendingImages.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final img = _pendingImages[i];
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  img.bytes,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () => setState(() => _pendingImages.removeAt(i)),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close,
                        size: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Centered date separator between message groups: muted caption with
/// hairlines on both sides.
class _DateSeparator extends StatelessWidget {
  final String label;
  const _DateSeparator({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget line() => Expanded(
          child: Container(
            height: 0.5,
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          line(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.outline),
            ),
          ),
          line(),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isUser = message.isUser;
    final color =
        isUser ? scheme.primaryContainer : scheme.surfaceContainerHigh;
    // Asymmetric corners: the tail side keeps a small corner.
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isUser ? 16 : 4),
      bottomRight: Radius.circular(isUser ? 4 : 16),
    );
    final bubble = Container(
        margin: EdgeInsets.only(
          top: 6,
          bottom: 6,
          left: isUser ? 0 : 2,
          right: isUser ? 2 : 0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(color: color, borderRadius: radius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final block in message.blocks)
              if (block.isReasoning)
                _ReasoningBlock(text: block.text)
              else if (block.isImage)
                _ImagePlaceholder(name: block.text)
              else
                SelectableText(block.text),
            if (message.streaming)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      );
    if (isUser) {
      return Align(alignment: Alignment.centerRight, child: bubble);
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Small accent orb marking the assistant side.
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(left: 2, bottom: 6),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child:
                Icon(Icons.smart_toy_outlined, size: 15, color: scheme.primary),
          ),
          const SizedBox(width: 8),
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

/// Placeholder card for an image attachment in history (bytes are not
/// fetched; the host serves them by reference).
class _ImagePlaceholder extends StatelessWidget {
  final String name;
  const _ImagePlaceholder({required this.name});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasoningBlock extends StatefulWidget {
  final String text;
  const _ReasoningBlock({required this.text});

  @override
  State<_ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<_ReasoningBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.psychology_alt,
                      size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Text('思考过程', style: style),
                  const SizedBox(width: 2),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: SelectableText(widget.text, style: style),
            ),
        ],
      ),
    );
  }
}

/// Quick-action definitions shared by the empty-chat bento grid and the
/// composer chip strip: (icon, iconColor, label, prompt prefix).
const kQuickActions = <(IconData, Color, String, String)>[
  (Icons.code, Color(0xFF7C6CF0), '写代码', '帮我写一段代码：'),
  (Icons.school_outlined, Color(0xFF4FC3F7), '解释概念', '用简单的语言解释一下：'),
  (Icons.lightbulb_outline, Color(0xFFFFB74D), '头脑风暴', '我们来头脑风暴一下：'),
  (Icons.summarize_outlined, Color(0xFF81C784), '总结文字', '帮我总结这段文字：'),
];

/// Empty-conversation hero: greeting + glowing accent orb + a 2×2 bento
/// grid of quick actions. Tapping a card only stages its prompt in the
/// composer; nothing is sent automatically.
class _EmptyChat extends StatelessWidget {
  final ValueChanged<String> onPick;
  const _EmptyChat({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Glowing orb: radial-gradient core wrapped in a soft halo.
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    scheme.primary.withValues(alpha: 0.95),
                    scheme.primary.withValues(alpha: 0.35),
                    scheme.primary.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.45, 1],
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.45),
                    blurRadius: 60,
                    spreadRadius: 12,
                  ),
                ],
              ),
              child: Icon(
                Icons.auto_awesome,
                size: 34,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              '有什么可以帮你？',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '消息会与其他端实时同步',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
            const SizedBox(height: 28),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var r = 0; r < 2; r++) ...[
                    if (r > 0) const SizedBox(height: 10),
                    Row(
                      children: [
                        for (var c = 0; c < 2; c++) ...[
                          if (c > 0) const SizedBox(width: 10),
                          Expanded(
                            child: _QuickActionCard(
                              icon: kQuickActions[r * 2 + c].$1,
                              color: kQuickActions[r * 2 + c].$2,
                              label: kQuickActions[r * 2 + c].$3,
                              onTap: () =>
                                  onPick(kQuickActions[r * 2 + c].$4),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One bento cell of the empty-chat quick-action grid.
class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _QuickActionCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
