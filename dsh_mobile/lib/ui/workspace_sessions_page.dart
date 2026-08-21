import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'chat_page.dart';

/// Sessions of one workspace: session.list filtered by the workspace's
/// sessionIds (archived/unknown ids dropped).
class WorkspaceSessionsPage extends StatefulWidget {
  final AppState state;
  final Workspace workspace;
  const WorkspaceSessionsPage({
    super.key,
    required this.state,
    required this.workspace,
  });

  @override
  State<WorkspaceSessionsPage> createState() => _WorkspaceSessionsPageState();
}

class _WorkspaceSessionsPageState extends State<WorkspaceSessionsPage> {
  bool _creating = false;

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

  Future<void> _newSession() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final sessionId = await widget.state.api
          .createSession(workspaceId: widget.workspace.workspaceId);
      if (!mounted) return;
      await widget.state.refresh();
      if (!mounted) return;
      _openChat(sessionId, '新会话');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('创建会话失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _openChat(String sessionId, String title) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          ChatPage(state: widget.state, sessionId: sessionId, title: title),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final sessions = sessionsForWorkspace(
        s.sessions, widget.workspace, s.archivedSessionIds);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.workspace.title.isEmpty
                ? '项目会话'
                : widget.workspace.title),
            Text(
              widget.workspace.path,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _creating ? null : _newSession,
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
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('该项目下暂无会话')),
                ],
              )
            : ListView.separated(
                itemCount: sessions.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final item = sessions[i];
                  return ListTile(
                    leading: Icon(
                      item.running
                          ? Icons.play_circle
                          : Icons.chat_bubble_outline,
                      color: item.running ? Colors.greenAccent : null,
                    ),
                    title: Text(item.displayName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: item.agentPreset == null
                        ? null
                        : Text(item.agentPreset!,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text(formatTime(item.updatedAt),
                        style: Theme.of(context).textTheme.bodySmall),
                    onTap: () => _openChat(item.sessionId, item.displayName),
                  );
                },
              ),
      ),
    );
  }
}
