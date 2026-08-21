/// Pure data models and JSON parsing helpers for the dsh protocol.
///
/// Everything in this file is free of I/O so it can be unit-tested with
/// fake JSON payloads.
library;

/// One row of `session.list`.
class SessionSummary {
  final String sessionId;
  final int updatedAt; // epoch ms
  final bool running;
  final bool blank;
  final String? cwd;
  final String? agentPreset;
  final String? title;

  SessionSummary({
    required this.sessionId,
    required this.updatedAt,
    required this.running,
    required this.blank,
    this.cwd,
    this.agentPreset,
    this.title,
  });

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    return SessionSummary(
      sessionId: json['sessionId'] as String? ?? '',
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      running: json['running'] as bool? ?? false,
      blank: json['blank'] as bool? ?? false,
      cwd: json['cwd'] as String?,
      agentPreset: json['agentPreset'] as String?,
      title: extractTitle(json['projections']),
    );
  }

  /// Display name: title > "新会话" (blank) > cwd basename + short id.
  String get displayName {
    final t = title;
    if (t != null && t.isNotEmpty) return t;
    if (blank) return '新会话';
    final base = cwd == null ? '' : cwd!.split('/').where((s) => s.isNotEmpty).lastOrNull ?? '';
    final short = sessionId.length > 8 ? sessionId.substring(0, 8) : sessionId;
    return base.isEmpty ? short : '$base · $short';
  }
}

/// Defensively dig a session title out of a `projections` block.
///
/// Shape: `{asOfSeq, values: {<key>: <value>}}`. A value may be a string
/// or a map containing a `title` string; any of them may be the title.
String? extractTitle(dynamic projections) {
  if (projections is! Map) return null;
  final values = projections['values'];
  if (values is! Map) return null;
  for (final v in values.values) {
    if (v is String && v.isNotEmpty) return v;
    if (v is Map) {
      final t = v['title'];
      if (t is String && t.isNotEmpty) return t;
    }
  }
  return null;
}

/// One content block of a chat message.
class ChatBlock {
  final bool isReasoning;
  final String text;
  const ChatBlock(this.text, {this.isReasoning = false});
}

/// A renderable chat bubble.
class ChatMessage {
  final bool isUser;
  final List<ChatBlock> blocks;

  /// True while this bubble is the in-progress streaming placeholder.
  bool streaming;

  ChatMessage({required this.isUser, required this.blocks, this.streaming = false});

  String get text =>
      blocks.where((b) => !b.isReasoning).map((b) => b.text).join();
}

/// Concatenate the `text` blocks out of a content array, collecting
/// `reasoning` blocks separately (assistant only).
List<ChatBlock> _blocksFromContent(dynamic content) {
  final blocks = <ChatBlock>[];
  if (content is! List) return blocks;
  for (final b in content) {
    if (b is! Map) continue;
    final text = b['text'];
    if (text is! String || text.isEmpty) continue;
    if (b['type'] == 'text') {
      blocks.add(ChatBlock(text));
    } else if (b['type'] == 'reasoning') {
      blocks.add(ChatBlock(text, isReasoning: true));
    }
  }
  return blocks;
}

/// Convert a `SessionEvent` (history entry or mux frame event) into a
/// renderable [ChatMessage], or null when the event is not a visible message.
///
/// - `user/message`: only rendered when `data.source.kind == 'user'`
///   (a second user/message carries the runtime context snapshot and must be
///   filtered out).
/// - `assistant/message`: text + reasoning blocks.
ChatMessage? messageFromEvent(Map<String, dynamic> event) {
  final type = event['type'];
  final data = event['data'];
  if (data is! Map) return null;
  if (type == 'user/message') {
    final source = data['source'];
    if (source is! Map || source['kind'] != 'user') return null;
    final blocks = _blocksFromContent(data['content']);
    if (blocks.isEmpty) return null;
    return ChatMessage(isUser: true, blocks: blocks);
  }
  if (type == 'assistant/message') {
    final message = data['message'];
    if (message is! Map) return null;
    final blocks = _blocksFromContent(message['content']);
    if (blocks.isEmpty) return null;
    return ChatMessage(isUser: false, blocks: blocks);
  }
  return null;
}

/// Defensively extract incremental text from an `assistant/chunk` event.
///
/// Known shapes carry the text in `data.chunk.text` or in
/// `data.chunk.delta.text`; anything else returns null and the final
/// `assistant/message` event is relied upon instead.
String? chunkTextFromEvent(Map<String, dynamic> event) {
  if (event['type'] != 'assistant/chunk') return null;
  final data = event['data'];
  if (data is! Map) return null;
  final chunk = data['chunk'];
  if (chunk is! Map) return null;
  final direct = chunk['text'];
  if (direct is String && direct.isNotEmpty) return direct;
  final delta = chunk['delta'];
  if (delta is Map) {
    final t = delta['text'];
    if (t is String && t.isNotEmpty) return t;
  }
  return null;
}

/// Format epoch ms as `MM-dd HH:mm` (today: `HH:mm`).
String formatTime(int epochMs) {
  if (epochMs <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(dt.hour)}:${two(dt.minute)}';
  if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
    return hm;
  }
  return '${two(dt.month)}-${two(dt.day)} $hm';
}

/// One directory row of a `host.listDirectory` listing (child or crumb).
class DirectoryEntry {
  final String name;
  final String path;
  final bool hidden;
  const DirectoryEntry({required this.name, required this.path, this.hidden = false});

  factory DirectoryEntry.fromJson(Map<String, dynamic> json) => DirectoryEntry(
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        hidden: json['hidden'] as bool? ?? false,
      );
}

/// `host.listDirectory` response value: one level plus its ancestry.
class DirectoryListing {
  final String path;
  final String home;
  final List<DirectoryEntry> crumbs;
  final List<DirectoryEntry> entries;
  final bool truncated;

  const DirectoryListing({
    required this.path,
    required this.home,
    required this.crumbs,
    required this.entries,
    this.truncated = false,
  });

  factory DirectoryListing.fromJson(Map<String, dynamic> json) {
    List<DirectoryEntry> parseList(dynamic v) => v is List
        ? v
            .whereType<Map>()
            .map((e) => DirectoryEntry.fromJson(e.cast<String, dynamic>()))
            .toList()
        : const <DirectoryEntry>[];
    return DirectoryListing(
      path: json['path'] as String? ?? '',
      home: json['home'] as String? ?? '',
      crumbs: parseList(json['crumbs']),
      entries: parseList(json['entries']),
      truncated: json['truncated'] as bool? ?? false,
    );
  }
}

/// A managed dsh host ("device"): one row of the device list.
class Device {
  final String id;
  final String name;
  final String baseUrl;

  const Device({required this.id, required this.name, required this.baseUrl});

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        baseUrl: json['baseUrl'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'baseUrl': baseUrl};
}

/// Basic validation for a user-entered server address: absolute http(s) URL
/// with a non-empty host.
bool isValidBaseUrl(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null) return false;
  if (u.scheme != 'http' && u.scheme != 'https') return false;
  return u.host.isNotEmpty;
}

/// One workspace row of `workspace.list`.
class Workspace {
  final String workspaceId;
  final String path;
  final String title;
  final List<String> sessionIds;
  final String createdAt; // ISO-8601
  final String updatedAt; // ISO-8601

  const Workspace({
    required this.workspaceId,
    required this.path,
    required this.title,
    required this.sessionIds,
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory Workspace.fromJson(Map<String, dynamic> json) => Workspace(
        workspaceId: json['workspaceId'] as String? ?? '',
        path: json['path'] as String? ?? '',
        title: json['title'] as String? ?? '',
        sessionIds: (json['sessionIds'] is List)
            ? (json['sessionIds'] as List).whereType<String>().toList()
            : const [],
        createdAt: json['createdAt'] as String? ?? '',
        updatedAt: json['updatedAt'] as String? ?? '',
      );

  /// Sessions accounted here minus the archived ones (grouping surfaces hide
  /// archived sessions).
  int visibleSessionCount(Set<String> archivedSessionIds) =>
      sessionIds.where((id) => !archivedSessionIds.contains(id)).length;
}

/// Filter a full session list down to one workspace's sessions.
///
/// Membership comes from [workspace.sessionIds]; ids not present in
/// [sessions] (archived-elsewhere, deleted, or otherwise unknown) are
/// dropped, as are sessions in [archivedSessionIds]. Result keeps the
/// session.list order (updatedAt descending).
List<SessionSummary> sessionsForWorkspace(
  List<SessionSummary> sessions,
  Workspace workspace, [
  Set<String> archivedSessionIds = const {},
]) {
  final ids = workspace.sessionIds.toSet();
  return sessions
      .where((s) =>
          ids.contains(s.sessionId) && !archivedSessionIds.contains(s.sessionId))
      .toList();
}
