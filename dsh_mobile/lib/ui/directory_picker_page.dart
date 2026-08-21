import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'chat_page.dart';

/// What the bottom action button of the picker does.
enum PickerMode {
  /// session.create({cwd: picked dir}), then enter the chat.
  createSession,

  /// workspace.create({path: picked dir}), then return to the project list.
  addWorkspace,
}

/// Server-side directory browser (host.listDirectory) for picking a host
/// directory: the cwd of a new session, or the path of a new workspace.
class DirectoryPickerPage extends StatefulWidget {
  final AppState state;
  final PickerMode mode;
  const DirectoryPickerPage({
    super.key,
    required this.state,
    this.mode = PickerMode.createSession,
  });

  @override
  State<DirectoryPickerPage> createState() => _DirectoryPickerPageState();
}

class _DirectoryPickerPageState extends State<DirectoryPickerPage> {
  DirectoryListing? _listing;
  bool _loading = true;
  String? _error;
  bool _showHidden = false;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    // Initial path: the host cwd cached from the host.describe handshake.
    _load(widget.state.hostCwd);
  }

  Future<void> _load(String? path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await widget.state.api.listDirectory(path: path);
      if (!mounted) return;
      setState(() {
        _listing = DirectoryListing.fromJson(raw);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _newFolder() async {
    final current = _listing?.path;
    if (current == null) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '文件夹名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    try {
      await widget.state.api.createDirectory(path: current, name: trimmed);
      if (!mounted) return;
      _load(current);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('创建文件夹失败: $e')));
      }
    }
  }

  Future<void> _confirm() async {
    final current = _listing?.path;
    if (current == null || _creating) return;
    setState(() => _creating = true);
    try {
      if (widget.mode == PickerMode.addWorkspace) {
        final res = await widget.state.api.createWorkspace(current);
        if (!mounted) return;
        await widget.state.refresh();
        if (!mounted) return;
        if (res['created'] == false) {
          final title =
              (res['workspace'] as Map?)?['title'] as String? ?? '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('该目录已属于项目「$title」')),
          );
        }
        // Back to the project list (refreshed via AppState listener).
        Navigator.of(context).pop();
      } else {
        final sessionId =
            await widget.state.api.createSession(cwd: current);
        if (!mounted) return;
        await widget.state.refresh();
        if (!mounted) return;
        // Replace the picker with the chat so back lands on the session list.
        await Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ChatPage(
            state: widget.state,
            sessionId: sessionId,
            title: '新会话',
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${widget.mode == PickerMode.addWorkspace ? '添加项目' : '创建会话'}失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAddWorkspace = widget.mode == PickerMode.addWorkspace;
    return Scaffold(
      appBar: AppBar(
        title: Text(isAddWorkspace ? '选择项目目录' : '选择工作目录'),
        actions: [
          IconButton(
            icon: Icon(_showHidden ? Icons.visibility : Icons.visibility_off),
            tooltip: _showHidden ? '隐藏以点开头的目录' : '显示隐藏目录',
            onPressed: () => setState(() => _showHidden = !_showHidden),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            tooltip: '新建文件夹',
            onPressed: _listing == null ? null : _newFolder,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loading ? null : () => _load(_listing?.path),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: (_listing == null || _creating) ? null : _confirm,
            icon: _creating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            label: Text(isAddWorkspace ? '添加此目录为项目' : '在此目录创建会话'),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _listing == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _listing == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _load(widget.state.hostCwd),
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    final listing = _listing!;
    final entries = _showHidden
        ? listing.entries
        : listing.entries.where((e) => !e.hidden).toList();
    return Column(
      children: [
        _buildCrumbs(listing),
        const Divider(height: 1),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('没有子目录'))
              : ListView.builder(
                  itemCount: entries.length + (listing.truncated ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= entries.length) {
                      return const ListTile(
                        leading: Icon(Icons.more_horiz),
                        title: Text('条目过多，仅显示前一部分'),
                      );
                    }
                    final e = entries[i];
                    return ListTile(
                      leading: Icon(
                        Icons.folder,
                        color: e.hidden ? Colors.grey : Colors.amber,
                      ),
                      title: Text(e.name),
                      onTap: () => _load(e.path),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCrumbs(DirectoryListing listing) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: listing.crumbs.length,
        separatorBuilder: (_, _) => const Icon(Icons.chevron_right, size: 16),
        itemBuilder: (_, i) {
          final c = listing.crumbs[i];
          final isLast = i == listing.crumbs.length - 1;
          return Center(
            child: TextButton(
              onPressed: isLast ? null : () => _load(c.path),
              child: Text(
                c.name.isEmpty ? '/' : c.name,
                style: TextStyle(
                  fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
