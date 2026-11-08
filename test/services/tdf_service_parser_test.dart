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

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';
import 'package:tiertask/services/tdf_service.dart';

void main() {
  const tdfService = TdfService();
  final fixedDate = DateTime.utc(2026, 11, 1, 12, 0);

  group('TdfService 0.5.1 Lexical Scanner, Parser & Canonical Serializer', () {
    test('parses canonical TDF 0.5.1 document from TDF_SPEC.md Section 9 and derives all 6 tiers', () {
      const canonicalTdf = '''
# ==========================================
# TierTask Data Format (TDF) Example Document
# ==========================================

tdf 0.5.1

deleted {
    generation 4
    task 6uCk8N0aB1 2026-11-01 12:00:00
    label 1rQv7S0cD2 2026-11-02 09:00:00
}

queue {
    modified 2026-11-01 19:30:00
    task 8jKaCdOkD2
    task 5vWx9ZOk91
    task 3nQp7ROkB8
}

label 4x9p2mOkD2 {
    name     "Home & Garden"
    modified 2026-11-01 08:00

    condition {
        day      sat sun
        time     08:00 20:00
        location 50.9787 11.0328 150
    }
}

label 9kLm2P0aBc {
    name     "IT & Servers"
    color    "#2196F3"
    modified 2026-11-01 08:00

    condition {
        day  mon tue wed thu fri
        time 08:00 12:00
        time 14:00 18:00
    }
}

task 8jKaCdOkD2 priority {
    name      "Mow the lawn"
    note      "Check fuel level before starting"
    created   2026-11-01 19:30
    modified  2026-11-01 19:30
    labels    4x9p2mOkD2
    blocked   3nQp7ROkB8
    suspended 2026-11-04 23:00:00
    condition time 09:00 18:00

    subtasks auto-finish {
        step false "Get lawnmower from the shed"
        step true  "Empty grass catcher bag"
    }
}

task 3nQp7ROkB8 {
    name      "Order replacement lawnmower blades online"
    created   2026-11-01 18:00
    modified  2026-11-01 18:00
    labels    4x9p2mOkD2
    link      "Portal Login" "https://example.com/portal#login"
    link      "Local Folder" "file:///home/user/documents/tax2026"
    condition any
}

task 5vWx9ZOk91 {
    name     "Clean dust filters on home NAS server"
    created  2026-11-01 10:00
    modified 2026-11-01 10:00
    labels   4x9p2mOkD2 9kLm2P0aBc
    repeat   30 days
}

task 2bDf6HOkA4 {
    name     "Design 3D-printed enclosure for backup NAS"
    created  2026-11-01 12:00
    modified 2026-11-01 12:00
    labels   9kLm2P0aBc
}

task 7mPr4T09xY {
    name        "Mount winter tires"
    created     2026-10-20 14:00
    finished    2026-10-29 16:45
    modified    2026-10-29 16:45
    completions 1
    labels      4x9p2mOkD2
}
''';

      final board = tdfService.parse(canonicalTdf, evaluationTime: fixedDate);

      expect(board.deletedBlock.generation, equals(4));
      expect(board.deletedBlock.tasks.single.taskId, equals('6uCk8N0aB1'));
      expect(
        board.deletedBlock.tasks.single.deletedAt,
        equals(DateTime.utc(2026, 11, 1, 12, 0, 0)),
      );
      expect(board.deletedBlock.labels.single.labelId, equals('1rQv7S0cD2'));
      expect(
        board.queueBlock.modifiedAt,
        equals(DateTime.utc(2026, 11, 1, 19, 30, 0)),
      );
      expect(
        board.queueBlock.taskIds,
        equals(['8jKaCdOkD2', '5vWx9ZOk91', '3nQp7ROkB8']),
      );

      expect(
        board.labels.map((label) => label.id),
        equals(['4x9p2mOkD2', '9kLm2P0aBc']),
      );
      expect(
        board.focus.map((task) => task.id),
        equals(['5vWx9ZOk91', '3nQp7ROkB8']),
        reason: '8jKaCdOkD2 is blocked by 3nQp7ROkB8 and suspended until Nov 4, so 5vWx9ZOk91 and 3nQp7ROkB8 enter Focus in saved queue order',
      );
      expect(board.blocked.map((task) => task.id), equals(['8jKaCdOkD2']));
      expect(board.someday.map((task) => task.id), equals(['2bDf6HOkA4']));
      expect(board.completed.map((task) => task.id), equals(['7mPr4T09xY']));
      expect(board.completed.single.completions, equals(1));

      final serialized = tdfService.serialize(board);
      expect(serialized, startsWith('tdf 0.6.0\n\ndeleted {\n'));
      expect(serialized.contains('    queued '), isFalse);
      expect(
        serialized,
        contains('    suspended 2026-11-04 23:00:00\n'),
        reason: 'Section 6.10.3 requires emitting finite deferrals as YYYY-MM-DD HH:MM:SS',
      );
      final repeatIdx = serialized.indexOf('    repeat   30 days\n');
      final labelsIdx = serialized.indexOf(
        '    labels   4x9p2mOkD2 9kLm2P0aBc\n',
      );
      expect(
        repeatIdx,
        lessThan(labelsIdx),
        reason: 'Section 4.1.2 and 7.1 place repeat (position 7) before labels (position 8)',
      );
      expect(
        serialized,
        contains(
          'deleted {\n'
          '    generation 4\n'
          '    task 6uCk8N0aB1 2026-11-01 12:00:00\n'
          '    label 1rQv7S0cD2 2026-11-02 09:00:00\n'
          '}\n\n'
          'queue {\n'
          '    modified 2026-11-01 19:30:00\n'
          '    task 8jKaCdOkD2\n'
          '    task 5vWx9ZOk91\n'
          '    task 3nQp7ROkB8\n'
          '}',
        ),
      );

      final reparsed = tdfService.parse(serialized, evaluationTime: fixedDate);
      expect(
        reparsed.queueBlock.taskIds,
        equals(['8jKaCdOkD2', '5vWx9ZOk91', '3nQp7ROkB8']),
      );
      expect(reparsed.deletedBlock, equals(board.deletedBlock));
      expect(
        reparsed.focus.map((task) => task.id),
        equals(['5vWx9ZOk91', '3nQp7ROkB8']),
      );
      expect(reparsed.blocked.map((task) => task.id), equals(['8jKaCdOkD2']));
      expect(reparsed.someday.map((task) => task.id), equals(['2bDf6HOkA4']));
      expect(reparsed.completed.map((task) => task.id), equals(['7mPr4T09xY']));
    });

    test('parses and serializes deleted block checkpoints, queue order, completions, numbered dependencies, suspended forever, and repeat clocks', () {
      const advanced050Tdf = '''
tdf 0.5.0

deleted {
    generation 2
    task ZZZZZZZZZZ 2026-11-01 7
    task AAAAAAAAAA 2026-11-01 12:30 7
    task MMMMMMMMMM 2026-11-01 08:00:00 0
    label LLLLLLLLL2 2026-11-01 09:00
    label LLLLLLLLL1 2026-11-01 10:00:05
}

queue {
    modified 2026-11-01 11:00:00
    task 222222OkD2
    task 111111OkD2
}

label cdev00OkD2 {
    name "Dev"
}

task 111111OkD2 {
    name        "Prerequisite Recurring Task"
    created     2026-11-01 08:00
    queued      2026-11-01 08:00
    completions 3
    labels      cdev00OkD2
    repeat      1 days 09:30
}

task 222222OkD2 {
    name      "Dependent Task"
    created   2026-11-01 09:00
    queued    2026-11-01 09:00
    blocked   999999OkD2:1 111111OkD2:2 111111OkD2:5
    repeat    2 weeks 14:15:30
}

task 333333OkD2 {
    name      "Suspended Forever Task"
    created   2026-11-01 10:00
    suspended forever
    repeat    1 months 00:00:00
}
''';

      final board = tdfService.parse(advanced050Tdf, evaluationTime: fixedDate);
      expect(board.deletedBlock.generation, equals(2));
      expect(board.deletedBlock.tasks.length, equals(3));
      final recA = board.deletedBlock.findTaskRecord('AAAAAAAAAA')!;
      expect(recA.deletedAt, equals(DateTime.utc(2026, 11, 1, 12, 30, 0)));
      expect(recA.completionsCheckpoint, equals(7));
      final recZ = board.deletedBlock.findTaskRecord('ZZZZZZZZZZ')!;
      expect(recZ.deletedAt, equals(DateTime.utc(2026, 11, 1, 0, 0, 0)));
      expect(recZ.completionsCheckpoint, equals(7));

      final task1 = board.findTask('111111OkD2')!;
      expect(task1.completions, equals(3));
      expect(
        task1.repeatRule,
        equals(
          const TaskRepeatRule(
            count: 1,
            unit: RepeatUnit.days,
            clock: TdfRepeatClock(hour: 9, minute: 30),
          ),
        ),
      );

      final task2 = board.findTask('222222OkD2')!;
      expect(
        task2.dependencies,
        equals(const [
          TdfTaskDependency(taskId: '111111OkD2', requiredCompletion: 5),
          TdfTaskDependency(taskId: '999999OkD2', requiredCompletion: 1),
        ]),
        reason: 'Duplicate prerequisite targets must retain greatest requiredCompletion and sort by ascending target ID',
      );
      expect(
        board.blocked.map((task) => task.id),
        equals(['222222OkD2', '333333OkD2']),
        reason: '222222OkD2 requires 5 completions of 111111OkD2 (currently 3) and 333333OkD2 is suspended forever',
      );
      expect(board.findTask('333333OkD2')!.isSuspendedForever, isTrue);

      final serialized = tdfService.serialize(board);
      expect(
        serialized,
        contains(
          'deleted {\n'
          '    generation 2\n'
          '    task AAAAAAAAAA 2026-11-01 12:30:00 7\n'
          '    task MMMMMMMMMM 2026-11-01 08:00:00\n'
          '    task ZZZZZZZZZZ 2026-11-01 00:00:00 7\n'
          '    label LLLLLLLLL1 2026-11-01 10:00:05\n'
          '    label LLLLLLLLL2 2026-11-01 09:00:00\n'
          '}',
        ),
        reason: 'deleted block must emit task records before label records, sorted by ascending ASCII ID, with explicit seconds and omitting zero checkpoints',
      );
      expect(serialized, contains('    completions 3\n'));
      expect(serialized, contains('    repeat      1 days 09:30\n'));
      expect(
        serialized,
        contains('    blocked 111111OkD2:5 999999OkD2\n'),
        reason: 'Canonical blocked directive must sort by ascending ASCII target ID and omit :1 suffix',
      );
      expect(serialized, contains('    repeat  2 weeks 14:15:30\n'));
      expect(serialized, contains('    suspended forever\n'));
      expect(
        serialized,
        contains('    repeat    1 months\n'),
        reason: 'Default midnight clock 00:00:00 must be omitted canonically',
      );
    });

    test('supports bare words, double-quoted escapes, single-quoted raw strings, inline comments with U+00A0, CRLF, and multiple condition blocks', () {
      const validDocument =
          'tdf 0.5.0 # version\u00A0comment\r\n'
          'queue {\r\n'
          '  modified 2026-11-01 08:00:05\r\n'
          '  task tax260OkD2\r\n'
          '}\r\n'
          'label cdev00OkD2 { # comment\r\n'
          '  name \'Raw "quote" and \\\\backslash\'\r\n'
          '  note "Line1\\nLine2\\tTabbed\\rReturn\\\\Slash\\"Quote"\r\n'
          '  condition {\r\n'
          '    day mon\r\n'
          '  }\r\n'
          '  condition {\r\n'
          '    day wed fri\r\n'
          '    time 09:00 17:00\r\n'
          '  }\r\n'
          '}#comment\r\n'
          'task tax260OkD2 {#comment\r\n'
          '  name "File taxes #2026"#comment\r\n'
          '  created 2026-11-01#inline_date_comment\r\n'
          '  queued 2026-11-01 08:00:05\r\n'
          '  labels cdev00OkD2#inline_id_comment\r\n'
          '  subtasks {\r\n'
          '    step false "Collect receipts"\r\n'
          '  }\r\n'
          '}';

      final board = tdfService.parse(validDocument, evaluationTime: fixedDate);
      expect(board.labels.single.id, equals('cdev00OkD2'));
      expect(board.labels.single.conditions.length, equals(3));
      expect(board.labels.single.name, equals('Raw "quote" and \\\\backslash'));
      expect(
        board.labels.single.note,
        equals('Line1\nLine2\tTabbed\rReturn\\Slash"Quote'),
      );

      final serialized = tdfService.serialize(board);
      expect(
        serialized,
        contains(
          '    condition {\n'
          '        day  mon\n'
          '        day  wed fri\n'
          '        time 09:00 17:00\n'
          '    }\n',
        ),
        reason: 'Multiple condition blocks must serialize to one canonical condition block preserving rule order within each group',
      );
      final reparsed = tdfService.parse(serialized, evaluationTime: fixedDate);
      expect(reparsed.labels.single.conditions.length, equals(3));
    });

    test('accepts tdf 0.6.0, tdf 0.5.1, and tdf 0.5.0 with zero blocks as valid empty TaskBoard and rejects legacy versions and noncanonical IDs during normal loading', () {
      expect(
        TdfService.supportedVersion,
        equals('0.6.0'),
        reason: 'Supported TDF version must be 0.6.0',
      );
      expect(tdfService.parse('tdf 0.6.0\n').focus, isEmpty);
      expect(tdfService.parse('tdf 0.5.1\n').focus, isEmpty);
      expect(tdfService.parse('tdf 0.5.0\n').focus, isEmpty);
      expect(
        tdfService
            .parse('   \t  \n# only comment\r\ntdf 0.6.0  # version\n')
            .focus,
        isEmpty,
      );
      expect(tdfService.serialize(TaskBoard.empty()), equals('tdf 0.6.0\n'));

      for (final legacyVersion in ['0.4.0', '0.3.0', '0.2.0', '0.1.0']) {
        expect(
          () => tdfService.parse('tdf $legacyVersion\n'),
          throwsA(
            isA<TdfException>().having(
              (error) => error.kind,
              'kind',
              TdfErrorKind.unsupportedVersion,
            ),
          ),
          reason:
              'Normal loading must reject older version $legacyVersion with UnsupportedVersion',
        );
      }

      final invalidIdDocuments = <String>[
        'tdf 0.5.1\ntask t001 {\n  name "Noncanonical ID"\n  created 2026-11-01\n}\n',
        'tdf 0.5.1\ntask t_8jKaCd_OkD2 {\n  name "13-char ID"\n  created 2026-11-01\n}\n',
        'tdf 0.5.1\nlabel home {\n  name "Short label ID"\n}\n',
        'tdf 0.5.1\ntask "8jKaCdOkD2" {\n  name "Quoted task ID"\n  created 2026-11-01\n}\n',
        'tdf 0.5.1\nlabel "4x9p2mOkD2" {\n  name "Quoted label ID"\n}\n',
        'tdf 0.5.1\ntask 8jKaCdOkD2 {\n  name "T"\n  created 2026-11-01\n  labels "4x9p2mOkD2"\n}\n',
        'tdf 0.5.1\ntask 8jKaCdOkD2 {\n  name "T"\n  created 2026-11-01\n  blocked "3nQp7ROkB8"\n}\n',
        'tdf 0.5.1\ntask 8jKaCdOkD2 {\n  name "T"\n  created 2026-11-01\n  blocked t001:2\n}\n',
      ];

      for (final doc in invalidIdDocuments) {
        expect(
          () => tdfService.parse(doc, evaluationTime: fixedDate),
          throwsA(
            isA<TdfException>().having(
              (error) => error.kind,
              'kind',
              TdfErrorKind.invalidIdentifier,
            ),
          ),
          reason:
              'Noncanonical or quoted entity token must throw invalidIdentifier during normal loading: $doc',
        );
      }
    });

    test('converts tdf 0.5.0 in memory on load per Section 10.6, preserving queued > created into modified, synthesizing omitted queue, and stripping queued on serialize', () {
      const tdf050WithOmittedQueue = '''
tdf 0.5.0

label explicOkD2 {
    name     "Explicit Label"
    modified 2026-11-01 09:15:30
}

label fallbkOkD2 {
    name "Fallback Label"
}

task explicOkD2 {
    name     "Explicit Modified Task"
    created  2026-11-01 08:00
    queued   2026-11-01 08:30
    modified 2026-11-01 10:45:12
    labels   explicOkD2
}

task fallbkOkD2 priority {
    name     "Fallback Modified Task"
    created  2026-11-01 08:00
    queued   2026-11-01 09:20
    labels   fallbkOkD2
}

task somdayOkD2 {
    name    "Unqueued Someday Task"
    created 2026-11-01 07:00
}
''';

      final board = tdfService.parse(
        tdf050WithOmittedQueue,
        evaluationTime: fixedDate,
      );
      expect(
        board.labels[0].effectiveModifiedAt,
        equals(DateTime.utc(2026, 11, 1, 9, 15, 30)),
      );
      expect(
        board.labels[1].effectiveModifiedAt,
        equals(DateTime.utc(1970, 1, 1)),
        reason: 'Label without modified must fall back to fixed UTC epoch 1970-01-01 00:00:00 per Section 6.7.2',
      );
      expect(
        board.findTask('fallbkOkD2')!.modifiedAt,
        equals(DateTime.utc(2026, 11, 1, 9, 20)),
        reason: 'Section 10.6 step 3 must set task.modified to max(created, queued, finished) when modified was omitted and queued > created',
      );
      expect(
        board.queueBlock.taskIds,
        equals(['fallbkOkD2', 'explicOkD2']),
        reason: 'Section 10.6 step 2 must construct omitted 0.5.0 queue with priority tasks first, then regular tasks by ascending queued',
      );
      expect(
        board.queueBlock.modifiedAt,
        equals(DateTime.utc(2026, 11, 1, 10, 45, 12)),
        reason: 'Constructed 0.5.0 queue.modified must equal greatest 0.5.0 effective revision among queued tasks',
      );
      expect(board.someday.map((task) => task.id), equals(['somdayOkD2']));

      final serialized = tdfService.serialize(board);
      expect(serialized, startsWith('tdf 0.6.0\n'));
      expect(
        serialized.contains('\n    queued '),
        isFalse,
        reason: 'Serializing a converted 0.5.0 document must emit tdf 0.6.0 with zero queued directives',
      );
    });

    test('parses and serializes repeatable link directives in canonical order with escaped characters', () {
      const tdfWithLinks = '''
tdf 0.5.0

queue {
    modified 2026-11-01 08:30:00
    task link01OkD2
}

task link01OkD2 {
    name    "Upgrade database"
    created 2026-11-01 08:00
    queued  2026-11-01 08:30
    repeat  1 weeks 08:30
    link    "Runbook \\"Prod\\"" "https://example.com/docs/db?env=prod&v=1"
    link    'Local Notes' 'obsidian://open?vault=Ops&file=DB'
    link    "Mail Team" "mailto:dba@example.com"
    condition day mon
    subtasks {
        step false "Backup snapshot"
    }
}
''';

      final board = tdfService.parse(tdfWithLinks, evaluationTime: fixedDate);
      final task = board.findTask('link01OkD2')!;
      expect(task.links.length, equals(3));

      final serialized = tdfService.serialize(board);
      final repeatIndex = serialized.indexOf('    repeat    1 weeks 08:30\n');
      final firstLinkIndex = serialized.indexOf(
        '    link      "Runbook \\"Prod\\"" "https://example.com/docs/db?env=prod&v=1"\n',
      );
      final conditionIndex = serialized.indexOf('    condition day mon\n');
      final subtasksIndex = serialized.indexOf('    subtasks {\n');

      expect(repeatIndex, greaterThan(0));
      expect(firstLinkIndex, greaterThan(repeatIndex));
      expect(conditionIndex, greaterThan(firstLinkIndex));
      expect(subtasksIndex, greaterThan(conditionIndex));

      final reparsed = tdfService.parse(serialized, evaluationTime: fixedDate);
      expect(reparsed.findTask('link01OkD2')!.links, equals(task.links));
    });
  });
}
