import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/markdown_service.dart';

void main() {
  const markdownService = MarkdownService();
  final fixedDate = DateTime.utc(2026, 11, 1);

  group('MarkdownService Parser & Serializer', () {
    test('parses and serializes the 6 German H1 sections in exact order', () {
      const sampleMarkdown = '''
# Fokus
- [ ] Task A
- [ ] Task B
- [ ] Task C

# Bereit
- [ ] Task D
- [ ] Task E

# Irgendwann
- [ ] Someday Idea 1

# Blockiert
- [ ] Blocked Task 1

# Geplant
- [ ] Backlog Task 1
- [ ] Backlog Task 2

# Erledigt
- [x] 2026-10-30 Completed Task 1
- [x] 2026-10-15 Completed Task 2
''';

      final board = markdownService.parse(sampleMarkdown);

      expect(board.fokus.map((t) => t.title), ['Task A', 'Task B', 'Task C']);
      expect(board.bereit.map((t) => t.title), ['Task D', 'Task E']);
      expect(board.irgendwann.map((t) => t.title), ['Someday Idea 1']);
      expect(board.blockiert.map((t) => t.title), ['Blocked Task 1']);
      expect(board.geplant.map((t) => t.title), [
        'Backlog Task 1',
        'Backlog Task 2',
      ]);
      expect(board.erledigt.length, 2);
      expect(board.erledigt[0].title, 'Completed Task 1');
      expect(board.erledigt[0].isCompleted, isTrue);
      expect(board.erledigt[0].completedAt, DateTime.utc(2026, 10, 30));
      expect(board.erledigt[1].title, 'Completed Task 2');
      expect(board.erledigt[1].completedAt, DateTime.utc(2026, 10, 15));

      final serialized = markdownService.serialize(board);
      expect(serialized, sampleMarkdown);
    });

    test('gracefully handles empty sections and trailing whitespace', () {
      const sparseMarkdown =
          '# Fokus\r\n- [ ] Only Focus   \r\n\r\n# Bereit\r\n\r\n# Geplant\r\n';
      final board = markdownService.parse(sparseMarkdown);

      expect(board.fokus.map((t) => t.title), ['Only Focus']);
      expect(board.bereit, isEmpty);
      expect(board.irgendwann, isEmpty);
      expect(board.blockiert, isEmpty);
      expect(board.geplant, isEmpty);
      expect(board.erledigt, isEmpty);

      final serialized = markdownService.serialize(board);
      expect(serialized, contains('# Fokus\n- [ ] Only Focus'));
      expect(serialized, contains('# Bereit\n\n# Irgendwann'));
    });

    test('validates ISO-8601 dates strictly and rejects impossible calendar rollover dates', () {
      const markdownWithDates = '''
# Erledigt
- [x] 2024-02-29 Valid Leap Day Task
- [x] 2026-02-29 Invalid Non-Leap Day Task
- [x] 2026-02-31 Invalid February Day Task
- [x] 2026-13-45 Invalid Month And Day Task
- [x] 2026-00-00 Zero Month And Day Task
''';

      final board = markdownService.parse(markdownWithDates);

      expect(
        board.erledigt.length,
        equals(5),
        reason: 'All 5 completed task lines must be parsed',
      );
      expect(
        board.erledigt[0].completedAt,
        equals(DateTime.utc(2024, 2, 29)),
        reason: '2024 is a leap year so 2024-02-29 is valid',
      );
      expect(
        board.erledigt[1].completedAt,
        isNull,
        reason: '2026-02-29 must not roll over to 2026-03-01',
      );
      expect(
        board.erledigt[2].completedAt,
        isNull,
        reason: '2026-02-31 must not roll over to 2026-03-03',
      );
      expect(
        board.erledigt[3].completedAt,
        isNull,
        reason: '2026-13-45 must not roll over to 2027-02-14',
      );
      expect(
        board.erledigt[4].completedAt,
        isNull,
        reason: '2026-00-00 must not underflow to 2025-11-30',
      );
      expect(
        TaskItem.formatIsoDate(DateTime.utc(2026, 1, 5)),
        equals('2026-01-05'),
        reason: 'Single-digit month and day must be zero-padded',
      );
      expect(
        TaskItem.tryParseIsoDate('2026-11-01'),
        equals(DateTime.utc(2026, 11, 1)),
        reason: 'Valid ISO date must parse to UTC midnight',
      );
      expect(
        TaskItem.tryParseIsoDate('2026-02-30'),
        isNull,
        reason: 'Out-of-range day for February must return null',
      );
    });
  });

  group('Auto-Pull Cascade & Soft WIP Limits', () {
    test('fills # Fokus (limit 3) from # Bereit and # Bereit (limit 5) from # Geplant', () {
      final board = TaskBoard(
        fokus: [TaskItem(id: 'f1', title: 'F1')],
        bereit: [
          TaskItem(id: 'b1', title: 'B1'),
          TaskItem(id: 'b2', title: 'B2'),
          TaskItem(id: 'b3', title: 'B3'),
        ],
        irgendwann: [TaskItem(id: 'i1', title: 'I1')],
        blockiert: [TaskItem(id: 'bl1', title: 'BL1')],
        geplant: [
          TaskItem(id: 'g1', title: 'G1'),
          TaskItem(id: 'g2', title: 'G2'),
          TaskItem(id: 'g3', title: 'G3'),
          TaskItem(id: 'g4', title: 'G4'),
          TaskItem(id: 'g5', title: 'G5'),
        ],
      );

      final cascaded = board.applyAutoPull();

      // Fokus had 1, pulls B1 and B2 from Bereit -> [F1, B1, B2] (3 items)
      expect(cascaded.fokus.map((t) => t.title), ['F1', 'B1', 'B2']);
      // Bereit had B3 left, pulls G1..G4 from Geplant -> [B3, G1, G2, G3, G4] (5 items)
      expect(cascaded.bereit.map((t) => t.title), [
        'B3',
        'G1',
        'G2',
        'G3',
        'G4',
      ]);
      // Geplant has G5 remaining
      expect(cascaded.geplant.map((t) => t.title), ['G5']);
      // Static tiers untouched
      expect(cascaded.irgendwann.map((t) => t.title), ['I1']);
      expect(cascaded.blockiert.map((t) => t.title), ['BL1']);
    });

    test('manual overfilling of # Fokus or # Bereit never throws or force-moves downward', () {
      final overfilled = TaskBoard(
        fokus: [
          TaskItem(title: 'F1'),
          TaskItem(title: 'F2'),
          TaskItem(title: 'F3'),
          TaskItem(title: 'F4'),
        ],
        bereit: [
          TaskItem(title: 'B1'),
          TaskItem(title: 'B2'),
          TaskItem(title: 'B3'),
          TaskItem(title: 'B4'),
          TaskItem(title: 'B5'),
          TaskItem(title: 'B6'),
        ],
        geplant: [TaskItem(title: 'G1')],
      );

      final result = overfilled.applyAutoPull();
      expect(result.fokus.length, 4);
      expect(result.bereit.length, 6);
      expect(result.geplant.length, 1);
    });

    test('Quick-Add to # Geplant cascades all the way to # Fokus when board has capacity', () {
      final emptyBoard = TaskBoard.empty();
      final afterAdd = emptyBoard.addTask(
        'First Task',
        targetTier: TaskTier.geplant,
        currentDate: fixedDate,
      );

      expect(afterAdd.fokus.map((t) => t.title), ['First Task']);
      expect(afterAdd.bereit, isEmpty);
      expect(afterAdd.geplant, isEmpty);
    });
  });

  group('Completing, Pruning (30-Day GC) & Restoring Tasks', () {
    test('completes active task, stamps YYYY-MM-DD at top of # Erledigt, prunes >30d, and triggers cascade', () {
      final board = TaskBoard(
        fokus: [
          TaskItem(id: 'f1', title: 'Finish spec'),
          TaskItem(id: 'f2', title: 'Task 2'),
          TaskItem(id: 'f3', title: 'Task 3'),
        ],
        bereit: [TaskItem(id: 'b1', title: 'Ready 1')],
        erledigt: [
          // 30 days old on 2026-11-01 -> should be kept (difference == 30)
          TaskItem(
            id: 'e_keep',
            title: '30 Days Ago',
            isCompleted: true,
            completedAt: DateTime.utc(2026, 10, 2),
          ),
          // 31 days old on 2026-11-01 -> should be pruned (difference == 31 > 30)
          TaskItem(
            id: 'e_prune',
            title: '31 Days Ago',
            isCompleted: true,
            completedAt: DateTime.utc(2026, 10, 1),
          ),
        ],
      );

      final afterComplete = board.completeTask('f1', currentDate: fixedDate);

      // Fokus refilled with Ready 1
      expect(afterComplete.fokus.map((t) => t.title), [
        'Task 2',
        'Task 3',
        'Ready 1',
      ]);
      expect(afterComplete.bereit, isEmpty);

      // Erledigt has newly completed task at index 0, kept 30-day task, and pruned 31-day task
      expect(afterComplete.erledigt.map((t) => t.title), [
        'Finish spec',
        '30 Days Ago',
      ]);
      expect(afterComplete.erledigt.first.completedAt, fixedDate);
      expect(
        afterComplete.erledigt.first.toMarkdownLine(inErledigt: true),
        '- [x] 2026-11-01 Finish spec',
      );
    });

    test('restores completed task by stripping [x] and date and moving to selected tier', () {
      final board = TaskBoard(
        erledigt: [
          TaskItem(
            id: 'done1',
            title: 'Restorable Task',
            isCompleted: true,
            completedAt: DateTime.utc(2026, 10, 28),
          ),
        ],
      );

      final restored = board.restoreTask(
        'done1',
        TaskTier.irgendwann,
        currentDate: fixedDate,
      );

      expect(restored.erledigt, isEmpty);
      expect(restored.irgendwann.length, 1);
      expect(restored.irgendwann.first.title, 'Restorable Task');
      expect(restored.irgendwann.first.isCompleted, isFalse);
      expect(restored.irgendwann.first.completedAt, isNull);
      expect(
        restored.irgendwann.first.toMarkdownLine(inErledigt: false),
        '- [ ] Restorable Task',
      );
    });
  });

  group('Anti-Ping-Pong Downgrade & Quick-Block Rules', () {
    test('downgrading from # Fokus to # Bereit pulls top of # Bereit first and appends downgraded task to end of # Bereit', () {
      final board = TaskBoard(
        fokus: [
          TaskItem(id: 'f1', title: 'Fokus 1 (Downgrade Me)'),
          TaskItem(id: 'f2', title: 'Fokus 2'),
          TaskItem(id: 'f3', title: 'Fokus 3'),
        ],
        bereit: [
          TaskItem(id: 'b1', title: 'Bereit 1 (Should Pull Up)'),
          TaskItem(id: 'b2', title: 'Bereit 2'),
        ],
        geplant: [TaskItem(id: 'g1', title: 'Geplant 1')],
      );

      final downgraded = board.downgradeTask('f1', currentDate: fixedDate);

      expect(downgraded.fokus.map((t) => t.title), [
        'Fokus 2',
        'Fokus 3',
        'Bereit 1 (Should Pull Up)',
      ]);
      expect(downgraded.bereit.map((t) => t.title), [
        'Bereit 2',
        'Fokus 1 (Downgrade Me)',
        'Geplant 1',
      ]);
      expect(downgraded.geplant, isEmpty);
    });

    test('downgrading from # Fokus to # Bereit when # Fokus has < 3 tasks does NOT ping-pong back to # Fokus', () {
      final board = TaskBoard(
        fokus: [TaskItem(id: 'f1', title: 'Sole Fokus Task')],
        bereit: [TaskItem(id: 'b1', title: 'Sole Bereit Task')],
      );

      final downgraded = board.downgradeTask('f1', currentDate: fixedDate);

      // b1 moves to Fokus, f1 stays in Bereit without bouncing back into Fokus!
      expect(downgraded.fokus.map((t) => t.title), ['Sole Bereit Task']);
      expect(downgraded.bereit.map((t) => t.title), ['Sole Fokus Task']);
    });

    test('downgrading from # Bereit to # Geplant pulls top of # Geplant first and prevents ping-pong back into # Bereit', () {
      final board = TaskBoard(
        fokus: [
          TaskItem(id: 'f1', title: 'F1'),
          TaskItem(id: 'f2', title: 'F2'),
          TaskItem(id: 'f3', title: 'F3'),
        ],
        bereit: [
          TaskItem(id: 'b1', title: 'Bereit 1 (Downgrade Me)'),
          TaskItem(id: 'b2', title: 'Bereit 2'),
        ],
        geplant: [TaskItem(id: 'g1', title: 'Geplant 1 (Replacement)')],
      );

      final downgraded = board.downgradeTask('b1', currentDate: fixedDate);

      // Even though Bereit only has 2 items (< 5), g1 is pulled into Bereit first
      // and b1 stays in Geplant without being auto-pulled right back!
      expect(downgraded.bereit.map((t) => t.title), [
        'Bereit 2',
        'Geplant 1 (Replacement)',
      ]);
      expect(downgraded.geplant.map((t) => t.title), [
        'Bereit 1 (Downgrade Me)',
      ]);
    });

    test('Quick-Block moves task from # Fokus to # Blockiert and cascades # Bereit/# Geplant upward', () {
      final board = TaskBoard(
        fokus: [
          TaskItem(id: 'f1', title: 'Blocked Focus Task'),
          TaskItem(id: 'f2', title: 'F2'),
          TaskItem(id: 'f3', title: 'F3'),
        ],
        bereit: [TaskItem(id: 'b1', title: 'B1')],
      );

      final blocked = board.blockTask('f1', currentDate: fixedDate);

      expect(blocked.fokus.map((t) => t.title), ['F2', 'F3', 'B1']);
      expect(blocked.bereit, isEmpty);
      expect(blocked.blockiert.map((t) => t.title), ['Blocked Focus Task']);
    });
  });

  group('Riverpod TaskNotifier & Native WebDavRepository', () {
    late HttpServer server;
    String remoteMarkdownStore = '';
    String? lastAuthHeader;
    int putCount = 0;

    setUp(() async {
      remoteMarkdownStore = '''
# Fokus
- [ ] Remote Focus 1
- [ ] Remote Focus 2
- [ ] Remote Focus 3

# Bereit
- [ ] Remote Ready 1

# Irgendwann

# Blockiert

# Geplant
- [ ] Remote Backlog 1

# Erledigt
''';
      lastAuthHeader = null;
      putCount = 0;

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        lastAuthHeader = request.headers.value(HttpHeaders.authorizationHeader);
        if (request.method == 'GET') {
          request.response.statusCode = HttpStatus.ok;
          request.response.write(remoteMarkdownStore);
          await request.response.close();
        } else if (request.method == 'PUT') {
          putCount++;
          remoteMarkdownStore = await utf8.decoder.bind(request).join();
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
        } else {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
        }
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('fetches Markdown via HTTP GET with Basic Auth and syncs mutations via HTTP PUT', () async {
      final config = WebDavConfig(
        serverUrl: 'http://${server.address.host}:${server.port}',
        username: 'stefan',
        password: 'secret-app-password',
        filePath: 'tiertask.md',
      );

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(config),
          ),
          clockProvider.overrideWithValue(() => fixedDate),
        ],
      );
      addTearDown(container.dispose);

      // Wait for initial build (GET + auto-pull normalization + PUT)
      final initialBoard = await container.read(taskNotifierProvider.future);

      final expectedAuth =
          'Basic ${base64Encode(utf8.encode('stefan:secret-app-password'))}';
      expect(lastAuthHeader, expectedAuth);

      // Remote Backlog 1 automatically pulled into # Bereit (since Bereit had 1 < 5)
      expect(initialBoard.fokus.length, 3);
      expect(initialBoard.bereit.map((t) => t.title), [
        'Remote Ready 1',
        'Remote Backlog 1',
      ]);
      expect(initialBoard.geplant, isEmpty);

      // Complete a task in # Fokus through Riverpod TaskNotifier
      final firstFocusId = initialBoard.fokus.first.id;
      await container
          .read(taskNotifierProvider.notifier)
          .completeTask(firstFocusId);

      final updatedBoard = container.read(taskNotifierProvider).value!;
      expect(updatedBoard.fokus.map((t) => t.title), [
        'Remote Focus 2',
        'Remote Focus 3',
        'Remote Ready 1',
      ]);
      expect(updatedBoard.bereit.map((t) => t.title), ['Remote Backlog 1']);
      expect(
        updatedBoard.erledigt.first.toMarkdownLine(inErledigt: true),
        '- [x] 2026-11-01 Remote Focus 1',
      );

      expect(putCount, greaterThanOrEqualTo(2));
      expect(remoteMarkdownStore, contains('- [x] 2026-11-01 Remote Focus 1'));
    });
  });
}
