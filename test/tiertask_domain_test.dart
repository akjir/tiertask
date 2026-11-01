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

import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
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

    test('accepts tdf 0.2.0 with zero blocks as valid empty TaskBoard and serializes empty board with tdf 0.2.0', () {
      expect(tdfService.parse('tdf 0.2.0\n').focus, isEmpty);
      expect(
        tdfService
            .parse('   \t  \n# only comment\r\ntdf 0.2.0  # version\n')
            .focus,
        isEmpty,
      );
      expect(tdfService.serialize(TaskBoard.empty()), equals('tdf 0.2.0\n'));
    });
  });

  group('TDF Section 4.3 & Section 5 Dynamic 6-Tier Derivation, Condition Inheritance & Context Filtering', () {
    test('evaluates blocking conditions, group-level label condition inheritance, task overrides, group resets, global resets, Haversine GPS, and cohesive per-label OR logic', () {
      const tdfWithConditions = '''
tdf 0.2.0

label office {
    name "Office"
    condition {
        day mon tue wed thu fri
        time 09:00 17:00
        location 50.9787 11.0328 150
    }
}
label weekend_home {
    name "Weekend Home"
    condition {
        day sat sun
        time 10:00 20:00
    }
}

task prereq_open {
    name "Open Prerequisite"
    created 2026-11-01 07:00
    queued 2026-11-01 07:00
}

task prereq_done {
    name "Finished Prerequisite"
    created 2026-11-01 07:00
    queued 2026-11-01 07:00
    finished 2026-11-01 07:30
}

task wait_on_open {
    name "Blocked by open task"
    created 2026-11-01 08:00
    queued 2026-11-01 08:00
    blocked prereq_open
}

task wait_on_done {
    name "Unblocked because prereq is finished"
    created 2026-11-01 08:05
    queued 2026-11-01 08:05
    blocked prereq_done
}

task suspended_future {
    name "Suspended until tomorrow"
    created 2026-11-01 08:10
    queued 2026-11-01 08:10
    suspended 2026-11-02 09:00
}

task multi_label_or {
    name "Multi-label task (office OR weekend_home)"
    created 2026-11-01 08:15
    queued 2026-11-01 08:15
    labels office weekend_home
}

task override_day {
    name "Office task overridden to Sunday"
    created 2026-11-01 08:20
    queued 2026-11-01 08:20
    labels office
    condition day sun
}

task reset_day {
    name "Office task with day reset"
    created 2026-11-01 08:25
    queued 2026-11-01 08:25
    labels office
    condition day any
}

task reset_global {
    name "Office task with global condition any"
    created 2026-11-01 08:30
    queued 2026-11-01 08:30
    labels office
    condition any
}

task office_strict {
    name "Strict office task"
    created 2026-11-01 08:35
    queued 2026-11-01 08:35
    labels office
}
''';

      final sundayNoon = DateTime.utc(2026, 11, 1, 12, 0);
      final boardAtNoon = tdfService.parse(
        tdfWithConditions,
        evaluationTime: sundayNoon,
      );

      expect(
        boardAtNoon.blocked.map((task) => task.id),
        equals(['wait_on_open', 'suspended_future', 'office_strict']),
        reason: 'Tasks with unfinished prereqs, future suspension, or unmet inherited weekday condition must be Blocked',
      );
      expect(
        boardAtNoon.focus.map((task) => task.id),
        equals(['prereq_open', 'wait_on_done', 'multi_label_or']),
      );
      expect(
        boardAtNoon.ready.map((task) => task.id),
        equals(['override_day', 'reset_day', 'reset_global']),
        reason: 'override_day (day sun), reset_day (day any), and reset_global (condition any) must all be active on Sunday noon',
      );

      final sunday930 = DateTime.utc(2026, 11, 1, 9, 30);
      final boardAt930 = tdfService.parse(
        tdfWithConditions,
        evaluationTime: sunday930,
      );
      expect(
        boardAt930.blocked.map((task) => task.id),
        contains('multi_label_or'),
        reason: 'At Sunday 09:30, office fails day (mon..fri) and weekend_home fails time (10:00..20:00); per-label evaluation must not mix groups across labels',
      );
      expect(
        boardAt930.focus.followedBy(boardAt930.ready).map((task) => task.id),
        containsAll(['override_day', 'reset_day', 'reset_global']),
        reason: 'At Sunday 09:30, office time (09:00..17:00) is satisfied when day is overridden or reset',
      );

      final sundayLate = DateTime.utc(2026, 11, 1, 22, 0);
      final boardAtLate = tdfService.parse(
        tdfWithConditions,
        evaluationTime: sundayLate,
      );
      expect(
        boardAtLate.blocked.map((task) => task.id),
        containsAll(['override_day', 'reset_day']),
        reason: 'At Sunday 22:00, inherited office time (09:00..17:00) fails for override_day and reset_day',
      );
      expect(
        boardAtLate.focus.followedBy(boardAtLate.ready).map((task) => task.id),
        contains('reset_global'),
        reason: 'condition any must ignore all inherited label conditions even at 22:00',
      );

      final farGpsBoard = boardAtNoon.evaluateForContext(
        evaluationTime: sundayNoon,
        currentLatitude: 52.5200,
        currentLongitude: 13.4050,
      );
      expect(
        farGpsBoard.blocked.map((task) => task.id),
        containsAll(['override_day', 'reset_day']),
        reason: 'When device GPS coordinates are outside the 150m radius of office, inherited location condition must block the task',
      );
      expect(
        farGpsBoard.focus.followedBy(farGpsBoard.ready).map((task) => task.id),
        containsAll(['multi_label_or', 'reset_global']),
        reason: 'multi_label_or (via weekend_home without GPS) and reset_global (via condition any) must remain active when away from office',
      );

      final nearGpsBoard = boardAtNoon.evaluateForContext(
        evaluationTime: sundayNoon,
        currentLatitude: 50.9788,
        currentLongitude: 11.0329,
      );
      expect(
        nearGpsBoard.focus
            .followedBy(nearGpsBoard.ready)
            .map((task) => task.id),
        containsAll(['override_day', 'reset_day']),
        reason: 'When device GPS coordinates are within the 150m radius of office, inherited location condition must be satisfied',
      );

      final filteredWeekendHome = boardAtNoon.evaluateForContext(
        activeLabelId: 'weekend_home',
        evaluationTime: sundayNoon,
      );
      expect(
        filteredWeekendHome.allTasks.map((task) => task.id),
        equals(['multi_label_or']),
        reason: 'Section 5.1 label pre-filtering must restrict all 6 tiers to tasks referencing activeLabelId',
      );
    });

    test('sorts priority tasks ahead of regular FIFO tasks and preserves declaration order on ties', () {
      const sortingTdf = '''
tdf 0.2.0

task reg1 {
    name "Regular 1 (09:00)"
    created 2026-11-01 09:00
    queued 2026-11-01 09:00
}
task reg2 {
    name "Regular 2 (08:00 first)"
    created 2026-11-01 08:00
    queued 2026-11-01 08:00
}
task reg3 {
    name "Regular 3 (08:00 second)"
    created 2026-11-01 08:00
    queued 2026-11-01 08:00
}
task prio1 priority {
    name "Priority 1 (10:00)"
    created 2026-11-01 10:00
    queued 2026-11-01 10:00
}
task prio2 priority {
    name "Priority 2 (09:30)"
    created 2026-11-01 09:30
    queued 2026-11-01 09:30
}
''';

      final board = tdfService.parse(sortingTdf, evaluationTime: fixedDate);

      expect(
        board.focus.map((task) => task.id),
        equals(['prio2', 'prio1', 'reg2']),
        reason: 'Priority tasks ordered by queued must precede regular tasks ordered by queued',
      );
      expect(
        board.ready.map((task) => task.id),
        equals(['reg3', 'reg1']),
        reason: 'Tie between reg2 and reg3 at 08:00 must preserve declaration order',
      );
    });
  });

  group('TDF Section 6 State Transitions, Subtasks Auto-Finish & Retention GC', () {
    test(
      'fills Focus (limit 3) from Ready and Ready (limit 5) from Planned',
      () {
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
      },
    );

    test('Quick-Add to Planned cascades to Focus when board has capacity, and Priority sorts ahead of regular tasks', () {
      var board = TaskBoard.empty();
      board = board.addTask(
        'Task 1',
        targetTier: TaskTier.planned,
        currentDate: DateTime.utc(2026, 11, 1, 8, 0),
        id: 't001',
      );
      board = board.addTask(
        'Task 2',
        targetTier: TaskTier.planned,
        currentDate: DateTime.utc(2026, 11, 1, 8, 5),
        id: 't002',
      );
      board = board.addTask(
        'Task 3',
        targetTier: TaskTier.planned,
        currentDate: DateTime.utc(2026, 11, 1, 8, 10),
        id: 't003',
      );

      expect(
        board.focus.map((task) => task.id),
        equals(['t001', 't002', 't003']),
      );

      final updated = board.addTask(
        'Urgent Hotfix',
        targetTier: TaskTier.focus,
        isPriority: true,
        subtasksAutoFinish: true,
        subtasks: const [
          SubtaskItem(title: 'Patch vulnerability'),
          SubtaskItem(title: 'Verify regression tests', isCompleted: true),
        ],
        currentDate: DateTime.utc(2026, 11, 1, 8, 15),
        id: 't004',
      );

      expect(
        updated.focus.map((task) => task.id),
        equals(['t004', 't001', 't002']),
        reason: 'Priority task must sort to the top of Focus and push 3rd task to Ready',
      );
      expect(updated.ready.map((task) => task.id), equals(['t003']));

      final serialized = tdfService.serialize(updated);
      expect(serialized, contains('task t004 priority {'));
      expect(serialized, contains('subtasks auto-finish {'));
      expect(serialized, contains('step false "Patch vulnerability"'));
      expect(serialized, contains('step true "Verify regression tests"'));

      final reparsed = tdfService.parse(serialized, evaluationTime: fixedDate);
      expect(
        reparsed.focus.first.subtasks.map((subtask) => subtask.title),
        equals(['Patch vulnerability', 'Verify regression tests']),
      );
    });

    test('completes enclosing task automatically when subtasks has auto-finish and all steps become true', () {
      const autoFinishTdf = '''
tdf 0.2.0

task t_auto {
    name "Auto-finish task"
    created 2026-11-01 09:00
    queued 2026-11-01 09:00
    subtasks auto-finish {
        step true "Step 1"
        step false "Step 2"
    }
}
task t_manual {
    name "Manual finish task"
    created 2026-11-01 09:05
    queued 2026-11-01 09:05
    subtasks {
        step true "Step A"
        step false "Step B"
    }
}
''';

      var board = tdfService.parse(autoFinishTdf, evaluationTime: fixedDate);
      expect(
        board.focus.map((task) => task.id),
        equals(['t_auto', 't_manual']),
      );

      board = board.toggleSubtask('t_auto', 1, currentDate: fixedDate);
      expect(
        board.completed.map((task) => task.id),
        equals(['t_auto']),
        reason: 'Completing all steps in subtasks auto-finish must transition task to Completed',
      );
      expect(board.focus.map((task) => task.id), equals(['t_manual']));

      board = board.toggleSubtask('t_manual', 1, currentDate: fixedDate);
      expect(
        board.focus.map((task) => task.id),
        equals(['t_manual']),
        reason: 'Completing all steps without auto-finish must keep task open',
      );
    });

    test('completes active task, unblocks dependent tasks, prunes >30d completed tasks (29, 30, 31 day bounds), schedules Someday tasks (Section 6.2), and restores tasks (Section 6.5)', () {
      final board = TaskBoard(
        focus: [
          TaskItem(id: 'f1', title: 'Finish spec'),
          TaskItem(id: 'f2', title: 'Task 2'),
          TaskItem(id: 'f3', title: 'Task 3'),
        ],
        ready: [TaskItem(id: 'b1', title: 'Ready 1')],
        blocked: [
          TaskItem(
            id: 'dep1',
            title: 'Waiting on f1',
            queuedAt: DateTime.utc(2026, 11, 1, 9, 0),
            blockedByTaskIds: const ['f1'],
          ),
        ],
        someday: [TaskItem(id: 's1', title: 'Someday Idea')],
        completed: [
          TaskItem(
            id: 'e_keep_29',
            title: '29 Days Ago',
            isCompleted: true,
            completedAt: DateTime.utc(2026, 10, 3),
          ),
          TaskItem(
            id: 'e_keep_30',
            title: '30 Days Ago',
            isCompleted: true,
            completedAt: DateTime.utc(2026, 10, 2),
          ),
          TaskItem(
            id: 'e_prune_31',
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
      expect(
        afterComplete.ready.map((task) => task.id),
        equals(['dep1']),
        reason: 'Completing prerequisite f1 must automatically unblock dep1 into the active cycle',
      );
      expect(afterComplete.blocked, isEmpty);
      expect(
        afterComplete.completed.map((task) => task.title),
        equals(['Finish spec', '29 Days Ago', '30 Days Ago']),
        reason:
            '29 and 30 day old tasks must be kept while 31 day old is pruned',
      );

      final afterSchedule = afterComplete.scheduleTask(
        's1',
        currentDate: fixedDate,
      );
      expect(
        afterSchedule.someday,
        isEmpty,
        reason: 'scheduleTask must remove task from Someday',
      );
      expect(
        afterSchedule.ready.map((task) => task.id),
        equals(['dep1', 's1']),
        reason: 'Scheduled Someday task must enter the active queue',
      );

      final restoredToSomeday = afterSchedule.restoreTask(
        'f1',
        targetTier: TaskTier.someday,
        currentDate: fixedDate,
      );
      expect(
        restoredToSomeday.someday.map((task) => task.id),
        equals(['f1']),
        reason: 'Restoring to Someday must clear finished and queued and strip priority',
      );
      expect(restoredToSomeday.someday.single.queuedAt, isNull);
      expect(restoredToSomeday.someday.single.isPriority, isFalse);

      final restoredToFocus = afterSchedule.restoreTask(
        'f1',
        targetTier: TaskTier.focus,
        currentDate: fixedDate,
      );
      expect(
        restoredToFocus.focus.first.id,
        equals('f1'),
        reason: 'Restoring to Focus must set priority and place task at the top of Focus',
      );
      expect(restoredToFocus.focus.first.isPriority, isTrue);
    });

    test('executes Section 6.3 Focus-to-Ready (< 8 and >= 8 active tasks, priority alignment, +00:00:01 offset, collision shift) and Downgrade to Planned', () {
      final board = TaskBoard(
        focus: [
          TaskItem(id: 'f1', title: 'Focus 1 (Downgrade Me)', isPriority: true),
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
        equals(['Ready 2', 'Planned 1', 'Focus 1 (Downgrade Me)']),
      );
      expect(
        downgraded.findTask('f1')?.isPriority,
        isFalse,
        reason: 'Downgrading with < 8 active tasks must strip the priority flag per Section 6.3',
      );
      expect(
        downgraded.findTask('f1')?.queuedAt,
        equals(fixedDate),
        reason: 'Downgrading from Focus with < 8 active tasks must set queued to now per Section 6.3',
      );
      expect(downgraded.planned, isEmpty);

      final downgradedReadyUnder8 = downgraded.downgradeTask(
        'b2',
        currentDate: fixedDate.add(const Duration(minutes: 5)),
      );
      expect(
        downgradedReadyUnder8.ready.map((task) => task.id),
        equals(['g1', 'f1', 'b2']),
        reason: 'Downgrading Ready task when < 8 other active tasks exist must place it into the highest open Ready slot at the end of the regular queue',
      );
      expect(downgradedReadyUnder8.planned, isEmpty);

      final slot8Time = DateTime.utc(2026, 11, 1, 9, 0, 0);
      final collidingSlot9Time = DateTime.utc(2026, 11, 1, 9, 0, 1);
      final fullBoard = TaskBoard(
        focus: [
          TaskItem(
            id: 'f1',
            title: 'F1',
            isPriority: true,
            queuedAt: DateTime.utc(2026, 11, 1, 8, 0),
          ),
          TaskItem(
            id: 'f2',
            title: 'F2',
            queuedAt: DateTime.utc(2026, 11, 1, 8, 5),
          ),
          TaskItem(
            id: 'f3',
            title: 'F3',
            queuedAt: DateTime.utc(2026, 11, 1, 8, 10),
          ),
        ],
        ready: [
          TaskItem(
            id: 'r1',
            title: 'R1',
            queuedAt: DateTime.utc(2026, 11, 1, 8, 15),
          ),
          TaskItem(
            id: 'r2',
            title: 'R2',
            queuedAt: DateTime.utc(2026, 11, 1, 8, 20),
          ),
          TaskItem(
            id: 'r3',
            title: 'R3',
            queuedAt: DateTime.utc(2026, 11, 1, 8, 25),
          ),
          TaskItem(
            id: 'r4',
            title: 'R4',
            queuedAt: DateTime.utc(2026, 11, 1, 8, 30),
          ),
          TaskItem(id: 'r5', title: 'R5 (Slot 8)', queuedAt: slot8Time),
        ],
        planned: [
          TaskItem(
            id: 'p1',
            title: 'P1 (Colliding Slot 9)',
            queuedAt: collidingSlot9Time,
          ),
          TaskItem(
            id: 'p2',
            title: 'P2',
            queuedAt: DateTime.utc(2026, 11, 1, 9, 5),
          ),
        ],
      );

      final afterFocusDowngradeOnFullBoard = fullBoard.downgradeTask(
        'f1',
        currentDate: fixedDate,
      );
      expect(
        afterFocusDowngradeOnFullBoard.focus.map((task) => task.id),
        equals(['f2', 'f3', 'r1']),
        reason: 'r1 at slot 4 must advance into Focus slot 3',
      );
      expect(
        afterFocusDowngradeOnFullBoard.ready.map((task) => task.id),
        equals(['r2', 'r3', 'r4', 'r5', 'f1']),
        reason: 'Downgraded Focus task f1 must land at the end of Ready (slot 8) ahead of Planned tasks',
      );
      expect(
        afterFocusDowngradeOnFullBoard.findTask('f1')?.isPriority,
        isFalse,
        reason: 'Downgraded Focus task must remove priority when slot 8 is a regular task',
      );
      expect(
        afterFocusDowngradeOnFullBoard.findTask('f1')?.queuedAt,
        equals(DateTime.utc(2026, 11, 1, 9, 0, 1)),
        reason: 'Downgraded Focus task must receive slot_8.queued + 1 second (+00:00:01)',
      );
      expect(
        afterFocusDowngradeOnFullBoard.findTask('p1')?.queuedAt,
        equals(DateTime.utc(2026, 11, 1, 9, 0, 2)),
        reason: 'Colliding Planned task p1 at slot 9 must be shifted forward by +00:00:01 so f1 stays in Ready',
      );

      final allPriorityBoard = TaskBoard(
        focus: [
          TaskItem(
            id: 'pf1',
            title: 'PF1',
            isPriority: true,
            queuedAt: DateTime.utc(2026, 11, 1, 8, 0),
          ),
          TaskItem(
            id: 'pf2',
            title: 'PF2',
            isPriority: true,
            queuedAt: DateTime.utc(2026, 11, 1, 8, 5),
          ),
          TaskItem(
            id: 'pf3',
            title: 'PF3',
            isPriority: true,
            queuedAt: DateTime.utc(2026, 11, 1, 8, 10),
          ),
        ],
        ready: [
          TaskItem(
            id: 'pr1',
            title: 'PR1',
            isPriority: true,
            queuedAt: DateTime.utc(2026, 11, 1, 8, 15),
          ),
          TaskItem(
            id: 'pr2',
            title: 'PR2',
            isPriority: true,
            queuedAt: DateTime.utc(2026, 11, 1, 8, 20),
          ),
          TaskItem(
            id: 'pr3',
            title: 'PR3',
            isPriority: true,
            queuedAt: DateTime.utc(2026, 11, 1, 8, 25),
          ),
          TaskItem(
            id: 'pr4',
            title: 'PR4',
            isPriority: true,
            queuedAt: DateTime.utc(2026, 11, 1, 8, 30),
          ),
          TaskItem(
            id: 'pr5',
            title: 'PR5 (Priority Slot 8)',
            isPriority: true,
            queuedAt: slot8Time,
          ),
        ],
        planned: [
          TaskItem(
            id: 'pp1',
            title: 'PP1 (Priority Slot 9)',
            isPriority: true,
            queuedAt: collidingSlot9Time,
          ),
          TaskItem(
            id: 'reg_p2',
            title: 'Regular Planned Task',
            isPriority: false,
            queuedAt: DateTime.utc(2026, 11, 1, 8, 0),
          ),
        ],
      );

      final afterPriorityFocusDowngrade = allPriorityBoard.downgradeTask(
        'pf1',
        currentDate: fixedDate,
      );
      expect(
        afterPriorityFocusDowngrade.findTask('pf1')?.isPriority,
        isTrue,
        reason: 'When slot 8 carries priority, downgraded Focus task must retain priority per Section 6.3 Step 1',
      );
      expect(
        afterPriorityFocusDowngrade.findTask('pf1')?.queuedAt,
        equals(DateTime.utc(2026, 11, 1, 9, 0, 1)),
        reason: 'Downgraded priority Focus task must receive slot_8.queued + 00:00:01',
      );
      expect(
        afterPriorityFocusDowngrade.findTask('pp1')?.queuedAt,
        equals(DateTime.utc(2026, 11, 1, 9, 0, 2)),
        reason: 'Colliding priority task pp1 at slot 9 must be shifted to 09:00:02 per Section 6.3 Step 3',
      );
      expect(
        afterPriorityFocusDowngrade.findTask('reg_p2')?.queuedAt,
        equals(DateTime.utc(2026, 11, 1, 8, 0)),
        reason: 'Non-priority task in Planned belongs to a different sorting group and must not be shifted',
      );
      final reparsedPriorityDowngrade = tdfService.parse(
        tdfService.serialize(afterPriorityFocusDowngrade),
        evaluationTime: fixedDate,
      );
      expect(
        reparsedPriorityDowngrade.ready.map((task) => task.id),
        equals(['pr2', 'pr3', 'pr4', 'pr5', 'pf1']),
        reason: 'Reparsed TDF document must keep pf1 at Ready slot 8 ahead of pp1 in Planned',
      );
      expect(
        reparsedPriorityDowngrade.planned.map((task) => task.id),
        equals(['pp1', 'reg_p2']),
      );

      final afterReadyDowngrade = fullBoard.downgradeTask(
        'r1',
        currentDate: fixedDate,
      );
      expect(
        afterReadyDowngrade.ready.map((task) => task.id),
        equals(['r2', 'r3', 'r4', 'r5', 'p1']),
        reason: 'Task at position 9 (p1) must advance into position 8 (Ready)',
      );
      expect(
        afterReadyDowngrade.planned.map((task) => task.id),
        equals(['p2', 'r1']),
        reason: 'Downgraded Ready task must sort to the end of Planned',
      );
      expect(
        afterReadyDowngrade.findTask('r1')?.queuedAt,
        equals(fixedDate),
        reason: 'Downgrading Ready to Planned must set queued to now per Section 6.3',
      );

      final afterPlannedDowngrade = afterReadyDowngrade.downgradeTask(
        'p2',
        currentDate: fixedDate,
      );
      expect(
        afterPlannedDowngrade,
        equals(afterReadyDowngrade),
        reason: 'Downgrading a Planned task must be a no-op because only Focus and Ready can be downgraded',
      );
    });

    test(
      'Quick-Block moves task from Focus to Blocked and advances Ready upward',
      () {
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
      },
    );

    test('rejects empty and duplicate task titles in addTask and updateTask while updating all task fields and re-evaluating tiers', () {
      var board = TaskBoard(
        labels: const [
          TdfLabel(id: 'c_it', name: 'IT'),
          TdfLabel(id: 'c_ops', name: 'Ops'),
          TdfLabel(id: 'home', name: 'Home'),
          TdfLabel(id: 'office', name: 'Office'),
        ],
      );

      board = board.addTask(
        'Deploy cluster',
        note: 'Initial note',
        labelIds: const ['c_it', 'office'],
        currentDate: fixedDate,
        id: 't001',
      );
      board = board.addTask(
        'Audit firewall',
        currentDate: fixedDate.add(const Duration(minutes: 5)),
        id: 't002',
      );

      expect(
        board.hasDuplicateTaskTitle('  deploy cluster  '),
        isTrue,
        reason: 'hasDuplicateTaskTitle must detect case-insensitive duplicate titles',
      );
      expect(
        board.hasDuplicateTaskTitle('Deploy cluster', excludingTaskId: 't001'),
        isFalse,
        reason: 'hasDuplicateTaskTitle must ignore the task matching excludingTaskId',
      );

      final afterDuplicateAdd = board.addTask(
        'DEPLOY CLUSTER',
        currentDate: fixedDate,
      );
      expect(
        afterDuplicateAdd.allTasks.length,
        equals(2),
        reason: 'addTask must reject duplicate task titles',
      );

      final afterEmptyUpdate = board.updateTask(
        't001',
        title: '   ',
        currentDate: fixedDate,
      );
      expect(
        afterEmptyUpdate.findTask('t001')?.title,
        equals('Deploy cluster'),
        reason: 'updateTask must reject empty task titles',
      );

      final afterDuplicateUpdate = board.updateTask(
        't001',
        title: 'audit firewall',
        currentDate: fixedDate,
      );
      expect(
        afterDuplicateUpdate.findTask('t001')?.title,
        equals('Deploy cluster'),
        reason: 'updateTask must reject renaming a task to another existing task title',
      );

      final updatedSomeday = board.updateTask(
        't001',
        title: 'Deploy K8s cluster',
        note: 'Updated runbook',
        targetTier: TaskTier.someday,
        isPriority: false,
        labelIds: const ['c_ops', 'home'],
        subtasksAutoFinish: true,
        subtasks: const [
          SubtaskItem(title: 'Prepare nodes', isCompleted: true),
          SubtaskItem(title: 'Bootstrap control plane', isCompleted: false),
        ],
        currentDate: fixedDate,
      );

      expect(
        updatedSomeday.someday.map((task) => task.id),
        equals(['t001']),
        reason: 'Updating targetTier to Someday must move the task to Someday',
      );
      final editedTask = updatedSomeday.findTask('t001')!;
      expect(editedTask.title, equals('Deploy K8s cluster'));
      expect(editedTask.note, equals('Updated runbook'));
      expect(editedTask.labelIds, equals(['c_ops', 'home']));
      expect(editedTask.subtasksAutoFinish, isTrue);
      expect(editedTask.subtasks.length, equals(2));

      final promotedPriority = updatedSomeday.updateTask(
        't001',
        title: 'Deploy K8s cluster',
        note: '',
        targetTier: TaskTier.focus,
        isPriority: true,
        currentDate: fixedDate,
      );
      expect(
        promotedPriority.focus.first.id,
        equals('t001'),
        reason: 'Promoting edited task to Priority must place it at the top of Focus even when keeping its own title',
      );
      expect(
        promotedPriority.focus.first.note,
        isNull,
        reason: 'Updating note with empty string must clear the note',
      );
    });
  });

  group('TDF Section 7 Resource Bounds & Section 8 Error Conditions', () {
    test('rejects all mandatory syntax and schema error conditions in Section 8', () {
      void expectRawTdfError(
        String input,
        TdfErrorKind expectedKind, {
        int? expectedLine,
      }) {
        expect(
          () => tdfService.parse(input, evaluationTime: fixedDate),
          throwsA(
            isA<TdfException>()
                .having((error) => error.kind, 'kind', expectedKind)
                .having(
                  (error) => expectedLine == null ? null : error.line,
                  'line',
                  expectedLine,
                ),
          ),
          reason: 'Input must fail with $expectedKind',
        );
      }

      void expectTdfError(
        String bodyWithoutHeader,
        TdfErrorKind expectedKind, {
        int? expectedLine,
      }) {
        expectRawTdfError(
          'tdf 0.2.0\n$bodyWithoutHeader',
          expectedKind,
          expectedLine: expectedLine == null ? null : expectedLine + 1,
        );
      }

      expectRawTdfError('', TdfErrorKind.missingVersionHeader, expectedLine: 1);
      expectRawTdfError(
        '# comment only\n',
        TdfErrorKind.missingVersionHeader,
        expectedLine: 1,
      );
      expectRawTdfError(
        'tdf\n',
        TdfErrorKind.missingVersionHeader,
        expectedLine: 1,
      );
      expectRawTdfError(
        'label home {\n  name "Home"\n}',
        TdfErrorKind.missingVersionHeader,
        expectedLine: 1,
      );
      expectRawTdfError(
        'task t001 {\n  name "T"\n  created 2026-11-01\n}',
        TdfErrorKind.missingVersionHeader,
        expectedLine: 1,
      );
      expectRawTdfError(
        'tdf 0.1.0\n',
        TdfErrorKind.unsupportedVersion,
        expectedLine: 1,
      );
      expectRawTdfError(
        'tdf "0.2.0"\n',
        TdfErrorKind.unsupportedVersion,
        expectedLine: 1,
      );
      expectRawTdfError(
        'tdf 0.2.0 extra\n',
        TdfErrorKind.unsupportedVersion,
        expectedLine: 1,
      );

      expectTdfError(
        'tdf 0.2.0',
        TdfErrorKind.unexpectedRootDirective,
        expectedLine: 1,
      );
      expectTdfError(
        'name "Root Directive"',
        TdfErrorKind.unexpectedRootDirective,
        expectedLine: 1,
      );
      expectTdfError(
        'task t001 {\n  name "Test"\n  created 2026-11-01\n  queued\n}',
        TdfErrorKind.missingDirectiveArgument,
        expectedLine: 4,
      );
      expectTdfError(
        '"task" t001 {\n  name "Test"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidIdentifier,
        expectedLine: 1,
      );
      expectTdfError(
        'task t001 {\n  "name" "Test"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidIdentifier,
        expectedLine: 2,
      );
      expectTdfError(
        '123task t001 {\n  name "Test"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidIdentifier,
        expectedLine: 1,
      );
      expectTdfError(
        'task t001 {\n  -bad "Test"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidIdentifier,
        expectedLine: 2,
      );
      expectTdfError(
        'task t001{\n  name "Test"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidBlockHeader,
        expectedLine: 1,
      );
      expectTdfError(
        'task t001 {\n  name "Test"\n  created 2026-11-01\n  subtasks{\n  }\n}',
        TdfErrorKind.invalidBlockHeader,
        expectedLine: 4,
      );
      expectTdfError(
        'task t001 { extra\n  name "Test"\n  created 2026-11-01\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 1,
      );
      expectTdfError(
        'label empty_lbl {}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 1,
      );
      expectTdfError(
        'task t001 {\n  name "Test"\n  created 2026-11-01\n  subtasks {}\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 4,
      );
      expectTdfError(
        'task t001 {\n  name "Test"\n  created 2026-11-01\n} trailing',
        TdfErrorKind.unexpectedToken,
        expectedLine: 4,
      );
      expectTdfError(
        'task t001 {\n  name "Control\x07Char"\n  created 2026-11-01\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 2,
      );
      expectTdfError(
        '# comment with control char \x7F\n',
        TdfErrorKind.unexpectedToken,
        expectedLine: 1,
      );
      expectTdfError(
        'task t001 {\n  name "Test"\n  created 2026-11-01',
        TdfErrorKind.unclosedBlock,
      );
      expectTdfError('}', TdfErrorKind.unexpectedClosingBrace, expectedLine: 1);
      expectTdfError(
        'task t001 {\n  name "Unterminated\n  created 2026-11-01\n}',
        TdfErrorKind.unterminatedString,
        expectedLine: 2,
      );
      expectTdfError(
        "task t001 {\n  name 'Unterminated\n  created 2026-11-01\n}",
        TdfErrorKind.unterminatedString,
        expectedLine: 2,
      );
      expectTdfError(
        'task t001 {\n  name foo"bar"\n  created 2026-11-01\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 2,
      );
      expectTdfError(
        'task t001 {\n  name "foo"bar\n  created 2026-11-01\n}',
        TdfErrorKind.unexpectedToken,
        expectedLine: 2,
      );
      expectTdfError(
        'task t001 {\n  name "Bad \\x escape"\n  created 2026-11-01\n}',
        TdfErrorKind.invalidEscapeSequence,
        expectedLine: 2,
      );
      expectTdfError(
        'project p001 {\n  name "Unknown"\n}',
        TdfErrorKind.unknownBlockType,
        expectedLine: 1,
      );
      expectTdfError(
        'label l1 {\n  name "L1"\n  subtasks {\n    step false "Bad"\n  }\n}',
        TdfErrorKind.unknownBlockType,
        expectedLine: 3,
      );
      expectTdfError(
        'task t001 {\n  name "Test"\n  created 2026-11-01\n  unknown_dir 123\n}',
        TdfErrorKind.unknownDirective,
        expectedLine: 4,
      );
      expectTdfError(
        'task t001 {\n  name "Missing created"\n}',
        TdfErrorKind.missingRequiredDirective,
      );
      expectTdfError(
        'task t001 {\n  name "Empty subtasks"\n  created 2026-11-01\n  subtasks {\n  }\n}',
        TdfErrorKind.missingRequiredDirective,
        expectedLine: 5,
      );
      expectTdfError(
        'label l1 {\n  name "Empty condition block"\n  condition {\n  }\n}',
        TdfErrorKind.missingRequiredDirective,
        expectedLine: 4,
      );
      expectTdfError(
        'task t001 {\n  name "First"\n  name "Second"\n  created 2026-11-01\n}',
        TdfErrorKind.duplicateDirective,
        expectedLine: 3,
      );
      expectTdfError(
        'label l1 {\n  name "Dup condition blocks"\n  condition {\n    day mon\n  }\n  condition {\n    time 09:00 17:00\n  }\n}',
        TdfErrorKind.duplicateDirective,
        expectedLine: 6,
      );
      expectTdfError(
        'task t001 {\n  name "First"\n  created 2026-11-01\n}\ntask t001 {\n  name "Dup"\n  created 2026-11-01\n}',
        TdfErrorKind.duplicateIdentifier,
        expectedLine: 5,
      );
      expectTdfError(
        'label l1 {\n  name "First"\n}\nlabel l1 {\n  name "Dup"\n}',
        TdfErrorKind.duplicateIdentifier,
        expectedLine: 4,
      );
      expectTdfError(
        'task t001 {\n  name "Unknown label"\n  created 2026-11-01\n  labels missing_lbl\n}',
        TdfErrorKind.unknownLabelReference,
        expectedLine: 4,
      );
      expectTdfError(
        'task t001 {\n  name "Self blocked"\n  created 2026-11-01\n  blocked t001\n}',
        TdfErrorKind.circularDependency,
      );
      expectTdfError(
        'task t001 {\n  name "Cycle A"\n  created 2026-11-01\n  blocked t002\n}\n'
        'task t002 {\n  name "Cycle B"\n  created 2026-11-01\n  blocked t001\n}',
        TdfErrorKind.circularDependency,
      );
      expectTdfError(
        'task t001 {\n  name "Bad leap day"\n  created 2026-02-29\n}',
        TdfErrorKind.invalidTimestamp,
        expectedLine: 3,
      );
      expectTdfError(
        'task t001 {\n  name "Bad time"\n  created 2026-11-01 25:00\n}',
        TdfErrorKind.invalidTimestamp,
        expectedLine: 3,
      );
      expectTdfError(
        'task t001 {\n  name "Bad seconds"\n  created 2026-11-01 12:00:60\n}',
        TdfErrorKind.invalidTimestamp,
        expectedLine: 3,
      );
      expectTdfError(
        'task t001 {\n  name "Bad step bool"\n  created 2026-11-01\n  subtasks {\n    step yes "Sub"\n  }\n}',
        TdfErrorKind.invalidBoolean,
        expectedLine: 5,
      );
      expectTdfError(
        'label work {\n  name "Work"\n  condition location not_a_number 11.0 150\n}',
        TdfErrorKind.invalidNumber,
        expectedLine: 3,
      );
      expectTdfError(
        'label work {\n  name "Work"\n  color 4CAF50\n}',
        TdfErrorKind.invalidColor,
        expectedLine: 3,
      );
      expectTdfError(
        'label work {\n  name "Work"\n  color "#GGGGGG"\n}',
        TdfErrorKind.invalidColor,
        expectedLine: 3,
      );
      expectTdfError(
        'label work {\n  name "Work"\n  color "#12345"\n}',
        TdfErrorKind.invalidColor,
        expectedLine: 3,
      );
      expectTdfError(
        'task t001 {\n  name "Bad day"\n  created 2026-11-01\n  condition day funday\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 4,
      );
      expectTdfError(
        'task t001 {\n  name "Equal time window"\n  created 2026-11-01\n  condition time 09:00 09:00\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 4,
      );
      expectTdfError(
        'label work {\n  name "Bad lat"\n  condition location 95.0 11.0 150\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 3,
      );
      expectTdfError(
        'label work {\n  name "Bad lon"\n  condition location 50.0 -185.0 150\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 3,
      );
      expectTdfError(
        'label work {\n  name "Bad radius"\n  condition location 50.0 11.0 0\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 3,
      );
      expectTdfError(
        'label work {\n  name "Label reset forbidden"\n  condition any\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 3,
      );
      expectTdfError(
        'label work {\n  name "Label group reset forbidden"\n  condition day any\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 3,
      );
      expectTdfError(
        'task t001 {\n  name "Global reset mixed"\n  created 2026-11-01\n  condition any\n  condition day mon\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 5,
      );
      expectTdfError(
        'task t001 {\n  name "Group reset mixed"\n  created 2026-11-01\n  condition day any\n  condition day mon\n}',
        TdfErrorKind.invalidCondition,
        expectedLine: 5,
      );
    });

    test('enforces all Section 7 resource bounds before allocation', () {
      final overText = 'a' * (TdfService.maxTextLength + 1);
      expect(
        () => tdfService.parse(
          'tdf 0.2.0\ntask t001 {\n  name "$overText"\n  created 2026-11-01\n}',
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'name exceeding MAX_TEXT_LENGTH (500) must throw LimitExceeded',
      );

      final overNote = 'n' * (TdfService.maxNoteLength + 1);
      expect(
        () => tdfService.parse(
          'tdf 0.2.0\ntask t001 {\n  name "Valid"\n  note "$overNote"\n  created 2026-11-01\n}',
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason:
            'note exceeding MAX_NOTE_LENGTH (2000) must throw LimitExceeded',
      );

      final tooManyArgs = List.generate(
        TdfService.maxArgsPerStmt + 1,
        (index) => 'c$index',
      ).join(' ');
      expect(
        () => tdfService.parse(
          'tdf 0.2.0\ntask t001 {\n  name "Test"\n  created 2026-11-01\n  labels $tooManyArgs\n}',
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Directive exceeding MAX_ARGS_PER_STMT (64) must throw LimitExceeded',
      );

      expect(
        () => tdfService.parse(
          'tdf 0.2.0\ntask t001 {\n  name "Test"\n  created 2026-11-01\n  subtasks {\n    nested {\n    }\n  }\n}',
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Block nesting exceeding MAX_NESTING_DEPTH (2) must throw LimitExceeded',
      );

      final tooManyStmtsBuffer = StringBuffer(
        'tdf 0.2.0\ntask t001 {\n  name "Test"\n  created 2026-11-01\n  subtasks {\n',
      );
      for (var i = 0; i <= TdfService.maxStmtsPerBlock; i++) {
        tooManyStmtsBuffer.writeln('    step false "Step $i"');
      }
      tooManyStmtsBuffer.writeln('  }\n}');
      expect(
        () => tdfService.parse(tooManyStmtsBuffer.toString()),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Block exceeding MAX_STMTS_PER_BLOCK (512) must throw LimitExceeded',
      );

      final tooManyLines = List.filled(
        TdfService.maxLineCount + 1,
        '# comment',
      ).join('\n');
      expect(
        () => tdfService.parse(tooManyLines),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Document exceeding MAX_LINE_COUNT (16384) must throw LimitExceeded',
      );

      final tooManyBytes = '# ${'x' * TdfService.maxFileBytes}';
      expect(
        () => tdfService.parse(tooManyBytes),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Document exceeding MAX_FILE_BYTES (1 MiB) must throw LimitExceeded',
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
        );
        expect(
          AppLanguage.system.resolveLocale(const Locale('en', 'US')),
          equals(const Locale('en')),
        );
        expect(
          AppLanguage.system.resolveLocale(const Locale('fr', 'FR')),
          equals(const Locale('en')),
        );
        expect(
          AppLanguage.system.resolveLocale(null),
          equals(const Locale('en')),
        );
        expect(
          AppLanguage.english.resolveLocale(const Locale('de', 'DE')),
          equals(const Locale('en')),
        );
        expect(
          AppLanguage.german.resolveLocale(const Locale('en', 'US')),
          equals(const Locale('de')),
        );
        expect(AppLanguage.fromCode('de'), equals(AppLanguage.german));
        expect(AppLanguage.fromCode('en'), equals(AppLanguage.english));
        expect(AppLanguage.fromCode('unknown'), equals(AppLanguage.system));
      },
    );
  });

  group('Riverpod TaskNotifier & Native WebDavRepository (TDF)', () {
    late HttpServer server;
    String remoteTdfStore = '';
    String? lastAuthHeader;
    int putCount = 0;

    setUp(() async {
      remoteTdfStore = '''
tdf 0.2.0

task f1 {
    name "Remote Focus 1"
    created 2026-11-01 08:00
    queued 2026-11-01 08:00
}
task f2 {
    name "Remote Focus 2"
    created 2026-11-01 08:05
    queued 2026-11-01 08:05
}
task f3 {
    name "Remote Focus 3"
    created 2026-11-01 08:10
    queued 2026-11-01 08:10
}
task r1 {
    name "Remote Ready 1"
    created 2026-11-01 08:15
    queued 2026-11-01 08:15
}
task b1 {
    name "Remote Backlog 1"
    created 2026-11-01 08:20
    queued 2026-11-01 08:20
}
''';
      lastAuthHeader = null;
      putCount = 0;

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        lastAuthHeader = request.headers.value(HttpHeaders.authorizationHeader);
        if (request.method == 'GET') {
          request.response.statusCode = HttpStatus.ok;
          request.response.write(remoteTdfStore);
          await request.response.close();
        } else if (request.method == 'PUT') {
          putCount++;
          remoteTdfStore = await utf8.decoder.bind(request).join();
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

    test('fetches TDF via HTTP GET with Basic Auth, derives tiers, and syncs mutations via HTTP PUT', () async {
      final config = WebDavConfig(
        serverUrl: 'http://${server.address.host}:${server.port}',
        username: 'stefan',
        password: 'secret-app-password',
        filePath: 'tiertask.tdf',
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
      expect(updatedBoard.completed.first.title, equals('Remote Focus 1'));

      expect(putCount, greaterThanOrEqualTo(1));
      expect(remoteTdfStore, contains('tdf 0.2.0'));
      expect(remoteTdfStore, contains('task f1 {'));
      expect(remoteTdfStore, contains('finished 2026-11-01 12:00'));
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

      expect(enMessageKeys, contains('sectionReadyTasks'));
      expect(enMessageKeys, contains('sectionLabels'));
      expect(enMessageKeys, contains('drawerLabels'));
      expect(enMessageKeys, contains('emptyLabelsHint'));
      expect(enMessageKeys, isNot(contains('sectionCategories')));
      expect(enMessageKeys, isNot(contains('sectionLocations')));
      expect(enMessageKeys, isNot(contains('moveTaskTitle')));
      expect(enMessageKeys, isNot(contains('menuMoveTo')));
      expect(deMessageKeys, equals(enMessageKeys));

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
      );
      expect(
        linuxRunner,
        contains('gtk_window_set_title(window, "TierTask");'),
      );
      expect(linuxRunner, contains('g_set_application_name("TierTask");'));

      final windowsMain = File('windows/runner/main.cpp').readAsStringSync();
      expect(windowsMain, contains('window.Create(L"TierTask", origin, size)'));

      final windowsResource = File('windows/runner/Runner.rc')
          .readAsStringSync();
      expect(
        windowsResource,
        contains('VALUE "FileDescription", "TierTask" "\\0"'),
      );

      final androidManifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(androidManifest, contains('android:label="TierTask"'));
    });
  });

  group('AppThemeMode, StorageMode & WebDavConfig Resolution', () {
    test('resolves AppThemeMode and StorageMode codes with system and local tiertask.tdf defaults', () {
      expect(AppThemeMode.fromCode('light'), equals(AppThemeMode.light));
      expect(AppThemeMode.fromCode('DARK'), equals(AppThemeMode.dark));
      expect(AppThemeMode.fromCode('system'), equals(AppThemeMode.system));
      expect(AppThemeMode.fromCode('invalid'), equals(AppThemeMode.system));
      expect(AppThemeMode.fromCode(null), equals(AppThemeMode.system));

      expect(StorageMode.fromCode('local'), equals(StorageMode.local));
      expect(StorageMode.fromCode('webdav'), equals(StorageMode.webdav));
      expect(StorageMode.fromCode('BOTH'), equals(StorageMode.both));
      expect(StorageMode.fromCode(null), equals(StorageMode.local));

      const defaultConfig = WebDavConfig();
      expect(defaultConfig.themeMode, equals(AppThemeMode.system));
      expect(defaultConfig.storageMode, equals(StorageMode.local));
      expect(
        defaultConfig.localFilePath,
        equals('tiertask.tdf'),
        reason: 'Default localFilePath must be tiertask.tdf',
      );
      expect(
        defaultConfig.filePath,
        equals('tiertask.tdf'),
        reason: 'Default remote filePath must be tiertask.tdf',
      );
      expect(defaultConfig.showOpenTaskCount, isFalse);
      expect(defaultConfig.isConfigured, isTrue);
    });
  });

  group('LocalFileRepository & Persistent Local TDF Storage', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tiertask_local_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('reads and writes local .tdf files and rejects traversal or oversized payloads', () async {
      const config = WebDavConfig(
        localFilePath: 'custom_tasks.tdf',
        storageMode: StorageMode.local,
      );
      final repository = LocalFileRepository(
        config: config,
        baseDirectoryPath: tempDir.path,
        maxFileBytes: 256,
      );

      expect(
        await repository.loadTdf(),
        isEmpty,
        reason: 'Missing local TDF file must return empty string',
      );

      const sampleTdf =
          'tdf 0.2.0\ntask t001 {\n  name "Local Task"\n  created 2026-11-01 08:00\n  queued 2026-11-01 08:00\n}\n';
      await repository.saveTdf(sampleTdf);
      final loaded = await repository.loadTdf();
      expect(loaded, contains('name "Local Task"'));

      final traversalRepo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: '../escape.tdf'),
        baseDirectoryPath: tempDir.path,
      );
      await expectLater(
        traversalRepo.loadTdf,
        throwsA(isA<LocalFileException>()),
        reason: 'Relative parent traversal (..) must be rejected',
      );

      final nullByteRepo = LocalFileRepository(
        config: const WebDavConfig(localFilePath: 'bad\x00file.tdf'),
        baseDirectoryPath: tempDir.path,
      );
      await expectLater(
        nullByteRepo.saveTdf('content'),
        throwsA(isA<LocalFileException>()),
        reason: 'Null bytes in local file name must be rejected',
      );

      await expectLater(
        repository.saveTdf('A' * 300),
        throwsA(isA<LocalFileException>()),
        reason: 'Content exceeding maxFileBytes must be rejected before write',
      );
    });

    test('persists and reloads TDF tasks across container restarts in StorageMode.local and StorageMode.both', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      var remoteTdf = '';
      var remotePutCount = 0;
      server.listen((HttpRequest request) async {
        if (request.method == 'GET') {
          request.response.statusCode = remoteTdf.isEmpty
              ? HttpStatus.notFound
              : HttpStatus.ok;
          request.response.write(remoteTdf);
          await request.response.close();
        } else if (request.method == 'PUT') {
          remotePutCount++;
          remoteTdf = await utf8.decoder.bind(request).join();
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
        }
      });

      const localOnlyConfig = WebDavConfig(
        localFilePath: 'local_only.tdf',
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
          .addTask(
            'Persistent Local Task',
            isPriority: true,
            subtasks: const [SubtaskItem(title: 'First step')],
          );

      final localFile = File('${tempDir.path}/local_only.tdf');
      expect(
        await localFile.exists(),
        isTrue,
        reason: 'Local mode must persist local_only.tdf on disk',
      );
      final savedDiskContent = await localFile.readAsString();
      expect(savedDiskContent, contains('tdf 0.2.0'));
      expect(savedDiskContent, contains('name "Persistent Local Task"'));
      expect(savedDiskContent, contains('step false "First step"'));
      expect(remotePutCount, equals(0));

      final restartedContainer = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(localOnlyConfig),
          ),
          localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
          clockProvider.overrideWithValue(() => fixedDate),
        ],
      );
      addTearDown(restartedContainer.dispose);

      final reloadedBoard = await restartedContainer.read(
        taskNotifierProvider.future,
      );
      expect(
        reloadedBoard.focus.map((task) => task.title),
        equals(['Persistent Local Task']),
        reason: 'Reloaded container must restore task from local .tdf file',
      );
      expect(
        reloadedBoard.focus.first.subtasks.single.title,
        equals('First step'),
      );

      final bothConfig = WebDavConfig(
        serverUrl: 'http://${server.address.host}:${server.port}',
        username: 'stefan',
        password: 'secret',
        filePath: 'remote_both.tdf',
        localFilePath: 'both_mode.tdf',
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
          .addTask('Dual Synced TDF Task');

      final bothFile = File('${tempDir.path}/both_mode.tdf');
      expect(await bothFile.exists(), isTrue);
      expect(
        await bothFile.readAsString(),
        contains('name "Dual Synced TDF Task"'),
      );
      expect(remoteTdf, contains('name "Dual Synced TDF Task"'));
      expect(remotePutCount, greaterThanOrEqualTo(1));
    });
  });

  group('Labels Creation, Color Parsing, and Multi-Assignment', () {
    test('normalizes hex colors, parses/serializes label colors, and rejects duplicate label color directives', () {
      expect(
        TdfColor.normalizeHex('#4caf50'),
        equals('#4CAF50'),
        reason: 'Hex string with leading # must normalize to uppercase #RRGGBB',
      );
      expect(
        TdfColor.normalizeHex('  2196f3 '),
        equals('#2196F3'),
        reason:
            'Hex string without # must prepend # and normalize to uppercase',
      );
      expect(
        TdfColor.normalizeHex('#GGGGGG'),
        isNull,
        reason: 'Non-hex characters must be rejected',
      );
      expect(
        TdfColor.normalizeHex('#12345'),
        isNull,
        reason: '5-character hex string must be rejected',
      );
      expect(
        TdfColor.tryParseArgb('eb06ff'),
        equals(0xFFEB06FF),
        reason: 'Valid 6-digit hex must parse to opaque 32-bit ARGB int',
      );
      expect(
        TdfColor.formatArgb(0xFF00E5FF),
        equals('#00E5FF'),
        reason: '32-bit ARGB int must format to canonical #RRGGBB',
      );

      const labelWithColorTdf = '''
tdf 0.2.0

label office {
    name  "Main Office"
    color "#FF9100"
    note  "Downtown"
}
''';
      final parsed = tdfService.parse(
        labelWithColorTdf,
        evaluationTime: fixedDate,
      );
      expect(parsed.labels.single.id, equals('office'));
      expect(parsed.labels.single.name, equals('Main Office'));
      expect(
        parsed.labels.single.color,
        equals('#FF9100'),
        reason: 'Label block must parse optional color directive',
      );

      final serialized = tdfService.serialize(parsed);
      expect(
        serialized,
        contains('color "#FF9100"'),
        reason: 'Serializer must emit color directive for label block',
      );

      expect(
        () => tdfService.parse(
          'tdf 0.2.0\nlabel home {\n  name "Home"\n  color "#112233"\n  color "#445566"\n}',
          evaluationTime: fixedDate,
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.duplicateDirective,
          ),
        ),
        reason: 'Duplicate color directive in label block must fail',
      );
    });

    test('adds and deletes labels on TaskBoard and assigns multiple labels to tasks', () {
      var board = TaskBoard.empty();
      board = board.addLabel('IT & Servers', color: '2196f3');
      board = board.addLabel('IT & Servers', color: '#4CAF50');
      board = board.addLabel('   ', color: '#000000');
      board = board.addLabel('Home Office', color: 'ff9100');

      expect(
        board.labels.map((label) => label.id),
        equals(['l_it_servers', 'l_it_servers_2', 'l_home_office']),
        reason: 'Duplicate label names must generate distinct TDF identifiers',
      );
      expect(
        board.labels.first.color,
        equals('#2196F3'),
        reason: 'Label color must be normalized to #RRGGBB',
      );

      board = board.addTask(
        'Configure VPN router',
        currentDate: fixedDate,
        labelIds: const ['l_it_servers', 'l_home_office'],
      );

      expect(
        board.focus.single.labelIds,
        equals(['l_it_servers', 'l_home_office']),
        reason: 'Task must store multiple selected label IDs',
      );

      board = board.deleteLabel('l_it_servers');
      expect(
        board.labels.map((label) => label.id),
        equals(['l_it_servers_2', 'l_home_office']),
        reason: 'Deleting a label must remove it from board.labels',
      );
      expect(
        board.focus.single.labelIds,
        equals(['l_home_office']),
        reason: 'Deleting a label must strip its ID from referencing tasks',
      );

      expect(
        board.openTaskCountForLabel('l_home_office'),
        equals(1),
        reason:
            'openTaskCountForLabel must count open tasks referencing the label',
      );
      expect(
        board.openTaskCountForLabel('l_it_servers_2'),
        equals(0),
        reason: 'openTaskCountForLabel must return 0 when no open tasks reference the label',
      );

      board = board.renameLabel('l_home_office', '  Remote Work  ');
      expect(
        board.labels.map((label) => label.name),
        equals(['IT & Servers', 'Remote Work']),
        reason: 'renameLabel must update the trimmed display name of the matching label',
      );

      board = board.renameLabel('l_home_office', '   ');
      expect(
        board.labels.map((label) => label.name),
        equals(['IT & Servers', 'Remote Work']),
        reason: 'renameLabel must ignore empty or whitespace-only names',
      );
    });

    test('evaluateForContext derives top 3 Focus tasks for an active label while preserving all other filters', () {
      const multiLabelTdf = '''
tdf 0.2.0

label c_house {
    name "Household"
}
label c_it {
    name "IT"
}

task house_prio priority {
    name "Urgent roof repair"
    created 2026-11-01 11:00
    queued 2026-11-01 11:00
    labels c_house
}
task house_regular {
    name "Mow lawn"
    created 2026-11-01 07:30
    queued 2026-11-01 07:30
    labels c_house
}
task it_first {
    name "Patch database"
    created 2026-11-01 08:00
    queued 2026-11-01 08:00
    labels c_it
}
task it_second {
    name "Rotate TLS certificates"
    created 2026-11-01 08:30
    queued 2026-11-01 08:30
    labels c_it
}
task it_prio priority {
    name "Restore production cluster"
    created 2026-11-01 09:30
    queued 2026-11-01 09:30
    labels c_it
}
task it_fourth {
    name "Audit SSH keys"
    created 2026-11-01 10:00
    queued 2026-11-01 10:00
    labels c_it
}
task it_blocked_prereq {
    name "Deploy app after lawn"
    created 2026-11-01 08:05
    queued 2026-11-01 08:05
    labels c_it
    blocked house_regular
}
task it_suspended {
    name "Deferred hardware upgrade"
    created 2026-11-01 08:10
    queued 2026-11-01 08:10
    labels c_it
    suspended 2026-11-05 09:00
}
task it_wrong_day {
    name "Monday maintenance window"
    created 2026-11-01 08:15
    queued 2026-11-01 08:15
    labels c_it
    condition day mon
}
task it_someday {
    name "Evaluate Rust kernel module"
    created 2026-11-01 08:20
    labels c_it
}
task it_completed {
    name "Decommission old switch"
    created 2026-10-25 08:00
    queued 2026-10-25 08:00
    finished 2026-10-26 10:00
    labels c_it
}
''';

      final sundayNoon = DateTime.utc(2026, 11, 1, 12, 0);
      final globalBoard = tdfService.parse(
        multiLabelTdf,
        evaluationTime: sundayNoon,
      );

      expect(
        globalBoard.focus.map((task) => task.id),
        equals(['it_prio', 'house_prio', 'house_regular']),
        reason: 'Global Focus must contain top 3 tasks across all labels',
      );

      final itBoard = globalBoard.evaluateForContext(
        activeLabelId: 'c_it',
        evaluationTime: sundayNoon,
      );

      expect(
        itBoard.focus.map((task) => task.id),
        equals(['it_prio', 'it_first', 'it_second']),
        reason: 'Label c_it Focus must contain top 3 unblocked scheduled c_it tasks in priority then FIFO order',
      );
      expect(
        itBoard.ready.map((task) => task.id),
        equals(['it_fourth']),
        reason: '4th active c_it task must overflow into Ready when Focus has 3 tasks',
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
