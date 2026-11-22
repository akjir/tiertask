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
import 'dart:typed_data';
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

  Object? Function(String key)? readErrorForKey;
  Object? Function(String key, String? value)? writeErrorForKey;

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

/// Test-only TTW v2 encoder for legacy migration fixtures.
Uint8List _encodeLegacyTtwV2(
  List<AppWorkspace> workspaces, {
  required String activeId,
  int versionByte = 0x02,
}) {
  var activeIndex = 0;
  final builder = BytesBuilder(copy: false)
    ..add(<int>[0x54, 0x54, 0x57, versionByte, workspaces.length, 0]);
  for (var i = 0; i < workspaces.length; i++) {
    final workspace = workspaces[i];
    if (workspace.id == activeId) {
      activeIndex = i;
    }
    final config = workspace.config;
    final storageId = switch (config.storageMode) {
      StorageMode.local => 0,
      StorageMode.webdav => 1,
      StorageMode.both => 2,
    };
    final langId = switch (config.language) {
      AppLanguage.system => 0,
      AppLanguage.english => 1,
      AppLanguage.german => 2,
    };
    final themeId = switch (config.themeMode) {
      AppThemeMode.system => 0,
      AppThemeMode.light => 1,
      AppThemeMode.dark => 2,
    };
    final paletteId = switch (config.themePalette) {
      AppThemePalette.calm => 0,
      AppThemePalette.plumUmber => 1,
    };
    final dueLeadId = switch (config.dueLeadWindow) {
      DueLeadWindow.off => 0,
      DueLeadWindow.atDue => 1,
      DueLeadWindow.hours12 => 2,
      DueLeadWindow.hours24 => 3,
      DueLeadWindow.hours48 => 4,
      DueLeadWindow.days7 => 5,
    };
    final remoteLog = config.logStorageMode == StorageMode.local ? 0 : 1;
    final flags =
        (storageId & 0x03) |
        ((langId & 0x03) << 2) |
        ((themeId & 0x03) << 4) |
        ((paletteId & 0x01) << 6) |
        (remoteLog << 7);
    builder.addByte(flags);
    for (final field in <String>[
      workspace.id,
      workspace.name,
      config.serverUrl,
      config.username,
      config.password,
      config.filePath,
      config.localFilePath,
    ]) {
      final encoded = utf8.encode(field);
      builder
        ..addByte((encoded.length >> 8) & 0xFF)
        ..addByte(encoded.length & 0xFF)
        ..add(encoded);
    }
    final tzMode = config.timeZoneMode == AppTimeZoneMode.manual ? 1 : 0;
    final offsetField =
        config.manualTimeZoneOffsetMinutes - WebDavConfig.minUtcOffsetMinutes;
    final tzWord =
        (tzMode << 15) |
        ((config.locationEnabled ? 1 : 0) << 14) |
        ((config.diagnosticsEnabled ? 1 : 0) << 13) |
        (offsetField & 0x07FF);
    builder
      ..addByte((tzWord >> 8) & 0xFF)
      ..addByte(tzWord & 0xFF);
    if (versionByte == 0x02) {
      builder.addByte(dueLeadId);
    }
  }
  final result = builder.toBytes();
  result[5] = activeIndex;
  return result;
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
          filePath: 'tasks.tdf',
          localFilePath: 'tasks.tdf',
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
      final wsList = decodedMap['workspaces'] as List<Object?>;
      (wsList.first as Map<String, Object?>)['futureWorkspaceMeta'] = 'keep-me';
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
      final afterRenameWs =
          (afterRenameJson['workspaces'] as List<Object?>).first
              as Map<String, Object?>;
      expect(afterRenameWs['futureWorkspaceMeta'], equals('keep-me'));

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

    test('quarantines corrupt primary and backup, writes initial settings.json without triggering legacy migration, and handles missing primary with valid backup', () async {
      final settingsDir = Directory('${tempRoot.path}/double_corrupt')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/locks')
        ..createSync(recursive: true);
      // Seed a legacy TTW v2 key that MUST NOT be invoked when settings files existed:
      final legacyV2 = _encodeLegacyTtwV2(const <AppWorkspace>[
        AppWorkspace(
          id: 'legacy_ws',
          name: 'Legacy',
          config: WebDavConfig(
            localFilePath: 'legacy.tdf',
            filePath: 'legacy.tdf',
          ),
        ),
      ], activeId: 'legacy_ws');
      final fakeStorage = _TrackingFakeSecureStorage(<String, String>{
        't2_settings_v1': const Base64Service().encodeBytes(legacyV2),
      });
      final primaryFile = File('${settingsDir.path}/settings.json')
        ..writeAsStringSync('not-json-primary');
      final backupFile = File('${settingsDir.path}/settings.json.bak')
        ..writeAsStringSync('not-json-backup');
      final fixedUtc = DateTime.utc(2026, 11, 20, 15, 0, 0);

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
        reason: 'Double-corrupt recovery must reset to default workspace without invoking legacy migration',
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
        reason:
            'Legacy TTW v2 key must not be read when settings files existed',
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

  group('SecureSettingsRepository Legacy TTW v2 Migration, Android filesDir & Sync State', () {
    test('migrates TTW\\x02 once with password split and verified readback, rejects TTW\\x01, and handles cleanup/keyring errors', () async {
      final settingsDir = Directory('${tempRoot.path}/migration_ok')
        ..createSync(recursive: true);
      final lockDir = Directory('${tempRoot.path}/locks')
        ..createSync(recursive: true);
      final legacyWorkspaces = <AppWorkspace>[
        const AppWorkspace(
          id: 'tasks',
          name: 'Tasks',
          config: WebDavConfig(
            serverUrl: 'https://cloud.example.com',
            username: 'alice',
            password: 'migrated-secret-password',
            filePath: 'tasks.tdf',
            localFilePath: 'tasks.tdf',
            storageMode: StorageMode.both,
            language: AppLanguage.german,
            dueLeadWindow: DueLeadWindow.hours48,
          ),
        ),
        const AppWorkspace(
          id: 'privat',
          name: 'Privat',
          config: WebDavConfig(
            filePath: 'privat.tdf',
            localFilePath: 'privat.tdf',
            storageMode: StorageMode.local,
          ),
        ),
      ];
      final v2Encoded = const Base64Service().encodeBytes(
        _encodeLegacyTtwV2(legacyWorkspaces, activeId: 'tasks'),
      );
      final fakeStorage = _TrackingFakeSecureStorage(<String, String>{
        't2_settings_v1': v2Encoded,
      });

      final repository = SecureSettingsRepository(
        storage: fakeStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: settingsDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );
      final migrated = await repository.loadActiveWorkspace();
      expect(migrated, equals(legacyWorkspaces.first));
      expect(
        fakeStorage.store['t2_webdav_pw_tasks'],
        equals('migrated-secret-password'),
      );
      expect(
        fakeStorage.store.containsKey('t2_webdav_pw_privat'),
        isFalse,
        reason: 'Workspace without password must not create a keyring entry',
      );
      expect(
        fakeStorage.store.containsKey('t2_settings_v1'),
        isFalse,
        reason: 'Legacy t2_settings_v1 must be removed after verified settings.json write-and-readback',
      );
      final settingsText = File('${settingsDir.path}/settings.json')
          .readAsStringSync();
      expect(settingsText.contains('migrated-secret-password'), isFalse);

      // Failed password write during migration must leave t2_settings_v1 intact:
      final failedDir = Directory('${tempRoot.path}/migration_fail')
        ..createSync(recursive: true);
      final failingStorage = _TrackingFakeSecureStorage(<String, String>{
        't2_settings_v1': v2Encoded,
      })..writeErrorForKey = (key, value) => PlatformException(code: 'IO_ERR');
      final failingRepo = SecureSettingsRepository(
        storage: failingStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: failedDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );
      await expectLater(
        () => failingRepo.loadActiveWorkspace(),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.credentialStorageUnavailable,
          ),
        ),
      );
      expect(
        failingStorage.store['t2_settings_v1'],
        equals(v2Encoded),
        reason:
            'Aborted migration must leave t2_settings_v1 untouched for retry',
      );
      expect(File('${failedDir.path}/settings.json').existsSync(), isFalse);

      // TTW\x01 payload is rejected without deleting t2_settings_v1:
      final v1Dir = Directory('${tempRoot.path}/migration_v1')
        ..createSync(recursive: true);
      final v1Encoded = const Base64Service().encodeBytes(
        _encodeLegacyTtwV2(
          const <AppWorkspace>[AppWorkspace.defaultWorkspace],
          activeId: 'tasks',
          versionByte: 0x01,
        ),
      );
      final v1Storage = _TrackingFakeSecureStorage(<String, String>{
        't2_settings_v1': v1Encoded,
      });
      final v1Repo = SecureSettingsRepository(
        storage: v1Storage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: v1Dir.path,
        hostLockDirectoryOverride: lockDir.path,
      );
      expect(
        await v1Repo.loadActiveWorkspace(),
        equals(AppWorkspace.defaultWorkspace),
      );
      expect(
        v1Storage.store['t2_settings_v1'],
        equals(v1Encoded),
        reason: 'Rejected TTW\\x01 payload must not delete t2_settings_v1',
      );

      // Cleanup failure after verified write logs warning and still returns migrated state:
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.debug,
        persistToDisk: false,
      );
      final cleanupFailDir = Directory('${tempRoot.path}/migration_cleanup')
        ..createSync(recursive: true);
      final cleanupFailStorage =
          _TrackingFakeSecureStorage(<String, String>{
              't2_settings_v1': v2Encoded,
            })
            ..writeErrorForKey = (key, value) {
              if (key == 't2_settings_v1' && value == null) {
                return PlatformException(code: 'DELETE_ERR');
              }
              return null;
            };
      final cleanupRepo = SecureSettingsRepository(
        storage: cleanupFailStorage,
        buildProfile: AppBuildProfile.release,
        settingsDirectoryPath: cleanupFailDir.path,
        hostLockDirectoryOverride: lockDir.path,
      );
      final migratedDespiteCleanupErr = await cleanupRepo.loadActiveWorkspace();
      expect(migratedDespiteCleanupErr, equals(legacyWorkspaces.first));
      expect(
        AppLogger.lines.any(
          (line) => line.contains('settings.legacy_migration.cleanup_failed'),
        ),
        isTrue,
      );
      // Next load reads settings.json directly without touching t2_settings_v1:
      cleanupFailStorage.resetCounts();
      final nextLoad = await cleanupRepo.loadActiveWorkspace();
      expect(nextLoad, equals(legacyWorkspaces.first));
      expect(cleanupFailStorage.readKeys.contains('t2_settings_v1'), isFalse);
    });

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
      final storedEncoded = fakeStorage.store['t2_sync_v1_tasks'];
      expect(storedEncoded, isNotNull);
      expect(
        storedEncoded?.length ?? rawBytes.length,
        lessThan(rawBytes.length ~/ 4),
        reason: 'Gzip compression must shrink repetitive dual TDF sync state dramatically',
      );
      expect(
        await repo.loadWorkspaceSyncState('tasks'),
        equals(largeState),
        reason:
            'Compressed >1 MiB WorkspaceSyncState must round-trip losslessly',
      );

      // Backward compatibility: pre-existing uncompressed TTS\x04 entry in storage must still load.
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

      // Bounded decompression guard: gzip payload expanding past WorkspaceSyncState.maxSerializedBytes must return empty cleanly.
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
    });
  });
}
