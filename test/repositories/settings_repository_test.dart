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
import 'package:tiertask/models/tdf_error.dart';
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

      const digestA =
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      const digestB =
          '2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae';
      final syncState = WorkspaceSyncState(
        lastSyncedLocalTdf: 'tdf 0.8.0\n',
        lastSyncedRemoteTdf: 'tdf 0.8.0\n',
        acknowledgedLocalGeneration: 2,
        acknowledgedRemoteGeneration: 3,
        localSourceDigest: digestA,
        remoteSourceDigest: digestB,
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

    test('persists TTS\\x04 WorkspaceSyncState across all 8 fields, rejects TTS\\x01..TTS\\x03/TTS\\x05, enforces atomic per-target validation, and recovers from corrupted storage', () async {
      final fakeStorage = _FakeFlutterSecureStorage();
      final repository = SecureSettingsRepository(storage: fakeStorage);

      expect(
        await repository.loadWorkspaceSyncState('tasks'),
        equals(WorkspaceSyncState.empty),
      );

      const validLocalDigest =
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      const validRemoteDigest =
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
      final v4State = WorkspaceSyncState(
        lastSyncedLocalTdf: 'tdf 0.8.0\n\ntask 000001OkD2 {\n    name "Local"\n    created 2026-11-01 08:00\n}\n',
        lastSyncedRemoteTdf: 'tdf 0.8.0\n\ntask 000001OkD2 {\n    name "Remote"\n    created 2026-11-01 08:00\n}\n',
        acknowledgedLocalGeneration: 4,
        acknowledgedRemoteGeneration: 7,
        localSourceDigest: validLocalDigest,
        remoteSourceDigest: validRemoteDigest,
        remoteEtag: '"etag-v4"',
        remoteLastModified: 'Mon, 09 Nov 2026 22:00:00 GMT',
      );
      final encodedV4 = v4State.toBytes();
      expect(
        encodedV4.sublist(0, 4),
        equals(<int>[0x54, 0x54, 0x53, 0x04]),
        reason: 'Must write TTS\\x04 header',
      );
      await repository.saveWorkspaceSyncState('tasks', v4State);
      expect(await repository.loadWorkspaceSyncState('tasks'), equals(v4State));

      for (final rejectedVersion in <int>[1, 2, 3, 5]) {
        final legacyBytes = Uint8List.fromList(<int>[
          0x54,
          0x54,
          0x53,
          rejectedVersion,
          ...encodedV4.sublist(4),
        ]);
        await fakeStorage.write(
          key: 't2_sync_v1_v$rejectedVersion',
          value: const Base64Service().encodeBytes(legacyBytes),
        );
        expect(
          await repository.loadWorkspaceSyncState('v$rejectedVersion'),
          equals(WorkspaceSyncState.empty),
          reason:
              'TTS\\x0$rejectedVersion must decode to WorkspaceSyncState.empty',
        );
      }

      for (var shortLen = 0; shortLen < 4; shortLen++) {
        expect(
          WorkspaceSyncState.fromBytes(encodedV4.sublist(0, shortLen)),
          equals(WorkspaceSyncState.empty),
          reason:
              'Payloads shorter than 4 bytes ($shortLen) must decode to empty',
        );
      }

      // Atomic local invalidation preserves valid remote target fields:
      final invalidLocalComment = WorkspaceSyncState(
        lastSyncedLocalTdf: '# comment\ntdf 0.8.0\n',
        acknowledgedLocalGeneration: 1,
        localSourceDigest: validLocalDigest,
        lastSyncedRemoteTdf: 'tdf 0.8.0\n',
        acknowledgedRemoteGeneration: maxTdfSyncGeneration,
        remoteSourceDigest: validRemoteDigest,
        remoteEtag: '"keep-etag"',
        remoteLastModified: 'Tue, 10 Nov 2026 10:00:00 GMT',
      );
      expect(invalidLocalComment.lastSyncedLocalTdf, isNull);
      expect(invalidLocalComment.acknowledgedLocalGeneration, isNull);
      expect(invalidLocalComment.localSourceDigest, isNull);
      expect(invalidLocalComment.lastSyncedRemoteTdf, equals('tdf 0.8.0\n'));
      expect(
        invalidLocalComment.acknowledgedRemoteGeneration,
        equals(maxTdfSyncGeneration),
      );
      expect(invalidLocalComment.remoteSourceDigest, equals(validRemoteDigest));
      expect(invalidLocalComment.remoteEtag, equals('"keep-etag"'));

      // Atomic remote invalidation preserves valid local target fields:
      final invalidRemoteGen = WorkspaceSyncState(
        lastSyncedLocalTdf: 'tdf 0.8.0\n',
        acknowledgedLocalGeneration: 0,
        localSourceDigest: validLocalDigest,
        lastSyncedRemoteTdf: 'tdf 0.8.0\n',
        acknowledgedRemoteGeneration: maxTdfSyncGeneration + 1,
        remoteSourceDigest: validRemoteDigest,
        remoteEtag: '"drop-etag"',
        remoteLastModified: 'Tue, 10 Nov 2026 10:00:00 GMT',
      );
      expect(invalidRemoteGen.lastSyncedLocalTdf, equals('tdf 0.8.0\n'));
      expect(invalidRemoteGen.acknowledgedLocalGeneration, equals(0));
      expect(invalidRemoteGen.localSourceDigest, equals(validLocalDigest));
      expect(invalidRemoteGen.lastSyncedRemoteTdf, isNull);
      expect(invalidRemoteGen.acknowledgedRemoteGeneration, isNull);
      expect(invalidRemoteGen.remoteSourceDigest, isNull);
      expect(invalidRemoteGen.remoteEtag, isNull);
      expect(invalidRemoteGen.remoteLastModified, isNull);

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
