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
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/board_actions_provider.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/floating_notice_providers.dart';
import 'package:tiertask/providers/shell_providers.dart';
import 'package:tiertask/providers/sync_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/task_schedule_helper.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/tdf_service.dart';

import '../ui/test_helpers.dart';

class _CountingLocalFileRepository extends FakeLocalFileRepository {
  _CountingLocalFileRepository({
    required super.config,
    required super.initialTdf,
  });

  bool failOnSave = false;
  int saveCount = 0;

  @override
  Future<void> saveTdf(String tdfContent) async {
    saveCount++;
    if (failOnSave) {
      throw const LocalFileException('Disk full while writing tasks.tdf.');
    }
    await super.saveTdf(tdfContent);
  }
}

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

class _MutableWorkspaceNotifier extends ActiveWorkspaceNotifier {
  _MutableWorkspaceNotifier(this._initialWorkspace);

  final AppWorkspace _initialWorkspace;

  @override
  Future<AppWorkspace> build() async => _initialWorkspace;

  void emitLoading() {
    state = const AsyncLoading<AppWorkspace>();
  }

  void emitWorkspace(AppWorkspace workspace) {
    state = AsyncData<AppWorkspace>(workspace);
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
    ActiveWorkspaceNotifier Function()? workspaceNotifierFactory,
  }) async {
    final effectiveBoard = board ?? buildBaseBoard();
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(config),
        ),
        if (workspaceNotifierFactory != null)
          activeWorkspaceProvider.overrideWith(workspaceNotifierFactory),
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
    final shellSubscription = container.listen(shellProvider, (_, _) {});
    final noticeSubscription = container.listen(
      floatingNoticeProvider,
      (_, _) {},
    );
    addTearDown(shellSubscription.close);
    addTearDown(noticeSubscription.close);
    return container;
  }

  Future<ProviderContainer> createRealPersistenceContainer({
    required WebDavConfig config,
    required _CountingLocalFileRepository localRepo,
    FakeWebDavRepository? webDavRepo,
    DateTime? now,
  }) async {
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(config),
        ),
        localFileRepositoryProvider.overrideWithValue(localRepo),
        if (webDavRepo != null)
          webDavRepositoryProvider.overrideWithValue(webDavRepo),
        clockProvider.overrideWithValue(() => now ?? fixedNow),
      ],
    );
    addTearDown(container.dispose);
    await container.read(webDavConfigProvider.future);
    await container.read(taskNotifierProvider.future);
    await Future<void>.microtask(() {});
    final shellSubscription = container.listen(shellProvider, (_, _) {});
    final noticeSubscription = container.listen(
      floatingNoticeProvider,
      (_, _) {},
    );
    addTearDown(shellSubscription.close);
    addTearDown(noticeSubscription.close);
    return container;
  }

  group('BoardActionsState & TaskDraftInput models', () {
    test(
      'immutable state and draft value equality, defaults, and copyWith',
      () {
        const stateA = BoardActionsState();
        const stateB = BoardActionsState(isBusy: false, busyTaskId: null);
        expect(stateA, equals(stateB));
        expect(stateA.hashCode, equals(stateB.hashCode));

        final busy = stateA.copyWith(isBusy: true, busyTaskId: 'taskA00001');
        expect(busy.isBusy, isTrue);
        expect(busy.busyTaskId, equals('taskA00001'));
        final cleared = busy.copyWith(isBusy: false, clearBusyTaskId: true);
        expect(cleared, equals(stateA));

        const linkA = TaskLink(title: 'Docs', uri: 'https://example.com');
        const linkB = TaskLink(title: 'Docs', uri: 'https://example.com');
        const subA = SubtaskItem(title: 'Step 1', isCompleted: true);
        const subB = SubtaskItem(title: 'Step 1', isCompleted: true);

        final draftA = TaskDraftInput(
          title: 'Draft',
          labelIds: const <String>['work000001'],
          links: const <TaskLink>[linkA],
          subtasks: const <SubtaskItem>[subA],
        );
        final draftB = TaskDraftInput(
          title: 'Draft',
          labelIds: const <String>['work000001'],
          links: const <TaskLink>[linkB],
          subtasks: const <SubtaskItem>[subB],
        );
        expect(draftA.placement, equals(QuickAddMode.standard));
        expect(draftA.repeatUnit, equals(RepeatUnit.days));
        expect(draftA.conditions, equals(ConditionDraft()));
        expect(draftA, equals(draftB));
        expect(draftA.hashCode, equals(draftB.hashCode));

        final copied = draftA.copyWith(
          title: 'Updated',
          placement: QuickAddMode.priority,
          repeatUnit: RepeatUnit.weeks,
          conditions: ConditionDraft(ignoreAllLabelConditions: true),
        );
        expect(copied.title, equals('Updated'));
        expect(copied.placement, equals(QuickAddMode.priority));
        expect(copied.repeatUnit, equals(RepeatUnit.weeks));
        expect(copied.conditions.ignoreAllLabelConditions, isTrue);
        expect(copied, isNot(equals(draftA)));
      },
    );
  });

  group('BoardActionsNotifier.quickAddTask', () {
    test('creates task without jumping tiers or expanding and announces noticeTaskSaved when landing in activeTier', () async {
      final container = await createContainer();
      final actions = container.read(boardActionsProvider.notifier);

      final result = await actions.quickAddTask(
        rawTitle: '  Gamma Task  ',
        placement: QuickAddMode.standard,
        labelIds: const <String>['work000001'],
      );

      expect(result, isA<ActionSucceeded>());
      final succeeded = result as ActionSucceeded;
      expect(succeeded.entityId, isNotNull);
      expect(succeeded.noticeMessage, equals(localizations.noticeTaskSaved));

      final shell = container.read(shellProvider);
      expect(shell.activeTier, equals(TaskTier.focus));
      expect(shell.expandedEntity, isNull);
      expect(
        container.read(floatingNoticeProvider)?.message,
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
      final actions = container.read(boardActionsProvider.notifier);

      final readyResult = await actions.quickAddTask(
        rawTitle: 'Fourth Active Task',
        placement: QuickAddMode.standard,
        labelIds: const <String>[],
      );
      expect(readyResult, isA<ActionSucceeded>());
      expect(
        (readyResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticeTaskSavedInTier(localizations.tier2Name)),
        reason: '4th active task lands in Ready when Focus WIP (3) is full',
      );
      expect(
        container.read(shellProvider).activeTier,
        equals(TaskTier.focus),
        reason: 'Quick-Add must never jump away from Focus',
      );

      final somedayResult = await actions.quickAddTask(
        rawTitle: 'Future Idea',
        placement: QuickAddMode.someday,
        labelIds: const <String>[],
      );
      expect(somedayResult, isA<ActionSucceeded>());
      expect(
        (somedayResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticeTaskSavedInTier(localizations.tier5Name)),
      );
      expect(container.read(shellProvider).activeTier, equals(TaskTier.focus));
    });

    test('announces noticeTaskMovedToScopedQueue when task is restricted by a scoped label outside activeLabelId', () async {
      final container = await createContainer();
      final actions = container.read(boardActionsProvider.notifier);

      final result = await actions.quickAddTask(
        rawTitle: 'Secret Chore',
        placement: QuickAddMode.standard,
        labelIds: const <String>['scop000002'],
      );
      expect(result, isA<ActionSucceeded>());
      expect(
        (result as ActionSucceeded).noticeMessage,
        equals(localizations.noticeTaskMovedToScopedQueue('Private')),
      );
      expect(
        container.read(floatingNoticeProvider)?.message,
        equals(localizations.noticeTaskMovedToScopedQueue('Private')),
      );

      container.read(shellProvider.notifier).selectLabelFilter('scop000002');
      final inScopedResult = await actions.quickAddTask(
        rawTitle: 'Visible Scoped Chore',
        placement: QuickAddMode.standard,
        labelIds: const <String>['scop000002'],
      );
      expect(inScopedResult, isA<ActionSucceeded>());
      expect(
        (inScopedResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticeTaskSaved),
      );
    });

    test('emits FloatingNoticeTone.danger floating toast and returns ActionValidationFailed on case-insensitive duplicate', () async {
      final container = await createContainer();
      final actions = container.read(boardActionsProvider.notifier);

      final result = await actions.quickAddTask(
        rawTitle: '  alpha task  ',
        placement: QuickAddMode.standard,
        labelIds: const <String>[],
      );

      expect(result, isA<ActionValidationFailed>());
      expect(
        (result as ActionValidationFailed).message,
        equals(localizations.taskNameErrorDuplicate),
      );
      final notice = container.read(floatingNoticeProvider);
      expect(notice, isNotNull);
      expect(notice?.tone, equals(FloatingNoticeTone.danger));
      expect(notice?.message, equals(localizations.taskNameErrorDuplicate));
    });

    test('enforces maxTdfTextLength (500 Unicode scalars), non-BMP scalars, control chars, and safe delimiter characters', () async {
      final container = await createContainer();
      final actions = container.read(boardActionsProvider.notifier);

      final emptyResult = await actions.quickAddTask(
        rawTitle: '   ',
        placement: QuickAddMode.standard,
        labelIds: const <String>[],
      );
      expect(emptyResult, isA<ActionValidationFailed>());

      final validNonBmp = '\u{1D400}' * maxTdfTextLength;
      final validBoundResult = await actions.quickAddTask(
        rawTitle: validNonBmp,
        placement: QuickAddMode.standard,
        labelIds: const <String>[],
      );
      expect(
        validBoundResult,
        isA<ActionSucceeded>(),
        reason: '500 non-BMP scalars must satisfy maxTdfTextLength',
      );

      final tooLongResult = await actions.quickAddTask(
        rawTitle: '${'a' * maxTdfTextLength}b',
        placement: QuickAddMode.standard,
        labelIds: const <String>[],
      );
      expect(
        tooLongResult,
        isA<ActionValidationFailed>(),
        reason: '501 scalars must fail maxTdfTextLength',
      );

      for (final badTitle in <String>[
        'Bad\nLine',
        'Bad\r\nLine',
        'Bad\tTab',
        'Bad\x00Null',
        'Bad\x7FDel',
        'Bad\uD800Surrogate',
      ]) {
        final badResult = await actions.quickAddTask(
          rawTitle: badTitle,
          placement: QuickAddMode.standard,
          labelIds: const <String>[],
        );
        expect(
          badResult,
          isA<ActionValidationFailed>(),
          reason: 'Control char or surrogate title must be rejected',
        );
      }

      const delimiterTitle = 'Quote "x" \\ {brace} #inline';
      final delimiterResult = await actions.quickAddTask(
        rawTitle: delimiterTitle,
        placement: QuickAddMode.standard,
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

  group('BoardActionsNotifier.createTaskDraft', () {
    test('commits full task draft, cancels active draft card, and emits non-jumping placement toast', () async {
      final container = await createContainer();
      final shell = container.read(shellProvider.notifier);
      shell.openDraft(EntityDraftKind.task, seedTitle: 'Seed');

      final actions = container.read(boardActionsProvider.notifier);
      final result = await actions.createTaskDraft(
        TaskDraftInput(
          title: 'Rich Draft Task',
          note: 'Line 1\r\nLine 2\tindented',
          placement: QuickAddMode.priority,
          labelIds: const <String>['work000001'],
          links: const <TaskLink>[
            TaskLink(title: 'Spec', uri: 'https://example.com/spec'),
          ],
          subtasks: const <SubtaskItem>[
            SubtaskItem(title: 'Step 1'),
            SubtaskItem(title: '   '),
            SubtaskItem(title: 'Step 2', isCompleted: true),
          ],
          subtasksAutoFinish: true,
          rawDue: '2026-11-20 14:30',
          autoPrioritizeDue: false,
          rawDueNote: 'Before demo',
          isRepeating: true,
          rawRepeatCount: '2',
          repeatUnit: RepeatUnit.weeks,
          rawRepeatLeadDays: '3',
          isSuspended: true,
          suspendedIndefinitely: false,
          rawSuspendedUntil: '2026-11-15 09:00',
          rawSuspendedNote: 'Waiting on vendor',
          prerequisiteTaskIds: const <String>['taskA00001'],
          conditions: ConditionDraft(
            daysMode: ConditionDimensionMode.custom,
            weekdays: const <int>[1, 3, 5],
            timeMode: ConditionDimensionMode.custom,
            timeWindows: const <TimeWindowDraft>[
              TimeWindowDraft(start: '09:00', end: '17:00'),
            ],
            locationMode: ConditionDimensionMode.custom,
            locationIds: const <String>['locA000001'],
          ),
        ),
      );

      expect(result, isA<ActionSucceeded>());
      final succeeded = result as ActionSucceeded;
      expect(
        container.read(shellProvider).activeDraft,
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
        container.read(shellProvider.notifier).openDraft(EntityDraftKind.task);
        final actions = container.read(boardActionsProvider.notifier);

        final noteTooLong = await actions.createTaskDraft(
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
          container.read(shellProvider).activeDraft,
          equals(EntityDraftKind.task),
        );

        final tooManyLinks = await actions.createTaskDraft(
          TaskDraftInput(
            title: 'Link Bound Task',
            links: <TaskLink>[
              for (var i = 0; i <= maxTdfLinksPerTask; i++)
                TaskLink(title: 'Link $i', uri: 'https://example.com/$i'),
            ],
          ),
        );
        expect(tooManyLinks, isA<ActionValidationFailed>());
        expect(
          (tooManyLinks as ActionValidationFailed).fieldErrors['links'],
          equals(localizations.linkErrorMaxExceeded),
        );

        final tooManySubtasks = await actions.createTaskDraft(
          TaskDraftInput(
            title: 'Subtask Bound Task',
            subtasks: <SubtaskItem>[
              for (var i = 0; i <= maxTdfStmtsPerBlock; i++)
                SubtaskItem(title: 'Step $i'),
            ],
          ),
        );
        expect(tooManySubtasks, isA<ActionValidationFailed>());

        final badRepeat = await actions.createTaskDraft(
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

        final badSuspended = await actions.createTaskDraft(
          TaskDraftInput(
            title: 'Bad Suspend Task',
            isSuspended: true,
            suspendedIndefinitely: false,
            rawSuspendedUntil: '',
          ),
        );
        expect(badSuspended, isA<ActionValidationFailed>());

        final badCondition = await actions.createTaskDraft(
          TaskDraftInput(
            title: 'Bad Condition Task',
            conditions: ConditionDraft(
              timeMode: ConditionDimensionMode.custom,
              timeWindows: const <TimeWindowDraft>[
                TimeWindowDraft(start: '10:00', end: '10:00'),
              ],
            ),
          ),
        );
        expect(badCondition, isA<ActionValidationFailed>());

        final indefiniteSuspended = await actions.createTaskDraft(
          TaskDraftInput(
            title: 'Indefinitely Suspended Task',
            isSuspended: true,
            suspendedIndefinitely: true,
            rawSuspendedNote: 'Someday maybe blocked',
          ),
        );
        expect(indefiniteSuspended, isA<ActionSucceeded>());
        final created = container
            .read(taskNotifierProvider)
            .requireValue
            .findTask((indefiniteSuspended as ActionSucceeded).entityId ?? '');
        expect(created?.isSuspendedForever, isTrue);
        expect(created?.suspendedNote, equals('Someday maybe blocked'));
      },
    );
  });

  group('BoardActionsNotifier lifecycle & live controls', () {
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
      final shell = container.read(shellProvider.notifier);
      final actions = container.read(boardActionsProvider.notifier);

      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'taskA00001'),
      );
      final completeResult = await actions.completeOrRestoreTask('taskA00001');
      expect(completeResult, isA<ActionSucceeded>());
      expect(container.read(shellProvider).expandedEntity, isNull);
      final undoNotice = container.read(floatingNoticeProvider);
      expect(undoNotice?.hasUndoAction, isTrue);
      expect(undoNotice?.tone, equals(FloatingNoticeTone.accent));
      expect(
        undoNotice?.message,
        equals(localizations.taskCompletedUndoSnackBar('Alpha Task')),
      );

      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'rept000004'),
      );
      final repeatResult = await actions.completeOrRestoreTask('rept000004');
      expect(repeatResult, isA<ActionSucceeded>());
      expect(container.read(shellProvider).expandedEntity, isNull);
      expect(
        container.read(floatingNoticeProvider)?.message,
        equals(localizations.taskCompletedRepeatNotice('Daily Standup')),
      );

      final restoreResult = await actions.completeOrRestoreTask('done000003');
      expect(restoreResult, isA<ActionSucceeded>());
      expect(
        container.read(floatingNoticeProvider)?.message,
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
      final shell = container.read(shellProvider.notifier);
      final actions = container.read(boardActionsProvider.notifier);

      final downgradeResult = await actions.downgradeTask('task000001');
      expect(downgradeResult, isA<ActionSucceeded>());
      expect(
        container.read(floatingNoticeProvider)?.message,
        equals(localizations.taskDowngradedUndoSnackBar('Task 1')),
      );

      const target = EntityRef(kind: EntityKind.task, id: 'task000002');
      shell.requestInlineDelete(target);
      final deleteResult = await actions.deleteTask('task000002');
      expect(deleteResult, isA<ActionSucceeded>());
      expect(container.read(shellProvider).expandedEntity, isNull);
      expect(container.read(shellProvider).activeDeleteConfirm, isNull);
      expect(
        container.read(floatingNoticeProvider)?.message,
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
      final shell = container.read(shellProvider.notifier);
      final actions = container.read(boardActionsProvider.notifier);

      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'auto000001'),
      );
      await actions.toggleSubtask('auto000001', 0);
      expect(
        container.read(shellProvider).expandedEntity,
        equals(const EntityRef(kind: EntityKind.task, id: 'auto000001')),
      );

      await actions.toggleSubtask('auto000001', 0);
      final finishResult = await actions.toggleSubtask('auto000001', 1);
      expect(finishResult, isA<ActionSucceeded>());
      expect(container.read(shellProvider).expandedEntity, isNull);
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('auto000001')
            ?.isCompleted,
        isTrue,
      );
      expect(container.read(floatingNoticeProvider)?.hasUndoAction, isTrue);
    });

    test('setPlacement updates priority and someday, collapses when tier changes, and emits exact notices', () async {
      final container = await createContainer();
      final shell = container.read(shellProvider.notifier);
      final actions = container.read(boardActionsProvider.notifier);

      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'taskA00001'),
      );
      final priorityResult = await actions.setPlacement(
        'taskA00001',
        QuickAddMode.priority,
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

      final clearPriorityResult = await actions.setPlacement(
        'taskA00001',
        QuickAddMode.standard,
      );
      expect(
        (clearPriorityResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticePriorityDisabled),
      );

      final somedayResult = await actions.setPlacement(
        'taskA00001',
        QuickAddMode.someday,
      );
      expect(
        (somedayResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticeMovedToSomeday),
      );
      expect(
        container.read(shellProvider).expandedEntity,
        isNull,
        reason: 'Moving from Focus to Someday must collapse expanded card',
      );

      final activateResult = await actions.setPlacement(
        'taskA00001',
        QuickAddMode.standard,
      );
      expect(
        (activateResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticeMovedToQueue),
      );
    });

    test('toggleLabel and createAndAssignLabel handle scoped queue collapse, rotating preset color, and bounds', () async {
      final container = await createContainer();
      final shell = container.read(shellProvider.notifier);
      final actions = container.read(boardActionsProvider.notifier);

      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'taskB00002'),
      );
      final scopedAddResult = await actions.toggleLabel(
        'taskB00002',
        'scop000002',
      );
      expect(scopedAddResult, isA<ActionSucceeded>());
      expect(
        (scopedAddResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticeTaskMovedToScopedQueue('Private')),
      );
      expect(container.read(shellProvider).expandedEntity, isNull);

      final removeResult = await actions.toggleLabel(
        'taskA00001',
        'work000001',
      );
      expect(
        (removeResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticeLabelRemoved('Work')),
      );

      final addResult = await actions.toggleLabel('taskA00001', 'work000001');
      expect(
        (addResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticeLabelAdded('Work')),
      );

      final createResult = await actions.createAndAssignLabel(
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

      expect(
        await actions.createAndAssignLabel('taskA00001', 'urgent'),
        isA<ActionValidationFailed>(),
      );
      expect(
        await actions.createAndAssignLabel('taskA00001', '   '),
        isA<ActionValidationFailed>(),
      );
      expect(
        await actions.createAndAssignLabel('taskA00001', 'Bad\nName'),
        isA<ActionValidationFailed>(),
      );
      expect(
        await actions.createAndAssignLabel(
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
      final actions = container.read(boardActionsProvider.notifier);

      final maxExceeded = await actions.addHistoryEntry(
        'hist000005',
        rawText: 'Overflow entry',
      );
      expect(maxExceeded, isA<ActionValidationFailed>());
      expect(
        (maxExceeded as ActionValidationFailed).message,
        equals(localizations.historyErrorMaxExceeded),
      );

      final addResult = await actions.addHistoryEntry(
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

      final duplicateResult = await actions.addHistoryEntry(
        'done000003',
        rawText: 'First line with   tabs',
        rawTimestampOverride: '2026-11-09 15:45',
      );
      expect(duplicateResult, isA<ActionValidationFailed>());
      expect(
        (duplicateResult as ActionValidationFailed).message,
        equals(localizations.historyErrorDuplicate),
      );

      await actions.addHistoryEntry(
        'done000003',
        rawText: 'Second entry',
        rawTimestampOverride: '2026-11-09 16:00',
      );
      final updateDup = await actions.updateHistoryEntry(
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

      final updateOk = await actions.updateHistoryEntry(
        'done000003',
        oldTimestampUtcIso: DateTime.utc(2026, 11, 9, 15, 45).toIso8601String(),
        oldText: 'First line with   tabs',
        rawNewText: 'Updated first',
        rawNewTimestamp: '2026-11-09 15:45',
      );
      expect(updateOk, isA<ActionSucceeded>());

      final deleteOk = await actions.deleteHistoryEntry(
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

      expect(
        await actions.addHistoryEntry('taskA00001', rawText: 'Bad\x00Text'),
        isA<ActionValidationFailed>(),
      );
      expect(
        await actions.addHistoryEntry(
          'taskA00001',
          rawText: 'h' * (maxTdfTextLength + 1),
        ),
        isA<ActionValidationFailed>(),
      );
    });
  });

  group('BoardActionsNotifier single-section inline editors', () {
    test('saveTitle closes inline edit on success and keeps open on validation failure or completed task', () async {
      final container = await createContainer();
      final shell = container.read(shellProvider.notifier);
      final actions = container.read(boardActionsProvider.notifier);

      shell.openInlineEdit(
        InlineEditTarget.task('taskA00001', TaskSectionKind.title),
      );
      final duplicateFail = await actions.saveTitle('taskA00001', 'beta task');
      expect(duplicateFail, isA<ActionValidationFailed>());
      expect(
        container.read(shellProvider).activeInlineEdit,
        isNotNull,
        reason: 'Inline editor must remain open on validation failure',
      );

      final okResult = await actions.saveTitle(
        'taskA00001',
        'Alpha "Quoted" #1',
      );
      expect(okResult, isA<ActionSucceeded>());
      expect(container.read(shellProvider).activeInlineEdit, isNull);
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('taskA00001')
            ?.title,
        equals('Alpha "Quoted" #1'),
      );

      expect(
        await actions.saveTitle('done000003', 'Cannot Edit'),
        isA<ActionValidationFailed>(),
      );
    });

    test(
      'saveNote and clearNote enforce 2000-scalar and control-char bounds',
      () async {
        final container = await createContainer();
        final shell = container.read(shellProvider.notifier);
        final actions = container.read(boardActionsProvider.notifier);

        shell.openInlineEdit(
          InlineEditTarget.task('taskA00001', TaskSectionKind.note),
        );
        expect(
          await actions.saveNote('taskA00001', 'x' * (maxTdfNoteLength + 1)),
          isA<ActionValidationFailed>(),
        );
        expect(
          await actions.saveNote('taskA00001', 'Bad\x00Note'),
          isA<ActionValidationFailed>(),
        );
        expect(container.read(shellProvider).activeInlineEdit, isNotNull);

        final exactMax = 'n' * maxTdfNoteLength;
        expect(
          await actions.saveNote('taskA00001', exactMax),
          isA<ActionSucceeded>(),
        );
        expect(container.read(shellProvider).activeInlineEdit, isNull);
        expect(
          container
              .read(taskNotifierProvider)
              .requireValue
              .findTask('taskA00001')
              ?.note,
          equals(exactMax),
        );

        expect(await actions.clearNote('taskA00001'), isA<ActionSucceeded>());
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

    test(
      'saveLinks enforces 20 links, 2048-scalar URI, and URI edge cases',
      () async {
        final container = await createContainer();
        final actions = container.read(boardActionsProvider.notifier);

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
            await actions.saveLinks('taskA00001', <TaskLink>[
              TaskLink(title: 'Ref', uri: uri),
            ]),
            isA<ActionValidationFailed>(),
            reason: 'Malformed or unsafe URI "$uri" must fail validation',
          );
        }

        const basePrefix = 'https://example.com/';
        final exactMaxUri =
            '$basePrefix${'a' * (maxTdfUriLength - basePrefix.length)}';
        final overMaxUri = '${exactMaxUri}z';
        expect(
          await actions.saveLinks('taskA00001', <TaskLink>[
            TaskLink(title: 'Exact Max URI', uri: exactMaxUri),
          ]),
          isA<ActionSucceeded>(),
        );
        expect(
          await actions.saveLinks('taskA00001', <TaskLink>[
            TaskLink(title: 'Over Max URI', uri: overMaxUri),
          ]),
          isA<ActionValidationFailed>(),
        );

        final twentyLinks = <TaskLink>[
          for (var i = 0; i < maxTdfLinksPerTask; i++)
            TaskLink(title: 'Link $i', uri: 'https://example.com/$i'),
        ];
        expect(
          await actions.saveLinks('taskA00001', twentyLinks),
          isA<ActionSucceeded>(),
        );
        expect(
          await actions.saveLinks('taskA00001', <TaskLink>[
            ...twentyLinks,
            const TaskLink(title: 'Extra', uri: 'https://example.com/extra'),
          ]),
          isA<ActionValidationFailed>(),
        );
      },
    );

    test('saveSubtasks strips blanks, enforces 1024/500 bounds, and triggers auto-finish with Undo and collapse', () async {
      final container = await createContainer();
      final shell = container.read(shellProvider.notifier);
      final actions = container.read(boardActionsProvider.notifier);

      expect(
        await actions.saveSubtasks('taskA00001', <SubtaskItem>[
          for (var i = 0; i <= maxTdfStmtsPerBlock; i++)
            SubtaskItem(title: 'Step $i'),
        ], autoFinish: false),
        isA<ActionValidationFailed>(),
      );
      expect(
        await actions.saveSubtasks('taskA00001', <SubtaskItem>[
          SubtaskItem(title: 's' * (maxTdfTextLength + 1)),
        ], autoFinish: false),
        isA<ActionValidationFailed>(),
      );

      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'taskA00001'),
      );
      shell.openInlineEdit(
        InlineEditTarget.task('taskA00001', TaskSectionKind.subtasks),
      );
      final autoResult = await actions.saveSubtasks(
        'taskA00001',
        const <SubtaskItem>[
          SubtaskItem(title: 'Done step', isCompleted: true),
          SubtaskItem(title: '   ', isCompleted: false),
        ],
        autoFinish: true,
      );
      expect(autoResult, isA<ActionSucceeded>());
      expect(container.read(shellProvider).expandedEntity, isNull);
      final updated = container
          .read(taskNotifierProvider)
          .requireValue
          .findTask('taskA00001');
      expect(updated?.isCompleted, isTrue);
      expect(updated?.subtasksAutoFinish, isTrue);
      expect(updated?.subtasks, hasLength(1));
      expect(updated?.subtasks.single.isCompleted, isTrue);
      expect(
        container.read(floatingNoticeProvider)?.hasUndoAction,
        isTrue,
        reason: 'Auto-finish via saveSubtasks must push Undo toast',
      );
    });

    test('saveDue, clearDue, saveRepeat, disableRepeat, saveSuspended, and resumeTask persist and validate bounds', () async {
      final container = await createContainer();
      final shell = container.read(shellProvider.notifier);
      final actions = container.read(boardActionsProvider.notifier);

      expect(
        await actions.saveDue(
          'taskA00001',
          rawDue: 'not-a-date',
          autoPrioritize: true,
          rawDueNote: '',
        ),
        isA<ActionValidationFailed>(),
      );
      expect(
        await actions.saveDue(
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

      expect(
        await actions.saveRepeat(
          'taskA00001',
          rawCount: '0',
          unit: RepeatUnit.days,
          rawLeadDays: '0',
        ),
        isA<ActionValidationFailed>(),
      );
      expect(
        await actions.saveRepeat(
          'taskA00001',
          rawCount: '3650',
          unit: RepeatUnit.months,
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

      expect(await actions.clearDue('taskA00001'), isA<ActionSucceeded>());
      taskA = container
          .read(taskNotifierProvider)
          .requireValue
          .findTask('taskA00001');
      expect(taskA?.dueAt, isNull);
      expect(taskA?.repeatRule?.leadDays, equals(0));

      expect(await actions.disableRepeat('taskA00001'), isA<ActionSucceeded>());
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('taskA00001')
            ?.repeatRule,
        isNull,
      );

      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'taskA00001'),
      );
      expect(
        await actions.saveSuspended(
          'taskA00001',
          indefinitely: false,
          rawUntil: '',
          rawNote: '',
        ),
        isA<ActionValidationFailed>(),
      );
      expect(
        await actions.saveSuspended(
          'taskA00001',
          indefinitely: true,
          rawUntil: '',
          rawNote: 'Paused indefinitely',
        ),
        isA<ActionSucceeded>(),
      );
      expect(container.read(shellProvider).expandedEntity, isNull);
      taskA = container
          .read(taskNotifierProvider)
          .requireValue
          .findTask('taskA00001');
      expect(taskA?.isSuspendedForever, isTrue);
      expect(taskA?.suspendedNote, equals('Paused indefinitely'));

      expect(await actions.resumeTask('taskA00001'), isA<ActionSucceeded>());
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
      final shell = container.read(shellProvider.notifier);
      final actions = container.read(boardActionsProvider.notifier);

      expect(
        await actions.savePrerequisites('taskA00001', const <String>[
          'taskB00002',
        ]),
        isA<ActionSucceeded>(),
      );
      expect(
        await actions.savePrerequisites('taskB00002', const <String>[
          'taskC00003',
        ]),
        isA<ActionSucceeded>(),
      );

      shell.openInlineEdit(
        InlineEditTarget.task('taskC00003', TaskSectionKind.prerequisites),
      );
      final selfCycle = await actions.savePrerequisites(
        'taskC00003',
        const <String>['taskC00003'],
      );
      expect(selfCycle, isA<ActionValidationFailed>());
      expect(
        (selfCycle as ActionValidationFailed).message,
        equals(localizations.prerequisiteCyclePreventedHint),
      );

      final transitiveCycle = await actions.savePrerequisites(
        'taskC00003',
        const <String>['taskA00001'],
      );
      expect(transitiveCycle, isA<ActionValidationFailed>());
      expect(
        (transitiveCycle as ActionValidationFailed).message,
        equals(localizations.prerequisiteCyclePreventedHint),
      );
      expect(container.read(shellProvider).activeInlineEdit, isNotNull);
    });

    test('saveConditions and clearConditions compile global/group resets and custom rules and reject invalid inputs', () async {
      final container = await createContainer();
      final actions = container.read(boardActionsProvider.notifier);

      expect(
        await actions.saveConditions(
          'taskA00001',
          ConditionDraft(ignoreAllLabelConditions: true),
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

      expect(
        await actions.saveConditions(
          'taskA00001',
          ConditionDraft(
            daysMode: ConditionDimensionMode.any,
            timeMode: ConditionDimensionMode.custom,
            timeWindows: const <TimeWindowDraft>[
              TimeWindowDraft(start: '08:00', end: '12:00'),
            ],
            locationMode: ConditionDimensionMode.custom,
            locationIds: const <String>['locA000001'],
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

      expect(
        await actions.saveConditions(
          'taskA00001',
          ConditionDraft(
            locationMode: ConditionDimensionMode.custom,
            locationIds: const <String>['unknown001'],
          ),
        ),
        isA<ActionValidationFailed>(),
      );
      expect(
        await actions.saveConditions(
          'taskA00001',
          ConditionDraft(
            timeMode: ConditionDimensionMode.custom,
            timeWindows: const <TimeWindowDraft>[
              TimeWindowDraft(start: '25:00', end: '26:00'),
            ],
          ),
        ),
        isA<ActionValidationFailed>(),
      );

      expect(
        await actions.clearConditions('taskA00001'),
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

  group(
    'BoardActionsNotifier mid-flight async serialization & workspace switching',
    () {
      test('tracks isBusy/busyTaskId across await and rejects concurrent overlapping mutations', () async {
        final gate = Completer<void>();
        late _DelayedTaskNotifier delayedNotifier;
        final container = await createContainer(
          notifierFactory: () {
            delayedNotifier = _DelayedTaskNotifier(buildBaseBoard(), gate);
            return delayedNotifier;
          },
        );
        final actions = container.read(boardActionsProvider.notifier);

        final firstFuture = actions.saveNote('taskA00001', 'First save');
        expect(container.read(boardActionsProvider).isBusy, isTrue);
        expect(
          container.read(boardActionsProvider).busyTaskId,
          equals('taskA00001'),
        );

        final overlapping = await actions.saveNote(
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
        expect(container.read(boardActionsProvider).isBusy, isFalse);
        expect(container.read(boardActionsProvider).busyTaskId, isNull);
      });

      test('ignores transient AsyncLoading on activeWorkspaceProvider and resets busy state on actual workspace switch', () async {
        const config = WebDavConfig(
          language: AppLanguage.english,
          timeZoneMode: AppTimeZoneMode.manual,
          manualTimeZoneOffsetMinutes: 0,
        );
        const workspaceA = AppWorkspace(
          id: 'wsA0000001',
          name: 'Workspace A',
          config: config,
        );
        const workspaceB = AppWorkspace(
          id: 'wsB0000002',
          name: 'Workspace B',
          config: config,
        );
        final gate = Completer<void>();
        late _MutableWorkspaceNotifier workspaceNotifier;
        final container = await createContainer(
          config: config,
          workspaceNotifierFactory: () {
            workspaceNotifier = _MutableWorkspaceNotifier(workspaceA);
            return workspaceNotifier;
          },
          notifierFactory: () => _DelayedTaskNotifier(buildBaseBoard(), gate),
        );
        final actions = container.read(boardActionsProvider.notifier);

        final inFlight = actions.saveNote('taskA00001', 'Pending note');
        expect(container.read(boardActionsProvider).isBusy, isTrue);

        // Transient AsyncLoading must NOT clear busy state.
        workspaceNotifier.emitLoading();
        expect(
          container.read(boardActionsProvider).isBusy,
          isTrue,
          reason: 'Transient AsyncLoading must not clear busy state',
        );

        // Actual workspace switch resets busy state immediately and invalidates stale token.
        workspaceNotifier.emitWorkspace(workspaceB);
        expect(
          container.read(boardActionsProvider).isBusy,
          isFalse,
          reason: 'Switching workspace must clear busy state',
        );

        gate.complete();
        await inFlight;
        expect(container.read(boardActionsProvider).isBusy, isFalse);
      });
    },
  );

  group('BoardActionsNotifier TEP-020 critical persistence & atomicity fixes', () {
    test('offline StorageMode.both inline edits succeed locally and close inline editor while remote WebDAV error stays in syncStateProvider', () async {
      const config = WebDavConfig(
        storageMode: StorageMode.both,
        localFilePath: 'tasks.tdf',
        serverUrl: 'https://webdav.example.com',
        username: 'alice',
        password: 'secret-app-password',
        filePath: '/tasks.tdf',
        language: AppLanguage.english,
        timeZoneMode: AppTimeZoneMode.manual,
        manualTimeZoneOffsetMinutes: 0,
      );
      final initialTdf = const TdfService().serialize(buildBaseBoard());
      final localRepo = _CountingLocalFileRepository(
        config: config,
        initialTdf: initialTdf,
      );
      var isWebDavOffline = false;
      final remoteStore = <String, String>{
        config.resolveEndpointUri()?.path ?? '': initialTdf,
      };
      final webDavRepo = FakeWebDavRepository(
        config: config,
        shouldFail: () => isWebDavOffline,
        remoteStore: remoteStore,
      );
      final container = await createRealPersistenceContainer(
        config: config,
        localRepo: localRepo,
        webDavRepo: webDavRepo,
      );
      isWebDavOffline = true;
      final shell = container.read(shellProvider.notifier);
      final actions = container.read(boardActionsProvider.notifier);

      // Inline title edit while WebDAV is offline.
      shell.openInlineEdit(
        InlineEditTarget.task('taskA00001', TaskSectionKind.title),
      );
      final titleResult = await actions.saveTitle(
        'taskA00001',
        'Alpha Offline Title',
      );
      expect(
        titleResult,
        isA<ActionSucceeded>(),
        reason: 'Offline dual-storage local commit must return ActionSucceeded',
      );
      expect(
        container.read(shellProvider).activeInlineEdit,
        isNull,
        reason: 'Inline editor must close when local write committed',
      );
      expect(
        container.read(taskNotifierProvider.notifier).lastMutationCommitted,
        isTrue,
      );
      expect(
        container.read(syncStateProvider).errorMessage,
        isNotNull,
        reason: 'Non-blocking syncStateProvider must still report WebDAV error',
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('taskA00001')
            ?.title,
        equals('Alpha Offline Title'),
      );
      expect(localRepo.initialTdf, contains('Alpha Offline Title'));

      // Inline note edit while WebDAV remains offline.
      shell.openInlineEdit(
        InlineEditTarget.task('taskA00001', TaskSectionKind.note),
      );
      final noteResult = await actions.saveNote(
        'taskA00001',
        'Saved locally offline',
      );
      expect(noteResult, isA<ActionSucceeded>());
      expect(container.read(shellProvider).activeInlineEdit, isNull);
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('taskA00001')
            ?.note,
        equals('Saved locally offline'),
      );
      expect(container.read(syncStateProvider).errorMessage, isNotNull);

      // History add and update also succeed locally while WebDAV remains offline.
      final historyAddResult = await actions.addHistoryEntry(
        'taskA00001',
        rawText: 'Offline entry',
        rawTimestampOverride: '2026-11-10 11:00',
      );
      expect(historyAddResult, isA<ActionSucceeded>());
      final historyUpdateResult = await actions.updateHistoryEntry(
        'taskA00001',
        oldTimestampUtcIso: DateTime.utc(2026, 11, 10, 11, 0).toIso8601String(),
        oldText: 'Offline entry',
        rawNewText: 'Offline entry updated',
        rawNewTimestamp: '2026-11-10 11:00',
      );
      expect(historyUpdateResult, isA<ActionSucceeded>());
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('taskA00001')
            ?.history
            .single
            .text,
        equals('Offline entry updated'),
      );
      expect(container.read(syncStateProvider).errorMessage, isNotNull);
    });

    test('failed local write and failed WebDAV-only persistence return ActionPersistFailed and keep inline editor open', () async {
      // 1. Local storage write failure rolls back and keeps inline editor open.
      const localConfig = WebDavConfig(
        storageMode: StorageMode.local,
        localFilePath: 'tasks.tdf',
        language: AppLanguage.english,
        timeZoneMode: AppTimeZoneMode.manual,
        manualTimeZoneOffsetMinutes: 0,
      );
      final initialTdf = const TdfService().serialize(buildBaseBoard());
      final failingLocalRepo = _CountingLocalFileRepository(
        config: localConfig,
        initialTdf: initialTdf,
      );
      final localContainer = await createRealPersistenceContainer(
        config: localConfig,
        localRepo: failingLocalRepo,
      );
      failingLocalRepo.failOnSave = true;

      localContainer
          .read(shellProvider.notifier)
          .openInlineEdit(
            InlineEditTarget.task('taskA00001', TaskSectionKind.note),
          );
      final localFail = await localContainer
          .read(boardActionsProvider.notifier)
          .saveNote('taskA00001', 'Unpersisted note');
      expect(localFail, isA<ActionPersistFailed>());
      expect(
        localContainer
            .read(taskNotifierProvider.notifier)
            .lastMutationCommitted,
        isFalse,
      );
      expect(
        localContainer.read(shellProvider).activeInlineEdit,
        equals(InlineEditTarget.task('taskA00001', TaskSectionKind.note)),
        reason: 'Inline editor must stay open when local write fails',
      );
      expect(
        localContainer
            .read(taskNotifierProvider)
            .requireValue
            .findTask('taskA00001')
            ?.note,
        isNull,
        reason: 'Board state must roll back on local write failure',
      );

      // 2. WebDAV-only persistence failure rolls back and keeps inline editor open.
      const webDavOnlyConfig = WebDavConfig(
        storageMode: StorageMode.webdav,
        serverUrl: 'https://webdav.example.com',
        username: 'alice',
        password: 'secret-app-password',
        filePath: '/tasks.tdf',
        language: AppLanguage.english,
        timeZoneMode: AppTimeZoneMode.manual,
        manualTimeZoneOffsetMinutes: 0,
      );
      var shouldFailWebDav = false;
      final remoteStore = <String, String>{
        webDavOnlyConfig.resolveEndpointUri()?.path ?? '': initialTdf,
      };
      final webDavRepo = FakeWebDavRepository(
        config: webDavOnlyConfig,
        shouldFail: () => shouldFailWebDav,
        remoteStore: remoteStore,
      );
      final webDavContainer = await createRealPersistenceContainer(
        config: webDavOnlyConfig,
        localRepo: _CountingLocalFileRepository(
          config: webDavOnlyConfig,
          initialTdf: '',
        ),
        webDavRepo: webDavRepo,
      );
      shouldFailWebDav = true;

      webDavContainer
          .read(shellProvider.notifier)
          .openInlineEdit(
            InlineEditTarget.task('taskA00001', TaskSectionKind.title),
          );
      final webDavFail = await webDavContainer
          .read(boardActionsProvider.notifier)
          .saveTitle('taskA00001', 'Remote Failure Title');
      expect(webDavFail, isA<ActionPersistFailed>());
      expect(
        webDavContainer
            .read(taskNotifierProvider.notifier)
            .lastMutationCommitted,
        isFalse,
      );
      expect(
        webDavContainer.read(shellProvider).activeInlineEdit,
        equals(InlineEditTarget.task('taskA00001', TaskSectionKind.title)),
        reason: 'Inline editor must stay open when WebDAV-only save fails',
      );
      expect(
        webDavContainer
            .read(taskNotifierProvider)
            .requireValue
            .findTask('taskA00001')
            ?.title,
        equals('Alpha Task'),
        reason: 'Board state must roll back on WebDAV-only save failure',
      );
    });

    test('createAndAssignLabel executes in one single storage write', () async {
      const config = WebDavConfig(
        storageMode: StorageMode.local,
        localFilePath: 'tasks.tdf',
        language: AppLanguage.english,
        timeZoneMode: AppTimeZoneMode.manual,
        manualTimeZoneOffsetMinutes: 0,
      );
      final initialTdf = const TdfService().serialize(buildBaseBoard());
      final localRepo = _CountingLocalFileRepository(
        config: config,
        initialTdf: initialTdf,
      );
      final container = await createRealPersistenceContainer(
        config: config,
        localRepo: localRepo,
      );
      localRepo.saveCount = 0;

      final result = await container
          .read(boardActionsProvider.notifier)
          .createAndAssignLabel('taskA00001', 'Urgent');

      expect(result, isA<ActionSucceeded>());
      final succeeded = result as ActionSucceeded;
      expect(
        localRepo.saveCount,
        equals(1),
        reason: 'createAndAssignLabel must commit in one atomic storage write',
      );
      expect(
        succeeded.noticeMessage,
        equals(localizations.noticeLabelCreatedAndAssigned('Urgent')),
      );
      final board = container.read(taskNotifierProvider).requireValue;
      final createdLabel = board.findLabel(succeeded.entityId ?? '');
      expect(createdLabel, isNotNull);
      expect(createdLabel?.color, equals(canonicalLabelPresetHexColors[2]));
      expect(
        board.findTask('taskA00001')?.labelIds,
        contains(createdLabel?.id),
      );
    });

    test('saveSubtasks auto-finish executes in one single storage write and records Undo cleanly', () async {
      const config = WebDavConfig(
        storageMode: StorageMode.local,
        localFilePath: 'tasks.tdf',
        language: AppLanguage.english,
        timeZoneMode: AppTimeZoneMode.manual,
        manualTimeZoneOffsetMinutes: 0,
      );
      final repeatingTask = TaskItem(
        id: 'rsub000001',
        title: 'Weekly Checklist',
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.weeks),
        subtasksAutoFinish: true,
        subtasks: const <SubtaskItem>[
          SubtaskItem(title: 'Step A', isCompleted: false),
        ],
        createdAt: fixedNow,
        modifiedAt: fixedNow,
      );
      final board = buildBaseBoard(
        tasks: <TaskItem>[...buildBaseBoard().allTasks, repeatingTask],
      );
      final initialTdf = const TdfService().serialize(board);
      final localRepo = _CountingLocalFileRepository(
        config: config,
        initialTdf: initialTdf,
      );
      final container = await createRealPersistenceContainer(
        config: config,
        localRepo: localRepo,
      );
      final shell = container.read(shellProvider.notifier);
      final actions = container.read(boardActionsProvider.notifier);

      // Non-repeating auto-finish in ONE write + clean Undo.
      localRepo.saveCount = 0;
      shell.openInlineEdit(
        InlineEditTarget.task('taskA00001', TaskSectionKind.subtasks),
      );
      final result = await actions.saveSubtasks(
        'taskA00001',
        const <SubtaskItem>[
          SubtaskItem(title: 'Final step', isCompleted: true),
        ],
        autoFinish: true,
      );
      expect(result, isA<ActionSucceeded>());
      expect(
        localRepo.saveCount,
        equals(1),
        reason: 'saveSubtasks auto-finish must commit in one atomic write',
      );
      expect(container.read(shellProvider).expandedEntity, isNull);
      final completedTask = container
          .read(taskNotifierProvider)
          .requireValue
          .findTask('taskA00001');
      expect(completedTask?.isCompleted, isTrue);
      expect(completedTask?.completions, equals(1));
      expect(completedTask?.subtasks.single.isCompleted, isTrue);
      expect(container.read(taskUndoStateProvider).canUndo, isTrue);
      expect(container.read(floatingNoticeProvider)?.hasUndoAction, isTrue);

      final undone = await container
          .read(floatingNoticeProvider.notifier)
          .undoLatest();
      expect(undone, isTrue);
      final restoredAfterUndo = container
          .read(taskNotifierProvider)
          .requireValue
          .findTask('taskA00001');
      expect(restoredAfterUndo?.isCompleted, isFalse);
      expect(restoredAfterUndo?.completedAt, isNull);
      expect(restoredAfterUndo?.subtasks, isEmpty);
      expect(restoredAfterUndo?.subtasksAutoFinish, isFalse);
      expect(
        restoredAfterUndo?.completions,
        equals(1),
        reason: 'TDF completions counter remains monotonic after Undo',
      );

      // Repeating task auto-finish in ONE write with exactly +1 completion.
      localRepo.saveCount = 0;
      shell.openInlineEdit(
        InlineEditTarget.task('rsub000001', TaskSectionKind.subtasks),
      );
      final repeatResult = await actions.saveSubtasks(
        'rsub000001',
        const <SubtaskItem>[SubtaskItem(title: 'Step A', isCompleted: true)],
        autoFinish: true,
      );
      expect(repeatResult, isA<ActionSucceeded>());
      expect(
        localRepo.saveCount,
        equals(1),
        reason: 'Repeating saveSubtasks auto-finish must commit in one write',
      );
      expect(
        (repeatResult as ActionSucceeded).noticeMessage,
        equals(localizations.taskCompletedRepeatNotice('Weekly Checklist')),
      );
      final rescheduled = container
          .read(taskNotifierProvider)
          .requireValue
          .findTask('rsub000001');
      expect(rescheduled?.isCompleted, isFalse);
      expect(
        rescheduled?.completions,
        equals(1),
        reason: 'Repeating auto-finish must complete exactly once, not twice',
      );
      expect(rescheduled?.subtasks.single.isCompleted, isFalse);
    });
  });

  group('BoardActionsNotifier extreme boundaries & secondary edge cases', () {
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
      final shell = container.read(shellProvider.notifier);
      final actions = container.read(boardActionsProvider.notifier);

      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'rsub000001'),
      );
      final toggleResult = await actions.toggleSubtask('rsub000001', 1);
      expect(toggleResult, isA<ActionSucceeded>());
      expect(
        (toggleResult as ActionSucceeded).noticeMessage,
        equals(localizations.taskCompletedRepeatNotice('Weekly Checklist')),
      );
      expect(container.read(shellProvider).expandedEntity, isNull);
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

      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'rsub000001'),
      );
      final saveResult = await actions.saveSubtasks(
        'rsub000001',
        const <SubtaskItem>[SubtaskItem(title: 'Step A', isCompleted: true)],
        autoFinish: true,
      );
      expect(saveResult, isA<ActionSucceeded>());
      expect(
        (saveResult as ActionSucceeded).noticeMessage,
        equals(localizations.taskCompletedRepeatNotice('Weekly Checklist')),
      );
      expect(container.read(shellProvider).expandedEntity, isNull);
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
      final actions = container.read(boardActionsProvider.notifier);

      final exactSubtasks = await actions.saveSubtasks(
        'tsk0000000',
        <SubtaskItem>[
          for (var i = 0; i < maxTdfStmtsPerBlock; i++)
            SubtaskItem(title: 'S$i'),
        ],
        autoFinish: false,
      );
      expect(
        exactSubtasks,
        isA<ActionSucceeded>(),
        reason: '1024 subtasks must satisfy maxTdfStmtsPerBlock',
      );

      final validLocationIds = <String>[
        for (var i = 0; i < maxTdfLocationRefsPerEntity; i++) locations[i].id,
      ];
      expect(
        await actions.saveConditions(
          'tsk0000000',
          ConditionDraft(
            locationMode: ConditionDimensionMode.custom,
            locationIds: validLocationIds,
          ),
        ),
        isA<ActionSucceeded>(),
        reason: '63 location refs must satisfy maxTdfLocationRefsPerEntity',
      );
      expect(
        await actions.saveConditions(
          'tsk0000000',
          ConditionDraft(
            locationMode: ConditionDimensionMode.custom,
            locationIds: <String>[...validLocationIds, locations.last.id],
          ),
        ),
        isA<ActionValidationFailed>(),
        reason: '64 location refs must exceed maxTdfLocationRefsPerEntity',
      );

      final overflowWindows = <TimeWindowDraft>[
        for (var i = 0; i <= maxTdfConditionRulesPerEntity; i++)
          const TimeWindowDraft(start: '08:00', end: '09:00'),
      ];
      expect(
        await actions.saveConditions(
          'tsk0000000',
          ConditionDraft(
            timeMode: ConditionDimensionMode.custom,
            timeWindows: overflowWindows,
          ),
        ),
        isA<ActionValidationFailed>(),
        reason: '513 condition rules must exceed maxTdfConditionRulesPerEntity',
      );

      final sixtyFourIds = <String>[
        for (var i = 1; i <= maxTdfArgsPerStmt; i++) manyTasks[i].id,
      ];
      expect(
        await actions.savePrerequisites('tsk0000000', <String>[
          ...sixtyFourIds,
          manyTasks[maxTdfArgsPerStmt + 1].id,
        ]),
        isA<ActionValidationFailed>(),
        reason: '65 prerequisites must exceed maxTdfArgsPerStmt',
      );
      expect(
        await actions.savePrerequisites('tsk0000000', sixtyFourIds),
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
      final shell = container.read(shellProvider.notifier);
      final actions = container.read(boardActionsProvider.notifier);

      expect(
        await actions.updateHistoryEntry(
          'mixd000001',
          oldTimestampUtcIso: preciseTimestamp.toIso8601String(),
          oldText: 'Initial entry',
          rawNewText: 'Initial entry',
          rawNewTimestamp: '2026-11-09 14:30:42',
        ),
        isA<ActionSucceeded>(),
      );
      expect(
        await actions.updateHistoryEntry(
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

      expect(
        await actions.saveDue(
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

      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'mixd000001'),
      );
      final stripGlobalResult = await actions.toggleLabel(
        'mixd000001',
        'work000001',
      );
      expect(stripGlobalResult, isA<ActionSucceeded>());
      expect(
        (stripGlobalResult as ActionSucceeded).noticeMessage,
        equals(localizations.noticeTaskMovedToScopedQueue('Private')),
      );
      expect(container.read(shellProvider).expandedEntity, isNull);

      final deLocalizations = lookupAppLocalizations(const Locale('de'));
      final deDuplicate = await actions.quickAddTask(
        rawTitle: 'mixed labels task',
        placement: QuickAddMode.standard,
        labelIds: const <String>[],
        locale: const Locale('de'),
      );
      expect(deDuplicate, isA<ActionValidationFailed>());
      expect(
        (deDuplicate as ActionValidationFailed).message,
        equals(deLocalizations.taskNameErrorDuplicate),
      );
    });
  });
}
