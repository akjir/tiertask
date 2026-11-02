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
    test('parses canonical TDF document from TDF_SPEC.md Section 9 and derives all 6 tiers', () {
      const canonicalTdf = '''
# ==========================================
# TierTask Data Format (TDF) Example Document
# ==========================================

tdf 0.2.0

# === Labels ===
label home {
    name  "Home"
    color "#4CAF50"
    condition {
        day sat sun
        location 50.9787 11.0328 150
    }
}

label it {
    name  "IT & Servers"
    color "#2196F3"
    condition time 09:00 18:00
}

# === Tasks ===

# Prioritized task -> Lands at the top of Focus (in it)
task t001 priority {
    name      "Verify server backup"
    note      "Inspect logs under /var/log/backup"
    created   2026-11-01 08:30
    queued    2026-11-01 08:30
    labels    it
}

# Regular active task with subtasks -> Focus / Ready
task t002 {
    name      "Clean up study"
    created   2026-11-01 09:00
    queued    2026-11-01 09:15
    labels    home

    subtasks auto-finish {
        step true  "Wipe desk"
        step false "Organize cables"
        step false "Empty trash bin"
    }
}

# Task with multiple labels and global condition reset (always active)
task t003 {
    name      "Clean dust from NAS drives"
    created   2026-11-01 10:00
    queued    2026-11-01 10:00
    labels    home it
    condition any
}

# Blocked task (waits for t001 and is suspended until Nov 5)
task t004 {
    name      "Apply firewall update"
    created   2026-11-01 11:00
    queued    2026-11-01 11:00
    labels    it
    blocked   t001
    suspended 2026-11-05 08:00
}

# Task in "Someday" (no 'queued' directive present)
task t005 {
    name      "3D-print custom NAS enclosure"
    created   2026-11-01 12:00
    labels    it
}

# Completed task ('finished' is set -> deleted after 30 days)
task t006 {
    name      "Mount winter tires"
    created   2026-10-20 14:00
    queued    2026-10-21 08:00
    finished  2026-10-29 16:45
    labels    home
}
''';

      final board = tdfService.parse(canonicalTdf, evaluationTime: fixedDate);

      expect(
        board.labels.map((label) => label.id),
        equals(['home', 'it']),
        reason: 'Labels must be parsed in declaration order',
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
        equals(['t001', 't002', 't003']),
        reason: 't001 (priority in it at 12:00), t002 (active on Sunday in home), and t003 (condition any) must fill Focus',
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
        equals(['t004']),
        reason: 't004 is blocked by t001 and suspended until 2026-11-05',
      );
      expect(
        board.someday.map((task) => task.id),
        equals(['t005']),
        reason: 't005 has no queued directive so it lands in Someday',
      );
      expect(
        board.completed.map((task) => task.id),
        equals(['t006']),
        reason: 't006 has a finished directive so it lands in Completed',
      );

      final serialized = tdfService.serialize(board);
      expect(
        serialized.contains('\r\n'),
        isFalse,
        reason: 'Canonical serialization must emit LF line terminators only',
      );
      expect(
        serialized,
        contains(
          'label home {\n'
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
          'label it {\n'
          '    name "IT & Servers"\n'
          '    color "#2196F3"\n'
          '    condition time 09:00 18:00\n'
          '}',
        ),
        reason: 'Label with 1 condition must serialize as an inline condition directive',
      );
      expect(serialized, contains('labels home it'));
      expect(serialized, contains('condition any'));

      final reparsed = tdfService.parse(serialized, evaluationTime: fixedDate);
      expect(
        reparsed.focus.map((task) => task.id),
        equals(['t001', 't002', 't003']),
      );
      expect(reparsed.blocked.map((task) => task.id), equals(['t004']));
      expect(reparsed.someday.map((task) => task.id), equals(['t005']));
      expect(reparsed.completed.map((task) => task.id), equals(['t006']));
    });

    test('automatically migrates legacy category and location blocks and task categories/locations directives into canonical labels', () {
      const legacyTdf = '''
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
''';

      final board = tdfService.parse(legacyTdf, evaluationTime: fixedDate);
      expect(
        board.labels.map((label) => label.id),
        equals(['home', 'work', 'c_house', 'c_it']),
        reason: 'Legacy location and category blocks must migrate to TdfLabel in declaration order',
      );
      expect(
        board.labels[1].conditions.single,
        isA<LocationTaskCondition>()
            .having((condition) => condition.latitude, 'latitude', 50.9787)
            .having((condition) => condition.longitude, 'longitude', 11.0328)
            .having(
              (condition) => condition.radiusMeters,
              'radiusMeters',
              150.0,
            ),
        reason: 'Legacy gps directive on location block must migrate to LocationTaskCondition on TdfLabel',
      );
      expect(
        board.focus.single.labelIds,
        equals(['home', 'work', 'c_house', 'c_it']),
        reason: 'Legacy locations and categories task directives must merge into labelIds',
      );

      final serialized = tdfService.serialize(board);
      expect(serialized, contains('label home {'));
      expect(serialized, contains('label work {'));
      expect(serialized, contains('condition location 50.9787 11.0328 150'));
      expect(serialized, contains('label c_house {'));
      expect(serialized, contains('labels home work c_house c_it'));
      expect(serialized, isNot(contains('category ')));
      expect(serialized, isNot(contains('location work')));
      expect(serialized, isNot(contains('categories ')));
      expect(serialized, isNot(contains('locations ')));
    });

    test('supports bare words, double-quoted escapes, single-quoted raw strings, inline comments, CRLF, and optional seconds in timestamps', () {
      const validDocument =
          'tdf 0.2.0 # version comment\r\n'
          'label c_dev { # comment\r\n'
          '  name \'Raw "quote" and \\\\backslash\'\r\n'
          '  note "Line1\\nLine2\\tTabbed\\rReturn\\\\Slash\\"Quote"\r\n'
          '}#comment\r\n'
          'task taxes2026 {#comment\r\n'
          '  name "File taxes #2026"#comment\r\n'
          '  created 2026-11-01#inline_date_comment\r\n'
          '  queued 2026-11-01 08:00:05\r\n'
          '  labels c_dev#inline_id_comment\r\n'
          '  subtasks {\r\n'
          '    step false "Collect receipts"\r\n'
          '  }\r\n'
          '}';

      final board = tdfService.parse(validDocument, evaluationTime: fixedDate);
      expect(board.labels.single.id, equals('c_dev'));
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
      expect(board.focus.single.id, equals('taxes2026'));
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

    test('accepts tdf 0.3.0 and legacy tdf 0.2.0 with zero blocks as valid empty TaskBoard and serializes with tdf 0.3.0', () {
      expect(
        TdfService.supportedVersion,
        equals('0.3.0'),
        reason: 'Supported TDF version must be 0.3.0',
      );
      expect(tdfService.parse('tdf 0.3.0\n').focus, isEmpty);
      expect(tdfService.parse('tdf 0.2.0\n').focus, isEmpty);
      expect(
        tdfService
            .parse('   \t  \n# only comment\r\ntdf 0.3.0  # version\n')
            .focus,
        isEmpty,
      );
      expect(tdfService.serialize(TaskBoard.empty()), equals('tdf 0.3.0\n'));
    });

    test('parses and serializes per-entity modified UTC timestamps on label and task blocks with effectiveModifiedAt fallbacks and duplicate/invalid error checks', () {
      const tdfWithModified = '''
tdf 0.3.0

label l_explicit {
    name     "Explicit Label"
    modified 2026-11-01 09:15:30
}

label l_fallback {
    name "Fallback Label"
}

task t_explicit {
    name     "Explicit Modified Task"
    created  2026-11-01 08:00
    queued   2026-11-01 08:30
    modified 2026-11-01 10:45:12
    labels   l_explicit
}

task t_fallback {
    name     "Fallback Modified Task"
    created  2026-11-01 08:00
    queued   2026-11-01 09:20
    labels   l_fallback
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

      final explicitTask = board.findTask('t_explicit')!;
      expect(
        explicitTask.modifiedAt,
        equals(DateTime.utc(2026, 11, 1, 10, 45, 12)),
      );
      expect(
        explicitTask.effectiveModifiedAt,
        equals(DateTime.utc(2026, 11, 1, 10, 45, 12)),
      );

      final fallbackTask = board.findTask('t_fallback')!;
      expect(fallbackTask.modifiedAt, isNull);
      expect(
        fallbackTask.effectiveModifiedAt,
        equals(DateTime.utc(2026, 11, 1, 9, 20)),
        reason: 'Task without modified must fall back to max(created, queued, finished) in UTC',
      );

      final serialized = tdfService.serialize(board);
      expect(serialized, startsWith('tdf 0.3.0\n'));
      expect(serialized, contains('modified 2026-11-01 09:15:30\n'));
      expect(serialized, contains('modified 2026-11-01 10:45:12\n'));

      expect(
        () => tdfService.parse(
          'tdf 0.3.0\nlabel l1 {\n  name "L1"\n  modified 2026-11-01 08:00\n  modified 2026-11-01 09:00\n}\n',
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
          'tdf 0.3.0\ntask t1 {\n  name "T1"\n  created 2026-11-01\n  modified 2026-11-01 08:00\n  modified 2026-11-01 09:00\n}\n',
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
          'tdf 0.3.0\ntask t1 {\n  name "T1"\n  created 2026-11-01\n  modified 2026-11-01 25:99\n}\n',
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
  });
}
