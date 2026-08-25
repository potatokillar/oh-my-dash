/// Pure data models and JSON parsing helpers for the dsh protocol.
///
/// Everything in this file is free of I/O so it can be unit-tested with
/// fake JSON payloads.
library;

import 'dart:convert';
import 'dart:typed_data';

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

  /// True for an image attachment placeholder (history carries image blocks
  /// by reference; bytes are not rendered inline).
  final bool isImage;
  final String text;
  const ChatBlock(this.text, {this.isReasoning = false, this.isImage = false});
}

/// A renderable chat bubble.
class ChatMessage {
  final bool isUser;
  final List<ChatBlock> blocks;

  /// Event time (epoch ms); 0 when unknown.
  final int time;

  /// True while this bubble is the in-progress streaming placeholder.
  bool streaming;

  ChatMessage(
      {required this.isUser,
      required this.blocks,
      this.time = 0,
      this.streaming = false});

  String get text =>
      blocks.where((b) => !b.isReasoning).map((b) => b.text).join();
}

/// Concatenate the `text` blocks out of a content array, collecting
/// `reasoning` blocks separately (assistant only) and `image` blocks as
/// placeholders.
List<ChatBlock> _blocksFromContent(dynamic content) {
  final blocks = <ChatBlock>[];
  if (content is! List) return blocks;
  for (final b in content) {
    if (b is! Map) continue;
    if (b['type'] == 'image') {
      final name = b['name'];
      blocks.add(ChatBlock(
          name is String && name.isNotEmpty ? name : '图片',
          isImage: true));
      continue;
    }
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
    return ChatMessage(
        isUser: true,
        blocks: blocks,
        time: (event['time'] as num?)?.toInt() ?? 0);
  }
  if (type == 'assistant/message') {
    final message = data['message'];
    if (message is! Map) return null;
    final blocks = _blocksFromContent(message['content']);
    if (blocks.isEmpty) return null;
    return ChatMessage(
        isUser: false,
        blocks: blocks,
        time: (event['time'] as num?)?.toInt() ?? 0);
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

// ---- date grouping ----

/// Chat message separator label: 今天 / 昨天 / `M月d日` (different year:
/// `yyyy年M月d日`). [now] is injectable for tests.
String dateSeparatorLabel(int epochMs, {DateTime? now}) {
  final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final n = now ?? DateTime.now();
  final diff =
      DateTime(n.year, n.month, n.day).difference(DateTime(dt.year, dt.month, dt.day)).inDays;
  if (diff <= 0) return '今天';
  if (diff == 1) return '昨天';
  if (dt.year == n.year) return '${dt.month}月${dt.day}日';
  return '${dt.year}年${dt.month}月${dt.day}日';
}

/// Whether two timestamps fall on different calendar days (local time).
bool isDifferentDay(int prevMs, int curMs) {
  final a = DateTime.fromMillisecondsSinceEpoch(prevMs);
  final b = DateTime.fromMillisecondsSinceEpoch(curMs);
  return a.year != b.year || a.month != b.month || a.day != b.day;
}

/// Coarse recency bucket for session lists: 0 = 今天, 1 = 昨天, 2 = 更早
/// (epochMs <= 0 counts as 更早).
int recencyBucket(int epochMs, {DateTime? now}) {
  if (epochMs <= 0) return 2;
  final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final n = now ?? DateTime.now();
  final diff =
      DateTime(n.year, n.month, n.day).difference(DateTime(dt.year, dt.month, dt.day)).inDays;
  if (diff <= 0) return 0;
  if (diff == 1) return 1;
  return 2;
}

/// Display label of a [recencyBucket].
String recencyBucketLabel(int bucket) =>
    const ['今天', '昨天', '更早'][bucket.clamp(0, 2)];

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
}

// ---- session.models / session.selectModel ----

/// One selectable reasoning effort of a model.
class ModelEffort {
  final String id;
  final String name;
  const ModelEffort({required this.id, required this.name});

  factory ModelEffort.fromJson(Map<String, dynamic> json) => ModelEffort(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );
}

/// One model inside a provider group.
class ModelInfo {
  final String id;
  final String name;
  final List<ModelEffort> efforts;
  final String? defaultEffort;

  const ModelInfo({
    required this.id,
    required this.name,
    this.efforts = const [],
    this.defaultEffort,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    final reasoning = json['reasoning'];
    List<ModelEffort> efforts = const [];
    String? defaultEffort;
    if (reasoning is Map) {
      final list = reasoning['efforts'];
      if (list is List) {
        efforts = list
            .whereType<Map>()
            .map((e) => ModelEffort.fromJson(e.cast<String, dynamic>()))
            .toList();
      }
      defaultEffort = reasoning['defaultEffort'] as String?;
    }
    return ModelInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      efforts: efforts,
      defaultEffort: defaultEffort,
    );
  }
}

/// One provider and the models it advertised.
class ProviderGroup {
  final String id;
  final String name;
  final List<ModelInfo> models;
  const ProviderGroup({required this.id, required this.name, this.models = const []});

  factory ProviderGroup.fromJson(Map<String, dynamic> json) => ProviderGroup(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        models: (json['models'] is List)
            ? (json['models'] as List)
                .whereType<Map>()
                .map((e) => ModelInfo.fromJson(e.cast<String, dynamic>()))
                .toList()
            : const [],
      );
}

/// Complete model selection for one session.
class ModelSelection {
  final String provider;
  final String model;
  final String? reasoningEffort;
  const ModelSelection({required this.provider, required this.model, this.reasoningEffort});

  factory ModelSelection.fromJson(Map<String, dynamic> json) => ModelSelection(
        provider: json['provider'] as String? ?? '',
        model: json['model'] as String? ?? '',
        reasoningEffort: json['reasoningEffort'] as String?,
      );
}

/// `session.models` response value.
class SessionModels {
  final ModelSelection current;
  final bool routable;
  final List<ProviderGroup> groups;
  final int failureCount;

  const SessionModels({
    required this.current,
    required this.routable,
    this.groups = const [],
    this.failureCount = 0,
  });

  factory SessionModels.fromJson(Map<String, dynamic> json) {
    final current = json['current'];
    final groups = json['groups'];
    final failures = json['failures'];
    return SessionModels(
      current: current is Map
          ? ModelSelection.fromJson(current.cast<String, dynamic>())
          : const ModelSelection(provider: '', model: ''),
      routable: json['routable'] as bool? ?? true,
      groups: groups is List
          ? groups
              .whereType<Map>()
              .map((e) => ProviderGroup.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const [],
      failureCount: failures is List ? failures.length : 0,
    );
  }
}

/// Normalize a host path for comparison: strip trailing slashes (except the
/// filesystem root).
String normalizePath(String path) {
  if (path.length > 1) {
    var end = path.length;
    while (end > 1 && path[end - 1] == '/') {
      end--;
    }
    return path.substring(0, end);
  }
  return path;
}

/// Last non-empty segment of a host path ('/' itself yields '/').
String pathBasename(String path) {
  final normalized = normalizePath(path);
  if (normalized == '/') return '/';
  final i = normalized.lastIndexOf('/');
  return i < 0 ? normalized : normalized.substring(i + 1);
}

/// One project card of the 项目 tab: a directory and the sessions opened in
/// it. Grouping is keyed on the sessions' cwd ONLY — the workspace registry
/// just contributes display titles (and empty projects).
class ProjectGroup {
  final String path; // normalized absolute path
  final String title;
  final List<SessionSummary> sessions; // updatedAt descending
  const ProjectGroup({
    required this.path,
    required this.title,
    required this.sessions,
  });

  int get sessionCount => sessions.length;
}

/// Group sessions by their normalized cwd, merged with the workspace
/// registry:
/// - a cwd group whose path matches a workspace takes the workspace title,
///   otherwise the path basename;
/// - workspaces with no sessions appear as empty projects;
/// - sessions without cwd are excluded (see [unknownCwdSessions]).
///
/// Groups are ordered by their latest session's updatedAt descending; empty
/// projects go last, ordered by title.
List<ProjectGroup> groupSessionsByCwd(
  List<SessionSummary> sessions,
  List<Workspace> workspaces,
) {
  final byPath = <String, List<SessionSummary>>{};
  for (final s in sessions) {
    final cwd = s.cwd;
    if (cwd == null || cwd.isEmpty) continue;
    byPath.putIfAbsent(normalizePath(cwd), () => []).add(s);
  }
  final wsTitle = <String, String>{};
  for (final w in workspaces) {
    if (w.path.isEmpty || w.title.isEmpty) continue;
    wsTitle[normalizePath(w.path)] = w.title;
  }
  final groups = <ProjectGroup>[
    for (final e in byPath.entries)
      ProjectGroup(
        path: e.key,
        title: wsTitle[e.key] ?? pathBasename(e.key),
        sessions: [...e.value]
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
      ),
  ];
  // Workspaces without any session appear as empty projects.
  for (final w in workspaces) {
    if (w.path.isEmpty) continue;
    final key = normalizePath(w.path);
    if (byPath.containsKey(key)) continue;
    groups.add(ProjectGroup(
      path: key,
      title: w.title.isEmpty ? pathBasename(key) : w.title,
      sessions: const [],
    ));
  }
  groups.sort((a, b) {
    final la = a.sessions.isEmpty ? -1 : a.sessions.first.updatedAt;
    final lb = b.sessions.isEmpty ? -1 : b.sessions.first.updatedAt;
    if (la != lb) return lb.compareTo(la);
    return a.title.compareTo(b.title);
  });
  return groups;
}

/// Sessions with no recorded cwd: the "未知目录" group (updatedAt desc).
List<SessionSummary> unknownCwdSessions(List<SessionSummary> sessions) =>
    sessions.where((s) => s.cwd == null || s.cwd!.isEmpty).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

/// Flatten sessions (expected updatedAt descending) into a display list with
/// recency group labels ('今天' / '昨天' / '更早') interleaved: entries are
/// String labels or SessionSummary rows.
List<Object> groupSessionsByRecency(List<SessionSummary> sessions,
    {DateTime? now}) {
  final items = <Object>[];
  int? last;
  for (final s in sessions) {
    final b = recencyBucket(s.updatedAt, now: now);
    if (b != last) {
      items.add(recencyBucketLabel(b));
      last = b;
    }
    items.add(s);
  }
  return items;
}

// ---- prompt content assembly ----

/// One image staged in the composer for sending.
class PendingImage {
  final Uint8List bytes;
  final String mediaType;
  final String name;
  const PendingImage({
    required this.bytes,
    required this.mediaType,
    required this.name,
  });

  Map<String, dynamic> toContentBlock() => {
        'type': 'image',
        'mediaType': mediaType,
        'data': base64Encode(bytes),
        'name': name,
      };
}

/// Assemble `session.prompt` content: one text block (when the text is
/// non-empty) followed by image blocks, matching PromptContentPart.
List<Map<String, dynamic>> buildPromptContent(
    String text, List<PendingImage> images) {
  return [
    if (text.trim().isNotEmpty) {'type': 'text', 'text': text.trim()},
    for (final img in images) img.toContentBlock(),
  ];
}
