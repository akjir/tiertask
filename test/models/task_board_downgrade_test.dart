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

  group('TDF Section 6.3 Task Downgrade Transitions', () {
    test('executes Section 6.3 Focus-to-Ready (< 8 and >= 8 active tasks, priority alignment, +00:00:01 offset, collision shift), Ready-to-Planned, and Planned-to-Someday downgrades', () {
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
        afterPlannedDowngrade.planned.map((task) => task.id),
        equals(['r1']),
        reason: 'Downgraded Planned task p2 must leave Planned',
      );
      expect(
        afterPlannedDowngrade.someday.map((task) => task.id),
        equals(['p2']),
        reason: 'Downgrading a Planned task must move it to Someday per Section 6.3',
      );
      expect(
        afterPlannedDowngrade.findTask('p2')?.queuedAt,
        isNull,
        reason: 'Downgrading from Planned to Someday must omit queued per Section 6.3',
      );
      expect(
        afterPlannedDowngrade.findTask('p2')?.isPriority,
        isFalse,
        reason: 'Downgrading from Planned to Someday must remove priority per Section 6.3',
      );

      final afterPriorityPlannedDowngrade = afterPriorityFocusDowngrade
          .downgradeTask('pp1', currentDate: fixedDate);
      expect(
        afterPriorityPlannedDowngrade.planned.map((task) => task.id),
        equals(['reg_p2']),
        reason: 'Downgraded priority Planned task pp1 must leave Planned',
      );
      expect(
        afterPriorityPlannedDowngrade.someday.map((task) => task.id),
        equals(['pp1']),
        reason: 'Downgraded priority Planned task pp1 must move to Someday',
      );
      expect(
        afterPriorityPlannedDowngrade.findTask('pp1')?.isPriority,
        isFalse,
        reason: 'Downgrading a priority Planned task to Someday must remove the priority flag per Section 6.3',
      );
      expect(
        afterPriorityPlannedDowngrade.findTask('pp1')?.queuedAt,
        isNull,
        reason: 'Downgrading a priority Planned task to Someday must omit queued per Section 6.3',
      );

      final afterSomedayNoop = afterPlannedDowngrade.downgradeTask(
        'p2',
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
