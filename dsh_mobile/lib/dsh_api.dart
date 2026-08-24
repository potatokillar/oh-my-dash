/// dsh JSON-RPC over HTTP client (unary calls + approval responses).
///
/// Zero third-party dependencies: dart:io HttpClient only.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DshApiException implements Exception {
  final String method;
  final String message;
  DshApiException(this.method, this.message);
  @override
  String toString() => '$method: $message';
}

class DshApi {
  String baseUrl;
  int _seq = 0;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  DshApi(this.baseUrl);

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final HttpClientRequest req;
    try {
      req = await _client.postUrl(_uri(path));
    } catch (e) {
      throw DshApiException(path, '无法连接服务器: $e');
    }
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final HttpClientResponse res;
    try {
      res = await req.close().timeout(const Duration(seconds: 30));
    } catch (e) {
      throw DshApiException(path, '请求失败: $e');
    }
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw DshApiException(path, 'HTTP ${res.statusCode}: $text');
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw DshApiException(path, '意外响应: $text');
    }
    return decoded;
  }

  /// Unary call: POST `<base>/api/<method>`.
  Future<dynamic> rpc(String method, [Map<String, dynamic> payload = const {}]) async {
    final rpcId = 'dsh-mobile-${++_seq}-${DateTime.now().millisecondsSinceEpoch}';
    final msg = await _post('/api/$method', {
      'type': 'client-request',
      'rpcId': rpcId,
      'method': method,
      'payload': payload,
    });
    if (msg['type'] != 'server-response') {
      throw DshApiException(method, '意外报文: ${jsonEncode(msg)}');
    }
    final result = msg['result'];
    if (result is! Map) {
      throw DshApiException(method, '缺少 result: ${jsonEncode(msg)}');
    }
    if (result['ok'] == true) return result['value'];
    final error = result['error'];
    final em = error is Map ? (error['message'] ?? error['code'] ?? error) : error;
    throw DshApiException(method, 'RPC 错误: $em');
  }

  /// Answer an answerable server-request (approval). POST `<base>/api/respond`.
  Future<void> respond({
    required String rpcId,
    required Map<String, dynamic> value,
  }) async {
    await _post('/api/respond', {
      'type': 'client-response',
      'rpcId': rpcId,
      'result': {'ok': true, 'value': value},
    });
  }

  // ---- convenience wrappers ----

  Future<Map<String, dynamic>> describe() async =>
      (await rpc('host.describe')) as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> listSessions() async {
    final value = await rpc('session.list');
    final items = (value as Map)['items'];
    if (items is! List) return const [];
    return items.whereType<Map<String, dynamic>>().toList();
  }

  /// session.create: pass exactly one of [cwd] / [workspaceId].
  Future<String> createSession({String? cwd, String? workspaceId}) async {
    final value = await rpc('session.create', {
      'cwd': ?cwd,
      'workspaceId': ?workspaceId,
    });
    return ((value as Map)['sessionId'] as String?) ?? '';
  }

  /// workspace.list: {items: [WorkspaceView], archivedSessionIds: [string]}.
  Future<Map<String, dynamic>> listWorkspaces() async {
    final value = await rpc('workspace.list');
    return (value as Map).cast<String, dynamic>();
  }

  /// workspace.create over an existing directory: {workspace, created}.
  Future<Map<String, dynamic>> createWorkspace(String path) async {
    final value = await rpc('workspace.create', {'path': path});
    return (value as Map).cast<String, dynamic>();
  }

  /// host.listDirectory: omit [path] to list the host default directory.
  Future<Map<String, dynamic>> listDirectory({String? path}) async {
    final value = await rpc('host.listDirectory', {'path': ?path});
    return (value as Map).cast<String, dynamic>();
  }

  /// host.createDirectory: create child [name] under [path]; returns the new path.
  Future<String> createDirectory({required String path, required String name}) async {
    final value = await rpc('host.createDirectory', {'path': path, 'name': name});
    return ((value as Map)['path'] as String?) ?? '';
  }

  /// Returns the raw history value: {events: [{event, view?}], hasMore, projections?}.
  /// Pass [beforeSeq] (the earliest loaded event seq) to page one window older.
  Future<Map<String, dynamic>> history(String sessionId,
      {int? beforeSeq, int maxMessages = 200}) async {
    final value = await rpc('session.history', {
      'sessionId': sessionId,
      'beforeSeq': ?beforeSeq,
      'maxMessages': maxMessages,
    });
    return (value as Map).cast<String, dynamic>();
  }

  /// session.models: the model catalog + current selection for one session.
  Future<Map<String, dynamic>> sessionModels(String sessionId) async {
    final value = await rpc('session.models', {'sessionId': sessionId});
    return (value as Map).cast<String, dynamic>();
  }

  /// session.selectModel: select provider/model (+optional reasoningEffort).
  Future<Map<String, dynamic>> selectModel({
    required String sessionId,
    required String provider,
    required String model,
    String? reasoningEffort,
  }) async {
    final value = await rpc('session.selectModel', {
      'sessionId': sessionId,
      'provider': provider,
      'model': model,
      'reasoningEffort': ?reasoningEffort,
    });
    return (value as Map).cast<String, dynamic>();
  }

  /// session.rename: pin a new title; returns {title, seq}.
  Future<String> renameSession(String sessionId, String title) async {
    final value = await rpc('session.rename', {
      'sessionId': sessionId,
      'title': title,
    });
    return ((value as Map)['title'] as String?) ?? title;
  }

  Future<void> prompt(
      String sessionId, List<Map<String, dynamic>> content) async {
    await rpc('session.prompt', {
      'sessionId': sessionId,
      'mode': 'queue',
      'content': content,
    });
  }

  Future<void> cancel(String sessionId) async {
    await rpc('session.cancel', {'sessionId': sessionId});
  }

  Future<void> respondApproval({
    required String rpcId,
    required String sessionId,
    required String approvalId,
    required String outcome, // 'allowed-once' | 'rejected'
  }) async {
    await respond(rpcId: rpcId, value: {
      'sessionId': sessionId,
      'approvalId': approvalId,
      'outcome': outcome,
    });
  }

  void dispose() => _client.close(force: true);
}
