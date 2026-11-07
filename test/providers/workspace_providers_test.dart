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

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/location_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/location_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixedDate = DateTime.utc(2026, 11, 2, 10, 0);

  group('ActiveWorkspaceNotifier & Single-Workspace Lifecycle', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tiertask_workspace_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('loads only one workspace in memory and unloads the current TaskBoard and settings when switching workspaces at runtime', () async {
      final settingsRepository = InMemorySettingsRepository(
        const WebDavConfig(
          language: AppLanguage.german,
          themeMode: AppThemeMode.dark,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
          clockProvider.overrideWithValue(() => fixedDate),
        ],
      );
      addTearDown(container.dispose);

      final initialWorkspace = await container.read(
        activeWorkspaceProvider.future,
      );
      expect(initialWorkspace.id, equals('tasks'));
      expect(initialWorkspace.name, equals('Tasks'));
      expect(initialWorkspace.config.localFilePath, equals('tasks.tdf'));
      expect(
        container.read(appThemeModeProvider),
        equals(AppThemeMode.dark),
        reason: 'Initial theme mode must follow active workspace config',
      );
      expect(
        container.read(appLocaleProvider),
        equals(const Locale('de')),
        reason: 'Initial locale must follow active workspace config',
      );

      final initialBoard = await container.read(taskNotifierProvider.future);
      expect(initialBoard.allTasks, isEmpty);

      await container
          .read(taskNotifierProvider.notifier)
          .addTask('Private Steuererklärung', isPriority: true);

      final tasksBoard = container.read(taskNotifierProvider).requireValue;
      expect(
        tasksBoard.focus.map((task) => task.title),
        equals(['Private Steuererklärung']),
      );
      final tasksFile = File('${tempDir.path}/tasks.tdf');
      expect(await tasksFile.exists(), isTrue);
      expect(
        await tasksFile.readAsString(),
        contains('name "Private Steuererklärung"'),
      );

      final arbeitWorkspace = await container
          .read(activeWorkspaceProvider.notifier)
          .createWorkspace(
            'Arbeit',
            config: const WebDavConfig(
              localFilePath: 'arbeit.tdf',
              filePath: 'arbeit.tdf',
              language: AppLanguage.english,
              themeMode: AppThemeMode.light,
            ),
            activate: true,
          );

      expect(arbeitWorkspace.id, equals('arbeit'));
      expect(
        container.read(activeWorkspaceProvider).requireValue.name,
        equals('Arbeit'),
      );

      final switchedConfig = await container.read(webDavConfigProvider.future);
      expect(switchedConfig.localFilePath, equals('arbeit.tdf'));
      expect(container.read(appThemeModeProvider), equals(AppThemeMode.light));
      expect(container.read(appLocaleProvider), equals(const Locale('en')));

      final arbeitBoard = await container.read(taskNotifierProvider.future);
      expect(
        arbeitBoard.allTasks,
        isEmpty,
        reason: 'Switching to Arbeit must unload Tasks board and never leak previous tasks',
      );
      final arbeitFile = File('${tempDir.path}/arbeit.tdf');
      expect(await arbeitFile.exists(), isFalse);

      await container
          .read(taskNotifierProvider.notifier)
          .addTask('Sprint Planning vorbereiten', isPriority: true);
      expect(await arbeitFile.exists(), isTrue);
      expect(
        await arbeitFile.readAsString(),
        contains('name "Sprint Planning vorbereiten"'),
      );
      expect(
        await tasksFile.readAsString(),
        isNot(contains('Sprint Planning vorbereiten')),
      );

      await container
          .read(activeWorkspaceProvider.notifier)
          .renameWorkspace('arbeit', 'Kunde Alpha');
      expect(
        container.read(activeWorkspaceProvider).requireValue.name,
        equals('Kunde Alpha'),
      );

      await container
          .read(activeWorkspaceProvider.notifier)
          .switchWorkspace('tasks');

      final reloadedTasksConfig = await container.read(
        webDavConfigProvider.future,
      );
      expect(reloadedTasksConfig.localFilePath, equals('tasks.tdf'));
      expect(container.read(appThemeModeProvider), equals(AppThemeMode.dark));
      expect(container.read(appLocaleProvider), equals(const Locale('de')));

      final reloadedTasksBoard = await container.read(
        taskNotifierProvider.future,
      );
      expect(
        reloadedTasksBoard.focus.map((task) => task.title),
        equals(['Private Steuererklärung']),
      );

      await container
          .read(activeWorkspaceProvider.notifier)
          .switchWorkspace('arbeit');
      await container.read(taskNotifierProvider.future);
      await container
          .read(activeWorkspaceProvider.notifier)
          .deleteWorkspace('arbeit');

      expect(
        container.read(activeWorkspaceProvider).requireValue.id,
        equals('tasks'),
        reason: 'Deleting active workspace must unload it and load fallback workspace',
      );
      final fallbackBoard = await container.read(taskNotifierProvider.future);
      expect(
        fallbackBoard.focus.map((task) => task.title),
        equals(['Private Steuererklärung']),
      );
    });

    test('workspaceSummariesProvider reflects creation, renaming, and deletion and prepareForWorkspaceUnload flushes outgoing board before switching or deleting', () async {
      final settingsRepository = InMemorySettingsRepository();
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
          clockProvider.overrideWithValue(() => fixedDate),
        ],
      );
      addTearDown(container.dispose);

      final initialSummaries = await container.read(
        workspaceSummariesProvider.future,
      );
      expect(
        initialSummaries.map((summary) => (summary.id, summary.name)),
        equals(<(String, String)>[('tasks', 'Tasks')]),
      );

      await container.read(taskNotifierProvider.future);
      await container
          .read(taskNotifierProvider.notifier)
          .addTask('Task Before Switch', isPriority: true);

      await container
          .read(activeWorkspaceProvider.notifier)
          .createWorkspace('Projekt B', activate: true);

      final summariesAfterCreate = await container.read(
        workspaceSummariesProvider.future,
      );
      expect(
        summariesAfterCreate.map(
          (summary) => (summary.id, summary.name, summary.localFilePath),
        ),
        equals(<(String, String, String)>[
          ('tasks', 'Tasks', 'tasks.tdf'),
          ('projekt_b', 'Projekt B', 'projekt_b.tdf'),
        ]),
      );

      final projektBBoard = await container.read(taskNotifierProvider.future);
      expect(projektBBoard.allTasks, isEmpty);
      await container
          .read(taskNotifierProvider.notifier)
          .addTask('Projekt B Task', isPriority: true);

      await container
          .read(activeWorkspaceProvider.notifier)
          .renameWorkspace('projekt_b', 'Projekt Beta');
      final summariesAfterRename = await container.read(
        workspaceSummariesProvider.future,
      );
      expect(
        summariesAfterRename.map((summary) => (summary.id, summary.name)),
        equals(<(String, String)>[
          ('tasks', 'Tasks'),
          ('projekt_b', 'Projekt Beta'),
        ]),
      );

      await container
          .read(activeWorkspaceProvider.notifier)
          .deleteWorkspace('projekt_b');

      final summariesAfterDelete = await container.read(
        workspaceSummariesProvider.future,
      );
      expect(
        summariesAfterDelete.map((summary) => summary.id),
        equals(<String>['tasks']),
      );
      final projektBFile = File('${tempDir.path}/projekt_b.tdf');
      expect(await projektBFile.exists(), isTrue);
      expect(
        await projektBFile.readAsString(),
        contains('name "Projekt B Task"'),
      );

      final restoredTasksBoard = await container.read(
        taskNotifierProvider.future,
      );
      expect(
        restoredTasksBoard.focus.map((task) => task.title),
        equals(<String>['Task Before Switch']),
      );
    });

    test('WorkspaceUnloadCoordinator invokes registered callback on switch or active delete and skips unload for inactive operations', () async {
      final settingsRepository = InMemorySettingsRepository();
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
        ],
      );
      addTearDown(container.dispose);

      final coordinator = container.read(workspaceUnloadCoordinatorProvider);
      await coordinator.runBeforeUnload();

      var unloadCount = 0;
      coordinator.register(() async {
        unloadCount++;
      });

      await container.read(activeWorkspaceProvider.future);
      final notifier = container.read(activeWorkspaceProvider.notifier);

      await notifier.createWorkspace('Inactive Workspace', activate: false);
      expect(unloadCount, equals(0));

      final sameSwitch = await notifier.switchWorkspace('tasks');
      expect(sameSwitch.id, equals('tasks'));
      expect(unloadCount, equals(0));

      await notifier.renameWorkspace('inactive_workspace', 'Renamed Inactive');
      expect(
        container.read(activeWorkspaceProvider).requireValue.name,
        equals('Tasks'),
      );

      await notifier.deleteWorkspace('inactive_workspace');
      expect(unloadCount, equals(0));
      expect(disableProviderRetry(1, StateError('boom')), isNull);
    });
  });

  group('LocationNotifier & WebDavConfigNotifier Lifecycle Integration', () {
    test('starts disabled by default, queries on enable, enforces 5-minute resume cooldown, and stops when disabled', () async {
      var now = DateTime.utc(2026, 3, 29, 12, 0);
      final fakeLocationRepository = FakeLocationRepository(
        initialFix: const LocationFix(
          latitude: 50.9787,
          longitude: 11.0328,
          placeName: 'Erfurt, Germany',
        ),
      );
      final settingsRepo = InMemorySettingsRepository();

      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          settingsRepositoryProvider.overrideWithValue(settingsRepo),
          locationRepositoryProvider.overrideWithValue(fakeLocationRepository),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        locationStateProvider,
        (previous, next) {},
      );
      addTearDown(subscription.close);

      await container.read(webDavConfigProvider.future);
      expect(container.read(locationEnabledProvider), isFalse);
      expect(
        container.read(locationStateProvider).status,
        equals(LocationStatus.disabled),
      );
      expect(fakeLocationRepository.callCount, equals(0));

      await container
          .read(webDavConfigProvider.notifier)
          .updateLocationEnabled(true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final enabledState = container.read(locationStateProvider);
      expect(enabledState.status, equals(LocationStatus.found));
      expect(enabledState.fix?.placeName, equals('Erfurt, Germany'));
      expect(fakeLocationRepository.callCount, equals(1));

      container
          .read(locationStateProvider.notifier)
          .handleAppLifecycleState(AppLifecycleState.paused);
      container
          .read(locationStateProvider.notifier)
          .handleAppLifecycleState(AppLifecycleState.inactive);

      now = now.add(const Duration(minutes: 4, seconds: 59));
      container
          .read(locationStateProvider.notifier)
          .handleAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(fakeLocationRepository.callCount, equals(1));

      now = now.add(const Duration(seconds: 1));
      fakeLocationRepository.currentFix = const LocationFix(
        latitude: 52.5200,
        longitude: 13.4050,
        placeName: 'Berlin, Germany',
      );
      container
          .read(locationStateProvider.notifier)
          .handleAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(fakeLocationRepository.callCount, equals(2));
      expect(
        container.read(locationStateProvider).fix?.placeName,
        equals('Berlin, Germany'),
      );

      fakeLocationRepository.currentFix = null;
      await container.read(locationStateProvider.notifier).refreshLocation();
      expect(fakeLocationRepository.callCount, equals(3));
      expect(fakeLocationRepository.lastForceRefresh, isTrue);
      expect(
        container.read(locationStateProvider).status,
        equals(LocationStatus.unavailable),
      );

      await container
          .read(webDavConfigProvider.notifier)
          .updateLocationEnabled(false);
      expect(
        container.read(locationStateProvider).status,
        equals(LocationStatus.disabled),
      );
    });
  });
}
