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
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';

class _FakeFlutterSecureStorage extends FlutterSecureStorage {
  _FakeFlutterSecureStorage([Map<String, String>? initialValues])
    : _store = Map<String, String>.from(initialValues ?? const {});

  final Map<String, String> _store;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _store[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }
}

void main() {
  final fixedDate = DateTime.utc(2026, 11, 2, 10, 0);

  group('AppWorkspace & Suggested TDF File Names', () {
    test('defaults to Tasks workspace with tasks.tdf and derives lowercase .tdf filenames from workspace names', () {
      const defaultWorkspace = AppWorkspace.defaultWorkspace;
      expect(defaultWorkspace.id, equals('tasks'));
      expect(defaultWorkspace.name, equals('Tasks'));
      expect(defaultWorkspace.config.localFilePath, equals('tasks.tdf'));
      expect(defaultWorkspace.config.filePath, equals('tasks.tdf'));

      expect(AppWorkspace.suggestFileName('Tasks'), equals('tasks.tdf'));
      expect(AppWorkspace.suggestFileName('Arbeit'), equals('arbeit.tdf'));
      expect(
        AppWorkspace.suggestFileName('  Kunde Müller & Söhne! '),
        equals('kunde_mueller_soehne.tdf'),
      );
      expect(
        AppWorkspace.suggestFileName('Großprojekt ÄÖÜ'),
        equals('grossprojekt_aeoeue.tdf'),
      );
      expect(
        AppWorkspace.suggestFileName('   ---   '),
        equals('workspace.tdf'),
      );

      final updated = defaultWorkspace.copyWith(
        name: 'Private Tasks',
        config: const WebDavConfig(
          localFilePath: 'private.tdf',
          filePath: 'private.tdf',
          themeMode: AppThemeMode.dark,
        ),
      );
      final roundTrip = AppWorkspace.fromJson(updated.toJson());
      expect(roundTrip, equals(updated));
      expect(roundTrip.hashCode, equals(updated.hashCode));
      expect(roundTrip.summary.id, equals('tasks'));
      expect(roundTrip.summary.name, equals('Private Tasks'));
      expect(roundTrip.summary.localFilePath, equals('private.tdf'));
      expect(roundTrip.summary.filePath, equals('private.tdf'));
    });
  });

  group('Workspace Uniqueness, Bounds & Error Exhaustiveness', () {
    test('enforces non-empty names, unique workspace names, unique .tdf file paths, and all WorkspaceErrorKind variants', () async {
      final repository = InMemorySettingsRepository();

      final initialActive = await repository.loadActiveWorkspace();
      expect(initialActive.id, equals('tasks'));
      expect(initialActive.name, equals('Tasks'));
      expect(initialActive.config.localFilePath, equals('tasks.tdf'));

      for (final invalidName in ['', '   ', 'Bad\nName', 'A' * 129]) {
        await expectLater(
          () => repository.createWorkspace(invalidName),
          throwsA(
            isA<WorkspaceException>().having(
              (error) => error.kind,
              'kind',
              WorkspaceErrorKind.emptyName,
            ),
          ),
          reason: 'Invalid workspace name "$invalidName" must be rejected',
        );
      }

      for (final duplicateName in ['Tasks', 'tasks', '  TASKS  ']) {
        await expectLater(
          () => repository.createWorkspace(duplicateName),
          throwsA(
            isA<WorkspaceException>().having(
              (error) => error.kind,
              'kind',
              WorkspaceErrorKind.duplicateName,
            ),
          ),
          reason: 'Duplicate workspace name "$duplicateName" must be rejected',
        );
      }

      final arbeitWorkspace = await repository.createWorkspace('Arbeit');
      expect(arbeitWorkspace.id, equals('arbeit'));
      expect(arbeitWorkspace.name, equals('Arbeit'));
      expect(arbeitWorkspace.config.localFilePath, equals('arbeit.tdf'));
      expect(arbeitWorkspace.config.filePath, equals('arbeit.tdf'));

      await expectLater(
        () => repository.createWorkspace(
          'Zweiter Job',
          config: const WebDavConfig(
            localFilePath: 'ARBEIT.tdf',
            filePath: 'zweiter_job.tdf',
          ),
        ),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.duplicateFilePath,
          ),
        ),
        reason: 'Duplicate localFilePath must be rejected across workspaces',
      );

      await expectLater(
        () => repository.createWorkspace(
          'Dritter Job',
          config: const WebDavConfig(
            localFilePath: 'dritter_job.tdf',
            filePath: 'tasks.tdf',
          ),
        ),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.duplicateFilePath,
          ),
        ),
        reason: 'Duplicate remote filePath must be rejected across workspaces',
      );

      for (final invalidPath in [
        '',
        '../escape.tdf',
        'notes.txt',
        'bad\x00.tdf',
      ]) {
        await expectLater(
          () => repository.createWorkspace(
            'Invalid File Workspace',
            config: WebDavConfig(
              localFilePath: invalidPath,
              filePath: 'valid.tdf',
            ),
          ),
          throwsA(
            isA<WorkspaceException>().having(
              (error) => error.kind,
              'kind',
              WorkspaceErrorKind.invalidFilePath,
            ),
          ),
          reason: 'Invalid TDF path "$invalidPath" must be rejected',
        );
      }

      await expectLater(
        () => repository.renameWorkspace('arbeit', '  tasks '),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.duplicateName,
          ),
        ),
        reason: 'Renaming to an existing workspace name must be rejected',
      );

      final renamedArbeit = await repository.renameWorkspace(
        'arbeit',
        'Kunde Nord',
      );
      expect(renamedArbeit.name, equals('Kunde Nord'));
      expect(
        renamedArbeit.config.localFilePath,
        equals('arbeit.tdf'),
        reason: 'Renaming a workspace must keep its configured .tdf file',
      );

      await expectLater(
        () => repository.saveConfig(
          const WebDavConfig(
            localFilePath: 'arbeit.tdf',
            filePath: 'tasks.tdf',
          ),
        ),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.duplicateFilePath,
          ),
        ),
        reason: 'Updating active config to another workspace file must fail',
      );

      await expectLater(
        () => repository.activateWorkspace('nonexistent'),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.workspaceNotFound,
          ),
        ),
      );

      await repository.deleteWorkspace('arbeit');
      await expectLater(
        () => repository.deleteWorkspace('tasks'),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.cannotDeleteLastWorkspace,
          ),
        ),
        reason: 'Deleting the sole remaining workspace must be rejected',
      );

      for (var i = 2; i <= AppWorkspace.maxWorkspaces; i++) {
        await repository.createWorkspace('Workspace $i');
      }
      await expectLater(
        () => repository.createWorkspace('Overflow Workspace'),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.maxWorkspacesExceeded,
          ),
        ),
        reason: 'Exceeding AppWorkspace.maxWorkspaces must be rejected',
      );
    });
  });

  group('Single-Workspace In-Memory Unload and Load Lifecycle', () {
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
          showOpenTaskCount: true,
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
      expect(container.read(appThemeModeProvider), equals(AppThemeMode.dark));
      expect(container.read(appLocaleProvider), equals(const Locale('de')));

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
        reason: 'Only the newly activated Arbeit workspace must be in state',
      );

      final switchedConfig = await container.read(webDavConfigProvider.future);
      expect(switchedConfig.localFilePath, equals('arbeit.tdf'));
      expect(
        container.read(appThemeModeProvider),
        equals(AppThemeMode.light),
        reason: 'Theme mode must reflect the loaded Arbeit workspace',
      );
      expect(
        container.read(appLocaleProvider),
        equals(const Locale('en')),
        reason: 'Locale must reflect the loaded Arbeit workspace',
      );

      final arbeitBoard = await container.read(taskNotifierProvider.future);
      expect(
        arbeitBoard.allTasks,
        isEmpty,
        reason: 'Switching to Arbeit must unload Tasks board and never leak previous tasks into the new workspace',
      );
      final arbeitFile = File('${tempDir.path}/arbeit.tdf');
      expect(
        await arbeitFile.exists(),
        isFalse,
        reason: 'Switching to an empty workspace must not write old tasks',
      );

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
        reason: 'Arbeit mutations must not touch tasks.tdf',
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
        reason: 'Switching back to Tasks must unload Kunde Alpha and reload tasks.tdf',
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
        reason: 'Deleting the active workspace must unload it and load the fallback workspace',
      );
      final fallbackBoard = await container.read(taskNotifierProvider.future);
      expect(
        fallbackBoard.focus.map((task) => task.title),
        equals(['Private Steuererklärung']),
      );
    });

    test('SecureSettingsRepository migrates legacy single-profile keys into Tasks workspace and persists workspace switches', () async {
      final fakeStorage = _FakeFlutterSecureStorage(<String, String>{
        't2_webdav_server_url': 'https://cloud.example.com',
        't2_webdav_username': 'alice',
        't2_webdav_password': 'secret',
        't2_webdav_file_path': 'tiertask.md',
        't2_local_file_path': '',
        't2_storage_mode': 'both',
        't2_app_language': 'de',
        't2_theme_mode': 'dark',
        't2_show_open_task_count': 'true',
      });
      final repository = SecureSettingsRepository(storage: fakeStorage);

      final migrated = await repository.loadActiveWorkspace();
      expect(migrated.id, equals('tasks'));
      expect(migrated.name, equals('Tasks'));
      expect(migrated.config.filePath, equals('tasks.tdf'));
      expect(migrated.config.localFilePath, equals('tasks.tdf'));
      expect(migrated.config.storageMode, equals(StorageMode.both));
      expect(migrated.config.language, equals(AppLanguage.german));
      expect(migrated.config.themeMode, equals(AppThemeMode.dark));
      expect(migrated.config.showOpenTaskCount, isTrue);

      await repository.createWorkspace('Arbeit', activate: true);
      final activeArbeit = await repository.loadActiveWorkspace();
      expect(activeArbeit.id, equals('arbeit'));
      expect(activeArbeit.name, equals('Arbeit'));
      expect(activeArbeit.config.localFilePath, equals('arbeit.tdf'));

      await repository.renameWorkspace('arbeit', 'Beratung');
      await repository.activateWorkspace('tasks');
      expect((await repository.loadActiveWorkspace()).id, equals('tasks'));
      await repository.deleteWorkspace('arbeit');
      expect((await repository.loadActiveWorkspace()).id, equals('tasks'));
    });
  });
}
