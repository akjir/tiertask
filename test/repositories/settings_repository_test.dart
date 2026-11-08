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

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/models/workspace_sync_state.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/base64_service.dart';

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
  group('AppLanguage, AppThemeMode, StorageMode & WebDavConfig Defaults', () {
    test('resolves English as default and honors German or System locale settings and binary IDs', () {
      expect(
        AppLanguage.system.resolveLocale(const Locale('de', 'DE')),
        equals(const Locale('de')),
      );
      expect(
        AppLanguage.system.resolveLocale(const Locale('en', 'US')),
        equals(const Locale('en')),
      );
      expect(
        AppLanguage.system.resolveLocale(const Locale('fr', 'FR')),
        equals(const Locale('en')),
      );
      expect(
        AppLanguage.system.resolveLocale(null),
        equals(const Locale('en')),
      );
      expect(
        AppLanguage.english.resolveLocale(const Locale('de', 'DE')),
        equals(const Locale('en')),
      );
      expect(
        AppLanguage.german.resolveLocale(const Locale('en', 'US')),
        equals(const Locale('de')),
      );
      expect(AppLanguage.fromId(2), equals(AppLanguage.german));
      expect(AppLanguage.fromId(1), equals(AppLanguage.english));
      expect(AppLanguage.fromId(0), equals(AppLanguage.system));
      expect(AppLanguage.fromId(99), equals(AppLanguage.system));

      expect(AppThemeMode.fromId(1), equals(AppThemeMode.light));
      expect(AppThemeMode.fromId(2), equals(AppThemeMode.dark));
      expect(AppThemeMode.fromId(0), equals(AppThemeMode.system));
      expect(AppThemeMode.fromId(99), equals(AppThemeMode.system));

      expect(StorageMode.fromId(0), equals(StorageMode.local));
      expect(StorageMode.fromId(1), equals(StorageMode.webdav));
      expect(StorageMode.fromId(2), equals(StorageMode.both));
      expect(StorageMode.fromId(99), equals(StorageMode.local));

      const defaultConfig = WebDavConfig();
      expect(defaultConfig.themeMode, equals(AppThemeMode.system));
      expect(defaultConfig.storageMode, equals(StorageMode.local));
      expect(defaultConfig.localFilePath, equals('tasks.tdf'));
      expect(defaultConfig.filePath, equals('tasks.tdf'));
      expect(defaultConfig.isConfigured, isTrue);
    });
  });

  group('InMemorySettingsRepository', () {
    test('creates, activates, renames, updates config, and deletes workspaces and sync states', () async {
      final repository = InMemorySettingsRepository(
        const WebDavConfig(
          language: AppLanguage.german,
          themeMode: AppThemeMode.dark,
        ),
      );

      final activeInitial = await repository.loadActiveWorkspace();
      expect(activeInitial.id, equals('tasks'));
      expect(activeInitial.name, equals('Tasks'));
      expect(activeInitial.config.language, equals(AppLanguage.german));
      expect((await repository.loadConfig()).themeMode, AppThemeMode.dark);

      final arbeit = await repository.createWorkspace(
        'Arbeit',
        config: const WebDavConfig(
          localFilePath: 'arbeit.tdf',
          filePath: 'arbeit.tdf',
          storageMode: StorageMode.both,
        ),
        activate: true,
      );
      expect(arbeit.id, equals('arbeit'));
      expect((await repository.loadActiveWorkspace()).id, equals('arbeit'));

      final syncState = WorkspaceSyncState(
        lastSyncedLocalTdf: 'tdf 0.5.1\n',
        lastSyncedRemoteTdf: 'tdf 0.5.1\n',
        deletedLabelTimestamps: <String, DateTime>{
          'work00OkD2': DateTime.utc(2026, 11, 1, 12),
        },
        acknowledgedLocalGeneration: 2,
        acknowledgedRemoteGeneration: 3,
      );
      await repository.saveWorkspaceSyncState('arbeit', syncState);
      expect(
        await repository.loadWorkspaceSyncState('arbeit'),
        equals(syncState),
      );

      final renamed = await repository.renameWorkspace('arbeit', 'Beratung');
      expect(renamed.name, equals('Beratung'));

      final summaries = await repository.loadWorkspaceSummaries();
      expect(
        summaries.map((summary) => (summary.id, summary.name)),
        equals(<(String, String)>[('tasks', 'Tasks'), ('arbeit', 'Beratung')]),
      );

      final remaining = await repository.deleteWorkspace('arbeit');
      expect(remaining.id, equals('tasks'));
      expect(
        await repository.loadWorkspaceSyncState('arbeit'),
        equals(WorkspaceSyncState.empty),
        reason: 'Deleting a workspace must remove its sync state',
      );
    });

    test('enforces workspace name uniqueness, path uniqueness, and WorkspaceErrorKind bounds', () async {
      final repository = InMemorySettingsRepository();

      await expectLater(
        () => repository.createWorkspace('  TASKS  '),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.duplicateName,
          ),
        ),
      );

      await repository.createWorkspace('Arbeit');
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
      );

      await expectLater(
        () => repository.activateWorkspace('missing'),
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
      );
    });
  });

  group('SecureSettingsRepository Binary Persistence & Corruption Recovery', () {
    test('persists TTW\\x01 workspaces and activeId in Base64 and restores WebDavConfig across restarts', () async {
      final fakeStorage = _FakeFlutterSecureStorage();
      final repository = SecureSettingsRepository(storage: fakeStorage);

      final initial = await repository.loadActiveWorkspace();
      expect(initial, equals(AppWorkspace.defaultWorkspace));
      expect(initial.config.storageMode, equals(StorageMode.local));

      await repository.saveConfig(
        const WebDavConfig(
          serverUrl: 'https://cloud.example.com',
          username: 'alice',
          password: 'secret',
          filePath: 'tasks.tdf',
          localFilePath: 'tasks.tdf',
          storageMode: StorageMode.both,
          language: AppLanguage.german,
          themeMode: AppThemeMode.dark,
          themePalette: AppThemePalette.navy,
          timeZoneMode: AppTimeZoneMode.manual,
          manualTimeZoneOffsetMinutes: 120,
          locationEnabled: true,
          diagnosticsEnabled: true,
        ),
      );

      final rawStoredSettings = await fakeStorage.read(key: 't2_settings_v1');
      expect(rawStoredSettings, isNotNull);
      expect(rawStoredSettings?.contains('"'), isFalse);
      expect(rawStoredSettings?.contains(r'\'), isFalse);

      final reloadedRepository = SecureSettingsRepository(storage: fakeStorage);
      final reloaded = await reloadedRepository.loadActiveWorkspace();
      expect(reloaded.id, equals('tasks'));
      expect(reloaded.name, equals('Tasks'));
      expect(reloaded.config.storageMode, equals(StorageMode.both));
      expect(reloaded.config.language, equals(AppLanguage.german));
      expect(reloaded.config.themeMode, equals(AppThemeMode.dark));
      expect(reloaded.config.themePalette, equals(AppThemePalette.navy));
      expect(reloaded.config.timeZoneMode, equals(AppTimeZoneMode.manual));
      expect(reloaded.config.manualTimeZoneOffsetMinutes, equals(120));
      expect(reloaded.config.locationEnabled, isTrue);
      expect(reloaded.config.diagnosticsEnabled, isTrue);

      await reloadedRepository.createWorkspace('Arbeit', activate: true);
      final activeArbeit = await reloadedRepository.loadActiveWorkspace();
      expect(activeArbeit.id, equals('arbeit'));
      expect(activeArbeit.config.localFilePath, equals('arbeit.tdf'));

      await reloadedRepository.renameWorkspace('arbeit', 'Beratung');
      final summariesBeforeDelete = await reloadedRepository
          .loadWorkspaceSummaries();
      expect(
        summariesBeforeDelete.map((summary) => (summary.id, summary.name)),
        equals(<(String, String)>[('tasks', 'Tasks'), ('arbeit', 'Beratung')]),
      );

      await reloadedRepository.activateWorkspace('tasks');
      expect(
        (await reloadedRepository.loadConfig()).storageMode,
        equals(StorageMode.both),
      );

      await reloadedRepository.deleteWorkspace('arbeit');
      final summariesAfterDelete = await reloadedRepository
          .loadWorkspaceSummaries();
      expect(
        summariesAfterDelete.map((summary) => summary.id),
        equals(<String>['tasks']),
      );
    });

    test('persists TTS\\x02 WorkspaceSyncState, migrates legacy TTS\\x01 payloads, and recovers from corrupted storage', () async {
      final fakeStorage = _FakeFlutterSecureStorage();
      final repository = SecureSettingsRepository(storage: fakeStorage);

      expect(
        await repository.loadWorkspaceSyncState('tasks'),
        equals(WorkspaceSyncState.empty),
      );

      final v2State = WorkspaceSyncState(
        lastSyncedLocalTdf: 'tdf 0.5.1\n# local\n',
        lastSyncedRemoteTdf: 'tdf 0.5.1\n# remote\n',
        deletedLabelTimestamps: <String, DateTime>{
          'ops000OkD2': DateTime.utc(2026, 11, 2, 10, 30),
        },
        acknowledgedLocalGeneration: 4,
        acknowledgedRemoteGeneration: 7,
      );
      await repository.saveWorkspaceSyncState('tasks', v2State);
      expect(await repository.loadWorkspaceSyncState('tasks'), equals(v2State));

      // Simulate legacy TTS\x01 payload (without the trailing 16-byte generations and 3-byte v3 suffix).
      final v3Bytes = v2State.toBytes();
      final v1Bytes = Uint8List.fromList(<int>[
        0x54,
        0x54,
        0x53,
        0x01,
        ...v3Bytes.sublist(4, v3Bytes.length - 19),
      ]);
      await fakeStorage.write(
        key: 't2_sync_v1_legacy',
        value: const Base64Service().encodeBytes(v1Bytes),
      );
      final migratedV1 = await repository.loadWorkspaceSyncState('legacy');
      expect(migratedV1.lastSyncedLocalTdf, equals(v2State.lastSyncedLocalTdf));
      expect(
        migratedV1.lastSyncedRemoteTdf,
        equals(v2State.lastSyncedRemoteTdf),
      );
      expect(
        migratedV1.deletedLabelTimestamps,
        equals(v2State.deletedLabelTimestamps),
      );
      expect(migratedV1.acknowledgedLocalGeneration, equals(0));
      expect(migratedV1.acknowledgedRemoteGeneration, equals(0));

      // Corrupted Base64 or binary payloads fall back safely without throwing.
      await fakeStorage.write(
        key: 't2_settings_v1',
        value: '!!!not-valid-base64!!!',
      );
      await fakeStorage.write(
        key: 't2_sync_v1_tasks',
        value: '!!!corrupt-sync-payload!!!',
      );

      expect(
        await repository.loadActiveWorkspace(),
        equals(AppWorkspace.defaultWorkspace),
        reason: 'Corrupted settings payload must fall back to defaultWorkspace',
      );
      expect(
        await repository.loadWorkspaceSyncState('tasks'),
        equals(WorkspaceSyncState.empty),
        reason: 'Corrupted sync state payload must fall back to empty',
      );
    });
  });
}
