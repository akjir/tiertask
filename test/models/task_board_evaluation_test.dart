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
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/services/tdf_service.dart';

void main() {
  const tdfService = TdfService();
  final fixedDate = DateTime.utc(2026, 11, 1, 12, 0);

  group('TDF Section 4.3 & Section 5 Dynamic 6-Tier Derivation, Condition Inheritance & Context Filtering', () {
    test('evaluates blocking conditions, group-level label condition inheritance, task overrides, group resets, global resets, Haversine GPS, and cohesive per-label OR logic', () {
      const tdfWithConditions = '''
tdf 0.5.0

queue {
    modified 2026-11-01 08:35:00
    task preopnOkD2
    task wtopenOkD2
    task wtdoneOkD2
    task susfutOkD2
    task multorOkD2
    task ovrdayOkD2
    task rstdayOkD2
    task rstglbOkD2
    task offstrOkD2
}

label officeOkD2 {
    name "Office"
    condition {
        day mon tue wed thu fri
        time 09:00 17:00
        location 50.9787 11.0328 150
    }
}
label wkhom0OkD2 {
    name "Weekend Home"
    condition {
        day sat sun
        time 10:00 20:00
    }
}

task preopnOkD2 {
    name "Open Prerequisite"
    created 2026-11-01 07:00
    queued 2026-11-01 07:00
}

task predonOkD2 {
    name "Finished Prerequisite"
    created 2026-11-01 07:00
    queued 2026-11-01 07:00
    finished 2026-11-01 07:30
    completions 1
}

task wtopenOkD2 {
    name "Blocked by open task"
    created 2026-11-01 08:00
    queued 2026-11-01 08:00
    blocked preopnOkD2
}

task wtdoneOkD2 {
    name "Unblocked because prereq is finished"
    created 2026-11-01 08:05
    queued 2026-11-01 08:05
    blocked predonOkD2
}

task susfutOkD2 {
    name "Suspended until tomorrow"
    created 2026-11-01 08:10
    queued 2026-11-01 08:10
    suspended 2026-11-02 09:00
}

task multorOkD2 {
    name "Multi-label task (office OR weekend_home)"
    created 2026-11-01 08:15
    queued 2026-11-01 08:15
    labels officeOkD2 wkhom0OkD2
}

task ovrdayOkD2 {
    name "Office task overridden to Sunday"
    created 2026-11-01 08:20
    queued 2026-11-01 08:20
    labels officeOkD2
    condition day sun
}

task rstdayOkD2 {
    name "Office task with day reset"
    created 2026-11-01 08:25
    queued 2026-11-01 08:25
    labels officeOkD2
    condition day any
}

task rstglbOkD2 {
    name "Office task with global condition any"
    created 2026-11-01 08:30
    queued 2026-11-01 08:30
    labels officeOkD2
    condition any
}

task offstrOkD2 {
    name "Strict office task"
    created 2026-11-01 08:35
    queued 2026-11-01 08:35
    labels officeOkD2
}
''';

      final sundayNoon = DateTime.utc(2026, 11, 1, 12, 0);
      final boardAtNoon = tdfService.parse(
        tdfWithConditions,
        evaluationTime: sundayNoon,
      );

      expect(
        boardAtNoon.blocked.map((task) => task.id),
        equals(['wtopenOkD2', 'susfutOkD2', 'offstrOkD2']),
        reason: 'Tasks with unfinished prereqs, future suspension, or unmet inherited weekday condition must be Blocked',
      );
      expect(
        boardAtNoon.focus.map((task) => task.id),
        equals(['preopnOkD2', 'wtdoneOkD2', 'multorOkD2']),
      );
      expect(
        boardAtNoon.ready.map((task) => task.id),
        equals(['ovrdayOkD2', 'rstdayOkD2', 'rstglbOkD2']),
        reason: 'ovrdayOkD2 (day sun), rstdayOkD2 (day any), and rstglbOkD2 (condition any) must all be active on Sunday noon',
      );

      final sunday930 = DateTime.utc(2026, 11, 1, 9, 30);
      final boardAt930 = tdfService.parse(
        tdfWithConditions,
        evaluationTime: sunday930,
      );
      expect(
        boardAt930.blocked.map((task) => task.id),
        contains('multorOkD2'),
        reason: 'At Sunday 09:30, office fails day (mon..fri) and weekend_home fails time (10:00..20:00); per-label evaluation must not mix groups across labels',
      );
      expect(
        boardAt930.focus.followedBy(boardAt930.ready).map((task) => task.id),
        containsAll(['ovrdayOkD2', 'rstdayOkD2', 'rstglbOkD2']),
        reason: 'At Sunday 09:30, office time (09:00..17:00) is satisfied when day is overridden or reset',
      );

      final sundayLate = DateTime.utc(2026, 11, 1, 22, 0);
      final boardAtLate = tdfService.parse(
        tdfWithConditions,
        evaluationTime: sundayLate,
      );
      expect(
        boardAtLate.blocked.map((task) => task.id),
        containsAll(['ovrdayOkD2', 'rstdayOkD2']),
        reason: 'At Sunday 22:00, inherited office time (09:00..17:00) fails for ovrdayOkD2 and rstdayOkD2',
      );
      expect(
        boardAtLate.focus.followedBy(boardAtLate.ready).map((task) => task.id),
        contains('rstglbOkD2'),
        reason: 'condition any must ignore all inherited label conditions even at 22:00',
      );

      final farGpsBoard = boardAtNoon.evaluateForContext(
        evaluationTime: sundayNoon,
        currentLatitude: 52.5200,
        currentLongitude: 13.4050,
      );
      expect(
        farGpsBoard.blocked.map((task) => task.id),
        containsAll(['ovrdayOkD2', 'rstdayOkD2']),
        reason: 'When device GPS coordinates are outside the 150m radius of office, inherited location condition must block the task',
      );
      expect(
        farGpsBoard.focus.followedBy(farGpsBoard.ready).map((task) => task.id),
        containsAll(['multorOkD2', 'rstglbOkD2']),
        reason: 'multorOkD2 (via weekend_home without GPS) and rstglbOkD2 (via condition any) must remain active when away from office',
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
        containsAll(['ovrdayOkD2', 'rstdayOkD2']),
        reason: 'When device GPS coordinates are within the 150m radius of office, inherited location condition must be satisfied',
      );

      final filteredWeekendHome = boardAtNoon.evaluateForContext(
        activeLabelId: 'wkhom0OkD2',
        evaluationTime: sundayNoon,
      );
      expect(
        filteredWeekendHome.allTasks.map((task) => task.id),
        equals(['multorOkD2']),
        reason: 'Section 5.1 label pre-filtering must restrict all 6 tiers to tasks referencing activeLabelId',
      );
    });

    test('does not evaluate conditions, prerequisites, or suspension for completed tasks in Section 5.2 and evaluates them upon restoration', () {
      const completedWithUnmetConditionsTdf = '''
tdf 0.5.0

queue {
    modified 2026-11-01 08:00:00
    task opnpreOkD2
}

label officeOkD2 {
    name "Office"
    condition {
        day mon tue wed thu fri
        time 09:00 17:00
        location 50.9787 11.0328 150
    }
}

task opnpreOkD2 {
    name "Open prerequisite"
    created 2026-11-01 08:00
    queued 2026-11-01 08:00
}

task donunmOkD2 priority {
    name "Completed with unmet conditions, prereq, and suspension"
    created 2026-10-25 08:00
    queued 2026-10-25 08:00
    finished 2026-11-01 09:00
    completions 1
    suspended 2026-11-05 09:00
    blocked opnpreOkD2
    labels officeOkD2
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
        equals(['donunmOkD2']),
        reason: 'Completed task with unmet day/time/location conditions, unfinished blocked prerequisite, and future suspended timestamp must remain in Completed (Section 5.2)',
      );
      expect(
        board.blocked,
        isEmpty,
        reason: 'Conditions of completed tasks must not be evaluated or place them into Blocked',
      );

      final filteredOffice = board.evaluateForContext(
        activeLabelId: 'officeOkD2',
        evaluationTime: sundayNoon,
        currentLatitude: 52.5200,
        currentLongitude: 13.4050,
      );
      expect(
        filteredOffice.completed.map((task) => task.id),
        equals(['donunmOkD2']),
        reason: 'Label-filtered view must include completed task matching activeLabelId without evaluating its unmet label conditions',
      );
      expect(filteredOffice.blocked, isEmpty);

      final filteredOtherLabel = board.evaluateForContext(
        activeLabelId: 'home00OkD2',
        evaluationTime: sundayNoon,
      );
      expect(
        filteredOtherLabel.completed,
        isEmpty,
        reason: 'Section 5.1 active label pre-filtering must still filter Completed tasks by label membership',
      );

      final restoredTime = DateTime.utc(2026, 11, 1, 16, 0);
      final restoredBoard = board.restoreTask(
        'donunmOkD2',
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
        equals(['donunmOkD2']),
        reason: 'Once restored to an open scheduled state, the task conditions must be evaluated again and classify it as Blocked when unmet',
      );
      final restoredTask = restoredBoard.findTask('donunmOkD2')!;
      expect(restoredTask.isCompleted, isFalse);
      expect(restoredTask.completedAt, isNull);
      expect(
        restoredTask.isPriority,
        isFalse,
        reason:
            'Restoring to Planned must strip the priority flag per Section 6.5',
      );
      expect(
        restoredBoard.queueTaskIds.last,
        equals('donunmOkD2'),
        reason:
            'Restoring to Planned must append task ID to queue per Section 6.5',
      );
    });

    test('sorts priority tasks ahead of regular FIFO tasks and preserves declaration order on ties', () {
      const sortingTdf = '''
tdf 0.5.0

queue {
    modified 2026-11-01 10:00:00
    task reg200OkD2
    task reg300OkD2
    task reg100OkD2
    task prio20OkD2
    task prio10OkD2
}

task reg100OkD2 {
    name "Regular 1 (09:00)"
    created 2026-11-01 09:00
    queued 2026-11-01 09:00
}
task reg200OkD2 {
    name "Regular 2 (08:00 first)"
    created 2026-11-01 08:00
    queued 2026-11-01 08:00
}
task reg300OkD2 {
    name "Regular 3 (08:00 second)"
    created 2026-11-01 08:00
    queued 2026-11-01 08:00
}
task prio10OkD2 priority {
    name "Priority 1 (10:00)"
    created 2026-11-01 10:00
    queued 2026-11-01 10:00
}
task prio20OkD2 priority {
    name "Priority 2 (09:30)"
    created 2026-11-01 09:30
    queued 2026-11-01 09:30
}
''';

      final board = tdfService.parse(sortingTdf, evaluationTime: fixedDate);

      expect(
        board.focus.map((task) => task.id),
        equals(['prio20OkD2', 'prio10OkD2', 'reg200OkD2']),
        reason: 'Priority tasks ordered by queued must precede regular tasks ordered by queued',
      );
      expect(
        board.ready.map((task) => task.id),
        equals(['reg300OkD2', 'reg100OkD2']),
        reason: 'Tie between reg200OkD2 and reg300OkD2 at 08:00 must preserve declaration order',
      );
    });

    test('evaluateForContext derives top 3 Focus tasks for an active label while preserving all other filters', () {
      const multiLabelTdf = '''
tdf 0.5.0

queue {
    modified 2026-11-01 11:00:00
    task hsreg0OkD2
    task it1st0OkD2
    task itblkdOkD2
    task itsuspOkD2
    task itwdayOkD2
    task it2nd0OkD2
    task itprioOkD2
    task it4th0OkD2
    task hsprioOkD2
}

label chouseOkD2 {
    name "Household"
}
label cit000OkD2 {
    name "IT"
}

task hsprioOkD2 priority {
    name "Urgent roof repair"
    created 2026-11-01 11:00
    queued 2026-11-01 11:00
    labels chouseOkD2
}
task hsreg0OkD2 {
    name "Mow lawn"
    created 2026-11-01 07:30
    queued 2026-11-01 07:30
    labels chouseOkD2
}
task it1st0OkD2 {
    name "Patch database"
    created 2026-11-01 08:00
    queued 2026-11-01 08:00
    labels cit000OkD2
}
task it2nd0OkD2 {
    name "Rotate TLS certificates"
    created 2026-11-01 08:30
    queued 2026-11-01 08:30
    labels cit000OkD2
}
task itprioOkD2 priority {
    name "Restore production cluster"
    created 2026-11-01 09:30
    queued 2026-11-01 09:30
    labels cit000OkD2
}
task it4th0OkD2 {
    name "Audit SSH keys"
    created 2026-11-01 10:00
    queued 2026-11-01 10:00
    labels cit000OkD2
}
task itblkdOkD2 {
    name "Deploy app after lawn"
    created 2026-11-01 08:05
    queued 2026-11-01 08:05
    labels cit000OkD2
    blocked hsreg0OkD2
}
task itsuspOkD2 {
    name "Deferred hardware upgrade"
    created 2026-11-01 08:10
    queued 2026-11-01 08:10
    labels cit000OkD2
    suspended 2026-11-05 09:00
}
task itwdayOkD2 {
    name "Monday maintenance window"
    created 2026-11-01 08:15
    queued 2026-11-01 08:15
    labels cit000OkD2
    condition day mon
}
task itsmdeOkD2 {
    name "Evaluate Rust kernel module"
    created 2026-11-01 08:20
    labels cit000OkD2
}
task itdoneOkD2 {
    name "Decommission old switch"
    created 2026-10-25 08:00
    queued 2026-10-25 08:00
    finished 2026-10-26 10:00
    completions 1
    labels cit000OkD2
}
''';

      final sundayNoon = DateTime.utc(2026, 11, 1, 12, 0);
      final globalBoard = tdfService.parse(
        multiLabelTdf,
        evaluationTime: sundayNoon,
      );

      expect(
        globalBoard.focus.map((task) => task.id),
        equals(['itprioOkD2', 'hsprioOkD2', 'hsreg0OkD2']),
        reason: 'Global Focus must contain top 3 tasks across all labels',
      );

      final itBoard = globalBoard.evaluateForContext(
        activeLabelId: 'cit000OkD2',
        evaluationTime: sundayNoon,
      );

      expect(
        itBoard.focus.map((task) => task.id),
        equals(['itprioOkD2', 'it1st0OkD2', 'it2nd0OkD2']),
        reason: 'Label cit000OkD2 Focus must contain top 3 unblocked scheduled tasks in priority then FIFO order',
      );
      expect(
        itBoard.ready.map((task) => task.id),
        equals(['it4th0OkD2']),
        reason:
            '4th active task must overflow into Ready when Focus has 3 tasks',
      );
    });

    test('evaluates condition day, condition time, and suspended against localEvaluationTime while keeping point-in-time timestamps and 30-day retention in UTC', () {
      const manualPlusTwo = WebDavConfig(
        timeZoneMode: AppTimeZoneMode.manual,
        manualTimeZoneOffsetMinutes: 120,
      );
      const manualMinusFive = WebDavConfig(
        timeZoneMode: AppTimeZoneMode.manual,
        manualTimeZoneOffsetMinutes: -300,
      );
      expect(WebDavConfig.formatUtcOffset(0), equals('UTC+00:00'));
      expect(WebDavConfig.formatUtcOffset(120), equals('UTC+02:00'));
      expect(WebDavConfig.formatUtcOffset(-330), equals('UTC-05:30'));

      final utcInstant = DateTime.utc(2026, 11, 1, 23, 30, 15, 999);
      expect(
        TaskItem.normalizeTimestamp(utcInstant),
        equals(DateTime.utc(2026, 11, 1, 23, 30, 15)),
        reason: 'normalizeTimestamp must truncate sub-second precision to UTC seconds',
      );
      expect(
        TaskItem.nextModifiedTimestamp(
          DateTime.utc(2026, 11, 1, 23, 30, 15),
          DateTime.utc(2026, 11, 1, 23, 30, 15),
        ),
        equals(DateTime.utc(2026, 11, 1, 23, 30, 16)),
        reason:
            'nextModifiedTimestamp must advance by +1s when now <= previous',
      );

      final localPlusTwo = manualPlusTwo.toLocalWallClock(utcInstant);
      expect(
        localPlusTwo,
        equals(DateTime.utc(2026, 11, 2, 1, 30, 15)),
        reason: '23:30 Sunday UTC in UTC+02:00 must convert to 01:30 Monday local wall-clock time',
      );
      expect(
        manualPlusTwo.localWallClockToUtc(localPlusTwo),
        equals(DateTime.utc(2026, 11, 1, 23, 30, 15)),
        reason: 'localWallClockToUtc must invert toLocalWallClock in manual timezone mode',
      );
      expect(
        manualMinusFive.toLocalWallClock(DateTime.utc(2026, 11, 1, 2, 0)),
        equals(DateTime.utc(2026, 10, 31, 21, 0)),
      );

      const wallClockTdf = '''
tdf 0.5.0

queue {
    modified 2026-11-01 20:05:00
    task monmrnOkD2
    task suslocOkD2
}

task monmrnOkD2 {
    name "Monday Early Task"
    created 2026-11-01 20:00
    queued 2026-11-01 20:00
    condition {
        day mon
        time 01:00 03:00
    }
}

task suslocOkD2 {
    name "Suspended Until Monday 01:00 Local"
    created 2026-11-01 20:00
    queued 2026-11-01 20:05
    suspended 2026-11-02 01:00
}
''';

      final boardInUtc = tdfService.parse(
        wallClockTdf,
        evaluationTime: DateTime.utc(2026, 11, 1, 23, 30),
        localEvaluationTime: DateTime.utc(2026, 11, 1, 23, 30),
      );
      expect(
        boardInUtc.blocked.map((task) => task.id),
        equals(['monmrnOkD2', 'suslocOkD2']),
        reason: 'At 23:30 Sunday wall-clock time, Monday condition and Monday 01:00 suspension must block both tasks',
      );

      final boardInPlusTwo = tdfService.parse(
        wallClockTdf,
        evaluationTime: DateTime.utc(2026, 11, 1, 23, 30),
        localEvaluationTime: localPlusTwo,
      );
      expect(
        boardInPlusTwo.focus.map((task) => task.id),
        equals(['monmrnOkD2']),
        reason: 'At 23:30 Sunday UTC, local wall-clock in UTC+02:00 is 01:30 Monday so monmrnOkD2 becomes active in Focus while suslocOkD2 (UTC 01:00 Monday) remains Blocked in UTC',
      );
      expect(
        boardInPlusTwo.blocked.map((task) => task.id),
        equals(['suslocOkD2']),
      );
    });

    test('evaluates TDF 0.6.0 scoped labels, ID-referenced locations, sortedLocations, and openTaskCountForLocation inheritance', () {
      const locOffice = TdfLocation(
        id: '7pQr9mOkD2',
        name: 'Office',
        latitude: 50.9787,
        longitude: 11.0328,
        radius: 150,
      );
      const locHome = TdfLocation(
        id: '3kLm8nOkD2',
        name: 'Home',
        latitude: 52.5200,
        longitude: 13.4050,
        radius: 200,
      );

      final lblScopedWeekend = TdfLabel(
        id: 'scpWk0OkD2',
        name: 'Scoped Weekend',
        isScoped: true,
        conditions: [
          DayTaskCondition(
            weekdays: const [DateTime.saturday, DateTime.sunday],
            dayTokens: const ['sat', 'sun'],
          ),
        ],
      );
      final lblWorkWeekday = TdfLabel(
        id: 'wrkDayOkD2',
        name: 'Work Weekday',
        conditions: [
          DayTaskCondition(
            weekdays: const [DateTime.monday],
            dayTokens: const ['mon'],
          ),
          LocationTaskCondition.fromIds(const ['7pQr9mOkD2']),
        ],
      );

      final sundayNoon = DateTime.utc(2026, 11, 1, 12, 0);
      final tasks = <TaskItem>[
        TaskItem(
          id: 'tScopedOnl',
          title: 'Scoped Only Task',
          createdAt: sundayNoon,
          labelIds: const ['scpWk0OkD2'],
        ),
        TaskItem(
          id: 'tMixedLbls',
          title: 'Mixed Scoped and Regular Label Task',
          createdAt: sundayNoon,
          labelIds: const ['scpWk0OkD2', 'wrkDayOkD2'],
        ),
        TaskItem(
          id: 'tOvrLocHom',
          title: 'Task Overriding Location to Home',
          createdAt: sundayNoon,
          labelIds: const ['wrkDayOkD2'],
          conditions: [
            const GroupResetTaskCondition(targetGroup: ConditionGroup.day),
            LocationTaskCondition.fromIds(const ['3kLm8nOkD2']),
          ],
        ),
        TaskItem(
          id: 'tRstLocAny',
          title: 'Task Resetting Location to Any',
          createdAt: sundayNoon,
          labelIds: const ['wrkDayOkD2'],
          conditions: const [
            GroupResetTaskCondition(targetGroup: ConditionGroup.day),
            GroupResetTaskCondition(targetGroup: ConditionGroup.location),
          ],
        ),
        TaskItem(
          id: 'tRstGlbAny',
          title: 'Task With Global Condition Any',
          createdAt: sundayNoon,
          labelIds: const ['wrkDayOkD2'],
          conditions: const [GlobalResetTaskCondition()],
        ),
      ];

      final globalBoard = TaskBoard.evaluate(
        tasks: tasks,
        labels: [lblScopedWeekend, lblWorkWeekday],
        locations: const [locOffice, locHome],
        evaluationTime: sundayNoon,
        localEvaluationTime: sundayNoon,
        currentLatitude: 52.5200,
        currentLongitude: 13.4050,
        queueBlock: TdfQueueBlock(
          modifiedAt: sundayNoon,
          taskIds: tasks.map((task) => task.id).toList(),
        ),
      );

      expect(
        globalBoard.sortedLocations.map((location) => location.id),
        equals(['3kLm8nOkD2', '7pQr9mOkD2']),
        reason: 'sortedLocations must sort case-insensitively by name (Home before Office)',
      );
      expect(globalBoard.findLocation('7pQr9mOkD2'), equals(locOffice));
      expect(globalBoard.findLocation('missingLoc'), isNull);

      final globalTierTaskIds = <TaskItem>[
        ...globalBoard.focus,
        ...globalBoard.ready,
        ...globalBoard.planned,
        ...globalBoard.blocked,
        ...globalBoard.someday,
        ...globalBoard.completed,
      ].map((task) => task.id);
      expect(
        globalTierTaskIds,
        isNot(contains('tScopedOnl')),
        reason: 'Section 5.1: Tasks whose assigned labels are all scoped must be excluded from all 6 tiers in the global view',
      );
      expect(
        globalBoard.findTask('tScopedOnl'),
        isNotNull,
        reason: 'Document model must retain scoped-only tasks in allTasks for serialization, search, and scoped label context evaluation',
      );
      expect(
        globalBoard.blocked.map((task) => task.id),
        contains('tMixedLbls'),
        reason: 'Section 4.4.3 Rule 4: In global view, scoped labels are ignored in L_global(T), so tMixedLbls evaluates only against wrkDayOkD2 (which fails on Sunday)',
      );
      expect(
        globalBoard.focus.map((task) => task.id),
        equals(['tOvrLocHom', 'tRstLocAny', 'tRstGlbAny']),
        reason: 'At Home GPS coordinates on Sunday, tOvrLocHom (day any + Home location), tRstLocAny (day any + location any), and tRstGlbAny (condition any) are all satisfied',
      );

      expect(
        globalBoard.openTaskCountForLocation('7pQr9mOkD2'),
        equals(1),
        reason: 'Only tMixedLbls inherits 7pQr9mOkD2 from wrkDayOkD2; tOvrLocHom overrides location, tRstLocAny resets location any, and tRstGlbAny has condition any',
      );
      expect(
        globalBoard.openTaskCountForLocation('3kLm8nOkD2'),
        equals(1),
        reason: 'tOvrLocHom directly references 3kLm8nOkD2',
      );
      expect(
        globalBoard.openTaskCountsByLocation,
        equals({'7pQr9mOkD2': 1, '3kLm8nOkD2': 1}),
      );

      final scopedView = globalBoard.evaluateForContext(
        activeLabelId: 'scpWk0OkD2',
        evaluationTime: sundayNoon,
        localEvaluationTime: sundayNoon,
      );
      expect(
        scopedView.focus.map((task) => task.id),
        equals(['tScopedOnl', 'tMixedLbls']),
        reason: 'When activeLabelId selects a scoped label, both tScopedOnl and tMixedLbls are included and satisfied on Sunday',
      );
    });
  });
}
