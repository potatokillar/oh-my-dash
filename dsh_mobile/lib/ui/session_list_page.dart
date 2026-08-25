import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'chat_page.dart';
import 'directory_picker_page.dart';
import 'widgets.dart';

class SessionListPage extends StatefulWidget {
  final AppState state;
  const SessionListPage({super.key, required this.state});

  @override
  State<SessionListPage> createState() => _SessionListPageState();
}

class _SessionListPageState extends State<SessionListPage> {
  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onState);
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.state.refresh());
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  void _openChat(String sessionId, String title, {String? cwd}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatPage(
          state: widget.state, sessionId: sessionId, title: title, cwd: cwd),
    ));
  }

  void _openPicker() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DirectoryPickerPage(state: widget.state),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.currentDevice?.name ?? '会话'),
            if (s.currentDevice != null)
              Text(
                s.currentDevice!.baseUrl,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(
              s.muxConnected ? Icons.cloud_done : Icons.cloud_off,
              color: s.muxConnected ? Colors.greenAccent : Colors.grey,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        onPressed: _openPicker,
        tooltip: '新建会话',
        child: const Icon(Icons.add),
      ),
      body: _buildBody(s),
    );
  }

  Widget _buildBody(AppState s) {
    if (s.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text('连接失败', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                s.error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: s.loading ? null : s.refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (s.loading && s.sessions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = groupSessionsByRecency(s.sessions);
    return RefreshIndicator(
      onRefresh: s.refresh,
      child: s.sessions.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 140),
                EmptyState(
                  icon: Icons.chat_bubble_outline,
                  title: '暂无会话',
                  hint: '点右下角 + 选一个目录开始新会话',
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final entry = items[i];
                if (entry is String) return ListSectionHeader(label: entry);
                final item = entry as SessionSummary;
                return SessionTile(
                  session: item,
                  onTap: () => _openChat(item.sessionId, item.displayName,
                      cwd: item.cwd),
                );
              },
            ),
    );
  }
}
