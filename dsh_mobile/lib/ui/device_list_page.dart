import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'device_home_page.dart';

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
        onPressed: () => _editDevice(),
        tooltip: '添加设备',
        child: const Icon(Icons.add),
      ),
      body: devices.isEmpty
          ? const Center(child: Text('暂无设备，点右下角添加'))
          : ListView.separated(
              itemCount: devices.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final d = devices[i];
                final probe = _probes[d.id];
                return ListTile(
                  leading: _statusIcon(probe),
                  title: Text(d.name),
                  subtitle: Text(
                    [d.baseUrl, if (probe?.subtitle != null) probe!.subtitle!]
                        .join('\n'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: probe?.subtitle != null,
                  onTap: () => _openSessions(d),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) {
                      if (action == 'edit') _editDevice(existing: d);
                      if (action == 'delete') _deleteDevice(d);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _statusIcon(_Probe? probe) {
    if (probe == null || probe.loading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Icon(
      probe.online ? Icons.dns : Icons.cloud_off,
      color: probe.online ? Colors.greenAccent : Colors.grey,
    );
  }
}
