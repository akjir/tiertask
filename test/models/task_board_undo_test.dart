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
import 'package:tiertask/services/tdf_serializer.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 1, 9, 0);
  final t1 = DateTime.utc(2026, 11, 1, 10, 0);
  final t2 = DateTime.utc(2026, 11, 1, 11, 0);
  final t3 = DateTime.utc(2026, 11, 1, 12, 0);

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
            dueAt: DateTime.utc(2026, 11, 5, 18, 0),
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
          TdfTaskDependency(taskId: 'block1OkD2', requiredCompletion: 1),
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
      expect(restored.dueAt, equals(DateTime.utc(2026, 11, 5, 18, 0)));
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
        equals(
          const TdfTaskDependency(taskId: 'block1OkD2', requiredCompletion: 1),
        ),
        reason: 'Previously satisfied dependent must remain unblocked at :1',
      );
    });

    test('reverses recurring task completion and subtasks auto-finish completion accurately', () {
      final board = TaskBoard.empty().addTask(
        'Weekly Backup',
        id: 'recur1OkD2',
        targetTier: TaskTier.focus,
        isPriority: true,
        dueAt: DateTime.utc(2026, 11, 2, 9, 0),
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.weeks),
        subtasksAutoFinish: true,
        subtasks: const <SubtaskItem>[
          SubtaskItem(title: 'Step 1', isCompleted: true),
          SubtaskItem(title: 'Step 2', isCompleted: false),
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
      expect(rescheduled.dueAt, equals(DateTime.utc(2026, 11, 9, 9, 0)));
      expect(rescheduled.subtasks.every((step) => !step.isCompleted), isTrue);

      final outcome = TaskBoardUndo.apply(afterAutoFinish, entry, utcNow: t2);
      expect(outcome, isNotNull);
      final restored = outcome!.board.findTask('recur1OkD2')!;
      expect(restored.completions, equals(1));
      expect(restored.dueAt, equals(DateTime.utc(2026, 11, 2, 9, 0)));
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
          .addTask(
            'Task C',
            id: 'taskC0OkD2',
            targetTier: TaskTier.planned,
            currentDate: t0,
          );
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
      board = board.addTask(
        'Task E',
        id: 'taskE0OkD2',
        targetTier: TaskTier.planned,
        currentDate: t2,
      );
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
        createdAt: DateTime.utc(2026, 9, 1),
        completedAt: DateTime.utc(2026, 9, 15),
      );

      var board = TaskBoard.evaluate(
        tasks: <TaskItem>[openTaskWithOverride, oldCompleted],
        labels: <TdfLabel>[workLabel],
        locations: const <TdfLocation>[office, home],
        evaluationTime: t0,
        pruneExpiredCompleted: false,
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
          TdfTaskDependency(taskId: 'pre001OkD2', requiredCompletion: 1),
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
          'depSatOkD2': TdfTaskDependency(
            taskId: 'pre001OkD2',
            requiredCompletion: 1,
          ),
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
      final futureDeferral = DateTime.utc(2026, 11, 2, 9, 0);
      final expiredDeferral = DateTime.utc(2026, 11, 1, 11, 30);
      final targetFuture = TaskItem(
        id: 'delFutOkD2',
        title: 'Future Deferred Target',
        createdAt: t0,
        modifiedAt: t0,
        suspendedAt: futureDeferral,
        suspendedNote: 'Keep future note',
        dueAt: DateTime.utc(2026, 11, 5, 17, 0),
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
        dueAt: DateTime.utc(2026, 11, 5, 17, 0),
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
          TdfTaskDependency(taskId: 'trgLimOkD2', requiredCompletion: 1),
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
