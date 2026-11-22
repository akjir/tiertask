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
import 'package:tiertask/models/task_board_evaluator.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/services/tdf_service.dart';

void main() {
  const tdfService = TdfService();
  final fixedDate = DateTime.utc(2026, 11, 1, 12);

  group('TDF Section 4.3 & Section 5 Dynamic 6-Tier Derivation, Condition Inheritance & Context Filtering', () {
    test('evaluates blocking conditions, group-level label condition inheritance, task overrides, group resets, global resets, Haversine GPS, and cohesive per-label OR logic', () {
      const tdfWithConditions = '''
tdf 0.8.0

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

location locOffOkD2 {
    name "Office"
    coordinates 50.9787 11.0328
    radius 150
}

label officeOkD2 {
    name "Office"
    condition {
        day mon tue wed thu fri
        time 09:00 17:00
        location locOffOkD2
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
}

task predonOkD2 {
    name "Finished Prerequisite"
    created 2026-11-01 07:00
    finished 2026-11-01 07:30
    completions 1
}

task wtopenOkD2 {
    name "Blocked by open task"
    created 2026-11-01 08:00
    blocked preopnOkD2
}

task wtdoneOkD2 {
    name "Unblocked because prereq is finished"
    created 2026-11-01 08:05
    blocked predonOkD2
}

task susfutOkD2 {
    name "Suspended until tomorrow"
    created 2026-11-01 08:10
    suspended 2026-11-02 09:00
}

task multorOkD2 {
    name "Multi-label task (office OR weekend_home)"
    created 2026-11-01 08:15
    labels officeOkD2 wkhom0OkD2
}

task ovrdayOkD2 {
    name "Office task overridden to Sunday"
    created 2026-11-01 08:20
    labels officeOkD2
    condition day sun
}

task rstdayOkD2 {
    name "Office task with day reset"
    created 2026-11-01 08:25
    labels officeOkD2
    condition day any
}

task rstglbOkD2 {
    name "Office task with global condition any"
    created 2026-11-01 08:30
    labels officeOkD2
    condition any
}

task offstrOkD2 {
    name "Strict office task"
    created 2026-11-01 08:35
    labels officeOkD2
}
''';

      final sundayNoon = DateTime.utc(2026, 11, 1, 12);
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

      final sundayLate = DateTime.utc(2026, 11, 1, 22);
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
tdf 0.8.0

queue {
    modified 2026-11-01 08:00:00
    task opnpreOkD2
}

location locOffOkD2 {
    name "Office"
    coordinates 50.9787 11.0328
    radius 150
}

location locMunOkD2 {
    name "Munich"
    coordinates 48.1351 11.582
    radius 100
}

label officeOkD2 {
    name "Office"
    condition {
        day mon tue wed thu fri
        time 09:00 17:00
        location locOffOkD2
    }
}

task opnpreOkD2 {
    name "Open prerequisite"
    created 2026-11-01 08:00
}

task donunmOkD2 priority {
    name "Completed with unmet conditions, prereq, and suspension"
    created 2026-10-25 08:00
    finished 2026-11-01 09:00
    completions 1
    suspended 2026-11-05 09:00
    blocked opnpreOkD2
    labels officeOkD2
    condition {
        day wed
        time 14:00 15:00
        location locMunOkD2
    }
}
''';

      final sundayNoon = DateTime.utc(2026, 11, 1, 12);
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

      final restoredTime = DateTime.utc(2026, 11, 1, 16);
      final restoredBoard = board.restoreTask(
        'donunmOkD2',
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
tdf 0.8.0

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
}
task reg200OkD2 {
    name "Regular 2 (08:00 first)"
    created 2026-11-01 08:00
}
task reg300OkD2 {
    name "Regular 3 (08:00 second)"
    created 2026-11-01 08:00
}
task prio10OkD2 priority {
    name "Priority 1 (10:00)"
    created 2026-11-01 10:00
}
task prio20OkD2 priority {
    name "Priority 2 (09:30)"
    created 2026-11-01 09:30
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
tdf 0.8.0

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
    labels chouseOkD2
}
task hsreg0OkD2 {
    name "Mow lawn"
    created 2026-11-01 07:30
    labels chouseOkD2
}
task it1st0OkD2 {
    name "Patch database"
    created 2026-11-01 08:00
    labels cit000OkD2
}
task it2nd0OkD2 {
    name "Rotate TLS certificates"
    created 2026-11-01 08:30
    labels cit000OkD2
}
task itprioOkD2 priority {
    name "Restore production cluster"
    created 2026-11-01 09:30
    labels cit000OkD2
}
task it4th0OkD2 {
    name "Audit SSH keys"
    created 2026-11-01 10:00
    labels cit000OkD2
}
task itblkdOkD2 {
    name "Deploy app after lawn"
    created 2026-11-01 08:05
    labels cit000OkD2
    blocked hsreg0OkD2
}
task itsuspOkD2 {
    name "Deferred hardware upgrade"
    created 2026-11-01 08:10
    labels cit000OkD2
    suspended 2026-11-05 09:00
}
task itwdayOkD2 {
    name "Monday maintenance window"
    created 2026-11-01 08:15
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
    finished 2026-10-26 10:00
    completions 1
    labels cit000OkD2
}
''';

      final sundayNoon = DateTime.utc(2026, 11, 1, 12);
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
        manualMinusFive.toLocalWallClock(DateTime.utc(2026, 11, 1, 2)),
        equals(DateTime.utc(2026, 10, 31, 21)),
      );

      const wallClockTdf = '''
tdf 0.8.0

queue {
    modified 2026-11-01 20:05:00
    task monmrnOkD2
    task suslocOkD2
}

task monmrnOkD2 {
    name "Monday Early Task"
    created 2026-11-01 20:00
    condition {
        day mon
        time 01:00 03:00
    }
}

task suslocOkD2 {
    name "Suspended Until Monday 01:00 Local"
    created 2026-11-01 20:00
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

      final sundayNoon = DateTime.utc(2026, 11, 1, 12);
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

  group('TDF 0.7.0 Due-Date Lead Window Promotion, Passive Suppression & Block Cleanup', () {
    test('promotes queued tasks within dueLeadWindow alongside priority tasks without mutating stored fields or overriding Someday/Blocked/Completed/scoped rules', () {
      expect(
        TaskBoardEvaluator.defaultDueLeadWindow,
        equals(const Duration(hours: 24)),
      );
      final now = DateTime.utc(2026, 11, 1, 12);
      const scopedLabel = TdfLabel(
        id: 'lblScoped1',
        name: 'Private',
        isScoped: true,
      );

      final regular1 = TaskItem(
        id: 'reg0000001',
        title: 'Regular 1',
        createdAt: now,
        modifiedAt: now,
        history: <TaskHistoryEntry>[
          TaskHistoryEntry(timestampUtc: now, text: 'Regular history'),
        ],
      );
      final duePassive = TaskItem(
        id: 'pasDue0001',
        title: 'Due Passive (No Promotion)',
        createdAt: now,
        modifiedAt: now,
        dueAt: now.add(const Duration(hours: 2)),
        isDuePassive: true,
        dueNote: 'Passive deadline',
      );
      final dueBoundary = TaskItem(
        id: 'due24h0001',
        title: 'Due At Exact +24h Boundary',
        createdAt: now,
        modifiedAt: now,
        dueAt: now.add(const Duration(seconds: 86400)),
        dueNote: 'Exact boundary',
      );
      final dueOutside = TaskItem(
        id: 'due24h0002',
        title: 'Due At +86401s Outside Window',
        createdAt: now,
        modifiedAt: now,
        dueAt: now.add(const Duration(seconds: 86401)),
      );
      final prioTask = TaskItem(
        id: 'prio000001',
        title: 'Explicit Priority After Due Task In Queue',
        createdAt: now,
        modifiedAt: now,
        isPriority: true,
      );
      final overdueQueued = TaskItem(
        id: 'ovdDue0001',
        title: 'Overdue Queued Task',
        createdAt: now,
        modifiedAt: now,
        dueAt: now.subtract(const Duration(hours: 3)),
      );
      final somedayDue = TaskItem(
        id: 'someDue001',
        title: 'Unqueued Someday Task With Urgent Due',
        createdAt: now,
        modifiedAt: now,
        dueAt: now.add(const Duration(hours: 1)),
      );
      final blockedDue = TaskItem(
        id: 'blkDue0001',
        title: 'Blocked Task With Urgent Due',
        createdAt: now,
        modifiedAt: now,
        suspendedAt: now.add(const Duration(hours: 1)),
        suspendedNote: 'Deferred 1h',
        dueAt: now.add(const Duration(hours: 2)),
      );
      final completedDue = TaskItem(
        id: 'cmpDue0001',
        title: 'Completed Task With Urgent Due',
        createdAt: now,
        isCompleted: true,
        completedAt: now,
        modifiedAt: now,
        dueAt: now.add(const Duration(hours: 1)),
      );
      final scopedDue = TaskItem(
        id: 'scpDue0001',
        title: 'Scoped Urgent Task',
        createdAt: now,
        modifiedAt: now,
        labelIds: const <String>['lblScoped1'],
        dueAt: now.add(const Duration(hours: 1)),
      );

      final allTasks = <TaskItem>[
        regular1,
        duePassive,
        dueBoundary,
        dueOutside,
        prioTask,
        overdueQueued,
        somedayDue,
        blockedDue,
        completedDue,
        scopedDue,
      ];
      final queueBlock = TdfQueueBlock(
        modifiedAt: now,
        taskIds: const <String>[
          'reg0000001',
          'pasDue0001',
          'due24h0001',
          'due24h0002',
          'prio000001',
          'ovdDue0001',
          'blkDue0001',
          'scpDue0001',
        ],
      );

      // Default 24h window: urgent bucket is [due24h0001, prio000001, ovdDue0001], regular bucket is [reg0000001, pasDue0001, due24h0002]
      final defaultBoard = TaskBoard.evaluate(
        tasks: allTasks,
        labels: const <TdfLabel>[scopedLabel],
        evaluationTime: now,
        queueBlock: queueBlock,
      );
      expect(
        defaultBoard.focus.map((task) => task.id),
        equals(const <String>['due24h0001', 'prio000001', 'ovdDue0001']),
        reason: 'Stable two-bucket partition must place due-urgent and priority tasks in Focus in queue order',
      );
      expect(
        defaultBoard.ready.map((task) => task.id),
        equals(const <String>['reg0000001', 'pasDue0001', 'due24h0002']),
      );
      expect(
        defaultBoard.someday.map((task) => task.id),
        equals(const <String>['someDue001']),
      );
      expect(
        defaultBoard.blocked.map((task) => task.id),
        equals(const <String>['blkDue0001']),
      );
      expect(
        defaultBoard.completed.map((task) => task.id),
        equals(const <String>['cmpDue0001']),
      );
      expect(defaultBoard.findTierOfTask('scpDue0001'), isNull);
      expect(defaultBoard.findTask('scpDue0001'), isNotNull);
      expect(
        defaultBoard.findTask('due24h0001')!.isPriority,
        isFalse,
        reason: 'Read-only evaluation must never write priority=true onto due-promoted tasks',
      );
      expect(defaultBoard.queueModifiedAt, equals(now));

      // Off (dueLeadWindow: null): only explicit priority promotes
      final offBoard = defaultBoard.evaluateForContext(
        evaluationTime: now,
        dueLeadWindow: null,
      );
      expect(
        offBoard.focus.map((task) => task.id),
        equals(const <String>['prio000001', 'reg0000001', 'pasDue0001']),
      );

      // Zero window (0s): promotes overdue (<= now) + explicit priority, not +24h
      final zeroWindowBoard = defaultBoard.evaluateForContext(
        evaluationTime: now,
        dueLeadWindow: Duration.zero,
      );
      expect(
        zeroWindowBoard.focus.map((task) => task.id),
        equals(const <String>['prio000001', 'ovdDue0001', 'reg0000001']),
      );

      // 48h window: promotes due24h0002 (+86401s) as well, spilling 4th urgent task into Ready[0]
      final wideWindowBoard = defaultBoard.evaluateForContext(
        evaluationTime: now,
        dueLeadWindow: const Duration(hours: 48),
      );
      expect(
        wideWindowBoard.focus.map((task) => task.id),
        equals(const <String>['due24h0001', 'due24h0002', 'prio000001']),
      );
      expect(wideWindowBoard.ready.first.id, equals('ovdDue0001'));
    });

    test('cleans expired suspended and resolved non-recurring-to-recurring blocked directives in cleanupResolvedTaskBlocks while preserving recurring pipelines and conditions', () {
      final now = DateTime.utc(2026, 11, 1, 12);
      final doneNonRec = TaskItem(
        id: 'preNonRec1',
        title: 'Completed Non-Recurring Prereq',
        createdAt: now.subtract(const Duration(hours: 2)),
        isCompleted: true,
        completedAt: now.subtract(const Duration(hours: 1)),
        completions: 1,
      );
      final liveRecPrereq = TaskItem(
        id: 'preRec0001',
        title: 'Recurring Prereq With 1 Completion',
        createdAt: now.subtract(const Duration(hours: 2)),
        completions: 1,
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.days),
      );
      final openNonRecCleaned = TaskItem(
        id: 'depNonRec1',
        title: 'Open Task With Expired Suspended And Resolved Deps',
        createdAt: now.subtract(const Duration(hours: 2)),
        modifiedAt: now,
        suspendedAt: now,
        suspendedNote: 'Expired at exact now',
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'preNonRec1'),
          TdfTaskDependency(taskId: 'preRec0001'),
          TdfTaskDependency(taskId: 'delPrereq1', requiredCompletion: 5),
          TdfTaskDependency(taskId: 'fwdUnknown'),
        ],
        conditions: <TaskCondition>[
          DayTaskCondition.fromWeekdays(const <int>[1]),
        ],
      );
      final openRecPipeline = TaskItem(
        id: 'depRec0001',
        title: 'Recurring Dependent On Recurring Prereq',
        createdAt: now.subtract(const Duration(hours: 2)),
        modifiedAt: now.subtract(const Duration(minutes: 10)),
        suspendedAt: now.subtract(const Duration(seconds: 1)),
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'preRec0001'),
        ],
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.days),
      );
      final futureAndForever = TaskItem(
        id: 'susFuture1',
        title: 'Future Suspended Open Task',
        createdAt: now.subtract(const Duration(hours: 1)),
        modifiedAt: now.subtract(const Duration(hours: 1)),
        suspendedAt: now.add(const Duration(seconds: 1)),
        suspendedNote: 'Still active at +1s',
      );
      final foreverSuspended = TaskItem(
        id: 'susForevr1',
        title: 'Forever Suspended Open Task',
        createdAt: now.subtract(const Duration(hours: 1)),
        modifiedAt: now.subtract(const Duration(hours: 1)),
        isSuspendedForever: true,
        suspendedNote: 'Indefinite hold',
      );

      final deleted = TdfDeletedBlock(
        generation: 1,
        tasks: <TdfDeletedTaskRecord>[
          TdfDeletedTaskRecord(
            taskId: 'delPrereq1',
            deletedAt: now.subtract(const Duration(minutes: 5)),
          ),
        ],
      );

      final pureNormalized =
          TaskBoardEvaluator.normalizeOpenTaskForBlockCleanupComparison(
            task: openNonRecCleaned,
            liveTasksById: <String, TaskItem>{
              doneNonRec.id: doneNonRec,
              liveRecPrereq.id: liveRecPrereq,
            },
            deletedTaskIds: const <String>{'delPrereq1'},
            nowUtc: now,
          );
      expect(pureNormalized.suspendedAt, isNull);
      expect(pureNormalized.suspendedNote, isNull);
      expect(
        pureNormalized.modifiedAt,
        equals(now),
        reason: 'normalizeOpenTaskForBlockCleanupComparison must not advance modifiedAt',
      );

      final result = TaskBoardEvaluator.cleanupResolvedTaskBlocks(
        tasks: <TaskItem>[
          doneNonRec,
          liveRecPrereq,
          openNonRecCleaned,
          openRecPipeline,
          futureAndForever,
          foreverSuspended,
        ],
        deleted: deleted,
        nowUtc: now,
      );
      expect(result.cleanedSuspendedCount, equals(2));
      expect(result.cleanedBlockedCount, equals(3));

      final byId = <String, TaskItem>{
        for (final task in result.tasks) task.id: task,
      };
      final cleanedDep = byId['depNonRec1']!;
      expect(cleanedDep.suspendedAt, isNull);
      expect(cleanedDep.suspendedNote, isNull);
      expect(
        cleanedDep.dependencies,
        equals(const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'fwdUnknown'),
        ]),
        reason: 'Must strip satisfied non-rec, satisfied rec->non-rec, and tombstoned deps while keeping unknown forward ref',
      );
      expect(
        cleanedDep.conditions,
        isNotEmpty,
        reason: 'Section 5.4: condition rules are persistent constraints and must not be stripped',
      );
      expect(
        cleanedDep.modifiedAt,
        equals(now.add(const Duration(seconds: 1))),
        reason: 'When both suspended and blocked are cleaned on the same task with modified==now, modifiedAt advances once to now+1s',
      );

      final cleanedRecDep = byId['depRec0001']!;
      expect(cleanedRecDep.suspendedAt, isNull);
      expect(
        cleanedRecDep.dependencies,
        equals(const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'preRec0001'),
        ]),
        reason: 'Recurring-to-recurring dependency must be preserved across cleanup',
      );
      expect(cleanedRecDep.modifiedAt, equals(now));

      expect(
        byId['susFuture1']!.suspendedAt,
        equals(now.add(const Duration(seconds: 1))),
      );
      expect(byId['susFuture1']!.suspendedNote, equals('Still active at +1s'));
      expect(
        byId['susFuture1']!.modifiedAt,
        equals(now.subtract(const Duration(hours: 1))),
      );
      expect(byId['susForevr1']!.isSuspendedForever, isTrue);
      expect(byId['susForevr1']!.suspendedNote, equals('Indefinite hold'));

      // Overflow at 9999-12-31 23:59:59 UTC throws TdfException(invalidTimestamp):
      final maxTime = DateTime.utc(9999, 12, 31, 23, 59, 59);
      expect(
        () => TaskBoardEvaluator.cleanupResolvedTaskBlocks(
          tasks: <TaskItem>[
            TaskItem(
              id: 'tOverflow1',
              title: 'Max Timestamp Task',
              createdAt: maxTime,
              modifiedAt: maxTime,
              suspendedAt: maxTime,
            ),
          ],
          deleted: TdfDeletedBlock.empty,
          nowUtc: maxTime,
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.invalidTimestamp,
          ),
        ),
      );
    });
  });

  group('TDF 0.8.0 TimeZoneContextRequired (TDF-CTX-001) & Condition Context Resolution', () {
    test('throws TdfContextException(timeZoneContextRequired) on queued open tasks reaching day/time conditions when timeZone is unavailable while allowing non-reaching tasks', () {
      final nowUtc = DateTime.utc(2026, 11, 2, 10);
      const missingZone = TdfTimeZoneContext.missing('Mars/Phobos');
      final unknownNamedZone = TdfTimeZoneContext.named('Unknown/Zone');
      expect(unknownNamedZone.isAvailable, isFalse);

      final dayRule = DayTaskCondition(
        weekdays: const <int>[DateTime.monday],
        dayTokens: const <String>['mon'],
      );
      final timeRule = TimeWindowTaskCondition.tryParse('09:00', '17:00')!;
      const office = TdfLocation(
        id: 'locOff0001',
        name: 'Office',
        latitude: 52.52,
        longitude: 13.405,
        radius: 250,
      );
      final locRule = LocationTaskCondition.fromIds(const <String>[
        'locOff0001',
      ]);

      final dayLabel = TdfLabel(
        id: 'lblDay0001',
        name: 'Weekday Work',
        conditions: <TaskCondition>[dayRule],
      );
      const unrestrictedLabel = TdfLabel(
        id: 'lblAny0001',
        name: 'Unrestricted',
      );
      final scopedDayLabel = TdfLabel(
        id: 'lblScp0001',
        name: 'Scoped Weekday',
        isScoped: true,
        conditions: <TaskCondition>[timeRule],
      );

      // 1. Direct day condition on queued open task fails with TimeZoneContextRequired even if localEvaluationTime is supplied:
      expect(
        () => TaskBoard.evaluate(
          tasks: <TaskItem>[
            TaskItem(
              id: 'qDayTask01',
              title: 'Queued Day Task',
              createdAt: nowUtc,
              conditions: <TaskCondition>[dayRule],
            ),
          ],
          queueBlock: TdfQueueBlock(
            modifiedAt: nowUtc,
            taskIds: const <String>['qDayTask01'],
          ),
          evaluationTime: nowUtc,
          localEvaluationTime: nowUtc,
          timeZone: missingZone,
        ),
        throwsA(
          isA<TdfContextException>().having(
            (error) => error.kind,
            'kind',
            TdfContextOutcomeKind.timeZoneContextRequired,
          ),
        ),
        reason: 'TDF-CTX-001: unavailable timeZone must not silently fall back to localEvaluationTime for day condition',
      );

      // 2. Inherited time condition on queued open task fails with TimeZoneContextRequired:
      expect(
        () => TaskBoard.evaluate(
          tasks: <TaskItem>[
            TaskItem(
              id: 'qInhTime01',
              title: 'Inherited Time Task',
              createdAt: nowUtc,
              labelIds: const <String>['lblScp0001'],
            ),
          ],
          labels: <TdfLabel>[scopedDayLabel],
          queueBlock: TdfQueueBlock(
            modifiedAt: nowUtc,
            taskIds: const <String>['qInhTime01'],
          ),
          activeLabelId: 'lblScp0001',
          evaluationTime: nowUtc,
          timeZone: unknownNamedZone,
        ),
        throwsA(
          isA<TdfContextException>().having(
            (error) => error.kind,
            'kind',
            TdfContextOutcomeKind.timeZoneContextRequired,
          ),
        ),
        reason: 'TDF-CTX-001: active scoped label filter reaching inherited time rule must throw TimeZoneContextRequired',
      );

      // 3. Tasks NOT reaching day/time condition evaluation succeed without localNow:
      final prereqOpen = TaskItem(
        id: 'preOpen001',
        title: 'Open Prerequisite',
        createdAt: nowUtc,
      );
      final doneWithDay = TaskItem(
        id: 'doneDay001',
        title: 'Completed With Day',
        isCompleted: true,
        completedAt: nowUtc,
        completions: 1,
        createdAt: nowUtc,
        conditions: <TaskCondition>[dayRule],
      );
      final somedayWithTime = TaskItem(
        id: 'someTim001',
        title: 'Someday With Time',
        createdAt: nowUtc,
        conditions: <TaskCondition>[timeRule],
      );
      final suspendedWithDay = TaskItem(
        id: 'suspDay001',
        title: 'Suspended Queued With Day',
        createdAt: nowUtc,
        suspendedAt: nowUtc.add(const Duration(hours: 2)),
        conditions: <TaskCondition>[dayRule],
      );
      final depBlockedWithTime = TaskItem(
        id: 'depBlkTm01',
        title: 'Prerequisite-Blocked With Time',
        createdAt: nowUtc,
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'preOpen001'),
        ],
        conditions: <TaskCondition>[timeRule],
      );
      final globalResetTask = TaskItem(
        id: 'globAny001',
        title: 'Global Reset Overrides Label Day',
        createdAt: nowUtc,
        labelIds: const <String>['lblDay0001'],
        conditions: const <TaskCondition>[GlobalResetTaskCondition()],
      );
      final groupResetTask = TaskItem(
        id: 'grpAny0001',
        title: 'Group Reset Clears Day and Time',
        createdAt: nowUtc,
        labelIds: const <String>['lblDay0001'],
        conditions: const <TaskCondition>[
          GroupResetTaskCondition(targetGroup: ConditionGroup.day),
          GroupResetTaskCondition(targetGroup: ConditionGroup.time),
        ],
      );
      final locationOnlyTask = TaskItem(
        id: 'locOnly001',
        title: 'Location Only Task',
        createdAt: nowUtc,
        conditions: <TaskCondition>[locRule],
      );
      final scopedGlobalHiddenTask = TaskItem(
        id: 'scpHid0001',
        title: 'Scoped Hidden Task',
        createdAt: nowUtc,
        labelIds: const <String>['lblScp0001'],
      );
      // Multi-label task with ['lblDay0001', 'lblAny0001']: in ascending ASCII <label-id> order,
      // 'lblAny0001' < 'lblDay0001', so 'lblAny0001' evaluates first and short-circuits OR to true!
      final asciiShortCircuitTask = TaskItem(
        id: 'ascOrOk001',
        title: 'ASCII Label Order Short-Circuit',
        createdAt: nowUtc,
        labelIds: const <String>['lblDay0001', 'lblAny0001'],
      );

      final board = TaskBoard.evaluate(
        tasks: <TaskItem>[
          prereqOpen,
          doneWithDay,
          somedayWithTime,
          suspendedWithDay,
          depBlockedWithTime,
          globalResetTask,
          groupResetTask,
          locationOnlyTask,
          scopedGlobalHiddenTask,
          asciiShortCircuitTask,
        ],
        labels: <TdfLabel>[dayLabel, unrestrictedLabel, scopedDayLabel],
        locations: const <TdfLocation>[office],
        queueBlock: TdfQueueBlock(
          modifiedAt: nowUtc,
          taskIds: const <String>[
            'preOpen001',
            'suspDay001',
            'depBlkTm01',
            'globAny001',
            'grpAny0001',
            'locOnly001',
            'scpHid0001',
            'ascOrOk001',
          ],
        ),
        evaluationTime: nowUtc,
        timeZone: missingZone,
        currentLatitude: 52.52,
        currentLongitude: 13.405,
      );

      expect(board.completed.map((t) => t.id), contains('doneDay001'));
      expect(board.someday.map((t) => t.id), contains('someTim001'));
      expect(
        board.blocked.map((t) => t.id),
        containsAll(<String>['suspDay001', 'depBlkTm01']),
      );
      final eligibleIds = <String>[
        ...board.focus.map((t) => t.id),
        ...board.ready.map((t) => t.id),
        ...board.planned.map((t) => t.id),
      ];
      expect(
        eligibleIds,
        containsAll(<String>[
          'preOpen001',
          'globAny001',
          'grpAny0001',
          'locOnly001',
          'ascOrOk001',
        ]),
        reason: 'Tasks clearing or short-circuiting before day/time rules must evaluate cleanly when timeZone is unavailable',
      );
    });
  });

  group('Dependency cycle reverse-reachability index', () {
    test('collectCycleCreatingPrerequisiteIds matches wouldCreateDependencyCycle across chains, diamonds, completed nodes, dangling IDs, and blank input', () {
      final now = DateTime.utc(2026, 11, 10, 12);
      final root = TaskItem(
        id: 'tskRoot001',
        title: 'Root',
        createdAt: now,
        modifiedAt: now,
      );
      final leftBranch = TaskItem(
        id: 'tskLeft001',
        title: 'Left',
        createdAt: now,
        modifiedAt: now,
        blockedByTaskIds: const <String>['tskRoot001'],
      );
      final rightBranch = TaskItem(
        id: 'tskRght001',
        title: 'Right',
        createdAt: now,
        modifiedAt: now,
        blockedByTaskIds: const <String>['tskRoot001'],
      );
      final diamondLeaf = TaskItem(
        id: 'tskLeaf001',
        title: 'Diamond Leaf',
        createdAt: now,
        modifiedAt: now,
        blockedByTaskIds: const <String>['tskLeft001', 'tskRght001'],
      );
      final unrelated = TaskItem(
        id: 'tskFree001',
        title: 'Unrelated',
        createdAt: now,
        modifiedAt: now,
        blockedByTaskIds: const <String>['missing999'],
      );
      final completedChild = TaskItem(
        id: 'tskDone001',
        title: 'Completed Child',
        createdAt: now,
        modifiedAt: now,
        completedAt: now,
        isCompleted: true,
        completions: 1,
        blockedByTaskIds: const <String>['tskLeaf001'],
      );
      final board = TaskBoard.evaluate(
        tasks: <TaskItem>[
          root,
          leftBranch,
          rightBranch,
          diamondLeaf,
          unrelated,
          completedChild,
        ],
        queueBlock: TdfQueueBlock(
          taskIds: const <String>[
            'tskRoot001',
            'tskLeft001',
            'tskRght001',
            'tskLeaf001',
            'tskFree001',
          ],
        ),
        evaluationTime: now,
      );

      expect(
        TaskBoardEvaluator.collectCycleCreatingPrerequisiteIds(
          taskId: '   ',
          tasks: board.allTasks,
        ),
        isEmpty,
        reason: 'Blank taskId must produce an empty cycle set',
      );
      expect(
        TaskBoardEvaluator.collectCycleCreatingPrerequisiteIds(
          taskId: 'missing999',
          tasks: board.allTasks,
        ),
        equals(<String>{'missing999', 'tskFree001'}),
        reason: 'Even a dangling target must include nodes blocked by it',
      );

      for (final task in board.allTasks) {
        final cyclicIds =
            TaskBoardEvaluator.collectCycleCreatingPrerequisiteIds(
              taskId: task.id,
              tasks: board.allTasks,
            );
        for (final candidate in board.allTasks) {
          final expected = board.wouldCreateDependencyCycle(
            task.id,
            candidate.id,
          );
          expect(
            cyclicIds.contains(candidate.id),
            equals(expected),
            reason:
                'Reverse reachability for (${task.id} <- ${candidate.id}) must match wouldCreateDependencyCycle',
          );
        }
      }
    });

    test(
      'collectCycleCreatingPrerequisiteIds scales linearly on a 400-task chain',
      () {
        final now = DateTime.utc(2026, 11, 10, 12);
        final tasks = <TaskItem>[
          for (var i = 0; i < 400; i++)
            TaskItem(
              id: 'chn${i.toString().padLeft(7, '0')}',
              title: 'Chain $i',
              createdAt: now,
              modifiedAt: now,
              blockedByTaskIds: i == 0
                  ? const <String>[]
                  : <String>['chn${(i - 1).toString().padLeft(7, '0')}'],
            ),
        ];
        final stopwatch = Stopwatch()..start();
        final cyclic = TaskBoardEvaluator.collectCycleCreatingPrerequisiteIds(
          taskId: 'chn0000100',
          tasks: tasks,
        );
        stopwatch.stop();

        expect(cyclic, hasLength(300));
        expect(cyclic, contains('chn0000100'));
        expect(cyclic, contains('chn0000399'));
        expect(cyclic, isNot(contains('chn0000099')));
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(200),
          reason: 'Single-pass reverse BFS over 400 tasks must finish well under 200ms',
        );
      },
    );

    test('eval.blocked debug logging resolves locationIds via locationMap and omits metrics for unknown location IDs without leaking coordinates', () {
      final now = DateTime.utc(2026, 11, 10, 12);
      AppLogger.resetForTesting(clock: () => now);
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.debug,
        persistToDisk: false,
      );
      addTearDown(AppLogger.resetForTesting);

      const munich = TdfLocation(
        id: 'locMun0001',
        name: 'Munich Office',
        latitude: 48.137154,
        longitude: 11.576124,
        radius: 250.0,
      );
      const currentLat = 48.146154;
      const currentLon = 11.576124;
      final expectedDistance = LocationTaskCondition.haversineDistanceMeters(
        currentLat,
        currentLon,
        munich.latitude,
        munich.longitude,
      ).round();

      TaskBoard.evaluate(
        locations: const <TdfLocation>[munich],
        tasks: <TaskItem>[
          TaskItem(
            id: 'tskMun0001',
            title: 'Secret Munich Task',
            createdAt: now,
            conditions: const <TaskCondition>[
              LocationTaskCondition(locationIds: <String>['locMun0001']),
            ],
          ),
          TaskItem(
            id: 'tskMis0001',
            title: 'Task With Missing Location ID',
            createdAt: now,
            conditions: const <TaskCondition>[
              LocationTaskCondition(locationIds: <String>['locMiss001']),
            ],
          ),
        ],
        queueBlock: TdfQueueBlock(
          modifiedAt: now,
          taskIds: const <String>['tskMun0001', 'tskMis0001'],
        ),
        evaluationTime: now,
        currentLatitude: currentLat,
        currentLongitude: currentLon,
      );

      final munichLine = AppLogger.lines.firstWhere(
        (line) =>
            line.contains('eval.blocked |') && line.contains('id=tskMun0001'),
      );
      expect(
        munichLine,
        contains('distance_m=$expectedDistance'),
        reason: 'eval.blocked must log Haversine distance against resolved TdfLocation rather than (0, 0)',
      );
      expect(
        munichLine,
        contains('radius_m=250'),
        reason: 'eval.blocked must log resolved TdfLocation radius',
      );
      expect(
        munichLine,
        isNot(contains('48.137154')),
        reason: 'eval.blocked must never log raw coordinates',
      );

      final missingLine = AppLogger.lines.firstWhere(
        (line) =>
            line.contains('eval.blocked |') && line.contains('id=tskMis0001'),
      );
      expect(
        missingLine,
        contains('reason=condition'),
        reason:
            'Missing location ID must still log eval.blocked without crashing',
      );
      expect(
        missingLine,
        isNot(contains('distance_m=')),
        reason: 'Missing location ID must omit distance_m',
      );
      expect(
        missingLine,
        isNot(contains('radius_m=')),
        reason: 'Missing location ID must omit radius_m',
      );
    });

    test('domain mutation logs emit canonical event names directly and never leak task titles or label names', () {
      final now = DateTime.utc(2026, 11, 10, 12);
      AppLogger.resetForTesting(clock: () => now);
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.info,
        persistToDisk: false,
      );
      addTearDown(AppLogger.resetForTesting);

      var board = TaskBoard.empty()
          .addLabel(
            'ConfidentialLabelAlpha',
            currentDate: now,
            id: 'lblSec0001',
          )
          .updateLabel(
            'lblSec0001',
            name: 'ConfidentialLabelBeta',
            currentDate: now.add(const Duration(seconds: 5)),
          )
          .addTask(
            'ConfidentialTaskTitleOne',
            currentDate: now.add(const Duration(seconds: 10)),
            id: 'tskSec0001',
          )
          .updateTask(
            'tskSec0001',
            title: 'ConfidentialTaskTitleTwo',
            currentDate: now.add(const Duration(seconds: 15)),
          );

      expect(board.labels.single.name, equals('ConfidentialLabelBeta'));
      expect(board.allTasks.single.title, equals('ConfidentialTaskTitleTwo'));

      final logText = AppLogger.fullLogText;
      expect(
        logText,
        contains('[INFO ] [DOMAIN   ] label.add | id=lblSec0001 '),
        reason: 'addLabel must emit canonical label.add event',
      );
      expect(
        logText,
        contains('[INFO ] [DOMAIN   ] label.update | id=lblSec0001 '),
        reason: 'updateLabel must emit canonical label.update event',
      );
      expect(
        logText,
        contains('[INFO ] [DOMAIN   ] task.add | id=tskSec0001 '),
        reason: 'addTask must emit canonical task.add event',
      );
      expect(
        logText,
        contains('[INFO ] [DOMAIN   ] task.update | id=tskSec0001 '),
        reason: 'updateTask must emit canonical task.update event',
      );
      for (final sensitive in const <String>[
        'ConfidentialLabelAlpha',
        'ConfidentialLabelBeta',
        'ConfidentialTaskTitleOne',
        'ConfidentialTaskTitleTwo',
      ]) {
        expect(
          logText,
          isNot(contains(sensitive)),
          reason: 'Domain mutation logs must never leak "$sensitive"',
        );
      }
    });
  });

  group('Wave 2B Structural Equality, Batch Tombstone Recording & Zero-Copy Normalization', () {
    test('TaskBoard implements structural operator == and hashCode across all slices and unevaluated boards', () {
      final now = DateTime.utc(2026, 11, 15, 12);
      const label = TdfLabel(id: 'lblEq00001', name: 'Work');
      const location = TdfLocation(
        id: 'locEq00001',
        name: 'Office',
        latitude: 48.137154,
        longitude: 11.576124,
        radius: 150,
      );
      final task = TaskItem(
        id: 'tskEq00001',
        title: 'Task Alpha',
        createdAt: now,
        labelIds: const <String>['lblEq00001'],
      );
      final queue = TdfQueueBlock(
        modifiedAt: now,
        taskIds: const <String>['tskEq00001'],
      );
      final deleted = TdfDeletedBlock(
        generation: 1,
        tasks: <TdfDeletedTaskRecord>[
          TdfDeletedTaskRecord(taskId: 'delEq00001', deletedAt: now),
        ],
      );

      final boardA = TaskBoard.evaluate(
        tasks: <TaskItem>[task],
        labels: const <TdfLabel>[label],
        locations: const <TdfLocation>[location],
        queueBlock: queue,
        deletedBlock: deleted,
        evaluationTime: now,
      );
      final boardB = TaskBoard.evaluate(
        tasks: <TaskItem>[task],
        labels: const <TdfLabel>[label],
        locations: const <TdfLocation>[location],
        queueBlock: queue,
        deletedBlock: deleted,
        evaluationTime: now,
      );

      expect(boardA, equals(boardB));
      expect(boardA.hashCode, equals(boardB.hashCode));
      expect(
        boardA,
        isNot(equals(boardA.copyWith(deletedBlock: TdfDeletedBlock.empty))),
      );
      expect(
        boardA,
        isNot(equals(boardA.copyWith(labels: const <TdfLabel>[]))),
      );
      expect(
        boardA,
        isNot(equals(boardA.copyWith(locations: const <TdfLocation>[]))),
      );

      final unevaluatedA = TaskBoard.unevaluated(tasks: <TaskItem>[task]);
      final unevaluatedB = TaskBoard.unevaluated(tasks: <TaskItem>[task]);
      final unevaluatedEmpty = TaskBoard.unevaluated(tasks: const <TaskItem>[]);
      expect(unevaluatedA, equals(unevaluatedB));
      expect(unevaluatedA.hashCode, equals(unevaluatedB.hashCode));
      expect(unevaluatedA, isNot(equals(unevaluatedEmpty)));
    });

    test('TaskBoardEvaluator.recordTaskDeletions merges batches in one pass and enforces maxTdfDeletedRecords', () {
      final now = DateTime.utc(2026, 11, 15, 12);
      final initial = TdfDeletedBlock(
        generation: 2,
        tasks: <TdfDeletedTaskRecord>[
          TdfDeletedTaskRecord(
            taskId: 'tskBatch02',
            deletedAt: now,
            completionsCheckpoint: 1,
          ),
        ],
      );

      expect(
        identical(
          TaskBoardEvaluator.recordTaskDeletions(
            initial,
            const <TdfDeletedTaskRecord>[],
          ),
          initial,
        ),
        isTrue,
        reason: 'Empty batch must return identical TdfDeletedBlock',
      );

      final merged = TaskBoardEvaluator.recordTaskDeletions(
        initial,
        <TdfDeletedTaskRecord>[
          TdfDeletedTaskRecord(
            taskId: 'tskBatch03',
            deletedAt: now.add(const Duration(seconds: 5)),
          ),
          TdfDeletedTaskRecord(
            taskId: 'tskBatch02',
            deletedAt: now.add(const Duration(seconds: 10)),
            completionsCheckpoint: 3,
          ),
          TdfDeletedTaskRecord(
            taskId: 'tskBatch01',
            deletedAt: now.add(const Duration(seconds: 1)),
          ),
        ],
      );
      expect(merged.generation, equals(2));
      expect(
        merged.tasks.map((record) => record.taskId).toList(),
        equals(const <String>['tskBatch01', 'tskBatch02', 'tskBatch03']),
      );
      expect(
        merged.findTaskRecord('tskBatch02')?.completionsCheckpoint,
        equals(3),
      );

      final fullBlock = TdfDeletedBlock(
        generation: 1,
        tasks: <TdfDeletedTaskRecord>[
          for (var i = 0; i < maxTdfDeletedRecords; i++)
            TdfDeletedTaskRecord(
              taskId: 'DEL${i.toString().padLeft(7, '0')}',
              deletedAt: now,
            ),
        ],
      );
      expect(
        () => TaskBoardEvaluator.recordTaskDeletions(
          fullBlock,
          <TdfDeletedTaskRecord>[
            TdfDeletedTaskRecord(taskId: 'OVR0000001', deletedAt: now),
          ],
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
      );
    });

    test('TaskBoardEvaluator.evaluate and normalizeTierSlices preserve identical instances for already-normalized tasks', () {
      final now = DateTime.utc(2026, 11, 15, 12);
      const scopedLabel = TdfLabel(
        id: 'lblScp0001',
        name: 'Scoped',
        isScoped: true,
      );
      final focusTask = TaskItem(
        id: 'tskFoc0001',
        title: 'Focus task',
        createdAt: now,
      );
      final blockedTask = TaskItem(
        id: 'tskBlk0001',
        title: 'Blocked task',
        createdAt: now,
        isSuspendedForever: true,
      );
      final somedayTask = TaskItem(
        id: 'tskSom0001',
        title: 'Someday task',
        createdAt: now,
      );
      final completedTask = TaskItem(
        id: 'tskCmp0001',
        title: 'Completed task',
        createdAt: now,
        isCompleted: true,
        completedAt: now,
      );
      final hiddenOpenTask = TaskItem(
        id: 'tskHid0001',
        title: 'Hidden open task',
        createdAt: now,
        labelIds: const <String>['lblScp0001'],
      );

      final board = TaskBoard.evaluate(
        tasks: <TaskItem>[
          focusTask,
          blockedTask,
          somedayTask,
          completedTask,
          hiddenOpenTask,
        ],
        labels: const <TdfLabel>[scopedLabel],
        queueBlock: TdfQueueBlock(
          modifiedAt: now,
          taskIds: const <String>['tskFoc0001', 'tskBlk0001'],
        ),
        evaluationTime: now,
      );

      expect(identical(board.focus.single, focusTask), isTrue);
      expect(identical(board.blocked.single, blockedTask), isTrue);
      expect(identical(board.someday.single, somedayTask), isTrue);
      expect(identical(board.completed.single, completedTask), isTrue);
      expect(identical(board.findTask('tskHid0001'), hiddenOpenTask), isTrue);
    });
  });
}
