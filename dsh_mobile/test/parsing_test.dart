import 'dart:convert';
import 'dart:typed_data';

import 'package:dsh_mobile/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionSummary.fromJson', () {
    test('parses core fields', () {
      final s = SessionSummary.fromJson(jsonDecode('''
      {
        "sessionId": "abc123def456",
        "updatedAt": 1755000000000,
        "running": true,
        "blank": false,
        "cwd": "/home/yo/workspace/oh-my-dash",
        "agentPreset": "default"
      }
      ''') as Map<String, dynamic>);
      expect(s.sessionId, 'abc123def456');
      expect(s.updatedAt, 1755000000000);
      expect(s.running, isTrue);
      expect(s.blank, isFalse);
      expect(s.cwd, '/home/yo/workspace/oh-my-dash');
      expect(s.title, isNull);
    });

    test('extracts title from projections values (map with title key)', () {
      final s = SessionSummary.fromJson(jsonDecode('''
      {
        "sessionId": "abc123def456",
        "updatedAt": 1,
        "running": false,
        "blank": false,
        "projections": {
          "asOfSeq": 42,
          "values": {"sessionTitle": {"title": "修复登录 bug"}}
        }
      }
      ''') as Map<String, dynamic>);
      expect(s.title, '修复登录 bug');
    });

    test('extracts title from projections values (plain string)', () {
      final s = SessionSummary.fromJson(jsonDecode('''
      {
        "sessionId": "abc123def456",
        "updatedAt": 1,
        "running": false,
        "blank": false,
        "projections": {"asOfSeq": 1, "values": {"title": "随便聊聊"}}
      }
      ''') as Map<String, dynamic>);
      expect(s.title, '随便聊聊');
    });

    test('displayName: blank session shows 新会话', () {
      final s = SessionSummary(
          sessionId: 'abc123def456',
          updatedAt: 0,
          running: false,
          blank: true);
      expect(s.displayName, '新会话');
    });

    test('displayName: falls back to cwd basename + short id', () {
      final s = SessionSummary(
        sessionId: 'abc123def456',
        updatedAt: 0,
        running: false,
        blank: false,
        cwd: '/home/yo/workspace/oh-my-dash',
      );
      expect(s.displayName, 'oh-my-dash · abc123de');
    });

    test('displayName: no cwd falls back to short id only', () {
      final s = SessionSummary(
          sessionId: 'abc123def456',
          updatedAt: 0,
          running: false,
          blank: false);
      expect(s.displayName, 'abc123de');
    });

    test('tolerates missing optional fields', () {
      final s = SessionSummary.fromJson(
          {'sessionId': 'x', 'updatedAt': 5} );
      expect(s.running, isFalse);
      expect(s.blank, isFalse);
      expect(s.cwd, isNull);
    });
  });

  group('messageFromEvent', () {
    test('renders user/message with source.kind == user', () {
      final m = messageFromEvent(jsonDecode('''
      {
        "type": "user/message",
        "seq": 3,
        "time": 1755000000000,
        "data": {
          "source": {"kind": "user", "rpcId": "r1"},
          "content": [{"type": "text", "text": "你好"}, {"type": "text", "text": "，世界"}]
        }
      }
      ''') as Map<String, dynamic>);
      expect(m, isNotNull);
      expect(m!.isUser, isTrue);
      expect(m.text, '你好，世界');
    });

    test('filters out the runtime context snapshot user/message', () {
      final m = messageFromEvent(jsonDecode('''
      {
        "type": "user/message",
        "seq": 4,
        "time": 1755000000000,
        "data": {
          "source": {"kind": "runtime-context"},
          "content": [{"type": "text", "text": "<context>cwd=/x</context>"}]
        }
      }
      ''') as Map<String, dynamic>);
      expect(m, isNull);
    });

    test('renders assistant/message with text + reasoning blocks', () {
      final m = messageFromEvent(jsonDecode('''
      {
        "type": "assistant/message",
        "seq": 7,
        "time": 1755000000000,
        "data": {
          "message": {
            "content": [
              {"type": "reasoning", "text": "先想想…"},
              {"type": "text", "text": "答案是 4"}
            ]
          }
        }
      }
      ''') as Map<String, dynamic>);
      expect(m, isNotNull);
      expect(m!.isUser, isFalse);
      expect(m.text, '答案是 4');
      expect(m.blocks.length, 2);
      expect(m.blocks[0].isReasoning, isTrue);
      expect(m.blocks[1].isReasoning, isFalse);
    });

    test('ignores unrelated event types', () {
      expect(
          messageFromEvent({'type': 'turn/start', 'data': {'turn': 1}}), isNull);
      expect(messageFromEvent({'type': 'tool/call', 'data': {}}), isNull);
    });
  });

  group('chunkTextFromEvent', () {
    test('extracts direct chunk.text', () {
      final t = chunkTextFromEvent(jsonDecode('''
      {"type": "assistant/chunk", "data": {"chunk": {"type": "delta", "text": "hel"}}}
      ''') as Map<String, dynamic>);
      expect(t, 'hel');
    });

    test('extracts chunk.delta.text', () {
      final t = chunkTextFromEvent(jsonDecode('''
      {"type": "assistant/chunk", "data": {"chunk": {"type": "block-delta", "index": 0, "delta": {"type": "text-delta", "text": "lo"}}}}
      ''') as Map<String, dynamic>);
      expect(t, 'lo');
    });

    test('returns null for block-start and foreign events', () {
      expect(
        chunkTextFromEvent(jsonDecode('''
        {"type": "assistant/chunk", "data": {"chunk": {"type": "block-start", "index": 0, "blockType": "text"}}}
        ''') as Map<String, dynamic>),
        isNull,
      );
      expect(chunkTextFromEvent({'type': 'user/message', 'data': {}}), isNull);
    });
  });

  group('formatTime', () {
    test('epoch 0 renders empty', () => expect(formatTime(0), ''));
    test('today renders HH:mm', () {
      final now = DateTime.now();
      final t = formatTime(now.millisecondsSinceEpoch);
      expect(t, matches(RegExp(r'^\d{2}:\d{2}$')));
    });
    test('other day renders MM-dd HH:mm', () {
      final t = formatTime(DateTime(2020, 1, 2, 3, 4).millisecondsSinceEpoch);
      expect(t, '01-02 03:04');
    });
  });

  group('DirectoryListing.fromJson', () {
    test('parses path/home/crumbs/entries/truncated', () {
      final l = DirectoryListing.fromJson(jsonDecode('''
      {
        "path": "/home/yo/workspace",
        "home": "/home/yo",
        "crumbs": [
          {"name": "/", "path": "/", "hidden": false},
          {"name": "home", "path": "/home", "hidden": false},
          {"name": "yo", "path": "/home/yo", "hidden": false},
          {"name": "workspace", "path": "/home/yo/workspace", "hidden": false}
        ],
        "entries": [
          {"name": ".hidden-dir", "path": "/home/yo/workspace/.hidden-dir", "hidden": true},
          {"name": "oh-my-dash", "path": "/home/yo/workspace/oh-my-dash", "hidden": false}
        ],
        "truncated": false
      }
      ''') as Map<String, dynamic>);
      expect(l.path, '/home/yo/workspace');
      expect(l.home, '/home/yo');
      expect(l.crumbs.length, 4);
      expect(l.crumbs[0].name, '/');
      expect(l.entries.length, 2);
      expect(l.entries[0].hidden, isTrue);
      expect(l.entries[1].hidden, isFalse);
      expect(l.truncated, isFalse);
    });

    test('defaults missing fields defensively', () {
      final l = DirectoryListing.fromJson(const {});
      expect(l.path, '');
      expect(l.home, '');
      expect(l.crumbs, isEmpty);
      expect(l.entries, isEmpty);
      expect(l.truncated, isFalse);
    });

    test('entry hidden defaults to false when absent', () {
      final e = DirectoryEntry.fromJson(const {'name': 'a', 'path': '/a'});
      expect(e.hidden, isFalse);
    });
  });

  group('Workspace.fromJson', () {
    test('parses all fields', () {
      final w = Workspace.fromJson(jsonDecode('''
      {
        "workspaceId": "ws-1",
        "path": "/home/yo/workspace/oh-my-dash",
        "title": "oh-my-dash",
        "sessionIds": ["s1", "s2"],
        "createdAt": "2026-08-01T00:00:00.000Z",
        "updatedAt": "2026-08-21T00:00:00.000Z"
      }
      ''') as Map<String, dynamic>);
      expect(w.workspaceId, 'ws-1');
      expect(w.title, 'oh-my-dash');
      expect(w.sessionIds, ['s1', 's2']);
      expect(w.updatedAt, startsWith('2026-08-21'));
    });

    test('tolerates missing fields', () {
      final w = Workspace.fromJson(const {});
      expect(w.workspaceId, '');
      expect(w.sessionIds, isEmpty);
    });
  });

  group('SessionModels.fromJson', () {
    test('parses current/routable/groups/efforts/failures', () {
      final m = SessionModels.fromJson(jsonDecode('''
      {
        "current": {"provider": "deepseek-official", "model": "deepseek-v4-flash", "reasoningEffort": "low"},
        "routable": true,
        "groups": [
          {
            "id": "deepseek-official",
            "name": "DeepSeek",
            "models": [
              {"id": "deepseek-v4-flash", "name": "V4 Flash"},
              {
                "id": "deepseek-v4-pro",
                "name": "V4 Pro",
                "reasoning": {
                  "efforts": [{"id": "low", "name": "低"}, {"id": "high", "name": "高"}],
                  "defaultEffort": "low"
                }
              }
            ]
          }
        ],
        "failures": [{"id": "broken", "name": "Broken", "message": "boom"}]
      }
      ''') as Map<String, dynamic>);
      expect(m.current.provider, 'deepseek-official');
      expect(m.current.model, 'deepseek-v4-flash');
      expect(m.current.reasoningEffort, 'low');
      expect(m.routable, isTrue);
      expect(m.groups.single.models.length, 2);
      final pro = m.groups.single.models[1];
      expect(pro.efforts.map((e) => e.id), ['low', 'high']);
      expect(pro.efforts[1].name, '高');
      expect(pro.defaultEffort, 'low');
      expect(m.groups.single.models[0].efforts, isEmpty);
      expect(m.failureCount, 1);
    });

    test('tolerates missing fields', () {
      final m = SessionModels.fromJson(const {});
      expect(m.current.provider, '');
      expect(m.routable, isTrue);
      expect(m.groups, isEmpty);
      expect(m.failureCount, 0);
    });

    test('model without reasoning has no efforts and no defaultEffort', () {
      final info = ModelInfo.fromJson(const {'id': 'm1', 'name': 'M1'});
      expect(info.efforts, isEmpty);
      expect(info.defaultEffort, isNull);
    });
  });

  group('normalizePath / pathBasename', () {
    test('strips trailing slashes except root', () {
      expect(normalizePath('/a/b/'), '/a/b');
      expect(normalizePath('/a/b//'), '/a/b');
      expect(normalizePath('/'), '/');
      expect(normalizePath('//'), '/');
      expect(normalizePath('/a'), '/a');
    });

    test('basename', () {
      expect(pathBasename('/home/yo/workspace/oh-my-dash'), 'oh-my-dash');
      expect(pathBasename('/home/yo/workspace/oh-my-dash/'), 'oh-my-dash');
      expect(pathBasename('/'), '/');
    });
  });

  group('groupSessionsByCwd', () {
    SessionSummary sess(String id, int updatedAt, {String? cwd}) =>
        SessionSummary(
            sessionId: id,
            updatedAt: updatedAt,
            running: false,
            blank: false,
            cwd: cwd);
    const ws = Workspace(
        workspaceId: 'ws-1',
        path: '/home/yo/workspace/researchs',
        title: '研究工作区',
        sessionIds: ['whatever']);

    test('groups by normalized cwd, sessions sorted by updatedAt desc', () {
      final all = [
        sess('a1', 100, cwd: '/x/proj'),
        sess('b1', 300, cwd: '/y'),
        sess('a2', 200, cwd: '/x/proj/'), // trailing slash merges
      ];
      final groups = groupSessionsByCwd(all, const []);
      expect(groups.length, 2);
      // Group order: latest session first.
      expect(groups[0].path, '/y');
      expect(groups[1].path, '/x/proj');
      expect(groups[1].sessions.map((s) => s.sessionId), ['a2', 'a1']);
      expect(groups[1].title, 'proj'); // basename fallback
    });

    test('prefers workspace title for matching path', () {
      final all = [sess('r1', 100, cwd: '/home/yo/workspace/researchs/')];
      final groups = groupSessionsByCwd(all, [ws]);
      expect(groups.single.title, '研究工作区');
    });

    test('workspace without sessions shows as empty project', () {
      final groups = groupSessionsByCwd(const [], [ws]);
      expect(groups.single.path, '/home/yo/workspace/researchs');
      expect(groups.single.title, '研究工作区');
      expect(groups.single.sessionCount, 0);
    });

    test('cwd group and workspace on same path merge into one card', () {
      final all = [sess('r1', 100, cwd: '/home/yo/workspace/researchs')];
      final groups = groupSessionsByCwd(all, [ws]);
      expect(groups.length, 1);
      expect(groups.single.sessionCount, 1);
    });

    test('empty projects sort after non-empty, by title', () {
      const wsEmpty = Workspace(
          workspaceId: 'ws-2', path: '/zzz', title: '空项目', sessionIds: []);
      final all = [sess('a', 100, cwd: '/x')];
      final groups = groupSessionsByCwd(all, [wsEmpty]);
      expect(groups.map((g) => g.path), ['/x', '/zzz']);
    });

    test('sessions without cwd are excluded', () {
      final all = [sess('noCwd', 100), sess('withCwd', 50, cwd: '/x')];
      final groups = groupSessionsByCwd(all, const []);
      expect(groups.single.path, '/x');
    });
  });

  group('unknownCwdSessions', () {
    test('collects cwd-missing sessions, updatedAt desc', () {
      SessionSummary sess(String id, int updatedAt, {String? cwd}) =>
          SessionSummary(
              sessionId: id,
              updatedAt: updatedAt,
              running: false,
              blank: false,
              cwd: cwd);
      final all = [
        sess('u1', 100),
        sess('k1', 300, cwd: '/x'),
        sess('u2', 200, cwd: ''),
      ];
      final unknown = unknownCwdSessions(all);
      expect(unknown.map((s) => s.sessionId), ['u2', 'u1']);
    });
  });

  group('buildPromptContent', () {
    PendingImage img(String name) => PendingImage(
        bytes: Uint8List.fromList(const [1, 2, 3]),
        mediaType: 'image/jpeg',
        name: name);

    test('text only', () {
      final content = buildPromptContent('你好', const []);
      expect(content, [
        {'type': 'text', 'text': '你好'},
      ]);
    });

    test('trims text and drops empty text block', () {
      expect(buildPromptContent('   ', const []), isEmpty);
      expect(buildPromptContent('  hi  ', const []).first['text'], 'hi');
    });

    test('text + images: text first, image blocks with base64', () {
      final content = buildPromptContent('看图', [img('a.jpg'), img('b.jpg')]);
      expect(content.length, 3);
      expect(content[0], {'type': 'text', 'text': '看图'});
      expect(content[1]['type'], 'image');
      expect(content[1]['mediaType'], 'image/jpeg');
      expect(content[1]['name'], 'a.jpg');
      expect(content[1]['data'], base64Encode(const [1, 2, 3]));
      expect(content[2]['name'], 'b.jpg');
    });

    test('image only is allowed', () {
      final content = buildPromptContent('', [img('a.jpg')]);
      expect(content.single['type'], 'image');
    });
  });

  group('messageFromEvent image blocks', () {
    test('user message with image renders placeholder block', () {
      final m = messageFromEvent(jsonDecode('''
      {
        "type": "user/message",
        "seq": 3,
        "time": 1755000000000,
        "data": {
          "source": {"kind": "user"},
          "content": [
            {"type": "text", "text": "看这个"},
            {"type": "image", "mediaType": "image/jpeg", "name": "photo.jpg", "data": "…"}
          ]
        }
      }
      ''') as Map<String, dynamic>);
      expect(m, isNotNull);
      expect(m!.blocks.length, 2);
      expect(m.blocks[0].text, '看这个');
      expect(m.blocks[1].isImage, isTrue);
      expect(m.blocks[1].text, 'photo.jpg');
    });

    test('image block without name falls back to 图片', () {
      final m = messageFromEvent(jsonDecode('''
      {
        "type": "user/message",
        "seq": 3,
        "time": 1755000000000,
        "data": {
          "source": {"kind": "user"},
          "content": [{"type": "image", "mediaType": "image/png", "data": "…"}]
        }
      }
      ''') as Map<String, dynamic>);
      expect(m!.blocks.single.isImage, isTrue);
      expect(m.blocks.single.text, '图片');
    });
  });
}
