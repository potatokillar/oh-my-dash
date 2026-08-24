import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'device_home_page.dart';
import 'widgets.dart';

/// Probe outcome for one device row.
class _Probe {
  final bool loading;
  final bool online;
  final String? subtitle;
  const _Probe({this.loading = false, this.online = false, this.subtitle});
}

/// Home page: managed dsh devices. Tap an online device to open its session
/// list; add/edit/delete devices here (server address setting lives in the
/// edit form).
class DeviceListPage extends StatefulWidget {
  final AppState state;
  const DeviceListPage({super.key, required this.state});

  @override
  State<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends State<DeviceListPage> {
  final Map<String, _Probe> _probes = {};

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onState);
    _probeAll();
    // Restore the last-used device: jump straight into its session list.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final d = widget.state.currentDevice;
      if (d != null && mounted) _openSessions(d);
    });
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  void _probeAll() {
    for (final d in widget.state.devices) {
      _probe(d);
    }
  }

  Future<void> _probe(Device d) async {
    setState(() => _probes[d.id] = const _Probe(loading: true));
    try {
      final desc = await widget.state.probeDevice(d);
      if (!mounted) return;
      final provider = desc['provider'];
      final model = desc['model'];
      final cwd = desc['cwd'];
      final subtitle = [
        if (provider != null || model != null)
          [provider, model].where((e) => e != null).join('/'),
        if (cwd != null) cwd as String,
      ].join(' · ');
      setState(() =>
          _probes[d.id] = _Probe(online: true, subtitle: subtitle));
    } catch (e) {
      if (!mounted) return;
      setState(() => _probes[d.id] = _Probe(subtitle: '离线: $e'));
    }
  }

  Future<void> _openSessions(Device d) async {
    final probe = _probes[d.id];
    if (probe != null && !probe.loading && !probe.online) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('「${d.name}」连不上，请检查设备与地址')),
      );
      return;
    }
    await widget.state.selectDevice(d);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DeviceHomePage(state: widget.state),
    ));
    // Returning from the session list: re-probe to refresh statuses.
    _probeAll();
  }

  Future<void> _editDevice({Device? existing}) async {
    final nameCtl = TextEditingController(text: existing?.name ?? '');
    final urlCtl = TextEditingController(text: existing?.baseUrl ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? '添加设备' : '编辑设备'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              autofocus: existing == null,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            TextField(
              controller: urlCtl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '地址',
                hintText: 'http://100.103.29.13:3080',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (nameCtl.text.trim().isEmpty ||
                  !isValidBaseUrl(urlCtl.text)) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('名称不能为空，地址须为 http(s):// 开头')),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    if (existing == null) {
      final d = await widget.state
          .addDevice(name: nameCtl.text, baseUrl: urlCtl.text);
      _probe(d);
    } else {
      final updated = Device(
          id: existing.id, name: nameCtl.text, baseUrl: urlCtl.text.trim());
      await widget.state.updateDevice(updated);
      _probe(updated);
    }
  }

  Future<void> _deleteDevice(Device d) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除设备'),
        content: Text('确定删除「${d.name}」(${d.baseUrl}) 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.state.removeDevice(d.id);
      _probes.remove(d.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = widget.state.devices;
    return Scaffold(
      appBar: AppBar(title: const Text('DSH 设备')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        onPressed: () => _editDevice(),
        tooltip: '添加设备',
        child: const Icon(Icons.add),
      ),
      body: devices.isEmpty
          ? const EmptyState(
              icon: Icons.dns_outlined,
              title: '暂无设备',
              hint: '点右下角 + 添加一台 dsh 主机',
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: devices.length,
              itemBuilder: (_, i) =>
                  _DeviceCard(
                    device: devices[i],
                    probe: _probes[devices[i].id],
                    onTap: () => _openSessions(devices[i]),
                    onEdit: () => _editDevice(existing: devices[i]),
                    onDelete: () => _deleteDevice(devices[i]),
                  ),
            ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final Device device;
  final _Probe? probe;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DeviceCard({
    required this.device,
    required this.probe,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = probe?.online ?? false;
    final loading = probe?.loading ?? true;
    final statusColor =
        loading ? theme.colorScheme.outline : (online ? Colors.greenAccent : Colors.grey);
    final statusText = loading ? '探测中…' : (online ? '在线' : '离线');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Stack(
                children: [
                  IconBadge(
                    icon: Icons.dns,
                    color: theme.colorScheme.primary,
                    size: 48,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surfaceContainer,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      device.baseUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    if (probe?.subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        probe!.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Text(
                      statusText,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (action) {
                  if (action == 'edit') onEdit();
                  if (action == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
