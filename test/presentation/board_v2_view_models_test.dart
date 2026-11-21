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
import 'package:tiertask/models/app_build_profile.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/storage_file_read_status.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/presentation/app_shell_controller.dart';
import 'package:tiertask/presentation/board_v2_view_models.dart';
import 'package:tiertask/presentation/ui_v2_shell_models.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/location_providers.dart';
import 'package:tiertask/providers/sync_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/location_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';

import '../ui/test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixedNow = DateTime.utc(2026, 11, 10, 12, 0);

  TaskBoard createRichBoard() {
    final workLabel = TdfLabel(
      id: 'work000001',
      name: 'Work',
      color: '#2196F3',
      isScoped: false,
      note: 'Work note',
      links: const <TaskLink>[
        TaskLink(title: 'Docs', uri: 'https://example.com/docs'),
      ],
      modifiedAt: fixedNow,
    );
    final secretLabel = TdfLabel(
      id: 'scop000002',
      name: 'Scoped',
      color: '#4CAF50',
      isScoped: true,
      modifiedAt: fixedNow,
    );
    final officeLoc = TdfLocation(
      id: 'locA000001',
      name: 'Office',
      latitude: 47.1204,
      longitude: 8.5173,
      radius: 250.0,
      source: 'manual',
      note: 'HQ building',
      modifiedAt: fixedNow,
    );
    final prereqTask = TaskItem(
      id: 'preq000001',
      title: 'Prereq Task',
      createdAt: fixedNow,
      modifiedAt: fixedNow,
    );
    // Task with all 9 secondary badge categories populated to verify exact priority order and 3 + N overflow.
    final loadedTask = TaskItem(
      id: 'rich000001',
      title: 'Rich Priority Task',
      note: 'Detailed task note',
      isPriority: true,
      dueAt: fixedNow.add(const Duration(hours: 6)),
      suspendedAt: fixedNow.add(const Duration(hours: 24)),
      suspendedNote: 'Waiting on review',
      dependencies: const <TdfTaskDependency>[
        TdfTaskDependency(taskId: 'preq000001'),
      ],
      conditions: <TaskCondition>[
        DayTaskCondition.fromWeekdays(const <int>[1, 2, 3]),
        LocationTaskCondition.fromIds(const <String>['locA000001']),
      ],
      subtasks: const <SubtaskItem>[
        SubtaskItem(title: 'Step 1', isCompleted: true),
        SubtaskItem(title: 'Step 2', isCompleted: false),
      ],
      subtasksAutoFinish: true,
      repeatRule: const TaskRepeatRule(count: 2, unit: RepeatUnit.weeks),
      links: const <TaskLink>[
        TaskLink(title: 'Spec', uri: 'https://example.com/spec'),
      ],
      history: <TaskHistoryEntry>[
        TaskHistoryEntry(timestampUtc: fixedNow, text: 'Started work'),
      ],
      labelIds: const <String>['work000001'],
      createdAt: fixedNow,
      modifiedAt: fixedNow,
    );
    final completedTask = TaskItem(
      id: 'done000001',
      title: 'Finished Item',
      isCompleted: true,
      completedAt: fixedNow.subtract(const Duration(hours: 1)),
      createdAt: fixedNow.subtract(const Duration(days: 1)),
      modifiedAt: fixedNow,
    );

    return TaskBoard.evaluate(
      tasks: <TaskItem>[prereqTask, loadedTask, completedTask],
      labels: <TdfLabel>[workLabel, secretLabel],
      locations: <TdfLocation>[officeLoc],
      evaluationTime: fixedNow,
      localEvaluationTime: fixedNow,
    );
  }

  group('board_v2_view_models', () {
    test('shellThemeStateProvider projects every palette, themeMode, and locale exhaustively', () async {
      for (final palette in AppThemePalette.values) {
        for (final themeMode in AppThemeMode.values) {
          final config = WebDavConfig(
            language: AppLanguage.english,
            themePalette: palette,
            themeMode: themeMode,
          );
          final container = ProviderContainer(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(
                InMemorySettingsRepository(config),
              ),
            ],
          );
          addTearDown(container.dispose);
          await container.read(webDavConfigProvider.future);

          final themeState = container.read(shellThemeStateProvider);
          expect(
            themeState.presetId,
            equals(palette.jsonValue),
            reason: 'presetId must match AppThemePalette.jsonValue',
          );
          expect(
            themeState.themeMode.name,
            equals(themeMode.name),
            reason: 'ShellThemeMode must mirror AppThemeMode',
          );
          expect(themeState.locale.languageCode, equals('en'));
        }
      }
    });

    test('boardChromeViewModelProvider and sidebarViewModelProvider project build profile, sync statuses, WIP limits, and version footer', () async {
      final board = createRichBoard();
      const config = WebDavConfig(
        language: AppLanguage.english,
        storageMode: StorageMode.both,
        serverUrl: 'https://cloud.example.com',
        username: 'alice',
        password: 'secret',
        locationEnabled: true,
        diagnosticsEnabled: true,
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(config),
          ),
          taskNotifierProvider.overrideWith(() => FakeTaskNotifier(board)),
          appBuildProfileProvider.overrideWithValue(AppBuildProfile.dev),
          appVersionProvider.overrideWith((ref) async => 'v0.4.0+4.abc1234'),
          supportsDesktopWindowControlsProvider.overrideWithValue(true),
          locationRepositoryProvider.overrideWithValue(
            FakeLocationRepository(
              initialFix: const LocationFix(
                latitude: 47.1204,
                longitude: 8.5173,
                source: LocationSource.gps,
                placeName: 'Riverdale',
              ),
            ),
          ),
          clockProvider.overrideWithValue(() => fixedNow),
        ],
      );
      addTearDown(container.dispose);
      await container.read(webDavConfigProvider.future);
      await container.read(taskNotifierProvider.future);
      await container.read(appVersionProvider.future);

      final chrome = container.read(boardChromeViewModelProvider);
      expect(chrome.isDevBuild, isTrue);
      expect(chrome.locationEnabled, isTrue);
      expect(chrome.showWindowControls, isTrue);
      expect(chrome.syncStatusKind, equals(ShellSyncStatusKind.synced));

      // Conflict state switches chrome indicator to conflict.
      container
          .read(syncStateProvider.notifier)
          .setConflict(
            'Conflict',
            outcome: const TdfSyncOutcomeException(
              kind: TdfSyncOutcomeKind.deletionConflict,
              message: 'Conflict',
              conflictedTaskIds: <String>['rich000001'],
            ),
          );
      expect(
        container.read(boardChromeViewModelProvider).syncStatusKind,
        equals(ShellSyncStatusKind.conflict),
      );

      final sidebar = container.read(sidebarViewModelProvider);
      expect(sidebar.showSyncWebDav, isTrue);
      expect(sidebar.showDiagnosticLog, isTrue);
      expect(sidebar.versionLabel, equals('Version 0.4.0'));
      expect(sidebar.buildSuffix, equals('+4.abc1234'));
      expect(sidebar.tierItems, hasLength(6));
      expect(sidebar.tierItems[0].wipLimit, equals(3));
      expect(sidebar.tierItems[1].wipLimit, equals(5));
      expect(sidebar.labels, hasLength(2));
      expect(sidebar.locations, hasLength(1));

      // Sidebar label filter restricts visible labels while keeping total count.
      container
          .read(appShellControllerProvider.notifier)
          .toggleSidebarLabelsFilter();
      container
          .read(appShellControllerProvider.notifier)
          .setSidebarLabelsFilterQuery('Scop');
      final filteredSidebar = container.read(sidebarViewModelProvider);
      expect(filteredSidebar.totalLabelCount, equals(2));
      expect(filteredSidebar.labels, hasLength(1));
      expect(filteredSidebar.labels.single.name, equals('Scoped'));
    });

    test('tasksViewModelProvider enforces exact collapsed badge priority order, 3 + N overflow, Search tier badges, and banners', () async {
      final board = createRichBoard();
      const config = WebDavConfig(language: AppLanguage.english);
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(config),
          ),
          taskNotifierProvider.overrideWith(() => FakeTaskNotifier(board)),
          clockProvider.overrideWithValue(() => fixedNow),
        ],
      );
      addTearDown(container.dispose);
      await container.read(webDavConfigProvider.future);
      await container.read(taskNotifierProvider.future);
      await container.read(appVersionProvider.future);

      // Switch to Blocked tier where loadedTask resides (suspended + blockedBy).
      final shell = container.read(appShellControllerProvider.notifier);
      shell.selectTier(ShellTier.blocked);

      final blockedVm = container.read(tasksViewModelProvider);
      expect(blockedVm.tasks, hasLength(1));
      final richCard = blockedVm.tasks.single;
      expect(richCard.id, equals('rich000001'));
      expect(richCard.assignedLabels, hasLength(1));
      // Primary badges: Due only in non-search mode (within 24h lead window -> warning).
      expect(richCard.primaryBadges, hasLength(1));
      expect(richCard.primaryBadges.single.tone, equals(BadgeTone.warning));
      // Secondary badges capped at 3 in strict priority order: Priority -> Suspended -> BlockedBy, overflow = 6 (9 total - 3).
      expect(richCard.visibleSecondaryBadges, hasLength(3));
      expect(
        richCard.visibleSecondaryBadges.map((badge) => badge.iconKey).toList(),
        equals(<CardBadgeIconKey>[
          CardBadgeIconKey.priority,
          CardBadgeIconKey.suspended,
          CardBadgeIconKey.blockedBy,
        ]),
        reason: 'Top 3 secondary badges must strictly follow U-CARD-005 priority order',
      );
      expect(
        richCard.overflowSecondaryCount,
        equals(6),
        reason: '9 total secondary indicators must show +6 overflow',
      );

      // Global Search across all tiers adds Tier badge (tone-soft) as first primary badge.
      shell.openSearch();
      shell.updateSearchQuery('Finished');
      final searchVm = container.read(tasksViewModelProvider);
      expect(searchVm.tasks, hasLength(1));
      expect(searchVm.tasks.single.id, equals('done000001'));
      expect(searchVm.tasks.single.isCompleted, isTrue);
      expect(searchVm.tasks.single.unsetSections, isEmpty);
      expect(
        searchVm.tasks.single.primaryBadges.first.tone,
        equals(BadgeTone.soft),
        reason: 'Search results must prepend a soft-toned Tier badge',
      );

      // Partial file-read report emits danger banner while keeping board usable.
      container
          .read(syncStateProvider.notifier)
          .setError(
            'Local file broken',
            fileReadReport: const StorageFileReadReport(
              local: StorageFileReadStatus.unreadable(
                StorageFileTarget.local,
                detail: 'Unexpected token',
                line: 4,
              ),
              remote: StorageFileReadStatus.readable(StorageFileTarget.remote),
            ),
          );
      final withBanner = container.read(tasksViewModelProvider);
      expect(
        withBanner.banners.any(
          (banner) => banner.kind == ShellBannerKind.partialFileRead,
        ),
        isTrue,
      );
    });

    test('labelsManagerViewModelProvider, locationsManagerViewModelProvider, and rawTdfViewModelProvider project sorted entity cards and raw telemetry', () async {
      final board = createRichBoard();
      const config = WebDavConfig(language: AppLanguage.english);
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(config),
          ),
          taskNotifierProvider.overrideWith(() => FakeTaskNotifier(board)),
          clockProvider.overrideWithValue(() => fixedNow),
        ],
      );
      addTearDown(container.dispose);
      await container.read(webDavConfigProvider.future);
      await container.read(taskNotifierProvider.future);
      await container.read(appVersionProvider.future);

      final labelsVm = container.read(labelsManagerViewModelProvider);
      expect(labelsVm.labels, hasLength(2));
      expect(labelsVm.labels.first.name, equals('Scoped'));
      expect(labelsVm.labels.last.name, equals('Work'));
      expect(labelsVm.labels.last.openCount, equals(1));

      final locationsVm = container.read(locationsManagerViewModelProvider);
      expect(locationsVm.locations, hasLength(1));
      expect(locationsVm.locations.single.name, equals('Office'));
      expect(locationsVm.locations.single.openCount, equals(1));
      expect(
        locationsVm.locations.single.coordinatesSummary,
        contains('47.1204'),
      );

      final rawVm = container.read(rawTdfViewModelProvider);
      expect(rawVm.isLimitExceeded, isFalse);
      expect(rawVm.content, startsWith('tdf 0.8.0'));
      expect(rawVm.byteCount, greaterThan(0));
      expect(rawVm.lineCount, greaterThan(0));
    });

    test('taskPrerequisiteCandidatesProvider computes sorted draft and task candidates with cross-label cycle detection', () async {
      const workLabel = TdfLabel(
        id: 'lblWork001',
        name: 'Work',
        color: '#2196F3',
      );
      final rootTask = TaskItem(
        id: 'tskRoot001',
        title: 'Beta Root',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
        labelIds: const <String>['lblWork001'],
      );
      final unlabeledBridge = TaskItem(
        id: 'tskMid0001',
        title: 'Alpha Bridge',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
        blockedByTaskIds: const <String>['tskRoot001'],
      );
      final leafTask = TaskItem(
        id: 'tskLeaf001',
        title: 'Gamma Leaf',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
        labelIds: const <String>['lblWork001'],
        blockedByTaskIds: const <String>['tskMid0001'],
      );
      final freeTask = TaskItem(
        id: 'tskFree001',
        title: 'Delta Free',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
      );
      final completedSelected = TaskItem(
        id: 'tskDoneSel',
        title: 'Completed Selected',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
        completedAt: fixedNow,
        isCompleted: true,
        completions: 1,
      );
      final completedUnselected = TaskItem(
        id: 'tskDoneIgn',
        title: 'Completed Ignored',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
        completedAt: fixedNow,
        isCompleted: true,
        completions: 1,
      );
      final taskWithCompletedDep = TaskItem(
        id: 'tskHasDone',
        title: 'Epsilon Dependent',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
        blockedByTaskIds: const <String>['tskDoneSel'],
      );
      final board = TaskBoard.evaluate(
        tasks: <TaskItem>[
          rootTask,
          unlabeledBridge,
          leafTask,
          freeTask,
          completedSelected,
          completedUnselected,
          taskWithCompletedDep,
        ],
        labels: const <TdfLabel>[workLabel],
        queueBlock: TdfQueueBlock(
          taskIds: const <String>[
            'tskRoot001',
            'tskMid0001',
            'tskLeaf001',
            'tskFree001',
            'tskHasDone',
          ],
        ),
        evaluationTime: fixedNow,
      );

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const WebDavConfig(language: AppLanguage.english),
            ),
          ),
          taskNotifierProvider.overrideWith(() => FakeTaskNotifier(board)),
          clockProvider.overrideWithValue(() => fixedNow),
        ],
      );
      addTearDown(container.dispose);
      await container.read(webDavConfigProvider.future);
      await container.read(taskNotifierProvider.future);

      // Filter the shell by Work label; cross-label bridge must still be visible and cycle-checked.
      container
          .read(appShellControllerProvider.notifier)
          .selectLabelFilter('lblWork001');

      final rootCandidates = container.read(
        taskPrerequisiteCandidatesProvider('tskRoot001'),
      );
      expect(
        rootCandidates.map((candidate) => candidate.id).toList(),
        equals(<String>[
          'tskMid0001',
          'tskFree001',
          'tskHasDone',
          'tskLeaf001',
        ]),
        reason: 'Open candidates must be sorted alphabetically by title and exclude self and unselected completed tasks',
      );
      expect(
        rootCandidates
            .where((candidate) => candidate.wouldCreateCycle)
            .map((candidate) => candidate.id)
            .toSet(),
        equals(<String>{'tskMid0001', 'tskLeaf001'}),
        reason: 'Transitive cycle through unlabeled bridge must be flagged even when activeLabelId filters the view',
      );

      final selectedCompletedCandidates = container.read(
        taskPrerequisiteCandidatesProvider('tskHasDone'),
      );
      expect(
        selectedCompletedCandidates.any(
          (candidate) => candidate.id == 'tskDoneSel' && candidate.isSelected,
        ),
        isTrue,
        reason: 'Already-selected completed prerequisite must remain visible for removal',
      );
      expect(
        selectedCompletedCandidates.any(
          (candidate) => candidate.id == 'tskDoneIgn',
        ),
        isFalse,
        reason: 'Unselected completed tasks must be excluded',
      );

      final draftCandidates = container.read(
        taskPrerequisiteCandidatesProvider(null),
      );
      expect(
        draftCandidates.map((candidate) => candidate.id).toList(),
        equals(<String>[
          'tskMid0001',
          'tskRoot001',
          'tskFree001',
          'tskHasDone',
          'tskLeaf001',
        ]),
        reason: 'Draft candidates must include all open tasks across tiers sorted by title',
      );
      expect(
        draftCandidates.every(
          (candidate) => !candidate.wouldCreateCycle && !candidate.isSelected,
        ),
        isTrue,
      );

      expect(
        container.read(taskPrerequisiteCandidatesProvider('tskDoneSel')),
        isEmpty,
        reason: 'Completed tasks cannot edit prerequisites',
      );
      expect(
        container.read(taskPrerequisiteCandidatesProvider('unknown999')),
        isEmpty,
        reason: 'Unknown task IDs must yield no prerequisite candidates',
      );
    });

    test('tasksViewModelProvider ignores non-banner sync churn and non-conflict view changes and scales linearly in Global Search', () async {
      final tasks = <TaskItem>[
        for (var i = 0; i < 400; i++)
          TaskItem(
            id: 'prf${i.toString().padLeft(7, '0')}',
            title: 'Task $i',
            createdAt: fixedNow,
            modifiedAt: fixedNow,
            isCompleted: i >= 320,
            completedAt: i >= 320 ? fixedNow : null,
            completions: i >= 320 ? 1 : 0,
            blockedByTaskIds: i > 0 && i < 20
                ? <String>['prf${(i - 1).toString().padLeft(7, '0')}']
                : const <String>[],
          ),
      ];
      final board = TaskBoard.evaluate(
        tasks: tasks,
        queueBlock: TdfQueueBlock(
          taskIds: <String>[
            for (var i = 0; i < 320; i++) 'prf${i.toString().padLeft(7, '0')}',
          ],
        ),
        evaluationTime: fixedNow,
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const WebDavConfig(language: AppLanguage.english),
            ),
          ),
          taskNotifierProvider.overrideWith(() => FakeTaskNotifier(board)),
          clockProvider.overrideWithValue(() => fixedNow),
        ],
      );
      addTearDown(container.dispose);
      await container.read(webDavConfigProvider.future);
      await container.read(taskNotifierProvider.future);

      var rebuildCount = 0;
      final subscription = container.listen<TasksViewModel>(
        tasksViewModelProvider,
        (_, _) => rebuildCount++,
        fireImmediately: false,
      );
      addTearDown(subscription.close);

      // Opening Global Search on 400 tasks must finish quickly without cubic candidate builds.
      final shell = container.read(appShellControllerProvider.notifier);
      final stopwatch = Stopwatch()..start();
      shell.openSearch();
      final searchVm = container.read(tasksViewModelProvider);
      stopwatch.stop();

      expect(searchVm.tasks, hasLength(400));
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(500),
        reason: 'Opening Global Search across 400 tasks must scale linearly instead of O(N^3)',
      );

      final rebuildsAfterSearch = rebuildCount;

      // Toggling isSyncing and updating lastSyncedAt without banner changes must not rebuild tasksViewModelProvider.
      final syncNotifier = container.read(syncStateProvider.notifier);
      syncNotifier.setSyncing();
      syncNotifier.setSuccess(fixedNow.add(const Duration(seconds: 5)));
      expect(
        rebuildCount,
        equals(rebuildsAfterSearch),
        reason: 'Clean sync isSyncing/lastSyncedAt updates must not recompute tasksViewModelProvider',
      );

      // Switching between Tasks, Settings, and Labels must not recompute tasksViewModelProvider.
      shell.openView(ShellView.settings);
      shell.openView(ShellView.labels);
      shell.openView(ShellView.tasks);
      expect(
        rebuildCount,
        equals(rebuildsAfterSearch),
        reason: 'Opening Settings or Labels must not recompute tasksViewModelProvider',
      );
    });
  });
}
