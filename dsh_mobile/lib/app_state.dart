/// App-wide state: device list, the currently selected device's connection
/// (DshApi + EventMux), session list, approval dispatch.
/// One ChangeNotifier, no third-party state lib.
///
/// Only the currently selected device holds a live mux connection, so all
/// inbound frames (including approvals) belong to that device.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_store.dart';
import 'dsh_api.dart';
import 'event_mux.dart';
import 'models.dart';

/// A pending tool-call approval the UI should present.
class ApprovalRequest {
  final String rpcId;
  final String sessionId;
  final String approvalId;
  final String toolName;
  final String? reason;
  const ApprovalRequest({
    required this.rpcId,
    required this.sessionId,
    required this.approvalId,
    required this.toolName,
    this.reason,
  });
}

class AppState extends ChangeNotifier {
  late SharedPreferences _prefs;

  /// API client of the current device; only valid while [currentDevice] is
  /// set (session list / picker / chat are only reachable in that state).
  DshApi get api => _api!;
  DshApi? _api;
  final EventMux mux = EventMux();

  List<Device> devices = [];
  Device? currentDevice;

  List<SessionSummary> sessions = [];
  List<Workspace> workspaces = [];
  Set<String> archivedSessionIds = {};
  bool loading = false;
  String? error;
  bool muxConnected = false;

  /// Host process cwd of the current device, cached from the host.describe
  /// handshake; used as the directory picker's initial path.
  String? hostCwd;

  final StreamController<ApprovalRequest> _approvals =
      StreamController<ApprovalRequest>.broadcast();
  Stream<ApprovalRequest> get approvals => _approvals.stream;

  StreamSubscription<MuxMessage>? _frameSub;
  StreamSubscription<bool>? _statusSub;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    devices = await DeviceStore.loadDevices(_prefs);
    _wireMux();
    final lastId = DeviceStore.loadLastDeviceId(_prefs);
    if (lastId != null) {
      final d = devices.where((e) => e.id == lastId).firstOrNull;
      if (d != null) {
        await selectDevice(d);
        return;
      }
    }
    notifyListeners();
  }

  void _wireMux() {
    _statusSub = mux.status.listen((connected) {
      muxConnected = connected;
      notifyListeners();
    });
    _frameSub = mux.frames.listen((msg) {
      final f = msg.payload;
      switch (f['type']) {
        case 'approval/requested':
          _approvals.add(ApprovalRequest(
            rpcId: msg.rpcId,
            sessionId: f['sessionId'] as String? ?? '',
            approvalId: f['approvalId'] as String? ?? '',
            toolName: f['toolName'] as String? ?? '(未知工具)',
            reason: f['reason'] as String?,
          ));
        case 'session/event':
          final ev = f['event'];
          if (ev is Map && ev['type'] == 'session/title') {
            _onTitle(f['sessionId'] as String?, (ev['data'] as Map?)?['title']);
          }
      }
    });
  }

  void _onTitle(String? sessionId, dynamic title) {
    if (sessionId == null || title is! String || title.isEmpty) return;
    final i = sessions.indexWhere((s) => s.sessionId == sessionId);
    if (i < 0) return;
    final s = sessions[i];
    sessions[i] = SessionSummary(
      sessionId: s.sessionId,
      updatedAt: s.updatedAt,
      running: s.running,
      blank: s.blank,
      cwd: s.cwd,
      agentPreset: s.agentPreset,
      title: title,
    );
    notifyListeners();
  }

  // ---- device management ----

  Future<Device> addDevice({required String name, required String baseUrl}) async {
    final d = Device(
      id: 'dev-${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      baseUrl: baseUrl.trim(),
    );
    devices = [...devices, d];
    await DeviceStore.saveDevices(_prefs, devices);
    notifyListeners();
    return d;
  }

  Future<void> updateDevice(Device updated) async {
    final i = devices.indexWhere((d) => d.id == updated.id);
    if (i < 0) return;
    devices = [...devices]..[i] = updated;
    await DeviceStore.saveDevices(_prefs, devices);
    if (currentDevice?.id == updated.id) {
      // Reconnect the live connection with the edited address.
      currentDevice = null;
      notifyListeners();
      await selectDevice(updated);
    } else {
      notifyListeners();
    }
  }

  Future<void> removeDevice(String id) async {
    devices = devices.where((d) => d.id != id).toList();
    await DeviceStore.saveDevices(_prefs, devices);
    if (currentDevice?.id == id) {
      currentDevice = null;
      mux.close();
      _api?.dispose();
      _api = null;
      sessions = [];
      workspaces = [];
      archivedSessionIds = {};
      error = null;
      hostCwd = null;
      await DeviceStore.saveLastDeviceId(_prefs, null);
    }
    notifyListeners();
  }

  /// host.describe probe for one device (temporary client, no side effects).
  Future<Map<String, dynamic>> probeDevice(Device d) async {
    final api = DshApi(d.baseUrl);
    try {
      return await api.describe();
    } finally {
      api.dispose();
    }
  }

  /// Select a device: tear down the old connection, build a fresh
  /// DshApi + mux for it, persist it as the last-used device.
  Future<void> selectDevice(Device d) async {
    if (currentDevice?.id == d.id) return;
    currentDevice = d;
    _api?.dispose();
    _api = DshApi(d.baseUrl);
    sessions = [];
    workspaces = [];
    archivedSessionIds = {};
    error = null;
    hostCwd = null;
    mux.connect(d.baseUrl);
    await DeviceStore.saveLastDeviceId(_prefs, d.id);
    notifyListeners();
    await refresh();
  }

  // ---- current-device session operations ----

  Future<void> refresh() async {
    if (_api == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final desc = await api.describe(); // health check
      hostCwd = desc['cwd'] as String? ?? hostCwd;
      final items = await api.listSessions();
      sessions = items.map(SessionSummary.fromJson).toList();
      try {
        final ws = await api.listWorkspaces();
        workspaces = ((ws['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Workspace.fromJson(e.cast<String, dynamic>()))
            .toList();
        archivedSessionIds =
            ((ws['archivedSessionIds'] as List?) ?? const [])
                .whereType<String>()
                .toSet();
      } catch (_) {
        // workspace.list unsupported on this host: degrade to no projects.
        workspaces = [];
        archivedSessionIds = {};
      }
      // Archived sessions are hidden from every session surface.
      sessions = sessions
          .where((s) => !archivedSessionIds.contains(s.sessionId))
          .toList();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> answerApproval(ApprovalRequest req, String outcome) async {
    await api.respondApproval(
      rpcId: req.rpcId,
      sessionId: req.sessionId,
      approvalId: req.approvalId,
      outcome: outcome,
    );
  }

  @override
  void dispose() {
    _frameSub?.cancel();
    _statusSub?.cancel();
    mux.dispose();
    _api?.dispose();
    _approvals.close();
    super.dispose();
  }
}
