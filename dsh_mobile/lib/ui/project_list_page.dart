import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'directory_picker_page.dart';
import 'widgets.dart';
import 'workspace_sessions_page.dart';

/// 项目 tab: sessions of the current device grouped by their cwd (the
/// directory is the project), merged with the workspace registry for titles
/// and empty projects.
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
    final theme = Theme.of(context);
    final groups = groupSessionsByCwd(s.sessions, s.workspaces);
    final unknownCount = unknownCwdSessions(s.sessions).length;
    final itemCount = groups.length + (unknownCount > 0 ? 1 : 0);
    return Scaffold(
      appBar: AppBar(title: const Text('项目')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        onPressed: _addWorkspace,
        tooltip: '添加项目',
        child: const Icon(Icons.create_new_folder),
      ),
      body: RefreshIndicator(
        onRefresh: s.refresh,
        child: itemCount == 0
            ? ListView(
                children: const [
                  SizedBox(height: 140),
                  EmptyState(
                    icon: Icons.folder_outlined,
                    title: '暂无项目',
                    hint: '点右下角按钮，把主机上的一个目录添加为项目',
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: itemCount,
                itemBuilder: (_, i) {
                  if (i == groups.length) {
                    return _buildUnknownDirCard(theme, unknownCount);
                  }
                  final g = groups[i];
                  return _buildProjectCard(g, theme);
                },
              ),
      ),
    );
  }

  Widget _buildProjectCard(ProjectGroup g, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => WorkspaceSessionsPage(
              state: widget.state,
              title: g.title,
              path: g.path,
            ),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const IconBadge(icon: Icons.folder, color: Colors.amber),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      g.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${g.sessionCount} 个会话',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnknownDirCard(ThemeData theme, int count) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => WorkspaceSessionsPage(
              state: widget.state,
              title: '未知目录',
            ),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              IconBadge(
                icon: Icons.folder_off_outlined,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '未知目录',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '没有记录工作目录的会话',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count 个会话',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
