import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../event_mux.dart';
import '../models.dart';

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

  /// The in-progress "typing" bubble fed by assistant/chunk deltas.
  ChatMessage? _streamingBubble;

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _sub = widget.state.mux.frames.listen(_onFrame);
    _scroll.addListener(_onScroll);
    _loadHistory();
    _loadModels();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
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
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(g.name.isEmpty ? g.id : g.name,
                                style:
                                    Theme.of(ctx).textTheme.labelLarge),
                          ),
                          for (final m in g.models)
                            ListTile(
                              dense: true,
                              title: Text(m.name.isEmpty ? m.id : m.name),
                              subtitle:
                                  m.name.isEmpty ? null : Text(m.id),
                              trailing: (g.id == selProvider &&
                                      m.id == selModel)
                                  ? const Icon(Icons.check,
                                      color: Colors.greenAccent)
                                  : null,
                              onTap: () => setSheet(() {
                                selProvider = g.id;
                                selModel = m.id;
                                selEffort = m.defaultEffort;
                              }),
                            ),
                        ],
                        if (efforts.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text('推理强度',
                                style:
                                    Theme.of(ctx).textTheme.labelLarge),
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
                                    onSelected: (_) =>
                                        setSheet(() => selEffort = e.id),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        if (models.failureCount > 0)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              '${models.failureCount} 个 provider 加载失败',
                              style: Theme.of(ctx).textTheme.bodySmall,
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

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.state.api.prompt(widget.sessionId, text);
      _input.clear();
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
    final modelLabel = _currentModelLabel();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (modelLabel.isNotEmpty)
              GestureDetector(
                onTap: _showModelPicker,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        modelLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 16),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          if (_models != null)
            IconButton(
              icon: const Icon(Icons.model_training),
              tooltip: '切换模型',
              onPressed: _showModelPicker,
            ),
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
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('正在思考…')),
                  TextButton.icon(
                    onPressed: _cancel,
                    icon: const Icon(Icons.stop, color: Colors.redAccent),
                    label: const Text('停止'),
                  ),
                ],
              ),
            ),
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
      return const Center(child: Text('开始对话吧'));
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length + (_loadingOlder ? 1 : 0),
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
        final index = _loadingOlder ? i - 1 : i;
        return _Bubble(message: _messages[index]);
      },
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: '发消息…',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
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
    final isUser = message.isUser;
    final color = isUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final block in message.blocks)
              if (block.isReasoning)
                _ReasoningBlock(text: block.text)
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
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Colors.grey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: Colors.grey,
              ),
              Text('思考过程', style: style),
            ],
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: SelectableText(widget.text, style: style),
          ),
      ],
    );
  }
}
