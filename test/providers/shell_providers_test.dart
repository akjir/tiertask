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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/settings_codec.dart';
import 'package:tiertask/models/storage_file_read_status.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/floating_notice_providers.dart';
import 'package:tiertask/providers/shell_providers.dart';
import 'package:tiertask/providers/sync_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/tdf_service.dart';

import '../ui/test_helpers.dart';

class _ControllableTaskNotifier extends FakeTaskNotifier {
  _ControllableTaskNotifier([super.initialBoard]);

  void emitBoard(TaskBoard board) {
    state = AsyncData<TaskBoard>(board);
  }

  void emitLoading() {
    state = const AsyncLoading<TaskBoard>();
  }
}

void main() {
  const sampleTdf = '''tdf 0.8.0

queue {
  modified 2026-11-01 08:00:00
  task taskA00001
  task taskB00002
}

label work000001 {
  name "Work"
  color "#2196F3"
  modified 2026-11-01 08:00:00
}

location home000001 {
  name "Home"
  coordinates 48.137154 11.576124
  radius 100
  modified 2026-11-01 08:00:00
}

task taskA00001 {
  name "Alpha Task"
  created 2026-11-01 08:00:00
  modified 2026-11-01 08:00:00
  labels work000001
}

task taskB00002 {
  name "Beta Task"
  created 2026-11-01 08:05:00
  modified 2026-11-01 08:05:00
}
''';

  ProviderContainer createContainer({
    WebDavConfig config = const WebDavConfig(language: AppLanguage.english),
    String initialTdf = sampleTdf,
    SettingsRecoveryNotice? recoveryNotice,
  }) {
    final settingsRepository = recoveryNotice != null
        ? InMemorySettingsRepository.withRecoveryNotice(
            initialConfig: config,
            recoveryNotice: recoveryNotice,
          )
        : InMemorySettingsRepository(config);
    final localRepository = FakeLocalFileRepository(
      config: config,
      initialTdf: initialTdf,
    );
    return ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settingsRepository),
        localFileRepositoryProvider.overrideWith((ref) => localRepository),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1, 12)),
      ],
    );
  }

  group('ShellNotifier high-frequency query isolation', () {
    test('updating searchQueryProvider, labelPickerQueryProvider, sidebarLabelsFilterQueryProvider, or sidebarLocationsFilterQueryProvider does not trigger shellProvider rebuilds', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      var shellNotificationCount = 0;
      final shellSubscription = container.listen(
        shellProvider,
        (_, _) => shellNotificationCount++,
      );
      addTearDown(shellSubscription.close);

      container.read(searchQueryProvider.notifier).setQuery('Alpha');
      container.read(searchQueryProvider.notifier).setQuery('Alpha Beta');
      container.read(labelPickerQueryProvider.notifier).setQuery('Work');
      container.read(sidebarLabelsFilterQueryProvider.notifier).setQuery('Wor');
      container
          .read(sidebarLocationsFilterQueryProvider.notifier)
          .setQuery('Hom');

      expect(
        shellNotificationCount,
        equals(0),
        reason: 'High-frequency text query updates must remain decoupled from shellProvider',
      );
      expect(container.read(searchQueryProvider), equals('Alpha Beta'));
      expect(container.read(labelPickerQueryProvider), equals('Work'));
      expect(container.read(sidebarLabelsFilterQueryProvider), equals('Wor'));
      expect(
        container.read(sidebarLocationsFilterQueryProvider),
        equals('Hom'),
      );

      container.read(searchQueryProvider.notifier).clear();
      container.read(labelPickerQueryProvider.notifier).clear();
      container.read(sidebarLabelsFilterQueryProvider.notifier).clear();
      container.read(sidebarLocationsFilterQueryProvider.notifier).clear();
      expect(shellNotificationCount, equals(0));
    });
  });

  group('ShellNotifier Escape and Android system Back unwind', () {
    test('unwinds all 9 desktop Escape layers in strict priority order and reaches allowSystemPop', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      final shell = container.read(shellProvider.notifier);
      const target = EntityRef(kind: EntityKind.task, id: 'taskA00001');

      // Stack Layers 0..6 (opening a draft intentionally clears expanded/edit state per U-CARD-006).
      shell.openSearch();
      container.read(searchQueryProvider.notifier).setQuery('Alpha');
      shell.openDraft(
        EntityDraftKind.task,
        seedTitle: 'Draft Task',
        seedPlacement: QuickAddMode.priority,
        seedLabelIds: const <String>['work000001'],
      );
      shell.setLabelPickerOpen(true);
      container.read(labelPickerQueryProvider.notifier).setQuery('Urg');
      shell.toggleSidebarLabelsFilter();
      container.read(sidebarLabelsFilterQueryProvider.notifier).setQuery('Wo');
      shell.setCompactDrawerOpen(true);

      // 0. Compact drawer closes first when open.
      expect(
        shell.handleEscape(),
        equals(ShellDismissOutcome.handled),
        reason: 'Compact drawer must dismiss before inner layers',
      );
      expect(container.read(shellProvider).compactDrawerOpen, isFalse);

      // Re-open sidebar filter to verify Layer 1 -> Layer 2 priority cleanly.
      shell.toggleSidebarLabelsFilter();
      container.read(sidebarLabelsFilterQueryProvider.notifier).setQuery('Wo');

      // 1. Label picker search query clears before sidebar filter.
      expect(shell.handleEscape(), equals(ShellDismissOutcome.handled));
      expect(
        container.read(labelPickerQueryProvider),
        isEmpty,
        reason: 'Layer 1 must clear label picker search query',
      );
      expect(container.read(shellProvider).labelPickerOpen, isTrue);

      // 2. Sidebar filter closes and clears query.
      expect(shell.handleEscape(), equals(ShellDismissOutcome.handled));
      expect(
        container.read(shellProvider).sidebarLabelsFilterOpen,
        isFalse,
        reason: 'Layer 2 must close sidebar filter',
      );
      expect(container.read(sidebarLabelsFilterQueryProvider), isEmpty);

      // 4. Open label picker closes (Layer 3 is modal route handled by Navigator).
      expect(shell.handleEscape(), equals(ShellDismissOutcome.handled));
      expect(
        container.read(shellProvider).labelPickerOpen,
        isFalse,
        reason: 'Layer 4 must close open label picker',
      );

      // 5. Open uncommitted entity draft card cancels and clears seeds.
      expect(shell.handleEscape(), equals(ShellDismissOutcome.handled));
      var shellState = container.read(shellProvider);
      expect(
        shellState.activeDraft,
        isNull,
        reason: 'Layer 5 must cancel active draft card',
      );
      expect(shellState.draftSeedTitle, isEmpty);
      expect(shellState.draftSeedPlacement, equals(QuickAddMode.standard));
      expect(shellState.draftSeedLabelIds, isEmpty);

      // 6. Global Search closes and clears searchQueryProvider.
      expect(shell.handleEscape(), equals(ShellDismissOutcome.handled));
      expect(
        container.read(shellProvider).searchOpen,
        isFalse,
        reason: 'Layer 6 must close Global Search',
      );
      expect(container.read(searchQueryProvider), isEmpty);

      // Stack Layers 7 -> 9 (inline edit -> expanded card) and Layer 8 -> 9 (delete confirm -> expanded card).
      shell.expandEntity(target);
      shell.openInlineEdit(
        InlineEditTarget.task(target.id, TaskSectionKind.note),
      );

      // 7. Active inline section edit cancels.
      expect(shell.handleEscape(), equals(ShellDismissOutcome.handled));
      expect(
        container.read(shellProvider).activeInlineEdit,
        isNull,
        reason: 'Layer 7 must cancel active inline edit',
      );
      expect(container.read(shellProvider).expandedEntity, equals(target));

      // 8. Active inline delete confirmation cancels before collapsing card.
      shell.requestInlineDelete(target);
      expect(shell.handleEscape(), equals(ShellDismissOutcome.handled));
      expect(
        container.read(shellProvider).activeDeleteConfirm,
        isNull,
        reason: 'Layer 8 must cancel inline delete confirm',
      );
      expect(container.read(shellProvider).expandedEntity, equals(target));

      // 9. Expanded entity card collapses.
      expect(shell.handleEscape(), equals(ShellDismissOutcome.handled));
      expect(
        container.read(shellProvider).expandedEntity,
        isNull,
        reason: 'Layer 9 must collapse expanded entity card',
      );

      // Clean root returns allowSystemPop.
      expect(
        shell.handleEscape(),
        equals(ShellDismissOutcome.allowSystemPop),
        reason: 'Clean tasks root must return allowSystemPop',
      );
    });

    test('handleSystemBack unwinds sidebar filter, returnContext, secondary views, and permits OS exit only on clean tasks root', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      final shell = container.read(shellProvider.notifier);
      shell.selectTier(TaskTier.ready);
      shell.selectLabelFilter('work000001');
      shell.openSearch();
      container.read(searchQueryProvider.notifier).setQuery('Alpha');
      shell.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'taskA00001'),
      );

      // Open label in manager with returnContext preserved.
      shell.openEntityInManager(
        const EntityRef(kind: EntityKind.label, id: 'work000001'),
        preserveReturnContext: true,
      );
      var state = container.read(shellProvider);
      expect(state.view, equals(ShellView.labels));
      expect(state.returnContext, isNotNull);
      expect(state.returnContext?.tier, equals(TaskTier.ready));
      expect(state.returnContext?.searchOpen, isTrue);
      expect(state.returnContext?.searchQuery, equals('Alpha'));
      expect(
        state.expandedEntity,
        equals(const EntityRef(kind: EntityKind.label, id: 'work000001')),
      );

      // Open persistent sidebar filter (tablet Layer 2).
      shell.toggleSidebarLocationsFilter();
      expect(
        shell.handleSystemBack(),
        equals(ShellDismissOutcome.handled),
        reason: 'Back must close persistent sidebar filter first',
      );
      expect(container.read(shellProvider).sidebarLocationsFilterOpen, isFalse);

      // Next Back collapses expanded label card.
      expect(shell.handleSystemBack(), equals(ShellDismissOutcome.handled));
      expect(container.read(shellProvider).expandedEntity, isNull);

      // Next Back restores returnContext back to Search + Ready + Work + expanded taskA + searchQueryProvider.
      expect(shell.handleSystemBack(), equals(ShellDismissOutcome.handled));
      state = container.read(shellProvider);
      expect(state.view, equals(ShellView.tasks));
      expect(state.activeTier, equals(TaskTier.ready));
      expect(state.activeLabelId, equals('work000001'));
      expect(state.searchOpen, isTrue);
      expect(container.read(searchQueryProvider), equals('Alpha'));
      expect(
        state.expandedEntity,
        equals(const EntityRef(kind: EntityKind.task, id: 'taskA00001')),
      );
      expect(state.returnContext, isNull);

      // Unwind search and expanded task.
      expect(shell.handleSystemBack(), equals(ShellDismissOutcome.handled));
      expect(shell.handleSystemBack(), equals(ShellDismissOutcome.handled));
      expect(
        shell.handleSystemBack(),
        equals(ShellDismissOutcome.allowSystemPop),
        reason: 'Clean tasks view must permit Android system pop',
      );

      // Direct secondary view without returnContext returns to tasks.
      shell.openView(ShellView.settings);
      expect(container.read(shellProvider).view, equals(ShellView.settings));
      expect(shell.handleSystemBack(), equals(ShellDismissOutcome.handled));
      expect(container.read(shellProvider).view, equals(ShellView.tasks));
      expect(
        shell.handleSystemBack(),
        equals(ShellDismissOutcome.allowSystemPop),
      );
    });
  });

  group('ShellNotifier board reconciliation and AsyncLoading guards', () {
    test('preserves active inline edit on benign external update, auto-closes on external deletion or completion, suppresses local mutations, and clears stale activeLabelId', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final initialBoard = await container.read(taskNotifierProvider.future);
      final shellSub = container.listen(shellProvider, (_, _) {});
      final noticeSub = container.listen(floatingNoticeProvider, (_, _) {});
      addTearDown(shellSub.close);
      addTearDown(noticeSub.close);

      final shell = container.read(shellProvider.notifier);
      const taskA = EntityRef(kind: EntityKind.task, id: 'taskA00001');
      shell.selectLabelFilter('work000001');
      shell.expandEntity(taskA);
      shell.openInlineEdit(
        InlineEditTarget.task(taskA.id, TaskSectionKind.note),
      );

      // Benign external board refresh keeps expanded card and inline edit intact.
      await container
          .read(taskNotifierProvider.notifier)
          .updateTask('taskB00002', note: 'External edit');
      expect(container.read(shellProvider).expandedEntity, equals(taskA));
      expect(
        container.read(shellProvider).activeInlineEdit,
        equals(InlineEditTarget.task(taskA.id, TaskSectionKind.note)),
      );
      expect(
        container.read(floatingNoticeProvider),
        isNull,
        reason: 'Benign refresh must not emit external removal notice',
      );

      // External completion of taskA while editing Note closes inline edit, keeps card expanded, and emits warning notice.
      final localRepository = container.read(localFileRepositoryProvider);
      expect(localRepository, isA<FakeLocalFileRepository>());
      if (localRepository case final FakeLocalFileRepository fakeLocal) {
        final currentBoard = container.read(taskNotifierProvider).requireValue;
        final externallyCompletedBoard = currentBoard.completeTask(
          'taskA00001',
          currentDate: DateTime.utc(2026, 11, 1, 12, 5),
        );
        fakeLocal.initialTdf = const TdfService().serialize(
          externallyCompletedBoard,
        );
      }
      final reconciled = await container
          .read(taskNotifierProvider.notifier)
          .reconcileExternalLocalChanges();
      expect(reconciled, isTrue);
      expect(
        container.read(shellProvider).expandedEntity,
        equals(taskA),
        reason: 'External completion keeps card expanded in read-only mode',
      );
      expect(
        container.read(shellProvider).activeInlineEdit,
        isNull,
        reason:
            'External completion must close non-History inline section edit',
      );
      expect(
        container.read(floatingNoticeProvider)?.tone,
        equals(FloatingNoticeTone.warning),
      );
      expect(
        container.read(floatingNoticeProvider)?.message,
        contains('completed by an external update'),
      );

      // External deletion of active filter label clears activeLabelId.
      await container
          .read(taskNotifierProvider.notifier)
          .deleteLabel('work000001');
      expect(
        container.read(shellProvider).activeLabelId,
        isNull,
        reason: 'External label deletion must clear stale activeLabelId',
      );

      // Local mutation suppression prevents spurious external removal notice.
      container.read(floatingNoticeProvider.notifier).dismiss();
      const taskB = EntityRef(kind: EntityKind.task, id: 'taskB00002');
      shell.expandEntity(taskB);
      await shell.runLocalEntityMutation(taskB, () async {
        await container
            .read(taskNotifierProvider.notifier)
            .deleteTask(taskB.id);
        shell.collapseEntity();
      });
      expect(
        container.read(floatingNoticeProvider)?.message,
        isNot(contains('external update')),
        reason: 'Suppressed local delete must show Undo notice instead of external removal notice',
      );
      expect(container.read(floatingNoticeProvider)?.undoSequence, isNotNull);

      expect(initialBoard.allTasks, hasLength(2));
    });

    test('_reconcileBoardUpdate across AsyncLoading does not falsely fire taskCompletedExternallyNotice for already-completed tasks, but does fire when an active task completes externally', () async {
      final parsedInitial = const TdfService().parse(sampleTdf);
      final completedTimestamp = DateTime.utc(2026, 11, 1, 12, 5);
      final boardWithCompletedA = parsedInitial.completeTask(
        'taskA00001',
        currentDate: completedTimestamp,
      );
      final controllableTasks = _ControllableTaskNotifier(boardWithCompletedA);

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const WebDavConfig(language: AppLanguage.english),
            ),
          ),
          taskNotifierProvider.overrideWith(() => controllableTasks),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);
      await container.read(taskNotifierProvider.future);

      final shellSub = container.listen(shellProvider, (_, _) {});
      final noticeSub = container.listen(floatingNoticeProvider, (_, _) {});
      addTearDown(shellSub.close);
      addTearDown(noticeSub.close);

      final shell = container.read(shellProvider.notifier);
      const taskA = EntityRef(kind: EntityKind.task, id: 'taskA00001');
      const taskB = EntityRef(kind: EntityKind.task, id: 'taskB00002');

      // Task A is already completed; open an inline edit on Task A and bounce through AsyncLoading.
      shell.expandEntity(taskA);
      shell.openInlineEdit(
        InlineEditTarget.task(taskA.id, TaskSectionKind.note),
      );
      controllableTasks.emitLoading();
      controllableTasks.emitBoard(boardWithCompletedA);

      expect(
        container.read(shellProvider).activeInlineEdit,
        equals(InlineEditTarget.task(taskA.id, TaskSectionKind.note)),
        reason: 'Already-completed task reloading across AsyncLoading must not falsely close inline edit',
      );
      expect(
        container.read(floatingNoticeProvider),
        isNull,
        reason: 'Already-completed task reloading across AsyncLoading must not fire taskCompletedExternallyNotice',
      );

      // Task B is active; open inline edit on Task B, bounce through AsyncLoading, and emit externally completed Task B.
      shell.expandEntity(taskB);
      shell.openInlineEdit(
        InlineEditTarget.task(taskB.id, TaskSectionKind.note),
      );
      final boardWithCompletedB = boardWithCompletedA.completeTask(
        'taskB00002',
        currentDate: DateTime.utc(2026, 11, 1, 12, 10),
      );
      controllableTasks.emitLoading();
      controllableTasks.emitBoard(boardWithCompletedB);

      expect(
        container.read(shellProvider).expandedEntity,
        equals(taskB),
        reason: 'External completion keeps card expanded',
      );
      expect(
        container.read(shellProvider).activeInlineEdit,
        isNull,
        reason: 'Active task externally completed across AsyncLoading must close inline edit',
      );
      expect(
        container.read(floatingNoticeProvider)?.tone,
        equals(FloatingNoticeTone.warning),
      );
      expect(
        container.read(floatingNoticeProvider)?.message,
        contains('completed by an external update'),
      );

      // External removal of an expanded entity collapses card and emits entityRemovedExternallyNotice.
      container.read(floatingNoticeProvider.notifier).dismiss();
      controllableTasks.emitBoard(TaskBoard.empty());
      expect(container.read(shellProvider).expandedEntity, isNull);
      expect(
        container.read(floatingNoticeProvider)?.tone,
        equals(FloatingNoticeTone.warning),
      );
      expect(
        container.read(floatingNoticeProvider)?.message,
        contains('removed by an external update'),
      );
    });

    test('preserves history inline edit on external completion', () async {
      final parsedInitial = const TdfService().parse(sampleTdf);
      final controllableTasks = _ControllableTaskNotifier(parsedInitial);
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const WebDavConfig(language: AppLanguage.english),
            ),
          ),
          taskNotifierProvider.overrideWith(() => controllableTasks),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);
      await container.read(taskNotifierProvider.future);

      final shellSub = container.listen(shellProvider, (_, _) {});
      final noticeSub = container.listen(floatingNoticeProvider, (_, _) {});
      addTearDown(shellSub.close);
      addTearDown(noticeSub.close);

      final shell = container.read(shellProvider.notifier);
      const taskA = EntityRef(kind: EntityKind.task, id: 'taskA00001');
      const historyTarget = InlineEditTarget(
        entity: taskA,
        sectionKey: 'history',
      );
      shell.openInlineEdit(historyTarget);

      controllableTasks.emitBoard(
        parsedInitial.completeTask(
          'taskA00001',
          currentDate: DateTime.utc(2026, 11, 1, 12, 15),
        ),
      );
      expect(
        container.read(shellProvider).activeInlineEdit,
        equals(historyTarget),
      );
      expect(container.read(floatingNoticeProvider), isNull);
    });
  });

  group('ShellNotifier workspace switches, navigation, and banners', () {
    test('resets shell state and all text queries on workspace switch and exposes startup recovery notice persistently', () async {
      final container = createContainer(
        recoveryNotice: const SettingsRecoveryNotice(
          kind: SettingsRecoveryKind.recoveredFromBackup,
          quarantinedFilePath: '/tmp/settings.json.corrupt',
        ),
      );
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      final shellSub = container.listen(shellProvider, (_, _) {});
      final noticeSub = container.listen(floatingNoticeProvider, (_, _) {});
      addTearDown(shellSub.close);
      addTearDown(noticeSub.close);

      container
          .read(floatingNoticeProvider.notifier)
          .showStartupRecoveryNoticeIfPending();
      final recovery = container.read(floatingNoticeProvider);
      expect(recovery, isNotNull);
      expect(recovery?.persistent, isTrue);
      expect(recovery?.tone, equals(FloatingNoticeTone.warning));

      final shell = container.read(shellProvider.notifier);
      shell.openView(ShellView.labels);
      shell.openDraft(EntityDraftKind.label);
      container.read(searchQueryProvider.notifier).setQuery('Alpha');
      container.read(labelPickerQueryProvider.notifier).setQuery('Work');
      container.read(sidebarLabelsFilterQueryProvider.notifier).setQuery('Wo');
      container
          .read(sidebarLocationsFilterQueryProvider.notifier)
          .setQuery('Ho');

      await container
          .read(activeWorkspaceProvider.notifier)
          .createWorkspace(
            'Personal',
            config: const WebDavConfig(
              localFilePath: 'personal.tdf',
              filePath: 'personal.tdf',
            ),
            activate: true,
          );
      expect(container.read(shellProvider).view, equals(ShellView.tasks));
      expect(container.read(shellProvider).activeDraft, isNull);
      expect(container.read(searchQueryProvider), isEmpty);
      expect(container.read(labelPickerQueryProvider), isEmpty);
      expect(container.read(sidebarLabelsFilterQueryProvider), isEmpty);
      expect(container.read(sidebarLocationsFilterQueryProvider), isEmpty);
    });

    test('supports stepTier clamping, sidebar collapse/filter toggles, label filter collapse rule, compact composer, reveal clear, and banner re-arming', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      final shellSub = container.listen(shellProvider, (_, _) {});
      addTearDown(shellSub.close);
      final shell = container.read(shellProvider.notifier);

      // stepTier clamps 0..5 and ignores calls during search or secondary views.
      shell.stepTier(-1);
      expect(container.read(shellProvider).activeTier, equals(TaskTier.focus));
      shell.stepTier(1);
      expect(container.read(shellProvider).activeTier, equals(TaskTier.ready));
      shell.stepTier(10);
      expect(
        container.read(shellProvider).activeTier,
        equals(TaskTier.completed),
      );
      shell.openSearch();
      shell.stepTier(-1);
      expect(
        container.read(shellProvider).activeTier,
        equals(TaskTier.completed),
      );
      shell.closeSearch();

      // Sidebar collapse clears open filter and query; opening filter auto-expands section.
      shell.toggleSidebarLabelsCollapsed();
      expect(container.read(shellProvider).sidebarLabelsCollapsed, isTrue);
      shell.toggleSidebarLabelsFilter();
      expect(container.read(shellProvider).sidebarLabelsCollapsed, isFalse);
      expect(container.read(shellProvider).sidebarLabelsFilterOpen, isTrue);
      container.read(sidebarLabelsFilterQueryProvider.notifier).setQuery('Wrk');
      shell.toggleSidebarLabelsCollapsed();
      expect(container.read(shellProvider).sidebarLabelsCollapsed, isTrue);
      expect(container.read(shellProvider).sidebarLabelsFilterOpen, isFalse);
      expect(container.read(sidebarLabelsFilterQueryProvider), isEmpty);

      shell.toggleSidebarLocationsCollapsed();
      expect(container.read(shellProvider).sidebarLocationsCollapsed, isTrue);
      shell.toggleSidebarLocationsFilter();
      expect(container.read(shellProvider).sidebarLocationsCollapsed, isFalse);
      expect(container.read(shellProvider).sidebarLocationsFilterOpen, isTrue);
      container
          .read(sidebarLocationsFilterQueryProvider.notifier)
          .setQuery('Hom');
      shell.toggleSidebarLocationsFilter();
      expect(container.read(shellProvider).sidebarLocationsFilterOpen, isFalse);
      expect(container.read(sidebarLocationsFilterQueryProvider), isEmpty);

      // toggleExpandEntity toggles expansion and clearRevealRequest clears revealEntityRequest.
      const taskA = EntityRef(kind: EntityKind.task, id: 'taskA00001');
      shell.toggleExpandEntity(taskA);
      expect(container.read(shellProvider).expandedEntity, equals(taskA));
      expect(container.read(shellProvider).revealEntityRequest, equals(taskA));
      shell.clearRevealRequest();
      expect(container.read(shellProvider).revealEntityRequest, isNull);
      shell.toggleExpandEntity(taskA);
      expect(container.read(shellProvider).expandedEntity, isNull);

      // Clearing activeLabelId collapses expanded task outside search, but keeps it in search.
      shell.selectLabelFilter('work000001');
      shell.expandEntity(taskA);
      shell.selectLabelFilter(null);
      expect(container.read(shellProvider).expandedEntity, isNull);

      shell.openSearch();
      shell.selectLabelFilter('work000001');
      shell.expandEntity(taskA);
      shell.selectLabelFilter(null);
      expect(container.read(shellProvider).expandedEntity, equals(taskA));

      // Compact composer open toggle.
      shell.setCompactComposerOpen(true);
      expect(container.read(shellProvider).compactComposerOpen, isTrue);
      shell.setCompactComposerOpen(false);
      expect(container.read(shellProvider).compactComposerOpen, isFalse);

      // Sync error & file-read banner dismissal re-arms when new error/report arrives.
      shell.dismissSyncErrorBanner();
      shell.dismissFileReadBanner();
      expect(container.read(shellProvider).syncErrorBannerDismissed, isTrue);
      expect(container.read(shellProvider).fileReadBannerDismissed, isTrue);

      const readReport = StorageFileReadReport(
        local: StorageFileReadStatus.unreadable(
          StorageFileTarget.local,
          detail: 'Corrupted line',
          line: 2,
        ),
      );
      container
          .read(syncStateProvider.notifier)
          .setError('Read failed', fileReadReport: readReport);
      expect(container.read(shellProvider).syncErrorBannerDismissed, isFalse);
      expect(container.read(shellProvider).fileReadBannerDismissed, isFalse);
    });
  });

  group('resolveSyncStatusKind exhaustive branches', () {
    test('maps syncing, conflict, error, localOnly, and synced with strict precedence', () {
      const outcome = TdfSyncOutcomeException(
        kind: TdfSyncOutcomeKind.deletionConflict,
        message: 'conflict',
        conflictedTaskIds: <String>['taskA00001'],
      );
      const failingReport = StorageFileReadReport(
        local: StorageFileReadStatus.unreadable(
          StorageFileTarget.local,
          detail: 'bad syntax',
        ),
      );
      const okReport = StorageFileReadReport(
        local: StorageFileReadStatus.readable(StorageFileTarget.local),
      );

      // 1. syncing takes top precedence over conflict, error, and local mode.
      expect(
        resolveSyncStatusKind(
          storageMode: StorageMode.local,
          syncState: const SyncState(
            isSyncing: true,
            hasOpenConflict: true,
            errorMessage: 'err',
          ),
        ),
        equals(SyncStatusKind.syncing),
      );

      // 2. conflict via hasOpenConflict or syncOutcome takes precedence over error and local mode.
      expect(
        resolveSyncStatusKind(
          storageMode: StorageMode.local,
          syncState: const SyncState(
            hasOpenConflict: true,
            errorMessage: 'err',
          ),
        ),
        equals(SyncStatusKind.conflict),
      );
      expect(
        resolveSyncStatusKind(
          storageMode: StorageMode.both,
          syncState: const SyncState(syncOutcome: outcome),
        ),
        equals(SyncStatusKind.conflict),
      );

      // 3. error via errorMessage or failing fileReadReport takes precedence over localOnly/synced.
      expect(
        resolveSyncStatusKind(
          storageMode: StorageMode.local,
          syncState: const SyncState(errorMessage: 'Network timeout'),
        ),
        equals(SyncStatusKind.error),
      );
      expect(
        resolveSyncStatusKind(
          storageMode: StorageMode.both,
          syncState: const SyncState(fileReadReport: failingReport),
        ),
        equals(SyncStatusKind.error),
      );

      // 4. localOnly when storageMode is local and no error/conflict/syncing is active.
      expect(
        resolveSyncStatusKind(
          storageMode: StorageMode.local,
          syncState: const SyncState(fileReadReport: okReport),
        ),
        equals(SyncStatusKind.localOnly),
      );

      // 5. synced when WebDAV or dual storage is healthy.
      for (final mode in const <StorageMode>[
        StorageMode.webdav,
        StorageMode.both,
      ]) {
        expect(
          resolveSyncStatusKind(
            storageMode: mode,
            syncState: const SyncState(fileReadReport: okReport),
          ),
          equals(SyncStatusKind.synced),
          reason: 'Healthy $mode storage must resolve to SyncStatusKind.synced',
        );
      }
    });
  });

  group('Shell value types equality and hashCode', () {
    test('supports value equality across ActionResult, EntityRef, InlineEditTarget, ReturnContext, and ShellState', () {
      const okA = ActionSucceeded(entityId: 'id1', noticeMessage: 'Done');
      const okB = ActionSucceeded(entityId: 'id1', noticeMessage: 'Done');
      expect(okA, equals(okB));
      expect(okA.hashCode, equals(okB.hashCode));

      const persistA = ActionPersistFailed(message: 'Failed');
      const persistB = ActionPersistFailed(message: 'Failed');
      expect(persistA, equals(persistB));
      expect(persistA.hashCode, equals(persistB.hashCode));

      final validationA = ActionValidationFailed(
        message: 'Invalid',
        fieldErrors: const <String, String>{'name': 'Required'},
      );
      final validationB = ActionValidationFailed(
        message: 'Invalid',
        fieldErrors: const <String, String>{'name': 'Required'},
      );
      expect(validationA, equals(validationB));
      expect(validationA.hashCode, equals(validationB.hashCode));

      final labelEdit = InlineEditTarget.label(
        'work000001',
        LabelSectionKind.color,
      );
      final locationEdit = InlineEditTarget.location(
        'home000001',
        LocationSectionKind.coordinates,
      );
      expect(labelEdit, isNot(equals(locationEdit)));
      expect(
        labelEdit,
        equals(InlineEditTarget.label('work000001', LabelSectionKind.color)),
      );
      expect(
        labelEdit.hashCode,
        equals(
          InlineEditTarget.label('work000001', LabelSectionKind.color).hashCode,
        ),
      );

      const contextA = ReturnContext(
        view: ShellView.tasks,
        tier: TaskTier.ready,
        labelId: 'work000001',
        searchOpen: true,
        searchQuery: 'Alpha',
        expandedEntity: EntityRef(kind: EntityKind.task, id: 'taskA00001'),
      );
      const contextB = ReturnContext(
        view: ShellView.tasks,
        tier: TaskTier.ready,
        labelId: 'work000001',
        searchOpen: true,
        searchQuery: 'Alpha',
        expandedEntity: EntityRef(kind: EntityKind.task, id: 'taskA00001'),
      );
      expect(contextA, equals(contextB));
      expect(contextA.hashCode, equals(contextB.hashCode));

      final stateA = ShellState(
        activeTier: TaskTier.planned,
        returnContext: contextA,
      );
      final stateB = stateA.copyWith();
      expect(stateA, equals(stateB));
      expect(stateA.hashCode, equals(stateB.hashCode));
    });

    test('ref-counts overlapping runLocalEntityMutation calls on the same EntityRef', () async {
      final fixedNow = DateTime.utc(2026, 11, 10, 12);
      final initialBoard = TaskBoard.evaluate(
        tasks: <TaskItem>[
          TaskItem(
            id: 'taskRef001',
            title: 'Overlap Target',
            createdAt: fixedNow,
            modifiedAt: fixedNow,
          ),
        ],
        queueBlock: TdfQueueBlock(
          taskIds: const <String>['taskRef001'],
          modifiedAt: fixedNow,
        ),
        evaluationTime: fixedNow,
      );
      final taskNotifier = _ControllableTaskNotifier(initialBoard);
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const WebDavConfig(language: AppLanguage.english),
            ),
          ),
          taskNotifierProvider.overrideWith(() => taskNotifier),
          clockProvider.overrideWithValue(() => fixedNow),
        ],
      );
      addTearDown(container.dispose);

      await container.read(activeWorkspaceProvider.future);
      await container.read(taskNotifierProvider.future);
      final shellSub = container.listen(shellProvider, (_, _) {});
      addTearDown(shellSub.close);
      final noticeSub = container.listen(floatingNoticeProvider, (_, _) {});
      addTearDown(noticeSub.close);

      const target = EntityRef(kind: EntityKind.task, id: 'taskRef001');
      final shell = container.read(shellProvider.notifier);
      shell.expandEntity(target);

      final firstGate = Completer<void>();
      final secondGate = Completer<void>();
      final firstMutation = shell.runLocalEntityMutation(
        target,
        () => firstGate.future,
      );
      final secondMutation = shell.runLocalEntityMutation(
        target,
        () => secondGate.future,
      );

      // Complete mutation #1 while mutation #2 is still in flight!
      firstGate.complete();
      await firstMutation;

      // Board update removes target while mutation #2 is STILL holding suppression.
      taskNotifier.emitBoard(TaskBoard.empty());
      expect(
        container.read(floatingNoticeProvider),
        isNull,
        reason: 'Overlapping runLocalEntityMutation must keep suppression active until the last call finishes',
      );
      expect(
        container.read(shellProvider).expandedEntity,
        equals(target),
        reason: 'Ref-counted suppression must prevent premature external-removal collapse',
      );

      secondGate.complete();
      await secondMutation;
    });
  });
}
