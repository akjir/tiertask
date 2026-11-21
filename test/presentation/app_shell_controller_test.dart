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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/settings_codec.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/presentation/app_shell_controller.dart';
import 'package:tiertask/presentation/floating_notice_controller.dart';
import 'package:tiertask/presentation/ui_v2_shell_models.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/tdf_service.dart';

import '../ui/test_helpers.dart';

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
    final settingsRepo = recoveryNotice != null
        ? InMemorySettingsRepository.withRecoveryNotice(
            initialConfig: config,
            recoveryNotice: recoveryNotice,
          )
        : InMemorySettingsRepository(config);
    final localRepo = FakeLocalFileRepository(
      config: config,
      initialTdf: initialTdf,
    );
    return ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        localFileRepositoryProvider.overrideWith((ref) => localRepo),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1, 12, 0)),
      ],
    );
  }

  group('AppShellController', () {
    test('unwinds all 9 desktop Escape layers in strict priority order and reaches allowSystemPop', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      final controller = container.read(appShellControllerProvider.notifier);
      const target = EntityRef(kind: EntityKind.task, id: 'taskA00001');

      // Stack Layers 0..6 (opening a draft intentionally clears expanded/edit state per U-CARD-006).
      controller.openSearch();
      controller.updateSearchQuery('Alpha');
      controller.openDraft(EntityDraftKind.task);
      controller.setLabelPickerOpen(true);
      controller.setLabelPickerQuery('Urg');
      controller.toggleSidebarLabelsFilter();
      controller.setSidebarLabelsFilterQuery('Wo');
      controller.setCompactDrawerOpen(true);

      // 0. Compact drawer closes first when open.
      expect(
        controller.handleEscape(),
        equals(ShellDismissOutcome.handled),
        reason: 'Compact drawer must dismiss before inner layers',
      );
      expect(
        container.read(appShellControllerProvider).compactDrawerOpen,
        isFalse,
      );

      // Re-open sidebar filter to test Layer 1 -> Layer 2 order cleanly.
      controller.toggleSidebarLabelsFilter();
      controller.setSidebarLabelsFilterQuery('Wo');

      // 1. Label picker search query clears before sidebar filter.
      expect(controller.handleEscape(), equals(ShellDismissOutcome.handled));
      expect(
        container.read(appShellControllerProvider).labelPickerQuery,
        isEmpty,
        reason: 'Layer 1 must clear label picker search query',
      );
      expect(
        container.read(appShellControllerProvider).labelPickerOpen,
        isTrue,
      );

      // 2. Sidebar filter closes and clears.
      expect(controller.handleEscape(), equals(ShellDismissOutcome.handled));
      expect(
        container.read(appShellControllerProvider).sidebarLabelsFilterOpen,
        isFalse,
        reason: 'Layer 2 must close sidebar filter',
      );
      expect(
        container.read(appShellControllerProvider).sidebarLabelsFilterQuery,
        isEmpty,
      );

      // 4. Open label picker closes (Layer 3 is modal route handled by Navigator).
      expect(controller.handleEscape(), equals(ShellDismissOutcome.handled));
      expect(
        container.read(appShellControllerProvider).labelPickerOpen,
        isFalse,
        reason: 'Layer 4 must close open label picker',
      );

      // 5. Open uncommitted entity draft card cancels.
      expect(controller.handleEscape(), equals(ShellDismissOutcome.handled));
      expect(
        container.read(appShellControllerProvider).activeDraft,
        isNull,
        reason: 'Layer 5 must cancel active draft card',
      );

      // 6. Global Search closes and clears query.
      expect(controller.handleEscape(), equals(ShellDismissOutcome.handled));
      expect(
        container.read(appShellControllerProvider).searchOpen,
        isFalse,
        reason: 'Layer 6 must close Global Search',
      );
      expect(container.read(appShellControllerProvider).searchQuery, isEmpty);

      // Stack Layers 7 -> 9 (inline edit -> expanded card) and Layer 8 -> 9 (delete confirm -> expanded card).
      controller.expandEntity(target);
      controller.openInlineEdit(
        InlineEditTarget.task(target.id, TaskSectionKind.note),
      );

      // 7. Active inline section edit cancels.
      expect(controller.handleEscape(), equals(ShellDismissOutcome.handled));
      expect(
        container.read(appShellControllerProvider).activeInlineEdit,
        isNull,
        reason: 'Layer 7 must cancel active inline edit',
      );
      expect(
        container.read(appShellControllerProvider).expandedEntity,
        equals(target),
      );

      // 8. Active inline delete confirmation cancels before collapsing card.
      controller.requestInlineDelete(target);
      expect(controller.handleEscape(), equals(ShellDismissOutcome.handled));
      expect(
        container.read(appShellControllerProvider).activeDeleteConfirm,
        isNull,
        reason: 'Layer 8 must cancel inline delete confirm',
      );
      expect(
        container.read(appShellControllerProvider).expandedEntity,
        equals(target),
      );

      // 9. Expanded entity card collapses.
      expect(controller.handleEscape(), equals(ShellDismissOutcome.handled));
      expect(
        container.read(appShellControllerProvider).expandedEntity,
        isNull,
        reason: 'Layer 9 must collapse expanded entity card',
      );

      // Clean root returns allowSystemPop.
      expect(
        controller.handleEscape(),
        equals(ShellDismissOutcome.allowSystemPop),
        reason: 'Clean tasks root must return allowSystemPop',
      );
    });

    test('handleSystemBack unwinds tablet sidebar filter, returnContext, secondary views, and permits OS exit only on clean tasks root', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      final controller = container.read(appShellControllerProvider.notifier);
      controller.selectTier(ShellTier.ready);
      controller.selectLabelFilter('work000001');
      controller.openSearch();
      controller.updateSearchQuery('Alpha');
      controller.expandEntity(
        const EntityRef(kind: EntityKind.task, id: 'taskA00001'),
      );

      // Open label in manager with returnContext preserved.
      controller.openEntityInManager(
        const EntityRef(kind: EntityKind.label, id: 'work000001'),
        preserveReturnContext: true,
      );
      var state = container.read(appShellControllerProvider);
      expect(state.view, equals(ShellView.labels));
      expect(state.returnContext, isNotNull);
      expect(state.returnContext?.searchOpen, isTrue);
      expect(state.returnContext?.searchQuery, equals('Alpha'));
      expect(
        state.expandedEntity,
        equals(const EntityRef(kind: EntityKind.label, id: 'work000001')),
      );

      // Open persistent sidebar filter (tablet Layer 2).
      controller.toggleSidebarLocationsFilter();
      expect(
        controller.handleSystemBack(),
        equals(ShellDismissOutcome.handled),
        reason: 'Back must close persistent sidebar filter first',
      );
      expect(
        container.read(appShellControllerProvider).sidebarLocationsFilterOpen,
        isFalse,
      );

      // Next Back collapses expanded label card.
      expect(
        controller.handleSystemBack(),
        equals(ShellDismissOutcome.handled),
      );
      expect(container.read(appShellControllerProvider).expandedEntity, isNull);

      // Next Back restores returnContext back to Search + Ready + Work + expanded taskA.
      expect(
        controller.handleSystemBack(),
        equals(ShellDismissOutcome.handled),
      );
      state = container.read(appShellControllerProvider);
      expect(state.view, equals(ShellView.tasks));
      expect(state.activeTier, equals(ShellTier.ready));
      expect(state.activeLabelId, equals('work000001'));
      expect(state.searchOpen, isTrue);
      expect(state.searchQuery, equals('Alpha'));
      expect(
        state.expandedEntity,
        equals(const EntityRef(kind: EntityKind.task, id: 'taskA00001')),
      );
      expect(state.returnContext, isNull);

      // Unwind search and expanded task.
      expect(
        controller.handleSystemBack(),
        equals(ShellDismissOutcome.handled),
      );
      expect(
        controller.handleSystemBack(),
        equals(ShellDismissOutcome.handled),
      );
      expect(
        controller.handleSystemBack(),
        equals(ShellDismissOutcome.allowSystemPop),
        reason: 'Clean tasks view must permit Android system pop',
      );

      // Direct secondary view without returnContext returns to tasks.
      controller.openView(ShellView.settings);
      expect(
        container.read(appShellControllerProvider).view,
        equals(ShellView.settings),
      );
      expect(
        controller.handleSystemBack(),
        equals(ShellDismissOutcome.handled),
      );
      expect(
        container.read(appShellControllerProvider).view,
        equals(ShellView.tasks),
      );
    });

    test('preserves active inline edit on benign external update, auto-closes on external deletion or completion, suppresses local mutations, and clears stale activeLabelId', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final initialBoard = await container.read(taskNotifierProvider.future);
      // Keep controllers alive while testing reactive board listener.
      final shellSub = container.listen(appShellControllerProvider, (_, _) {});
      final noticeSub = container.listen(
        floatingNoticeControllerProvider,
        (_, _) {},
      );
      addTearDown(shellSub.close);
      addTearDown(noticeSub.close);

      final controller = container.read(appShellControllerProvider.notifier);
      const taskA = EntityRef(kind: EntityKind.task, id: 'taskA00001');
      controller.selectLabelFilter('work000001');
      controller.expandEntity(taskA);
      controller.openInlineEdit(
        InlineEditTarget.task(taskA.id, TaskSectionKind.note),
      );

      // Benign external board refresh (e.g., another task updated): keep card & inline edit intact.
      await container
          .read(taskNotifierProvider.notifier)
          .updateTask('taskB00002', note: 'External edit');
      expect(
        container.read(appShellControllerProvider).expandedEntity,
        equals(taskA),
      );
      expect(
        container.read(appShellControllerProvider).activeInlineEdit,
        equals(InlineEditTarget.task(taskA.id, TaskSectionKind.note)),
      );
      expect(
        container.read(floatingNoticeControllerProvider),
        isNull,
        reason: 'Benign refresh must not emit external removal notice',
      );

      // External completion of taskA via disk update while editing Note cancels inline edit, keeps card open, and emits notice.
      final localRepo = container.read(
        localFileRepositoryProvider,
      ) as FakeLocalFileRepository;
      final currentBoard = container.read(taskNotifierProvider).requireValue;
      final externallyCompletedBoard = currentBoard.completeTask(
        'taskA00001',
        currentDate: DateTime.utc(2026, 11, 1, 12, 5),
      );
      localRepo.initialTdf = const TdfService().serialize(
        externallyCompletedBoard,
      );
      final reconciled = await container
          .read(taskNotifierProvider.notifier)
          .reconcileExternalLocalChanges();
      expect(reconciled, isTrue);
      expect(
        container.read(appShellControllerProvider).expandedEntity,
        equals(taskA),
        reason: 'External completion keeps card expanded in read-only mode',
      );
      expect(
        container.read(appShellControllerProvider).activeInlineEdit,
        isNull,
        reason:
            'External completion must close non-History inline section edit',
      );
      expect(
        container.read(floatingNoticeControllerProvider)?.message,
        contains('completed by an external update'),
      );

      // External deletion of active filter label clears activeLabelId.
      await container
          .read(taskNotifierProvider.notifier)
          .deleteLabel('work000001');
      expect(
        container.read(appShellControllerProvider).activeLabelId,
        isNull,
        reason: 'External label deletion must clear stale activeLabelId',
      );

      // Local mutation suppression prevents spurious external removal notice.
      container.read(floatingNoticeControllerProvider.notifier).dismiss();
      const taskB = EntityRef(kind: EntityKind.task, id: 'taskB00002');
      controller.expandEntity(taskB);
      await controller.runLocalEntityMutation(taskB, () async {
        await container
            .read(taskNotifierProvider.notifier)
            .deleteTask(taskB.id);
        controller.collapseEntity();
      });
      expect(
        container.read(floatingNoticeControllerProvider)?.message,
        isNot(contains('external update')),
        reason: 'Suppressed local delete must show Undo notice instead of external removal notice',
      );
      expect(
        container.read(floatingNoticeControllerProvider)?.undoSequence,
        isNotNull,
      );

      // Verify initial board fixture had 2 tasks.
      expect(initialBoard.allTasks, hasLength(2));
    });

    test('resets shell state on workspace switch and exposes startup recovery notice persistently', () async {
      final container = createContainer(
        recoveryNotice: const SettingsRecoveryNotice(
          kind: SettingsRecoveryKind.recoveredFromBackup,
          quarantinedFilePath: '/tmp/settings.json.corrupt',
        ),
      );
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      final shellSub = container.listen(appShellControllerProvider, (_, _) {});
      final noticeSub = container.listen(
        floatingNoticeControllerProvider,
        (_, _) {},
      );
      addTearDown(shellSub.close);
      addTearDown(noticeSub.close);

      container
          .read(floatingNoticeControllerProvider.notifier)
          .showStartupRecoveryNoticeIfPending();
      final recovery = container.read(floatingNoticeControllerProvider);
      expect(recovery, isNotNull);
      expect(recovery?.persistent, isTrue);
      expect(recovery?.tone, equals(NoticeTone.warning));

      final shell = container.read(appShellControllerProvider.notifier);
      shell.openView(ShellView.labels);
      shell.openDraft(EntityDraftKind.label);

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
      expect(
        container.read(appShellControllerProvider).view,
        equals(ShellView.tasks),
      );
      expect(container.read(appShellControllerProvider).activeDraft, isNull);
    });
  });
}
