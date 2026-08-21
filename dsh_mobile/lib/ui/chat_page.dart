import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../event_mux.dart';
import '../models.dart';

class ChatPage extends StatefulWidget {
  final AppState state;
  final String sessionId;
  final String title;
  const ChatPage({
    super.key,
    required this.state,
    required this.sessionId,
    required this.title,
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

  /// The in-progress "typing" bubble fed by assistant/chunk deltas.
  ChatMessage? _streamingBubble;

  @override
  void initState() {
    super.initState();
    _sub = widget.state.mux.frames.listen(_onFrame);
    _loadHistory();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hist = await widget.state.api.history(widget.sessionId);
      final events = hist['events'];
      final msgs = <ChatMessage>[];
      if (events is List) {
        for (final entry in events) {
          if (entry is! Map) continue;
          final ev = entry['event'];
          if (ev is Map) {
            final m = messageFromEvent(ev.cast<String, dynamic>());
            if (m != null) msgs.add(m);
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Expanded(child: _buildList()),
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
      itemCount: _messages.length,
      itemBuilder: (_, i) => _Bubble(message: _messages[i]),
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
