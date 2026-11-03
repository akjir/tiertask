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
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/services/tdf_service.dart';

void main() {
  const tdfService = TdfService();
  final fixedDate = DateTime.utc(2026, 11, 1, 12, 0);

  group('TdfService Lexical Scanner, Parser & Canonical Serializer', () {
    test('parses canonical TDF 0.4.0 document from TDF_SPEC.md Section 9 and derives all 6 tiers', () {
      const canonicalTdf = '''
# ==========================================
# TierTask Data Format (TDF) Example Document
# ==========================================

tdf 0.4.0

# === Labels ===
label 4x9p2mOkD2 {
    name  "Home"
    color "#4CAF50"
    condition {
        day sat sun
        location 50.9787 11.0328 150
    }
}

label 7qB1kZOkD2 {
    name  "IT & Servers"
    color "#2196F3"
    condition time 09:00 18:00
}

# === Tasks ===

# Prioritized task -> Lands at the top of Focus (in it)
task 8jKaCdOkD2 priority {
    name      "Verify server backup"
    note      "Inspect logs under /var/log/backup"
    created   2026-11-01 08:30
    queued    2026-11-01 08:30
    labels    7qB1kZOkD2
}

# Regular active task with subtasks -> Focus / Ready
task 3nR8vWOkD8 {
    name      "Clean up study"
    created   2026-11-01 09:00
    queued    2026-11-01 09:15
    labels    4x9p2mOkD2

    subtasks auto-finish {
        step true  "Wipe desk"
        step false "Organize cables"
        step false "Empty trash bin"
    }
}

# Task with multiple labels and global condition reset (always active)
task 9mP4xLOkDS {
    name      "Clean dust from NAS drives"
    created   2026-11-01 10:00
    queued    2026-11-01 10:00
    labels    4x9p2mOkD2 7qB1kZOkD2
    condition any
}

# Blocked task (waits for 8jKaCdOkD2 and is suspended until Nov 5)
task 2kF7yQOkDm {
    name      "Apply firewall update"
    created   2026-11-01 11:00
    queued    2026-11-01 11:00
    labels    7qB1kZOkD2
    blocked   8jKaCdOkD2
    suspended 2026-11-05 08:00
}

# Task in "Someday" (no 'queued' directive present)
task 5vH3nTOkE6 {
    name      "3D-print custom NAS enclosure"
    created   2026-11-01 12:00
    labels    7qB1kZOkD2
}

# Completed task ('finished' is set -> deleted after 30 days)
task 6wJ9cMOjcG {
    name      "Mount winter tires"
    created   2026-10-20 14:00
    queued    2026-10-21 08:00
    finished  2026-10-29 16:45
    labels    4x9p2mOkD2
}
''';

      final board = tdfService.parse(canonicalTdf, evaluationTime: fixedDate);

      expect(
        board.labels.map((label) => label.id),
        equals(['4x9p2mOkD2', '7qB1kZOkD2']),
        reason: 'Labels must be parsed in declaration order with 13-char IDs',
      );
      expect(board.labels[0].color, equals('#4CAF50'));
      expect(board.labels[0].conditions.length, equals(2));
      expect(
        board.labels[0].conditions[0],
        isA<DayTaskCondition>().having(
          (condition) => condition.dayTokens,
          'dayTokens',
          equals(['sat', 'sun']),
        ),
      );
      expect(
        board.labels[0].conditions[1],
        isA<LocationTaskCondition>()
            .having((condition) => condition.latitude, 'latitude', 50.9787)
            .having((condition) => condition.longitude, 'longitude', 11.0328)
            .having(
              (condition) => condition.radiusMeters,
              'radiusMeters',
              150.0,
            ),
      );
      expect(board.labels[1].color, equals('#2196F3'));
      expect(
        board.labels[1].conditions.single,
        isA<TimeWindowTaskCondition>()
            .having((condition) => condition.startToken, 'startToken', '09:00')
            .having((condition) => condition.endToken, 'endToken', '18:00'),
      );

      expect(
        board.focus.map((task) => task.id),
        equals(['8jKaCdOkD2', '3nR8vWOkD8', '9mP4xLOkDS']),
        reason: 'Active tasks must fill Focus in priority and queued order',
      );
      expect(board.focus[0].isPriority, isTrue);
      expect(board.focus[0].note, equals('Inspect logs under /var/log/backup'));
      expect(board.focus[1].subtasksAutoFinish, isTrue);
      expect(board.focus[1].subtasks.length, equals(3));
      expect(board.focus[1].subtasks[0].isCompleted, isTrue);
      expect(board.focus[1].subtasks[1].isCompleted, isFalse);
      expect(board.focus[2].conditions.single, isA<GlobalResetTaskCondition>());

      expect(board.ready, isEmpty);
      expect(board.planned, isEmpty);
      expect(
        board.blocked.map((task) => task.id),
        equals(['2kF7yQOkDm']),
        reason: '2kF7yQOkDm is blocked by 8jKaCdOkD2 and suspended',
      );
      expect(
        board.someday.map((task) => task.id),
        equals(['5vH3nTOkE6']),
        reason: '5vH3nTOkE6 has no queued directive so it lands in Someday',
      );
      expect(
        board.completed.map((task) => task.id),
        equals(['6wJ9cMOjcG']),
        reason: '6wJ9cMOjcG has a finished directive so it lands in Completed',
      );

      final serialized = tdfService.serialize(board);
      expect(
        serialized,
        startsWith('tdf 0.4.0\n'),
        reason: 'Canonical serialization must emit tdf 0.4.0 header',
      );
      expect(
        serialized.contains('\r\n'),
        isFalse,
        reason: 'Canonical serialization must emit LF line terminators only',
      );
      expect(
        serialized,
        contains(
          'label 4x9p2mOkD2 {\n'
          '    name "Home"\n'
          '    color "#4CAF50"\n'
          '    condition {\n'
          '        day sat sun\n'
          '        location 50.9787 11.0328 150\n'
          '    }\n'
          '}',
        ),
        reason: 'Label with 2 conditions must serialize as a condition { ... } sub-block',
      );
      expect(
        serialized,
        contains(
          'label 7qB1kZOkD2 {\n'
          '    name "IT & Servers"\n'
          '    color "#2196F3"\n'
          '    condition time 09:00 18:00\n'
          '}',
        ),
        reason: 'Label with 1 condition must serialize as an inline condition directive',
      );
      expect(serialized, contains('labels 4x9p2mOkD2 7qB1kZOkD2'));
      expect(serialized, contains('condition any'));

      final reparsed = tdfService.parse(serialized, evaluationTime: fixedDate);
      expect(
        reparsed.focus.map((task) => task.id),
        equals(['8jKaCdOkD2', '3nR8vWOkD8', '9mP4xLOkDS']),
      );
      expect(reparsed.blocked.map((task) => task.id), equals(['2kF7yQOkDm']));
      expect(reparsed.someday.map((task) => task.id), equals(['5vH3nTOkE6']));
      expect(reparsed.completed.map((task) => task.id), equals(['6wJ9cMOjcG']));
    });

    test('immediately converts legacy tdf 0.2.0 and tdf 0.3.0 task and label IDs to 10-character Base62 IDs and rewrites intra-document references', () {
      const legacy020Tdf = '''
tdf 0.2.0
location home {
    name "Home"
}
location work {
    name "Work"
    gps  50.9787 11.0328 150
}
category c_house {
    name  "Household"
    color "#4CAF50"
}
category c_it {
    name  "IT & Servers"
    color "#2196F3"
}
task t001 {
    name       "Clean up study"
    created    2026-11-01 09:00
    queued     2026-11-01 09:15
    locations  home work
    categories c_house c_it
}
task t002 {
    name       "Follow-up task"
    created    2026-11-01 10:00
    queued     2026-11-01 10:00
    blocked    t001
    locations  home
}
''';

      final board020 = tdfService.parse(
        legacy020Tdf,
        evaluationTime: fixedDate,
      );
      expect(board020.labels.length, equals(4));
      for (final label in board020.labels) {
        expect(
          isValidLabelId(label.id),
          isTrue,
          reason:
              'Every migrated 0.2.0 label ID (${label.id}) must be a valid 10-character <6xBase62><4xBase62> ID',
        );
      }
      expect(
        board020.labels.map((label) => label.name),
        equals(['Home', 'Work', 'Household', 'IT & Servers']),
      );
      expect(
        board020.labels[1].conditions.single,
        isA<LocationTaskCondition>()
            .having((condition) => condition.latitude, 'latitude', 50.9787)
            .having((condition) => condition.longitude, 'longitude', 11.0328)
            .having(
              (condition) => condition.radiusMeters,
              'radiusMeters',
              150.0,
            ),
      );

      final convertedFirstTask = board020.focus.single;
      final convertedSecondTask = board020.blocked.single;
      expect(
        isValidTaskId(convertedFirstTask.id),
        isTrue,
        reason: 'Migrated t001 must have a valid 10-char task ID',
      );
      expect(
        isValidTaskId(convertedSecondTask.id),
        isTrue,
        reason: 'Migrated t002 must have a valid 10-char task ID',
      );
      expect(
        convertedFirstTask.labelIds,
        equals(board020.labels.map((label) => label.id).toList()),
        reason: 'Legacy locations and categories references must be rewritten to the new 10-char label IDs',
      );
      expect(
        convertedSecondTask.blockedByTaskIds,
        equals([convertedFirstTask.id]),
        reason: 'Legacy blocked t001 reference must be rewritten to the new 10-char task ID',
      );

      final serialized020 = tdfService.serialize(board020);
      expect(serialized020, startsWith('tdf 0.4.0\n'));
      expect(serialized020, isNot(contains('task t001')));
      expect(serialized020, isNot(contains('label home')));
      final reparsed020 = tdfService.parse(
        serialized020,
        evaluationTime: fixedDate,
      );
      expect(reparsed020.focus.single.id, equals(convertedFirstTask.id));
      expect(reparsed020.blocked.single.id, equals(convertedSecondTask.id));

      const legacy030Tdf = '''
tdf 0.3.0
label office_work {
    name "Office Work"
}
task t001 {
    name "Prepare slides"
    created 2026-11-01 09:00
    queued 2026-11-01 09:00
    labels office_work
}
task t002 {
    name "Present slides"
    created 2026-11-01 09:30
    queued 2026-11-01 09:30
    blocked t001
    labels office_work
}
''';
      final board030 = tdfService.parse(
        legacy030Tdf,
        evaluationTime: fixedDate,
      );
      final convertedLabelId = board030.labels.single.id;
      expect(isValidLabelId(convertedLabelId), isTrue);
      expect(convertedLabelId, isNot(equals('office_work')));
      expect(isValidTaskId(board030.focus.single.id), isTrue);
      expect(isValidTaskId(board030.blocked.single.id), isTrue);
      expect(board030.focus.single.labelIds, equals([convertedLabelId]));
      expect(
        board030.blocked.single.blockedByTaskIds,
        equals([board030.focus.single.id]),
      );
    });

    test('supports bare words, double-quoted escapes, single-quoted raw strings, inline comments, CRLF, and optional seconds in timestamps', () {
      const validDocument =
          'tdf 0.4.0 # version comment\r\n'
          'label cdev00OkD2 { # comment\r\n'
          '  name \'Raw "quote" and \\\\backslash\'\r\n'
          '  note "Line1\\nLine2\\tTabbed\\rReturn\\\\Slash\\"Quote"\r\n'
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
      expect(
        board.labels.single.name,
        equals('Raw "quote" and \\\\backslash'),
        reason: 'Single-quoted strings must preserve backslashes and quotes',
      );
      expect(
        board.labels.single.note,
        equals('Line1\nLine2\tTabbed\rReturn\\Slash"Quote'),
        reason: 'Double-quoted strings must unescape \\n, \\t, \\r, \\\\, \\"',
      );
      expect(board.focus.single.id, equals('tax260OkD2'));
      expect(board.focus.single.title, equals('File taxes #2026'));
      expect(
        board.focus.single.createdAt,
        equals(DateTime.utc(2026, 11, 1, 0, 0)),
        reason: 'Date-only timestamp must default time component to 00:00:00',
      );
      expect(
        board.focus.single.queuedAt,
        equals(DateTime.utc(2026, 11, 1, 8, 0, 5)),
        reason: 'Timestamp with :SS must preserve seconds precision',
      );

      final serialized = tdfService.serialize(board);
      expect(
        serialized,
        contains('created 2026-11-01 00:00\n'),
        reason: 'Zero seconds must omit :SS in canonical serialization',
      );
      expect(
        serialized,
        contains('queued 2026-11-01 08:00:05\n'),
        reason: 'Non-zero seconds must emit :SS in canonical serialization',
      );
      final reparsed = tdfService.parse(serialized, evaluationTime: fixedDate);
      expect(
        reparsed.labels.single.note,
        equals('Line1\nLine2\tTabbed\rReturn\\Slash"Quote'),
      );
      expect(
        reparsed.focus.single.queuedAt,
        equals(DateTime.utc(2026, 11, 1, 8, 0, 5)),
      );
    });

    test('accepts tdf 0.4.0 and legacy tdf 0.3.0 / 0.2.0 with zero blocks as valid empty TaskBoard and serializes with tdf 0.4.0', () {
      expect(
        TdfService.supportedVersion,
        equals('0.4.0'),
        reason: 'Supported TDF version must be 0.4.0',
      );
      expect(tdfService.parse('tdf 0.4.0\n').focus, isEmpty);
      expect(tdfService.parse('tdf 0.3.0\n').focus, isEmpty);
      expect(tdfService.parse('tdf 0.2.0\n').focus, isEmpty);
      expect(
        tdfService
            .parse('   \t  \n# only comment\r\ntdf 0.4.0  # version\n')
            .focus,
        isEmpty,
      );
      expect(tdfService.serialize(TaskBoard.empty()), equals('tdf 0.4.0\n'));
    });

    test('automatically normalizes non-conforming entity identifiers in tdf 0.4.0 documents (including 13-char t_/l_ IDs and short IDs) and rewrites all labels and blocked references while rejecting quoted or non-identifier tokens', () {
      const mixed040Tdf = '''
tdf 0.4.0

label 4x9p2mOkD2 {
    name "Valid Label"
}

label l_legacy_OkD2 {
    name "Old 13-Char Label"
}

label work-ctx {
    name "Short Hyphen Label"
}

task 8jKaCdOkD2 {
    name    "Valid Prerequisite Task"
    created 2026-11-01 08:00
    queued  2026-11-01 08:00
    labels  4x9p2mOkD2 l_legacy_OkD2
}

task t_8jKaCd_OkD2 {
    name    "Old 13-Char Task Blocked By Valid Task"
    created 2026-11-01 08:30
    queued  2026-11-01 08:30
    blocked 8jKaCdOkD2
    labels  l_legacy_OkD2 work-ctx
}

task t003 {
    name    "Short ID Task Blocked By Old 13-Char Task And Dangling Old ID"
    created 2026-11-01 09:00
    queued  2026-11-01 09:00
    blocked t_8jKaCd_OkD2 t_pruned_OkD2
    labels  work-ctx
}
''';

      final board = tdfService.parse(mixed040Tdf, evaluationTime: fixedDate);
      expect(board.labels.length, equals(3));
      expect(
        board.labels[0].id,
        equals('4x9p2mOkD2'),
        reason: 'Already-valid 10-character label ID must remain unchanged',
      );
      final converted13CharLabelId = board.labels[1].id;
      final convertedShortLabelId = board.labels[2].id;
      expect(isValidLabelId(converted13CharLabelId), isTrue);
      expect(isValidLabelId(convertedShortLabelId), isTrue);
      expect(converted13CharLabelId, isNot(equals('l_legacy_OkD2')));
      expect(convertedShortLabelId, isNot(equals('work-ctx')));

      final validTask = board.findTask('8jKaCdOkD2')!;
      expect(
        validTask.labelIds,
        equals(['4x9p2mOkD2', converted13CharLabelId]),
        reason:
            'Valid task must have its non-conforming label reference rewritten',
      );

      expect(board.blocked.length, equals(2));
      final converted13CharTask = board.blocked.firstWhere(
        (task) => task.title == 'Old 13-Char Task Blocked By Valid Task',
      );
      final convertedShortTask = board.blocked.firstWhere(
        (task) =>
            task.title ==
            'Short ID Task Blocked By Old 13-Char Task And Dangling Old ID',
      );
      expect(isValidTaskId(converted13CharTask.id), isTrue);
      expect(isValidTaskId(convertedShortTask.id), isTrue);
      expect(
        converted13CharTask.blockedByTaskIds,
        equals(['8jKaCdOkD2']),
        reason: 'Valid prerequisite reference must remain intact',
      );
      expect(
        converted13CharTask.labelIds,
        equals([converted13CharLabelId, convertedShortLabelId]),
        reason: 'All non-conforming label references on task must be rewritten',
      );
      expect(
        convertedShortTask.blockedByTaskIds.first,
        equals(converted13CharTask.id),
        reason: 'Blocked reference to t_8jKaCd_OkD2 must be rewritten to its new 10-character ID',
      );
      expect(
        isValidTaskId(convertedShortTask.blockedByTaskIds[1]),
        isTrue,
        reason: 'Dangling non-conforming blocked reference must also be normalized to 10-character Base62',
      );

      final filteredByOldLabel = tdfService.parse(
        mixed040Tdf,
        evaluationTime: fixedDate,
        activeLabelId: 'l_legacy_OkD2',
      );
      expect(
        filteredByOldLabel.focus.map((task) => task.id),
        equals(['8jKaCdOkD2']),
        reason: 'activeLabelId matching a normalized label ID must filter tasks using the rewritten ID',
      );
      expect(
        filteredByOldLabel.blocked.map((task) => task.id),
        equals([converted13CharTask.id]),
      );

      final invalidDocuments = <String>[
        'tdf 0.4.0\ntask "8jKaCdOkD2" {\n  name "Quoted task ID"\n  created 2026-11-01\n}\n',
        'tdf 0.4.0\ntask bad\$id {\n  name "Disallowed char in task ID"\n  created 2026-11-01\n}\n',
        'tdf 0.4.0\nlabel "4x9p2mOkD2" {\n  name "Quoted label ID"\n}\n',
        'tdf 0.4.0\nlabel bad\$label {\n  name "Disallowed char in label ID"\n}\n',
        'tdf 0.4.0\ntask 8jKaCdOkD2 {\n  name "T"\n  created 2026-11-01\n  labels "4x9p2mOkD2"\n}\n',
        'tdf 0.4.0\ntask 8jKaCdOkD2 {\n  name "T"\n  created 2026-11-01\n  labels bad\$label\n}\n',
        'tdf 0.4.0\ntask 8jKaCdOkD2 {\n  name "T"\n  created 2026-11-01\n  blocked "3nQp7ROkB8"\n}\n',
        'tdf 0.4.0\ntask 8jKaCdOkD2 {\n  name "T"\n  created 2026-11-01\n  blocked bad\$task\n}\n',
      ];

      for (final doc in invalidDocuments) {
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
              'Quoted or non-identifier entity token must throw invalidIdentifier: $doc',
        );
      }
    });

    test('parses and serializes per-entity modified UTC timestamps on label and task blocks with effectiveModifiedAt fallbacks and duplicate/invalid error checks', () {
      const tdfWithModified = '''
tdf 0.4.0

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

task fallbkOkD2 {
    name     "Fallback Modified Task"
    created  2026-11-01 08:00
    queued   2026-11-01 09:20
    labels   fallbkOkD2
}
''';

      final board = tdfService.parse(
        tdfWithModified,
        evaluationTime: fixedDate,
      );
      expect(
        board.labels[0].modifiedAt,
        equals(DateTime.utc(2026, 11, 1, 9, 15, 30)),
        reason: 'Label modified directive must parse to UTC second precision',
      );
      expect(
        board.labels[0].effectiveModifiedAt,
        equals(DateTime.utc(2026, 11, 1, 9, 15, 30)),
      );
      expect(
        board.labels[1].modifiedAt,
        isNull,
        reason: 'Label without modified directive must keep modifiedAt null',
      );
      expect(
        board.labels[1].effectiveModifiedAt,
        equals(TaskItem.defaultCreatedAt),
        reason:
            'Label without modified must fall back to defaultCreatedAt in UTC',
      );

      final explicitTask = board.findTask('explicOkD2')!;
      expect(
        explicitTask.modifiedAt,
        equals(DateTime.utc(2026, 11, 1, 10, 45, 12)),
      );
      expect(
        explicitTask.effectiveModifiedAt,
        equals(DateTime.utc(2026, 11, 1, 10, 45, 12)),
      );

      final fallbackTask = board.findTask('fallbkOkD2')!;
      expect(fallbackTask.modifiedAt, isNull);
      expect(
        fallbackTask.effectiveModifiedAt,
        equals(DateTime.utc(2026, 11, 1, 9, 20)),
        reason: 'Task without modified must fall back to max(created, queued, finished) in UTC',
      );

      final serialized = tdfService.serialize(board);
      expect(serialized, startsWith('tdf 0.4.0\n'));
      expect(serialized, contains('modified 2026-11-01 09:15:30\n'));
      expect(serialized, contains('modified 2026-11-01 10:45:12\n'));

      expect(
        () => tdfService.parse(
          'tdf 0.4.0\nlabel 000001OkD2 {\n  name "L1"\n  modified 2026-11-01 08:00\n  modified 2026-11-01 09:00\n}\n',
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.duplicateDirective,
          ),
        ),
        reason: 'Duplicate modified on label must throw duplicateDirective',
      );
      expect(
        () => tdfService.parse(
          'tdf 0.4.0\ntask 000001OkD2 {\n  name "T1"\n  created 2026-11-01\n  modified 2026-11-01 08:00\n  modified 2026-11-01 09:00\n}\n',
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.duplicateDirective,
          ),
        ),
        reason: 'Duplicate modified on task must throw duplicateDirective',
      );
      expect(
        () => tdfService.parse(
          'tdf 0.4.0\ntask 000001OkD2 {\n  name "T1"\n  created 2026-11-01\n  modified 2026-11-01 25:99\n}\n',
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.invalidTimestamp,
          ),
        ),
        reason: 'Invalid modified timestamp must throw invalidTimestamp',
      );
    });

    test(
      'parses and serializes repeat directives across days, weeks, and months',
      () {
        const tdfWithRepeat = '''
tdf 0.4.0

task days00OkD2 {
    name    "Daily standup"
    created 2026-11-01 08:00
    queued  2026-11-01 08:00
    repeat  1 days
}

task weeks0OkD2 {
    name    "Weekly review"
    created 2026-11-01 09:00
    queued  2026-11-01 09:00
    repeat  2 weeks
}

task monthsOkD2 {
    name    "Monthly billing"
    created 2026-11-01 10:00
    queued  2026-11-01 10:00
    repeat  3 months
}
''';

        final board = tdfService.parse(
          tdfWithRepeat,
          evaluationTime: fixedDate,
        );
        expect(
          board.findTask('days00OkD2')!.repeatRule,
          equals(const TaskRepeatRule(count: 1, unit: RepeatUnit.days)),
          reason: 'repeat 1 days must parse to RepeatUnit.days with count 1',
        );
        expect(
          board.findTask('weeks0OkD2')!.repeatRule,
          equals(const TaskRepeatRule(count: 2, unit: RepeatUnit.weeks)),
          reason: 'repeat 2 weeks must parse to RepeatUnit.weeks with count 2',
        );
        expect(
          board.findTask('monthsOkD2')!.repeatRule,
          equals(const TaskRepeatRule(count: 3, unit: RepeatUnit.months)),
          reason:
              'repeat 3 months must parse to RepeatUnit.months with count 3',
        );

        final serialized = tdfService.serialize(board);
        expect(serialized, contains('    repeat 1 days\n'));
        expect(serialized, contains('    repeat 2 weeks\n'));
        expect(serialized, contains('    repeat 3 months\n'));

        final reparsed = tdfService.parse(
          serialized,
          evaluationTime: fixedDate,
        );
        expect(
          reparsed.findTask('days00OkD2')!.repeatRule,
          equals(const TaskRepeatRule(count: 1, unit: RepeatUnit.days)),
        );
        expect(
          reparsed.findTask('weeks0OkD2')!.repeatRule,
          equals(const TaskRepeatRule(count: 2, unit: RepeatUnit.weeks)),
        );
        expect(
          reparsed.findTask('monthsOkD2')!.repeatRule,
          equals(const TaskRepeatRule(count: 3, unit: RepeatUnit.months)),
        );
      },
    );

    test('parses and serializes repeatable link directives in canonical order with escaped characters', () {
      const tdfWithLinks = '''
tdf 0.4.0

task link01OkD2 {
    name    "Upgrade database"
    created 2026-11-01 08:00
    queued  2026-11-01 08:30
    repeat  1 weeks
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
      expect(
        task.links,
        equals(const [
          TaskLink(
            title: 'Runbook "Prod"',
            uri: 'https://example.com/docs/db?env=prod&v=1',
          ),
          TaskLink(
            title: 'Local Notes',
            uri: 'obsidian://open?vault=Ops&file=DB',
          ),
          TaskLink(title: 'Mail Team', uri: 'mailto:dba@example.com'),
        ]),
        reason:
            'Multiple link directives must parse in exact declaration order',
      );

      final serialized = tdfService.serialize(board);
      final repeatIndex = serialized.indexOf('    repeat 1 weeks\n');
      final firstLinkIndex = serialized.indexOf(
        '    link "Runbook \\"Prod\\"" "https://example.com/docs/db?env=prod&v=1"\n',
      );
      final secondLinkIndex = serialized.indexOf(
        '    link "Local Notes" "obsidian://open?vault=Ops&file=DB"\n',
      );
      final thirdLinkIndex = serialized.indexOf(
        '    link "Mail Team" "mailto:dba@example.com"\n',
      );
      final conditionIndex = serialized.indexOf('    condition day mon\n');
      final subtasksIndex = serialized.indexOf('    subtasks {\n');

      expect(repeatIndex, greaterThan(0));
      expect(
        firstLinkIndex,
        greaterThan(repeatIndex),
        reason: 'link directives must be serialized after repeat',
      );
      expect(secondLinkIndex, greaterThan(firstLinkIndex));
      expect(thirdLinkIndex, greaterThan(secondLinkIndex));
      expect(
        conditionIndex,
        greaterThan(thirdLinkIndex),
        reason: 'link directives must be serialized before condition',
      );
      expect(subtasksIndex, greaterThan(conditionIndex));

      final reparsed = tdfService.parse(serialized, evaluationTime: fixedDate);
      expect(
        reparsed.findTask('link01OkD2')!.links,
        equals(task.links),
        reason: 'Round-trip parse/serialize must preserve all task links',
      );
    });
  });
}
