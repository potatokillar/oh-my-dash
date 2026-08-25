import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'chat_page.dart';
import 'widgets.dart';

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
  final ScrollController _crumbScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Initial path: the host cwd cached from the host.describe handshake.
    _load(widget.state.hostCwd);
  }

  @override
  void dispose() {
    _crumbScroll.dispose();
    super.dispose();
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
      // Keep the current-directory chip visible at the end of the chain.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_crumbScroll.hasClients) {
          _crumbScroll.jumpTo(_crumbScroll.position.maxScrollExtent);
        }
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
        // Grouping is keyed on cwd only; always create with the picked dir.
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isAddWorkspace ? '选择项目目录' : '选择工作目录'),
            if (_listing != null)
              Text(
                _listing!.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
          ],
        ),
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
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: theme.textTheme.titleSmall,
            ),
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
        Expanded(
          child: entries.isEmpty
              ? const EmptyState(
                  icon: Icons.folder_open,
                  title: '没有子目录',
                  hint: '可直接在底部选择当前目录',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: entries.length + (listing.truncated ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= entries.length) {
                      return const ListTile(
                        leading: Icon(Icons.more_horiz),
                        title: Text('条目过多，仅显示前一部分'),
                      );
                    }
                    final e = entries[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _load(e.path),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              IconBadge(
                                icon: e.hidden
                                    ? Icons.folder_off_outlined
                                    : Icons.folder,
                                color: e.hidden
                                    ? Theme.of(context).colorScheme.outline
                                    : Colors.amber,
                                size: 40,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  e.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                          fontWeight: FontWeight.w600),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Horizontal scrolling chip chain; the current directory is accent-lit.
  Widget _buildCrumbs(DirectoryListing listing) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 56,
      child: ListView.separated(
        controller: _crumbScroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: listing.crumbs.length,
        separatorBuilder: (_, _) => Icon(
          Icons.chevron_right,
          size: 16,
          color: scheme.outline,
        ),
        itemBuilder: (_, i) {
          final c = listing.crumbs[i];
          final isLast = i == listing.crumbs.length - 1;
          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: isLast ? null : () => _load(c.path),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isLast
                    ? scheme.primary.withValues(alpha: 0.18)
                    : scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isLast
                      ? scheme.primary.withValues(alpha: 0.6)
                      : scheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                c.name.isEmpty ? '/' : c.name,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: isLast ? scheme.primary : null,
                      fontWeight:
                          isLast ? FontWeight.w600 : FontWeight.normal,
                    ),
              ),
            ),
          );
        },
      ),
    );
  }
}
