import 'dart:convert';

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

    test('visibleSessionCount excludes archived', () {
      const w = Workspace(
          workspaceId: 'ws', path: '/p', title: 't', sessionIds: ['a', 'b', 'c']);
      expect(w.visibleSessionCount({'b'}), 2);
      expect(w.visibleSessionCount(const {}), 3);
    });
  });

  group('sessionsForWorkspace', () {
    SessionSummary sess(String id) => SessionSummary(
        sessionId: id, updatedAt: 0, running: false, blank: false);
    const ws = Workspace(
        workspaceId: 'ws', path: '/p', title: 't', sessionIds: ['s1', 's2', 'ghost']);

    test('keeps member sessions in session.list order', () {
      final all = [sess('s2'), sess('other'), sess('s1')];
      final filtered = sessionsForWorkspace(all, ws);
      expect(filtered.map((s) => s.sessionId), ['s2', 's1']);
    });

    test('drops ids not present in session.list and archived sessions', () {
      final all = [sess('s1'), sess('s2')];
      expect(sessionsForWorkspace(all, ws).length, 2);
      final filtered = sessionsForWorkspace(all, ws, {'s2'});
      expect(filtered.map((s) => s.sessionId), ['s1']);
    });
  });
}
