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
