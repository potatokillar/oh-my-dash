import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'chat_page.dart';
import 'directory_picker_page.dart';
import 'widgets.dart';

/// Sessions of one directory (one project): session.list filtered by the
/// sessions' cwd — grouping is keyed on cwd ONLY, never on the workspace
/// registry. With [path] null this is the "未知目录" view (sessions with no
/// recorded cwd).
class WorkspaceSessionsPage extends StatefulWidget {
  final AppState state;

  /// Normalized absolute path of the project; null = 未知目录 group.
  final String? path;
  final String title;
  const WorkspaceSessionsPage({
    super.key,
    required this.state,
    required this.title,
    this.path,
  });

  @override
  State<WorkspaceSessionsPage> createState() => _WorkspaceSessionsPageState();
}

class _WorkspaceSessionsPageState extends State<WorkspaceSessionsPage> {
  bool _creating = false;

  bool get _isUnknownDir => widget.path == null;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onState);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  Future<void> _newSessionInProject() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      // cwd is the single source of truth for grouping.
      final sessionId =
          await widget.state.api.createSession(cwd: widget.path);
      if (!mounted) return;
      await widget.state.refresh();
      if (!mounted) return;
      _openChat(sessionId, '新会话', cwd: widget.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('创建会话失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _newSessionPickDir() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DirectoryPickerPage(state: widget.state),
    ));
  }

  void _openChat(String sessionId, String title, {String? cwd}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatPage(
          state: widget.state, sessionId: sessionId, title: title, cwd: cwd),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final path = widget.path;
    final sessions = path != null
        ? (s.sessions
            .where((item) =>
                item.cwd != null && normalizePath(item.cwd!) == path)
            .toList())
        : unknownCwdSessions(s.sessions);
    return Scaffold(
      appBar: AppBar(
        title: path == null
            ? Text(widget.title)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title),
                  Text(
                    path,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        onPressed: _creating
            ? null
            : (_isUnknownDir ? _newSessionPickDir : _newSessionInProject),
        tooltip: '新建会话',
        child: _creating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: s.refresh,
        child: sessions.isEmpty
            ? ListView(
                children: [
                  const SizedBox(height: 140),
                  EmptyState(
                    icon: Icons.chat_bubble_outline,
                    title: _isUnknownDir ? '没有未知目录的会话' : '该项目下暂无会话',
                    hint: '点右下角 + 新建一个会话',
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: sessions.length,
                itemBuilder: (_, i) {
                  final item = sessions[i];
                  return SessionTile(
                    session: item,
                    onTap: () => _openChat(item.sessionId, item.displayName,
                        cwd: item.cwd ?? path),
                  );
                },
              ),
      ),
    );
  }
}
