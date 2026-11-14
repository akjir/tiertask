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
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/location_providers.dart';
import 'package:tiertask/providers/sync_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';

class _ControllableLocalRepository extends LocalFileRepository {
  _ControllableLocalRepository({
    required super.config,
    required this.getStore,
    required this.setStore,
    required this.shouldFailSave,
  });

  final String Function() getStore;
  final void Function(String value) setStore;
  final bool Function() shouldFailSave;

  @override
  bool get canWatchDirectory => false;

  @override
  bool fileExists() => getStore().isNotEmpty;

  @override
  Future<String> loadTdf() async => getStore();

  @override
  Future<void> saveTdf(String tdfContent) async {
    if (shouldFailSave()) {
      throw const LocalFileException('Simulated disk full failure');
    }
    setStore(tdfContent);
  }

  @override
  Future<void> wipeTdf({bool createBackup = false}) async {
    if (shouldFailSave()) {
      throw const LocalFileException('Simulated wipe failure');
    }
    setStore('tdf 0.6.0\n');
  }
}

class _ControllableWebDavRepository extends WebDavRepository {
  _ControllableWebDavRepository({
    required super.config,
    required this.remoteFiles,
    required this.shouldFail,
  });

  final Map<String, String> remoteFiles;
  final bool Function() shouldFail;

  @override
  Future<String> fetchTdf() async {
    if (shouldFail()) {
      throw const WebDavException('Simulated network failure');
    }
    final path = config.resolveEndpointUri()?.path ?? '';
    return remoteFiles[path] ?? '';
  }

  @override
  Future<void> saveTdf(String tdfContent) async {
    if (shouldFail()) {
      throw const WebDavException('Simulated network save failure');
    }
    final path = config.resolveEndpointUri()?.path ?? '';
    remoteFiles[path] = tdfContent;
  }

  @override
  Future<void> wipeTdf({bool createBackup = false}) async {
    if (shouldFail()) {
      throw const WebDavException('Simulated network wipe failure');
    }
    final path = config.resolveEndpointUri()?.path ?? '';
    if (createBackup && remoteFiles.containsKey(path)) {
      final existing = remoteFiles[path] ?? '';
      for (
        var index = 0;
        index <= LocalFileRepository.maxBackupSuffix;
        index++
      ) {
        final candidate = LocalFileRepository.formatBackupPath(path, index);
        if (!remoteFiles.containsKey(candidate)) {
          remoteFiles[candidate] = existing;
          break;
        }
      }
    }
    remoteFiles[path] = 'tdf 0.6.0\n';
  }
}

void main() {
  final fixedDate = DateTime.utc(2026, 11, 1, 12, 0);

  group('TaskNotifier Board Mutations & Atomic Rollback', () {
    test('executes task, subtask, queue, and label mutations and persists to storage', () async {
      var storedTdf = '';
      const config = WebDavConfig(
        storageMode: StorageMode.local,
        localFilePath: 'tasks.tdf',
        language: AppLanguage.english,
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(config),
          ),
          clockProvider.overrideWithValue(() => fixedDate),
          localFileRepositoryProvider.overrideWith(
            (ref) => _ControllableLocalRepository(
              config: config,
              getStore: () => storedTdf,
              setStore: (val) => storedTdf = val,
              shouldFailSave: () => false,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(taskNotifierProvider.future);
      final notifier = container.read(taskNotifierProvider.notifier);

      await notifier.addLabel(
        'Work',
        color: '#344FA1',
        id: 'work00OkD2',
        note: 'Primary work label',
      );
      await notifier.updateLabel(
        'work00OkD2',
        name: 'Work Updated',
        note: 'Updated note',
      );
      expect(
        container.read(taskNotifierProvider).requireValue.labels.single.name,
        equals('Work Updated'),
      );

      await notifier.addTask(
        'Task Alpha',
        id: 'alpha0OkD2',
        isPriority: true,
        labelIds: const ['work00OkD2'],
        subtasks: const [SubtaskItem(title: 'Step 1')],
      );
      await notifier.addTask(
        'Task Someday',
        id: 'smd000OkD2',
        targetTier: TaskTier.someday,
      );

      var board = container.read(taskNotifierProvider).requireValue;
      expect(board.focus.map((task) => task.id), equals(['alpha0OkD2']));
      expect(board.someday.map((task) => task.id), equals(['smd000OkD2']));

      await notifier.toggleSubtask('alpha0OkD2', 0);
      board = container.read(taskNotifierProvider).requireValue;
      expect(
        board.findTask('alpha0OkD2')?.subtasks.single.isCompleted,
        isTrue,
        reason: 'toggleSubtask must mark step 0 done',
      );

      await notifier.updateTask(
        'alpha0OkD2',
        title: 'Task Alpha Edited',
        note: 'Detailed note',
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('alpha0OkD2')
            ?.title,
        equals('Task Alpha Edited'),
      );

      await notifier.scheduleTask('smd000OkD2', isPriority: true);
      board = container.read(taskNotifierProvider).requireValue;
      expect(
        board.focus.map((task) => task.id),
        equals(['alpha0OkD2', 'smd000OkD2']),
        reason: 'scheduleTask must pull Someday task into open Focus slot per Section 6.2',
      );

      await notifier.moveTaskInQueue('smd000OkD2', beforeTaskId: 'alpha0OkD2');
      board = container.read(taskNotifierProvider).requireValue;
      expect(
        board.focus.map((task) => task.id),
        equals(['smd000OkD2', 'alpha0OkD2']),
      );

      await notifier.downgradeTask('smd000OkD2');
      board = container.read(taskNotifierProvider).requireValue;
      expect(
        board.findTask('smd000OkD2')?.isPriority,
        isFalse,
        reason: 'Downgrading a Focus task clears priority and moves to end of queue',
      );

      await notifier.blockTask(
        'smd000OkD2',
        suspendedUntil: DateTime.utc(2026, 11, 5, 9, 0),
      );
      board = container.read(taskNotifierProvider).requireValue;
      expect(board.blocked.map((task) => task.id), equals(['smd000OkD2']));

      await notifier.completeTask('alpha0OkD2');
      board = container.read(taskNotifierProvider).requireValue;
      expect(board.completed.map((task) => task.id), equals(['alpha0OkD2']));

      await notifier.restoreTask('alpha0OkD2', targetTier: TaskTier.focus);
      board = container.read(taskNotifierProvider).requireValue;
      expect(board.focus.map((task) => task.id), equals(['alpha0OkD2']));

      await notifier.deleteLabel('work00OkD2');
      board = container.read(taskNotifierProvider).requireValue;
      expect(board.labels, isEmpty);
      expect(board.findTask('alpha0OkD2')?.labelIds, isEmpty);

      await notifier.deleteTask('smd000OkD2');
      board = container.read(taskNotifierProvider).requireValue;
      expect(board.findTask('smd000OkD2'), isNull);
      expect(storedTdf, contains('task alpha0OkD2'));
    });

    test('rolls back in-memory TaskBoard state atomically when storage persistence fails (P-ATOMIC-STATE)', () async {
      var storedTdf = '';
      var failSaves = false;
      const config = WebDavConfig(
        storageMode: StorageMode.local,
        localFilePath: 'tasks.tdf',
        language: AppLanguage.english,
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(config),
          ),
          clockProvider.overrideWithValue(() => fixedDate),
          localFileRepositoryProvider.overrideWith(
            (ref) => _ControllableLocalRepository(
              config: config,
              getStore: () => storedTdf,
              setStore: (val) => storedTdf = val,
              shouldFailSave: () => failSaves,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(taskNotifierProvider.future);
      final notifier = container.read(taskNotifierProvider.notifier);

      await notifier.addTask('Baseline Task', id: 'base00OkD2');
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .allTasks
            .map((task) => task.title),
        equals(['Baseline Task']),
      );

      failSaves = true;
      await notifier.addTask('Should Roll Back Task', id: 'fail00OkD2');

      final rolledBackBoard = container.read(taskNotifierProvider).requireValue;
      expect(
        rolledBackBoard.allTasks.map((task) => task.title),
        equals(['Baseline Task']),
        reason: 'Failed local persistence must roll back TaskBoard state to pre-mutation snapshot',
      );
      expect(
        container.read(syncStateProvider).errorMessage,
        contains('Simulated disk full failure'),
        reason: 'Failed persistence must surface error message in syncStateProvider',
      );
    });
  });

  group('Local & Remote File Selection, Sync, and Wipe Operations', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tiertask_task_prov_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('selectLocalFile switches to an existing .tdf file or initializes a new .tdf file without deleting previous file', () async {
      final firstPath = '${tempDir.path}${Platform.pathSeparator}first.tdf';
      final secondPath = '${tempDir.path}${Platform.pathSeparator}second.tdf';
      final thirdPath = '${tempDir.path}${Platform.pathSeparator}third.tdf';

      await File(firstPath).writeAsString(
        'tdf 0.5.1\n\nqueue {\n    modified 2026-11-01 08:00:00\n    task 000001OkD2\n}\n\ntask 000001OkD2 {\n    name "First File Task"\n    created 2026-11-01 08:00:00\n    modified 2026-11-01 08:00:00\n}\n',
        flush: true,
      );
      await File(secondPath).writeAsString(
        'tdf 0.5.1\n\nqueue {\n    modified 2026-11-01 09:00:00\n    task 000002OkD2\n}\n\ntask 000002OkD2 {\n    name "Second File Task"\n    created 2026-11-01 09:00:00\n    modified 2026-11-01 09:00:00\n}\n',
        flush: true,
      );

      final settingsRepository = InMemorySettingsRepository(
        WebDavConfig(
          localFilePath: firstPath,
          storageMode: StorageMode.local,
          language: AppLanguage.english,
        ),
      );
      final container = ProviderContainer(
        retry: disableProviderRetry,
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          clockProvider.overrideWithValue(() => fixedDate),
        ],
      );
      addTearDown(container.dispose);

      final initialBoard = await container.read(taskNotifierProvider.future);
      expect(
        initialBoard.allTasks.map((task) => task.title),
        equals(<String>['First File Task']),
      );

      await container
          .read(taskNotifierProvider.notifier)
          .selectLocalFile(
            WebDavConfig(
              localFilePath: secondPath,
              storageMode: StorageMode.local,
              language: AppLanguage.english,
            ),
          );

      final secondBoard = await container.read(taskNotifierProvider.future);
      expect(
        secondBoard.allTasks.map((task) => task.title),
        equals(<String>['Second File Task']),
      );
      expect(await File(firstPath).exists(), isTrue);

      await container
          .read(taskNotifierProvider.notifier)
          .selectLocalFile(
            WebDavConfig(
              localFilePath: thirdPath,
              storageMode: StorageMode.local,
              language: AppLanguage.english,
            ),
          );

      final thirdBoard = await container.read(taskNotifierProvider.future);
      expect(thirdBoard.allTasks, isEmpty);
      expect(await File(thirdPath).exists(), isTrue);
      expect(await File(secondPath).exists(), isTrue);
    });

    test('wipeLocalFile, wipeRemoteFile, syncFromRemote, and testConnectionAndSync manage backups and validate configuration', () async {
      final remoteFiles = <String, String>{};
      var failRemote = false;
      const webdavConfig = WebDavConfig(
        serverUrl: 'https://cloud.example.com',
        username: 'stefan',
        password: 'secret',
        filePath: 'remote_wipe.tdf',
        localFilePath: 'local_wipe.tdf',
        storageMode: StorageMode.both,
        language: AppLanguage.english,
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(webdavConfig),
          ),
          localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
          clockProvider.overrideWithValue(() => fixedDate),
          webDavRepositoryProvider.overrideWith(
            (ref) => _ControllableWebDavRepository(
              config:
                  ref.watch(webDavConfigProvider).asData?.value ?? webdavConfig,
              remoteFiles: remoteFiles,
              shouldFail: () => failRemote,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(taskNotifierProvider.future);
      final notifier = container.read(taskNotifierProvider.notifier);

      await notifier.addTask('Task before wipe');
      const remotePath = '/remote.php/dav/files/stefan/remote_wipe.tdf';
      expect(remoteFiles[remotePath], contains('Task before wipe'));

      await notifier.testConnectionAndSync(webdavConfig);
      await notifier.syncFromRemote();
      expect(container.read(syncStateProvider).errorMessage, isNull);

      await notifier.wipeRemoteFile(webdavConfig, createBackup: true);
      expect(remoteFiles['$remotePath.bak'], contains('Task before wipe'));
      expect(remoteFiles[remotePath], equals('tdf 0.6.0\n'));

      await notifier.wipeLocalFile(webdavConfig, createBackup: true);
      final localWipeFile = File('${tempDir.path}/local_wipe.tdf');
      final localWipeBak = File('${tempDir.path}/local_wipe.tdf.bak');
      expect(await localWipeBak.exists(), isTrue);
      expect(await localWipeFile.readAsString(), equals('tdf 0.6.0\n'));
      expect(container.read(taskNotifierProvider).value?.allTasks, isEmpty);

      await expectLater(
        () => notifier.testConnectionAndSync(
          const WebDavConfig(storageMode: StorageMode.webdav),
        ),
        throwsA(isA<WebDavException>()),
        reason: 'Unconfigured WebDAV must throw WebDavException on testConnectionAndSync',
      );
      failRemote = false;
    });

    test('executes TDF 0.6.0 location CRUD, scoped labels, due/origin task fields, and scoped downgrade mutations', () async {
      var storedTdf = '';
      const config = WebDavConfig(
        storageMode: StorageMode.local,
        localFilePath: 'tasks.tdf',
        language: AppLanguage.english,
      );
      final settingsRepo = InMemorySettingsRepository(config);
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepo),
          localFileRepositoryProvider.overrideWith(
            (ref) => _ControllableLocalRepository(
              config: config,
              getStore: () => storedTdf,
              setStore: (value) => storedTdf = value,
              shouldFailSave: () => false,
            ),
          ),
          clockProvider.overrideWithValue(() => fixedDate),
        ],
      );
      addTearDown(container.dispose);

      await container.read(taskNotifierProvider.future);
      final notifier = container.read(taskNotifierProvider.notifier);

      await notifier.addLocation(
        'Office HQ',
        latitude: 52.520008,
        longitude: 13.404954,
        radiusMeters: 150,
        source: 'gps',
        note: 'Main office',
      );
      var board = container.read(taskNotifierProvider).requireValue;
      expect(board.locations.length, equals(1));
      final locationId = board.locations.single.id;
      expect(board.locations.single.name, equals('Office HQ'));
      expect(board.locations.single.source, equals('gps'));

      await notifier.updateLocation(
        locationId,
        name: 'Berlin Office',
        latitude: 52.5201,
        longitude: 13.4050,
        radiusMeters: 250,
        source: 'manual',
        note: 'Updated office',
      );
      board = container.read(taskNotifierProvider).requireValue;
      expect(board.locations.single.name, equals('Berlin Office'));
      expect(board.locations.single.radius, equals(250));
      expect(board.locations.single.source, equals('manual'));

      await notifier.addLabel(
        'Work Scoped',
        color: '#2196F3',
        isScoped: true,
        conditions: [
          LocationTaskCondition(locationIds: [locationId]),
        ],
      );
      board = container.read(taskNotifierProvider).requireValue;
      final labelId = board.labels.single.id;
      expect(board.labels.single.isScoped, isTrue);

      await notifier.updateLabel(
        labelId,
        name: 'Work Scoped Updated',
        color: '#4CAF50',
        isScoped: false,
        conditions: [
          LocationTaskCondition(locationIds: [locationId]),
        ],
      );
      board = container.read(taskNotifierProvider).requireValue;
      expect(board.labels.single.isScoped, isFalse);

      final dueAt = DateTime.utc(2026, 11, 5, 14, 0);
      const taskOrigin = TaskOrigin(namespace: 'jira', externalKey: 'OPS-42');
      await notifier.addTask(
        'Prepare Quarterly Report',
        labelIds: [labelId],
        dueAt: dueAt,
        origin: taskOrigin,
      );
      board = container.read(taskNotifierProvider).requireValue;
      final task = board.allTasks.single;
      expect(task.dueAt, equals(dueAt));
      expect(task.origin, equals(taskOrigin));

      await notifier.updateTask(
        task.id,
        title: 'Prepare Annual Report',
        isPriority: false,
        dueAt: DateTime.utc(2026, 11, 6),
        origin: task.origin,
        labelIds: [labelId],
      );
      board = container.read(taskNotifierProvider).requireValue;
      expect(board.findTask(task.id)?.dueAt, equals(DateTime.utc(2026, 11, 6)));
      expect(board.findTask(task.id)?.origin, equals(taskOrigin));

      await notifier.deleteLocation(locationId);
      board = container.read(taskNotifierProvider).requireValue;
      expect(board.locations, isEmpty);
      expect(
        board.deletedBlock.locations.any(
          (record) => record.locationId == locationId,
        ),
        isTrue,
        reason: 'Deleting a location must record its tombstone in deletedBlock.locations',
      );

      // Verify downgradeTask forwards current GPS fix from locationStateProvider:
      await notifier.addLocation(
        'Munich Office',
        latitude: 48.1351,
        longitude: 11.5820,
        radiusMeters: 100,
      );
      board = container.read(taskNotifierProvider).requireValue;
      final munichId = board.locations.single.id;
      await notifier.addTask(
        'Focus Top',
        targetTier: TaskTier.focus,
        isPriority: true,
      );
      await notifier.addTask(
        'Munich Only Task',
        targetTier: TaskTier.planned,
        conditions: [
          LocationTaskCondition(locationIds: [munichId]),
        ],
      );
      board = container.read(taskNotifierProvider).requireValue;
      final focusTopId = board.allTasks
          .firstWhere((item) => item.title == 'Focus Top')
          .id;
      final munichTaskId = board.allTasks
          .firstWhere((item) => item.title == 'Munich Only Task')
          .id;
      await notifier.moveTaskInQueue(focusTopId, beforeTaskId: task.id);
      await notifier.moveTaskInQueue(munichTaskId, afterTaskId: task.id);

      // With active GPS fix in Berlin (far from Munich), munichTaskId is excluded from E_ctx:
      container
          .read(locationStateProvider.notifier)
          .state = LocationState.found(
        fix: const LocationFix(latitude: 52.5200, longitude: 13.4050),
        updatedAt: fixedDate,
      );
      await notifier.downgradeTask(focusTopId, currentDate: fixedDate);
      board = container.read(taskNotifierProvider).requireValue;
      expect(
        board.queueTaskIds,
        equals([task.id, focusTopId, munichTaskId]),
        reason: 'TaskNotifier.downgradeTask must pass currentFix coordinates so GPS-blocked tasks are excluded from E_ctx',
      );
    });

    group('In-memory undo stack, bounds, rollback, and two-stage sync', () {
      setUp(() {
        HttpOverrides.global = null;
      });

      test('enforces maxUndoEntries = 10 (9, 10, 11 bounds), filters no-ops, checks expectedSequence, and retains entries across unrelated mutations and preference updates', () async {
        var localStore = 'tdf 0.6.0\n';
        const config = WebDavConfig(storageMode: StorageMode.local);
        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(config),
            ),
            localFileRepositoryProvider.overrideWith(
              (ref) => _ControllableLocalRepository(
                config: ref.read(webDavConfigProvider).asData?.value ?? config,
                getStore: () => localStore,
                setStore: (value) => localStore = value,
                shouldFailSave: () => false,
              ),
            ),
            clockProvider.overrideWithValue(() => fixedDate),
          ],
        );
        addTearDown(container.dispose);
        await container.read(taskNotifierProvider.future);
        final notifier = container.read(taskNotifierProvider.notifier);

        for (var i = 1; i <= 11; i++) {
          final id = 'tk${i.toString().padLeft(4, '0')}OkD2';
          await notifier.addTask(
            'Task $i',
            id: id,
            targetTier: TaskTier.planned,
            subtasksAutoFinish: i == 2,
            subtasks: i == 2
                ? const <SubtaskItem>[SubtaskItem(title: 'Only step')]
                : const <SubtaskItem>[
                    SubtaskItem(title: 'Step A'),
                    SubtaskItem(title: 'Step B'),
                  ],
          );
        }

        // Non-completing subtask toggle, missing delete, and Someday downgrade must be no-ops for undo:
        await notifier.toggleSubtask('tk0001OkD2', 0);
        await notifier.deleteTask('nonExiOkD2');
        await notifier.addTask(
          'Someday Noop',
          id: 'someNpOkD2',
          targetTier: TaskTier.someday,
        );
        await notifier.downgradeTask('someNpOkD2');
        expect(
          container.read(taskUndoStateProvider).stackDepth,
          equals(0),
          reason: 'Non-completing subtask toggles, missing task deletes, and Someday no-op downgrades must record 0 undo entries',
        );

        // Perform 11 undoable actions (1=complete, 2=auto-finish subtask, 3..9=delete, 10=downgrade, 11=complete):
        await notifier.completeTask('tk0001OkD2');
        expect(container.read(taskUndoStateProvider).stackDepth, equals(1));
        await notifier.toggleSubtask('tk0002OkD2', 0);
        expect(container.read(taskUndoStateProvider).stackDepth, equals(2));
        for (var i = 3; i <= 9; i++) {
          final id = 'tk${i.toString().padLeft(4, '0')}OkD2';
          await notifier.deleteTask(id);
        }
        expect(
          container.read(taskUndoStateProvider).stackDepth,
          equals(9),
          reason: 'N - 1 = 9 entries must be retained',
        );

        await notifier.downgradeTask('tk0010OkD2');
        expect(
          container.read(taskUndoStateProvider).stackDepth,
          equals(10),
          reason: 'N = 10 entries must be retained',
        );

        // 11th undoable action evicts tk0001OkD2:
        await notifier.completeTask('tk0011OkD2');
        final stateAt11 = container.read(taskUndoStateProvider);
        expect(
          stateAt11.stackDepth,
          equals(10),
          reason: 'N + 1 = 11th entry must cap stackDepth at 10',
        );
        expect(stateAt11.latestNotice?.taskId, equals('tk0011OkD2'));

        // Unrelated mutations & same-workspace preference updates must preserve the stack:
        await notifier.addLabel('Ops');
        await container
            .read(webDavConfigProvider.notifier)
            .updateLanguage(AppLanguage.german);
        await container
            .read(webDavConfigProvider.notifier)
            .updateThemeMode(AppThemeMode.dark);
        await container.read(taskNotifierProvider.future);
        expect(
          container.read(taskUndoStateProvider).stackDepth,
          equals(10),
          reason: 'Same-workspace preference updates and label additions must preserve undo stack',
        );

        // Mismatched expectedSequence must return false without popping:
        expect(await notifier.undoLastAction(expectedSequence: 9999), isFalse);
        expect(container.read(taskUndoStateProvider).stackDepth, equals(10));

        // Undo all 10 retained actions in LIFO order (entries 11 down to 2):
        for (var remaining = 9; remaining >= 0; remaining--) {
          expect(await notifier.undoLastAction(), isTrue);
          expect(
            container.read(taskUndoStateProvider).stackDepth,
            equals(remaining),
          );
        }
        expect(await notifier.undoLastAction(), isFalse);

        final finalBoard = container.read(taskNotifierProvider).requireValue;
        expect(
          finalBoard.findTierOfTask('tk0001OkD2'),
          equals(TaskTier.completed),
          reason: 'Evicted 1st entry must remain completed after 10 undos',
        );
        expect(
          finalBoard.findTierOfTask('tk0002OkD2'),
          isNot(TaskTier.completed),
          reason: '2nd entry (auto-finish subtask) must be restored to open',
        );
        expect(finalBoard.findTask('tk0009OkD2'), isNotNull);
        expect(
          finalBoard.findTierOfTask('tk0011OkD2'),
          isNot(TaskTier.completed),
        );
      });

      test('synchronizes complete+undo and delete+undo over Local + loopback WebDAV HttpServer, guards slow in-flight PUT epochs, rolls back on LocalFileException, and clears on workspace/file/import/wipe', () async {
        var remoteTdf = 'tdf 0.6.0\n';
        Completer<void>? putGate;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((HttpRequest request) async {
          if (request.method == 'GET') {
            request.response
              ..statusCode = HttpStatus.ok
              ..write(remoteTdf);
            await request.response.close();
            return;
          }
          if (request.method == 'PUT') {
            final body = await utf8.decoder.bind(request).join();
            if (putGate case final gate?) {
              await gate.future;
            }
            remoteTdf = body;
            request.response.statusCode = HttpStatus.noContent;
            await request.response.close();
            return;
          }
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
        });

        final tempDir = await Directory.systemTemp.createTemp('tiertask_undo_');
        addTearDown(() => tempDir.delete(recursive: true));

        var failLocalSave = false;
        var localStore = 'tdf 0.6.0\n';
        final initialConfig = WebDavConfig(
          storageMode: StorageMode.both,
          serverUrl: 'http://127.0.0.1:${server.port}',
          filePath: '/tasks.tdf',
          username: 'example-user',
          password: 'example-password',
        );
        final settingsRepo = InMemorySettingsRepository(initialConfig);
        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepo),
            localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
            localFileRepositoryProvider.overrideWith(
              (ref) => _ControllableLocalRepository(
                config:
                    ref.read(webDavConfigProvider).asData?.value ??
                    initialConfig,
                getStore: () => localStore,
                setStore: (value) => localStore = value,
                shouldFailSave: () => failLocalSave,
              ),
            ),
            clockProvider.overrideWithValue(() => fixedDate),
          ],
        );
        addTearDown(container.dispose);
        await container.read(taskNotifierProvider.future);
        final notifier = container.read(taskNotifierProvider.notifier);

        await notifier.addTask(
          'Deploy Gateway',
          id: 'depGtwOkD2',
          targetTier: TaskTier.focus,
          isPriority: true,
        );
        await notifier.addTask(
          'Verify Metrics',
          id: 'verMetOkD2',
          targetTier: TaskTier.planned,
          dependencies: const <TdfTaskDependency>[
            TdfTaskDependency(taskId: 'depGtwOkD2', requiredCompletion: 1),
          ],
        );

        // 1. Complete -> Sync -> Undo -> Sync:
        await notifier.completeTask('depGtwOkD2');
        expect(await notifier.undoLastAction(), isTrue);
        var board = container.read(taskNotifierProvider).requireValue;
        expect(board.findTask('depGtwOkD2')!.isCompleted, isFalse);
        expect(board.findTask('depGtwOkD2')!.completions, equals(1));
        expect(
          board.findTask('verMetOkD2')!.dependencies.single.requiredCompletion,
          equals(2),
        );
        expect(remoteTdf, contains('completions 1'));
        expect(remoteTdf, contains('depGtwOkD2:2'));

        // 2. Delete -> Sync -> Undo -> Sync:
        await notifier.deleteTask('depGtwOkD2');
        expect(remoteTdf, contains('deleted {'));
        expect(await notifier.undoLastAction(), isTrue);
        board = container.read(taskNotifierProvider).requireValue;
        expect(board.findTask('depGtwOkD2'), isNotNull);
        expect(board.deletedBlock.generation, equals(1));
        expect(board.deletedBlock.findTaskRecord('depGtwOkD2'), isNull);
        expect(remoteTdf, contains('generation 1'));
        expect(remoteTdf, contains('task depGtwOkD2 priority {'));

        // 3. Slow in-flight WebDAV PUT + immediate Undo (_mutationEpoch guard):
        putGate = Completer<void>();
        final pendingDeleteFuture = notifier.deleteTask('depGtwOkD2');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          container
              .read(taskNotifierProvider)
              .requireValue
              .findTask('depGtwOkD2'),
          isNull,
        );
        final undoDuringSlowPut = notifier.undoLastAction();
        expect(
          container
              .read(taskNotifierProvider)
              .requireValue
              .findTask('depGtwOkD2'),
          isNotNull,
          reason: 'Optimistic undo state must appear immediately even while prior WebDAV PUT is in flight',
        );
        putGate.complete();
        putGate = null;
        await pendingDeleteFuture;
        expect(await undoDuringSlowPut, isTrue);
        expect(
          container
              .read(taskNotifierProvider)
              .requireValue
              .findTask('depGtwOkD2'),
          isNotNull,
          reason: 'Stale in-flight delete completion must not overwrite newer undo epoch',
        );

        // 4. LocalFileException rollback atomicity (forward & undo):
        failLocalSave = true;
        await notifier.completeTask('depGtwOkD2');
        expect(
          container
              .read(taskNotifierProvider)
              .requireValue
              .findTask('depGtwOkD2')!
              .isCompleted,
          isFalse,
          reason: 'Failed local save must roll back task completion',
        );
        expect(
          container.read(taskUndoStateProvider).stackDepth,
          equals(0),
          reason:
              'Rolled-back forward mutation must remove optimistic undo entry',
        );

        failLocalSave = false;
        await notifier.completeTask('depGtwOkD2');
        expect(container.read(taskUndoStateProvider).stackDepth, equals(1));
        failLocalSave = true;
        expect(await notifier.undoLastAction(), isFalse);
        expect(
          container.read(taskUndoStateProvider).stackDepth,
          equals(1),
          reason: 'Failed local save during undo must re-insert popped entry',
        );
        failLocalSave = false;
        expect(await notifier.undoLastAction(), isTrue);
        expect(container.read(taskUndoStateProvider).stackDepth, equals(0));

        // 5. Stack clearing on importLegacyTdf, wipeLocalFile, wipeRemoteFile, and workspace switch:
        await notifier.downgradeTask('depGtwOkD2');
        expect(container.read(taskUndoStateProvider).canUndo, isTrue);
        await notifier.importLegacyTdf(
          'tdf 0.6.0\ntask imp001OkD2 {\n    name "Imported"\n    created 2026-11-01 08:00\n}\n',
        );
        expect(
          container.read(taskUndoStateProvider).canUndo,
          isFalse,
          reason: 'importLegacyTdf must clear undo stack',
        );

        await notifier.deleteTask('imp001OkD2');
        expect(container.read(taskUndoStateProvider).canUndo, isTrue);
        await notifier.wipeLocalFile(initialConfig);
        expect(
          container.read(taskUndoStateProvider).canUndo,
          isFalse,
          reason: 'wipeLocalFile must clear undo stack',
        );

        await notifier.addTask('Remote Wipe Target', id: 'remWipOkD2');
        await notifier.deleteTask('remWipOkD2');
        expect(container.read(taskUndoStateProvider).canUndo, isTrue);
        await notifier.wipeRemoteFile(initialConfig);
        expect(
          container.read(taskUndoStateProvider).canUndo,
          isFalse,
          reason: 'wipeRemoteFile must clear undo stack',
        );

        await notifier.addTask('Select Local Target', id: 'selLocOkD2');
        await notifier.deleteTask('selLocOkD2');
        expect(container.read(taskUndoStateProvider).canUndo, isTrue);
        await notifier.selectLocalFile(
          initialConfig.copyWith(localFilePath: 'other.tdf'),
        );
        expect(
          container.read(taskUndoStateProvider).canUndo,
          isFalse,
          reason: 'selectLocalFile must clear undo stack',
        );

        await notifier.addTask('Workspace Switch Target', id: 'wsSwitOkD2');
        await notifier.deleteTask('wsSwitOkD2');
        expect(container.read(taskUndoStateProvider).canUndo, isTrue);
        remoteTdf = 'tdf 0.6.0\n';
        await container
            .read(activeWorkspaceProvider.notifier)
            .createWorkspace(
              'Second',
              config: WebDavConfig(
                storageMode: StorageMode.webdav,
                localFilePath: 'second.tdf',
                serverUrl: 'http://127.0.0.1:${server.port}',
                filePath: '/second.tdf',
                username: 'example-user',
                password: 'example-password',
              ),
              activate: true,
            );
        await container.read(taskNotifierProvider.future);
        expect(
          container.read(taskUndoStateProvider).canUndo,
          isFalse,
          reason: 'Switching active workspace must clear undo stack',
        );

        // 6. WebDAV-only complete+undo and delete+undo in Second workspace:
        final secondNotifier = container.read(taskNotifierProvider.notifier);
        await secondNotifier.addTask('WebDAV Only Task', id: 'webOnlOkD2');
        await secondNotifier.completeTask('webOnlOkD2');
        expect(await secondNotifier.undoLastAction(), isTrue);
        expect(
          container
              .read(taskNotifierProvider)
              .requireValue
              .findTask('webOnlOkD2')!
              .isCompleted,
          isFalse,
        );
        await secondNotifier.deleteTask('webOnlOkD2');
        expect(await secondNotifier.undoLastAction(), isTrue);
        expect(
          container
              .read(taskNotifierProvider)
              .requireValue
              .findTask('webOnlOkD2'),
          isNotNull,
        );
      });
    });
  });

  group('External Local File Reconciliation, Serialization, Undo Pruning & Wipe Convergence', () {
    late Directory watchTempDir;

    setUp(() async {
      HttpOverrides.global = null;
      watchTempDir = await Directory.systemTemp.createTemp(
        'tiertask_ext_reconcile_',
      );
    });

    tearDown(() async {
      if (await watchTempDir.exists()) {
        await watchTempDir.delete(recursive: true);
      }
    });

    test('serializes reconcileExternalLocalChanges pre-check I/O strictly in FIFO order with user mutations and retries transient FileSystemException locks once', () async {
      var diskTdf = 'tdf 0.6.0\n';
      Completer<void>? readGate;
      var activePreCheckOrSyncOps = 0;
      var maxConcurrentOps = 0;
      var transientLockRemaining = 0;
      var readDigestCalls = 0;
      var maxFileBytesOverride = LocalFileRepository.defaultMaxFileBytes;

      final settingsRepo = InMemorySettingsRepository(
        const WebDavConfig(storageMode: StorageMode.local),
      );
      var currentTime = DateTime.utc(2026, 11, 14, 10, 0);

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepo),
          clockProvider.overrideWithValue(() => currentTime),
          localFileWatchReadRetryDelayProvider.overrideWithValue(
            const Duration(milliseconds: 10),
          ),
          localFileRepositoryProvider.overrideWith((ref) {
            final cfg =
                ref.watch(webDavConfigProvider).asData?.value ??
                const WebDavConfig();
            return _GateableWatchLocalRepository(
              config: cfg,
              maxFileBytes: maxFileBytesOverride,
              getStore: () => diskTdf,
              setStore: (value) => diskTdf = value,
              onReadTdfWithDigest: () async {
                readDigestCalls++;
                activePreCheckOrSyncOps++;
                if (activePreCheckOrSyncOps > maxConcurrentOps) {
                  maxConcurrentOps = activePreCheckOrSyncOps;
                }
                try {
                  if (readGate case final gate?) {
                    await gate.future;
                  }
                  if (transientLockRemaining > 0) {
                    transientLockRemaining--;
                    throw const LocalFileException(
                      'File temporarily locked',
                      cause: FileSystemException('Sharing violation'),
                    );
                  }
                  final bytes = utf8.encode(diskTdf);
                  if (bytes.length > maxFileBytesOverride) {
                    throw const LocalFileException('Local file too large');
                  }
                } finally {
                  activePreCheckOrSyncOps--;
                }
              },
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(taskNotifierProvider.future);
      final notifier = container.read(taskNotifierProvider.notifier);

      // 1. Strict FIFO serialization while readTdfWithDigest() is suspended at await.
      diskTdf =
          'tdf 0.6.0\n\n'
          'queue {\n'
          '    modified 2026-11-14 10:01:00\n'
          '    task extFifo001\n'
          '}\n\n'
          'task extFifo001 {\n'
          '    name "External FIFO Task"\n'
          '    created 2026-11-14 10:01:00\n'
          '    modified 2026-11-14 10:01:00\n'
          '}\n';
      readGate = Completer<void>();

      final firstReconcile = notifier.reconcileExternalLocalChanges();
      await Future<void>.delayed(Duration.zero);
      currentTime = DateTime.utc(2026, 11, 14, 10, 2);
      final concurrentAdd = notifier.addTask(
        'In-App Queued Task',
        id: 'appFifo001',
      );
      final secondReconcile = notifier.reconcileExternalLocalChanges();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        maxConcurrentOps,
        equals(1),
        reason: 'Concurrent addTask and second reconcile must queue behind _inFlightSync',
      );

      final gateToRelease = readGate;
      readGate = null;
      gateToRelease.complete();

      expect(await firstReconcile, isTrue);
      await concurrentAdd;
      expect(
        await secondReconcile,
        isFalse,
        reason: 'Queued reconcile after converged addTask must skip on matching localSourceDigest',
      );
      expect(maxConcurrentOps, equals(1));

      final mergedTitles = container
          .read(taskNotifierProvider)
          .requireValue
          .allTasks
          .map((task) => task.title)
          .toList();
      expect(
        mergedTitles,
        containsAll(<String>['External FIFO Task', 'In-App Queued Task']),
      );

      // 2. Single 250ms-equivalent retry recovers from transient OS FileSystemException lock.
      diskTdf =
          '$diskTdf\n'
          'task extLock001 {\n'
          '    name "Recovered After Lock"\n'
          '    created 2026-11-14 10:03:00\n'
          '    modified 2026-11-14 10:03:00\n'
          '}\n';
      transientLockRemaining = 1;
      readDigestCalls = 0;
      expect(await notifier.reconcileExternalLocalChanges(), isTrue);
      expect(
        readDigestCalls,
        greaterThanOrEqualTo(2),
        reason: 'Must retry readTdfWithDigest once after transient FileSystemException',
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('extLock001')
            ?.title,
        equals('Recovered After Lock'),
      );
      expect(container.read(syncStateProvider).errorMessage, isNull);

      // 3. Persistent lock on both initial read and retry surfaces error and preserves board.
      transientLockRemaining = 2;
      expect(await notifier.reconcileExternalLocalChanges(), isFalse);
      expect(
        container.read(syncStateProvider).errorMessage,
        contains('File temporarily locked'),
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('extLock001'),
        isNotNull,
      );
      transientLockRemaining = 0;

      // 4. Oversized file (> maxFileBytes) fails immediately without retry.
      maxFileBytesOverride = 16;
      readDigestCalls = 0;
      expect(await notifier.reconcileExternalLocalChanges(), isFalse);
      expect(
        readDigestCalls,
        equals(1),
        reason: 'Non-FileSystemException maxFileBytes failure must not retry',
      );
      expect(
        container.read(syncStateProvider).errorMessage,
        contains('Local file too large'),
      );
    });

    test('selectively prunes only invalidated undo entries across external merges while preserving unrelated undo entries', () async {
      final settingsRepo = InMemorySettingsRepository(
        const WebDavConfig(
          localFilePath: 'undo_reconcile.tdf',
          storageMode: StorageMode.local,
        ),
      );
      var currentTime = DateTime.utc(2026, 11, 14, 11, 0);
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepo),
          localStorageDirectoryPathProvider.overrideWithValue(
            watchTempDir.path,
          ),
          clockProvider.overrideWithValue(() => currentTime),
        ],
      );
      addTearDown(container.dispose);

      await container.read(taskNotifierProvider.future);
      final notifier = container.read(taskNotifierProvider.notifier);

      await notifier.addTask('Keep Undo Task', id: 'uKeep00001');
      await notifier.addTask('Edit Target Task', id: 'uEdit00001');
      await notifier.addTask('Blocker Task', id: 'uBlkr00001');
      await notifier.addTask(
        'Dependent Task',
        id: 'uDepn00001',
        blockedByTaskIds: const <String>['uBlkr00001'],
      );

      currentTime = DateTime.utc(2026, 11, 14, 11, 1);
      await notifier.deleteTask('uKeep00001');
      currentTime = DateTime.utc(2026, 11, 14, 11, 2);
      await notifier.completeTask('uEdit00001');
      currentTime = DateTime.utc(2026, 11, 14, 11, 3);
      await notifier.completeTask('uBlkr00001');
      expect(container.read(taskUndoStateProvider).stackDepth, equals(3));

      // 1. Externally adding a task, label, and location keeps all 3 undo entries valid.
      final localFile = File('${watchTempDir.path}/undo_reconcile.tdf');
      final currentRaw = await localFile.readAsString();
      final withExternalAdditions =
          '$currentRaw\n'
          'location extLoc0001 {\n'
          '    name "External Office"\n'
          '    coordinates 52.52 13.405\n'
          '    radius 150\n'
          '    modified 2026-11-14 11:04:00\n'
          '}\n\n'
          'label extLbl0001 {\n'
          '    name "External Label"\n'
          '    color "#336699"\n'
          '    modified 2026-11-14 11:04:00\n'
          '}\n\n'
          'task extTsk0001 {\n'
          '    name "Externally Added Someday"\n'
          '    created 2026-11-14 11:04:00\n'
          '    modified 2026-11-14 11:04:00\n'
          '    labels extLbl0001\n'
          '}\n';
      await localFile.writeAsString(withExternalAdditions, flush: true);
      currentTime = DateTime.utc(2026, 11, 14, 11, 5);
      expect(await notifier.reconcileExternalLocalChanges(), isTrue);
      expect(
        container.read(taskUndoStateProvider).stackDepth,
        equals(3),
        reason: 'Unrelated external task/label/location additions must keep all undo entries',
      );

      // 2. Externally modifying uEdit00001 and dependent uDepn00001 prunes those 2 entries, leaving uKeep00001.
      final afterAddBoard = container
          .read(taskNotifierProvider)
          .requireValue
          .updateTask(
            'uEdit00001',
            title: 'Externally Renamed Target',
            currentDate: DateTime.utc(2026, 11, 14, 11, 6),
            localEvaluationTime: DateTime(2026, 11, 14, 11, 6),
          )
          .updateTask(
            'uDepn00001',
            title: 'Externally Edited Dependent',
            currentDate: DateTime.utc(2026, 11, 14, 11, 6),
            localEvaluationTime: DateTime(2026, 11, 14, 11, 6),
          );
      final externallyEdited = container
          .read(tdfServiceProvider)
          .serialize(afterAddBoard);
      await localFile.writeAsString(externallyEdited, flush: true);
      currentTime = DateTime.utc(2026, 11, 14, 11, 7);
      expect(await notifier.reconcileExternalLocalChanges(), isTrue);
      expect(
        container.read(taskUndoStateProvider).stackDepth,
        equals(1),
        reason: 'External edits to target and dependent tasks must prune only those 2 undo entries',
      );
      expect(
        container.read(taskUndoStateProvider).latestNotice,
        isNull,
        reason:
            'latestNotice belonging to pruned uBlkr00001 entry must be cleared',
      );

      // Remaining undo entry (uKeep00001 deletion) still reverses cleanly without losing external items!
      currentTime = DateTime.utc(2026, 11, 14, 11, 8);
      expect(await notifier.undoLastAction(), isTrue);
      final finalBoard = container.read(taskNotifierProvider).requireValue;
      expect(
        finalBoard.findTask('uKeep00001')?.title,
        equals('Keep Undo Task'),
      );
      expect(
        finalBoard.findTask('extTsk0001')?.title,
        equals('Externally Added Someday'),
      );
      expect(
        finalBoard.labels.map((label) => label.id),
        contains('extLbl0001'),
      );
      expect(finalBoard.locations.map((loc) => loc.id), contains('extLoc0001'));
    });

    test('handles StorageMode.both online WebDAV PUT convergence, offline Stage 1 commit, and wipeLocalFile + HTTP 304 cached remote recovery', () async {
      var remoteTdf = 'tdf 0.6.0\n';
      var remoteEtag = '"etag-1"';
      var etagCounter = 1;
      var failWebDav = false;
      var getCount = 0;
      var get304Count = 0;
      var putCount = 0;

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (failWebDav) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        if (request.method == 'GET') {
          getCount++;
          final ifNoneMatch = request.headers.value(
            HttpHeaders.ifNoneMatchHeader,
          );
          if (ifNoneMatch == remoteEtag) {
            get304Count++;
            request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
            request.response.statusCode = HttpStatus.notModified;
            await request.response.close();
            return;
          }
          request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
          request.response.statusCode = HttpStatus.ok;
          request.response.write(remoteTdf);
          await request.response.close();
          return;
        }
        if (request.method == 'PUT') {
          putCount++;
          remoteTdf = await utf8.decoder.bind(request).join();
          etagCounter++;
          remoteEtag = '"etag-$etagCounter"';
          request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
      });

      final bothConfig = WebDavConfig(
        serverUrl: 'http://127.0.0.1:${server.port}',
        username: 'example-user',
        password: 'example-password',
        filePath: '/both_tasks.tdf',
        localFilePath: 'both_tasks.tdf',
        storageMode: StorageMode.both,
      );
      final settingsRepo = InMemorySettingsRepository(bothConfig);
      var currentTime = DateTime.utc(2026, 11, 14, 12, 0);

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepo),
          localStorageDirectoryPathProvider.overrideWithValue(
            watchTempDir.path,
          ),
          clockProvider.overrideWithValue(() => currentTime),
        ],
      );
      addTearDown(container.dispose);

      await container.read(taskNotifierProvider.future);
      final notifier = container.read(taskNotifierProvider.notifier);
      await notifier.addTask('Initial Shared Task', id: 'shr0000001');
      final localFile = File('${watchTempDir.path}/both_tasks.tdf');

      // (a) Online external local edit -> automatic 3-way merge -> WebDAV PUT -> zero self-trigger loop.
      final baseLocal = await localFile.readAsString();
      await localFile.writeAsString(
        '$baseLocal\n'
        'task extOnline1 {\n'
        '    name "External Online Task"\n'
        '    created 2026-11-14 12:01:00\n'
        '    modified 2026-11-14 12:01:00\n'
        '}\n',
        flush: true,
      );
      final putsBeforeOnline = putCount;
      currentTime = DateTime.utc(2026, 11, 14, 12, 2);
      expect(await notifier.reconcileExternalLocalChanges(), isTrue);
      expect(
        putCount,
        equals(putsBeforeOnline + 1),
        reason: 'External local edit in Both mode must upload merged board via WebDAV PUT',
      );
      expect(remoteTdf, contains('External Online Task'));
      final getsAfterConverge = getCount;
      expect(
        await notifier.reconcileExternalLocalChanges(),
        isFalse,
        reason: 'Stage 2 local convergence must update localSourceDigest so follow-up watch events skip immediately',
      );
      expect(getCount, equals(getsAfterConverge));

      // (b) Offline WebDAV during external local edit commits Stage 1 locally and surfaces WebDAV error.
      failWebDav = true;
      final beforeOfflineRaw = await localFile.readAsString();
      await localFile.writeAsString(
        '$beforeOfflineRaw\n'
        'task extOfflin1 {\n'
        '    name "External Offline Task"\n'
        '    created 2026-11-14 12:03:00\n'
        '    modified 2026-11-14 12:03:00\n'
        '}\n',
        flush: true,
      );
      currentTime = DateTime.utc(2026, 11, 14, 12, 4);
      expect(
        await notifier.reconcileExternalLocalChanges(),
        isTrue,
        reason: 'Stage 1 local merge must commit in Both mode even when WebDAV fails',
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('extOfflin1')
            ?.title,
        equals('External Offline Task'),
      );
      expect(container.read(syncStateProvider).errorMessage, isNotNull);

      // Bring WebDAV back online and sync so local + remote converge.
      failWebDav = false;
      currentTime = DateTime.utc(2026, 11, 14, 12, 5);
      await notifier.syncFromRemote();
      expect(container.read(syncStateProvider).errorMessage, isNull);
      expect(remoteTdf, contains('External Offline Task'));

      // (c) wipeLocalFile in StorageMode.both suppresses watcher self-triggers and preserves remoteEtag / lastSyncedRemoteTdf for lossless HTTP 304 sync recovery.
      currentTime = DateTime.utc(2026, 11, 14, 12, 6);
      await notifier.wipeLocalFile(bothConfig);
      expect(
        container.read(taskNotifierProvider).requireValue.allTasks,
        isEmpty,
      );
      final getsBeforeWipeWatchCheck = getCount;
      expect(
        await notifier.reconcileExternalLocalChanges(),
        isFalse,
        reason: 'wipeLocalFile must record wipedDigest in localSourceDigest to suppress self-triggers',
      );
      expect(getCount, equals(getsBeforeWipeWatchCheck));

      final syncStateAfterWipe = await settingsRepo.loadWorkspaceSyncState(
        'tasks',
      );
      expect(syncStateAfterWipe.remoteEtag, equals(remoteEtag));
      expect(
        syncStateAfterWipe.lastSyncedRemoteTdf,
        contains('External Offline Task'),
      );

      final prev304 = get304Count;
      currentTime = DateTime.utc(2026, 11, 14, 12, 7);
      await notifier.syncFromRemote();
      expect(
        get304Count,
        equals(prev304 + 1),
        reason: 'Preserved remoteEtag after wipeLocalFile must allow HTTP 304 Not Modified',
      );
      final recoveredTitles = container
          .read(taskNotifierProvider)
          .requireValue
          .allTasks
          .map((task) => task.title)
          .toList();
      expect(
        recoveredTitles,
        containsAll(<String>[
          'Initial Shared Task',
          'External Online Task',
          'External Offline Task',
        ]),
        reason: 'HTTP 304 Not Modified after wipeLocalFile must merge cached remote tasks back into the board',
      );
    });

    test('prunes pending downgrade undo entry on external queue-only edits while preserving unaffected downgrade entries', () async {
      var diskContent = '';
      var currentTime = DateTime.utc(2026, 11, 14, 13, 0);
      final settingsRepo = InMemorySettingsRepository(
        const WebDavConfig(
          localFilePath: 'tasks.tdf',
          storageMode: StorageMode.local,
          localWatchEnabled: true,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepo),
          clockProvider.overrideWithValue(() => currentTime),
          localFileRepositoryProvider.overrideWith((ref) {
            final config = resolveCurrentConfig(ref);
            return _GateableWatchLocalRepository(
              config: config,
              maxFileBytes: 10485760,
              getStore: () => diskContent,
              setStore: (value) => diskContent = value,
              onReadTdfWithDigest: () async {},
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(taskNotifierProvider.future);
      final notifier = container.read(taskNotifierProvider.notifier);

      // Populate Ready (3 tasks) + Planned (2 tasks) so downgrades mutate only queue {}.
      await notifier.addTask('Ready 1', id: 'qReady0001');
      await notifier.addTask('Ready 2', id: 'qReady0002');
      await notifier.addTask('Ready 3', id: 'qReady0003');
      await notifier.addTask('Planned Keep', id: 'qPlanKep01');
      await notifier.addTask('Planned Target', id: 'qPlanTrg01');

      // Downgrade qPlanKep01 (Planned -> Someday) and qReady0001 (Ready -> Planned).
      currentTime = DateTime.utc(2026, 11, 14, 13, 1);
      await notifier.downgradeTask('qPlanKep01');
      currentTime = DateTime.utc(2026, 11, 14, 13, 2);
      await notifier.downgradeTask('qReady0001');
      expect(container.read(taskUndoStateProvider).stackDepth, equals(2));

      // External editor modifies ONLY queue {}: removes qReady0001 from queue (Planned -> Someday)
      // while leaving qPlanKep01 untouched (still absent from queue) and all task {} blocks untouched!
      final updatedQueueOnly = diskContent
          .replaceFirst('    task qReady0001\n', '')
          .replaceFirst(
            'queue {\n    modified 2026-11-14 13:02:00\n',
            'queue {\n    modified 2026-11-14 13:03:00\n',
          );
      expect(updatedQueueOnly, isNot(equals(diskContent)));
      diskContent = updatedQueueOnly;

      currentTime = DateTime.utc(2026, 11, 14, 13, 4);
      final merged = await notifier.reconcileExternalLocalChanges();
      expect(merged, isTrue);
      expect(
        container.read(taskUndoStateProvider).stackDepth,
        equals(1),
        reason: 'Downgrade undo entry for qReady0001 must be pruned after external queue removal, while qPlanKep01 remains valid',
      );

      // Undoing remaining entry must restore qPlanKep01 without pulling qReady0001 back out of Someday!
      currentTime = DateTime.utc(2026, 11, 14, 13, 5);
      await notifier.undoLastAction();
      final finalBoard = container.read(taskNotifierProvider).requireValue;
      expect(
        finalBoard.queueBlock.taskIds.contains('qPlanKep01'),
        isTrue,
        reason: 'Unaffected downgrade undo entry must still restore qPlanKep01',
      );
      expect(
        finalBoard.queueBlock.taskIds.contains('qReady0001'),
        isFalse,
        reason: 'Pruned downgrade undo entry must never overwrite external queue removal of qReady0001',
      );
    });

    test('queues reconcileExternalLocalChanges behind syncFromRemote AsyncLoading and clears open conflict on importLegacyTdf', () async {
      var diskContent = 'tdf 0.6.0\n\ntask broken0001 {\n';
      var remoteContent = 'tdf 0.6.0\n';
      Completer<void>? remoteFetchGate;
      var currentTime = DateTime.utc(2026, 11, 14, 14, 0);

      var failNextRemoteGet = false;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.method == 'GET') {
          if (remoteFetchGate case final gate?) {
            await gate.future;
          }
          if (failNextRemoteGet) {
            failNextRemoteGet = false;
            request.response.statusCode = HttpStatus.serviceUnavailable;
            await request.response.close();
            return;
          }
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.set(HttpHeaders.etagHeader, '"v1"')
            ..write(remoteContent);
          await request.response.close();
          return;
        }
        if (request.method == 'PUT') {
          remoteContent = await utf8.decoder.bind(request).join();
          request.response
            ..statusCode = HttpStatus.noContent
            ..headers.set(HttpHeaders.etagHeader, '"v2"');
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
      });

      final config = WebDavConfig(
        serverUrl: 'http://127.0.0.1:${server.port}',
        username: 'example-user',
        password: 'example-password',
        filePath: 'tasks.tdf',
        localFilePath: 'tasks.tdf',
        storageMode: StorageMode.both,
        localWatchEnabled: true,
      );
      final settingsRepo = InMemorySettingsRepository(config);
      final container = ProviderContainer(
        retry: disableProviderRetry,
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepo),
          clockProvider.overrideWithValue(() => currentTime),
          localFileRepositoryProvider.overrideWith((ref) {
            final latest = resolveCurrentConfig(ref);
            return _GateableWatchLocalRepository(
              config: latest,
              maxFileBytes: 10485760,
              getStore: () => diskContent,
              setStore: (value) => diskContent = value,
              onReadTdfWithDigest: () async {},
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      // Startup fails into AsyncError (!state.hasValue).
      await expectLater(
        () => container.read(taskNotifierProvider.future),
        throwsA(anything),
      );
      await container.pump();
      expect(container.read(taskNotifierProvider).hasError, isTrue);

      // Repair disk file, start syncFromRemote() (sets state = AsyncLoading() with !state.hasValue), and pause on Stage 2 GET!
      diskContent = 'tdf 0.6.0\n';
      failNextRemoteGet = true;
      remoteFetchGate = Completer<void>();
      final notifier = container.read(taskNotifierProvider.notifier);
      final syncFuture = notifier.syncFromRemote();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(taskNotifierProvider).isLoading, isTrue);

      // External edit arrives while syncFromRemote() is still in-flight!
      diskContent =
          'tdf 0.6.0\n\n'
          'task extSync001 {\n'
          '    name "Saved During SyncFromRemote"\n'
          '    created 2026-11-14 14:01:00\n'
          '    modified 2026-11-14 14:01:00\n'
          '}\n';
      final reconcileFuture = notifier.reconcileExternalLocalChanges();

      remoteFetchGate.complete();
      remoteFetchGate = null;
      await syncFuture;
      final reconciled = await reconcileFuture;
      expect(
        reconciled,
        isTrue,
        reason: 'reconcileExternalLocalChanges must queue behind in-flight syncFromRemote even when state started without a prior value',
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('extSync001')
            ?.title,
        equals('Saved During SyncFromRemote'),
      );

      // Also verify importLegacyTdf clears SyncState.hasOpenConflict!
      container
          .read(syncStateProvider.notifier)
          .setConflict('Unresolved deletionConflict');
      expect(container.read(syncStateProvider).hasOpenConflict, isTrue);

      currentTime = DateTime.utc(2026, 11, 14, 14, 5);
      await notifier.importLegacyTdf(
        'tdf 0.6.0\n\n'
        'task import0001 {\n'
        '    name "Imported Clean Board"\n'
        '    created 2026-11-14 14:05:00\n'
        '    modified 2026-11-14 14:05:00\n'
        '}\n',
      );
      expect(
        container.read(syncStateProvider).hasOpenConflict,
        isFalse,
        reason: 'importLegacyTdf must clear SyncState.hasOpenConflict',
      );
      expect(container.read(syncStateProvider).errorMessage, isNull);
    });
  });
}

class _GateableWatchLocalRepository extends LocalFileRepository {
  _GateableWatchLocalRepository({
    required super.config,
    required super.maxFileBytes,
    required this.getStore,
    required this.setStore,
    required this.onReadTdfWithDigest,
  });

  final String Function() getStore;
  final Future<void> Function() onReadTdfWithDigest;
  final void Function(String value) setStore;

  @override
  bool get canWatchDirectory => false;

  @override
  bool fileExists() => getStore().isNotEmpty;

  @override
  Future<String> loadTdf() async => getStore();

  @override
  Future<({String content, String? digest, bool exists})>
  readTdfWithDigest() async {
    await onReadTdfWithDigest();
    return super.readTdfWithDigest();
  }

  @override
  Future<void> saveTdf(String tdfContent) async => setStore(tdfContent);
}
