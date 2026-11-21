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

import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/presentation/app_shell_controller.dart';
import 'package:tiertask/presentation/floating_notice_controller.dart';
import 'package:tiertask/presentation/shell_models.dart';
import 'package:tiertask/presentation/task_controller.dart';
import 'package:tiertask/presentation/view_model_primitives.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';

import '../ui/test_helpers.dart';

class _DelayedTaskNotifier extends FakeTaskNotifier {
  _DelayedTaskNotifier(super.initialBoard, this.gate);

  final Completer<void> gate;
  int pushCount = 0;

  @override
  Future<void> pushToRemote(
    TaskBoard board, {
    TaskBoard? fallbackBoard,
    Map<String, TdfDeletionResolution> taskConflictResolutions = const {},
    int? mutationEpoch,
  }) async {
    pushCount++;
    await gate.future;
    state = AsyncData(board);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedNow = DateTime.utc(2026, 11, 10, 12, 0, 0);
  final localizations = lookupAppLocalizations(const Locale('en'));

  TaskBoard buildBaseBoard({
    List<TaskItem>? tasks,
    List<TdfLabel>? labels,
    List<TdfLocation>? locations,
  }) {
    final workLabel = TdfLabel(
      id: 'work000001',
      name: 'Work',
      color: '#2196F3',
      isScoped: false,
      modifiedAt: fixedNow,
    );
    final scopedLabel = TdfLabel(
      id: 'scop000002',
      name: 'Private',
      color: '#4CAF50',
      isScoped: true,
      modifiedAt: fixedNow,
    );
    final officeLocation = TdfLocation(
      id: 'locA000001',
      name: 'Office',
      latitude: 47.1204,
      longitude: 8.5173,
      radius: 250.0,
      modifiedAt: fixedNow,
    );
    final defaultTasks = <TaskItem>[
      TaskItem(
        id: 'taskA00001',
        title: 'Alpha Task',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
        labelIds: const <String>['work000001'],
      ),
      TaskItem(
        id: 'taskB00002',
        title: 'Beta Task',
        createdAt: fixedNow.add(const Duration(minutes: 1)),
        modifiedAt: fixedNow.add(const Duration(minutes: 1)),
      ),
      TaskItem(
        id: 'done000003',
        title: 'Completed Item',
        isCompleted: true,
        completedAt: fixedNow.subtract(const Duration(hours: 2)),
        completions: 1,
        createdAt: fixedNow.subtract(const Duration(days: 1)),
        modifiedAt: fixedNow,
      ),
    ];
    final effectiveTasks = tasks ?? defaultTasks;
    final queuedIds = <String>[
      for (final task in effectiveTasks)
        if (!task.isCompleted &&
            task.completedAt == null &&
            !task.isSuspendedForever &&
            task.suspendedAt == null)
          task.id,
    ];
    return TaskBoard.evaluate(
      tasks: effectiveTasks,
      labels: labels ?? <TdfLabel>[workLabel, scopedLabel],
      locations: locations ?? <TdfLocation>[officeLocation],
      queueBlock: TdfQueueBlock(modifiedAt: fixedNow, taskIds: queuedIds),
      evaluationTime: fixedNow,
      localEvaluationTime: fixedNow,
    );
  }

  Future<ProviderContainer> createContainer({
    TaskBoard? board,
    WebDavConfig config = const WebDavConfig(
      language: AppLanguage.english,
      timeZoneMode: AppTimeZoneMode.manual,
      manualTimeZoneOffsetMinutes: 0,
    ),
    DateTime? now,
    TaskNotifier Function()? notifierFactory,
  }) async {
    final effectiveBoard = board ?? buildBaseBoard();
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(config),
        ),
        taskNotifierProvider.overrideWith(
          notifierFactory ?? () => FakeTaskNotifier(effectiveBoard),
        ),
        clockProvider.overrideWithValue(() => now ?? fixedNow),
      ],
    );
    addTearDown(container.dispose);
    await container.read(webDavConfigProvider.future);
    await container.read(taskNotifierProvider.future);
    await Future<void>.microtask(() {});
    // Keep shell and notice listeners active throughout each test.
    final shellSubscription = container.listen(
      appShellControllerProvider,
      (_, _) {},
    );
    final noticeSubscription = container.listen(
      floatingNoticeControllerProvider,
      (_, _) {},
    );
    addTearDown(shellSubscription.close);
    addTearDown(noticeSubscription.close);
    return container;
  }

  group('TaskController models & state', () {
    test('immutable input and state value equality and copyWith', () {
      const stateA = TaskControllerState();
      const stateB = TaskControllerState(isBusy: false, busyTaskId: null);
      expect(stateA, equals(stateB));
      expect(stateA.hashCode, equals(stateB.hashCode));

      final busy = stateA.copyWith(isBusy: true, busyTaskId: 'taskA00001');
      expect(busy.isBusy, isTrue);
      expect(busy.busyTaskId, equals('taskA00001'));
      final cleared = busy.copyWith(isBusy: false, clearBusyTaskId: true);
      expect(cleared, equals(stateA));

      const linkA = EntityLinkInput(title: 'Docs', uri: 'https://example.com');
      const linkB = EntityLinkInput(title: 'Docs', uri: 'https://example.com');
      expect(linkA, equals(linkB));
      expect(linkA.hashCode, equals(linkB.hashCode));

      const subA = SubtaskInput(title: 'Step 1', isCompleted: true);
      const subB = SubtaskInput(title: 'Step 1', isCompleted: true);
      expect(subA, equals(subB));
      expect(subA.hashCode, equals(subB.hashCode));

      final draftA = TaskDraftInput(
        title: 'Draft',
        labelIds: const <String>['work000001'],
        links: const <EntityLinkInput>[linkA],
        subtasks: const <SubtaskInput>[subA],
      );
      final draftB = TaskDraftInput(
        title: 'Draft',
        labelIds: const <String>['work000001'],
        links: const <EntityLinkInput>[linkB],
        subtasks: const <SubtaskInput>[subB],
      );
      expect(draftA, equals(draftB));
      expect(draftA.hashCode, equals(draftB.hashCode));
    });
  });

  group('TaskController.quickAddTask', () {
    test('creates task without jumping tiers or expanding and announces noticeTaskSaved when landing in activeTier', () async {
      final container = await createContainer();
      final controller = container.read(taskControllerProvider.notifier);

      final result = await controller.quickAddTask(
        rawTitle: '  Gamma Task  ',
        placement: TaskPlacementOption.queue,
        labelIds: const <String>['work000001'],
      );

      expect(result, isA<ActionSucceeded>());
      final succeeded = result as ActionSucceeded;
      expect(succeeded.entityId, isNotNull);
      expect(succeeded.noticeMessage, equals(localizations.noticeTaskSaved));

      final shell = container.read(appShellControllerProvider);
      expect(shell.activeTier, equals(ShellTier.focus));
      expect(shell.expandedEntity, isNull);
      expect(
        container.read(floatingNoticeControllerProvider)?.message,
        equals(localizations.noticeTaskSaved),
      );

      final board = container.read(taskNotifierProvider).requireValue;
      final created = board.findTask(succeeded.entityId ?? '');
      expect(created, isNotNull);
      expect(created?.title, equals('Gamma Task'));
      expect(created?.labelIds, equals(const <String>['work000001']));
    });

    test('announces noticeTaskSavedInTier without jumping when Focus WIP is full or placement is Someday', () async {
      final fullFocusTasks = <TaskItem>[
        for (var i = 1; i <= 3; i++)
          TaskItem(
            id: 'focus0000$i',
            title: 'Focus $i',
            createdAt: fixedNow.add(Duration(minutes: i)),
            modifiedAt: fixedNow.add(Duration(minutes: i)),
          ),
      ];
      final container = await createContainer(
        board: buildBaseBoard(tasks: fullFocusTasks),
      );
      final controller = container.read(taskControllerProvider.notifier);

      final readyResult = await controller.quickAddTask(
        rawTitle: 'Fourth Active Task',
        placement: TaskPlacementOption.queue,
        labelIds: const <String>[],
      );
      expect(readyResult, isA<ActionSucceeded>());
      expect(
        (readyResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticeTaskSavedInTier(localizations.tier2Name)),
        reason: '4th active task lands in Ready when Focus WIP (3) is full',
      );
      expect(
        container.read(appShellControllerProvider).activeTier,
        equals(ShellTier.focus),
        reason: 'Quick-Add must never jump away from Focus',
      );

      final somedayResult = await controller.quickAddTask(
        rawTitle: 'Future Idea',
        placement: TaskPlacementOption.someday,
        labelIds: const <String>[],
      );
      expect(somedayResult, isA<ActionSucceeded>());
      expect(
        (somedayResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticeTaskSavedInTier(localizations.tier5Name)),
      );
      expect(
        container.read(appShellControllerProvider).activeTier,
        equals(ShellTier.focus),
      );
    });

    test('announces noticeTaskMovedToScopedQueue when task is restricted by a scoped label outside activeLabelId', () async {
      final container = await createContainer();
      final controller = container.read(taskControllerProvider.notifier);

      final result = await controller.quickAddTask(
        rawTitle: 'Secret Chore',
        placement: TaskPlacementOption.queue,
        labelIds: const <String>['scop000002'],
      );
      expect(result, isA<ActionSucceeded>());
      expect(
        (result as ActionSucceeded).noticeMessage,
        equals(localizations.noticeTaskMovedToScopedQueue('Private')),
      );
      expect(
        container.read(floatingNoticeControllerProvider)?.message,
        equals(localizations.noticeTaskMovedToScopedQueue('Private')),
      );

      // When filtering by that scoped label, creation stays in current queue.
      container
          .read(appShellControllerProvider.notifier)
          .selectLabelFilter('scop000002');
      final inScopedResult = await controller.quickAddTask(
        rawTitle: 'Visible Scoped Chore',
        placement: TaskPlacementOption.queue,
        labelIds: const <String>['scop000002'],
      );
      expect(inScopedResult, isA<ActionSucceeded>());
      expect(
        (inScopedResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticeTaskSaved),
      );
    });

    test('emits NoticeTone.danger floating toast and returns ActionValidationFailed on case-insensitive duplicate', () async {
      final container = await createContainer();
      final controller = container.read(taskControllerProvider.notifier);

      final result = await controller.quickAddTask(
        rawTitle: '  alpha task  ',
        placement: TaskPlacementOption.queue,
        labelIds: const <String>[],
      );

      expect(result, isA<ActionValidationFailed>());
      expect(
        (result as ActionValidationFailed).message,
        equals(localizations.taskNameErrorDuplicate),
      );
      final notice = container.read(floatingNoticeControllerProvider);
      expect(notice, isNotNull);
      expect(notice?.tone, equals(NoticeTone.danger));
      expect(notice?.message, equals(localizations.taskNameErrorDuplicate));
    });

    test('enforces maxTdfTextLength (500 Unicode scalars), non-BMP scalars, control chars, and safe delimiter characters', () async {
      final container = await createContainer();
      final controller = container.read(taskControllerProvider.notifier);

      final emptyResult = await controller.quickAddTask(
        rawTitle: '   ',
        placement: TaskPlacementOption.queue,
        labelIds: const <String>[],
      );
      expect(emptyResult, isA<ActionValidationFailed>());

      // Exactly 500 non-BMP Unicode scalar values (1000 UTF-16 code units) must succeed.
      final validNonBmp = '\u{1D400}' * maxTdfTextLength;
      final validBoundResult = await controller.quickAddTask(
        rawTitle: validNonBmp,
        placement: TaskPlacementOption.queue,
        labelIds: const <String>[],
      );
      expect(
        validBoundResult,
        isA<ActionSucceeded>(),
        reason: '500 non-BMP scalars must satisfy maxTdfTextLength',
      );

      // 501 Unicode scalars must fail.
      final tooLongResult = await controller.quickAddTask(
        rawTitle: '${'a' * maxTdfTextLength}b',
        placement: TaskPlacementOption.queue,
        labelIds: const <String>[],
      );
      expect(
        tooLongResult,
        isA<ActionValidationFailed>(),
        reason: '501 scalars must fail maxTdfTextLength',
      );

      // Unpaired surrogate and ASCII control characters must fail.
      for (final badTitle in <String>[
        'Bad\nLine',
        'Bad\r\nLine',
        'Bad\tTab',
        'Bad\x00Null',
        'Bad\x7FDel',
        'Bad\uD800Surrogate',
      ]) {
        final badResult = await controller.quickAddTask(
          rawTitle: badTitle,
          placement: TaskPlacementOption.queue,
          labelIds: const <String>[],
        );
        expect(
          badResult,
          isA<ActionValidationFailed>(),
          reason: 'Control char or surrogate title must be rejected',
        );
      }

      // Delimiter characters (", \, {, }, #) are valid inside quoted TDF <text>.
      const delimiterTitle = 'Quote "x" \\ {brace} #inline';
      final delimiterResult = await controller.quickAddTask(
        rawTitle: delimiterTitle,
        placement: TaskPlacementOption.queue,
        labelIds: const <String>[],
      );
      expect(delimiterResult, isA<ActionSucceeded>());
      final created = container
          .read(taskNotifierProvider)
          .requireValue
          .findTask((delimiterResult as ActionSucceeded).entityId ?? '');
      expect(created?.title, equals(delimiterTitle));
    });
  });

  group('TaskController.createTaskDraft', () {
    test('commits full task draft, cancels active draft card, and emits non-jumping placement toast', () async {
      final container = await createContainer();
      final shell = container.read(appShellControllerProvider.notifier);
      shell.openDraft(EntityDraftKind.task, seedTitle: 'Seed');

      final controller = container.read(taskControllerProvider.notifier);
      final result = await controller.createTaskDraft(
        TaskDraftInput(
          title: 'Rich Draft Task',
          note: 'Line 1\r\nLine 2\tindented',
          placement: TaskPlacementOption.priority,
          labelIds: const <String>['work000001'],
          links: const <EntityLinkInput>[
            EntityLinkInput(title: 'Spec', uri: 'https://example.com/spec'),
          ],
          subtasks: const <SubtaskInput>[
            SubtaskInput(title: 'Step 1'),
            SubtaskInput(title: '   '),
            SubtaskInput(title: 'Step 2', isCompleted: true),
          ],
          subtasksAutoFinish: true,
          rawDue: '2026-11-20 14:30',
          autoPrioritizeDue: false,
          rawDueNote: 'Before demo',
          isRepeating: true,
          rawRepeatCount: '2',
          repeatUnit: ShellRepeatUnit.weeks,
          rawRepeatLeadDays: '3',
          isSuspended: true,
          suspendedIndefinitely: false,
          rawSuspendedUntil: '2026-11-15 09:00',
          rawSuspendedNote: 'Waiting on vendor',
          prerequisiteTaskIds: const <String>['taskA00001'],
          conditionDraft: ConditionDraftViewModel(
            daysMode: ConditionDimensionMode.custom,
            selectedWeekdays: const <int>[1, 3, 5],
            timesMode: ConditionDimensionMode.custom,
            timeWindows: const <TimeWindowDraftViewModel>[
              TimeWindowDraftViewModel(start: '09:00', end: '17:00'),
            ],
            locationsMode: ConditionDimensionMode.custom,
            selectedLocationIds: const <String>['locA000001'],
          ),
        ),
      );

      expect(result, isA<ActionSucceeded>());
      final succeeded = result as ActionSucceeded;
      expect(
        container.read(appShellControllerProvider).activeDraft,
        isNull,
        reason: 'Draft card must close after commit',
      );
      expect(
        succeeded.noticeMessage,
        equals(localizations.noticeTaskSavedInTier(localizations.tier4Name)),
        reason: 'Suspended/blocked draft lands in Blocked while viewing Focus',
      );

      final created = container
          .read(taskNotifierProvider)
          .requireValue
          .findTask(succeeded.entityId ?? '');
      expect(created, isNotNull);
      expect(created?.title, equals('Rich Draft Task'));
      expect(created?.note, equals('Line 1\nLine 2\tindented'));
      expect(created?.isPriority, isTrue);
      expect(created?.links, hasLength(1));
      expect(created?.subtasks, hasLength(2));
      expect(created?.subtasksAutoFinish, isTrue);
      expect(created?.isDuePassive, isTrue);
      expect(created?.dueNote, equals('Before demo'));
      expect(created?.repeatRule?.count, equals(2));
      expect(created?.repeatRule?.unit, equals(RepeatUnit.weeks));
      expect(created?.repeatRule?.leadDays, equals(3));
      expect(created?.suspendedAt, equals(DateTime.utc(2026, 11, 15, 9, 0)));
      expect(created?.suspendedNote, equals('Waiting on vendor'));
      expect(created?.blockedByTaskIds, equals(const <String>['taskA00001']));
      expect(created?.conditions, hasLength(3));
    });

    test(
      'validates all draft bounds and keeps draft open on validation failure',
      () async {
        final container = await createContainer();
        container
            .read(appShellControllerProvider.notifier)
            .openDraft(EntityDraftKind.task);
        final controller = container.read(taskControllerProvider.notifier);

        // Note > 2000 scalars.
        final noteTooLong = await controller.createTaskDraft(
          TaskDraftInput(
            title: 'Note Bound Task',
            note: 'n' * (maxTdfNoteLength + 1),
          ),
        );
        expect(noteTooLong, isA<ActionValidationFailed>());
        expect(
          (noteTooLong as ActionValidationFailed).fieldErrors['note'],
          equals(localizations.schedulingNoteErrorTooLong),
        );
        expect(
          container.read(appShellControllerProvider).activeDraft,
          equals(EntityDraftKind.task),
        );

        // Links > 20.
        final tooManyLinks = await controller.createTaskDraft(
          TaskDraftInput(
            title: 'Link Bound Task',
            links: <EntityLinkInput>[
              for (var i = 0; i <= maxTdfLinksPerTask; i++)
                EntityLinkInput(
                  title: 'Link $i',
                  uri: 'https://example.com/$i',
                ),
            ],
          ),
        );
        expect(tooManyLinks, isA<ActionValidationFailed>());
        expect(
          (tooManyLinks as ActionValidationFailed).fieldErrors['links'],
          equals(localizations.linkErrorMaxExceeded),
        );

        // Subtasks > 1024.
        final tooManySubtasks = await controller.createTaskDraft(
          TaskDraftInput(
            title: 'Subtask Bound Task',
            subtasks: <SubtaskInput>[
              for (var i = 0; i <= maxTdfStmtsPerBlock; i++)
                SubtaskInput(title: 'Step $i'),
            ],
          ),
        );
        expect(tooManySubtasks, isA<ActionValidationFailed>());

        // Invalid repeat count (0 and 3651) and leadDays (3651).
        final badRepeat = await controller.createTaskDraft(
          TaskDraftInput(
            title: 'Repeat Bound Task',
            rawDue: '2026-11-20',
            isRepeating: true,
            rawRepeatCount: '3651',
            rawRepeatLeadDays: '3651',
          ),
        );
        expect(badRepeat, isA<ActionValidationFailed>());
        final repeatErrors = (badRepeat as ActionValidationFailed).fieldErrors;
        expect(
          repeatErrors['repeatCount'],
          equals(localizations.repeatErrorInvalid),
        );
        expect(
          repeatErrors['repeatLeadDays'],
          equals(localizations.repeatLeadDaysErrorInvalid),
        );

        // Finite suspended with blank date must fail; indefinite suspended succeeds.
        final badSuspended = await controller.createTaskDraft(
          TaskDraftInput(
            title: 'Bad Suspend Task',
            isSuspended: true,
            suspendedIndefinitely: false,
            rawSuspendedUntil: '',
          ),
        );
        expect(badSuspended, isA<ActionValidationFailed>());

        // Invalid condition time window (equal start == end).
        final badCondition = await controller.createTaskDraft(
          TaskDraftInput(
            title: 'Bad Condition Task',
            conditionDraft: ConditionDraftViewModel(
              timesMode: ConditionDimensionMode.custom,
              timeWindows: const <TimeWindowDraftViewModel>[
                TimeWindowDraftViewModel(start: '10:00', end: '10:00'),
              ],
            ),
          ),
        );
        expect(badCondition, isA<ActionValidationFailed>());
      },
    );
  });

  group('TaskController lifecycle & live controls', () {
    test('completeOrRestoreTask completes open task with Undo toast and no external warning, handles repeat notice, and restores completed task', () async {
      final repeatingTask = TaskItem(
        id: 'rept000004',
        title: 'Daily Standup',
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.days),
        createdAt: fixedNow,
        modifiedAt: fixedNow,
      );
      final board = buildBaseBoard(
        tasks: <TaskItem>[...buildBaseBoard().allTasks, repeatingTask],
      );
      final container = await createContainer(board: board);
      final shell = container.read(appShellControllerProvider.notifier);
      final controller = container.read(taskControllerProvider.notifier);

      // Complete non-repeating expanded task -> collapses + keeps Undo toast.
      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'taskA00001'),
      );
      final completeResult = await controller.completeOrRestoreTask(
        'taskA00001',
      );
      expect(completeResult, isA<ActionSucceeded>());
      expect(container.read(appShellControllerProvider).expandedEntity, isNull);
      final undoNotice = container.read(floatingNoticeControllerProvider);
      expect(undoNotice?.hasUndoAction, isTrue);
      expect(undoNotice?.tone, equals(NoticeTone.accent));
      expect(
        undoNotice?.message,
        equals(localizations.taskCompletedUndoSnackBar('Alpha Task')),
      );

      // Complete repeating task -> collapses + emits repeat notice.
      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'rept000004'),
      );
      final repeatResult = await controller.completeOrRestoreTask('rept000004');
      expect(repeatResult, isA<ActionSucceeded>());
      expect(container.read(appShellControllerProvider).expandedEntity, isNull);
      expect(
        container.read(floatingNoticeControllerProvider)?.message,
        equals(localizations.taskCompletedRepeatNotice('Daily Standup')),
      );

      // Restore completed task -> emits taskRestoredNotice.
      final restoreResult = await controller.completeOrRestoreTask(
        'done000003',
      );
      expect(restoreResult, isA<ActionSucceeded>());
      expect(
        container.read(floatingNoticeControllerProvider)?.message,
        equals(localizations.taskRestoredNotice('Completed Item')),
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('done000003')
            ?.isCompleted,
        isFalse,
      );
    });

    test('downgradeTask and deleteTask wrap local mutations cleanly and preserve Undo', () async {
      final tasks = <TaskItem>[
        for (var i = 1; i <= 4; i++)
          TaskItem(
            id: 'task00000$i',
            title: 'Task $i',
            createdAt: fixedNow.add(Duration(minutes: i)),
            modifiedAt: fixedNow.add(Duration(minutes: i)),
          ),
      ];
      final container = await createContainer(
        board: buildBaseBoard(tasks: tasks),
      );
      final shell = container.read(appShellControllerProvider.notifier);
      final controller = container.read(taskControllerProvider.notifier);

      final downgradeResult = await controller.downgradeTask('task000001');
      expect(downgradeResult, isA<ActionSucceeded>());
      expect(
        container.read(floatingNoticeControllerProvider)?.message,
        equals(localizations.taskDowngradedUndoSnackBar('Task 1')),
      );

      const target = EntityRef(kind: EntityKind.task, id: 'task000002');
      shell.requestInlineDelete(target);
      final deleteResult = await controller.deleteTask('task000002');
      expect(deleteResult, isA<ActionSucceeded>());
      expect(container.read(appShellControllerProvider).expandedEntity, isNull);
      expect(
        container.read(appShellControllerProvider).activeDeleteConfirm,
        isNull,
      );
      expect(
        container.read(floatingNoticeControllerProvider)?.message,
        equals(localizations.taskDeletedUndoSnackBar('Task 2')),
        reason: 'runLocalEntityMutation must suppress external-removal toast',
      );
    });

    test('toggleSubtask auto-finishes last step, collapses card, and preserves Undo toast', () async {
      final autoTask = TaskItem(
        id: 'auto000001',
        title: 'Checklist Task',
        subtasksAutoFinish: true,
        subtasks: const <SubtaskItem>[
          SubtaskItem(title: 'First', isCompleted: true),
          SubtaskItem(title: 'Second', isCompleted: false),
        ],
        createdAt: fixedNow,
        modifiedAt: fixedNow,
      );
      final container = await createContainer(
        board: buildBaseBoard(tasks: <TaskItem>[autoTask]),
      );
      final shell = container.read(appShellControllerProvider.notifier);
      final controller = container.read(taskControllerProvider.notifier);

      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'auto000001'),
      );
      // Unchecking first step keeps card expanded.
      await controller.toggleSubtask('auto000001', 0);
      expect(
        container.read(appShellControllerProvider).expandedEntity,
        equals(const EntityRef(kind: EntityKind.task, id: 'auto000001')),
      );

      // Checking both steps completes task and collapses card.
      await controller.toggleSubtask('auto000001', 0);
      final finishResult = await controller.toggleSubtask('auto000001', 1);
      expect(finishResult, isA<ActionSucceeded>());
      expect(container.read(appShellControllerProvider).expandedEntity, isNull);
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('auto000001')
            ?.isCompleted,
        isTrue,
      );
      expect(
        container.read(floatingNoticeControllerProvider)?.hasUndoAction,
        isTrue,
      );
    });

    test('setPlacement updates priority and someday, collapses when tier changes, and emits exact notices', () async {
      final container = await createContainer();
      final shell = container.read(appShellControllerProvider.notifier);
      final controller = container.read(taskControllerProvider.notifier);

      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'taskA00001'),
      );
      final priorityResult = await controller.setPlacement(
        'taskA00001',
        TaskPlacementOption.priority,
      );
      expect(priorityResult, isA<ActionSucceeded>());
      expect(
        (priorityResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticePriorityEnabled),
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('taskA00001')
            ?.isPriority,
        isTrue,
      );

      final clearPriorityResult = await controller.setPlacement(
        'taskA00001',
        TaskPlacementOption.queue,
      );
      expect(
        (clearPriorityResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticePriorityDisabled),
      );

      final somedayResult = await controller.setPlacement(
        'taskA00001',
        TaskPlacementOption.someday,
      );
      expect(
        (somedayResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticeMovedToSomeday),
      );
      expect(
        container.read(appShellControllerProvider).expandedEntity,
        isNull,
        reason: 'Moving from Focus to Someday must collapse expanded card',
      );

      final activateResult = await controller.setPlacement(
        'taskA00001',
        TaskPlacementOption.queue,
      );
      expect(
        (activateResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticeMovedToQueue),
      );
    });

    test('toggleLabel and createAndAssignLabel handle scoped queue collapse, rotating preset color, and bounds', () async {
      final container = await createContainer();
      final shell = container.read(appShellControllerProvider.notifier);
      final controller = container.read(taskControllerProvider.notifier);

      // Adding a scoped label to taskB (which has no global label) moves it to scoped queue & collapses card.
      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'taskB00002'),
      );
      final scopedAddResult = await controller.toggleLabel(
        'taskB00002',
        'scop000002',
      );
      expect(scopedAddResult, isA<ActionSucceeded>());
      expect(
        (scopedAddResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticeTaskMovedToScopedQueue('Private')),
      );
      expect(container.read(appShellControllerProvider).expandedEntity, isNull);

      // Removing Work label from taskA emits noticeLabelRemoved.
      final removeResult = await controller.toggleLabel(
        'taskA00001',
        'work000001',
      );
      expect(
        (removeResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticeLabelRemoved('Work')),
      );

      // Re-adding Work label emits noticeLabelAdded.
      final addResult = await controller.toggleLabel(
        'taskA00001',
        'work000001',
      );
      expect(
        (addResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticeLabelAdded('Work')),
      );

      // createAndAssignLabel creates label with rotating preset color (index 2 of 8) and assigns it.
      final createResult = await controller.createAndAssignLabel(
        'taskA00001',
        'Urgent',
      );
      expect(createResult, isA<ActionSucceeded>());
      final createdLabelId = (createResult as ActionSucceeded).entityId;
      expect(createdLabelId, isNotNull);
      expect(
        createResult.noticeMessage,
        equals(localizations.noticeLabelCreatedAndAssigned('Urgent')),
      );
      final board = container.read(taskNotifierProvider).requireValue;
      final createdLabel = board.findLabel(createdLabelId ?? '');
      expect(createdLabel?.color, equals(canonicalLabelPresetHexColors[2]));
      expect(board.findTask('taskA00001')?.labelIds, contains(createdLabelId));

      // Reject duplicate, empty, control char, and > 500 scalars.
      expect(
        await controller.createAndAssignLabel('taskA00001', 'urgent'),
        isA<ActionValidationFailed>(),
      );
      expect(
        await controller.createAndAssignLabel('taskA00001', '   '),
        isA<ActionValidationFailed>(),
      );
      expect(
        await controller.createAndAssignLabel('taskA00001', 'Bad\nName'),
        isA<ActionValidationFailed>(),
      );
      expect(
        await controller.createAndAssignLabel(
          'taskA00001',
          'x' * (maxTdfTextLength + 1),
        ),
        isA<ActionValidationFailed>(),
      );
    });

    test('history live controls enforce 500 entries, 500 scalars, whitespace collapse, timestamp override, duplicate rejection, update, delete, and completed-task access', () async {
      final fullHistory = <TaskHistoryEntry>[
        for (var i = 0; i < maxTdfHistoryPerTask; i++)
          TaskHistoryEntry(
            timestampUtc: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
            text: 'Entry $i',
          ),
      ];
      final fullHistoryTask = TaskItem(
        id: 'hist000005',
        title: 'Full History Task',
        history: fullHistory,
        createdAt: fixedNow,
        modifiedAt: fixedNow,
      );
      final container = await createContainer(
        board: buildBaseBoard(
          tasks: <TaskItem>[...buildBaseBoard().allTasks, fullHistoryTask],
        ),
      );
      final controller = container.read(taskControllerProvider.notifier);

      // 501st entry rejected with historyErrorMaxExceeded.
      final maxExceeded = await controller.addHistoryEntry(
        'hist000005',
        rawText: 'Overflow entry',
      );
      expect(maxExceeded, isA<ActionValidationFailed>());
      expect(
        (maxExceeded as ActionValidationFailed).message,
        equals(localizations.historyErrorMaxExceeded),
      );

      // Add with whitespace collapse and custom local timestamp on completed task.
      final addResult = await controller.addHistoryEntry(
        'done000003',
        rawText: '  First\r\nline\twith   tabs  ',
        rawTimestampOverride: '2026-11-09 15:45',
      );
      expect(addResult, isA<ActionSucceeded>());
      var completedTask = container
          .read(taskNotifierProvider)
          .requireValue
          .findTask('done000003');
      expect(completedTask?.history, hasLength(1));
      expect(
        completedTask?.history.single.text,
        equals('First line with   tabs'),
      );
      expect(
        completedTask?.history.single.timestampUtc,
        equals(DateTime.utc(2026, 11, 9, 15, 45)),
      );

      // Exact (timestampUtc, text) duplicate must fail with historyErrorDuplicate.
      final duplicateResult = await controller.addHistoryEntry(
        'done000003',
        rawText: 'First line with   tabs',
        rawTimestampOverride: '2026-11-09 15:45',
      );
      expect(duplicateResult, isA<ActionValidationFailed>());
      expect(
        (duplicateResult as ActionValidationFailed).message,
        equals(localizations.historyErrorDuplicate),
      );

      // Add second entry and attempt to update first into exact duplicate of second.
      await controller.addHistoryEntry(
        'done000003',
        rawText: 'Second entry',
        rawTimestampOverride: '2026-11-09 16:00',
      );
      final updateDup = await controller.updateHistoryEntry(
        'done000003',
        oldTimestampUtcIso: DateTime.utc(2026, 11, 9, 15, 45).toIso8601String(),
        oldText: 'First line with   tabs',
        rawNewText: 'Second entry',
        rawNewTimestamp: '2026-11-09 16:00',
      );
      expect(updateDup, isA<ActionValidationFailed>());
      expect(
        (updateDup as ActionValidationFailed).message,
        equals(localizations.historyErrorDuplicate),
      );

      // Valid update succeeds.
      final updateOk = await controller.updateHistoryEntry(
        'done000003',
        oldTimestampUtcIso: DateTime.utc(2026, 11, 9, 15, 45).toIso8601String(),
        oldText: 'First line with   tabs',
        rawNewText: 'Updated first',
        rawNewTimestamp: '2026-11-09 15:45',
      );
      expect(updateOk, isA<ActionSucceeded>());

      // Delete removes entry.
      final deleteOk = await controller.deleteHistoryEntry(
        'done000003',
        timestampUtcIso: DateTime.utc(2026, 11, 9, 15, 45).toIso8601String(),
        text: 'Updated first',
      );
      expect(deleteOk, isA<ActionSucceeded>());
      completedTask = container
          .read(taskNotifierProvider)
          .requireValue
          .findTask('done000003');
      expect(completedTask?.history, hasLength(1));

      // Reject control char (\x00) and > 500 scalars.
      expect(
        await controller.addHistoryEntry('taskA00001', rawText: 'Bad\x00Text'),
        isA<ActionValidationFailed>(),
      );
      expect(
        await controller.addHistoryEntry(
          'taskA00001',
          rawText: 'h' * (maxTdfTextLength + 1),
        ),
        isA<ActionValidationFailed>(),
      );
    });
  });

  group('TaskController single-section inline editors', () {
    test('saveTitle closes inline edit on success and keeps open on validation failure or completed task', () async {
      final container = await createContainer();
      final shell = container.read(appShellControllerProvider.notifier);
      final controller = container.read(taskControllerProvider.notifier);

      shell.openInlineEdit(
        InlineEditTarget.task('taskA00001', TaskSectionKind.title),
      );
      final duplicateFail = await controller.saveTitle(
        'taskA00001',
        'beta task',
      );
      expect(duplicateFail, isA<ActionValidationFailed>());
      expect(
        container.read(appShellControllerProvider).activeInlineEdit,
        isNotNull,
        reason: 'Inline editor must remain open on validation failure',
      );

      final okResult = await controller.saveTitle(
        'taskA00001',
        'Alpha "Quoted" #1',
      );
      expect(okResult, isA<ActionSucceeded>());
      expect(
        container.read(appShellControllerProvider).activeInlineEdit,
        isNull,
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('taskA00001')
            ?.title,
        equals('Alpha "Quoted" #1'),
      );

      // Completed task edits must be rejected.
      expect(
        await controller.saveTitle('done000003', 'Cannot Edit'),
        isA<ActionValidationFailed>(),
      );
    });

    test(
      'saveNote and clearNote enforce 2000-scalar and control-char bounds',
      () async {
        final container = await createContainer();
        final shell = container.read(appShellControllerProvider.notifier);
        final controller = container.read(taskControllerProvider.notifier);

        shell.openInlineEdit(
          InlineEditTarget.task('taskA00001', TaskSectionKind.note),
        );
        expect(
          await controller.saveNote('taskA00001', 'x' * (maxTdfNoteLength + 1)),
          isA<ActionValidationFailed>(),
        );
        expect(
          await controller.saveNote('taskA00001', 'Bad\x00Note'),
          isA<ActionValidationFailed>(),
        );
        expect(
          container.read(appShellControllerProvider).activeInlineEdit,
          isNotNull,
        );

        final exactMax = 'n' * maxTdfNoteLength;
        expect(
          await controller.saveNote('taskA00001', exactMax),
          isA<ActionSucceeded>(),
        );
        expect(
          container.read(appShellControllerProvider).activeInlineEdit,
          isNull,
        );
        expect(
          container
              .read(taskNotifierProvider)
              .requireValue
              .findTask('taskA00001')
              ?.note,
          equals(exactMax),
        );

        expect(
          await controller.clearNote('taskA00001'),
          isA<ActionSucceeded>(),
        );
        expect(
          container
              .read(taskNotifierProvider)
              .requireValue
              .findTask('taskA00001')
              ?.note,
          isNull,
        );
      },
    );

    test('saveLinks and validateLinkInput enforce 20 links, 2048-scalar URI, and URI edge cases', () async {
      final container = await createContainer();
      final controller = container.read(taskControllerProvider.notifier);

      // Static validateLinkInput checks.
      expect(
        TaskController.validateLinkInput(
          rawTitle: 'Docs',
          rawUri: 'https://example.com',
          currentCount: 20,
          isEditingExisting: false,
          isLabel: false,
        ),
        equals(localizations.linkErrorMaxExceeded),
      );
      expect(
        TaskController.validateLinkInput(
          rawTitle: 'Docs',
          rawUri: 'https://example.com',
          currentCount: 20,
          isEditingExisting: false,
          isLabel: true,
        ),
        equals(localizations.labelLinkErrorMaxExceeded),
      );
      expect(
        TaskController.validateLinkInput(
          rawTitle: 'Docs',
          rawUri: 'https://example.com',
          currentCount: 20,
          isEditingExisting: true,
          isLabel: false,
        ),
        isNull,
        reason: 'Editing an existing link at cap 20 must be permitted',
      );

      // URI edge cases: forbidden schemes, missing scheme, control chars, length 2048 vs 2049.
      const badUris = <String>[
        'example.com/no-scheme',
        '://missing',
        '1http://bad-scheme',
        'javascript:alert(1)',
        'JAVASCRIPT:void(0)',
        'vbscript:msgbox(1)',
        'data:text/html,hi',
        'https://example.com/\x00null',
        'https://example.com/\r\ncrlf',
        'https://example.com/\ttab',
        'https://example.com/\x7fdel',
      ];
      for (final uri in badUris) {
        expect(
          TaskController.validateLinkInput(
            rawTitle: 'Ref',
            rawUri: uri,
            currentCount: 0,
            isEditingExisting: false,
            isLabel: false,
          ),
          equals(localizations.linkErrorInvalid),
          reason: 'Malformed or unsafe URI "$uri" must fail validation',
        );
      }

      const basePrefix = 'https://example.com/';
      final exactMaxUri =
          '$basePrefix${'a' * (maxTdfUriLength - basePrefix.length)}';
      final overMaxUri = '${exactMaxUri}z';
      expect(
        TaskController.validateLinkInput(
          rawTitle: 'Exact Max URI',
          rawUri: exactMaxUri,
          currentCount: 0,
          isEditingExisting: false,
          isLabel: false,
        ),
        isNull,
      );
      expect(
        TaskController.validateLinkInput(
          rawTitle: 'Over Max URI',
          rawUri: overMaxUri,
          currentCount: 0,
          isEditingExisting: false,
          isLabel: false,
        ),
        equals(localizations.linkErrorInvalid),
      );

      // Save 20 valid links succeeds; 21 fails.
      final twentyLinks = <EntityLinkInput>[
        for (var i = 0; i < maxTdfLinksPerTask; i++)
          EntityLinkInput(title: 'Link $i', uri: 'https://example.com/$i'),
      ];
      expect(
        await controller.saveLinks('taskA00001', twentyLinks),
        isA<ActionSucceeded>(),
      );
      expect(
        await controller.saveLinks('taskA00001', <EntityLinkInput>[
          ...twentyLinks,
          const EntityLinkInput(
            title: 'Extra',
            uri: 'https://example.com/extra',
          ),
        ]),
        isA<ActionValidationFailed>(),
      );
    });

    test('saveSubtasks strips blanks, enforces 1024/500 bounds, and triggers auto-finish with Undo and collapse', () async {
      final container = await createContainer();
      final shell = container.read(appShellControllerProvider.notifier);
      final controller = container.read(taskControllerProvider.notifier);

      // Reject > 1024 subtasks and > 500 scalar title.
      expect(
        await controller.saveSubtasks('taskA00001', <SubtaskInput>[
          for (var i = 0; i <= maxTdfStmtsPerBlock; i++)
            SubtaskInput(title: 'Step $i'),
        ], autoFinish: false),
        isA<ActionValidationFailed>(),
      );
      expect(
        await controller.saveSubtasks('taskA00001', <SubtaskInput>[
          SubtaskInput(title: 's' * (maxTdfTextLength + 1)),
        ], autoFinish: false),
        isA<ActionValidationFailed>(),
      );

      // Saving all-completed subtasks with autoFinish: true triggers completeTask + Undo + collapse.
      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'taskA00001'),
      );
      shell.openInlineEdit(
        InlineEditTarget.task('taskA00001', TaskSectionKind.subtasks),
      );
      final autoResult = await controller.saveSubtasks(
        'taskA00001',
        const <SubtaskInput>[
          SubtaskInput(title: 'Done step', isCompleted: true),
          SubtaskInput(title: '   ', isCompleted: false),
        ],
        autoFinish: true,
      );
      expect(autoResult, isA<ActionSucceeded>());
      expect(container.read(appShellControllerProvider).expandedEntity, isNull);
      final updated = container
          .read(taskNotifierProvider)
          .requireValue
          .findTask('taskA00001');
      expect(updated?.isCompleted, isTrue);
      expect(updated?.subtasksAutoFinish, isTrue);
      expect(updated?.subtasks, hasLength(1));
      expect(
        container.read(floatingNoticeControllerProvider)?.hasUndoAction,
        isTrue,
        reason: 'Auto-finish via saveSubtasks must push Undo toast',
      );
    });

    test('saveDue, clearDue, saveRepeat, disableRepeat, saveSuspended, and resumeTask persist and validate bounds', () async {
      final container = await createContainer();
      final shell = container.read(appShellControllerProvider.notifier);
      final controller = container.read(taskControllerProvider.notifier);

      // Due validation and persistence.
      expect(
        await controller.saveDue(
          'taskA00001',
          rawDue: 'not-a-date',
          autoPrioritize: true,
          rawDueNote: '',
        ),
        isA<ActionValidationFailed>(),
      );
      expect(
        await controller.saveDue(
          'taskA00001',
          rawDue: '2026-11-25 18:00',
          autoPrioritize: false,
          rawDueNote: 'Submit filing',
        ),
        isA<ActionSucceeded>(),
      );
      var taskA = container
          .read(taskNotifierProvider)
          .requireValue
          .findTask('taskA00001');
      expect(taskA?.dueAt, equals(DateTime.utc(2026, 11, 25, 18, 0)));
      expect(taskA?.isDuePassive, isTrue);
      expect(taskA?.dueNote, equals('Submit filing'));

      // Repeat validation (1..3650, lead 0..3650) and persistence.
      expect(
        await controller.saveRepeat(
          'taskA00001',
          rawCount: '0',
          unit: ShellRepeatUnit.days,
          rawLeadDays: '0',
        ),
        isA<ActionValidationFailed>(),
      );
      expect(
        await controller.saveRepeat(
          'taskA00001',
          rawCount: '3650',
          unit: ShellRepeatUnit.months,
          rawLeadDays: '3650',
        ),
        isA<ActionSucceeded>(),
      );
      taskA = container
          .read(taskNotifierProvider)
          .requireValue
          .findTask('taskA00001');
      expect(taskA?.repeatRule?.count, equals(3650));
      expect(taskA?.repeatRule?.leadDays, equals(3650));

      // clearDue removes due and resets repeat leadDays to 0.
      expect(await controller.clearDue('taskA00001'), isA<ActionSucceeded>());
      taskA = container
          .read(taskNotifierProvider)
          .requireValue
          .findTask('taskA00001');
      expect(taskA?.dueAt, isNull);
      expect(taskA?.repeatRule?.leadDays, equals(0));

      expect(
        await controller.disableRepeat('taskA00001'),
        isA<ActionSucceeded>(),
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('taskA00001')
            ?.repeatRule,
        isNull,
      );

      // saveSuspended moves Focus task to Blocked & collapses; resumeTask brings it back.
      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'taskA00001'),
      );
      expect(
        await controller.saveSuspended(
          'taskA00001',
          indefinitely: false,
          rawUntil: '',
          rawNote: '',
        ),
        isA<ActionValidationFailed>(),
      );
      expect(
        await controller.saveSuspended(
          'taskA00001',
          indefinitely: true,
          rawUntil: '',
          rawNote: 'Paused indefinitely',
        ),
        isA<ActionSucceeded>(),
      );
      expect(container.read(appShellControllerProvider).expandedEntity, isNull);
      taskA = container
          .read(taskNotifierProvider)
          .requireValue
          .findTask('taskA00001');
      expect(taskA?.isSuspendedForever, isTrue);
      expect(taskA?.suspendedNote, equals('Paused indefinitely'));

      expect(await controller.resumeTask('taskA00001'), isA<ActionSucceeded>());
      taskA = container
          .read(taskNotifierProvider)
          .requireValue
          .findTask('taskA00001');
      expect(taskA?.isSuspendedForever, isFalse);
      expect(taskA?.suspendedAt, isNull);
      expect(taskA?.suspendedNote, isNull);
    });

    test('savePrerequisites rejects self and transitive dependency cycles and keeps inline edit open', () async {
      final taskC = TaskItem(
        id: 'taskC00003',
        title: 'Gamma Task',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
      );
      final board = buildBaseBoard(
        tasks: <TaskItem>[...buildBaseBoard().allTasks, taskC],
      );
      final container = await createContainer(board: board);
      final shell = container.read(appShellControllerProvider.notifier);
      final controller = container.read(taskControllerProvider.notifier);

      // Chain: A -> B -> C.
      expect(
        await controller.savePrerequisites('taskA00001', const <String>[
          'taskB00002',
        ]),
        isA<ActionSucceeded>(),
      );
      expect(
        await controller.savePrerequisites('taskB00002', const <String>[
          'taskC00003',
        ]),
        isA<ActionSucceeded>(),
      );

      // Self-cycle and transitive cycle C -> A must fail.
      shell.openInlineEdit(
        InlineEditTarget.task('taskC00003', TaskSectionKind.prerequisites),
      );
      final selfCycle = await controller.savePrerequisites(
        'taskC00003',
        const <String>['taskC00003'],
      );
      expect(selfCycle, isA<ActionValidationFailed>());
      expect(
        (selfCycle as ActionValidationFailed).message,
        equals(localizations.prerequisiteCyclePreventedHint),
      );

      final transitiveCycle = await controller.savePrerequisites(
        'taskC00003',
        const <String>['taskA00001'],
      );
      expect(transitiveCycle, isA<ActionValidationFailed>());
      expect(
        (transitiveCycle as ActionValidationFailed).message,
        equals(localizations.prerequisiteCyclePreventedHint),
      );
      expect(
        container.read(appShellControllerProvider).activeInlineEdit,
        isNotNull,
      );
    });

    test('saveConditions and clearConditions compile global/group resets and custom rules and reject invalid inputs', () async {
      final container = await createContainer();
      final controller = container.read(taskControllerProvider.notifier);

      // Global reset (`condition any`).
      expect(
        await controller.saveConditions(
          'taskA00001',
          ConditionDraftViewModel(ignoreAllLabelConditions: true),
        ),
        isA<ActionSucceeded>(),
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('taskA00001')
            ?.conditions,
        equals(const <TaskCondition>[GlobalResetTaskCondition()]),
      );

      // Mixed group reset + custom rules.
      expect(
        await controller.saveConditions(
          'taskA00001',
          ConditionDraftViewModel(
            daysMode: ConditionDimensionMode.any,
            timesMode: ConditionDimensionMode.custom,
            timeWindows: const <TimeWindowDraftViewModel>[
              TimeWindowDraftViewModel(start: '08:00', end: '12:00'),
            ],
            locationsMode: ConditionDimensionMode.custom,
            selectedLocationIds: const <String>['locA000001'],
          ),
        ),
        isA<ActionSucceeded>(),
      );
      final conditions = container
          .read(taskNotifierProvider)
          .requireValue
          .findTask('taskA00001')
          ?.conditions;
      expect(conditions, hasLength(3));

      // Reject unknown location ID and invalid time window.
      expect(
        await controller.saveConditions(
          'taskA00001',
          ConditionDraftViewModel(
            locationsMode: ConditionDimensionMode.custom,
            selectedLocationIds: const <String>['unknown001'],
          ),
        ),
        isA<ActionValidationFailed>(),
      );
      expect(
        await controller.saveConditions(
          'taskA00001',
          ConditionDraftViewModel(
            timesMode: ConditionDimensionMode.custom,
            timeWindows: const <TimeWindowDraftViewModel>[
              TimeWindowDraftViewModel(start: '25:00', end: '26:00'),
            ],
          ),
        ),
        isA<ActionValidationFailed>(),
      );

      // Clear all conditions.
      expect(
        await controller.clearConditions('taskA00001'),
        isA<ActionSucceeded>(),
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('taskA00001')
            ?.conditions,
        isEmpty,
      );
    });
  });

  group('TaskController mid-flight async serialization', () {
    test('tracks isBusy/busyTaskId across await and rejects concurrent overlapping mutations', () async {
      final gate = Completer<void>();
      late _DelayedTaskNotifier delayedNotifier;
      final container = await createContainer(
        notifierFactory: () {
          delayedNotifier = _DelayedTaskNotifier(buildBaseBoard(), gate);
          return delayedNotifier;
        },
      );
      final controller = container.read(taskControllerProvider.notifier);

      final firstFuture = controller.saveNote('taskA00001', 'First save');
      expect(container.read(taskControllerProvider).isBusy, isTrue);
      expect(
        container.read(taskControllerProvider).busyTaskId,
        equals('taskA00001'),
      );

      final overlapping = await controller.saveNote(
        'taskA00001',
        'Second overlapping save',
      );
      expect(overlapping, isA<ActionPersistFailed>());
      expect(
        delayedNotifier.pushCount,
        equals(1),
        reason: 'Overlapping mutation must not trigger a second save',
      );

      gate.complete();
      final firstResult = await firstFuture;
      expect(firstResult, isA<ActionSucceeded>());
      expect(container.read(taskControllerProvider).isBusy, isFalse);
      expect(container.read(taskControllerProvider).busyTaskId, isNull);
    });
  });

  group('TaskController extreme boundaries & secondary edge cases', () {
    test('repeating subtask auto-finish via toggleSubtask and saveSubtasks reschedules, collapses, and emits repeat notice', () async {
      final repeatingSubtaskTask = TaskItem(
        id: 'rsub000001',
        title: 'Weekly Checklist',
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.weeks),
        subtasksAutoFinish: true,
        subtasks: const <SubtaskItem>[
          SubtaskItem(title: 'Step A', isCompleted: true),
          SubtaskItem(title: 'Step B', isCompleted: false),
        ],
        createdAt: fixedNow,
        modifiedAt: fixedNow,
      );
      final container = await createContainer(
        board: buildBaseBoard(tasks: <TaskItem>[repeatingSubtaskTask]),
      );
      final shell = container.read(appShellControllerProvider.notifier);
      final controller = container.read(taskControllerProvider.notifier);

      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'rsub000001'),
      );
      final toggleResult = await controller.toggleSubtask('rsub000001', 1);
      expect(toggleResult, isA<ActionSucceeded>());
      expect(
        (toggleResult as ActionSucceeded).noticeMessage,
        equals(localizations.taskCompletedRepeatNotice('Weekly Checklist')),
      );
      expect(container.read(appShellControllerProvider).expandedEntity, isNull);
      var updated = container
          .read(taskNotifierProvider)
          .requireValue
          .findTask('rsub000001');
      expect(updated?.completions, equals(1));
      expect(updated?.isCompleted, isFalse);
      expect(
        updated?.subtasks.every((step) => !step.isCompleted),
        isTrue,
        reason: 'Rescheduled repeating task must reset subtasks',
      );

      // Now trigger auto-finish via saveSubtasks on the repeating task.
      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'rsub000001'),
      );
      final saveResult = await controller.saveSubtasks(
        'rsub000001',
        const <SubtaskInput>[SubtaskInput(title: 'Step A', isCompleted: true)],
        autoFinish: true,
      );
      expect(saveResult, isA<ActionSucceeded>());
      expect(
        (saveResult as ActionSucceeded).noticeMessage,
        equals(localizations.taskCompletedRepeatNotice('Weekly Checklist')),
      );
      expect(container.read(appShellControllerProvider).expandedEntity, isNull);
      updated = container
          .read(taskNotifierProvider)
          .requireValue
          .findTask('rsub000001');
      expect(updated?.completions, equals(2));
      expect(updated?.subtasks, hasLength(1));
      expect(updated?.subtasks.single.isCompleted, isFalse);
    });

    test('accepts exact 1024 subtasks, 63 location condition refs, rejects 64 location refs, >512 time windows, and >64 prerequisites', () async {
      final locations = <TdfLocation>[
        for (var i = 0; i < maxTdfLocationRefsPerEntity + 1; i++)
          TdfLocation(
            id: 'loc${i.toString().padLeft(7, '0')}',
            name: 'Loc $i',
            latitude: 47.0,
            longitude: 8.0,
            radius: 100.0,
            modifiedAt: fixedNow,
          ),
      ];
      final manyTasks = <TaskItem>[
        for (var i = 0; i < maxTdfArgsPerStmt + 2; i++)
          TaskItem(
            id: 'tsk${i.toString().padLeft(7, '0')}',
            title: 'Bulk Task $i',
            createdAt: fixedNow.add(Duration(seconds: i)),
            modifiedAt: fixedNow.add(Duration(seconds: i)),
          ),
      ];
      final container = await createContainer(
        board: buildBaseBoard(tasks: manyTasks, locations: locations),
      );
      final controller = container.read(taskControllerProvider.notifier);

      // Exactly 1024 subtasks succeeds.
      final exactSubtasks = await controller.saveSubtasks(
        'tsk0000000',
        <SubtaskInput>[
          for (var i = 0; i < maxTdfStmtsPerBlock; i++)
            SubtaskInput(title: 'S$i'),
        ],
        autoFinish: false,
      );
      expect(
        exactSubtasks,
        isA<ActionSucceeded>(),
        reason: '1024 subtasks must satisfy maxTdfStmtsPerBlock',
      );

      // Exactly 63 location refs succeeds; 64 fails.
      final validLocationIds = <String>[
        for (var i = 0; i < maxTdfLocationRefsPerEntity; i++) locations[i].id,
      ];
      expect(
        await controller.saveConditions(
          'tsk0000000',
          ConditionDraftViewModel(
            locationsMode: ConditionDimensionMode.custom,
            selectedLocationIds: validLocationIds,
          ),
        ),
        isA<ActionSucceeded>(),
        reason: '63 location refs must satisfy maxTdfLocationRefsPerEntity',
      );
      expect(
        await controller.saveConditions(
          'tsk0000000',
          ConditionDraftViewModel(
            locationsMode: ConditionDimensionMode.custom,
            selectedLocationIds: <String>[
              ...validLocationIds,
              locations.last.id,
            ],
          ),
        ),
        isA<ActionValidationFailed>(),
        reason: '64 location refs must exceed maxTdfLocationRefsPerEntity',
      );

      // > 512 time-window rules fails.
      final overflowWindows = <TimeWindowDraftViewModel>[
        for (var i = 0; i <= maxTdfConditionRulesPerEntity; i++)
          const TimeWindowDraftViewModel(start: '08:00', end: '09:00'),
      ];
      expect(
        await controller.saveConditions(
          'tsk0000000',
          ConditionDraftViewModel(
            timesMode: ConditionDimensionMode.custom,
            timeWindows: overflowWindows,
          ),
        ),
        isA<ActionValidationFailed>(),
        reason: '513 condition rules must exceed maxTdfConditionRulesPerEntity',
      );

      // > 64 prerequisites fails; exactly 64 succeeds.
      final sixtyFourIds = <String>[
        for (var i = 1; i <= maxTdfArgsPerStmt; i++) manyTasks[i].id,
      ];
      expect(
        await controller.savePrerequisites('tsk0000000', <String>[
          ...sixtyFourIds,
          manyTasks[maxTdfArgsPerStmt + 1].id,
        ]),
        isA<ActionValidationFailed>(),
        reason: '65 prerequisites must exceed maxTdfArgsPerStmt',
      );
      expect(
        await controller.savePrerequisites('tsk0000000', sixtyFourIds),
        isA<ActionSucceeded>(),
        reason: '64 prerequisites must satisfy maxTdfArgsPerStmt',
      );
    });

    test('preserves seconds on unchanged history/due timestamps, detects scoped restriction on global label removal, and supports German locale', () async {
      final preciseTimestamp = DateTime.utc(2026, 11, 9, 14, 30, 42);
      final preciseDue = DateTime.utc(2026, 11, 20, 16, 45, 30);
      final mixedTask = TaskItem(
        id: 'mixd000001',
        title: 'Mixed Labels Task',
        labelIds: const <String>['work000001', 'scop000002'],
        dueAt: preciseDue,
        history: <TaskHistoryEntry>[
          TaskHistoryEntry(
            timestampUtc: preciseTimestamp,
            text: 'Initial entry',
          ),
        ],
        createdAt: fixedNow,
        modifiedAt: fixedNow,
      );
      final container = await createContainer(
        board: buildBaseBoard(tasks: <TaskItem>[mixedTask]),
      );
      final shell = container.read(appShellControllerProvider.notifier);
      final controller = container.read(taskControllerProvider.notifier);

      // No-op history edit succeeds and keeps exact seconds.
      expect(
        await controller.updateHistoryEntry(
          'mixd000001',
          oldTimestampUtcIso: preciseTimestamp.toIso8601String(),
          oldText: 'Initial entry',
          rawNewText: 'Initial entry',
          rawNewTimestamp: '2026-11-09 14:30:42',
        ),
        isA<ActionSucceeded>(),
      );
      // Editing text with unchanged formatted timestamp preserves :42 seconds.
      expect(
        await controller.updateHistoryEntry(
          'mixd000001',
          oldTimestampUtcIso: preciseTimestamp.toIso8601String(),
          oldText: 'Initial entry',
          rawNewText: 'Edited entry',
          rawNewTimestamp: '2026-11-09 14:30:42',
        ),
        isA<ActionSucceeded>(),
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('mixd000001')
            ?.history
            .single
            .timestampUtc,
        equals(preciseTimestamp),
      );

      // Saving dueNote with unchanged due text preserves :30 seconds on dueAt.
      expect(
        await controller.saveDue(
          'mixd000001',
          rawDue: '2026-11-20 16:45:30',
          autoPrioritize: false,
          rawDueNote: 'Note only update',
        ),
        isA<ActionSucceeded>(),
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('mixd000001')
            ?.dueAt,
        equals(preciseDue),
      );

      // Removing the last global label leaves only scoped label -> collapses and announces scoped queue move.
      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'mixd000001'),
      );
      final stripGlobalResult = await controller.toggleLabel(
        'mixd000001',
        'work000001',
      );
      expect(stripGlobalResult, isA<ActionSucceeded>());
      expect(
        (stripGlobalResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticeTaskMovedToScopedQueue('Private')),
      );
      expect(container.read(appShellControllerProvider).expandedEntity, isNull);

      // German locale formatting check on duplicate Quick-Add and validateLinkInput.
      final deLocalizations = lookupAppLocalizations(const Locale('de'));
      final deDuplicate = await controller.quickAddTask(
        rawTitle: 'mixed labels task',
        placement: TaskPlacementOption.queue,
        labelIds: const <String>[],
        locale: const Locale('de'),
      );
      expect(deDuplicate, isA<ActionValidationFailed>());
      expect(
        (deDuplicate as ActionValidationFailed).message,
        equals(deLocalizations.taskNameErrorDuplicate),
      );
      expect(
        TaskController.validateLinkInput(
          rawTitle: 'Doku',
          rawUri: 'not-a-uri',
          currentCount: 0,
          isEditingExisting: false,
          isLabel: false,
          locale: const Locale('de'),
        ),
        equals(deLocalizations.linkErrorInvalid),
      );
    });
  });
}
