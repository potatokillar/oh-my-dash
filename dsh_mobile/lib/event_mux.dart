/// WebSocket downstream stream: `<base>/api/events.mux`.
///
/// Receive-only. Every frame is a `server-request` envelope whose payload is
/// a MuxFrame. Auto-reconnects with simple backoff until [close] is called.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One received server-request: envelope rpcId + MuxFrame payload.
/// The rpcId must be echoed verbatim when answering an answerable frame
/// (e.g. `approval/requested` via POST /api/respond).
class MuxMessage {
  final String rpcId;
  final Map<String, dynamic> payload;
  const MuxMessage(this.rpcId, this.payload);
}

class EventMux {
  /// One broadcast event per received MuxFrame.
  final StreamController<MuxMessage> _frames =
      StreamController<MuxMessage>.broadcast();

  /// Connection status changes (true = connected).
  final StreamController<bool> _status = StreamController<bool>.broadcast();

  Stream<MuxMessage> get frames => _frames.stream;
  Stream<bool> get status => _status.stream;

  String? _baseUrl;
  WebSocket? _ws;
  bool _closed = true;
  int _retry = 0;
  Timer? _reconnectTimer;

  bool get connected => _ws != null;

  /// (Re)connect to `<base>/api/events.mux`. Safe to call again with a new
  /// base URL — the old socket is torn down first.
  void connect(String baseUrl) {
    _baseUrl = baseUrl;
    _closed = false;
    _retry = 0;
    _reconnectTimer?.cancel();
    _teardown();
    _open();
  }

  void close() {
    _closed = true;
    _reconnectTimer?.cancel();
    _teardown();
  }

  void _teardown() {
    final ws = _ws;
    _ws = null;
    if (ws != null) {
      ws.close().catchError((_) {});
      _status.add(false);
    }
  }

  Future<void> _open() async {
    final base = _baseUrl;
    if (base == null || _closed) return;
    final wsUrl = '${base.replaceFirst(RegExp(r'^http'), 'ws')}/api/events.mux';
    WebSocket ws;
    try {
      ws = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 10));
    } catch (_) {
      _scheduleReconnect();
      return;
    }
    if (_closed || base != _baseUrl) {
      ws.close().catchError((_) {});
      return;
    }
    _ws = ws;
    _retry = 0;
    _status.add(true);
    ws.listen(
      (data) {
        try {
          final msg = jsonDecode(data as String);
          if (msg is Map && msg['type'] == 'server-request') {
            final payload = msg['payload'];
            if (payload is Map) {
              _frames.add(MuxMessage(
                msg['rpcId'] as String? ?? '',
                payload.cast<String, dynamic>(),
              ));
            }
          }
        } catch (_) {
          // Malformed frame: ignore.
        }
      },
      onError: (_) {},
      onDone: () {
        if (identical(_ws, ws)) _ws = null;
        _status.add(false);
        _scheduleReconnect();
      },
      cancelOnError: true,
    );
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _reconnectTimer?.cancel();
    final delay = Duration(seconds: _retry < 5 ? (1 << _retry) : 30);
    _retry++;
    _reconnectTimer = Timer(delay, _open);
  }

  void dispose() {
    close();
    _frames.close();
    _status.close();
  }
}
