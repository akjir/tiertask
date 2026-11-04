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
import 'package:tiertask/services/tdf_service.dart';

void main() {
  const tdfService = TdfService();
  final fixedDate = DateTime.utc(2026, 11, 1, 12, 0);

  group('TDF 0.5.0 Section 6.3 and 6.11.3 Queue-Driven Task Downgrade Transitions', () {
    test('executes Section 6.3 Focus-to-Ready (< 8 and >= 8 eligible tasks), Ready-to-Planned, and Planned-to-Someday downgrades via shared queue order without shifting queuedAt timestamps', () {
      final f1InitialQueued = DateTime.utc(2026, 11, 1, 8, 0);
      final b2InitialQueued = DateTime.utc(2026, 11, 1, 8, 20);
      final board = TaskBoard(
        focus: [
          TaskItem(
            id: 'f10000OkD2',
            title: 'Focus 1 (Downgrade Me)',
            isPriority: true,
            queuedAt: f1InitialQueued,
          ),
          TaskItem(
            id: 'f20000OkD2',
            title: 'Focus 2',
            queuedAt: DateTime.utc(2026, 11, 1, 8, 5),
          ),
          TaskItem(
            id: 'f30000OkD2',
            title: 'Focus 3',
            queuedAt: DateTime.utc(2026, 11, 1, 8, 10),
          ),
        ],
        ready: [
          TaskItem(
            id: 'b10000OkD2',
            title: 'Ready 1 (Should Pull Up)',
            queuedAt: DateTime.utc(2026, 11, 1, 8, 15),
          ),
          TaskItem(
            id: 'b20000OkD2',
            title: 'Ready 2',
            queuedAt: b2InitialQueued,
          ),
        ],
        planned: [
          TaskItem(
            id: 'g10000OkD2',
            title: 'Planned 1',
            queuedAt: DateTime.utc(2026, 11, 1, 8, 25),
          ),
        ],
      );

      final downgraded = board.downgradeTask(
        'f10000OkD2',
        currentDate: fixedDate,
      );

      expect(
        downgraded.focus.map((task) => task.title),
        equals(['Focus 2', 'Focus 3', 'Ready 1 (Should Pull Up)']),
      );
      expect(
        downgraded.ready.map((task) => task.title),
        equals(['Ready 2', 'Planned 1', 'Focus 1 (Downgrade Me)']),
      );
      expect(
        downgraded.findTask('f10000OkD2')?.isPriority,
        isFalse,
        reason: 'Downgrading with < 8 eligible tasks must strip the priority flag per Section 6.3',
      );
      expect(
        downgraded.findTask('f10000OkD2')?.queuedAt,
        equals(f1InitialQueued),
        reason: 'Section 6.3 requires preserving queuedAt when moving to the end of queue',
      );
      expect(
        downgraded.queueTaskIds.last,
        equals('f10000OkD2'),
        reason: 'Downgraded task (< 8 eligible) must move to the end of queue',
      );
      expect(downgraded.planned, isEmpty);

      final downgradedReadyUnder8 = downgraded.downgradeTask(
        'b20000OkD2',
        currentDate: fixedDate.add(const Duration(minutes: 5)),
      );
      expect(
        downgradedReadyUnder8.ready.map((task) => task.id),
        equals(['g10000OkD2', 'f10000OkD2', 'b20000OkD2']),
        reason: 'Downgrading Ready task when < 8 eligible tasks exist must move it to the end of queue',
      );
      expect(
        downgradedReadyUnder8.findTask('b20000OkD2')?.queuedAt,
        equals(b2InitialQueued),
        reason: 'Ready downgrade must preserve queuedAt',
      );
      expect(downgradedReadyUnder8.planned, isEmpty);

      final beforeNoopTask = downgradedReadyUnder8.findTask('b20000OkD2')!;
      final beforeNoopQueueModified = downgradedReadyUnder8.queueModifiedAt;
      final afterTailNoop = downgradedReadyUnder8.downgradeTask(
        'b20000OkD2',
        currentDate: fixedDate.add(const Duration(minutes: 10)),
      );
      expect(
        afterTailNoop.findTask('b20000OkD2')?.modifiedAt,
        equals(beforeNoopTask.modifiedAt),
        reason: 'Section 6.3 and 6.11.3: downgrading a non-priority Focus/Ready task already at the end of queue must leave task.modified unchanged',
      );
      expect(
        afterTailNoop.queueModifiedAt,
        equals(beforeNoopQueueModified),
        reason: 'Section 6.3 and 6.11.3: downgrading a non-priority Focus/Ready task already at the end of queue must leave queue.modified unchanged',
      );

      final slot8Time = DateTime.utc(2026, 11, 1, 9, 0, 0);
      final collidingSlot9Time = DateTime.utc(2026, 11, 1, 9, 0, 1);
      final fullBoard = TaskBoard(
        focus: [
          TaskItem(
            id: 'f10000OkD2',
            title: 'F1',
            isPriority: true,
            queuedAt: DateTime.utc(2026, 11, 1, 8, 0),
          ),
          TaskItem(
            id: 'f20000OkD2',
            title: 'F2',
            queuedAt: DateTime.utc(2026, 11, 1, 8, 5),
          ),
          TaskItem(
            id: 'f30000OkD2',
            title: 'F3',
            queuedAt: DateTime.utc(2026, 11, 1, 8, 10),
          ),
        ],
        ready: [
          TaskItem(
            id: 'r10000OkD2',
            title: 'R1',
            queuedAt: DateTime.utc(2026, 11, 1, 8, 15),
          ),
          TaskItem(
            id: 'r20000OkD2',
            title: 'R2',
            queuedAt: DateTime.utc(2026, 11, 1, 8, 20),
          ),
          TaskItem(
            id: 'r30000OkD2',
            title: 'R3',
            queuedAt: DateTime.utc(2026, 11, 1, 8, 25),
          ),
          TaskItem(
            id: 'r40000OkD2',
            title: 'R4',
            queuedAt: DateTime.utc(2026, 11, 1, 8, 30),
          ),
          TaskItem(id: 'r50000OkD2', title: 'R5 (Slot 8)', queuedAt: slot8Time),
        ],
        planned: [
          TaskItem(
            id: 'p10000OkD2',
            title: 'P1 (Slot 9)',
            queuedAt: collidingSlot9Time,
          ),
          TaskItem(
            id: 'p20000OkD2',
            title: 'P2',
            queuedAt: DateTime.utc(2026, 11, 1, 9, 5),
          ),
        ],
      );

      final afterFocusDowngradeOnFullBoard = fullBoard.downgradeTask(
        'f10000OkD2',
        currentDate: fixedDate,
      );
      expect(
        afterFocusDowngradeOnFullBoard.focus.map((task) => task.id),
        equals(['f20000OkD2', 'f30000OkD2', 'r10000OkD2']),
        reason: 'r10000OkD2 at slot 4 must advance into Focus slot 3',
      );
      expect(
        afterFocusDowngradeOnFullBoard.ready.map((task) => task.id),
        equals([
          'r20000OkD2',
          'r30000OkD2',
          'r40000OkD2',
          'r50000OkD2',
          'f10000OkD2',
        ]),
        reason: 'Downgraded Focus task f10000OkD2 must land at active slot 8 immediately after r50000OkD2',
      );
      expect(
        afterFocusDowngradeOnFullBoard.findTask('f10000OkD2')?.isPriority,
        isFalse,
        reason: 'Downgraded Focus task must match slot 8 anchor priority flag (false)',
      );
      expect(
        afterFocusDowngradeOnFullBoard.findTask('f10000OkD2')?.queuedAt,
        equals(DateTime.utc(2026, 11, 1, 8, 0)),
        reason: 'Section 6.3 and 6.11.3: Focus downgrade behind slot 8 must preserve queuedAt without timestamp shifts',
      );
      expect(
        afterFocusDowngradeOnFullBoard.findTask('p10000OkD2')?.queuedAt,
        equals(collidingSlot9Time),
        reason: 'Section 6.3 and 6.11.3: Planned task p10000OkD2 must not have its queuedAt or modifiedAt shifted',
      );

      final allPriorityBoard = TaskBoard(
        focus: [
          TaskItem(
            id: 'pf1000OkD2',
            title: 'PF1',
            isPriority: true,
            queuedAt: DateTime.utc(2026, 11, 1, 8, 0),
          ),
          TaskItem(
            id: 'pf2000OkD2',
            title: 'PF2',
            isPriority: true,
            queuedAt: DateTime.utc(2026, 11, 1, 8, 5),
          ),
          TaskItem(
            id: 'pf3000OkD2',
            title: 'PF3',
            isPriority: true,
            queuedAt: DateTime.utc(2026, 11, 1, 8, 10),
          ),
        ],
        ready: [
          TaskItem(
            id: 'pr1000OkD2',
            title: 'PR1',
            isPriority: true,
            queuedAt: DateTime.utc(2026, 11, 1, 8, 15),
          ),
          TaskItem(
            id: 'pr2000OkD2',
            title: 'PR2',
            isPriority: true,
            queuedAt: DateTime.utc(2026, 11, 1, 8, 20),
          ),
          TaskItem(
            id: 'pr3000OkD2',
            title: 'PR3',
            isPriority: true,
            queuedAt: DateTime.utc(2026, 11, 1, 8, 25),
          ),
          TaskItem(
            id: 'pr4000OkD2',
            title: 'PR4',
            isPriority: true,
            queuedAt: DateTime.utc(2026, 11, 1, 8, 30),
          ),
          TaskItem(
            id: 'pr5000OkD2',
            title: 'PR5 (Priority Slot 8)',
            isPriority: true,
            queuedAt: slot8Time,
          ),
        ],
        planned: [
          TaskItem(
            id: 'pp1000OkD2',
            title: 'PP1 (Priority Slot 9)',
            isPriority: true,
            queuedAt: collidingSlot9Time,
          ),
          TaskItem(
            id: 'regp20OkD2',
            title: 'Regular Planned Task',
            isPriority: false,
            queuedAt: DateTime.utc(2026, 11, 1, 8, 0),
          ),
        ],
      );

      final afterPriorityFocusDowngrade = allPriorityBoard.downgradeTask(
        'pf1000OkD2',
        currentDate: fixedDate,
      );
      expect(
        afterPriorityFocusDowngrade.findTask('pf1000OkD2')?.isPriority,
        isTrue,
        reason: 'When slot 8 carries priority, downgraded Focus task must retain priority per Section 6.3',
      );
      expect(
        afterPriorityFocusDowngrade.findTask('pf1000OkD2')?.queuedAt,
        equals(DateTime.utc(2026, 11, 1, 8, 0)),
        reason: 'Downgraded priority Focus task must preserve its original queuedAt',
      );
      expect(
        afterPriorityFocusDowngrade.findTask('pf1000OkD2')?.modifiedAt,
        isNull,
        reason: 'Section 6.3: When pf1000OkD2 keeps priority=true and only queue order changes, pf1000OkD2.modified must remain unchanged',
      );
      expect(
        afterPriorityFocusDowngrade.findTask('pp1000OkD2')?.queuedAt,
        equals(collidingSlot9Time),
        reason: 'pp1000OkD2 must preserve its queuedAt without shifting',
      );
      final reparsedPriorityDowngrade = tdfService.parse(
        tdfService.serialize(afterPriorityFocusDowngrade),
        evaluationTime: fixedDate,
      );
      expect(
        reparsedPriorityDowngrade.ready.map((task) => task.id),
        equals([
          'pr2000OkD2',
          'pr3000OkD2',
          'pr4000OkD2',
          'pr5000OkD2',
          'pf1000OkD2',
        ]),
        reason: 'Reparsed TDF 0.5.0 document must keep pf1000OkD2 at Ready slot 8 ahead of pp1000OkD2 in Planned via saved queue block',
      );
      expect(
        reparsedPriorityDowngrade.planned.map((task) => task.id),
        equals(['pp1000OkD2', 'regp20OkD2']),
      );

      final afterReadyDowngrade = fullBoard.downgradeTask(
        'r10000OkD2',
        currentDate: fixedDate,
      );
      expect(
        afterReadyDowngrade.ready.map((task) => task.id),
        equals([
          'r20000OkD2',
          'r30000OkD2',
          'r40000OkD2',
          'r50000OkD2',
          'p10000OkD2',
        ]),
        reason: 'Task at position 9 (p10000OkD2) must advance into position 8 (Ready)',
      );
      expect(
        afterReadyDowngrade.planned.map((task) => task.id),
        equals(['p20000OkD2', 'r10000OkD2']),
        reason: 'Downgraded Ready task must move to the end of Planned',
      );
      expect(
        afterReadyDowngrade.findTask('r10000OkD2')?.queuedAt,
        equals(DateTime.utc(2026, 11, 1, 8, 15)),
        reason: 'Section 6.3: Downgrading Ready to Planned must preserve queuedAt and move entry to the end of queue',
      );

      final afterPlannedDowngrade = afterReadyDowngrade.downgradeTask(
        'p20000OkD2',
        currentDate: fixedDate,
      );
      expect(
        afterPlannedDowngrade.planned.map((task) => task.id),
        equals(['r10000OkD2']),
        reason: 'Downgraded Planned task p20000OkD2 must leave Planned',
      );
      expect(
        afterPlannedDowngrade.someday.map((task) => task.id),
        equals(['p20000OkD2']),
        reason: 'Downgrading a Planned task must move it to Someday per Section 6.3',
      );
      expect(
        afterPlannedDowngrade.findTask('p20000OkD2')?.queuedAt,
        isNull,
        reason: 'Downgrading from Planned to Someday must omit queued per Section 6.3',
      );
      expect(
        afterPlannedDowngrade.queueTaskIds.contains('p20000OkD2'),
        isFalse,
        reason: 'Downgrading from Planned to Someday must remove the task from queue',
      );

      final afterPriorityPlannedDowngrade = afterPriorityFocusDowngrade
          .downgradeTask('pp1000OkD2', currentDate: fixedDate);
      expect(
        afterPriorityPlannedDowngrade.planned.map((task) => task.id),
        equals(['regp20OkD2']),
        reason:
            'Downgraded priority Planned task pp1000OkD2 must leave Planned',
      );
      expect(
        afterPriorityPlannedDowngrade.someday.map((task) => task.id),
        equals(['pp1000OkD2']),
        reason:
            'Downgraded priority Planned task pp1000OkD2 must move to Someday',
      );
      expect(
        afterPriorityPlannedDowngrade.findTask('pp1000OkD2')?.isPriority,
        isFalse,
        reason: 'Downgrading a priority Planned task to Someday must remove the priority flag per Section 6.3',
      );
      expect(
        afterPriorityPlannedDowngrade.findTask('pp1000OkD2')?.queuedAt,
        isNull,
        reason: 'Downgrading a priority Planned task to Someday must omit queued per Section 6.3',
      );

      final afterSomedayNoop = afterPlannedDowngrade.downgradeTask(
        'p20000OkD2',
        currentDate: fixedDate,
      );
      expect(
        afterSomedayNoop,
        equals(afterPlannedDowngrade),
        reason: 'Downgrading a Someday task must be a no-op per Section 6.3',
      );
    });
  });
}
