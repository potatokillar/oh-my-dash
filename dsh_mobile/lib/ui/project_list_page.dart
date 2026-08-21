import 'package:flutter/material.dart';

import '../app_state.dart';
import 'directory_picker_page.dart';
import 'workspace_sessions_page.dart';

/// 项目 tab: workspace.list of the current device.
class ProjectListPage extends StatefulWidget {
  final AppState state;
  const ProjectListPage({super.key, required this.state});

  @override
  State<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends State<ProjectListPage> {
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

  void _addWorkspace() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DirectoryPickerPage(
        state: widget.state,
        mode: PickerMode.addWorkspace,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Scaffold(
      appBar: AppBar(title: const Text('项目')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addWorkspace,
        tooltip: '添加项目',
        child: const Icon(Icons.create_new_folder),
      ),
      body: RefreshIndicator(
        onRefresh: s.refresh,
        child: s.workspaces.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('暂无项目，点右下角添加')),
                ],
              )
            : ListView.separated(
                itemCount: s.workspaces.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final w = s.workspaces[i];
                  final count = w.visibleSessionCount(s.archivedSessionIds);
                  return ListTile(
                    leading: const Icon(Icons.folder, color: Colors.amber),
                    title: Text(w.title.isEmpty ? w.path : w.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(w.path,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text('$count 个会话',
                        style: Theme.of(context).textTheme.bodySmall),
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => WorkspaceSessionsPage(
                          state: widget.state,
                          workspace: w,
                        ),
                      ));
                    },
                  );
                },
              ),
      ),
    );
  }
}
