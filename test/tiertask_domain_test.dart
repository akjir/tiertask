// TierTask
// Copyright (C) 2026  Stefan Stark
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option)
// any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// this program.  If not, see <https://www.gnu.org/licenses/>.

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/l10n/tier_localization_extension.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';
import 'package:tiertask/services/markdown_service.dart';

void main() {
  const markdownService = MarkdownService();
  final fixedDate = DateTime.utc(2026, 11, 1);

  group('MarkdownService Parser & Serializer (Numbered Tiers 1-6)', () {
    test(
      'parses and serializes the 6 numbered H1 sections in exact order 1 to 6',
      () {
        const sampleMarkdown = '''
# [1] Focus
- [ ] Task A
- [ ] Task B
- [ ] Task C

# [2] Ready
- [ ] Task D
- [ ] Task E

# [3] Planned
- [ ] Backlog Task 1
- [ ] Backlog Task 2

# [4] Blocked
- [ ] Blocked Task 1

# [5] Someday
- [ ] Someday Idea 1

# [6] Completed
- [x] 2026-10-30 Completed Task 1
- [x] 2026-10-15 Completed Task 2
''';

        final board = markdownService.parse(sampleMarkdown);

        expect(
          board.focus.map((task) => task.title),
          equals(['Task A', 'Task B', 'Task C']),
          reason: 'Tier 1 must contain Focus tasks',
        );
        expect(
          board.ready.map((task) => task.title),
          equals(['Task D', 'Task E']),
          reason: 'Tier 2 must contain Ready tasks',
        );
        expect(
          board.planned.map((task) => task.title),
          equals(['Backlog Task 1', 'Backlog Task 2']),
          reason: 'Tier 3 must contain Planned tasks',
        );
        expect(
          board.blocked.map((task) => task.title),
          equals(['Blocked Task 1']),
          reason: 'Tier 4 must contain Blocked tasks',
        );
        expect(
          board.someday.map((task) => task.title),
          equals(['Someday Idea 1']),
          reason: 'Tier 5 must contain Someday tasks',
        );
        expect(
          board.completed.length,
          equals(2),
          reason: 'Tier 6 must contain 2 Completed tasks',
        );
        expect(board.completed[0].title, equals('Completed Task 1'));
        expect(board.completed[0].isCompleted, isTrue);
        expect(
          board.completed[0].completedAt,
          equals(DateTime.utc(2026, 10, 30)),
        );
        expect(board.completed[1].title, equals('Completed Task 2'));
        expect(
          board.completed[1].completedAt,
          equals(DateTime.utc(2026, 10, 15)),
        );

        final serialized = markdownService.serialize(board);
        expect(serialized, equals(sampleMarkdown));
      },
    );

    test(
      'ignores heading label text and matches strictly by tier number 1 to 6',
      () {
        const mixedLanguageAndCustomLabels = '''
# [1] Fokus
- [ ] German Focus Task

# (2) Ready
- [ ] Parenthesized Ready Task

# [3] Custom Backlog Title
- [ ] Custom Planned Task

# [4]
- [ ] Label-Free Blocked Task

# (5) Irgendwann / Ideen
- [ ] Someday Idea

# [6] Erledigt
- [x] 2026-10-20 Done Task

# [9] Unknown Tier
- [ ] Ignored Task

# Unnumbered Heading
- [ ] Also Ignored
''';

        final board = markdownService.parse(mixedLanguageAndCustomLabels);

        expect(
          board.focus.map((task) => task.title),
          equals(['German Focus Task']),
          reason: '# [1] Fokus must resolve to Tier 1',
        );
        expect(
          board.ready.map((task) => task.title),
          equals(['Parenthesized Ready Task']),
          reason: '# (2) Ready must resolve to Tier 2',
        );
        expect(
          board.planned.map((task) => task.title),
          equals(['Custom Planned Task']),
          reason: '# [3] with arbitrary label must resolve to Tier 3',
        );
        expect(
          board.blocked.map((task) => task.title),
          equals(['Label-Free Blocked Task']),
          reason: '# [4] without label must resolve to Tier 4',
        );
        expect(
          board.someday.map((task) => task.title),
          equals(['Someday Idea']),
          reason: '# (5) with German label must resolve to Tier 5',
        );
        expect(
          board.completed.map((task) => task.title),
          equals(['Done Task']),
          reason: '# [6] Erledigt must resolve to Tier 6',
        );
      },
    );

    test('creates missing tiers automatically on serialization and supports localized labels', () {
      const sparseMarkdown = '# [1] Fokus\r\n- [ ] Only Focus   \r\n';
      final board = markdownService.parse(sparseMarkdown);

      expect(board.focus.map((task) => task.title), equals(['Only Focus']));
      expect(board.ready, isEmpty);
      expect(board.planned, isEmpty);
      expect(board.blocked, isEmpty);
      expect(board.someday, isEmpty);
      expect(board.completed, isEmpty);

      final englishSerialized = markdownService.serialize(board);
      expect(englishSerialized, contains('# [1] Focus\n- [ ] Only Focus'));
      expect(
        englishSerialized,
        contains(
          '# [2] Ready\n\n# [3] Planned\n\n# [4] Blocked\n\n# [5] Someday\n\n# [6] Completed',
        ),
        reason: 'All missing tiers 2-6 must be created in English by default',
      );

      final germanLocalizations = lookupAppLocalizations(const Locale('de'));
      final germanSerialized = markdownService.serialize(
        board,
        tierLabelBuilder: germanLocalizations.tierName,
      );
      expect(germanSerialized, contains('# [1] Fokus\n- [ ] Only Focus'));
      expect(
        germanSerialized,
        contains(
          '# [2] Bereit\n\n# [3] Geplant\n\n# [4] Blockiert\n\n# [5] Irgendwann\n\n# [6] Erledigt',
        ),
        reason: 'All missing tiers 2-6 must be serialized with German labels when requested',
      );
    });

    test('validates ISO-8601 dates strictly and rejects impossible calendar rollover dates', () {
      const markdownWithDates = '''
# [6] Completed
- [x] 2024-02-29 Valid Leap Day Task
- [x] 2026-02-29 Invalid Non-Leap Day Task
- [x] 2026-02-31 Invalid February Day Task
- [x] 2026-13-45 Invalid Month And Day Task
- [x] 2026-00-00 Zero Month And Day Task
''';

      final board = markdownService.parse(markdownWithDates);

      expect(
        board.completed.length,
        equals(5),
        reason: 'All 5 completed task lines must be parsed',
      );
      expect(
        board.completed[0].completedAt,
        equals(DateTime.utc(2024, 2, 29)),
        reason: '2024 is a leap year so 2024-02-29 is valid',
      );
      expect(
        board.completed[1].completedAt,
        isNull,
        reason: '2026-02-29 must not roll over to 2026-03-01',
      );
      expect(
        board.completed[2].completedAt,
        isNull,
        reason: '2026-02-31 must not roll over to 2026-03-03',
      );
      expect(
        board.completed[3].completedAt,
        isNull,
        reason: '2026-13-45 must not roll over to 2027-02-14',
      );
      expect(
        board.completed[4].completedAt,
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

  group('AppLanguage & Locale Resolution', () {
    test(
      'resolves English as default and honors German or System locale settings',
      () {
        expect(
          AppLanguage.system.resolveLocale(const Locale('de', 'DE')),
          equals(const Locale('de')),
          reason: 'System mode on German OS must resolve to de',
        );
        expect(
          AppLanguage.system.resolveLocale(const Locale('en', 'US')),
          equals(const Locale('en')),
          reason: 'System mode on English OS must resolve to en',
        );
        expect(
          AppLanguage.system.resolveLocale(const Locale('fr', 'FR')),
          equals(const Locale('en')),
          reason: 'System mode on unsupported OS language must fall back to English default',
        );
        expect(
          AppLanguage.system.resolveLocale(null),
          equals(const Locale('en')),
          reason:
              'System mode with null locale must fall back to English default',
        );
        expect(
          AppLanguage.english.resolveLocale(const Locale('de', 'DE')),
          equals(const Locale('en')),
          reason: 'Explicit English setting must override German OS locale',
        );
        expect(
          AppLanguage.german.resolveLocale(const Locale('en', 'US')),
          equals(const Locale('de')),
          reason: 'Explicit German setting must override English OS locale',
        );
        expect(
          AppLanguage.fromCode('de'),
          equals(AppLanguage.german),
          reason: 'Code de must map to AppLanguage.german',
        );
        expect(
          AppLanguage.fromCode('en'),
          equals(AppLanguage.english),
          reason: 'Code en must map to AppLanguage.english',
        );
        expect(
          AppLanguage.fromCode('unknown'),
          equals(AppLanguage.system),
          reason: 'Unknown code must default to AppLanguage.system',
        );
      },
    );
  });

  group('Auto-Pull Cascade & Soft WIP Limits', () {
    test('fills # [1] Focus (limit 3) from # [2] Ready and # [2] Ready (limit 5) from # [3] Planned', () {
      final board = TaskBoard(
        focus: [TaskItem(id: 'f1', title: 'F1')],
        ready: [
          TaskItem(id: 'b1', title: 'B1'),
          TaskItem(id: 'b2', title: 'B2'),
          TaskItem(id: 'b3', title: 'B3'),
        ],
        planned: [
          TaskItem(id: 'g1', title: 'G1'),
          TaskItem(id: 'g2', title: 'G2'),
          TaskItem(id: 'g3', title: 'G3'),
          TaskItem(id: 'g4', title: 'G4'),
          TaskItem(id: 'g5', title: 'G5'),
        ],
        blocked: [TaskItem(id: 'bl1', title: 'BL1')],
        someday: [TaskItem(id: 'i1', title: 'I1')],
      );

      final cascaded = board.applyAutoPull();

      expect(
        cascaded.focus.map((task) => task.title),
        equals(['F1', 'B1', 'B2']),
      );
      expect(
        cascaded.ready.map((task) => task.title),
        equals(['B3', 'G1', 'G2', 'G3', 'G4']),
      );
      expect(cascaded.planned.map((task) => task.title), equals(['G5']));
      expect(cascaded.blocked.map((task) => task.title), equals(['BL1']));
      expect(cascaded.someday.map((task) => task.title), equals(['I1']));
    });

    test('manual overfilling of # [1] Focus or # [2] Ready never throws or force-moves downward', () {
      final overfilled = TaskBoard(
        focus: [
          TaskItem(title: 'F1'),
          TaskItem(title: 'F2'),
          TaskItem(title: 'F3'),
          TaskItem(title: 'F4'),
        ],
        ready: [
          TaskItem(title: 'B1'),
          TaskItem(title: 'B2'),
          TaskItem(title: 'B3'),
          TaskItem(title: 'B4'),
          TaskItem(title: 'B5'),
          TaskItem(title: 'B6'),
        ],
        planned: [TaskItem(title: 'G1')],
      );

      final result = overfilled.applyAutoPull();
      expect(result.focus.length, equals(4));
      expect(result.ready.length, equals(6));
      expect(result.planned.length, equals(1));
    });

    test('Quick-Add to # [3] Planned cascades all the way to # [1] Focus when board has capacity', () {
      final emptyBoard = TaskBoard.empty();
      final afterAdd = emptyBoard.addTask(
        'First Task',
        targetTier: TaskTier.planned,
        currentDate: fixedDate,
      );

      expect(afterAdd.focus.map((task) => task.title), equals(['First Task']));
      expect(afterAdd.ready, isEmpty);
      expect(afterAdd.planned, isEmpty);
    });

    test('adds priority task directly to Focus and preserves subtasks across board and Markdown round-trip', () {
      final board = TaskBoard(
        focus: [
          TaskItem(id: 'f1', title: 'F1'),
          TaskItem(id: 'f2', title: 'F2'),
          TaskItem(id: 'f3', title: 'F3'),
        ],
      );

      final updated = board.addTask(
        'Urgent Hotfix',
        targetTier: TaskTier.focus,
        isPriority: true,
        subtasks: const [
          SubtaskItem(title: 'Patch vulnerability'),
          SubtaskItem(title: 'Verify regression tests', isCompleted: true),
        ],
        currentDate: fixedDate,
      );

      expect(updated.focus.length, equals(4));
      final added = updated.focus.last;
      expect(added.title, equals('Urgent Hotfix'));
      expect(added.isPriority, isTrue);
      expect(added.subtasks.length, equals(2));
      expect(added.subtasks[0].title, equals('Patch vulnerability'));
      expect(added.subtasks[0].isCompleted, isFalse);
      expect(added.subtasks[1].title, equals('Verify regression tests'));
      expect(added.subtasks[1].isCompleted, isTrue);

      final serialized = markdownService.serialize(updated);
      expect(serialized, contains('- [ ] Urgent Hotfix'));
      expect(serialized, contains('  - [ ] Patch vulnerability'));
      expect(serialized, contains('  - [x] Verify regression tests'));

      final reparsed = markdownService.parse(serialized);
      expect(reparsed.focus.last.title, equals('Urgent Hotfix'));
      expect(
        reparsed.focus.last.subtasks.map((subtask) => subtask.title),
        equals(['Patch vulnerability', 'Verify regression tests']),
      );
      expect(reparsed.focus.last.subtasks[0].isCompleted, isFalse);
      expect(reparsed.focus.last.subtasks[1].isCompleted, isTrue);
    });
  });

  group('Completing, Pruning (30-Day GC) & Restoring Tasks', () {
    test('completes active task, stamps YYYY-MM-DD at top of # [6] Completed, prunes >30d, and triggers cascade', () {
      final board = TaskBoard(
        focus: [
          TaskItem(id: 'f1', title: 'Finish spec'),
          TaskItem(id: 'f2', title: 'Task 2'),
          TaskItem(id: 'f3', title: 'Task 3'),
        ],
        ready: [TaskItem(id: 'b1', title: 'Ready 1')],
        completed: [
          TaskItem(
            id: 'e_keep',
            title: '30 Days Ago',
            isCompleted: true,
            completedAt: DateTime.utc(2026, 10, 2),
          ),
          TaskItem(
            id: 'e_prune',
            title: '31 Days Ago',
            isCompleted: true,
            completedAt: DateTime.utc(2026, 10, 1),
          ),
        ],
      );

      final afterComplete = board.completeTask('f1', currentDate: fixedDate);

      expect(
        afterComplete.focus.map((task) => task.title),
        equals(['Task 2', 'Task 3', 'Ready 1']),
      );
      expect(afterComplete.ready, isEmpty);

      expect(
        afterComplete.completed.map((task) => task.title),
        equals(['Finish spec', '30 Days Ago']),
      );
      expect(afterComplete.completed.first.completedAt, equals(fixedDate));
      expect(
        afterComplete.completed.first.toMarkdownLine(inCompleted: true),
        equals('- [x] 2026-11-01 Finish spec'),
      );
    });

    test('restores completed task by stripping [x] and date and moving to selected tier', () {
      final board = TaskBoard(
        completed: [
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
        TaskTier.someday,
        currentDate: fixedDate,
      );

      expect(restored.completed, isEmpty);
      expect(restored.someday.length, equals(1));
      expect(restored.someday.first.title, equals('Restorable Task'));
      expect(restored.someday.first.isCompleted, isFalse);
      expect(restored.someday.first.completedAt, isNull);
      expect(
        restored.someday.first.toMarkdownLine(inCompleted: false),
        equals('- [ ] Restorable Task'),
      );
    });
  });

  group('Anti-Ping-Pong Downgrade & Quick-Block Rules', () {
    test('downgrading from # [1] Focus to # [2] Ready pulls top of # [2] Ready first and appends downgraded task to end of # [2] Ready', () {
      final board = TaskBoard(
        focus: [
          TaskItem(id: 'f1', title: 'Focus 1 (Downgrade Me)'),
          TaskItem(id: 'f2', title: 'Focus 2'),
          TaskItem(id: 'f3', title: 'Focus 3'),
        ],
        ready: [
          TaskItem(id: 'b1', title: 'Ready 1 (Should Pull Up)'),
          TaskItem(id: 'b2', title: 'Ready 2'),
        ],
        planned: [TaskItem(id: 'g1', title: 'Planned 1')],
      );

      final downgraded = board.downgradeTask('f1', currentDate: fixedDate);

      expect(
        downgraded.focus.map((task) => task.title),
        equals(['Focus 2', 'Focus 3', 'Ready 1 (Should Pull Up)']),
      );
      expect(
        downgraded.ready.map((task) => task.title),
        equals(['Ready 2', 'Focus 1 (Downgrade Me)', 'Planned 1']),
      );
      expect(downgraded.planned, isEmpty);
    });

    test('downgrading from # [1] Focus to # [2] Ready when # [1] Focus has < 3 tasks does NOT ping-pong back to # [1] Focus', () {
      final board = TaskBoard(
        focus: [TaskItem(id: 'f1', title: 'Sole Focus Task')],
        ready: [TaskItem(id: 'b1', title: 'Sole Ready Task')],
      );

      final downgraded = board.downgradeTask('f1', currentDate: fixedDate);

      expect(
        downgraded.focus.map((task) => task.title),
        equals(['Sole Ready Task']),
      );
      expect(
        downgraded.ready.map((task) => task.title),
        equals(['Sole Focus Task']),
      );
    });

    test('downgrading from # [2] Ready to # [3] Planned pulls top of # [3] Planned first and prevents ping-pong back into # [2] Ready', () {
      final board = TaskBoard(
        focus: [
          TaskItem(id: 'f1', title: 'F1'),
          TaskItem(id: 'f2', title: 'F2'),
          TaskItem(id: 'f3', title: 'F3'),
        ],
        ready: [
          TaskItem(id: 'b1', title: 'Ready 1 (Downgrade Me)'),
          TaskItem(id: 'b2', title: 'Ready 2'),
        ],
        planned: [TaskItem(id: 'g1', title: 'Planned 1 (Replacement)')],
      );

      final downgraded = board.downgradeTask('b1', currentDate: fixedDate);

      expect(
        downgraded.ready.map((task) => task.title),
        equals(['Ready 2', 'Planned 1 (Replacement)']),
      );
      expect(
        downgraded.planned.map((task) => task.title),
        equals(['Ready 1 (Downgrade Me)']),
      );
    });

    test('Quick-Block moves task from # [1] Focus to # [4] Blocked and cascades # [2] Ready / # [3] Planned upward', () {
      final board = TaskBoard(
        focus: [
          TaskItem(id: 'f1', title: 'Blocked Focus Task'),
          TaskItem(id: 'f2', title: 'F2'),
          TaskItem(id: 'f3', title: 'F3'),
        ],
        ready: [TaskItem(id: 'b1', title: 'B1')],
      );

      final blocked = board.blockTask('f1', currentDate: fixedDate);

      expect(
        blocked.focus.map((task) => task.title),
        equals(['F2', 'F3', 'B1']),
      );
      expect(blocked.ready, isEmpty);
      expect(
        blocked.blocked.map((task) => task.title),
        equals(['Blocked Focus Task']),
      );
    });
  });

  group('Riverpod TaskNotifier & Native WebDavRepository', () {
    late HttpServer server;
    String remoteMarkdownStore = '';
    String? lastAuthHeader;
    int putCount = 0;

    setUp(() async {
      remoteMarkdownStore = '''
# [1] Fokus
- [ ] Remote Focus 1
- [ ] Remote Focus 2
- [ ] Remote Focus 3

# [2] Bereit
- [ ] Remote Ready 1

# [3] Geplant
- [ ] Remote Backlog 1
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

    test('fetches Markdown via HTTP GET with Basic Auth, creates missing tiers, and syncs mutations via HTTP PUT', () async {
      final config = WebDavConfig(
        serverUrl: 'http://${server.address.host}:${server.port}',
        username: 'stefan',
        password: 'secret-app-password',
        filePath: 'tiertask.md',
        language: AppLanguage.english,
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

      final initialBoard = await container.read(taskNotifierProvider.future);

      final expectedAuth =
          'Basic ${base64Encode(utf8.encode('stefan:secret-app-password'))}';
      expect(lastAuthHeader, equals(expectedAuth));

      expect(initialBoard.focus.length, equals(3));
      expect(
        initialBoard.ready.map((task) => task.title),
        equals(['Remote Ready 1', 'Remote Backlog 1']),
      );
      expect(initialBoard.planned, isEmpty);

      final firstFocusId = initialBoard.focus.first.id;
      await container
          .read(taskNotifierProvider.notifier)
          .completeTask(firstFocusId);

      final updatedBoard = container.read(taskNotifierProvider).value!;
      expect(
        updatedBoard.focus.map((task) => task.title),
        equals(['Remote Focus 2', 'Remote Focus 3', 'Remote Ready 1']),
      );
      expect(
        updatedBoard.ready.map((task) => task.title),
        equals(['Remote Backlog 1']),
      );
      expect(
        updatedBoard.completed.first.toMarkdownLine(inCompleted: true),
        equals('- [x] 2026-11-01 Remote Focus 1'),
      );

      expect(putCount, greaterThanOrEqualTo(2));
      expect(remoteMarkdownStore, contains('# [1] Focus'));
      expect(remoteMarkdownStore, contains('# [4] Blocked'));
      expect(remoteMarkdownStore, contains('# [5] Someday'));
      expect(remoteMarkdownStore, contains('# [6] Completed'));
      expect(remoteMarkdownStore, contains('- [x] 2026-11-01 Remote Focus 1'));
    });
  });

  group('Localization ARB Metadata & Key Parity', () {
    test('every message key in app_en.arb defines @key metadata with a non-empty description and matches app_de.arb keys', () {
      final enRaw = File('lib/l10n/app_en.arb').readAsStringSync();
      final deRaw = File('lib/l10n/app_de.arb').readAsStringSync();
      final enDecoded = jsonDecode(enRaw);
      final deDecoded = jsonDecode(deRaw);

      expect(enDecoded, isA<Map<String, Object?>>());
      expect(deDecoded, isA<Map<String, Object?>>());
      if (enDecoded is! Map<String, Object?> ||
          deDecoded is! Map<String, Object?>) {
        return;
      }

      final enMessageKeys = <String>[
        for (final key in enDecoded.keys)
          if (!key.startsWith('@')) key,
      ];
      final deMessageKeys = <String>[
        for (final key in deDecoded.keys)
          if (!key.startsWith('@')) key,
      ];

      expect(
        enMessageKeys,
        contains('moveTaskTitle'),
        reason: 'Template ARB must include moveTaskTitle',
      );
      expect(
        deMessageKeys,
        equals(enMessageKeys),
        reason: 'German ARB must define the exact same message keys in order',
      );

      for (final key in enMessageKeys) {
        _expectArbKeyMetadata(enDecoded, key);
      }
    });

    test('Linux, Windows, and Android platform runners and manifests display TierTask as the taskbar and window title', () {
      final linuxRunner = File('linux/runner/my_application.cc')
          .readAsStringSync();
      expect(
        linuxRunner,
        contains('gtk_header_bar_set_title(header_bar, "TierTask");'),
        reason: 'Linux GTK header bar title must be TierTask',
      );
      expect(
        linuxRunner,
        contains('gtk_window_set_title(window, "TierTask");'),
        reason: 'Linux GTK window title must be TierTask',
      );
      expect(
        linuxRunner,
        contains('g_set_application_name("TierTask");'),
        reason:
            'Linux GLib application name must be TierTask for taskbar display',
      );
      expect(
        linuxRunner,
        isNot(contains('"tiertask"')),
        reason: 'Linux runner must not use lowercase tiertask for window or header titles',
      );

      final windowsMain = File('windows/runner/main.cpp').readAsStringSync();
      expect(
        windowsMain,
        contains('window.Create(L"TierTask", origin, size)'),
        reason: 'Windows Win32 window title must be TierTask',
      );
      expect(
        windowsMain,
        isNot(contains('L"tiertask"')),
        reason:
            'Windows main.cpp must not use lowercase tiertask as window title',
      );

      final windowsResource = File('windows/runner/Runner.rc')
          .readAsStringSync();
      expect(
        windowsResource,
        contains('VALUE "FileDescription", "TierTask" "\\0"'),
        reason: 'Windows Runner.rc FileDescription must be TierTask for taskbar and Task Manager',
      );
      expect(
        windowsResource,
        contains('VALUE "InternalName", "TierTask" "\\0"'),
        reason: 'Windows Runner.rc InternalName must be TierTask',
      );
      expect(
        windowsResource,
        contains('VALUE "ProductName", "TierTask" "\\0"'),
        reason: 'Windows Runner.rc ProductName must be TierTask',
      );

      final androidManifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(
        androidManifest,
        contains('android:label="TierTask"'),
        reason: 'Android manifest label must be TierTask',
      );
      expect(
        androidManifest,
        isNot(contains('android:label="tiertask"')),
        reason: 'Android manifest must not use lowercase tiertask as label',
      );
    });
  });

  group('AppThemeMode, StorageMode & WebDavConfig Resolution', () {
    test('resolves AppThemeMode and StorageMode codes with system and local defaults', () {
      expect(
        AppThemeMode.fromCode('light'),
        equals(AppThemeMode.light),
        reason: 'Code light must resolve to AppThemeMode.light',
      );
      expect(
        AppThemeMode.fromCode('DARK'),
        equals(AppThemeMode.dark),
        reason: 'Case-insensitive dark code must resolve to AppThemeMode.dark',
      );
      expect(
        AppThemeMode.fromCode('system'),
        equals(AppThemeMode.system),
        reason: 'Code system must resolve to AppThemeMode.system',
      );
      expect(
        AppThemeMode.fromCode('invalid'),
        equals(AppThemeMode.system),
        reason: 'Unknown theme code must default to AppThemeMode.system',
      );
      expect(
        AppThemeMode.fromCode(null),
        equals(AppThemeMode.system),
        reason: 'Null theme code must default to AppThemeMode.system',
      );

      expect(
        StorageMode.fromCode('local'),
        equals(StorageMode.local),
        reason: 'Code local must resolve to StorageMode.local',
      );
      expect(
        StorageMode.fromCode('webdav'),
        equals(StorageMode.webdav),
        reason: 'Code webdav must resolve to StorageMode.webdav',
      );
      expect(
        StorageMode.fromCode('BOTH'),
        equals(StorageMode.both),
        reason: 'Case-insensitive both code must resolve to StorageMode.both',
      );
      expect(
        StorageMode.fromCode(null),
        equals(StorageMode.local),
        reason: 'Null storage mode code must default to StorageMode.local',
      );

      expect(StorageMode.local.usesLocal, isTrue);
      expect(StorageMode.local.usesWebDav, isFalse);
      expect(StorageMode.webdav.usesLocal, isFalse);
      expect(StorageMode.webdav.usesWebDav, isTrue);
      expect(StorageMode.both.usesLocal, isTrue);
      expect(StorageMode.both.usesWebDav, isTrue);

      const defaultConfig = WebDavConfig();
      expect(
        defaultConfig.themeMode,
        equals(AppThemeMode.system),
        reason: 'Default themeMode must be AppThemeMode.system',
      );
      expect(
        defaultConfig.storageMode,
        equals(StorageMode.local),
        reason: 'Default storageMode must be StorageMode.local',
      );
      expect(
        defaultConfig.localFilePath,
        equals('tiertask.md'),
        reason: 'Default localFilePath must be tiertask.md',
      );
      expect(
        defaultConfig.showOpenTaskCount,
        isFalse,
        reason: 'Default showOpenTaskCount must be false (off)',
      );
      expect(
        defaultConfig.copyWith(showOpenTaskCount: true).showOpenTaskCount,
        isTrue,
        reason: 'copyWith(showOpenTaskCount: true) must enable task counts',
      );
      expect(
        defaultConfig.isConfigured,
        isTrue,
        reason: 'Local mode with non-empty localFilePath is configured',
      );

      final unconfiguredBoth = defaultConfig.copyWith(
        storageMode: StorageMode.both,
      );
      expect(
        unconfiguredBoth.isConfigured,
        isFalse,
        reason: 'Both mode requires both local file and WebDAV credentials',
      );
    });
  });

  group('LocalFileRepository & StorageMode Synchronization', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tiertask_local_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('reads and writes local Markdown files and rejects traversal or oversized payloads', () async {
      const config = WebDavConfig(
        localFilePath: 'custom_tasks.md',
        storageMode: StorageMode.local,
      );
      final repository = LocalFileRepository(
        config: config,
        baseDirectoryPath: tempDir.path,
        maxFileBytes: 256,
      );

      expect(
        await repository.loadMarkdown(),
        isEmpty,
        reason: 'Missing local Markdown file must return empty string',
      );

      await repository.saveMarkdown('# [1] Focus\n- [ ] Local Task\n');
      final loaded = await repository.loadMarkdown();
      expect(loaded, contains('- [ ] Local Task'));

      final traversalRepo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: '../escape.md'),
        baseDirectoryPath: tempDir.path,
      );
      await expectLater(
        traversalRepo.loadMarkdown,
        throwsA(isA<LocalFileException>()),
        reason: 'Relative parent traversal (..) must be rejected',
      );

      final nullByteRepo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'bad\x00file.md'),
        baseDirectoryPath: tempDir.path,
      );
      await expectLater(
        nullByteRepo.saveMarkdown('content'),
        throwsA(isA<LocalFileException>()),
        reason: 'Null bytes in local file name must be rejected',
      );

      await expectLater(
        repository.saveMarkdown('A' * 300),
        throwsA(isA<LocalFileException>()),
        reason: 'Content exceeding maxFileBytes must be rejected before write',
      );
    });

    test('synchronizes tasks in StorageMode.local and StorageMode.both', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      var remoteMarkdown = '';
      var remotePutCount = 0;
      server.listen((HttpRequest request) async {
        if (request.method == 'GET') {
          request.response.statusCode = remoteMarkdown.isEmpty
              ? HttpStatus.notFound
              : HttpStatus.ok;
          request.response.write(remoteMarkdown);
          await request.response.close();
        } else if (request.method == 'PUT') {
          remotePutCount++;
          remoteMarkdown = await utf8.decoder.bind(request).join();
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
        }
      });

      const localOnlyConfig = WebDavConfig(
        localFilePath: 'local_only.md',
        storageMode: StorageMode.local,
        language: AppLanguage.english,
      );

      final localContainer = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(localOnlyConfig),
          ),
          localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
          clockProvider.overrideWithValue(() => fixedDate),
        ],
      );
      addTearDown(localContainer.dispose);

      await localContainer.read(taskNotifierProvider.future);
      await localContainer
          .read(taskNotifierProvider.notifier)
          .addTask('Local Mode Task');

      final localFile = File('${tempDir.path}/local_only.md');
      expect(
        await localFile.exists(),
        isTrue,
        reason: 'Local mode must persist local_only.md on disk',
      );
      expect(await localFile.readAsString(), contains('- [ ] Local Mode Task'));
      expect(
        remotePutCount,
        equals(0),
        reason: 'Local mode must not send WebDAV PUT requests',
      );

      final bothConfig = WebDavConfig(
        serverUrl: 'http://${server.address.host}:${server.port}',
        username: 'stefan',
        password: 'secret',
        filePath: 'remote_both.md',
        localFilePath: 'both_mode.md',
        storageMode: StorageMode.both,
        language: AppLanguage.english,
      );

      final bothContainer = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(bothConfig),
          ),
          localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
          clockProvider.overrideWithValue(() => fixedDate),
        ],
      );
      addTearDown(bothContainer.dispose);

      await bothContainer.read(taskNotifierProvider.future);
      await bothContainer
          .read(taskNotifierProvider.notifier)
          .addTask('Dual Synced Task');

      final bothFile = File('${tempDir.path}/both_mode.md');
      expect(
        await bothFile.exists(),
        isTrue,
        reason: 'Both mode must persist both_mode.md locally',
      );
      expect(await bothFile.readAsString(), contains('- [ ] Dual Synced Task'));
      expect(
        remoteMarkdown,
        contains('- [ ] Dual Synced Task'),
        reason: 'Both mode must also push Markdown to WebDAV',
      );
      expect(remotePutCount, greaterThanOrEqualTo(1));

      await expectLater(
        localContainer
            .read(taskNotifierProvider.notifier)
            .testConnectionAndSync(localOnlyConfig),
        throwsA(isA<WebDavException>()),
        reason: 'testConnectionAndSync must reject StorageMode.local without WebDAV',
      );

      await expectLater(
        localContainer
            .read(taskNotifierProvider.notifier)
            .testConnectionAndSync(
              const WebDavConfig(
                storageMode: StorageMode.webdav,
                language: AppLanguage.english,
              ),
            ),
        throwsA(isA<WebDavException>()),
        reason:
            'testConnectionAndSync must reject unconfigured StorageMode.webdav',
      );
    });
  });
}

/// Verifies that [arbMap] defines an `@<key>` metadata map with a non-empty description.
void _expectArbKeyMetadata(Map<String, Object?> arbMap, String key) {
  final metadataKey = '@$key';
  final metadata = arbMap[metadataKey];
  expect(
    metadata,
    isA<Map<String, Object?>>(),
    reason:
        'The message with key "$key" must have $metadataKey metadata defined',
  );
  if (metadata is! Map<String, Object?>) {
    return;
  }

  final description = metadata['description'];
  expect(
    description,
    isA<String>(),
    reason: 'Metadata $metadataKey must define a description string',
  );
  if (description is String) {
    expect(
      description.trim(),
      isNotEmpty,
      reason: 'Metadata $metadataKey description must not be empty',
    );
  }
}
