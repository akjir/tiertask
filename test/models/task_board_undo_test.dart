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
import 'package:tiertask/models/task_board_undo.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';
import 'package:tiertask/services/tdf_serializer.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 1, 9);
  final t1 = DateTime.utc(2026, 11, 1, 10);
  final t2 = DateTime.utc(2026, 11, 1, 11);
  final t3 = DateTime.utc(2026, 11, 1, 12);

  test('TaskUndoEntry and TaskUndoOutcome enforce value equality, hashCode, and maxUndoEntries = 10', () {
    expect(TaskBoardUndo.maxUndoEntries, equals(10));
    final task = TaskItem(id: '000001OkD2', title: 'Task One', createdAt: t0);
    final entryA = TaskUndoEntry(
      sequence: 1,
      kind: TaskUndoActionKind.complete,
      snapshotTask: task,
      wasQueued: true,
      queueOrderSnapshot: const <String>['000001OkD2'],
      hadOnlyScopedLabels: false,
      previouslyBlockedDependentIds: const <String>{'000002OkD2'},
    );
    final entryB = TaskUndoEntry(
      sequence: 1,
      kind: TaskUndoActionKind.complete,
      snapshotTask: task,
      wasQueued: true,
      queueOrderSnapshot: const <String>['000001OkD2'],
      hadOnlyScopedLabels: false,
      previouslyBlockedDependentIds: const <String>{'000002OkD2'},
    );
    expect(entryA, equals(entryB));
    expect(entryA.hashCode, equals(entryB.hashCode));

    final board = TaskBoard.empty();
    final outcomeA = TaskUndoOutcome(
      board: board,
      taskConflictResolutions: const <String, TdfDeletionResolution>{
        '000001OkD2': TdfDeletionResolution.undelete,
      },
    );
    final outcomeB = TaskUndoOutcome(
      board: board,
      taskConflictResolutions: const <String, TdfDeletionResolution>{
        '000001OkD2': TdfDeletionResolution.undelete,
      },
    );
    expect(outcomeA, equals(outcomeB));
    expect(outcomeA.hashCode, equals(outcomeB.hashCode));
  });

  group('TaskUndoActionKind.complete', () {
    test('reverses standard completion, preserves monotonic completions and interim text/link edits, and re-arms only previously unsatisfied dependents', () {
      var board = TaskBoard.empty()
          .addTask(
            'Blocker Task',
            id: 'block1OkD2',
            targetTier: TaskTier.focus,
            isPriority: true,
            dueAt: DateTime.utc(2026, 11, 5, 18),
            currentDate: t0,
          )
          .addTask(
            'Middle Ready Task',
            id: 'ready1OkD2',
            targetTier: TaskTier.ready,
            currentDate: t0,
          );
      // Complete once then restore so completions == 1 before our second test setup:
      final alreadySatisfiedTask = TaskItem(
        id: 'alreadOkD2',
        title: 'Already Satisfied Dependent',
        createdAt: t0,
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'block1OkD2'),
        ],
      );
      final unsatisfiedTask = TaskItem(
        id: 'waitinOkD2',
        title: 'Waiting Dependent',
        createdAt: t0,
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'block1OkD2', requiredCompletion: 2),
        ],
      );
      final blockerAtOne = board
          .findTask('block1OkD2')!
          .copyWith(completions: 1);
      board = TaskBoard.evaluate(
        tasks: <TaskItem>[
          blockerAtOne,
          board.findTask('ready1OkD2')!,
          alreadySatisfiedTask,
          unsatisfiedTask,
        ],
        evaluationTime: t0,
        queueBlock: TdfQueueBlock(
          modifiedAt: t0,
          taskIds: const <String>[
            'block1OkD2',
            'ready1OkD2',
            'alreadOkD2',
            'waitinOkD2',
          ],
        ),
      );
      expect(board.findTierOfTask('alreadOkD2'), isNot(TaskTier.blocked));
      expect(board.findTierOfTask('waitinOkD2'), equals(TaskTier.blocked));

      final taskBefore = board.findTask('block1OkD2')!;
      final entry = TaskBoardUndo.capture(
        sequence: 1,
        kind: TaskUndoActionKind.complete,
        boardBefore: board,
        taskBefore: taskBefore,
      );
      expect(
        entry.previouslyBlockedDependentIds,
        equals(const <String>{'waitinOkD2'}),
        reason: 'Only dependents unsatisfied before completion must be recorded for re-arming',
      );

      var afterComplete = board.completeTask('block1OkD2', currentDate: t1);
      expect(afterComplete.findTask('block1OkD2')!.completions, equals(2));
      expect(
        afterComplete.findTierOfTask('waitinOkD2'),
        isNot(TaskTier.blocked),
        reason: 'Completing blocker to 2 unblocks waitinOkD2',
      );

      // Simulate interim title/note/link edit on the completed task before Undo:
      afterComplete = afterComplete.updateTask(
        'block1OkD2',
        title: 'Blocker Task Renamed',
        note: 'Added note after completion',
        links: const <TaskLink>[
          TaskLink(title: 'Docs', uri: 'https://example.com/docs'),
        ],
        currentDate: t2,
      );

      final outcome = TaskBoardUndo.apply(afterComplete, entry, utcNow: t3);
      expect(outcome, isNotNull);
      expect(outcome!.taskConflictResolutions, isEmpty);

      final restored = outcome.board.findTask('block1OkD2')!;
      expect(restored.isCompleted, isFalse);
      expect(restored.completedAt, isNull);
      expect(
        restored.completions,
        equals(2),
        reason: 'completions must remain monotonic (2, never reverted to 1)',
      );
      expect(restored.isPriority, isTrue);
      expect(restored.dueAt, equals(DateTime.utc(2026, 11, 5, 18)));
      expect(restored.title, equals('Blocker Task Renamed'));
      expect(restored.note, equals('Added note after completion'));
      expect(restored.links, hasLength(1));
      expect(
        outcome.board.findTierOfTask('block1OkD2'),
        equals(TaskTier.focus),
      );
      expect(
        outcome.board.queueTaskIds.first,
        equals('block1OkD2'),
        reason: 'Blocker task must return to the front of queueBlock',
      );

      expect(
        outcome.board.findTask('waitinOkD2')!.dependencies.single,
        equals(
          const TdfTaskDependency(taskId: 'block1OkD2', requiredCompletion: 3),
        ),
        reason: 'Previously blocked dependent must re-arm to completions + 1',
      );
      expect(
        outcome.board.findTierOfTask('waitinOkD2'),
        equals(TaskTier.blocked),
      );
      expect(
        outcome.board.findTask('alreadOkD2')!.dependencies.single,
        equals(const TdfTaskDependency(taskId: 'block1OkD2')),
        reason: 'Previously satisfied dependent must remain unblocked at :1',
      );
    });

    test('reverses recurring task completion and subtasks auto-finish completion accurately', () {
      final board = TaskBoard.empty().addTask(
        'Weekly Backup',
        id: 'recur1OkD2',
        targetTier: TaskTier.focus,
        isPriority: true,
        dueAt: DateTime.utc(2026, 11, 2, 9),
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.weeks),
        subtasksAutoFinish: true,
        subtasks: const <SubtaskItem>[
          SubtaskItem(title: 'Step 1', isCompleted: true),
          SubtaskItem(title: 'Step 2'),
        ],
        currentDate: t0,
      );
      final taskBefore = board.findTask('recur1OkD2')!;
      final entry = TaskBoardUndo.capture(
        sequence: 1,
        kind: TaskUndoActionKind.complete,
        boardBefore: board,
        taskBefore: taskBefore,
      );

      final afterAutoFinish = board.toggleSubtask(
        'recur1OkD2',
        1,
        currentDate: t1,
      );
      final rescheduled = afterAutoFinish.findTask('recur1OkD2')!;
      expect(rescheduled.completions, equals(1));
      expect(rescheduled.dueAt, equals(DateTime.utc(2026, 11, 9, 9)));
      expect(rescheduled.subtasks.every((step) => !step.isCompleted), isTrue);

      final outcome = TaskBoardUndo.apply(afterAutoFinish, entry, utcNow: t2);
      expect(outcome, isNotNull);
      final restored = outcome!.board.findTask('recur1OkD2')!;
      expect(restored.completions, equals(1));
      expect(restored.dueAt, equals(DateTime.utc(2026, 11, 2, 9)));
      expect(restored.suspendedAt, isNull);
      expect(restored.subtasks[0].isCompleted, isTrue);
      expect(
        restored.subtasks[1].isCompleted,
        isFalse,
        reason: 'Auto-finished subtask must revert to unchecked',
      );
      expect(
        outcome.board.findTierOfTask('recur1OkD2'),
        equals(TaskTier.focus),
      );
    });

    test('applies scoped-label flood protection when scoped-only label was deleted before undo', () {
      var board = TaskBoard.empty().addLabel(
        'Secret',
        id: 'scop01OkD2',
        isScoped: true,
        currentDate: t0,
      );
      board = board.addTask(
        'Scoped Focus Task',
        id: 'scopTkOkD2',
        targetTier: TaskTier.focus,
        isPriority: true,
        labelIds: const <String>['scop01OkD2'],
        currentDate: t0,
      );
      final taskBefore = board.findTask('scopTkOkD2')!;
      final entry = TaskBoardUndo.capture(
        sequence: 1,
        kind: TaskUndoActionKind.complete,
        boardBefore: board,
        taskBefore: taskBefore,
      );
      expect(entry.hadOnlyScopedLabels, isTrue);

      final afterCompleteAndDeleteLabel = board
          .completeTask('scopTkOkD2', currentDate: t1)
          .deleteLabel('scop01OkD2', currentDate: t2);

      final outcome = TaskBoardUndo.apply(
        afterCompleteAndDeleteLabel,
        entry,
        utcNow: t3,
      );
      expect(outcome, isNotNull);
      final restored = outcome!.board.findTask('scopTkOkD2')!;
      expect(restored.isPriority, isFalse);
      expect(outcome.board.queueTaskIds, isNot(contains('scopTkOkD2')));
      expect(
        outcome.board.findTierOfTask('scopTkOkD2'),
        equals(TaskTier.someday),
        reason: 'Restoring task whose only scoped label was deleted must route to Someday',
      );
    });
  });

  group('TaskUndoActionKind.downgrade', () {
    test('reverses Focus -> Ready, Ready -> Planned, and Planned -> Someday with exact queue slot', () {
      final board = TaskBoard.empty()
          .addTask(
            'Task A',
            id: 'taskA0OkD2',
            targetTier: TaskTier.focus,
            isPriority: true,
            currentDate: t0,
          )
          .addTask(
            'Task B',
            id: 'taskB0OkD2',
            targetTier: TaskTier.ready,
            currentDate: t0,
          )
          .addTask('Task C', id: 'taskC0OkD2', currentDate: t0);
      // Force explicit tiers (A=Focus priority, B=Ready, C=Planned):
      final seeded = TaskBoard.evaluate(
        tasks: <TaskItem>[
          board.findTask('taskA0OkD2')!,
          board.findTask('taskB0OkD2')!,
          board.findTask('taskC0OkD2')!,
        ],
        evaluationTime: t0,
        queueBlock: TdfQueueBlock(
          modifiedAt: t0,
          taskIds: const <String>['taskA0OkD2', 'taskB0OkD2', 'taskC0OkD2'],
        ),
      );

      // 1. Focus -> Ready
      final entryFocus = TaskBoardUndo.capture(
        sequence: 1,
        kind: TaskUndoActionKind.downgrade,
        boardBefore: seeded,
        taskBefore: seeded.findTask('taskA0OkD2')!,
      );
      final downgradedFromFocus = seeded.downgradeTask(
        'taskA0OkD2',
        currentDate: t1,
      );
      expect(downgradedFromFocus.findTask('taskA0OkD2')!.isPriority, isFalse);
      final undoneFocus = TaskBoardUndo.apply(
        downgradedFromFocus,
        entryFocus,
        utcNow: t2,
      );
      expect(undoneFocus, isNotNull);
      expect(undoneFocus!.board.findTask('taskA0OkD2')!.isPriority, isTrue);
      expect(
        undoneFocus.board.queueTaskIds,
        equals(const <String>['taskA0OkD2', 'taskB0OkD2', 'taskC0OkD2']),
      );

      // 2. Planned -> Someday (add 5 focus + 7 ready tasks or downgrade C directly when C is in Planned)
      final fillerTasks = <TaskItem>[
        for (var i = 0; i < 12; i++)
          TaskItem(
            id: 'fill${i.toString().padLeft(2, '0')}OkD2',
            title: 'Filler $i',
            isPriority: i < 5,
            createdAt: t0,
          ),
        TaskItem(id: 'planX0OkD2', title: 'Planned Target', createdAt: t0),
        TaskItem(id: 'planY0OkD2', title: 'Planned Tail', createdAt: t0),
      ];
      final fullBoard = TaskBoard.evaluate(
        tasks: fillerTasks,
        evaluationTime: t0,
        queueBlock: TdfQueueBlock(
          modifiedAt: t0,
          taskIds: <String>[for (final item in fillerTasks) item.id],
        ),
      );
      expect(fullBoard.findTierOfTask('planX0OkD2'), equals(TaskTier.planned));
      final entryPlanned = TaskBoardUndo.capture(
        sequence: 2,
        kind: TaskUndoActionKind.downgrade,
        boardBefore: fullBoard,
        taskBefore: fullBoard.findTask('planX0OkD2')!,
      );
      final downgradedToSomeday = fullBoard.downgradeTask(
        'planX0OkD2',
        currentDate: t1,
      );
      expect(
        downgradedToSomeday.findTierOfTask('planX0OkD2'),
        equals(TaskTier.someday),
      );
      final undonePlanned = TaskBoardUndo.apply(
        downgradedToSomeday,
        entryPlanned,
        utcNow: t2,
      );
      expect(undonePlanned, isNotNull);
      expect(
        undonePlanned!.board.findTierOfTask('planX0OkD2'),
        equals(TaskTier.planned),
      );
      expect(
        undonePlanned.board.queueTaskIds.sublist(12),
        equals(const <String>['planX0OkD2', 'planY0OkD2']),
        reason: 'Undoing Planned -> Someday must restore exact relative queue slot before planY0OkD2',
      );
    });
  });

  group('TaskUndoActionKind.delete', () {
    test('reverses multi-task deletions in LIFO order, advances deleted.generation, emits undelete resolution, and preserves newly added tasks', () {
      var board = TaskBoard.evaluate(
        tasks: <TaskItem>[
          TaskItem(id: 'taskA0OkD2', title: 'Task A', createdAt: t0),
          TaskItem(id: 'taskB0OkD2', title: 'Task B', createdAt: t0),
          TaskItem(id: 'taskC0OkD2', title: 'Task C', createdAt: t0),
          TaskItem(id: 'taskD0OkD2', title: 'Task D', createdAt: t0),
        ],
        evaluationTime: t0,
        queueBlock: TdfQueueBlock(
          modifiedAt: t0,
          taskIds: const <String>[
            'taskA0OkD2',
            'taskB0OkD2',
            'taskC0OkD2',
            'taskD0OkD2',
          ],
        ),
      );

      final entryA = TaskBoardUndo.capture(
        sequence: 1,
        kind: TaskUndoActionKind.delete,
        boardBefore: board,
        taskBefore: board.findTask('taskA0OkD2')!,
      );
      board = board.deleteTask('taskA0OkD2', currentDate: t1);

      final entryC = TaskBoardUndo.capture(
        sequence: 2,
        kind: TaskUndoActionKind.delete,
        boardBefore: board,
        taskBefore: board.findTask('taskC0OkD2')!,
      );
      board = board.deleteTask('taskC0OkD2', currentDate: t1);

      final entryD = TaskBoardUndo.capture(
        sequence: 3,
        kind: TaskUndoActionKind.delete,
        boardBefore: board,
        taskBefore: board.findTask('taskD0OkD2')!,
      );
      board = board.deleteTask('taskD0OkD2', currentDate: t1);

      // Add unrelated new task E in the interim:
      board = board.addTask('Task E', id: 'taskE0OkD2', currentDate: t2);
      expect(
        board.queueTaskIds,
        equals(const <String>['taskB0OkD2', 'taskE0OkD2']),
      );

      // Undo D, C, A in LIFO order:
      final outD = TaskBoardUndo.apply(board, entryD, utcNow: t3)!;
      expect(
        outD.taskConflictResolutions,
        equals(const <String, TdfDeletionResolution>{
          'taskD0OkD2': TdfDeletionResolution.undelete,
        }),
      );
      expect(outD.board.deletedBlock.generation, equals(1));
      expect(outD.board.deletedBlock.findTaskRecord('taskD0OkD2'), isNull);

      final outC = TaskBoardUndo.apply(outD.board, entryC, utcNow: t3)!;
      expect(outC.board.deletedBlock.generation, equals(2));

      final outA = TaskBoardUndo.apply(outC.board, entryA, utcNow: t3)!;
      expect(outA.board.deletedBlock.generation, equals(3));
      expect(
        outA.board.queueTaskIds,
        equals(const <String>[
          'taskA0OkD2',
          'taskB0OkD2',
          'taskC0OkD2',
          'taskD0OkD2',
          'taskE0OkD2',
        ]),
        reason: 'LIFO undo of first/middle/last deletions must reconstruct exact relative queue order while keeping newly added Task E',
      );
    });

    test('restores deleted Completed task without re-pruning and sanitizes deleted location with GroupResetTaskCondition', () {
      const office = TdfLocation(
        id: 'locOffOkD2',
        name: 'Office',
        latitude: 52.52,
        longitude: 13.405,
        radius: 100,
      );
      const home = TdfLocation(
        id: 'locHomOkD2',
        name: 'Home',
        latitude: 48.135,
        longitude: 11.582,
        radius: 100,
      );
      final workLabel = TdfLabel(
        id: 'lblWrkOkD2',
        name: 'Work',
        conditions: <TaskCondition>[
          LocationTaskCondition.fromIds(const <String>['locOffOkD2']),
        ],
      );
      final openTaskWithOverride = TaskItem(
        id: 'locOvrOkD2',
        title: 'Work From Home Override',
        createdAt: t0,
        labelIds: const <String>['lblWrkOkD2'],
        conditions: <TaskCondition>[
          LocationTaskCondition.fromIds(const <String>['locHomOkD2']),
        ],
      );
      final oldCompleted = TaskItem(
        id: 'oldCmpOkD2',
        title: 'Completed 40 Days Ago',
        isCompleted: true,
        completions: 4,
        createdAt: DateTime.utc(2026, 9),
        completedAt: DateTime.utc(2026, 9, 15),
      );

      var board = TaskBoard.evaluate(
        tasks: <TaskItem>[openTaskWithOverride, oldCompleted],
        labels: <TdfLabel>[workLabel],
        locations: const <TdfLocation>[office, home],
        evaluationTime: t0,
      );

      final entryOverride = TaskBoardUndo.capture(
        sequence: 1,
        kind: TaskUndoActionKind.delete,
        boardBefore: board,
        taskBefore: board.findTask('locOvrOkD2')!,
      );
      final entryCompleted = TaskBoardUndo.capture(
        sequence: 2,
        kind: TaskUndoActionKind.delete,
        boardBefore: board,
        taskBefore: board.findTask('oldCmpOkD2')!,
      );

      board = board
          .deleteTask('locOvrOkD2', currentDate: t1)
          .deleteTask('oldCmpOkD2', currentDate: t1)
          .deleteLocation('locHomOkD2', currentDate: t2);

      final outCompleted = TaskBoardUndo.apply(
        board,
        entryCompleted,
        utcNow: t3,
      )!;
      expect(
        outCompleted.board.findTierOfTask('oldCmpOkD2'),
        equals(TaskTier.completed),
        reason: 'Undoing deletion of a completed task must not immediately prune it',
      );
      expect(outCompleted.board.queueTaskIds, isNot(contains('oldCmpOkD2')));

      final outOverride = TaskBoardUndo.apply(
        outCompleted.board,
        entryOverride,
        utcNow: t3,
      )!;
      final restoredOverride = outOverride.board.findTask('locOvrOkD2')!;
      expect(
        restoredOverride.conditions,
        contains(
          const GroupResetTaskCondition(targetGroup: ConditionGroup.location),
        ),
        reason: 'Deleting overridden location while assigned label still has a location rule must inject location any reset',
      );
      // Must serialize cleanly without unknown location reference errors:
      expect(() => TdfSerializer.serialize(outOverride.board), returnsNormally);
    });
  });

  group('Skip branches and resource bounds (M-EXHAUSTIVE-STATE-TESTS, M-EXTREME-BOUND-TESTS)', () {
    test('skips missing/invalid states, dependency cycles, queue limits, block limits, and generation limits', () {
      final taskA = TaskItem(
        id: 'taskA0OkD2',
        title: 'Task A',
        createdAt: t0,
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'taskB0OkD2'),
        ],
      );
      final taskB = TaskItem(id: 'taskB0OkD2', title: 'Task B', createdAt: t0);
      final board = TaskBoard.evaluate(
        tasks: <TaskItem>[taskA, taskB],
        evaluationTime: t0,
        queueBlock: TdfQueueBlock(
          modifiedAt: t0,
          taskIds: const <String>['taskA0OkD2', 'taskB0OkD2'],
        ),
      );

      // 1. task_missing on complete
      final completeEntry = TaskUndoUndoHelper.capture(
        1,
        TaskUndoActionKind.complete,
        board,
        taskA,
      );
      expect(
        TaskBoardUndo.apply(TaskBoard.empty(), completeEntry, utcNow: t1),
        isNull,
        reason: 'complete undo must return null when target task is missing',
      );

      // 2. task_not_open & already_at_target_state on downgrade
      final downgradeEntry = TaskUndoUndoHelper.capture(
        2,
        TaskUndoActionKind.downgrade,
        board,
        taskB,
      );
      expect(
        TaskBoardUndo.apply(
          board.completeTask('taskB0OkD2', currentDate: t1),
          downgradeEntry,
          utcNow: t2,
        ),
        isNull,
        reason: 'downgrade undo must return null when task is completed',
      );
      expect(
        TaskBoardUndo.apply(board, downgradeEntry, utcNow: t2),
        isNull,
        reason: 'downgrade undo must return null when task is already at target state',
      );

      // 3. task_already_live on delete
      final deleteEntryA = TaskUndoUndoHelper.capture(
        3,
        TaskUndoActionKind.delete,
        board,
        taskA,
      );
      expect(
        TaskBoardUndo.apply(board, deleteEntryA, utcNow: t2),
        isNull,
        reason: 'delete undo must return null when task ID is already live',
      );

      // 4. dependency_cycle on delete (A depends on B; after A deleted, B edited to depend on A)
      final afterDeleteA = board.deleteTask('taskA0OkD2', currentDate: t1);
      final boardWithCycleTrap = TaskBoard.evaluate(
        tasks: <TaskItem>[
          afterDeleteA
              .findTask('taskB0OkD2')!
              .copyWith(
                dependencies: const <TdfTaskDependency>[
                  TdfTaskDependency(taskId: 'taskA0OkD2'),
                ],
              ),
        ],
        deletedBlock: afterDeleteA.deletedBlock,
        queueBlock: afterDeleteA.queueBlock,
        evaluationTime: t1,
      );
      expect(
        TaskBoardUndo.apply(boardWithCycleTrap, deleteEntryA, utcNow: t2),
        isNull,
        reason: 'delete undo must return null if restoring task creates a dependency cycle',
      );

      // 5. generation_limit_exceeded on delete
      final maxGenBoard = afterDeleteA.copyWith(
        deletedBlock: afterDeleteA.deletedBlock.copyWith(
          generation: TdfDeletedBlock.maxGeneration,
        ),
      );
      expect(
        TaskBoardUndo.apply(maxGenBoard, deleteEntryA, utcNow: t2),
        isNull,
        reason: 'delete undo must return null when deletedBlock.generation == maxGeneration',
      );

      // 6. queue_limit_exceeded (4096 queued tasks)
      final maxQueueTasks = <TaskItem>[
        for (var i = 0; i < TdfQueueBlock.maxQueueEntries; i++)
          TaskItem(
            id: 'q${i.toString().padLeft(5, '0')}OkD2',
            title: 'Q $i',
            createdAt: t0,
          ),
      ];
      // Note: 4096 tasks + 2 > 4096 root blocks, so test queue_limit_exceeded on downgrade undo
      // where task is already a live Someday task on a board with fewer nested blocks? Wait:
      // TdfQueueBlock.maxQueueEntries is 4096, and on downgrade undo the task is ALREADY live,
      // or test queue_limit_exceeded with 4096 IDs in queueBlock!
      final somedayBoard = TaskBoard.evaluate(
        tasks: <TaskItem>[
          TaskItem(id: 'some01OkD2', title: 'Target', createdAt: t0),
          for (var i = 0; i < TdfQueueBlock.maxQueueEntries; i++)
            TaskItem(
              id: 'q${i.toString().padLeft(5, '0')}OkD2',
              title: 'Q $i',
              createdAt: t0,
            ),
        ],
        evaluationTime: t0,
        queueBlock: TdfQueueBlock(
          modifiedAt: t0,
          taskIds: <String>[for (final item in maxQueueTasks) item.id],
        ),
      );
      final queuedSnapshotEntry = TaskUndoEntry(
        sequence: 4,
        kind: TaskUndoActionKind.downgrade,
        snapshotTask: TaskItem(
          id: 'some01OkD2',
          title: 'Target',
          createdAt: t0,
        ),
        wasQueued: true,
        queueOrderSnapshot: const <String>['some01OkD2'],
        hadOnlyScopedLabels: false,
      );
      expect(
        TaskBoardUndo.apply(somedayBoard, queuedSnapshotEntry, utcNow: t2),
        isNull,
        reason: 'undo must return null when inserting into queue would exceed maxQueueEntries (4096)',
      );

      // 7. block_limit_exceeded (nested subtasks + multi-rule conditions pushing total blocks > 4096)
      final heavyTasks = <TaskItem>[
        for (var i = 0; i < 1365; i++)
          TaskItem(
            id: 'hv${i.toString().padLeft(4, '0')}OkD2',
            title: 'Heavy $i',
            createdAt: t0,
            subtasks: const <SubtaskItem>[SubtaskItem(title: 'Step')],
            conditions: <TaskCondition>[
              DayTaskCondition.fromWeekdays(const <int>[DateTime.monday]),
              TimeWindowTaskCondition.tryParse('09:00', '17:00')!,
            ],
          ),
      ];
      // Each heavyTask emits 3 `{ ... }` blocks (task + condition + subtasks): 1365 * 3 = 4095 blocks + deleted (1) = 4096 blocks!
      final fullBlockBoard = TaskBoard.evaluate(
        tasks: heavyTasks,
        deletedBlock: afterDeleteA.deletedBlock,
        evaluationTime: t1,
      );
      expect(
        TaskBoardUndo.apply(fullBlockBoard, deleteEntryA, utcNow: t2),
        isNull,
        reason: 'delete undo must return null when serialized { ... } block count would exceed maxTdfBlocksPerDoc (4096)',
      );
    });
  });

  group('TDF 0.7.0 Undo Reversibility, Metadata Restoration & Atomic Guards', () {
    test('captures stripped dependencies accurately via TaskUndoEntry.captureStrippedDependencies and includes previouslyBlockedDependencies in equality/hashCode', () {
      final prereq = TaskItem(
        id: 'pre001OkD2',
        title: 'One-Shot Prereq',
        createdAt: t0,
        completions: 1,
      );
      final depSatisfied = TaskItem(
        id: 'depSatOkD2',
        title: 'Satisfied at 1',
        createdAt: t0,
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'pre001OkD2'),
        ],
      );
      final depResolvedNow = TaskItem(
        id: 'depResOkD2',
        title: 'Resolved at 2',
        createdAt: t0,
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'pre001OkD2', requiredCompletion: 2),
        ],
      );
      final depStillWaiting = TaskItem(
        id: 'depHi5OkD2',
        title: 'Still waiting for 5',
        createdAt: t0,
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'pre001OkD2', requiredCompletion: 5),
        ],
      );

      final before = TaskBoard.evaluate(
        tasks: <TaskItem>[
          prereq,
          depSatisfied,
          depResolvedNow,
          depStillWaiting,
        ],
        evaluationTime: t0,
      );
      final after = before.completeTask('pre001OkD2', currentDate: t1);

      final stripped = TaskUndoEntry.captureStrippedDependencies(
        boardBefore: before,
        boardAfter: after,
        targetTaskId: 'pre001OkD2',
      );
      expect(
        stripped,
        equals(const <String, TdfTaskDependency>{
          'depSatOkD2': TdfTaskDependency(taskId: 'pre001OkD2'),
          'depResOkD2': TdfTaskDependency(
            taskId: 'pre001OkD2',
            requiredCompletion: 2,
          ),
        }),
        reason: 'Higher unsatisfied threshold :5 must remain untouched and excluded from stripped map',
      );

      final entry1 = TaskBoardUndo.capture(
        sequence: 1,
        kind: TaskUndoActionKind.complete,
        boardBefore: before,
        boardAfter: after,
        taskBefore: prereq,
      );
      final entry2 = TaskUndoEntry(
        sequence: 1,
        kind: TaskUndoActionKind.complete,
        snapshotTask: prereq,
        wasQueued: false,
        queueOrderSnapshot: const <String>[],
        hadOnlyScopedLabels: false,
        previouslyBlockedDependentIds: const <String>{
          'depResOkD2',
          'depHi5OkD2',
        },
        previouslyBlockedDependencies: stripped,
      );
      final entryDifferentMap = TaskUndoEntry(
        sequence: 1,
        kind: TaskUndoActionKind.complete,
        snapshotTask: prereq,
        wasQueued: false,
        queueOrderSnapshot: const <String>[],
        hadOnlyScopedLabels: false,
        previouslyBlockedDependentIds: const <String>{
          'depResOkD2',
          'depHi5OkD2',
        },
      );
      expect(entry1, equals(entry2));
      expect(entry1.hashCode, equals(entry2.hashCode));
      expect(entry1, isNot(equals(entryDifferentMap)));
    });

    test('restores suspendedNote (stripping expired <= now), dueNote, isDuePassive, and history across complete, delete, and urgent-due downgrade undo', () {
      final hist = <TaskHistoryEntry>[
        TaskHistoryEntry(timestampUtc: t0, text: 'Started work'),
      ];

      // 1. Urgent-due Focus -> Ready downgrade (only isDuePassive changed from false -> true!)
      final dueBoard = TaskBoard.evaluate(
        tasks: <TaskItem>[
          TaskItem(id: 'reg001OkD2', title: 'Regular 1', createdAt: t0),
          TaskItem(id: 'reg002OkD2', title: 'Regular 2', createdAt: t0),
          TaskItem(id: 'reg003OkD2', title: 'Regular 3', createdAt: t0),
          TaskItem(
            id: 'urgDueOkD2',
            title: 'Urgent Due Task',
            createdAt: t0,
            dueAt: t0.add(const Duration(hours: 6)),
            dueNote: 'Submit before 15:00',
            history: hist,
          ),
        ],
        queueBlock: TdfQueueBlock(
          modifiedAt: t0,
          taskIds: const <String>[
            'reg001OkD2',
            'reg002OkD2',
            'reg003OkD2',
            'urgDueOkD2',
          ],
        ),
        evaluationTime: t0,
      );
      expect(dueBoard.findTierOfTask('urgDueOkD2'), equals(TaskTier.focus));

      final urgentBefore = dueBoard.findTask('urgDueOkD2')!;
      expect(urgentBefore.isPriority, isFalse);
      expect(urgentBefore.isDuePassive, isFalse);

      final downgradedBoard = dueBoard.downgradeTask(
        'urgDueOkD2',
        currentDate: t1,
      );
      expect(
        downgradedBoard.findTask('urgDueOkD2')!.isDuePassive,
        isTrue,
        reason:
            'Downgrading deadline-promoted Focus task sets isDuePassive = true',
      );
      expect(
        downgradedBoard.findTierOfTask('urgDueOkD2'),
        isNot(TaskTier.focus),
      );

      final downgradeEntry = TaskBoardUndo.capture(
        sequence: 1,
        kind: TaskUndoActionKind.downgrade,
        boardBefore: dueBoard,
        boardAfter: downgradedBoard,
        taskBefore: urgentBefore,
      );
      final undoneDowngrade = TaskBoardUndo.apply(
        downgradedBoard,
        downgradeEntry,
        utcNow: t2,
      );
      expect(undoneDowngrade, isNotNull);
      final restoredUrgent = undoneDowngrade!.board.findTask('urgDueOkD2')!;
      expect(restoredUrgent.isDuePassive, isFalse);
      expect(restoredUrgent.dueNote, equals('Submit before 15:00'));
      expect(restoredUrgent.history, equals(hist));
      expect(
        undoneDowngrade.board.findTierOfTask('urgDueOkD2'),
        equals(TaskTier.focus),
      );

      // 2. Complete & Delete undo with future vs expired suspendedAt + suspendedNote + dependent re-insertion:
      final futureDeferral = DateTime.utc(2026, 11, 2, 9);
      final expiredDeferral = DateTime.utc(2026, 11, 1, 11, 30);
      final targetFuture = TaskItem(
        id: 'delFutOkD2',
        title: 'Future Deferred Target',
        createdAt: t0,
        modifiedAt: t0,
        suspendedAt: futureDeferral,
        suspendedNote: 'Keep future note',
        dueAt: DateTime.utc(2026, 11, 5, 17),
        isDuePassive: true,
        dueNote: 'Passive cutoff note',
        history: hist,
      );
      final targetExpired = TaskItem(
        id: 'cmpExpOkD2',
        title: 'Expired Deferred Target',
        createdAt: t0,
        modifiedAt: t0,
        suspendedAt: expiredDeferral,
        suspendedNote: 'Must strip with expired deferral',
        dueAt: DateTime.utc(2026, 11, 5, 17),
        dueNote: 'Active cutoff note',
        history: hist,
      );
      final openDep = TaskItem(
        id: 'opnDepOkD2',
        title: 'Surviving Open Dependent',
        createdAt: t0,
        modifiedAt: t0,
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'delFutOkD2', requiredCompletion: 2),
        ],
      );

      final delBefore = TaskBoard.evaluate(
        tasks: <TaskItem>[targetFuture, openDep],
        evaluationTime: t0,
      );
      final delAfter = delBefore.deleteTask('delFutOkD2', currentDate: t1);
      expect(delAfter.findTask('opnDepOkD2')!.dependencies, isEmpty);

      final delEntry = TaskBoardUndo.capture(
        sequence: 2,
        kind: TaskUndoActionKind.delete,
        boardBefore: delBefore,
        boardAfter: delAfter,
        taskBefore: targetFuture,
      );
      final undoneDelete = TaskBoardUndo.apply(delAfter, delEntry, utcNow: t3)!;
      final restoredDel = undoneDelete.board.findTask('delFutOkD2')!;
      expect(restoredDel.suspendedAt, equals(futureDeferral));
      expect(restoredDel.suspendedNote, equals('Keep future note'));
      expect(restoredDel.isDuePassive, isTrue);
      expect(restoredDel.dueNote, equals('Passive cutoff note'));
      expect(restoredDel.history, equals(hist));
      expect(
        undoneDelete.board.findTask('opnDepOkD2')!.dependencies,
        equals(const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'delFutOkD2', requiredCompletion: 2),
        ]),
        reason: 'Delete undo must re-insert stripped dependency verbatim on surviving open dependent',
      );
      expect(undoneDelete.board.findTask('opnDepOkD2')!.modifiedAt, equals(t3));

      // Complete undo at t3 (12:00) when snapshot suspendedAt was 11:30 (<= t3):
      final cmpBefore = TaskBoard.evaluate(
        tasks: <TaskItem>[targetExpired],
        evaluationTime: t0,
      );
      final cmpAfter = cmpBefore.completeTask('cmpExpOkD2', currentDate: t1);
      final cmpEntry = TaskBoardUndo.capture(
        sequence: 3,
        kind: TaskUndoActionKind.complete,
        boardBefore: cmpBefore,
        boardAfter: cmpAfter,
        taskBefore: targetExpired,
      );
      final undoneComplete = TaskBoardUndo.apply(
        cmpAfter,
        cmpEntry,
        utcNow: t3,
      )!;
      final restoredCmp = undoneComplete.board.findTask('cmpExpOkD2')!;
      expect(
        restoredCmp.suspendedAt,
        isNull,
        reason: 'Expired snapshot suspendedAt <= now must be stripped on undo',
      );
      expect(
        restoredCmp.suspendedNote,
        isNull,
        reason:
            'Coupled suspendedNote must be stripped with expired suspendedAt',
      );
      expect(restoredCmp.dueNote, equals('Active cutoff note'));
      expect(restoredCmp.history, equals(hist));
    });

    test('aborts entire undo atomically (returning null) on dependency_limit_exceeded, completions_limit_exceeded, timestamp_out_of_bounds, and statement_limit_exceeded', () {
      // 1. dependency_limit_exceeded (dependent already has 64 dependencies when re-inserting stripped dependency):
      final target = TaskItem(
        id: 'trgLimOkD2',
        title: 'Target',
        createdAt: t0,
        modifiedAt: t0,
      );
      final depInitial = TaskItem(
        id: 'depLimOkD2',
        title: 'Dependent',
        createdAt: t0,
        modifiedAt: t0,
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'trgLimOkD2'),
        ],
      );
      final beforeDepLim = TaskBoard.evaluate(
        tasks: <TaskItem>[target, depInitial],
        evaluationTime: t0,
      );
      final afterDepLim = beforeDepLim.deleteTask(
        'trgLimOkD2',
        currentDate: t1,
      );
      final depLimEntry = TaskBoardUndo.capture(
        sequence: 1,
        kind: TaskUndoActionKind.delete,
        boardBefore: beforeDepLim,
        boardAfter: afterDepLim,
        taskBefore: target,
      );
      final full64Deps = <TdfTaskDependency>[
        for (var i = 0; i < maxTdfArgsPerStmt; i++)
          TdfTaskDependency(taskId: 'ot${i.toString().padLeft(4, '0')}OkD2'),
      ];
      final boardAt64Deps = TaskBoard.evaluate(
        tasks: <TaskItem>[
          afterDepLim
              .findTask('depLimOkD2')!
              .copyWith(dependencies: full64Deps),
        ],
        deletedBlock: afterDepLim.deletedBlock,
        evaluationTime: t1,
      );
      expect(
        TaskBoardUndo.apply(boardAt64Deps, depLimEntry, utcNow: t2),
        isNull,
        reason:
            'Re-inserting a 65th dependency must abort entire undo atomically',
      );

      // 2. completions_limit_exceeded (restoredCompletions == 999999999 when re-arming is required):
      final maxCompTarget = target.copyWith(
        completions: TdfTaskDependency.maxCompletions - 1,
      );
      final maxCompDep = depInitial.copyWith(
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(
            taskId: 'trgLimOkD2',
            requiredCompletion: TdfTaskDependency.maxCompletions,
          ),
        ],
      );
      final beforeMaxComp = TaskBoard.evaluate(
        tasks: <TaskItem>[maxCompTarget, maxCompDep],
        evaluationTime: t0,
      );
      final afterMaxComp = beforeMaxComp.completeTask(
        'trgLimOkD2',
        currentDate: t1,
      );
      final maxCompEntry = TaskBoardUndo.capture(
        sequence: 2,
        kind: TaskUndoActionKind.complete,
        boardBefore: beforeMaxComp,
        boardAfter: afterMaxComp,
        taskBefore: maxCompTarget,
      );
      expect(
        TaskBoardUndo.apply(afterMaxComp, maxCompEntry, utcNow: t2),
        isNull,
        reason: 'Re-arming past 999,999,999 completions must abort entire undo atomically',
      );

      // 3. timestamp_out_of_bounds (modifiedAt at 9999-12-31 23:59:59Z needing +1s):
      final maxTs = DateTime.utc(9999, 12, 31, 23, 59, 59);
      final atMaxTsBoard = TaskBoard.evaluate(
        tasks: <TaskItem>[
          afterMaxComp
              .findTask('trgLimOkD2')!
              .copyWith(completions: 1, modifiedAt: maxTs),
        ],
        evaluationTime: maxTs,
      );
      final simpleCompleteEntry = TaskUndoEntry(
        sequence: 3,
        kind: TaskUndoActionKind.complete,
        snapshotTask: target,
        wasQueued: false,
        queueOrderSnapshot: const <String>[],
        hadOnlyScopedLabels: false,
      );
      expect(
        TaskBoardUndo.apply(atMaxTsBoard, simpleCompleteEntry, utcNow: maxTs),
        isNull,
        reason: 'Advancing past 9999-12-31 23:59:59Z must abort undo with null',
      );

      // 4. statement_limit_exceeded (subtasks block > maxTdfStmtsPerBlock = 1024):
      final oversizedSnapshot = target.copyWith(
        subtasks: <SubtaskItem>[
          for (var i = 0; i <= maxTdfStmtsPerBlock; i++)
            SubtaskItem(title: 'Step $i'),
        ],
      );
      final stmtLimitEntry = TaskUndoEntry(
        sequence: 4,
        kind: TaskUndoActionKind.delete,
        snapshotTask: oversizedSnapshot,
        wasQueued: false,
        queueOrderSnapshot: const <String>[],
        hadOnlyScopedLabels: false,
      );
      expect(
        TaskBoardUndo.apply(afterDepLim, stmtLimitEntry, utcNow: t2),
        isNull,
        reason:
            'Exceeding maxTdfStmtsPerBlock (1024) must abort undo with null',
      );
    });

    test('preserves live currentTask.history across one-off complete, repeat rollover complete, and downgrade undo while restoring snapshotTask.history on delete undo', () {
      final h0 = TaskHistoryEntry(timestampUtc: t0, text: 'Initial log');
      final h1 = TaskHistoryEntry(timestampUtc: t1, text: 'Follow-up log');
      final h2 = TaskHistoryEntry(timestampUtc: t2, text: 'Post-action log');

      // 1. One-off completeTask -> add/update/remove history -> Undo complete
      final oneOffBefore = TaskBoard.evaluate(
        tasks: <TaskItem>[
          TaskItem(
            id: 'oneOffHst1',
            title: 'One-off Task',
            isPriority: true,
            createdAt: t0,
            modifiedAt: t0,
            history: <TaskHistoryEntry>[h0, h1],
          ),
        ],
        evaluationTime: t0,
      );
      final oneOffTaskBefore = oneOffBefore.findTask('oneOffHst1')!;
      final oneOffCompleted = oneOffBefore.completeTask(
        'oneOffHst1',
        currentDate: t1,
      );
      final oneOffUndoEntry = TaskBoardUndo.capture(
        sequence: 10,
        kind: TaskUndoActionKind.complete,
        boardBefore: oneOffBefore,
        boardAfter: oneOffCompleted,
        taskBefore: oneOffTaskBefore,
      );
      final oneOffInterim = oneOffCompleted
          .addTaskHistoryEntry(
            'oneOffHst1',
            timestampUtc: t2,
            text: 'Temp post-complete log',
            currentDate: t2,
          )
          .updateTaskHistoryEntry(
            'oneOffHst1',
            oldEntry: TaskHistoryEntry(
              timestampUtc: t2,
              text: 'Temp post-complete log',
            ),
            newTimestampUtc: t2,
            newText: h2.text,
            currentDate: t2,
          )
          .removeTaskHistoryEntry('oneOffHst1', entry: h0, currentDate: t2);
      final oneOffUndone = TaskBoardUndo.apply(
        oneOffInterim,
        oneOffUndoEntry,
        utcNow: t3,
      );
      expect(oneOffUndone, isNotNull);
      final restoredOneOff = oneOffUndone!.board.findTask('oneOffHst1')!;
      expect(restoredOneOff.isCompleted, isFalse);
      expect(
        restoredOneOff.history,
        equals(<TaskHistoryEntry>[h1, h2]),
        reason:
            'Undoing one-off completion must preserve interim history edits',
      );

      // 2. Repeat rollover completeTask -> add/update/remove history -> Undo complete
      final repeatBefore = TaskBoard.evaluate(
        tasks: <TaskItem>[
          TaskItem(
            id: 'repHst0001',
            title: 'Meter Reading',
            isPriority: true,
            createdAt: t0,
            modifiedAt: t0,
            repeatRule: const TaskRepeatRule(count: 7, unit: RepeatUnit.days),
            history: <TaskHistoryEntry>[h0, h1],
          ),
        ],
        evaluationTime: t0,
      );
      final repeatTaskBefore = repeatBefore.findTask('repHst0001')!;
      final repeatRolled = repeatBefore.completeTask(
        'repHst0001',
        currentDate: t1,
      );
      final repeatUndoEntry = TaskBoardUndo.capture(
        sequence: 11,
        kind: TaskUndoActionKind.complete,
        boardBefore: repeatBefore,
        boardAfter: repeatRolled,
        taskBefore: repeatTaskBefore,
      );
      final repeatInterim = repeatRolled
          .addTaskHistoryEntry(
            'repHst0001',
            timestampUtc: t2,
            text: 'Draft reading',
            currentDate: t2,
          )
          .updateTaskHistoryEntry(
            'repHst0001',
            oldEntry: TaskHistoryEntry(timestampUtc: t2, text: 'Draft reading'),
            newTimestampUtc: t2,
            newText: h2.text,
            currentDate: t2,
          )
          .removeTaskHistoryEntry('repHst0001', entry: h0, currentDate: t2);
      final repeatUndone = TaskBoardUndo.apply(
        repeatInterim,
        repeatUndoEntry,
        utcNow: t3,
      );
      expect(repeatUndone, isNotNull);
      final restoredRepeat = repeatUndone!.board.findTask('repHst0001')!;
      expect(restoredRepeat.completions, equals(1));
      expect(restoredRepeat.suspendedAt, isNull);
      expect(
        restoredRepeat.history,
        equals(<TaskHistoryEntry>[h1, h2]),
        reason: 'Undoing repeat rollover completion must preserve interim history edits',
      );

      // 3. Downgrade -> add/update/remove history -> Undo downgrade (+ already-restored no-op guard)
      final downBefore = TaskBoard.evaluate(
        tasks: <TaskItem>[
          TaskItem(
            id: 'dwnHst0001',
            title: 'Downgrade Target',
            isPriority: true,
            createdAt: t0,
            modifiedAt: t0,
            history: <TaskHistoryEntry>[h0, h1],
          ),
        ],
        queueBlock: TdfQueueBlock(
          modifiedAt: t0,
          taskIds: const <String>['dwnHst0001'],
        ),
        evaluationTime: t0,
      );
      final downTaskBefore = downBefore.findTask('dwnHst0001')!;
      final downAfter = downBefore.downgradeTask('dwnHst0001', currentDate: t1);
      final downUndoEntry = TaskBoardUndo.capture(
        sequence: 12,
        kind: TaskUndoActionKind.downgrade,
        boardBefore: downBefore,
        boardAfter: downAfter,
        taskBefore: downTaskBefore,
      );
      final downInterim = downAfter
          .addTaskHistoryEntry(
            'dwnHst0001',
            timestampUtc: t2,
            text: 'Interim note',
            currentDate: t2,
          )
          .updateTaskHistoryEntry(
            'dwnHst0001',
            oldEntry: TaskHistoryEntry(timestampUtc: t2, text: 'Interim note'),
            newTimestampUtc: t2,
            newText: h2.text,
            currentDate: t2,
          )
          .removeTaskHistoryEntry('dwnHst0001', entry: h0, currentDate: t2);
      final downUndone = TaskBoardUndo.apply(
        downInterim,
        downUndoEntry,
        utcNow: t3,
      );
      expect(downUndone, isNotNull);
      final restoredDown = downUndone!.board.findTask('dwnHst0001')!;
      expect(restoredDown.isPriority, isTrue);
      expect(
        restoredDown.history,
        equals(<TaskHistoryEntry>[h1, h2]),
        reason: 'Undoing downgrade must preserve interim history edits',
      );
      expect(
        TaskBoardUndo.apply(downUndone.board, downUndoEntry, utcNow: t3),
        isNull,
        reason: 'Already-restored downgrade target whose only difference from snapshot is history must skip as already_at_target_state',
      );

      // 4. Delete -> Undo delete still restores snapshotTask.history
      final deletedBoard = downBefore.deleteTask('dwnHst0001', currentDate: t1);
      final deleteUndoEntry = TaskBoardUndo.capture(
        sequence: 13,
        kind: TaskUndoActionKind.delete,
        boardBefore: downBefore,
        boardAfter: deletedBoard,
        taskBefore: downTaskBefore,
      );
      final deleteUndone = TaskBoardUndo.apply(
        deletedBoard,
        deleteUndoEntry,
        utcNow: t3,
      );
      expect(deleteUndone, isNotNull);
      expect(
        deleteUndone!.board.findTask('dwnHst0001')!.history,
        equals(<TaskHistoryEntry>[h0, h1]),
        reason: 'Undoing task deletion must restore snapshotTask.history',
      );
    });
  });

  group('TDF 0.8.0 Schedule Anchor (dueAnchor) Undo Restoration & Concurrent Edit Guards', () {
    test('restores snapshotTask.dueAnchor across Mode 2 recurring complete, delete, and downgrade undo and rejects post-capture dueAnchor edits', () {
      final berlin = TdfTimeZoneContext.named('Europe/Berlin');
      final jan31Now = DateTime.utc(2026, 1, 31, 10);
      final jan31Anchor = TdfLocalDateTime(2026, 1, 31, 18);

      // 1. Mode 2 recurring task starting with dueAnchor == null completed onto clamped Feb 28 (synthesizing dueAnchor = Jan 31):
      // Undo must restore dueAt = Jan 31 AND dueAnchor = null!
      final unanchoredJan31 = TaskItem(
        id: 'm2NullAnc1',
        title: 'Monthly Closing Without Initial Anchor',
        isPriority: true,
        createdAt: jan31Now,
        modifiedAt: jan31Now,
        dueAt: DateTime.utc(2026, 1, 31, 17),
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.months),
      );
      final boardJan = TaskBoard.evaluate(
        tasks: <TaskItem>[unanchoredJan31],
        queueBlock: TdfQueueBlock(
          modifiedAt: jan31Now,
          taskIds: const <String>['m2NullAnc1'],
        ),
        evaluationTime: jan31Now,
        timeZone: berlin,
      );
      final boardFeb = boardJan.completeTask(
        'm2NullAnc1',
        currentDate: jan31Now.add(const Duration(hours: 1)),
        timeZone: berlin,
      );
      expect(
        boardFeb.findTask('m2NullAnc1')!.dueAt,
        equals(DateTime.utc(2026, 2, 28, 17)),
      );
      expect(
        boardFeb.findTask('m2NullAnc1')!.dueAnchor,
        equals(jan31Anchor),
        reason:
            'Precondition: Mode 2 clamp synthesizes Jan 31 anchor on Feb 28',
      );

      final janEntry = TaskBoardUndo.capture(
        sequence: 20,
        kind: TaskUndoActionKind.complete,
        boardBefore: boardJan,
        boardAfter: boardFeb,
        taskBefore: boardJan.findTask('m2NullAnc1')!,
      );
      final undoneJan = TaskBoardUndo.apply(
        boardFeb,
        janEntry,
        utcNow: jan31Now.add(const Duration(hours: 2)),
        timeZone: berlin,
      );
      expect(undoneJan, isNotNull);
      expect(
        undoneJan!.board.findTask('m2NullAnc1')!.dueAt,
        equals(DateTime.utc(2026, 1, 31, 17)),
      );
      expect(
        undoneJan.board.findTask('m2NullAnc1')!.dueAnchor,
        isNull,
        reason: 'Undoing Mode 2 rollover must clear synthesized dueAnchor back to snapshot null',
      );

      // 2. Mode 2 recurring task on clamped Feb 28 (dueAnchor = Jan 31) completed onto Mar 31 (advancing dueAnchor = Mar 31):
      // Undo must restore dueAt = Feb 28 AND dueAnchor = Jan 31!
      final febNow = DateTime.utc(2026, 2, 28, 10);
      final boardMar = boardFeb.completeTask(
        'm2NullAnc1',
        currentDate: febNow,
        timeZone: berlin,
      );
      expect(
        boardMar.findTask('m2NullAnc1')!.dueAnchor,
        equals(TdfLocalDateTime(2026, 3, 31, 18)),
      );
      final febEntry = TaskBoardUndo.capture(
        sequence: 21,
        kind: TaskUndoActionKind.complete,
        boardBefore: boardFeb,
        boardAfter: boardMar,
        taskBefore: boardFeb.findTask('m2NullAnc1')!,
      );
      final undoneFeb = TaskBoardUndo.apply(
        boardMar,
        febEntry,
        utcNow: febNow.add(const Duration(hours: 1)),
        timeZone: berlin,
      );
      expect(undoneFeb, isNotNull);
      expect(
        undoneFeb!.board.findTask('m2NullAnc1')!.dueAt,
        equals(DateTime.utc(2026, 2, 28, 17)),
      );
      expect(
        undoneFeb.board.findTask('m2NullAnc1')!.dueAnchor,
        equals(jan31Anchor),
        reason: 'Undoing Feb 28 -> Mar 31 rollover must restore clamped Jan 31 dueAnchor',
      );

      // Post-capture external edit to dueAnchor on Mode 2 completed task guards/skips undo:
      final marExternallyEdited = boardMar.updateTask(
        'm2NullAnc1',
        dueAnchor: TdfLocalDateTime(2026, 3, 30, 18),
        currentDate: febNow.add(const Duration(minutes: 30)),
        timeZone: berlin,
      );
      expect(
        TaskBoardUndo.apply(
          marExternallyEdited,
          febEntry,
          utcNow: febNow.add(const Duration(hours: 1)),
          timeZone: berlin,
        ),
        isNull,
        reason: 'Post-capture external edit to dueAnchor after Mode 2 completion must invalidate undo',
      );

      // 3. Delete undo & Downgrade undo preserve snapshotTask.dueAnchor, and post-capture dueAnchor edit invalidates downgrade/one-off-complete undo:
      final urgentClamped = TaskItem(
        id: 'urgClamp01',
        title: 'Urgent Clamped Deadline',
        createdAt: febNow,
        modifiedAt: febNow,
        dueAt: DateTime.utc(2026, 2, 28, 17),
        dueAnchor: jan31Anchor,
        dueNote: 'Clamped deadline',
      );
      final downBoardBefore = TaskBoard.evaluate(
        tasks: <TaskItem>[
          TaskItem(id: 'f001000001', title: 'F1', createdAt: febNow),
          TaskItem(id: 'f002000001', title: 'F2', createdAt: febNow),
          TaskItem(id: 'f003000001', title: 'F3', createdAt: febNow),
          urgentClamped,
        ],
        queueBlock: TdfQueueBlock(
          modifiedAt: febNow,
          taskIds: const <String>[
            'f001000001',
            'f002000001',
            'f003000001',
            'urgClamp01',
          ],
        ),
        evaluationTime: febNow,
        timeZone: berlin,
      );
      final downBoardAfter = downBoardBefore.downgradeTask(
        'urgClamp01',
        currentDate: febNow.add(const Duration(minutes: 5)),
        timeZone: berlin,
      );
      final downEntry = TaskBoardUndo.capture(
        sequence: 22,
        kind: TaskUndoActionKind.downgrade,
        boardBefore: downBoardBefore,
        boardAfter: downBoardAfter,
        taskBefore: downBoardBefore.findTask('urgClamp01')!,
      );
      final undoneDown = TaskBoardUndo.apply(
        downBoardAfter,
        downEntry,
        utcNow: febNow.add(const Duration(minutes: 10)),
        timeZone: berlin,
      );
      expect(undoneDown, isNotNull);
      expect(
        undoneDown!.board.findTask('urgClamp01')!.dueAnchor,
        equals(jan31Anchor),
      );
      expect(undoneDown.board.findTask('urgClamp01')!.isDuePassive, isFalse);

      // External edit clearing dueAnchor after downgrade invalidates downgrade undo:
      final downAnchorCleared = downBoardAfter.updateTask(
        'urgClamp01',
        clearDueAnchor: true,
        currentDate: febNow.add(const Duration(minutes: 6)),
        timeZone: berlin,
      );
      expect(
        TaskBoardUndo.apply(
          downAnchorCleared,
          downEntry,
          utcNow: febNow.add(const Duration(minutes: 10)),
          timeZone: berlin,
        ),
        isNull,
        reason: 'Post-capture external edit clearing dueAnchor must invalidate downgrade undo',
      );

      // Delete undo preserves dueAnchor on both open and Completed tasks:
      final delBoardAfter = downBoardBefore.deleteTask(
        'urgClamp01',
        currentDate: febNow.add(const Duration(minutes: 5)),
        timeZone: berlin,
      );
      final delEntry = TaskBoardUndo.capture(
        sequence: 23,
        kind: TaskUndoActionKind.delete,
        boardBefore: downBoardBefore,
        boardAfter: delBoardAfter,
        taskBefore: downBoardBefore.findTask('urgClamp01')!,
      );
      final undoneDel = TaskBoardUndo.apply(
        delBoardAfter,
        delEntry,
        utcNow: febNow.add(const Duration(minutes: 10)),
        timeZone: berlin,
      );
      expect(undoneDel, isNotNull);
      expect(
        undoneDel!.board.findTask('urgClamp01')!.dueAnchor,
        equals(jan31Anchor),
      );

      // Post-capture external edit to dueAnchor after one-off complete invalidates complete undo:
      final oneOffDone = downBoardBefore.completeTask(
        'urgClamp01',
        currentDate: febNow.add(const Duration(minutes: 5)),
        timeZone: berlin,
      );
      final oneOffEntry = TaskBoardUndo.capture(
        sequence: 24,
        kind: TaskUndoActionKind.complete,
        boardBefore: downBoardBefore,
        boardAfter: oneOffDone,
        taskBefore: downBoardBefore.findTask('urgClamp01')!,
      );
      final oneOffAnchorEdited = oneOffDone.updateTask(
        'urgClamp01',
        dueAnchor: TdfLocalDateTime(2026, 2, 28, 18),
        currentDate: febNow.add(const Duration(minutes: 6)),
        timeZone: berlin,
      );
      expect(
        TaskBoardUndo.apply(
          oneOffAnchorEdited,
          oneOffEntry,
          utcNow: febNow.add(const Duration(minutes: 10)),
          timeZone: berlin,
        ),
        isNull,
        reason: 'Post-capture external edit to dueAnchor on completed one-off task must invalidate undo',
      );

      // 4. Mode 2 capture without boardAfter (hasPostActionDueAnchor == false) restores anchor on untouched rollover and skips on external anchor edit:
      final noAfterEntry = TaskBoardUndo.capture(
        sequence: 25,
        kind: TaskUndoActionKind.complete,
        boardBefore: boardFeb,
        taskBefore: boardFeb.findTask('m2NullAnc1')!,
      );
      expect(noAfterEntry.hasPostActionDueAnchor, isFalse);
      final undoneNoAfter = TaskBoardUndo.apply(
        boardMar,
        noAfterEntry,
        utcNow: febNow.add(const Duration(hours: 1)),
        timeZone: berlin,
      );
      expect(undoneNoAfter, isNotNull);
      expect(
        undoneNoAfter!.board.findTask('m2NullAnc1')!.dueAnchor,
        equals(jan31Anchor),
      );
      expect(
        TaskBoardUndo.apply(
          marExternallyEdited,
          noAfterEntry,
          utcNow: febNow.add(const Duration(hours: 1)),
          timeZone: berlin,
        ),
        isNull,
        reason: 'Mode 2 capture without boardAfter must still detect external post-rollover dueAnchor edits',
      );
    });

    test('undo delete preserves isDuePassive on Completed tasks, guards fromWallClock underflow, aggregates multiple LocationTaskCondition rules, and handles 9999 timestamp overflow', () {
      final t0 = DateTime.utc(2026, 9, 1, 10);
      final t1 = t0.add(const Duration(minutes: 1));
      final t2 = t1.add(const Duration(minutes: 1));

      // 1. Delete + undo of Completed task preserves isDuePassive == true:
      final donePassive = TaskItem(
        id: 'donePass01',
        title: 'Completed With Passive Due',
        isCompleted: true,
        completions: 1,
        createdAt: t0,
        completedAt: t0,
        modifiedAt: t0,
        dueAt: DateTime.utc(2026, 9, 5, 12),
        isDuePassive: true,
      );
      final boardDone = TaskBoard.evaluate(
        tasks: <TaskItem>[donePassive],
        evaluationTime: t0,
      );
      final afterDeleteDone = boardDone.deleteTask(
        'donePass01',
        currentDate: t1,
      );
      final deleteEntry = TaskBoardUndo.capture(
        sequence: 30,
        kind: TaskUndoActionKind.delete,
        boardBefore: boardDone,
        boardAfter: afterDeleteDone,
        taskBefore: boardDone.findTask('donePass01')!,
      );
      final undoneDelete = TaskBoardUndo.apply(
        afterDeleteDone,
        deleteEntry,
        utcNow: t2,
      );
      expect(undoneDelete, isNotNull);
      expect(
        undoneDelete!.board.findTask('donePass01')!.isDuePassive,
        isTrue,
        reason: 'Undoing deletion of a Completed task must preserve snapshotTask.isDuePassive',
      );

      // 2. Mode 2 undo without boardAfter when snapshotDue is 0001-01-01T00:00:00Z in UTC-5 does not throw FormatException:
      final minUtc = DateTime.utc(1);
      final minTask = TaskItem(
        id: 'minDue0001',
        title: 'Min Boundary Mode 2',
        createdAt: minUtc,
        modifiedAt: minUtc,
        dueAt: minUtc,
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.days),
      );
      final rolledTask = minTask.copyWith(
        completions: 1,
        dueAt: DateTime.utc(1, 1, 2),
        dueAnchor: TdfLocalDateTime(1, 1, 2),
        modifiedAt: DateTime.utc(1, 1, 1, 0, 0, 1),
      );
      final boardMinBefore = TaskBoard.evaluate(
        tasks: <TaskItem>[minTask],
        queueBlock: TdfQueueBlock(
          modifiedAt: minUtc,
          taskIds: const <String>['minDue0001'],
        ),
        evaluationTime: minUtc,
      );
      final boardMinAfter = TaskBoard.evaluate(
        tasks: <TaskItem>[rolledTask],
        queueBlock: TdfQueueBlock(
          modifiedAt: minUtc,
          taskIds: const <String>['minDue0001'],
        ),
        evaluationTime: minUtc,
      );
      final minEntry = TaskBoardUndo.capture(
        sequence: 31,
        kind: TaskUndoActionKind.complete,
        boardBefore: boardMinBefore,
        taskBefore: boardMinBefore.findTask('minDue0001')!,
      );
      expect(
        TaskBoardUndo.apply(
          boardMinAfter,
          minEntry,
          utcNow: DateTime.utc(1, 1, 1, 0, 5),
          timeZone: TdfTimeZoneContext.fixedOffset(const Duration(hours: -5)),
        ),
        isNull,
        reason: '_hasConcurrentDueAnchorEdit must catch FormatException from fromWallClock underflow and return null',
      );

      // 3. Undo delete sanitizing multiple LocationTaskCondition objects aggregates surviving IDs:
      const locA = TdfLocation(
        id: 'locUndoA01',
        name: 'Undo Site A',
        latitude: 52.5,
        longitude: 13.4,
        radius: 100,
      );
      const locB = TdfLocation(
        id: 'locUndoB01',
        name: 'Undo Site B',
        latitude: 52.6,
        longitude: 13.5,
        radius: 100,
      );
      const locLabel = TdfLabel(
        id: 'lblUndoL01',
        name: 'Field',
        conditions: <TaskCondition>[
          LocationTaskCondition(locationIds: <String>['locUndoB01']),
        ],
      );
      final multiLocTask = TaskItem(
        id: 'tskUndoM01',
        title: 'Multi Location Undo Task',
        createdAt: t0,
        modifiedAt: t0,
        labelIds: const <String>['lblUndoL01'],
        conditions: const <TaskCondition>[
          LocationTaskCondition(locationIds: <String>['locUndoA01']),
          LocationTaskCondition(locationIds: <String>['locUndoB01']),
        ],
      );
      final boardLoc = TaskBoard.evaluate(
        tasks: <TaskItem>[multiLocTask],
        labels: const <TdfLabel>[locLabel],
        locations: const <TdfLocation>[locA, locB],
        queueBlock: TdfQueueBlock(
          modifiedAt: t0,
          taskIds: const <String>['tskUndoM01'],
        ),
        evaluationTime: t0,
      );
      final afterTaskDel = boardLoc.deleteTask('tskUndoM01', currentDate: t1);
      final taskDelEntry = TaskBoardUndo.capture(
        sequence: 32,
        kind: TaskUndoActionKind.delete,
        boardBefore: boardLoc,
        boardAfter: afterTaskDel,
        taskBefore: boardLoc.findTask('tskUndoM01')!,
      );
      final afterLocDel = afterTaskDel.deleteLocation(
        'locUndoA01',
        currentDate: t2,
      );
      final undoneLocTask = TaskBoardUndo.apply(
        afterLocDel,
        taskDelEntry,
        utcNow: t2.add(const Duration(minutes: 1)),
      );
      expect(undoneLocTask, isNotNull);
      expect(
        undoneLocTask!.board.findTask('tskUndoM01')!.conditions,
        equals(const <TaskCondition>[
          LocationTaskCondition(locationIds: <String>['locUndoB01']),
        ]),
        reason: 'Undo condition sanitization must aggregate surviving location IDs and omit location any when any ID survives',
      );

      // 4. Undo gracefully returns null when nextModifiedTimestamp overflows 9999-12-31 23:59:59:
      final maxUtc = DateTime.utc(9999, 12, 31, 23, 59, 59);
      final maxDeletedBoard = afterDeleteDone.copyWith(
        deletedBlock: TdfDeletedBlock(
          tasks: <TdfDeletedTaskRecord>[
            TdfDeletedTaskRecord(
              taskId: 'donePass01',
              deletedAt: maxUtc,
              completionsCheckpoint: 1,
            ),
          ],
        ),
      );
      expect(
        TaskBoardUndo.apply(maxDeletedBoard, deleteEntry, utcNow: maxUtc),
        isNull,
        reason: 'Undo _tryNextTimestamp must catch TdfException on 9999 overflow and skip gracefully',
      );
    });

    test('computes exact canonical block count when deleted/queue blocks are default-empty at 4095 and 4096 entities', () {
      // 1. 4096 Someday tasks + empty deletedBlock + empty queueBlock == 4096 canonical blocks (<= maxTdfBlocksPerDoc):
      final tasks4096 = <TaskItem>[
        for (var i = 0; i < maxTdfBlocksPerDoc; i++)
          TaskItem(
            id: 'sm${i.toString().padLeft(4, '0')}OkD2',
            title: 'Someday $i',
            createdAt: t0,
            modifiedAt: t0,
          ),
      ];
      final board4096Before = TaskBoard.evaluate(
        tasks: tasks4096,
        evaluationTime: t0,
      );
      expect(board4096Before.deletedBlock.isDefaultEmpty, isTrue);
      expect(board4096Before.queueBlock.isDefaultEmpty, isTrue);

      final board4096After = board4096Before.completeTask(
        'sm0000OkD2',
        currentDate: t1,
      );
      final completeEntry4096 = TaskBoardUndo.capture(
        sequence: 40,
        kind: TaskUndoActionKind.complete,
        boardBefore: board4096Before,
        boardAfter: board4096After,
        taskBefore: board4096Before.findTask('sm0000OkD2')!,
      );
      final undone4096 = TaskBoardUndo.apply(
        board4096After,
        completeEntry4096,
        utcNow: t2,
      );
      expect(
        undone4096,
        isNotNull,
        reason: '4096 simple tasks with empty deleted/queue blocks emit exactly 4096 blocks and must not be falsely rejected',
      );
      expect(undone4096!.board.findTask('sm0000OkD2')!.isCompleted, isFalse);

      // 2. 4095 tasks + non-empty queueBlock (1) + empty deletedBlock (0) == 4096 canonical blocks (<= maxTdfBlocksPerDoc):
      final tasks4095 = <TaskItem>[
        TaskItem(
          id: 'qt0000OkD2',
          title: 'Queued Focus 0',
          isPriority: true,
          createdAt: t0,
          modifiedAt: t0,
        ),
        for (var i = 1; i < maxTdfBlocksPerDoc - 1; i++)
          TaskItem(
            id: 'qt${i.toString().padLeft(4, '0')}OkD2',
            title: 'Queued $i',
            createdAt: t0,
            modifiedAt: t0,
          ),
      ];
      final board4095Before = TaskBoard.evaluate(
        tasks: tasks4095,
        queueBlock: TdfQueueBlock(
          modifiedAt: t0,
          taskIds: const <String>['qt0000OkD2', 'qt0001OkD2'],
        ),
        evaluationTime: t0,
      );
      final board4095After = board4095Before.downgradeTask(
        'qt0000OkD2',
        currentDate: t1,
      );
      final downgradeEntry4095 = TaskBoardUndo.capture(
        sequence: 41,
        kind: TaskUndoActionKind.downgrade,
        boardBefore: board4095Before,
        boardAfter: board4095After,
        taskBefore: board4095Before.findTask('qt0000OkD2')!,
      );
      final undone4095 = TaskBoardUndo.apply(
        board4095After,
        downgradeEntry4095,
        utcNow: t2,
      );
      expect(
        undone4095,
        isNotNull,
        reason: '4095 simple tasks plus 1 queue block and empty deletedBlock equal 4096 blocks and must succeed',
      );
      expect(undone4095!.board.findTask('qt0000OkD2')!.isPriority, isTrue);

      // 3. 4096 tasks + non-empty queueBlock (1) == 4097 canonical blocks (> maxTdfBlocksPerDoc):
      final board4096Queued = TaskBoard.evaluate(
        tasks: tasks4096,
        queueBlock: TdfQueueBlock(
          modifiedAt: t0,
          taskIds: const <String>['sm0000OkD2', 'sm0001OkD2'],
        ),
        evaluationTime: t0,
      );
      final downgraded4096Queued = board4096Queued.downgradeTask(
        'sm0000OkD2',
        currentDate: t1,
      );
      final entry4096Queued = TaskBoardUndo.capture(
        sequence: 42,
        kind: TaskUndoActionKind.downgrade,
        boardBefore: board4096Queued,
        boardAfter: downgraded4096Queued,
        taskBefore: board4096Queued.findTask('sm0000OkD2')!,
      );
      expect(
        TaskBoardUndo.apply(downgraded4096Queued, entry4096Queued, utcNow: t2),
        isNull,
        reason: '4096 tasks plus 1 non-empty queue block (4097 blocks) must exceed maxTdfBlocksPerDoc and return null',
      );
    });

    test('preserves concurrent post-downgrade deferral, deadline, and untouched passive edits during downgrade undo', () {
      // 1. Focus (priority) -> Ready downgrade, followed by concurrent deferral (suspendedAt + suspendedNote) and deadline (dueAt + dueNote):
      final baseTask = TaskItem(
        id: 'dwnCnc0001',
        title: 'Concurrent Target',
        isPriority: true,
        createdAt: t0,
        modifiedAt: t0,
      );
      final otherTask = TaskItem(
        id: 'dwnOth0001',
        title: 'Other Focus Task',
        createdAt: t0,
        modifiedAt: t0,
      );
      final boardBefore = TaskBoard.evaluate(
        tasks: <TaskItem>[baseTask, otherTask],
        queueBlock: TdfQueueBlock(
          modifiedAt: t0,
          taskIds: const <String>['dwnCnc0001', 'dwnOth0001'],
        ),
        evaluationTime: t0,
      );
      final downgraded = boardBefore.downgradeTask(
        'dwnCnc0001',
        currentDate: t1,
      );
      expect(downgraded.findTask('dwnCnc0001')!.isPriority, isFalse);

      final entryWithAfter = TaskBoardUndo.capture(
        sequence: 50,
        kind: TaskUndoActionKind.downgrade,
        boardBefore: boardBefore,
        boardAfter: downgraded,
        taskBefore: baseTask,
      );

      final futureSnooze = DateTime.utc(2026, 11, 5, 9);
      final newDeadline = DateTime.utc(2026, 11, 8, 17);
      final withConcurrentSchedule = downgraded.updateTask(
        'dwnCnc0001',
        suspendedAt: futureSnooze,
        suspendedNote: 'Waiting on vendor',
        dueAt: newDeadline,
        dueNote: 'Contract deadline',
        isDuePassive: true,
        currentDate: t2,
      );

      final undoneSchedule = TaskBoardUndo.apply(
        withConcurrentSchedule,
        entryWithAfter,
        utcNow: t3,
      );
      expect(undoneSchedule, isNotNull);
      final restoredSchedule = undoneSchedule!.board.findTask('dwnCnc0001')!;
      expect(
        restoredSchedule.isPriority,
        isTrue,
        reason: 'Downgrade undo must still restore priority modified by the downgrade',
      );
      expect(
        restoredSchedule.suspendedAt,
        equals(futureSnooze),
        reason: 'Downgrade undo must preserve post-downgrade suspendedAt edit',
      );
      expect(
        restoredSchedule.suspendedNote,
        equals('Waiting on vendor'),
        reason:
            'Downgrade undo must preserve post-downgrade suspendedNote edit',
      );
      expect(
        restoredSchedule.dueAt,
        equals(newDeadline),
        reason: 'Downgrade undo must preserve post-downgrade dueAt edit',
      );
      expect(
        restoredSchedule.dueNote,
        equals('Contract deadline'),
        reason: 'Downgrade undo must preserve post-downgrade dueNote edit',
      );
      expect(
        restoredSchedule.isDuePassive,
        isTrue,
        reason: 'Downgrade undo must preserve isDuePassive set on post-downgrade deadline',
      );

      // 2. Concurrent isSuspendedForever edit after downgrade is preserved even when captured without boardAfter:
      final entryWithoutAfter = TaskBoardUndo.capture(
        sequence: 51,
        kind: TaskUndoActionKind.downgrade,
        boardBefore: boardBefore,
        taskBefore: baseTask,
      );
      final withForever = downgraded.updateTask(
        'dwnCnc0001',
        isSuspendedForever: true,
        suspendedNote: 'On hold indefinitely',
        currentDate: t2,
      );
      final undoneForever = TaskBoardUndo.apply(
        withForever,
        entryWithoutAfter,
        utcNow: t3,
      );
      expect(undoneForever, isNotNull);
      final restoredForever = undoneForever!.board.findTask('dwnCnc0001')!;
      expect(
        restoredForever.isSuspendedForever,
        isTrue,
        reason: 'Downgrade undo must preserve post-downgrade isSuspendedForever edit',
      );
      expect(
        restoredForever.suspendedNote,
        equals('On hold indefinitely'),
        reason: 'Downgrade undo must preserve suspendedNote on post-downgrade indefinite hold',
      );

      // 3. Non-urgent deadline where downgrade did NOT touch dueNote/isDuePassive: concurrent dueNote + isDuePassive edits are preserved:
      final nonUrgentDue = DateTime.utc(2026, 11, 20, 12);
      final nonUrgentTask = TaskItem(
        id: 'dwnNonUrg1',
        title: 'Non-Urgent Priority Task',
        isPriority: true,
        createdAt: t0,
        modifiedAt: t0,
        dueAt: nonUrgentDue,
        dueNote: 'Initial note',
      );
      final nonUrgentBefore = TaskBoard.evaluate(
        tasks: <TaskItem>[nonUrgentTask, otherTask],
        queueBlock: TdfQueueBlock(
          modifiedAt: t0,
          taskIds: const <String>['dwnNonUrg1', 'dwnOth0001'],
        ),
        evaluationTime: t0,
      );
      final nonUrgentDowngraded = nonUrgentBefore.downgradeTask(
        'dwnNonUrg1',
        currentDate: t1,
      );
      expect(nonUrgentDowngraded.findTask('dwnNonUrg1')!.isDuePassive, isFalse);
      final nonUrgentEntry = TaskBoardUndo.capture(
        sequence: 52,
        kind: TaskUndoActionKind.downgrade,
        boardBefore: nonUrgentBefore,
        boardAfter: nonUrgentDowngraded,
        taskBefore: nonUrgentTask,
      );
      final nonUrgentEdited = nonUrgentDowngraded.updateTask(
        'dwnNonUrg1',
        dueNote: 'Edited note after downgrade',
        isDuePassive: true,
        currentDate: t2,
      );
      final nonUrgentUndone = TaskBoardUndo.apply(
        nonUrgentEdited,
        nonUrgentEntry,
        utcNow: t3,
      );
      expect(nonUrgentUndone, isNotNull);
      final restoredNonUrgent = nonUrgentUndone!.board.findTask('dwnNonUrg1')!;
      expect(restoredNonUrgent.isPriority, isTrue);
      expect(
        restoredNonUrgent.dueNote,
        equals('Edited note after downgrade'),
        reason: 'Downgrade undo must preserve post-downgrade dueNote edit',
      );
      expect(
        restoredNonUrgent.isDuePassive,
        isTrue,
        reason: 'Downgrade undo must preserve post-downgrade isDuePassive edit when downgrade did not modify isDuePassive',
      );

      // 4. Clearing a deadline after downgrade is preserved on downgrade undo (not resurrected from snapshotTask):
      final clearedDueAfterDowngrade = nonUrgentDowngraded.updateTask(
        'dwnNonUrg1',
        clearDueAt: true,
        currentDate: t2,
      );
      final undoneClearedDue = TaskBoardUndo.apply(
        clearedDueAfterDowngrade,
        nonUrgentEntry,
        utcNow: t3,
      );
      expect(undoneClearedDue, isNotNull);
      final restoredClearedDue = undoneClearedDue!.board.findTask(
        'dwnNonUrg1',
      )!;
      expect(restoredClearedDue.isPriority, isTrue);
      expect(
        restoredClearedDue.dueAt,
        isNull,
        reason: 'Downgrade undo must not resurrect a deadline cleared after downgrade',
      );
      expect(
        restoredClearedDue.dueNote,
        isNull,
        reason: 'Downgrade undo must not resurrect a dueNote cleared after downgrade',
      );

      // 5. TaskUndoEntry equality and hashCode distinguish postActionIsPriority and postActionIsDuePassive:
      final entryDiffPassive = TaskUndoEntry(
        sequence: nonUrgentEntry.sequence,
        kind: nonUrgentEntry.kind,
        snapshotTask: nonUrgentEntry.snapshotTask,
        wasQueued: nonUrgentEntry.wasQueued,
        queueOrderSnapshot: nonUrgentEntry.queueOrderSnapshot,
        hadOnlyScopedLabels: nonUrgentEntry.hadOnlyScopedLabels,
        hasPostActionDueAnchor: nonUrgentEntry.hasPostActionDueAnchor,
        postActionDueAnchor: nonUrgentEntry.postActionDueAnchor,
        postActionIsDuePassive: true,
        postActionIsPriority: nonUrgentEntry.postActionIsPriority,
      );
      expect(nonUrgentEntry, isNot(equals(entryDiffPassive)));
    });

    test('capture omits queueOrderSnapshot when wasQueued is false, reuses unmodifiable queue list when true, and TaskUndoOutcome compares boards structurally', () {
      final now = DateTime.utc(2026, 11, 15, 12);
      final queuedTask = TaskItem(
        id: 'tskQue0001',
        title: 'Queued task',
        createdAt: now,
      );
      final somedayTask = TaskItem(
        id: 'tskSom0001',
        title: 'Someday task',
        createdAt: now,
      );
      final boardA = TaskBoard.evaluate(
        tasks: <TaskItem>[queuedTask, somedayTask],
        queueBlock: TdfQueueBlock(
          modifiedAt: now,
          taskIds: const <String>['tskQue0001'],
        ),
        evaluationTime: now,
      );
      final boardB = TaskBoard.evaluate(
        tasks: <TaskItem>[queuedTask, somedayTask],
        queueBlock: TdfQueueBlock(
          modifiedAt: now,
          taskIds: const <String>['tskQue0001'],
        ),
        evaluationTime: now,
      );

      final queuedEntry = TaskBoardUndo.capture(
        sequence: 1,
        kind: TaskUndoActionKind.delete,
        boardBefore: boardA,
        taskBefore: queuedTask,
      );
      expect(queuedEntry.wasQueued, isTrue);
      expect(
        identical(queuedEntry.queueOrderSnapshot, boardA.queueBlock.taskIds),
        isTrue,
        reason: 'Queued undo capture must reuse already-unmodifiable queueBlock.taskIds',
      );

      final unqueuedEntry = TaskBoardUndo.capture(
        sequence: 2,
        kind: TaskUndoActionKind.delete,
        boardBefore: boardA,
        taskBefore: somedayTask,
      );
      expect(unqueuedEntry.wasQueued, isFalse);
      expect(
        unqueuedEntry.queueOrderSnapshot,
        isEmpty,
        reason: 'Unqueued undo capture must not retain an unused queueOrderSnapshot copy',
      );

      final outcomeA = TaskUndoOutcome(board: boardA);
      final outcomeB = TaskUndoOutcome(board: boardB);
      expect(outcomeA, equals(outcomeB));
      expect(outcomeA.hashCode, equals(outcomeB.hashCode));
    });

    test('isTaskChangedModuloBlockCleanup, didTaskQueuePlacementChange, and pruneInvalidatedEntries detect structural and payload invalidation', () {
      final tEarly = DateTime.utc(2026, 11, 1, 9);
      final tCheck = DateTime.utc(2026, 11, 1, 10);

      // 1. isTaskChangedModuloBlockCleanup:
      final openWithExpiredBlock = TaskItem(
        id: 'chkTask001',
        title: 'Task A',
        createdAt: tEarly,
        modifiedAt: tEarly,
        suspendedAt: tEarly.add(const Duration(minutes: 30)),
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'donePrereq'),
        ],
      );
      final openCleaned = openWithExpiredBlock.copyWith(
        clearSuspendedAt: true,
        dependencies: const <TdfTaskDependency>[],
        modifiedAt: tCheck,
      );
      final openEdited = openCleaned.copyWith(title: 'Task A Edited');
      final donePrereq = TaskItem(
        id: 'donePrereq',
        title: 'Done Prereq',
        isCompleted: true,
        completions: 1,
        createdAt: tEarly,
        completedAt: tEarly,
        modifiedAt: tEarly,
      );
      final completedCopy = openCleaned.toCompleted(tCheck);

      expect(
        TaskBoardUndo.isTaskChangedModuloBlockCleanup(openCleaned, openCleaned),
        isFalse,
        reason: 'Identical task snapshots are unchanged',
      );
      expect(
        TaskBoardUndo.isTaskChangedModuloBlockCleanup(null, openCleaned),
        isTrue,
        reason: 'Added task counts as changed',
      );
      expect(
        TaskBoardUndo.isTaskChangedModuloBlockCleanup(openCleaned, null),
        isTrue,
        reason: 'Removed task counts as changed',
      );
      expect(
        TaskBoardUndo.isTaskChangedModuloBlockCleanup(
          openCleaned,
          completedCopy,
        ),
        isTrue,
        reason: 'Completion transition counts as changed',
      );
      expect(
        TaskBoardUndo.isTaskChangedModuloBlockCleanup(
          completedCopy,
          completedCopy,
        ),
        isFalse,
        reason: 'Identical completed snapshots are unchanged',
      );
      expect(
        TaskBoardUndo.isTaskChangedModuloBlockCleanup(
          openWithExpiredBlock,
          openCleaned,
          liveTasksById: <String, TaskItem>{
            'chkTask001': openCleaned,
            'donePrereq': donePrereq,
          },
          nowUtc: tCheck,
        ),
        isFalse,
        reason: 'Expired deferral and resolved dependency cleanup alone must not count as a change',
      );
      expect(
        TaskBoardUndo.isTaskChangedModuloBlockCleanup(
          openWithExpiredBlock,
          openEdited,
          liveTasksById: <String, TaskItem>{
            'chkTask001': openEdited,
            'donePrereq': donePrereq,
          },
          nowUtc: tCheck,
        ),
        isTrue,
        reason: 'Title edit beyond block cleanup must count as changed',
      );

      // 2. didTaskQueuePlacementChange:
      TaskBoard boardWithQueue(List<String> queueIds) => TaskBoard.evaluate(
        tasks: <TaskItem>[
          for (final id in const <String>[
            'qTask00001',
            'qTask00002',
            'qTask00003',
            'qTask00004',
          ])
            TaskItem(
              id: id,
              title: 'Task $id',
              createdAt: tEarly,
              modifiedAt: tEarly,
            ),
        ],
        queueBlock: TdfQueueBlock(modifiedAt: tEarly, taskIds: queueIds),
        evaluationTime: tEarly,
      );

      final qBase = boardWithQueue(const <String>['qTask00001', 'qTask00002']);
      final qUnrelatedAdded = boardWithQueue(const <String>[
        'qTask00003',
        'qTask00001',
        'qTask00004',
        'qTask00002',
      ]);
      final qSwapped = boardWithQueue(const <String>[
        'qTask00002',
        'qTask00001',
      ]);
      final qRemoved = boardWithQueue(const <String>['qTask00002']);

      expect(
        TaskBoardUndo.didTaskQueuePlacementChange(
          qBase,
          qUnrelatedAdded,
          'qTask00001',
        ),
        isFalse,
        reason: 'Adding unrelated queued tasks preserves relative placement of shared members',
      );
      expect(
        TaskBoardUndo.didTaskQueuePlacementChange(
          qBase,
          qSwapped,
          'qTask00001',
        ),
        isTrue,
        reason: 'Reordering shared queued tasks changes queue placement',
      );
      expect(
        TaskBoardUndo.didTaskQueuePlacementChange(
          qBase,
          qRemoved,
          'qTask00001',
        ),
        isTrue,
        reason: 'Evicting task from queue changes queue placement',
      );
      expect(
        TaskBoardUndo.didTaskQueuePlacementChange(qBase, qBase, 'qTask00004'),
        isFalse,
        reason: 'Task absent from both queues has unchanged placement',
      );

      // 3. pruneInvalidatedEntries:
      final emptyResult = TaskBoardUndo.pruneInvalidatedEntries(
        const <TaskUndoEntry>[],
        previousBoard: qBase,
        nextBoard: qSwapped,
        nowUtc: tCheck,
      );
      expect(emptyResult.retained, isEmpty);
      expect(emptyResult.pruned, isEmpty);

      final taskA = TaskItem(
        id: 'prnTask001',
        title: 'Task A',
        createdAt: tEarly,
        modifiedAt: tEarly,
      );
      final taskB = TaskItem(
        id: 'prnTask002',
        title: 'Task B',
        isPriority: true,
        createdAt: tEarly,
        modifiedAt: tEarly,
      );
      final dependentOfA = TaskItem(
        id: 'prnDep0001',
        title: 'Blocked By A',
        createdAt: tEarly,
        modifiedAt: tEarly,
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'prnTask001'),
        ],
      );
      final taskCleanOnly = openWithExpiredBlock;
      final boardBeforePrune = TaskBoard.evaluate(
        tasks: <TaskItem>[
          taskA,
          taskB,
          dependentOfA,
          taskCleanOnly,
          donePrereq,
        ],
        queueBlock: TdfQueueBlock(
          modifiedAt: tEarly,
          taskIds: const <String>['prnTask001', 'prnTask002', 'chkTask001'],
        ),
        evaluationTime: tEarly,
      );

      final boardAfterA = boardBeforePrune.completeTask(
        'prnTask001',
        currentDate: t1,
      );
      final entryCompleteA = TaskBoardUndo.capture(
        sequence: 101,
        kind: TaskUndoActionKind.complete,
        boardBefore: boardBeforePrune,
        boardAfter: boardAfterA,
        taskBefore: taskA,
      );
      final boardAfterDowngradeB = boardAfterA.downgradeTask(
        'prnTask002',
        currentDate: t2,
      );
      final entryDowngradeB = TaskBoardUndo.capture(
        sequence: 102,
        kind: TaskUndoActionKind.downgrade,
        boardBefore: boardAfterA,
        boardAfter: boardAfterDowngradeB,
        taskBefore: boardAfterA.findTask('prnTask002')!,
      );
      final entryCleanOnly = TaskBoardUndo.capture(
        sequence: 103,
        kind: TaskUndoActionKind.delete,
        boardBefore: boardAfterDowngradeB,
        taskBefore: boardAfterDowngradeB.findTask('chkTask001')!,
      );

      // External sync edits dependentOfA (invalidating entryCompleteA), reorders prnTask002 in queue (invalidating entryDowngradeB), and only cleans expired blocks on chkTask001 (retaining entryCleanOnly):
      final boardNextExternal = TaskBoard.evaluate(
        tasks: <TaskItem>[
          boardAfterDowngradeB.findTask('prnTask001')!,
          boardAfterDowngradeB.findTask('prnTask002')!,
          boardAfterDowngradeB
              .findTask('prnDep0001')!
              .copyWith(
                title: 'Externally Edited Dependent',
                modifiedAt: tCheck,
              ),
          openCleaned,
          donePrereq,
        ],
        queueBlock: TdfQueueBlock(
          modifiedAt: tCheck,
          taskIds: const <String>['prnTask002', 'chkTask001'],
        ),
        evaluationTime: tCheck,
      );
      final prunedResult = TaskBoardUndo.pruneInvalidatedEntries(
        <TaskUndoEntry>[entryCompleteA, entryDowngradeB, entryCleanOnly],
        previousBoard: boardAfterDowngradeB,
        nextBoard: boardNextExternal,
        nowUtc: tCheck,
      );
      expect(
        prunedResult.pruned.map((entry) => entry.sequence),
        equals(<int>[101, 102]),
        reason: 'Dependent edit and downgrade queue reorder must invalidate their undo entries',
      );
      expect(
        prunedResult.retained.map((entry) => entry.sequence),
        equals(<int>[103]),
        reason: 'Cleanup-only change on target must retain its undo entry',
      );
    });
  });
}

class TaskUndoUndoHelper {
  const TaskUndoUndoHelper._();

  static TaskUndoEntry capture(
    int seq,
    TaskUndoActionKind kind,
    TaskBoard board,
    TaskItem task,
  ) => TaskBoardUndo.capture(
    sequence: seq,
    kind: kind,
    boardBefore: board,
    taskBefore: task,
  );
}
