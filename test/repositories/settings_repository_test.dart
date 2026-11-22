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

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/app_build_profile.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/settings_codec.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/models/workspace_sync_state.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/services/base64_service.dart';

class _TrackingFakeSecureStorage extends FlutterSecureStorage {
  _TrackingFakeSecureStorage([Map<String, String>? initialValues])
    : store = Map<String, String>.from(initialValues ?? const {});

  final Map<String, String> store;
  final List<String> readKeys = <String>[];
  final List<String> writeKeys = <String>[];
  final List<String> deleteKeys = <String>[];

  Exception? Function(String key)? readErrorForKey;
  Exception? Function(String key, String? value)? writeErrorForKey;

  void resetCounts() {
    readKeys.clear();
    writeKeys.clear();
    deleteKeys.clear();
  }

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
    readKeys.add(key);
    final error = readErrorForKey?.call(key);
    if (error != null) {
      throw error;
    }
    return store[key];
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
      deleteKeys.add(key);
    } else {
      writeKeys.add(key);
    }
    final error = writeErrorForKey?.call(key, value);
    if (error != null) {
      throw error;
    }
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }
}

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('tiertask_settings_test_');
    AppLogger.resetForTesting();
  });

  tearDown(() {
    AppLogger.resetForTesting();
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  group('AppLanguage, AppThemeMode, StorageMode & WebDavConfig Defaults', () {
    test('resolves English as default and honors German or System locale settings and JSON tokens', () {
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

      expect(AppLanguage.tryParseJson('german'), equals(AppLanguage.german));
      expect(AppLanguage.tryParseJson('english'), equals(AppLanguage.english));
      expect(AppLanguage.tryParseJson('system'), equals(AppLanguage.system));
      expect(AppLanguage.tryParseJson('unknown'), isNull);

      expect(AppThemeMode.tryParseJson('light'), equals(AppThemeMode.light));
      expect(AppThemeMode.tryParseJson('dark'), equals(AppThemeMode.dark));
      expect(AppThemeMode.tryParseJson('system'), equals(AppThemeMode.system));
      expect(AppThemeMode.tryParseJson('unknown'), isNull);

      expect(StorageMode.tryParseJson('local'), equals(StorageMode.local));
      expect(StorageMode.tryParseJson('webdav'), equals(StorageMode.webdav));
      expect(StorageMode.tryParseJson('both'), equals(StorageMode.both));
      expect(StorageMode.tryParseJson('unknown'), isNull);

      const defaultConfig = WebDavConfig();
      expect(defaultConfig.themeMode, equals(AppThemeMode.system));
      expect(defaultConfig.storageMode, equals(StorageMode.local));
      expect(defaultConfig.localFilePath, equals('tasks.tdf'));
      expect(defaultConfig.filePath, equals('tasks.tdf'));
      expect(defaultConfig.isConfigured, isTrue);
    });
  });

  group('InMemorySettingsRepository', () {
    test('creates, activates, renames, updates config, deletes workspaces, and consumes one-shot recovery notices', () async {
      final repository = InMemorySettingsRepository.withRecoveryNotice(
        initialConfig: const WebDavConfig(
          language: AppLanguage.german,
          themeMode: AppThemeMode.dark,
        ),
        recoveryNotice: const SettingsRecoveryNotice(
          kind: SettingsRecoveryKind.recoveredFromBackup,
          quarantinedFilePath: '/tmp/settings.json.corrupt.20261120T120000Z',
        ),
      );

      expect(
        repository.takeLastRecoveryNotice(),
        equals(
          const SettingsRecoveryNotice(
            kind: SettingsRecoveryKind.recoveredFromBackup,
            quarantinedFilePath: '/tmp/settings.json.corrupt.20261120T120000Z',
          ),
        ),
      );
      expect(
        repository.takeLastRecoveryNotice(),
        isNull,
        reason: 'takeLastRecoveryNotice must be consumed once',
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
          const WebDavConfig(localFilePath: 'arbeit.tdf'),
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

  group('SecureSettingsRepository Split JSON Persistence & Secret Hygiene', () {
    test('persists settings.json without passwords, stores per-workspace passwords in secure storage, and preserves unknown keys', () async {
      final settingsDir = Directory('${tempRoot.path}/release_data')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/locks')
        ..createSync(recursive: true);
      final fakeStorage = _TrackingFakeSecureStorage();
      final repository = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );

      final initial = await repository.loadActiveWorkspace();
      expect(initial, equals(AppWorkspace.defaultWorkspace));

      const secretPassword = r'p"a\\s$w0rd!ÄÖÜß';
      await repository.saveConfig(
        const WebDavConfig(
          serverUrl: 'https://cloud.example.com',
          username: 'alice',
          password: secretPassword,
          storageMode: StorageMode.both,
          language: AppLanguage.german,
          themeMode: AppThemeMode.dark,
          themePalette: AppThemePalette.plumUmber,
          timeZoneMode: AppTimeZoneMode.manual,
          manualTimeZoneOffsetMinutes: 63,
          locationEnabled: true,
          diagnosticsEnabled: true,
          logLevel: LogLevel.warn,
          logStorageMode: StorageMode.both,
          localWatchEnabled: false,
          dueLeadWindow: DueLeadWindow.atDue,
        ),
      );

      final settingsFile = File('${settingsDir.path}/settings.json');
      expect(settingsFile.existsSync(), isTrue);
      final rawJson = settingsFile.readAsStringSync();
      expect(
        rawJson.contains(secretPassword),
        isFalse,
        reason: 'settings.json must never contain WebDAV password',
      );
      expect(rawJson.contains('"hasWebDavPassword": true'), isTrue);
      expect(fakeStorage.store['t2_webdav_pw_tasks'], equals(secretPassword));
      expect(
        fakeStorage.store.containsKey('t2_settings_v1'),
        isFalse,
        reason: 'New saves must never write legacy t2_settings_v1 key',
      );

      // Inject unknown root and workspace fields into settings.json to verify lossless preservation:
      final decodedMap = jsonDecode(rawJson) as Map<String, Object?>;
      decodedMap['futureRootMeta'] = <String, Object?>{'v': 2};
      final rawWsList = decodedMap['workspaces'];
      expect(rawWsList, isA<List<Object?>>());
      if (rawWsList is List<Object?>) {
        final rawFirstWs = rawWsList.first;
        expect(rawFirstWs, isA<Map<String, Object?>>());
        if (rawFirstWs is Map<String, Object?>) {
          rawFirstWs['futureWorkspaceMeta'] = 'keep-me';
        }
      }
      settingsFile.writeAsStringSync('${jsonEncode(decodedMap)}\n');

      final reloadedRepository = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );
      final reloaded = await reloadedRepository.loadActiveWorkspace();
      expect(reloaded.config.password, equals(secretPassword));
      expect(reloaded.config.manualTimeZoneOffsetMinutes, equals(63));
      expect(reloaded.config.dueLeadWindow, equals(DueLeadWindow.atDue));
      expect(reloaded.config.localWatchEnabled, isFalse);

      // Mutate and verify unknown fields survive:
      await reloadedRepository.renameWorkspace('tasks', 'Main Tasks');
      final afterRenameJson =
          jsonDecode(settingsFile.readAsStringSync()) as Map<String, Object?>;
      expect(
        afterRenameJson['futureRootMeta'],
        equals(<String, Object?>{'v': 2}),
      );
      final rawAfterRenameWorkspaces = afterRenameJson['workspaces'];
      expect(rawAfterRenameWorkspaces, isA<List<Object?>>());
      if (rawAfterRenameWorkspaces is List<Object?>) {
        final rawFirstAfterRename = rawAfterRenameWorkspaces.first;
        expect(rawFirstAfterRename, isA<Map<String, Object?>>());
        if (rawFirstAfterRename is Map<String, Object?>) {
          expect(rawFirstAfterRename['futureWorkspaceMeta'], equals('keep-me'));
        }
      }

      // Create second workspace with password, then delete it and verify password + sync cleanup:
      await reloadedRepository.createWorkspace(
        'Arbeit',
        config: const WebDavConfig(
          localFilePath: 'arbeit.tdf',
          filePath: 'arbeit.tdf',
          serverUrl: 'https://work.example.com',
          username: 'bob',
          password: 'work-password',
          storageMode: StorageMode.both,
        ),
        activate: true,
      );
      expect(fakeStorage.store['t2_webdav_pw_arbeit'], equals('work-password'));
      await reloadedRepository.deleteWorkspace('arbeit');
      expect(
        fakeStorage.store.containsKey('t2_webdav_pw_arbeit'),
        isFalse,
        reason: 'Deleting workspace must delete its per-workspace password key',
      );
    });

    test('never touches FlutterSecureStorage for local-only workspaces or unchanged-password UI toggles', () async {
      final settingsDir = Directory('${tempRoot.path}/local_only')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/locks')
        ..createSync(recursive: true);
      final fakeStorage = _TrackingFakeSecureStorage();
      final repository = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );

      // Persist initial local-only settings.json:
      await repository.saveConfig(
        const WebDavConfig(language: AppLanguage.german),
      );
      fakeStorage.resetCounts();

      await repository.loadActiveWorkspace();
      await repository.loadWorkspaceSummaries();
      await repository.renameWorkspace('tasks', 'Lokal');
      await repository.createWorkspace('Privat', activate: true);
      await repository.activateWorkspace('tasks');
      await repository.saveConfig(
        const WebDavConfig(
          language: AppLanguage.english,
          themeMode: AppThemeMode.dark,
        ),
      );

      expect(
        fakeStorage.readKeys,
        isEmpty,
        reason: 'Local-only workspaces must perform zero keyring reads',
      );
      expect(
        fakeStorage.writeKeys,
        isEmpty,
        reason: 'Local-only workspaces must perform zero keyring writes',
      );
      expect(
        fakeStorage.deleteKeys,
        isEmpty,
        reason: 'Local-only workspaces must perform zero keyring deletes',
      );

      // Now store a WebDAV password and verify UI toggle with unchanged password does zero keyring writes:
      const webdavConfig = WebDavConfig(
        serverUrl: 'https://cloud.example.com',
        username: 'alice',
        password: 'unchanged-password',
        storageMode: StorageMode.both,
      );
      await repository.saveConfig(webdavConfig);
      fakeStorage.resetCounts();

      await repository.saveConfig(
        webdavConfig.copyWith(themePalette: AppThemePalette.plumUmber),
      );
      await repository.loadActiveWorkspace();
      await repository.loadWorkspaceSummaries();

      expect(
        fakeStorage.writeKeys,
        isEmpty,
        reason: 'UI preference save with unchanged cached password must perform zero keyring writes',
      );
      expect(
        fakeStorage.readKeys,
        isEmpty,
        reason: 'Cached session password and summaries must avoid redundant keyring reads',
      );
    });

    test('protects unreadable keyring passwords on unrelated preference saves and throws credentialStorageUnavailable on write failure', () async {
      final settingsDir = Directory('${tempRoot.path}/locked_keyring')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/locks')
        ..createSync(recursive: true);
      final fakeStorage = _TrackingFakeSecureStorage();
      final setupRepo = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );
      await setupRepo.saveConfig(
        const WebDavConfig(
          serverUrl: 'https://cloud.example.com',
          username: 'alice',
          password: 'kept-safe-password',
          storageMode: StorageMode.both,
        ),
      );

      // Simulate locked OS keyring during startup read on a fresh repository instance:
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.debug,
        persistToDisk: false,
      );
      fakeStorage.readErrorForKey = (key) =>
          PlatformException(code: 'KEYRING_LOCKED', message: 'Keyring locked');
      final lockedRepo = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );
      final loaded = await lockedRepo.loadActiveWorkspace();
      expect(
        loaded.config.password,
        isEmpty,
        reason: 'Locked keyring must boot with empty password so local tasks stay accessible',
      );
      expect(
        AppLogger.lines.any(
          (line) => line.contains('settings.secret.read_failed'),
        ),
        isTrue,
        reason: 'Locked keyring read must emit settings.secret.read_failed',
      );

      // Unrelated preference save with empty password must NOT delete the unreadable keyring entry:
      fakeStorage.resetCounts();
      await lockedRepo.saveConfig(
        loaded.config.copyWith(themeMode: AppThemeMode.dark),
      );
      expect(
        fakeStorage.deleteKeys,
        isEmpty,
        reason: 'Unrelated preference save must not delete an unreadable keyring password',
      );
      expect(
        fakeStorage.store['t2_webdav_pw_tasks'],
        equals('kept-safe-password'),
      );
      final jsonAfterPrefSave = File('${settingsDir.path}/settings.json')
          .readAsStringSync();
      expect(
        jsonAfterPrefSave.contains('"hasWebDavPassword": true'),
        isTrue,
        reason: 'hasWebDavPassword must remain true while keyring secret is unreadable',
      );

      // Simulate keyring write failure: must throw credentialStorageUnavailable without mutating settings.json:
      final settingsBeforeFailedWrite = File(
        '${settingsDir.path}/settings.json',
      ).readAsStringSync();
      fakeStorage.writeErrorForKey = (key, value) => PlatformException(
        code: 'KEYRING_UNAVAILABLE',
        message: 'Cannot write',
      );
      await expectLater(
        () => lockedRepo.saveConfig(
          loaded.config.copyWith(
            themeMode: AppThemeMode.light,
            password: 'new-password',
          ),
        ),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.credentialStorageUnavailable,
          ),
        ),
      );
      expect(
        File('${settingsDir.path}/settings.json').readAsStringSync(),
        equals(settingsBeforeFailedWrite),
        reason: 'Failed password write must leave settings.json untouched',
      );

      // Once keyring unlocks and user saves a new password, unreadable marker clears:
      fakeStorage.readErrorForKey = null;
      fakeStorage.writeErrorForKey = null;
      await lockedRepo.saveConfig(
        loaded.config.copyWith(password: 'updated-password'),
      );
      expect(
        fakeStorage.store['t2_webdav_pw_tasks'],
        equals('updated-password'),
      );
    });
  });

  group('SecureSettingsRepository Backup Rotation, Quarantine, Future Schema & Symlink Defense', () {
    test('rotates settings.json.bak, quarantines corrupt primary, and restores from backup with one-shot notice', () async {
      final settingsDir = Directory('${tempRoot.path}/backup_recovery')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/locks')
        ..createSync(recursive: true);
      final fakeStorage = _TrackingFakeSecureStorage();
      final fixedUtc = DateTime.utc(2026, 11, 20, 14, 30, 45);
      final repository = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
        clock: () => fixedUtc,
      );

      // First save creates settings.json; second save rotates previous valid settings.json to settings.json.bak:
      await repository.saveConfig(
        const WebDavConfig(language: AppLanguage.german),
      );
      await repository.saveConfig(
        const WebDavConfig(
          language: AppLanguage.german,
          themeMode: AppThemeMode.dark,
        ),
      );
      final primaryFile = File('${settingsDir.path}/settings.json');
      final backupFile = File('${settingsDir.path}/settings.json.bak');
      expect(backupFile.existsSync(), isTrue);

      // Corrupt primary settings.json:
      primaryFile.writeAsStringSync('{corrupt-json!!!');

      final recoveryRepo = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
        clock: () => fixedUtc,
      );
      final recovered = await recoveryRepo.loadActiveWorkspace();
      expect(
        recovered.config.language,
        equals(AppLanguage.german),
        reason: 'Backup restoration must recover previously saved language',
      );
      final expectedQuarantine =
          '${settingsDir.path}/settings.json.corrupt.20261120T143045Z';
      expect(
        File(expectedQuarantine).existsSync(),
        isTrue,
        reason: 'Corrupt primary must be quarantined before backup restoration',
      );
      expect(
        File(expectedQuarantine).readAsStringSync(),
        equals('{corrupt-json!!!'),
      );
      expect(
        recoveryRepo.takeLastRecoveryNotice(),
        equals(
          SettingsRecoveryNotice(
            kind: SettingsRecoveryKind.recoveredFromBackup,
            quarantinedFilePath: expectedQuarantine,
          ),
        ),
      );
      expect(recoveryRepo.takeLastRecoveryNotice(), isNull);
    });

    test('quarantines corrupt primary and backup, writes initial settings.json without reading keyring, and handles missing primary with valid backup', () async {
      final settingsDir = Directory('${tempRoot.path}/double_corrupt')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/locks')
        ..createSync(recursive: true);
      final fakeStorage = _TrackingFakeSecureStorage();
      final primaryFile = File('${settingsDir.path}/settings.json')
        ..writeAsStringSync('not-json-primary');
      final backupFile = File('${settingsDir.path}/settings.json.bak')
        ..writeAsStringSync('not-json-backup');
      final fixedUtc = DateTime.utc(2026, 11, 20, 15);

      final repository = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
        clock: () => fixedUtc,
      );
      final workspace = await repository.loadActiveWorkspace();
      expect(
        workspace,
        equals(AppWorkspace.defaultWorkspace),
        reason: 'Double-corrupt recovery must reset to default workspace',
      );
      expect(
        primaryFile.existsSync(),
        isTrue,
        reason: 'Reset after quarantine must persist PersistedSettingsDocument.initial to settings.json',
      );
      expect(
        File('${settingsDir.path}/settings.json.corrupt.20261120T150000Z')
            .existsSync(),
        isTrue,
      );
      expect(
        File('${settingsDir.path}/settings.json.bak.corrupt.20261120T150000Z')
            .existsSync(),
        isTrue,
      );
      expect(
        fakeStorage.readKeys,
        isEmpty,
        reason: 'Double-corrupt recovery must not query secure storage',
      );
      expect(
        repository.takeLastRecoveryNotice()?.kind,
        equals(SettingsRecoveryKind.resetAfterQuarantine),
      );

      // Missing primary with valid backup restores from backup:
      await repository.saveConfig(
        const WebDavConfig(themePalette: AppThemePalette.plumUmber),
      );
      await repository.saveConfig(
        const WebDavConfig(
          themePalette: AppThemePalette.plumUmber,
          themeMode: AppThemeMode.dark,
        ),
      );
      primaryFile.deleteSync();
      expect(backupFile.existsSync(), isTrue);

      final restoredFromBak = await repository.loadActiveWorkspace();
      expect(
        restoredFromBak.config.themePalette,
        equals(AppThemePalette.plumUmber),
      );
      expect(primaryFile.existsSync(), isTrue);
      expect(
        repository.takeLastRecoveryNotice()?.kind,
        equals(SettingsRecoveryKind.recoveredFromBackup),
      );
    });

    test('refuses to quarantine or overwrite unsupported future schemaVersion in primary or backup', () async {
      final settingsDir = Directory('${tempRoot.path}/future_schema')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/locks')
        ..createSync(recursive: true);
      final fakeStorage = _TrackingFakeSecureStorage();
      const futurePayload =
          '{\n  "schemaVersion": 2,\n  "activeWorkspaceId": "tasks",\n  "workspaces": []\n}\n';
      final primaryFile = File('${settingsDir.path}/settings.json')
        ..writeAsStringSync(futurePayload);

      final repository = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );

      await expectLater(
        () => repository.loadActiveWorkspace(),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.unsupportedSettingsSchemaVersion,
          ),
        ),
      );
      expect(
        primaryFile.readAsStringSync(),
        equals(futurePayload),
        reason:
            'Future schema primary file must remain byte-for-byte untouched',
      );
      expect(
        settingsDir.listSync().where((e) => e.path.contains('.corrupt.')),
        isEmpty,
        reason: 'Future schema file must never be quarantined',
      );

      // Now test missing primary with future schema in settings.json.bak:
      primaryFile.deleteSync();
      final backupFile = File('${settingsDir.path}/settings.json.bak')
        ..writeAsStringSync(futurePayload);
      await expectLater(
        () => repository.loadActiveWorkspace(),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.unsupportedSettingsSchemaVersion,
          ),
        ),
      );
      expect(backupFile.readAsStringSync(), equals(futurePayload));
      expect(primaryFile.existsSync(), isFalse);
    });

    test('rejects symlink or directory at settings.json without following or clobbering target', () async {
      final settingsDir = Directory('${tempRoot.path}/symlink_defense')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/locks')
        ..createSync(recursive: true);
      final fakeStorage = _TrackingFakeSecureStorage();
      final repository = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );

      // Directory at settings.json:
      final dirTarget = Directory('${settingsDir.path}/settings.json')
        ..createSync();
      await expectLater(
        () => repository.loadActiveWorkspace(),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.settingsPersistenceFailed,
          ),
        ),
      );
      expect(dirTarget.existsSync(), isTrue);
      dirTarget.deleteSync();

      // Symlink at settings.json:
      final sensitiveTarget = File('${tempRoot.path}/sensitive.txt')
        ..writeAsStringSync('do-not-touch');
      final linkPath = '${settingsDir.path}/settings.json';
      Link(linkPath).createSync(sensitiveTarget.path);
      await expectLater(
        () => repository.loadActiveWorkspace(),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.settingsPersistenceFailed,
          ),
        ),
      );
      expect(
        sensitiveTarget.readAsStringSync(),
        equals('do-not-touch'),
        reason: 'Symlink target must never be read or clobbered',
      );
      expect(
        FileSystemEntity.typeSync(linkPath, followLinks: false),
        equals(FileSystemEntityType.link),
        reason: 'Symlink itself must not be quarantined or replaced',
      );
    });

    test('serializes concurrent createWorkspace, saveConfig, and renameWorkspace calls with zero lost updates', () async {
      final settingsDir = Directory('${tempRoot.path}/concurrent')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/locks')
        ..createSync(recursive: true);
      final fakeStorage = _TrackingFakeSecureStorage();
      final repository = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );
      await repository.saveConfig(const WebDavConfig());

      await Future.wait<Object?>(<Future<Object?>>[
        repository.createWorkspace('Alpha'),
        repository.createWorkspace('Beta'),
        repository.saveConfig(const WebDavConfig(themeMode: AppThemeMode.dark)),
        repository.renameWorkspace('tasks', 'Primary'),
      ]);

      final summaries = await repository.loadWorkspaceSummaries();
      expect(
        summaries.map((s) => (s.id, s.name)).toSet(),
        equals(<(String, String)>{
          ('tasks', 'Primary'),
          ('alpha', 'Alpha'),
          ('beta', 'Beta'),
        }),
        reason: 'All concurrent mutations must be serialized with zero lost updates',
      );
      final active = await repository.loadActiveWorkspace();
      expect(active.config.themeMode, equals(AppThemeMode.dark));
    });
  });

  group('SecureSettingsRepository Android filesDir & Sync State', () {
    test('resolves Android Context.filesDir via resolver and throws settingsPersistenceFailed when resolver fails', () async {
      final androidFilesDir = Directory('${tempRoot.path}/android_files')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/locks')
        ..createSync(recursive: true);
      final fakeStorage = _TrackingFakeSecureStorage();
      final repository = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.dev,
        hostLockDirectoryOverride: lockDir.path,
        androidFilesDirectoryResolver: () async => androidFilesDir.path,
      );

      await repository.saveConfig(
        const WebDavConfig(language: AppLanguage.german),
      );
      final expectedFile = File(
        '${androidFilesDir.path}/tiertask-dev/settings.json',
      );
      expect(
        expectedFile.existsSync(),
        isTrue,
        reason: 'Android resolver must write to <filesDir>/<dataDirectoryName>/settings.json',
      );

      // Resolver returning null or empty or throwing must fail with settingsPersistenceFailed:
      for (final brokenResolver in <Future<String?> Function()>[
        () async => null,
        () async => '   ',
        () async => throw PlatformException(code: 'NO_FILES_DIR'),
      ]) {
        final brokenRepo = SecureSettingsRepository(
          storage: fakeStorage,
          buildProfile: AppBuildProfile.release,
          hostLockDirectoryOverride: lockDir.path,
          androidFilesDirectoryResolver: brokenResolver,
        );
        await expectLater(
          () => brokenRepo.loadActiveWorkspace(),
          throwsA(
            isA<WorkspaceException>().having(
              (error) => error.kind,
              'kind',
              WorkspaceErrorKind.settingsPersistenceFailed,
            ),
          ),
          reason: 'Broken Android filesDir resolver must fail with settingsPersistenceFailed rather than falling back to cacheDir',
        );
      }
    });

    test('persists TTS\\x04 WorkspaceSyncState across all 8 fields, rejects TTS\\x01..TTS\\x03/TTS\\x05, and isolates dev from release profiles', () async {
      final releaseDir = Directory('${tempRoot.path}/profile_release')
        ..createSync(recursive: true);
      final devDir = Directory('${tempRoot.path}/profile_dev')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/locks')
        ..createSync(recursive: true);
      final fakeStorage = _TrackingFakeSecureStorage();

      final releaseRepo = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: releaseDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );
      final devRepo = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.dev,
        settingsDirectoryPath: devDir.path,
        hostLockDirectoryOverride: lockDir.path,
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
      expect(encodedV4.sublist(0, 4), equals(<int>[0x54, 0x54, 0x53, 0x04]));
      await releaseRepo.saveWorkspaceSyncState('tasks', v4State);
      expect(
        await releaseRepo.loadWorkspaceSyncState('tasks'),
        equals(v4State),
      );
      expect(
        await devRepo.loadWorkspaceSyncState('tasks'),
        equals(WorkspaceSyncState.empty),
      );

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
          await releaseRepo.loadWorkspaceSyncState('v$rejectedVersion'),
          equals(WorkspaceSyncState.empty),
        );
      }

      await releaseRepo.saveConfig(
        const WebDavConfig(
          serverUrl: 'https://prod.example.com',
          username: 'prod-user',
          password: 'prod-password',
          localFilePath: 'prod.tdf',
        ),
      );
      await devRepo.saveConfig(
        const WebDavConfig(
          serverUrl: 'https://dev.example.com',
          username: 'dev-user',
          password: 'dev-password',
          localFilePath: 'dev.tdf',
        ),
      );

      expect(fakeStorage.store['t2_webdav_pw_tasks'], equals('prod-password'));
      expect(
        fakeStorage.store['t2_dev_webdav_pw_tasks'],
        equals('dev-password'),
      );
      expect(
        (await releaseRepo.loadConfig()).serverUrl,
        equals('https://prod.example.com'),
      );
      expect(
        (await devRepo.loadConfig()).serverUrl,
        equals('https://dev.example.com'),
      );
    });

    test('compresses large WorkspaceSyncState payloads exceeding 1 MiB combined raw size, stays backward-compatible with uncompressed TTS\\x04, and rejects oversized gzip decompression bombs', () async {
      final fakeStorage = _TrackingFakeSecureStorage();
      final tempDir = await Directory.systemTemp.createTemp(
        'tiertask_sync_state_large_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final repo = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: '${tempDir.path}/cfg',
        hostLockDirectoryOverride: '${tempDir.path}/locks',
      );

      // Build a ~600 KB valid canonical TDF document so combined local + remote raw payload > 1_048_576 bytes:
      final buffer = StringBuffer('tdf 0.8.0\n');
      for (var i = 0; i < 10000; i++) {
        buffer.writeln(
          '# padded diagnostic baseline comment line number $i ----',
        );
      }
      final largeTdf = buffer.toString();
      expect(largeTdf.length, greaterThan(550000));
      const validDigest =
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      final largeState = WorkspaceSyncState(
        lastSyncedLocalTdf: largeTdf,
        lastSyncedRemoteTdf: largeTdf,
        acknowledgedLocalGeneration: 2,
        acknowledgedRemoteGeneration: 2,
        localSourceDigest: validDigest,
        remoteSourceDigest: validDigest,
        remoteEtag: '"etag-large"',
      );
      final rawBytes = largeState.toBytes();
      expect(
        rawBytes.length,
        greaterThan(Base64Service.defaultMaxInputBytes),
        reason: 'Combined local+remote payload must exceed 1 MiB to exercise overflow fix',
      );

      await repo.saveWorkspaceSyncState('tasks', largeState);
      final syncFile = File('${tempDir.path}/cfg/sync_state_tasks.tts');
      expect(
        syncFile.existsSync(),
        isTrue,
        reason:
            'Sync state must be stored in host-local sync_state_<id>.tts file',
      );
      expect(
        fakeStorage.store.containsKey('t2_sync_v1_tasks'),
        isFalse,
        reason: 'Saving sync state must never write to FlutterSecureStorage',
      );
      expect(
        syncFile.lengthSync(),
        lessThan(rawBytes.length ~/ 4),
        reason: 'Gzip compression must shrink repetitive dual TDF sync state dramatically',
      );
      if (Platform.isLinux) {
        expect(
          syncFile.statSync().mode & 0x1FF,
          equals(0x180),
          reason: 'Host-local .tts sync state file must use 0600 permissions',
        );
      }

      // Reload from a fresh repository instance to verify on-disk round-trip and string deduplication:
      final freshRepo = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: '${tempDir.path}/cfg',
        hostLockDirectoryOverride: '${tempDir.path}/locks',
      );
      final reloadedLarge = await freshRepo.loadWorkspaceSyncState('tasks');
      expect(
        reloadedLarge,
        equals(largeState),
        reason:
            'Compressed >1 MiB WorkspaceSyncState must round-trip losslessly',
      );
      expect(
        identical(
          reloadedLarge.lastSyncedLocalTdf,
          reloadedLarge.lastSyncedRemoteTdf,
        ),
        isTrue,
        reason: 'Identical local and remote baselines must share one String reference in memory',
      );

      // Backward compatibility: pre-existing uncompressed TTS\x04 entry in legacy secure storage must migrate to .tts and delete legacy key.
      final smallState = WorkspaceSyncState(
        lastSyncedLocalTdf: 'tdf 0.8.0\n',
        acknowledgedLocalGeneration: 1,
        localSourceDigest: validDigest,
      );
      await fakeStorage.write(
        key: 't2_sync_v1_legacy_uncompressed',
        value: const Base64Service().encodeBytes(smallState.toBytes()),
      );
      expect(
        await repo.loadWorkspaceSyncState('legacy_uncompressed'),
        equals(smallState),
        reason:
            'Pre-existing uncompressed TTS\\x04 entries must remain readable',
      );
      expect(
        File('${tempDir.path}/cfg/sync_state_legacy_uncompressed.tts')
            .existsSync(),
        isTrue,
        reason: 'Legacy secure-storage sync state must migrate to .tts file',
      );
      expect(
        fakeStorage.store.containsKey('t2_sync_v1_legacy_uncompressed'),
        isFalse,
        reason:
            'Legacy secure-storage sync key must be deleted after migration',
      );

      // Bounded decompression guard: gzip payload expanding past WorkspaceSyncState.maxSerializedBytes must return empty cleanly and log WARN.
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.warn,
        persistToDisk: false,
      );
      final oversizedPayload = Uint8List(
        WorkspaceSyncState.maxSerializedBytes + 4096,
      );
      final compressedBomb = gzip.encode(oversizedPayload);
      await fakeStorage.write(
        key: 't2_sync_v1_bomb',
        value: const Base64Service().encodeBytes(compressedBomb),
      );
      expect(
        await repo.loadWorkspaceSyncState('bomb'),
        equals(WorkspaceSyncState.empty),
        reason: 'Decompression exceeding maxSerializedBytes must fail safely to empty state',
      );
      expect(
        AppLogger.lines.any(
          (line) =>
              line.contains('[WARN ]') &&
              line.contains('settings.sync_state.corrupt'),
        ),
        isTrue,
        reason: 'Corrupt sync state fallback must emit a WARN diagnostic event',
      );

      // Direct on-disk .tts gzip bomb must also fail safely to empty state.
      File('${tempDir.path}/cfg/sync_state_disk_bomb.tts')
          .writeAsBytesSync(compressedBomb, flush: true);
      expect(
        await repo.loadWorkspaceSyncState('disk_bomb'),
        equals(WorkspaceSyncState.empty),
        reason: 'On-disk gzip bomb .tts file must fail safely to empty state',
      );

      // Truncated gzip stream must also fail safely to empty state without uncaught FormatException.
      final truncatedGzip = compressedBomb.sublist(0, 24);
      await fakeStorage.write(
        key: 't2_sync_v1_truncated',
        value: const Base64Service().encodeBytes(truncatedGzip),
      );
      expect(
        await repo.loadWorkspaceSyncState('truncated'),
        equals(WorkspaceSyncState.empty),
        reason: 'Truncated gzip payload must fail safely to empty state',
      );
    });

    test('deduplicates identical local/remote baselines in WorkspaceSyncState.fromBytes, caches .tts sync states in memory, cleans up empty/deleted workspaces, and rejects invalid workspaceIds or symlinks', () async {
      final settingsDir = Directory('${tempRoot.path}/sync_cache')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/sync_cache_locks')
        ..createSync(recursive: true);
      final fakeStorage = _TrackingFakeSecureStorage();
      final repository = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );

      const digest =
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      final sharedBaseline = String.fromCharCodes(
        'tdf 0.8.0\n\ntask 000001OkD2 {\n    name "Shared"\n    created 2026-11-01 08:00\n}\n'
            .codeUnits,
      );
      final copyBaseline = String.fromCharCodes(sharedBaseline.codeUnits);
      expect(identical(sharedBaseline, copyBaseline), isFalse);

      final constructed = WorkspaceSyncState(
        lastSyncedLocalTdf: sharedBaseline,
        lastSyncedRemoteTdf: copyBaseline,
        acknowledgedLocalGeneration: 3,
        acknowledgedRemoteGeneration: 3,
        localSourceDigest: digest,
        remoteSourceDigest: digest,
        remoteEtag: '"etag-shared"',
      );
      expect(
        identical(
          constructed.lastSyncedLocalTdf,
          constructed.lastSyncedRemoteTdf,
        ),
        isTrue,
        reason: 'WorkspaceSyncState constructor must deduplicate identical local and remote baselines',
      );

      // Verify both Uint8List and plain List<int> wire decoding produce deduplicated references.
      final wireBytes = constructed.toBytes();
      final decodedFromTyped = WorkspaceSyncState.fromBytes(wireBytes);
      final decodedFromList = WorkspaceSyncState.fromBytes(
        List<int>.of(wireBytes),
      );
      expect(decodedFromTyped, equals(constructed));
      expect(decodedFromList, equals(constructed));
      expect(
        identical(
          decodedFromTyped.lastSyncedLocalTdf,
          decodedFromTyped.lastSyncedRemoteTdf,
        ),
        isTrue,
      );
      expect(
        identical(
          decodedFromList.lastSyncedLocalTdf,
          decodedFromList.lastSyncedRemoteTdf,
        ),
        isTrue,
      );

      // Save to .tts file: zero FlutterSecureStorage calls.
      fakeStorage.resetCounts();
      await repository.saveWorkspaceSyncState('tasks', constructed);
      expect(fakeStorage.readKeys, isEmpty);
      expect(fakeStorage.writeKeys, isEmpty);
      expect(fakeStorage.deleteKeys, isEmpty);

      final syncFile = File('${settingsDir.path}/sync_state_tasks.tts');
      expect(syncFile.existsSync(), isTrue);

      // In-memory cache avoids repeated disk reads on same repository instance.
      final readsBeforeCacheHit = repository.syncStateDiskReadCountForTesting;
      expect(
        await repository.loadWorkspaceSyncState('tasks'),
        equals(constructed),
      );
      expect(
        await repository.loadWorkspaceSyncState('tasks'),
        equals(constructed),
      );
      expect(
        repository.syncStateDiskReadCountForTesting,
        equals(readsBeforeCacheHit),
        reason:
            'In-memory cache must serve saved sync state without disk reads',
      );
      expect(fakeStorage.readKeys, isEmpty);

      // Fresh repository reads once from disk, then serves subsequent loads from cache.
      final freshRepo = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );
      expect(
        await freshRepo.loadWorkspaceSyncState('tasks'),
        equals(constructed),
      );
      expect(freshRepo.syncStateDiskReadCountForTesting, equals(1));
      expect(
        await freshRepo.loadWorkspaceSyncState('tasks'),
        equals(constructed),
      );
      expect(
        freshRepo.syncStateDiskReadCountForTesting,
        equals(1),
        reason: 'Second load on fresh repository must hit in-memory cache',
      );
      expect(
        fakeStorage.readKeys,
        isEmpty,
        reason:
            'Existing .tts file must never trigger FlutterSecureStorage read',
      );

      // Saving empty state deletes both .tts file and any leftover legacy keyring key, and clears cache.
      fakeStorage.store['t2_sync_v1_tasks'] = 'stale-legacy-value';
      await freshRepo.saveWorkspaceSyncState('tasks', WorkspaceSyncState.empty);
      expect(syncFile.existsSync(), isFalse);
      expect(fakeStorage.store.containsKey('t2_sync_v1_tasks'), isFalse);
      expect(
        await freshRepo.loadWorkspaceSyncState('tasks'),
        equals(WorkspaceSyncState.empty),
      );

      // Deleting a workspace removes its .tts file, legacy keyring key, and cached state.
      await repository.createWorkspace('TempSync');
      await repository.saveWorkspaceSyncState('tempsync', constructed);
      fakeStorage.store['t2_sync_v1_tempsync'] = 'legacy-tempsync';
      final tempSyncFile = File('${settingsDir.path}/sync_state_tempsync.tts');
      expect(tempSyncFile.existsSync(), isTrue);
      await repository.deleteWorkspace('tempsync');
      expect(
        tempSyncFile.existsSync(),
        isFalse,
        reason: 'Deleting a workspace must remove its .tts sync state file',
      );
      expect(
        fakeStorage.store.containsKey('t2_sync_v1_tempsync'),
        isFalse,
        reason:
            'Deleting a workspace must remove any legacy sync keyring entry',
      );
      expect(
        await repository.loadWorkspaceSyncState('tempsync'),
        equals(WorkspaceSyncState.empty),
      );

      // Path traversal / invalid workspaceId checks.
      for (final badId in const <String>[
        '',
        '   ',
        '.',
        '..',
        '../escape',
        'nested/id',
        r'nested\id',
        'drive:id',
        'bad\x00id',
      ]) {
        await expectLater(
          () => repository.saveWorkspaceSyncState(badId, constructed),
          throwsA(
            isA<WorkspaceException>().having(
              (error) => error.kind,
              'kind',
              WorkspaceErrorKind.settingsPersistenceFailed,
            ),
          ),
          reason: 'Invalid workspaceId "$badId" must be rejected on save',
        );
        expect(
          await repository.loadWorkspaceSyncState(badId),
          equals(WorkspaceSyncState.empty),
          reason:
              'Invalid workspaceId "$badId" must safely return empty on load',
        );
      }

      // Symlink at sync_state_<id>.tts must not be followed or clobbered.
      final secretTarget = File('${tempRoot.path}/sync_secret.txt')
        ..writeAsStringSync('keep-me', flush: true);
      final symlinkSyncPath = '${settingsDir.path}/sync_state_linked.tts';
      Link(symlinkSyncPath).createSync(secretTarget.path);
      expect(
        await freshRepo.loadWorkspaceSyncState('linked'),
        equals(WorkspaceSyncState.empty),
        reason: 'Symlink sync state file must not be read',
      );
      await expectLater(
        () => freshRepo.saveWorkspaceSyncState('linked', constructed),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.settingsPersistenceFailed,
          ),
        ),
        reason: 'Symlink sync state file must be rejected on save',
      );
      expect(secretTarget.readAsStringSync(), equals('keep-me'));
    });

    test('caches decoded PersistedSettingsDocument across unchanged reads and reuses validated bytes for .bak rotation without redundant disk reads', () async {
      final settingsDir = Directory('${tempRoot.path}/settings_cache')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/settings_cache_locks')
        ..createSync(recursive: true);
      final fakeStorage = _TrackingFakeSecureStorage();
      final repository = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );

      // First save creates settings.json (no prior file on disk, populates cache).
      await repository.saveConfig(
        const WebDavConfig(language: AppLanguage.german),
      );
      expect(
        repository.settingsDiskReadCountForTesting,
        equals(0),
        reason:
            'Initial save on empty directory requires zero primary disk reads',
      );

      // Repeated read-only loads hit stat-validated cache with zero disk reads.
      expect(
        (await repository.loadActiveWorkspace()).config.language,
        equals(AppLanguage.german),
      );
      expect((await repository.loadWorkspaceSummaries()).length, equals(1));
      expect(
        repository.settingsDiskReadCountForTesting,
        equals(0),
        reason: 'Unchanged loadActiveWorkspace and loadWorkspaceSummaries must hit cache',
      );

      // Second save rotates .bak from cached bytes without reading disk again.
      final primaryBeforeSecondSave = File('${settingsDir.path}/settings.json')
          .readAsBytesSync();
      await repository.saveConfig(
        const WebDavConfig(
          language: AppLanguage.german,
          themeMode: AppThemeMode.dark,
        ),
      );
      expect(
        repository.settingsDiskReadCountForTesting,
        equals(0),
        reason: 'Mutating cached settings.json must reuse validated bytes for .bak rotation',
      );
      expect(
        File('${settingsDir.path}/settings.json.bak').readAsBytesSync(),
        equals(primaryBeforeSecondSave),
        reason: '.bak file must match exact bytes of previous settings.json',
      );

      // Fresh repository instance saving over existing settings.json reads disk ONLY ONCE (not twice for .bak rotation).
      final freshRepo = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );
      await freshRepo.saveConfig(
        const WebDavConfig(
          language: AppLanguage.english,
          themeMode: AppThemeMode.light,
        ),
      );
      expect(
        freshRepo.settingsDiskReadCountForTesting,
        equals(1),
        reason: 'Fresh save must read settings.json once in _loadDocumentLocked and reuse those bytes for .bak rotation',
      );

      // Subsequent reads hit cache (still 1 disk read).
      expect(
        (await freshRepo.loadActiveWorkspace()).config.themeMode,
        equals(AppThemeMode.light),
      );
      await freshRepo.loadWorkspaceSummaries();
      expect(freshRepo.settingsDiskReadCountForTesting, equals(1));

      // External modification invalidates stat cache and triggers a fresh disk read.
      final settingsFile = File('${settingsDir.path}/settings.json');
      final modifiedJson = settingsFile.readAsStringSync().replaceFirst(
        '"themeMode": "light"',
        '"themeMode": "dark"',
      );
      settingsFile.writeAsStringSync('$modifiedJson\n  \n', flush: true);
      final externallyUpdated = await freshRepo.loadActiveWorkspace();
      expect(
        externallyUpdated.config.themeMode,
        equals(AppThemeMode.dark),
        reason: 'External settings.json edit must invalidate stat-keyed cache',
      );
      expect(freshRepo.settingsDiskReadCountForTesting, equals(2));
    });

    test('saveConfigForWorkspace persists only to the targeted workspaceId and throws workspaceNotFound when missing or deleted', () async {
      final settingsDir = Directory('${tempRoot.path}/targeted_save')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/targeted_locks')
        ..createSync(recursive: true);
      final fakeStorage = _TrackingFakeSecureStorage();
      final secureRepo = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );
      final memoryRepo = InMemorySettingsRepository();

      for (final (label, repo) in <(String, SettingsRepository)>[
        ('InMemorySettingsRepository', memoryRepo),
        ('SecureSettingsRepository', secureRepo),
      ]) {
        final work = await repo.createWorkspace('Work', activate: true);
        expect((await repo.loadActiveWorkspace()).id, equals(work.id));

        const updatedTasksConfig = WebDavConfig(
          localFilePath: 'tasks_custom.tdf',
          filePath: 'tasks_custom.tdf',
          serverUrl: 'https://tasks.example.com',
          username: 'alice',
          password: 'tasks-secret-password',
          themeMode: AppThemeMode.dark,
        );

        await repo.saveConfigForWorkspace(
          AppWorkspace.defaultId,
          updatedTasksConfig,
        );

        // Active workspace ('work') must stay active and unmodified.
        final activeWork = await repo.loadActiveWorkspace();
        expect(
          activeWork.id,
          equals(work.id),
          reason: '$label must keep active workspace unchanged',
        );
        expect(
          activeWork.config.themeMode,
          equals(AppThemeMode.system),
          reason:
              '$label must NOT overwrite active workspace config when saving for another workspaceId',
        );
        expect(
          activeWork.config.password,
          isEmpty,
          reason:
              '$label must NOT leak targeted workspace password into active workspace',
        );

        // Switching back to 'tasks' must expose the targeted save (including password).
        final reloadedTasks = await repo.activateWorkspace(
          AppWorkspace.defaultId,
        );
        expect(
          reloadedTasks.config.themeMode,
          equals(AppThemeMode.dark),
          reason: '$label must persist targeted config to default workspace',
        );
        expect(reloadedTasks.config.localFilePath, equals('tasks_custom.tdf'));
        expect(
          reloadedTasks.config.password,
          equals('tasks-secret-password'),
          reason: '$label must persist password under targeted workspaceId',
        );

        // Duplicate file path collision against active/other workspace must still throw.
        await expectLater(
          () => repo.saveConfigForWorkspace(
            work.id,
            const WebDavConfig(localFilePath: 'tasks_custom.tdf'),
          ),
          throwsA(
            isA<WorkspaceException>().having(
              (error) => error.kind,
              'kind',
              WorkspaceErrorKind.duplicateFilePath,
            ),
          ),
          reason: '$label must reject duplicate .tdf paths across workspaces',
        );

        // Deleting 'work' and saving to its deleted ID must throw workspaceNotFound without touching 'tasks'.
        await repo.deleteWorkspace(work.id);
        await expectLater(
          () => repo.saveConfigForWorkspace(
            work.id,
            const WebDavConfig(
              localFilePath: 'ghost.tdf',
              password: 'ghost-password',
            ),
          ),
          throwsA(
            isA<WorkspaceException>().having(
              (error) => error.kind,
              'kind',
              WorkspaceErrorKind.workspaceNotFound,
            ),
          ),
          reason:
              '$label must fail with workspaceNotFound for deleted workspaceId',
        );
        expect(
          (await repo.loadActiveWorkspace()).config.localFilePath,
          equals('tasks_custom.tdf'),
          reason:
              '$label must leave active workspace intact after workspaceNotFound',
        );
      }

      expect(
        fakeStorage.store['t2_webdav_pw_tasks'],
        equals('tasks-secret-password'),
      );
      expect(
        fakeStorage.store.containsKey('t2_webdav_pw_work'),
        isFalse,
        reason:
            'Failed save to deleted workspace must never write keyring entry',
      );
    });

    test('offloads >= 32 KiB gzip sync state compression and decompression to Isolate.run while enforcing decompression bounds', () async {
      final settingsDir = Directory('${tempRoot.path}/large_tts_cfg')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/large_tts_locks')
        ..createSync(recursive: true);
      final fakeStorage = _TrackingFakeSecureStorage();
      final repository = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );

      // Build deterministic high-entropy TDF comments so both raw and gzipped wire sizes exceed 32 KiB.
      final rng = math.Random(42);
      const alphabet =
          'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final buffer = StringBuffer('tdf 0.8.0\n');
      for (var line = 0; line < 750; line++) {
        buffer.write('# ');
        for (var col = 0; col < 64; col++) {
          buffer.write(alphabet[rng.nextInt(alphabet.length)]);
        }
        buffer.writeln();
      }
      final highEntropyTdf = buffer.toString();
      const digest =
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      final largeState = WorkspaceSyncState(
        lastSyncedLocalTdf: highEntropyTdf,
        lastSyncedRemoteTdf: highEntropyTdf,
        acknowledgedLocalGeneration: 3,
        acknowledgedRemoteGeneration: 3,
        localSourceDigest: digest,
        remoteSourceDigest: digest,
        remoteEtag: '"etag-32k"',
      );
      expect(
        largeState.toBytes().length,
        greaterThanOrEqualTo(32768),
        reason: 'Raw sync state must exceed 32 KiB offload threshold',
      );

      await repository.saveWorkspaceSyncState('tasks', largeState);
      final syncFile = File('${settingsDir.path}/sync_state_tasks.tts');
      expect(syncFile.existsSync(), isTrue);
      final persistedBytes = syncFile.readAsBytesSync();
      expect(
        persistedBytes.length,
        greaterThanOrEqualTo(32768),
        reason: 'Persisted compressed sync state must exceed 32 KiB to exercise isolate decompression offload',
      );

      final freshRepository = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );
      final reloaded = await freshRepository.loadWorkspaceSyncState('tasks');
      expect(
        reloaded,
        equals(largeState),
        reason: 'Isolate-compressed and isolate-decompressed >= 32 KiB sync state must round-trip losslessly',
      );

      // Verify >= 32 KiB compressed gzip bomb expanding past maxSerializedBytes still returns empty safely.
      final bombRaw = Uint8List(WorkspaceSyncState.maxSerializedBytes + 65536);
      for (var i = 0; i < 40000; i++) {
        bombRaw[i] = rng.nextInt(256);
      }
      final largeBomb = gzip.encode(bombRaw);
      expect(largeBomb.length, greaterThanOrEqualTo(32768));
      File('${settingsDir.path}/sync_state_large_bomb.tts')
          .writeAsBytesSync(largeBomb, flush: true);
      expect(
        await freshRepository.loadWorkspaceSyncState('large_bomb'),
        equals(WorkspaceSyncState.empty),
        reason: 'Isolate-decompressed gzip bomb exceeding maxSerializedBytes must safely return empty',
      );
    });

    test('validates custom workspace id for uniqueness and filename safety in both InMemorySettingsRepository and SecureSettingsRepository', () async {
      final settingsDir = Directory('${tempRoot.path}/custom_id_cfg')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/custom_id_locks')
        ..createSync(recursive: true);
      final fakeStorage = _TrackingFakeSecureStorage();
      final secureRepo = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );
      final memoryRepo = InMemorySettingsRepository();

      for (final (label, repo) in <(String, SettingsRepository)>[
        ('InMemorySettingsRepository', memoryRepo),
        ('SecureSettingsRepository', secureRepo),
      ]) {
        for (final duplicateId in const <String>['tasks', 'TASKS']) {
          await expectLater(
            () => repo.createWorkspace('Unique Board', id: duplicateId),
            throwsA(isA<WorkspaceException>()),
            reason: '$label must reject duplicate workspace id "$duplicateId"',
          );
        }

        for (final unsafeId in <String>[
          '',
          '   ',
          '.',
          '..',
          '../escape',
          'nested/id',
          r'nested\id',
          'drive:id',
          'bad\x00id',
          '\nleading_control',
          'trailing_control\r',
          'bidi\u202Eid',
          'a' * 129,
        ]) {
          await expectLater(
            () => repo.createWorkspace('Safe Name', id: unsafeId),
            throwsA(isA<WorkspaceException>()),
            reason: '$label must reject unsafe workspace id "$unsafeId"',
          );
        }

        final created = await repo.createWorkspace('Custom', id: 'custom_id_1');
        expect(created.id, equals('custom_id_1'));
      }
    });

    test('rolls back keyring and password cache when settings.json persistence fails in createWorkspace and saveConfig', () async {
      final settingsDir = Directory('${tempRoot.path}/rollback_cfg')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/rollback_locks')
        ..createSync(recursive: true);
      final fakeStorage = _TrackingFakeSecureStorage();
      final repository = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );

      // Seed initial workspace with an existing password.
      await repository.saveConfig(
        const WebDavConfig(
          serverUrl: 'https://cloud.example.com',
          username: 'alice',
          password: 'original-password',
          storageMode: StorageMode.both,
        ),
      );
      expect(
        fakeStorage.store['t2_webdav_pw_tasks'],
        equals('original-password'),
      );

      // Poison settings.json.bak with a symlink so _persistDocumentLocked throws before writing settings.json.
      final backupSymlink = Link('${settingsDir.path}/settings.json.bak');
      if (File('${settingsDir.path}/settings.json.bak').existsSync()) {
        File('${settingsDir.path}/settings.json.bak').deleteSync();
      }
      backupSymlink.createSync('${tempRoot.path}/decoy_target.txt');

      // 1. createWorkspace with password rolls back newly written keyring entry.
      await expectLater(
        () => repository.createWorkspace(
          'Failing Workspace',
          id: 'failing_ws',
          config: const WebDavConfig(
            localFilePath: 'failing.tdf',
            filePath: 'failing.tdf',
            serverUrl: 'https://cloud.example.com',
            username: 'bob',
            password: 'ephemeral-password',
            storageMode: StorageMode.both,
          ),
        ),
        throwsA(isA<WorkspaceException>()),
      );
      expect(
        fakeStorage.store.containsKey('t2_webdav_pw_failing_ws'),
        isFalse,
        reason: 'Failed createWorkspace must roll back newly written keyring password',
      );

      // 2. saveConfig updating cached password rolls back keyring AND cache to original-password.
      await expectLater(
        () => repository.saveConfig(
          const WebDavConfig(
            serverUrl: 'https://cloud.example.com',
            username: 'alice',
            password: 'updated-password-should-rollback',
            storageMode: StorageMode.both,
          ),
        ),
        throwsA(isA<WorkspaceException>()),
      );
      expect(
        fakeStorage.store['t2_webdav_pw_tasks'],
        equals('original-password'),
        reason: 'Failed saveConfig password update must roll back keyring to original password',
      );

      // 3. saveConfig clearing password rolls back keyring deletion to original-password.
      await expectLater(
        () => repository.saveConfig(
          const WebDavConfig(
            serverUrl: 'https://cloud.example.com',
            username: 'alice',
          ),
        ),
        throwsA(isA<WorkspaceException>()),
      );
      expect(
        fakeStorage.store['t2_webdav_pw_tasks'],
        equals('original-password'),
        reason: 'Failed saveConfig password clear must restore original password in keyring',
      );

      // 4. Fresh uncached repository failing password update also restores prior keyring password.
      final freshRepo = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );
      await expectLater(
        () => freshRepo.saveConfig(
          const WebDavConfig(
            serverUrl: 'https://cloud.example.com',
            username: 'alice',
            password: 'uncached-update-should-rollback',
            storageMode: StorageMode.both,
          ),
        ),
        throwsA(isA<WorkspaceException>()),
      );
      expect(
        fakeStorage.store['t2_webdav_pw_tasks'],
        equals('original-password'),
        reason: 'Fresh uncached repository must restore prior keyring password on persistence failure',
      );

      // Remove poisoned backup symlink and verify cached password in original repository still matches original-password.
      backupSymlink.deleteSync();
      final activeAfterRollback = await repository.loadActiveWorkspace();
      expect(
        activeAfterRollback.config.password,
        equals('original-password'),
        reason: 'In-memory password cache must remain rolled back to original-password',
      );
    });

    test('quarantines oversized settings.json via bounded read and evicts sync-state cache inside sync lock during deleteWorkspace', () async {
      final settingsDir = Directory('${tempRoot.path}/bounded_and_race')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/bounded_and_race_locks')
        ..createSync(recursive: true);
      final fakeStorage = _TrackingFakeSecureStorage();
      final repository = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );

      // Oversized settings.json exceeding SettingsCodec.maxJsonBytes is quarantined and reset cleanly.
      final settingsFile = File('${settingsDir.path}/settings.json');
      settingsFile.writeAsBytesSync(
        List<int>.filled(SettingsCodec.maxJsonBytes + 1, 0x20),
        flush: true,
      );
      final recovered = await repository.loadActiveWorkspace();
      expect(recovered.id, equals(AppWorkspace.defaultId));
      expect(
        repository.takeLastRecoveryNotice()?.kind,
        equals(SettingsRecoveryKind.resetAfterQuarantine),
      );

      // Concurrent loadWorkspaceSyncState while deleteWorkspace removes workspace must not leave stale cache behind.
      await repository.createWorkspace('RaceBoard', id: 'race_board');
      const digest =
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      final state = WorkspaceSyncState(
        lastSyncedLocalTdf: 'tdf 0.8.0\n',
        lastSyncedRemoteTdf: 'tdf 0.8.0\n',
        acknowledgedLocalGeneration: 1,
        acknowledgedRemoteGeneration: 1,
        localSourceDigest: digest,
        remoteSourceDigest: digest,
      );
      await repository.saveWorkspaceSyncState('race_board', state);

      final freshRepo = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );
      await Future.wait(<Future<Object?>>[
        freshRepo.deleteWorkspace('race_board'),
        freshRepo.loadWorkspaceSyncState('race_board'),
      ]);
      expect(
        File('${settingsDir.path}/sync_state_race_board.tts').existsSync(),
        isFalse,
      );
      expect(
        await freshRepo.loadWorkspaceSyncState('race_board'),
        equals(WorkspaceSyncState.empty),
        reason: 'Sync state cache must be evicted under sync lock so post-delete loads see empty state',
      );

      // Verify TdfFilePath.trimTrailingSeparators preserves Windows drive roots (C:\) and POSIX root (/).
      final driveRootRepo = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: r'C:\',
        hostLockDirectoryOverride: lockDir.path,
      );
      expect(
        await driveRootRepo.resolveSettingsFilePathForTesting(),
        equals(r'C:\settings.json'),
        reason: 'Windows drive root C:\\ must not be truncated to drive-relative C:',
      );

      final multiSlashDriveRootRepo = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: r'C:\\\',
        hostLockDirectoryOverride: lockDir.path,
      );
      expect(
        await multiSlashDriveRootRepo.resolveSettingsFilePathForTesting(),
        equals(r'C:\settings.json'),
      );

      final posixRootRepo = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: '///',
        hostLockDirectoryOverride: lockDir.path,
      );
      expect(
        await posixRootRepo.resolveSettingsFilePathForTesting(),
        equals('/settings.json'),
      );
    });
  });
}
