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
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/services/tdf_service.dart';

void main() {
  const tdfService = TdfService();
  final fixedDate = DateTime.utc(2026, 11, 1, 12, 0);

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

    test('does not evaluate conditions, prerequisites, or suspension for completed tasks in Section 5.2 and evaluates them upon restoration', () {
      const completedWithUnmetConditionsTdf = '''
tdf 0.2.0

label office {
    name "Office"
    condition {
        day mon tue wed thu fri
        time 09:00 17:00
        location 50.9787 11.0328 150
    }
}

task open_prereq {
    name "Open prerequisite"
    created 2026-11-01 08:00
    queued 2026-11-01 08:00
}

task done_with_unmet_conditions priority {
    name "Completed with unmet conditions, prereq, and suspension"
    created 2026-10-25 08:00
    queued 2026-10-25 08:00
    finished 2026-11-01 09:00
    suspended 2026-11-05 09:00
    blocked open_prereq
    labels office
    condition {
        day wed
        time 14:00 15:00
        location 48.1351 11.5820 100
    }
}
''';

      final sundayNoon = DateTime.utc(2026, 11, 1, 12, 0);
      final board = tdfService.parse(
        completedWithUnmetConditionsTdf,
        evaluationTime: sundayNoon,
        currentLatitude: 52.5200,
        currentLongitude: 13.4050,
      );

      expect(
        board.completed.map((task) => task.id),
        equals(['done_with_unmet_conditions']),
        reason: 'Completed task with unmet day/time/location conditions, unfinished blocked prerequisite, and future suspended timestamp must remain in Completed (Section 5.2)',
      );
      expect(
        board.blocked,
        isEmpty,
        reason: 'Conditions of completed tasks must not be evaluated or place them into Blocked',
      );

      final filteredOffice = board.evaluateForContext(
        activeLabelId: 'office',
        evaluationTime: sundayNoon,
        currentLatitude: 52.5200,
        currentLongitude: 13.4050,
      );
      expect(
        filteredOffice.completed.map((task) => task.id),
        equals(['done_with_unmet_conditions']),
        reason: 'Label-filtered view must include completed task matching activeLabelId without evaluating its unmet label conditions',
      );
      expect(filteredOffice.blocked, isEmpty);

      final filteredOtherLabel = board.evaluateForContext(
        activeLabelId: 'home',
        evaluationTime: sundayNoon,
      );
      expect(
        filteredOtherLabel.completed,
        isEmpty,
        reason: 'Section 5.1 active label pre-filtering must still filter Completed tasks by label membership',
      );

      final restoredTime = DateTime.utc(2026, 11, 1, 16, 0);
      final restoredBoard = board.restoreTask(
        'done_with_unmet_conditions',
        targetTier: TaskTier.planned,
        currentDate: restoredTime,
      );
      expect(
        restoredBoard.completed,
        isEmpty,
        reason: 'Restored task must leave Completed',
      );
      expect(
        restoredBoard.blocked.map((task) => task.id),
        equals(['done_with_unmet_conditions']),
        reason: 'Once restored to an open scheduled state, the task conditions must be evaluated again and classify it as Blocked when unmet',
      );
      final restoredTask = restoredBoard.findTask(
        'done_with_unmet_conditions',
      )!;
      expect(restoredTask.isCompleted, isFalse);
      expect(restoredTask.completedAt, isNull);
      expect(
        restoredTask.isPriority,
        isFalse,
        reason:
            'Restoring to Planned must strip the priority flag per Section 6.5',
      );
      expect(
        restoredTask.queuedAt,
        equals(restoredTime),
        reason: 'Restoring to Planned must set queued to now per Section 6.5',
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
