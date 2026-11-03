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

Uint8List _buildRawRecord({
  int flags = 0,
  String id = 'tasks',
  String name = 'Tasks',
  String serverUrl = '',
  String username = '',
  String password = '',
  String filePath = 'tasks.tdf',
  String localFilePath = 'tasks.tdf',
}) {
  final builder = BytesBuilder(copy: false)..addByte(flags);
  for (final field in <String>[
    id,
    name,
    serverUrl,
    username,
    password,
    filePath,
    localFilePath,
  ]) {
    final encoded = utf8.encode(field);
    builder
      ..addByte((encoded.length >> 8) & 0xFF)
      ..addByte(encoded.length & 0xFF)
      ..add(encoded);
  }
  builder
    ..addByte(0x02)
    ..addByte(0xD0);
  return builder.toBytes();
}

void main() {
  final fixedDate = DateTime.utc(2026, 11, 2, 10, 0);

  group('AppWorkspace & Suggested TDF File Names', () {
    test('defaults to Tasks workspace with tasks.tdf and derives lowercase .tdf filenames and collision IDs', () {
      const defaultWorkspace = AppWorkspace.defaultWorkspace;
      expect(
        defaultWorkspace.id,
        equals('tasks'),
        reason: 'Default workspace ID must be tasks',
      );
      expect(
        defaultWorkspace.name,
        equals('Tasks'),
        reason: 'Default workspace name must be Tasks',
      );
      expect(
        defaultWorkspace.config.localFilePath,
        equals('tasks.tdf'),
        reason: 'Default localFilePath must be tasks.tdf',
      );
      expect(
        defaultWorkspace.config.filePath,
        equals('tasks.tdf'),
        reason: 'Default remote filePath must be tasks.tdf',
      );

      for (final (rawName, expectedFile) in <(String, String)>[
        ('Tasks', 'tasks.tdf'),
        ('Arbeit', 'arbeit.tdf'),
        ('  Kunde Müller & Söhne! ', 'kunde_mueller_soehne.tdf'),
        ('Großprojekt ÄÖÜ', 'grossprojekt_aeoeue.tdf'),
        ('   ---   ', 'workspace.tdf'),
      ]) {
        expect(
          AppWorkspace.suggestFileName(rawName),
          equals(expectedFile),
          reason: 'suggestFileName("$rawName") must return "$expectedFile"',
        );
      }

      final summaries = <WorkspaceSummary>[
        defaultWorkspace.summary,
        const WorkspaceSummary(
          id: 'tasks_2',
          name: 'Tasks 2',
          localFilePath: 'tasks_2.tdf',
          filePath: 'tasks_2.tdf',
        ),
      ];
      expect(
        AppWorkspace.deriveWorkspaceId('Tasks', summaries),
        equals('tasks_3'),
        reason: 'deriveWorkspaceId must increment numeric suffix on collision',
      );
      expect(
        AppWorkspace.deriveWorkspaceId('!!!', summaries),
        equals('workspace'),
        reason: 'deriveWorkspaceId must fall back to workspace on empty slug',
      );

      final updated = defaultWorkspace.copyWith(
        name: 'Private Tasks',
        config: const WebDavConfig(
          localFilePath: 'private.tdf',
          filePath: 'private.tdf',
          storageMode: StorageMode.both,
          language: AppLanguage.german,
          themeMode: AppThemeMode.dark,
          themePalette: AppThemePalette.navy,
          timeZoneMode: AppTimeZoneMode.manual,
          manualTimeZoneOffsetMinutes: 120,
        ),
      );
      final encodedBytes = updated.toBytes();
      expect(
        encodedBytes[6] & 0x80,
        equals(0),
        reason: 'Unused bit 7 in workspace flags byte must remain 0',
      );
      expect(
        encodedBytes.sublist(0, 4),
        equals(<int>[0x54, 0x54, 0x57, 0x01]),
        reason: 'Binary payload must start with TTW\\x01 magic header',
      );
      expect(
        defaultWorkspace.toBytes().length,
        equals(51),
        reason: 'Default workspace binary encoding must be 51 bytes',
      );
      expect(
        encodedBytes.length,
        equals(63),
        reason: 'Updated workspace binary encoding must be 63 bytes',
      );
      final roundTrip = AppWorkspace.fromBytes(encodedBytes);
      expect(
        roundTrip,
        equals(updated),
        reason: 'Binary round-trip must preserve AppWorkspace equality',
      );
      expect(
        roundTrip.hashCode,
        equals(updated.hashCode),
        reason: 'Binary round-trip must preserve AppWorkspace hashCode',
      );
      expect(
        roundTrip.summary,
        equals(
          const WorkspaceSummary(
            id: 'tasks',
            name: 'Private Tasks',
            localFilePath: 'private.tdf',
            filePath: 'private.tdf',
          ),
        ),
        reason: 'summary getter must match id, name, and paths',
      );
      expect(
        roundTrip.summary.hashCode,
        equals(updated.summary.hashCode),
        reason: 'WorkspaceSummary hashCode must be deterministic',
      );
    });
  });

  group('Workspace Uniqueness, Path Traversal, Control/BiDi Injection & Bounds', () {
    test('enforces name bounds, control/BiDi rejection, path traversal rejection, and all WorkspaceErrorKind variants', () async {
      final repository = InMemorySettingsRepository();

      final maxLenName = 'A' * AppWorkspace.maxNameLength;
      expect(
        AppWorkspace.validateName(maxLenName, const <WorkspaceSummary>[]),
        equals(maxLenName),
        reason: 'Exact 128-character workspace name must be accepted',
      );

      for (final invalidName in <String>[
        '',
        '   ',
        'Bad\nName',
        'Bad\rName',
        'Bad\x00Name',
        'Bad\x7FName',
        'Bad\u0085Name',
        'Bad\u009FName',
        'Bad\u2028Name',
        'Bad\u2029Name',
        'Bad\u202EName',
        'Bad\u2066Name',
        'Bad\u061CName',
        'Bad\u200EName',
        'Bad\u200FName',
        'A' * (AppWorkspace.maxNameLength + 1),
      ]) {
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

      for (final duplicateName in <String>['Tasks', 'tasks', '  TASKS  ']) {
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
      expect(
        arbeitWorkspace.id,
        equals('arbeit'),
        reason: 'Arbeit workspace ID must be arbeit',
      );

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

      for (final invalidPath in <String>[
        '',
        '.tdf',
        '/.tdf',
        'sub/.tdf',
        'dir/..tdf',
        'dir/ .tdf',
        'dir/ .. /tasks.tdf',
        'dir/ . /tasks.tdf',
        'dir/ /tasks.tdf',
        'dir/ sub/tasks.tdf',
        'dir/sub /tasks.tdf',
        '../escape.tdf',
        'notes.txt',
        'bad\x00.tdf',
        'bad\u0085.tdf',
        'bad\u2028.tdf',
        'bad\u202E.tdf',
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
      expect(
        renamedArbeit.name,
        equals('Kunde Nord'),
        reason: 'Renamed workspace must reflect new display name',
      );
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
        reason: 'Activating unknown workspace ID must throw workspaceNotFound',
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

    test('rejects corrupt, negative-indexed, oversized, trailing-byte, invalid-UTF8, and duplicate binary payloads', () {
      final validSingle = AppWorkspace.defaultWorkspace.toBytes();
      final recordDefault = _buildRawRecord();
      final recordControlName = _buildRawRecord(name: 'Bad\nName');
      final recordBiDiPath = _buildRawRecord(localFilePath: 'bad\u202E.tdf');
      final recordTraversalPath = _buildRawRecord(
        localFilePath: '../escape.tdf',
      );
      final recordOverlongName = _buildRawRecord(
        name: 'A' * (AppWorkspace.maxNameLength + 1),
      );

      for (final corruptBytes in <List<int>>[
        <int>[],
        <int>[0x54, 0x54, 0x57],
        <int>[0x00, 0x00, 0x00, 0x01, 0x01, 0x00],
        <int>[0x154, 0x54, 0x57, 0x01, 0x01, 0x00, ...recordDefault],
        <int>[0x54, 0x54, 0x57, 0x02, 0x01, 0x00],
        <int>[0x54, 0x54, 0x57, 0x01, 0x00, 0x00],
        <int>[0x54, 0x54, 0x57, 0x01, -1, 0x00, ...recordDefault],
        <int>[0x54, 0x54, 0x57, 0x01, 0x21, 0x00],
        <int>[0x54, 0x54, 0x57, 0x01, 0x01, 0x01],
        <int>[0x54, 0x54, 0x57, 0x01, 0x01, -256, ...recordDefault],
        <int>[0x54, 0x54, 0x57, 0x01, 0x01, 0x00],
        <int>[0x54, 0x54, 0x57, 0x01, 0x01, 0x00, 0x00, 0x00],
        <int>[0x54, 0x54, 0x57, 0x01, 0x01, 0x00, 0x00, 0x00, 0x05, 0x61],
        <int>[0x54, 0x54, 0x57, 0x01, 0x01, 0x00, 0x00, 0x00, 0x02, 0xFF, 0xFE],
        <int>[...validSingle, 0x00],
        <int>[0x54, 0x54, 0x57, 0x01, 0x01, 0x00, ...recordControlName],
        <int>[0x54, 0x54, 0x57, 0x01, 0x01, 0x00, ...recordBiDiPath],
        <int>[0x54, 0x54, 0x57, 0x01, 0x01, 0x00, ...recordTraversalPath],
        <int>[0x54, 0x54, 0x57, 0x01, 0x01, 0x00, ...recordOverlongName],
        <int>[
          0x54,
          0x54,
          0x57,
          0x01,
          0x02,
          0x00,
          ...recordDefault,
          ...recordDefault,
        ],
        Uint8List(AppWorkspace.maxBinaryBytes + 1),
      ]) {
        expect(
          () => AppWorkspace.decodePersistedState(corruptBytes),
          throwsA(
            isA<WorkspaceException>().having(
              (error) => error.kind,
              'kind',
              WorkspaceErrorKind.corruptBinaryPayload,
            ),
          ),
          reason:
              'Corrupt binary payload (length ${corruptBytes.length}) must throw corruptBinaryPayload',
        );
      }

      final hugePasswordWorkspace = AppWorkspace(
        id: 'tasks',
        name: 'Tasks',
        config: WebDavConfig(password: 'P' * AppWorkspace.maxBinaryBytes),
      );
      expect(
        () => AppWorkspace.encodePersistedState(<AppWorkspace>[
          hugePasswordWorkspace,
        ], activeId: 'tasks'),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.kind,
            'kind',
            WorkspaceErrorKind.corruptBinaryPayload,
          ),
        ),
        reason: 'Encoding a workspace payload exceeding maxBinaryBytes must throw corruptBinaryPayload',
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
      expect(
        initialWorkspace.id,
        equals('tasks'),
        reason: 'Initial active workspace ID must be tasks',
      );
      expect(
        initialWorkspace.name,
        equals('Tasks'),
        reason: 'Initial active workspace name must be Tasks',
      );
      expect(
        initialWorkspace.config.localFilePath,
        equals('tasks.tdf'),
        reason: 'Initial active workspace localFilePath must be tasks.tdf',
      );
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
      expect(
        initialBoard.allTasks,
        isEmpty,
        reason: 'Initial board before adding tasks must be empty',
      );

      await container
          .read(taskNotifierProvider.notifier)
          .addTask('Private Steuererklärung', isPriority: true);

      final tasksBoard = container.read(taskNotifierProvider).requireValue;
      expect(
        tasksBoard.focus.map((task) => task.title),
        equals(['Private Steuererklärung']),
        reason: 'Task added to Tasks workspace must appear in Focus tier',
      );
      final tasksFile = File('${tempDir.path}/tasks.tdf');
      expect(
        await tasksFile.exists(),
        isTrue,
        reason: 'tasks.tdf must be created on disk',
      );
      expect(
        await tasksFile.readAsString(),
        contains('name "Private Steuererklärung"'),
        reason: 'tasks.tdf must contain the serialized task name',
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

      expect(
        arbeitWorkspace.id,
        equals('arbeit'),
        reason: 'Derived workspace ID for Arbeit must be arbeit',
      );
      expect(
        container.read(activeWorkspaceProvider).requireValue.name,
        equals('Arbeit'),
        reason: 'Only the newly activated Arbeit workspace must be in state',
      );

      final switchedConfig = await container.read(webDavConfigProvider.future);
      expect(
        switchedConfig.localFilePath,
        equals('arbeit.tdf'),
        reason: 'Switched config must point to arbeit.tdf',
      );
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
      expect(
        await arbeitFile.exists(),
        isTrue,
        reason: 'arbeit.tdf must exist after adding a task to Arbeit',
      );
      expect(
        await arbeitFile.readAsString(),
        contains('name "Sprint Planning vorbereiten"'),
        reason: 'arbeit.tdf must contain the task added in Arbeit',
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
        reason: 'Active workspace name must update in memory after rename',
      );

      await container
          .read(activeWorkspaceProvider.notifier)
          .switchWorkspace('tasks');

      final reloadedTasksConfig = await container.read(
        webDavConfigProvider.future,
      );
      expect(
        reloadedTasksConfig.localFilePath,
        equals('tasks.tdf'),
        reason: 'Switching back to tasks must restore tasks.tdf config',
      );
      expect(
        container.read(appThemeModeProvider),
        equals(AppThemeMode.dark),
        reason: 'Switching back to tasks must restore dark theme mode',
      );
      expect(
        container.read(appLocaleProvider),
        equals(const Locale('de')),
        reason: 'Switching back to tasks must restore German locale',
      );

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
        reason: 'Fallback workspace board must contain its original tasks',
      );
    });

    test('SecureSettingsRepository persists workspaces and activeId in a single Base64-encoded binary key without quotes or backslashes and restores StorageMode.both across restarts', () async {
      final fakeStorage = _FakeFlutterSecureStorage();
      final repository = SecureSettingsRepository(storage: fakeStorage);

      final initial = await repository.loadActiveWorkspace();
      expect(
        initial,
        equals(AppWorkspace.defaultWorkspace),
        reason: 'Empty storage must return AppWorkspace.defaultWorkspace',
      );
      expect(
        initial.config.storageMode,
        equals(StorageMode.local),
        reason: 'Default storage mode must be StorageMode.local',
      );

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
        ),
      );

      final rawStoredSettings = await fakeStorage.read(key: 't2_settings_v1');
      expect(
        rawStoredSettings,
        isNotNull,
        reason: 'Persisted settings key must be populated',
      );
      expect(
        rawStoredSettings?.contains('"'),
        isFalse,
        reason: 'Persisted settings payload must be Base64 without quotes',
      );
      expect(
        rawStoredSettings?.contains(r'\'),
        isFalse,
        reason: 'Persisted settings payload must not contain backslashes',
      );

      final reloadedRepository = SecureSettingsRepository(storage: fakeStorage);
      final reloaded = await reloadedRepository.loadActiveWorkspace();
      expect(
        reloaded.id,
        equals('tasks'),
        reason: 'Reloaded workspace ID must be tasks',
      );
      expect(
        reloaded.name,
        equals('Tasks'),
        reason: 'Reloaded workspace name must be Tasks',
      );
      expect(
        reloaded.config.storageMode,
        equals(StorageMode.both),
        reason: 'Reloaded storageMode must preserve StorageMode.both',
      );
      expect(
        reloaded.config.language,
        equals(AppLanguage.german),
        reason: 'Reloaded language must preserve AppLanguage.german',
      );
      expect(
        reloaded.config.themeMode,
        equals(AppThemeMode.dark),
        reason: 'Reloaded themeMode must preserve AppThemeMode.dark',
      );
      expect(
        reloaded.config.themePalette,
        equals(AppThemePalette.navy),
        reason: 'Reloaded themePalette must preserve AppThemePalette.navy',
      );

      await reloadedRepository.createWorkspace('Arbeit', activate: true);
      final activeArbeit = await reloadedRepository.loadActiveWorkspace();
      expect(
        activeArbeit.id,
        equals('arbeit'),
        reason: 'Newly activated workspace ID must be arbeit',
      );
      expect(
        activeArbeit.config.localFilePath,
        equals('arbeit.tdf'),
        reason: 'Newly activated workspace localFilePath must be arbeit.tdf',
      );

      await reloadedRepository.renameWorkspace('arbeit', 'Beratung');
      final summariesBeforeDelete = await reloadedRepository
          .loadWorkspaceSummaries();
      expect(
        summariesBeforeDelete.map((summary) => (summary.id, summary.name)),
        equals(<(String, String)>[('tasks', 'Tasks'), ('arbeit', 'Beratung')]),
        reason: 'loadWorkspaceSummaries must list all workspaces in order',
      );
      await reloadedRepository.activateWorkspace('tasks');
      final reactivatedTasks = await reloadedRepository.loadActiveWorkspace();
      expect(
        reactivatedTasks.id,
        equals('tasks'),
        reason: 'Reactivated workspace ID must be tasks',
      );
      expect(
        reactivatedTasks.config.storageMode,
        equals(StorageMode.both),
        reason: 'Reactivated tasks workspace must retain StorageMode.both',
      );
      await reloadedRepository.deleteWorkspace('arbeit');
      final summariesAfterDelete = await reloadedRepository
          .loadWorkspaceSummaries();
      expect(
        summariesAfterDelete.map((summary) => summary.id),
        equals(<String>['tasks']),
        reason: 'Deleted workspace must be removed from loadWorkspaceSummaries',
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
        reason: 'Initial workspaceSummariesProvider must contain Tasks',
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
        reason: 'Creating Projekt B must update workspaceSummariesProvider',
      );

      final projektBBoard = await container.read(taskNotifierProvider.future);
      expect(
        projektBBoard.allTasks,
        isEmpty,
        reason: 'Newly activated Projekt B board must be empty',
      );
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
        reason: 'Renaming workspace must update workspaceSummariesProvider',
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
        reason: 'Deleting workspace must update workspaceSummariesProvider',
      );
      final projektBFile = File('${tempDir.path}/projekt_b.tdf');
      expect(
        await projektBFile.exists(),
        isTrue,
        reason:
            'Deleting a workspace profile must preserve its .tdf file on disk',
      );
      expect(
        await projektBFile.readAsString(),
        contains('name "Projekt B Task"'),
        reason: 'Preserved .tdf file must retain all tasks without data loss',
      );

      final restoredTasksBoard = await container.read(
        taskNotifierProvider.future,
      );
      expect(
        restoredTasksBoard.focus.map((task) => task.title),
        equals(<String>['Task Before Switch']),
        reason: 'Fallback Tasks workspace must reload its original tasks',
      );
    });
  });
}
