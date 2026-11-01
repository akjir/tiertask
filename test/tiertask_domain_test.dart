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

# === Locations (Draft) ===
location home {
    name "Home"
}

location work {
    name "Work"
    gps  50.9787 11.0328 150
}

# === Categories (Draft) ===
category c_house {
    name  "Household"
    color "#4CAF50"
}

category c_it {
    name  "IT & Servers"
    color "#2196F3"
}

# === Tasks ===

# Prioritized task -> Lands at the top of Focus (in c_it)
task t001 priority {
    name       "Verify server backup"
    note       "Inspect logs under /var/log/backup"
    created    2026-11-01 08:30
    queued     2026-11-01 08:30
    categories c_it
}

# Regular active task with subtasks -> Focus / Ready
task t002 {
    name       "Clean up study"
    created    2026-11-01 09:00
    queued     2026-11-01 09:15
    locations  home
    categories c_house

    subtasks auto-finish {
        step true  "Wipe desk"
        step false "Organize cables"
        step false "Empty trash bin"
    }
}

# Task in multiple categories with condition (weekends only)
task t003 {
    name       "Clean dust from NAS drives"
    created    2026-11-01 10:00
    queued     2026-11-01 10:00
    locations  home
    categories c_house c_it
    condition  day sat sun
}

# Blocked task (waits for t001 and is suspended until Nov 5)
task t004 {
    name       "Apply firewall update"
    created    2026-11-01 11:00
    queued     2026-11-01 11:00
    locations  work
    categories c_it
    blocked    t001
    suspended  2026-11-05 08:00
}

# Task in "Someday" (no 'queued' directive present)
task t005 {
    name       "3D-print custom NAS enclosure"
    created    2026-11-01 12:00
    categories c_it
}

# Completed task ('finished' is set -> deleted after 30 days)
task t006 {
    name       "Mount winter tires"
    created    2026-10-20 14:00
    queued     2026-10-21 08:00
    finished   2026-10-29 16:45
    locations  home
}
''';

      final board = tdfService.parse(canonicalTdf, evaluationTime: fixedDate);

      expect(
        board.locations.map((location) => location.id),
        equals(['home', 'work']),
        reason: 'Locations must be parsed in declaration order',
      );
      expect(board.locations[1].latitude, equals(50.9787));
      expect(board.locations[1].longitude, equals(11.0328));
      expect(board.locations[1].radiusMeters, equals(150.0));

      expect(
        board.categories.map((category) => category.id),
        equals(['c_house', 'c_it']),
        reason: 'Categories must be parsed in declaration order',
      );
      expect(board.categories[0].color, equals('#4CAF50'));
      expect(board.categories[1].color, equals('#2196F3'));

      expect(
        board.focus.map((task) => task.id),
        equals(['t001', 't002', 't003']),
        reason: 't001 (priority), t002, and t003 (active on Sunday) must fill Focus',
      );
      expect(board.focus[0].isPriority, isTrue);
      expect(board.focus[0].note, equals('Inspect logs under /var/log/backup'));
      expect(board.focus[1].subtasksAutoFinish, isTrue);
      expect(board.focus[1].subtasks.length, equals(3));
      expect(board.focus[1].subtasks[0].isCompleted, isTrue);
      expect(board.focus[1].subtasks[1].isCompleted, isFalse);

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
      final reparsed = tdfService.parse(serialized, evaluationTime: fixedDate);
      expect(
        reparsed.focus.map((task) => task.id),
        equals(['t001', 't002', 't003']),
      );
      expect(reparsed.blocked.map((task) => task.id), equals(['t004']));
      expect(reparsed.someday.map((task) => task.id), equals(['t005']));
      expect(reparsed.completed.map((task) => task.id), equals(['t006']));
    });

    test('supports bare words, double-quoted escapes, single-quoted raw strings, inline comments, CRLF, and empty blocks', () {
      expect(
        () => tdfService.parse('location empty_loc {}'),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.missingRequiredDirective,
          ),
        ),
        reason: 'Empty location block without mandatory name must fail',
      );

      const validInlineSubtasks =
          'category c_dev { # comment\r\n'
          '  name \'Raw "quote" and \\\\backslash\'\r\n'
          '  note "Line1\\nLine2\\tTabbed\\rReturn\\\\Slash\\"Quote"\r\n'
          '}#comment\r\n'
          'task taxes2026 {#comment\r\n'
          '  name "File taxes #2026"#comment\r\n'
          '  created 2026-11-01#inline_date_comment\r\n'
          '  queued 2026-11-01 08:00\r\n'
          '  categories c_dev#inline_id_comment\r\n'
          '  subtasks {}\r\n'
          '}';

      final board = tdfService.parse(
        validInlineSubtasks,
        evaluationTime: fixedDate,
      );
      expect(board.categories.single.id, equals('c_dev'));
      expect(
        board.categories.single.name,
        equals('Raw "quote" and \\\\backslash'),
        reason: 'Single-quoted strings must preserve backslashes and quotes',
      );
      expect(
        board.categories.single.note,
        equals('Line1\nLine2\tTabbed\rReturn\\Slash"Quote'),
        reason: 'Double-quoted strings must unescape \\n, \\t, \\r, \\\\, \\"',
      );
      expect(board.focus.single.id, equals('taxes2026'));
      expect(board.focus.single.title, equals('File taxes #2026'));
      expect(
        board.focus.single.createdAt,
        equals(DateTime.utc(2026, 11, 1, 0, 0)),
        reason: 'Date-only timestamp must default time component to 00:00',
      );

      final serialized = tdfService.serialize(board);
      final reparsed = tdfService.parse(serialized, evaluationTime: fixedDate);
      expect(
        reparsed.categories.single.note,
        equals('Line1\nLine2\tTabbed\rReturn\\Slash"Quote'),
      );
    });

    test(
      'accepts empty or comment-only documents as valid empty TaskBoard',
      () {
        expect(tdfService.parse('').focus, isEmpty);
        expect(
          tdfService.parse('   \t  \n# only comment\r\n  # another').focus,
          isEmpty,
        );
      },
    );
  });

  group('TDF Section 5 Dynamic 6-Tier Derivation & Context Filtering', () {
    test('evaluates blocking conditions (blocked, suspended, condition day/time) and context filters', () {
      const tdfWithConditions = '''
location home {
    name "Home"
}
location office {
    name "Office"
}
category c_work {
    name "Work"
}
category c_home {
    name "Home"
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

task suspended_past {
    name "Suspension already expired"
    created 2026-11-01 08:15
    queued 2026-11-01 08:15
    suspended 2026-11-01 10:00
}

task cond_weekday_only {
    name "Monday only task"
    created 2026-11-01 08:20
    queued 2026-11-01 08:20
    condition day mon
}

task cond_sunday_window {
    name "Sunday daytime task"
    created 2026-11-01 08:25
    queued 2026-11-01 08:25
    condition day sun
    condition time 09:00 17:00
    locations home
    categories c_home
}

task cond_outside_window {
    name "Sunday late night task"
    created 2026-11-01 08:30
    queued 2026-11-01 08:30
    condition day sun
    condition time 20:00 22:00
}
''';

      final sundayNoon = DateTime.utc(2026, 11, 1, 12, 0);
      final board = tdfService.parse(
        tdfWithConditions,
        evaluationTime: sundayNoon,
      );

      expect(
        board.blocked.map((task) => task.id),
        equals([
          'wait_on_open',
          'suspended_future',
          'cond_weekday_only',
          'cond_outside_window',
        ]),
        reason: 'Tasks with unfinished prereqs, future suspension, or unmet day/time conditions must be Blocked',
      );
      expect(
        board.focus.map((task) => task.id),
        equals(['prereq_open', 'wait_on_done', 'suspended_past']),
        reason: 'First 3 unblocked scheduled tasks must fill Focus',
      );
      expect(
        board.ready.map((task) => task.id),
        equals(['cond_sunday_window']),
        reason: '4th unblocked scheduled task must land in Ready',
      );

      final filteredHome = tdfService.parse(
        tdfWithConditions,
        evaluationTime: sundayNoon,
        activeCategoryId: 'c_home',
        activeLocationId: 'home',
      );
      expect(
        filteredHome.focus.map((task) => task.id),
        equals(['cond_sunday_window']),
        reason: 'Context filter for category c_home and location home must select matching task',
      );
    });

    test('sorts priority tasks ahead of regular FIFO tasks and preserves declaration order on ties', () {
      const sortingTdf = '''
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

    test('completes active task, unblocks dependent tasks, prunes >30d completed tasks (29, 30, 31 day bounds), and restores tasks', () {
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

      final restored = afterComplete.restoreTask(
        'f1',
        TaskTier.someday,
        currentDate: fixedDate,
      );
      expect(restored.someday.map((task) => task.id), equals(['f1']));
      expect(restored.someday.first.isCompleted, isFalse);
      expect(restored.someday.first.completedAt, isNull);
      expect(restored.someday.first.queuedAt, isNull);
    });

    test('executes Section 6.4 Minor Downgrade (Focus -> End of Ready) and Section 6.3 Full Downgrade (Ready -> Planned)', () {
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
        equals(['Ready 2', 'Focus 1 (Downgrade Me)', 'Planned 1']),
      );
      expect(
        downgraded.findTask('f1')?.isPriority,
        isFalse,
        reason: 'Downgrading must strip the priority flag per Section 6.4',
      );
      expect(downgraded.planned, isEmpty);

      final fullBoard = TaskBoard(
        focus: [
          TaskItem(id: 'f1', title: 'F1'),
          TaskItem(id: 'f2', title: 'F2'),
          TaskItem(id: 'f3', title: 'F3'),
        ],
        ready: [
          TaskItem(id: 'r1', title: 'R1 (Downgrade to Planned)'),
          TaskItem(id: 'r2', title: 'R2'),
          TaskItem(id: 'r3', title: 'R3'),
          TaskItem(id: 'r4', title: 'R4'),
          TaskItem(id: 'r5', title: 'R5'),
        ],
        planned: [
          TaskItem(id: 'p1', title: 'P1 (Advance to Ready)'),
          TaskItem(id: 'p2', title: 'P2'),
        ],
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
  });

  group('TDF Section 7 Resource Bounds & Section 8 Error Conditions', () {
    test('rejects all mandatory syntax and schema error conditions in Section 8', () {
      void expectTdfError(
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
        'task t001 {\n  name "Test"\n  created 2026-11-01\n} trailing',
        TdfErrorKind.unexpectedToken,
        expectedLine: 4,
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
        'task t001 {\n  name "Test"\n  created 2026-11-01\n  unknown_dir 123\n}',
        TdfErrorKind.unknownDirective,
        expectedLine: 4,
      );
      expectTdfError(
        'task t001 {\n  name "Missing created"\n}',
        TdfErrorKind.missingRequiredDirective,
      );
      expectTdfError(
        'task t001 {\n  name "First"\n  name "Second"\n  created 2026-11-01\n}',
        TdfErrorKind.duplicateDirective,
        expectedLine: 3,
      );
      expectTdfError(
        'task t001 {\n  name "First"\n  created 2026-11-01\n}\ntask t001 {\n  name "Dup"\n  created 2026-11-01\n}',
        TdfErrorKind.duplicateIdentifier,
        expectedLine: 5,
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
        'task t001 {\n  name "Bad step bool"\n  created 2026-11-01\n  subtasks {\n    step yes "Sub"\n  }\n}',
        TdfErrorKind.invalidBoolean,
        expectedLine: 5,
      );
      expectTdfError(
        'location work {\n  name "Work"\n  gps not_a_number 11.0\n}',
        TdfErrorKind.invalidNumber,
        expectedLine: 3,
      );
    });

    test('enforces all Section 7 resource bounds before allocation', () {
      final overText = 'a' * (TdfService.maxTextLength + 1);
      expect(
        () => tdfService.parse(
          'task t001 {\n  name "$overText"\n  created 2026-11-01\n}',
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

      final tooManyArgs = List.generate(
        TdfService.maxArgsPerStmt + 1,
        (index) => 'c$index',
      ).join(' ');
      expect(
        () => tdfService.parse(
          'task t001 {\n  name "Test"\n  created 2026-11-01\n  categories $tooManyArgs\n}',
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
          'task t001 {\n  name "Test"\n  created 2026-11-01\n  subtasks {\n    nested {\n    }\n  }\n}',
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
        'task t001 {\n  name "Test"\n  created 2026-11-01\n  subtasks {\n',
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

      expect(enMessageKeys, contains('moveTaskTitle'));
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
          'task t001 {\n  name "Local Task"\n  created 2026-11-01 08:00\n  queued 2026-11-01 08:00\n}\n';
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

  group(
    'Locations & Categories Creation, Color Parsing, and Multi-Assignment',
    () {
      test('normalizes hex colors, parses/serializes location colors, and rejects duplicate location color directives', () {
        expect(
          TdfColor.normalizeHex('#4caf50'),
          equals('#4CAF50'),
          reason:
              'Hex string with leading # must normalize to uppercase #RRGGBB',
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

        const locationWithColorTdf = '''
location office {
    name  "Main Office"
    color "#FF9100"
    note  "Downtown"
}
''';
        final parsed = tdfService.parse(
          locationWithColorTdf,
          evaluationTime: fixedDate,
        );
        expect(parsed.locations.single.id, equals('office'));
        expect(parsed.locations.single.name, equals('Main Office'));
        expect(
          parsed.locations.single.color,
          equals('#FF9100'),
          reason: 'Location block must parse optional color directive',
        );

        final serialized = tdfService.serialize(parsed);
        expect(
          serialized,
          contains('color "#FF9100"'),
          reason: 'Serializer must emit color directive for location block',
        );

        expect(
          () => tdfService.parse(
            'location home {\n  name "Home"\n  color "#112233"\n  color "#445566"\n}',
            evaluationTime: fixedDate,
          ),
          throwsA(
            isA<TdfException>().having(
              (error) => error.kind,
              'kind',
              TdfErrorKind.duplicateDirective,
            ),
          ),
          reason: 'Duplicate color directive in location block must fail',
        );
      });

      test('adds and deletes categories and locations on TaskBoard and assigns multiple locations and categories to tasks', () {
        var board = TaskBoard.empty();
        board = board.addCategory('IT & Servers', color: '2196f3');
        board = board.addCategory('IT & Servers', color: '#4CAF50');
        board = board.addCategory('   ', color: '#000000');
        board = board.addLocation('Home Office', color: 'ff9100');
        board = board.addLocation('Client Site', color: '#00E5FF');

        expect(
          board.categories.map((category) => category.id),
          equals(['c_it_servers', 'c_it_servers_2']),
          reason:
              'Duplicate category names must generate distinct TDF identifiers',
        );
        expect(
          board.categories.first.color,
          equals('#2196F3'),
          reason: 'Category color must be normalized to #RRGGBB',
        );
        expect(
          board.locations.map((location) => location.id),
          equals(['l_home_office', 'l_client_site']),
          reason: 'Location names must generate valid TDF identifiers',
        );
        expect(
          board.locations.first.color,
          equals('#FF9100'),
          reason: 'Location color must be normalized to #RRGGBB',
        );

        board = board.addTask(
          'Configure VPN router',
          currentDate: fixedDate,
          categoryIds: const ['c_it_servers', 'c_it_servers_2'],
          locationIds: const ['l_home_office', 'l_client_site'],
        );

        expect(
          board.focus.single.categoryIds,
          equals(['c_it_servers', 'c_it_servers_2']),
          reason: 'Task must store multiple selected category IDs',
        );
        expect(
          board.focus.single.locationIds,
          equals(['l_home_office', 'l_client_site']),
          reason: 'Task must store multiple selected location IDs',
        );

        board = board.deleteCategory('c_it_servers');
        expect(
          board.categories.map((category) => category.id),
          equals(['c_it_servers_2']),
          reason: 'Deleting a category must remove it from board.categories',
        );
        expect(
          board.focus.single.categoryIds,
          equals(['c_it_servers_2']),
          reason:
              'Deleting a category must strip its ID from referencing tasks',
        );

        board = board.deleteLocation('l_home_office');
        expect(
          board.locations.map((location) => location.id),
          equals(['l_client_site']),
          reason: 'Deleting a location must remove it from board.locations',
        );
        expect(
          board.focus.single.locationIds,
          equals(['l_client_site']),
          reason:
              'Deleting a location must strip its ID from referencing tasks',
        );
      });

      test('evaluateForContext derives top 3 Focus tasks for a category while preserving all other filters', () {
        const multiCategoryTdf = '''
location home {
    name "Home"
}
location office {
    name "Office"
}
category c_house {
    name "Household"
}
category c_it {
    name "IT"
}

task house_prio priority {
    name "Urgent roof repair"
    created 2026-11-01 11:00
    queued 2026-11-01 11:00
    categories c_house
}
task house_regular {
    name "Mow lawn"
    created 2026-11-01 07:30
    queued 2026-11-01 07:30
    categories c_house
}
task it_first {
    name "Patch database"
    created 2026-11-01 08:00
    queued 2026-11-01 08:00
    categories c_it
    locations office
}
task it_second {
    name "Rotate TLS certificates"
    created 2026-11-01 08:30
    queued 2026-11-01 08:30
    categories c_it
}
task it_prio priority {
    name "Restore production cluster"
    created 2026-11-01 09:30
    queued 2026-11-01 09:30
    categories c_it
    locations office
}
task it_fourth {
    name "Audit SSH keys"
    created 2026-11-01 10:00
    queued 2026-11-01 10:00
    categories c_it
}
task it_blocked_prereq {
    name "Deploy app after lawn"
    created 2026-11-01 08:05
    queued 2026-11-01 08:05
    categories c_it
    blocked house_regular
}
task it_suspended {
    name "Deferred hardware upgrade"
    created 2026-11-01 08:10
    queued 2026-11-01 08:10
    categories c_it
    suspended 2026-11-05 09:00
}
task it_wrong_day {
    name "Monday maintenance window"
    created 2026-11-01 08:15
    queued 2026-11-01 08:15
    categories c_it
    condition day mon
}
task it_someday {
    name "Evaluate Rust kernel module"
    created 2026-11-01 08:20
    categories c_it
}
task it_completed {
    name "Decommission old switch"
    created 2026-10-25 08:00
    queued 2026-10-25 08:00
    finished 2026-10-26 10:00
    categories c_it
}
''';

        final sundayNoon = DateTime.utc(2026, 11, 1, 12, 0);
        final globalBoard = tdfService.parse(
          multiCategoryTdf,
          evaluationTime: sundayNoon,
        );

        expect(
          globalBoard.focus.map((task) => task.id),
          equals(['it_prio', 'house_prio', 'house_regular']),
          reason: 'Global Focus must contain top 3 tasks across all categories',
        );

        final itBoard = globalBoard.evaluateForContext(
          activeCategoryId: 'c_it',
          evaluationTime: sundayNoon,
        );

        expect(
          itBoard.focus.map((task) => task.id),
          equals(['it_prio', 'it_first', 'it_second']),
          reason: 'Category c_it Focus must contain top 3 unblocked scheduled c_it tasks in priority then FIFO order',
        );
        expect(
          itBoard.ready.map((task) => task.id),
          equals(['it_fourth']),
          reason: '4th active c_it task must overflow into Ready when Focus has 3 tasks',
        );

        final itHomeBoard = globalBoard.evaluateForContext(
          activeCategoryId: 'c_it',
          activeLocationId: 'home',
          evaluationTime: sundayNoon,
        );
        expect(
          itHomeBoard.focus.map((task) => task.id),
          equals(['it_second', 'it_fourth']),
          reason: 'Combining category c_it and location home must keep location-independent tasks and exclude office-only tasks',
        );
      });
    },
  );
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
