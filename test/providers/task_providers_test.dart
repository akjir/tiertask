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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_metadata.dart';
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
  });
}
