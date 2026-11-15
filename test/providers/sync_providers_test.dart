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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_board_evaluator.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/models/workspace_sync_state.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/sync_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';
import 'package:tiertask/services/tdf_service.dart';

class _CountingTdfService extends TdfService {
  const _CountingTdfService(this.onParse);

  final void Function() onParse;

  @override
  TaskBoard parse(
    String tdfContent, {
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
    bool pruneExpiredCompleted = false,
    TdfSchemaVersion targetSchema = TdfSchemaVersion.v070,
  }) {
    onParse();
    return super.parse(
      tdfContent,
      evaluationTime: evaluationTime,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      activeLabelId: activeLabelId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
      pruneExpiredCompleted: pruneExpiredCompleted,
      targetSchema: targetSchema,
    );
  }
}

class _InMemorySyncLocalRepository extends LocalFileRepository {
  _InMemorySyncLocalRepository({
    required super.config,
    required this.getTdf,
    required this.setTdf,
  });

  final String Function() getTdf;
  final void Function(String value) setTdf;

  @override
  bool get canWatchDirectory => false;

  @override
  bool fileExists() => getTdf().isNotEmpty;

  @override
  Future<String> loadTdf() async => getTdf();

  @override
  Future<void> saveTdf(String tdfContent) async => setTdf(tdfContent);
}

class _InMemorySyncWebDavRepository extends WebDavRepository {
  _InMemorySyncWebDavRepository({
    required super.config,
    required this.getTdf,
    required this.setTdf,
    required this.isOnline,
  });

  final String Function() getTdf;
  final bool Function() isOnline;
  final void Function(String value) setTdf;

  @override
  Future<String> fetchTdf() async {
    if (!isOnline()) {
      throw const WebDavException('Network unreachable');
    }
    return getTdf();
  }

  @override
  Future<void> saveTdf(String tdfContent) async {
    if (!isOnline()) {
      throw const WebDavException('Network unreachable while saving');
    }
    setTdf(tdfContent);
  }
}

void main() {
  const bothConfig = WebDavConfig(
    storageMode: StorageMode.both,
    localFilePath: 'tasks.tdf',
    serverUrl: 'https://cloud.example.com/dav/',
    username: 'alice',
    password: 'secret',
    filePath: 'tasks.tdf',
  );

  ProviderContainer createSyncContainer({
    required SettingsRepository settingsRepository,
    required DateTime Function() clock,
    required String Function() getLocal,
    required void Function(String) setLocal,
    required String Function() getRemote,
    required void Function(String) setRemote,
    required bool Function() isOnline,
    WebDavConfig config = bothConfig,
  }) {
    return ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settingsRepository),
        clockProvider.overrideWithValue(clock),
        localFileRepositoryProvider.overrideWith(
          (ref) => _InMemorySyncLocalRepository(
            config: config,
            getTdf: getLocal,
            setTdf: setLocal,
          ),
        ),
        webDavRepositoryProvider.overrideWith(
          (ref) => _InMemorySyncWebDavRepository(
            config: config,
            getTdf: getRemote,
            setTdf: setRemote,
            isOnline: isOnline,
          ),
        ),
      ],
    );
  }

  test('SyncStateNotifier tracks syncing, success, error, clearError, and resets when active workspace switches', () async {
    final settingsRepository = InMemorySettingsRepository();
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settingsRepository),
      ],
    );
    addTearDown(container.dispose);

    await container.read(activeWorkspaceProvider.future);
    final notifier = container.read(syncStateProvider.notifier);

    expect(container.read(syncStateProvider), equals(const SyncState()));

    notifier.setSyncing();
    expect(container.read(syncStateProvider).isSyncing, isTrue);

    final syncedAt = DateTime.utc(2026, 11, 1, 10);
    notifier.setSuccess(syncedAt);
    expect(
      container.read(syncStateProvider),
      equals(SyncState(isSyncing: false, lastSyncedAt: syncedAt)),
    );
    expect(
      container.read(syncStateProvider).hashCode,
      equals(SyncState(isSyncing: false, lastSyncedAt: syncedAt).hashCode),
    );

    notifier.setError('Connection failed');
    expect(container.read(syncStateProvider).isSyncing, isFalse);
    expect(container.read(syncStateProvider).hasOpenConflict, isFalse);
    expect(
      container.read(syncStateProvider).errorMessage,
      equals('Connection failed'),
    );

    notifier.setConflict('Deletion conflict on taskA');
    expect(container.read(syncStateProvider).isSyncing, isFalse);
    expect(container.read(syncStateProvider).hasOpenConflict, isTrue);
    expect(
      container.read(syncStateProvider).errorMessage,
      equals('Deletion conflict on taskA'),
    );

    notifier.clearError();
    expect(container.read(syncStateProvider).errorMessage, isNull);
    expect(
      container.read(syncStateProvider).hasOpenConflict,
      isFalse,
      reason: 'clearError must reset hasOpenConflict to false',
    );
    expect(container.read(syncStateProvider).lastSyncedAt, equals(syncedAt));

    notifier.setConflict('Another conflict');
    notifier.setSyncing();
    expect(
      container.read(syncStateProvider).hasOpenConflict,
      isFalse,
      reason: 'setSyncing must reset hasOpenConflict to false',
    );
    notifier.setConflict('Conflict before success');
    notifier.setSuccess(syncedAt);
    expect(container.read(syncStateProvider).hasOpenConflict, isFalse);

    notifier.setError('Stale workspace error');
    await container
        .read(activeWorkspaceProvider.notifier)
        .createWorkspace('Second', activate: true);
    expect(
      container.read(syncStateProvider),
      equals(const SyncState()),
      reason: 'Switching active workspace must reset SyncState',
    );
  });

  test('Two-stage save pipeline merges external local file edits first and then merges with WebDAV on save', () async {
    var currentTime = DateTime.utc(2026, 11, 1, 9);
    var localTdf =
        'tdf 0.5.0\n\nqueue {\n  modified 2026-11-01 08:00:00\n  task 000001OkD2\n}\n\nlabel work00OkD2 {\n  name "Work"\n  modified 2026-11-01 08:00:00\n}\n\ntask 000001OkD2 {\n  name "Initial Task"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 08:00:00\n  queued 2026-11-01 08:00:00\n}\n';
    var remoteTdf = localTdf;
    final settingsRepository = InMemorySettingsRepository(bothConfig);

    final container = createSyncContainer(
      settingsRepository: settingsRepository,
      clock: () => currentTime,
      getLocal: () => localTdf,
      setLocal: (value) => localTdf = value,
      getRemote: () => remoteTdf,
      setRemote: (value) => remoteTdf = value,
      isOnline: () => true,
    );
    addTearDown(container.dispose);

    final initialBoard = await container.read(taskNotifierProvider.future);
    expect(
      initialBoard.allTasks.map((task) => task.title),
      contains('Initial Task'),
    );

    localTdf = 'tdf 0.5.0\n\nqueue {\n  modified 2026-11-01 09:30:00\n  task 000001OkD2\n  task 000002OkD2\n}\n\nlabel work00OkD2 {\n  name "Work"\n  modified 2026-11-01 08:00:00\n}\n\ntask 000001OkD2 {\n  name "Initial Task"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 08:00:00\n  queued 2026-11-01 08:00:00\n}\n\ntask 000002OkD2 {\n  name "External Local Task"\n  created 2026-11-01 09:30:00\n  modified 2026-11-01 09:30:00\n  queued 2026-11-01 09:30:00\n}\n';
    remoteTdf = 'tdf 0.5.0\n\nqueue {\n  modified 2026-11-01 08:00:00\n  task 000001OkD2\n}\n\nlabel work00OkD2 {\n  name "Enterprise"\n  modified 2026-11-01 09:45:00\n}\n\ntask 000001OkD2 {\n  name "Initial Task"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 08:00:00\n  queued 2026-11-01 08:00:00\n}\n';

    currentTime = DateTime.utc(2026, 11, 1, 10);
    await container
        .read(taskNotifierProvider.notifier)
        .addTask('In-Memory Task', targetTier: TaskTier.someday);

    final mergedBoard = container.read(taskNotifierProvider).requireValue;
    expect(
      mergedBoard.allTasks.map((task) => task.title),
      containsAll(<String>[
        'Initial Task',
        'External Local Task',
        'In-Memory Task',
      ]),
    );
    expect(mergedBoard.findLabel('work00OkD2')?.name, equals('Enterprise'));
    expect(localTdf, equals(remoteTdf));
    expect(localTdf, contains('tdf 0.7.0'));
  });

  test('Offline WebDAV save failure preserves local file sync and merges per-entity when connection returns', () async {
    var currentTime = DateTime.utc(2026, 11, 1, 8);
    var isOnline = true;
    var localTdf =
        'tdf 0.5.0\n\nqueue {\n  modified 2026-11-01 08:00:00\n  task 000001OkD2\n  task 000002OkD2\n}\n\nlabel ops000OkD2 {\n  name "Ops"\n  modified 2026-11-01 08:00:00\n}\n\ntask 000001OkD2 {\n  name "Task One"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 08:00:00\n  queued 2026-11-01 08:00:00\n}\n\ntask 000002OkD2 {\n  name "Task Two"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 08:00:00\n  queued 2026-11-01 08:00:00\n}\n';
    var remoteTdf = localTdf;
    final settingsRepository = InMemorySettingsRepository(bothConfig);

    final container1 = createSyncContainer(
      settingsRepository: settingsRepository,
      clock: () => currentTime,
      getLocal: () => localTdf,
      setLocal: (value) => localTdf = value,
      getRemote: () => remoteTdf,
      setRemote: (value) => remoteTdf = value,
      isOnline: () => isOnline,
    );
    await container1.read(taskNotifierProvider.future);

    isOnline = false;
    currentTime = DateTime.utc(2026, 11, 1, 9);
    await container1
        .read(taskNotifierProvider.notifier)
        .completeTask('000001OkD2');
    await container1
        .read(taskNotifierProvider.notifier)
        .deleteLabel('ops000OkD2');

    expect(container1.read(syncStateProvider).errorMessage, isNotNull);
    expect(localTdf, contains('finished    2026-11-01 09:00'));

    remoteTdf = 'tdf 0.5.0\n\nqueue {\n  modified 2026-11-01 08:00:00\n  task 000001OkD2\n  task 000002OkD2\n}\n\nlabel ops000OkD2 {\n  name "Ops"\n  modified 2026-11-01 08:00:00\n}\n\ntask 000001OkD2 {\n  name "Task One"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 08:00:00\n  queued 2026-11-01 08:00:00\n}\n\ntask 000002OkD2 {\n  name "Task Two Updated On Remote"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 09:30:00\n  queued 2026-11-01 08:00:00\n}\n';

    container1.dispose();
    isOnline = true;
    currentTime = DateTime.utc(2026, 11, 1, 10);
    final container2 = createSyncContainer(
      settingsRepository: settingsRepository,
      clock: () => currentTime,
      getLocal: () => localTdf,
      setLocal: (value) => localTdf = value,
      getRemote: () => remoteTdf,
      setRemote: (value) => remoteTdf = value,
      isOnline: () => isOnline,
    );
    addTearDown(container2.dispose);

    final convergedBoard = await container2.read(taskNotifierProvider.future);
    expect(convergedBoard.findTask('000001OkD2')?.isCompleted, isTrue);
    expect(
      convergedBoard.findTask('000002OkD2')?.title,
      equals('Task Two Updated On Remote'),
    );
    expect(convergedBoard.findLabel('ops000OkD2'), isNull);

    final activeWorkspace = await container2.read(
      activeWorkspaceProvider.future,
    );
    final syncStateAfter = await settingsRepository.loadWorkspaceSyncState(
      activeWorkspace.id,
    );
    expect(syncStateAfter.deletedLabelTimestamps, isEmpty);
  });

  test('Explicitly importing a legacy tdf 0.3.0 document via TaskNotifier.importLegacyTdf migrates IDs via SHA-256 Base62, resets sync baseline per Section 10.1, and syncs tdf 0.5.1 to local and WebDAV storage', () async {
    final currentTime = DateTime.utc(2026, 11, 1, 12);
    const legacyTdf =
        'tdf 0.3.0\n\nlabel l_work00_OkD2 {\n  name "Work"\n  modified 2026-11-01 08:00\n}\n\ntask t_000001_OkD2 {\n  name "Legacy First Task"\n  created 2026-11-01 08:00\n  queued 2026-11-01 08:00\n  labels l_work00_OkD2\n}\n\ntask t002 {\n  name "Legacy Blocked Task"\n  created 2026-11-01 08:30\n  queued 2026-11-01 08:30\n  blocked t_000001_OkD2\n  labels l_work00_OkD2\n}\n';
    var localTdf = 'tdf 0.5.0\n';
    var remoteTdf = 'tdf 0.5.0\n';
    var localSaveCount = 0;
    var remoteSaveCount = 0;
    final settingsRepository = InMemorySettingsRepository(bothConfig);

    final container = createSyncContainer(
      settingsRepository: settingsRepository,
      clock: () => currentTime,
      getLocal: () => localTdf,
      setLocal: (value) {
        localSaveCount++;
        localTdf = value;
      },
      getRemote: () => remoteTdf,
      setRemote: (value) {
        remoteSaveCount++;
        remoteTdf = value;
      },
      isOnline: () => true,
    );
    addTearDown(container.dispose);

    await container.read(taskNotifierProvider.future);
    final importResult = await container
        .read(taskNotifierProvider.notifier)
        .importLegacyTdf(legacyTdf);
    final board = importResult.board;

    expect(board.labels.length, equals(1));
    expect(board.allTasks.length, equals(2));

    final convertedLabelId = board.labels.single.id;
    final convertedFirstTaskId = board.focus.single.id;
    final convertedSecondTaskId = board.blocked.single.id;

    expect(isValidLabelId(convertedLabelId), isTrue);
    expect(isValidTaskId(convertedFirstTaskId), isTrue);
    expect(isValidTaskId(convertedSecondTaskId), isTrue);
    expect(board.focus.single.labelIds, equals([convertedLabelId]));
    expect(board.blocked.single.labelIds, equals([convertedLabelId]));
    expect(
      board.blocked.single.blockedByTaskIds,
      equals([convertedFirstTaskId]),
    );

    expect(localSaveCount, greaterThanOrEqualTo(1));
    expect(remoteSaveCount, greaterThanOrEqualTo(1));
    expect(localTdf, startsWith('tdf 0.7.0\n'));
    expect(remoteTdf, equals(localTdf));
  });

  test('Unsupported TDF version on remote, local, or both stops retrying, never overwrites unreadable files, and surfaces localized update recommendations', () async {
    const service = TdfService();
    expect(
      () => service.parse('tdf 0.8.0\n'),
      throwsA(
        isA<TdfException>()
            .having(
              (error) => error.kind,
              'kind',
              equals(TdfErrorKind.unsupportedVersion),
            )
            .having((error) => error.sourceVersion, 'sourceVersion', '0.8.0')
            .having((error) => error.targetVersion, 'targetVersion', '0.7.0'),
      ),
    );

    final currentTime = DateTime.utc(2026, 11, 1, 12);
    var remoteFetchCount = 0;
    var remoteSaveCount = 0;
    var remoteTdf = 'tdf 0.8.0\n';
    const webDavDeConfig = WebDavConfig(
      storageMode: StorageMode.webdav,
      language: AppLanguage.german,
      serverUrl: 'https://cloud.example.com/dav/',
      username: 'alice',
      password: 'secret',
      filePath: 'tasks.tdf',
    );
    final webDavContainer = createSyncContainer(
      config: webDavDeConfig,
      settingsRepository: InMemorySettingsRepository(webDavDeConfig),
      clock: () => currentTime,
      getLocal: () => '',
      setLocal: (_) {},
      getRemote: () {
        remoteFetchCount++;
        return remoteTdf;
      },
      setRemote: (value) {
        remoteSaveCount++;
        remoteTdf = value;
      },
      isOnline: () => true,
    );
    addTearDown(webDavContainer.dispose);

    Object? caughtRemoteError;
    try {
      await webDavContainer.read(taskNotifierProvider.future);
    } on Object catch (error) {
      caughtRemoteError = error;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(remoteFetchCount, equals(1));
    expect(remoteSaveCount, equals(0));
    expect(
      caughtRemoteError.toString(),
      equals(
        'Die Remote-Datei verwendet die nicht unterstützte Dateiversion 0.8.0. Bitte aktualisieren Sie TierTask auf eine neuere Version.',
      ),
    );

    var localFailSaveCount = 0;
    const bothEnConfig = WebDavConfig(
      storageMode: StorageMode.both,
      language: AppLanguage.english,
      localFilePath: 'tasks.tdf',
      serverUrl: 'https://cloud.example.com/dav/',
      username: 'alice',
      password: 'secret',
      filePath: 'tasks.tdf',
    );
    final bothLocalFailContainer = createSyncContainer(
      config: bothEnConfig,
      settingsRepository: InMemorySettingsRepository(bothEnConfig),
      clock: () => currentTime,
      getLocal: () => 'tdf 0.8.0\n',
      setLocal: (_) => localFailSaveCount++,
      getRemote: () => 'tdf 0.7.0\n',
      setRemote: (_) {},
      isOnline: () => true,
    );
    addTearDown(bothLocalFailContainer.dispose);

    Object? caughtLocalError;
    try {
      await bothLocalFailContainer.read(taskNotifierProvider.future);
    } on Object catch (error) {
      caughtLocalError = error;
    }
    expect(localFailSaveCount, equals(0));
    expect(
      caughtLocalError.toString(),
      equals(
        'The local file uses unsupported file version 0.8.0. Please update TierTask to a newer version.',
      ),
    );

    var bothFailRemoteFetchCount = 0;
    const bothDeConfig = WebDavConfig(
      storageMode: StorageMode.both,
      language: AppLanguage.german,
      localFilePath: 'tasks.tdf',
      serverUrl: 'https://cloud.example.com/dav/',
      username: 'alice',
      password: 'secret',
      filePath: 'tasks.tdf',
    );
    final bothFailContainer = createSyncContainer(
      config: bothDeConfig,
      settingsRepository: InMemorySettingsRepository(bothDeConfig),
      clock: () => currentTime,
      getLocal: () => 'tdf 0.8.0\n',
      setLocal: (_) {},
      getRemote: () {
        bothFailRemoteFetchCount++;
        return 'tdf 0.9.0\n';
      },
      setRemote: (_) {},
      isOnline: () => true,
    );
    addTearDown(bothFailContainer.dispose);

    Object? caughtBothFailError;
    try {
      await bothFailContainer.read(taskNotifierProvider.future);
    } on Object catch (error) {
      caughtBothFailError = error;
    }
    expect(bothFailRemoteFetchCount, equals(1));
    expect(
      caughtBothFailError.toString(),
      equals(
        'Die lokale Datei und die Remote-Datei verwenden die nicht unterstützte Dateiversion 0.8.0 / 0.9.0. Bitte aktualisieren Sie TierTask auf eine neuere Version.',
      ),
    );
  });

  test('TaskSyncPipeline.runSyncWithStatus records exact UTC clockProvider timestamp in syncStateProvider.lastSyncedAt', () async {
    final fixedClock = DateTime(2026, 11, 1, 14, 30, 15);
    var localTdf = 'tdf 0.5.1\n';
    var remoteTdf = 'tdf 0.5.1\n';
    final settingsRepository = InMemorySettingsRepository(bothConfig);

    final container = createSyncContainer(
      settingsRepository: settingsRepository,
      clock: () => fixedClock,
      getLocal: () => localTdf,
      setLocal: (value) => localTdf = value,
      getRemote: () => remoteTdf,
      setRemote: (value) => remoteTdf = value,
      isOnline: () => true,
    );
    addTearDown(container.dispose);

    await container.read(taskNotifierProvider.future);
    final syncState = container.read(syncStateProvider);
    expect(
      syncState.isSyncing,
      isFalse,
      reason: 'Sync should complete and clear isSyncing flag',
    );
    expect(
      syncState.lastSyncedAt,
      equals(fixedClock.toUtc()),
      reason: 'lastSyncedAt must match the injected clockProvider UTC timestamp instead of wall-clock DateTime.now()',
    );
    expect(
      syncState.lastSyncedAt?.isUtc,
      isTrue,
      reason: 'lastSyncedAt must be normalized to UTC',
    );
  });

  test('TaskSyncPipeline.flushOutgoingLocalBoard flushes local board when configured and swallows save exceptions', () async {
    var savedTdf = '';
    var shouldThrow = false;
    final settingsRepository = InMemorySettingsRepository(bothConfig);
    final container = createSyncContainer(
      settingsRepository: settingsRepository,
      clock: () => DateTime.utc(2026, 11, 1, 12),
      getLocal: () => savedTdf,
      setLocal: (value) {
        if (shouldThrow) {
          throw const LocalFileException('Simulated disk full');
        }
        savedTdf = value;
      },
      getRemote: () => savedTdf,
      setRemote: (value) => savedTdf = value,
      isOnline: () => true,
    );
    addTearDown(container.dispose);

    final workspace = await container.read(activeWorkspaceProvider.future);
    final board = TaskBoard.empty().addTask(
      'Flush Test Task',
      currentDate: DateTime.utc(2026, 11, 1, 12),
    );
    final flushProvider = FutureProvider.family<void, TaskBoard>(
      (ref, targetBoard) =>
          TaskSyncPipeline.flushOutgoingLocalBoard(ref, workspace, targetBoard),
    );

    await container.read(flushProvider(board).future);
    expect(
      savedTdf,
      contains('Flush Test Task'),
      reason: 'Normal flush should serialize and save board to local storage',
    );

    shouldThrow = true;
    final secondBoard = board.addTask(
      'Failing Flush Task',
      currentDate: DateTime.utc(2026, 11, 1, 12, 5),
    );
    await expectLater(
      container.read(flushProvider(secondBoard).future),
      completes,
      reason: 'Best-effort flush must swallow repository exceptions',
    );
    expect(
      savedTdf,
      isNot(contains('Failing Flush Task')),
      reason: 'Failed save should leave previous local content intact',
    );
  });

  test('Corrupted baseline TDF in SettingsRepository recovers via 2-way merge without throwing', () async {
    final currentTime = DateTime.utc(2026, 11, 1, 12);
    var localTdf =
        'tdf 0.5.1\n\nqueue {\n  modified 2026-11-01 08:00:00\n  task 000001OkD2\n}\n\ntask 000001OkD2 {\n  name "Local Surviving Task"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 08:00:00\n}\n';
    var remoteTdf =
        'tdf 0.5.1\n\nqueue {\n  modified 2026-11-01 09:00:00\n  task 000002OkD2\n}\n\ntask 000002OkD2 {\n  name "Remote Surviving Task"\n  created 2026-11-01 09:00:00\n  modified 2026-11-01 09:00:00\n}\n';
    final settingsRepository = InMemorySettingsRepository(bothConfig);
    final activeWorkspace = await settingsRepository.loadActiveWorkspace();
    await settingsRepository.saveWorkspaceSyncState(
      activeWorkspace.id,
      WorkspaceSyncState(
        lastSyncedLocalTdf: 'corrupted_header_without_version\n{{{',
        lastSyncedRemoteTdf: 'tdf 0.5.1\ntask broken {\n',
        acknowledgedLocalGeneration: 3,
        acknowledgedRemoteGeneration: 3,
      ),
    );

    final container = createSyncContainer(
      settingsRepository: settingsRepository,
      clock: () => currentTime,
      getLocal: () => localTdf,
      setLocal: (value) => localTdf = value,
      getRemote: () => remoteTdf,
      setRemote: (value) => remoteTdf = value,
      isOnline: () => true,
    );
    addTearDown(container.dispose);

    final mergedBoard = await container.read(taskNotifierProvider.future);
    expect(
      mergedBoard.allTasks.map((task) => task.title),
      containsAll(<String>['Local Surviving Task', 'Remote Surviving Task']),
      reason: 'Corrupted local and remote baselines must fall back to 2-way merge and retain tasks from both sides',
    );
  });

  test('TaskSyncPipeline.importLegacyTdf applies manual timeZoneMode offset when sourceTimeZone is omitted', () async {
    final currentTime = DateTime.utc(2026, 11, 1, 12);
    const manualConfig = WebDavConfig(
      storageMode: StorageMode.local,
      localFilePath: 'tasks.tdf',
      timeZoneMode: AppTimeZoneMode.manual,
      manualTimeZoneOffsetMinutes: 120,
    );
    const legacyTdf =
        'tdf 0.2.0\n\ntask 000001OkD2 {\n  name "Manual Offset Legacy Task"\n  created 2026-11-01 10:00\n  queued 2026-11-01 10:00\n}\n';
    var localTdf = 'tdf 0.5.1\n';
    final settingsRepository = InMemorySettingsRepository(manualConfig);

    final container = createSyncContainer(
      config: manualConfig,
      settingsRepository: settingsRepository,
      clock: () => currentTime,
      getLocal: () => localTdf,
      setLocal: (value) => localTdf = value,
      getRemote: () => '',
      setRemote: (_) {},
      isOnline: () => true,
    );
    addTearDown(container.dispose);

    await container.read(taskNotifierProvider.future);
    final importResult = await container
        .read(taskNotifierProvider.notifier)
        .importLegacyTdf(legacyTdf);
    final importedTask = importResult.board.allTasks.single;
    expect(
      importedTask.createdAt,
      equals(DateTime.utc(2026, 11, 1, 8)),
      reason: '10:00 local in manual +02:00 offset must convert to 08:00 UTC during 0.2.0 -> 0.5.1 import',
    );
    expect(
      localTdf,
      contains('created 2026-11-01 08:00'),
      reason: 'Persisted migrated TDF must contain the UTC-converted timestamp',
    );
  });

  test('Universal 3-retry CAS-merge loop resolves concurrent local file edits before save and aborts after maxCasRetries', () async {
    expect(TaskSyncPipeline.maxCasRetries, equals(3));
    var currentTime = DateTime.utc(2026, 11, 1, 10);
    var localTdf =
        'tdf 0.6.0\n\nqueue {\n  modified 2026-11-01 08:00:00\n  task 000001OkD2\n}\n\ntask 000001OkD2 {\n  name "Base Task"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 08:00:00\n}\n';
    var readCallCount = 0;
    var injectConcurrentEditsRemaining = 2;
    const localOnlyConfig = WebDavConfig(
      storageMode: StorageMode.local,
      localFilePath: 'tasks.tdf',
    );
    final settingsRepository = InMemorySettingsRepository(localOnlyConfig);

    final container = createSyncContainer(
      config: localOnlyConfig,
      settingsRepository: settingsRepository,
      clock: () => currentTime,
      getLocal: () {
        readCallCount++;
        if (readCallCount > 1 && injectConcurrentEditsRemaining > 0) {
          final taskIndex = 3 - injectConcurrentEditsRemaining;
          injectConcurrentEditsRemaining--;
          localTdf =
              '$localTdf\ntask 00000${taskIndex + 1}OkD2 {\n  name "Concurrent Task $taskIndex"\n  created 2026-11-01 09:0$taskIndex:00\n  modified 2026-11-01 09:0$taskIndex:00\n}\n';
        }
        return localTdf;
      },
      setLocal: (value) => localTdf = value,
      getRemote: () => '',
      setRemote: (_) {},
      isOnline: () => false,
    );
    addTearDown(container.dispose);

    final initialBoard = await container.read(taskNotifierProvider.future);
    expect(
      initialBoard.allTasks.map((task) => task.title),
      containsAll(<String>[
        'Base Task',
        'Concurrent Task 1',
        'Concurrent Task 2',
      ]),
    );

    injectConcurrentEditsRemaining = 4;
    currentTime = DateTime.utc(2026, 11, 1, 11);
    await container
        .read(taskNotifierProvider.notifier)
        .addTask('Contended Task', targetTier: TaskTier.someday);
    expect(
      container.read(syncStateProvider).errorMessage,
      isNotNull,
      reason: 'Exceeding 3 CAS retries must surface a LocalFileException error in syncStateProvider',
    );
  });

  test('WebDAV 304 Not Modified skips remote TDF parsing, 3-way merge, and PUT upload, and 412 Precondition Failed retries via 3-way merge', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    const canonicalInitial =
        'tdf 0.7.0\n\nqueue {\n    modified 2026-11-01 08:00:00\n    task 000001OkD2\n}\n\ntask 000001OkD2 {\n    name     "Initial Task"\n    created  2026-11-01 08:00\n    modified 2026-11-01 08:00\n}\n';
    var remoteTdf = canonicalInitial;
    var remoteEtag = '"etag-v1"';
    var remoteLastModified = 'Mon, 09 Nov 2026 22:00:00 GMT';
    var get200Count = 0;
    var get304Count = 0;
    var putCount = 0;
    var injectConcurrentRemoteEditOnNextPut = false;

    server.listen((HttpRequest request) async {
      if (request.method == 'GET') {
        final ifNoneMatch = request.headers.value(
          HttpHeaders.ifNoneMatchHeader,
        );
        if (ifNoneMatch == remoteEtag) {
          get304Count++;
          request.response.statusCode = HttpStatus.notModified;
          request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
          request.response.headers.set(
            HttpHeaders.lastModifiedHeader,
            remoteLastModified,
          );
          await request.response.close();
          return;
        }
        get200Count++;
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
        request.response.headers.set(
          HttpHeaders.lastModifiedHeader,
          remoteLastModified,
        );
        request.response.write(remoteTdf);
        await request.response.close();
        return;
      }

      if (request.method == 'PUT') {
        putCount++;
        final body = await utf8.decoder.bind(request).join();
        final ifMatch = request.headers.value(HttpHeaders.ifMatchHeader);
        if (injectConcurrentRemoteEditOnNextPut) {
          injectConcurrentRemoteEditOnNextPut = false;
          remoteTdf = 'tdf 0.7.0\n\nqueue {\n    modified 2026-11-01 08:00:00\n    task 000001OkD2\n}\n\ntask 000001OkD2 {\n    name     "Initial Task"\n    created  2026-11-01 08:00\n    modified 2026-11-01 08:00\n}\n\ntask 000002OkD2 {\n    name     "Concurrent Server Task"\n    created  2026-11-01 09:30\n    modified 2026-11-01 09:30\n}\n';
          remoteEtag = '"etag-concurrent"';
        }
        if (ifMatch != null && ifMatch != remoteEtag) {
          request.response.statusCode = HttpStatus.preconditionFailed;
          await request.response.close();
          return;
        }
        remoteTdf = body;
        remoteEtag = '"etag-put-$putCount"';
        remoteLastModified = 'Mon, 09 Nov 2026 22:0$putCount:00 GMT';
        request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
        request.response.headers.set(
          HttpHeaders.lastModifiedHeader,
          remoteLastModified,
        );
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      }
    });

    var currentTime = DateTime.utc(2026, 11, 1, 9);
    var parseCount = 0;
    final webdavOnlyConfig = WebDavConfig(
      storageMode: StorageMode.webdav,
      serverUrl: 'http://${server.address.host}:${server.port}',
      username: 'alice',
      password: 'secret',
      filePath: 'tasks.tdf',
    );
    final settingsRepository = InMemorySettingsRepository(webdavOnlyConfig);

    final container1 = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settingsRepository),
        clockProvider.overrideWithValue(() => currentTime),
        tdfServiceProvider.overrideWithValue(
          _CountingTdfService(() => parseCount++),
        ),
      ],
    );

    // 1. Initial load fetches 200 OK, persists ETag + Last-Modified, and skips redundant PUT since remote is already canonical.
    final initialBoard = await container1.read(taskNotifierProvider.future);
    expect(initialBoard.allTasks.single.title, equals('Initial Task'));
    expect(get200Count, equals(1));
    expect(get304Count, equals(0));
    expect(
      putCount,
      equals(0),
      reason: 'Unchanged canonical remote TDF must not trigger a redundant PUT',
    );
    final activeWorkspace = await container1.read(
      activeWorkspaceProvider.future,
    );
    final savedState = await settingsRepository.loadWorkspaceSyncState(
      activeWorkspace.id,
    );
    expect(savedState.remoteEtag, equals('"etag-v1"'));
    expect(
      savedState.remoteLastModified,
      equals('Mon, 09 Nov 2026 22:00:00 GMT'),
    );

    // 2. Manual syncFromRemote receives 304 Not Modified and runs 0 TDF parser passes and 0 PUT uploads.
    parseCount = 0;
    await container1.read(taskNotifierProvider.notifier).syncFromRemote();
    expect(get200Count, equals(1));
    expect(get304Count, equals(1));
    expect(
      parseCount,
      equals(0),
      reason: '304 Not Modified with existing in-memory board must skip all TDF parser passes',
    );
    expect(putCount, equals(0));

    // 3. Simulate app restart (new ProviderContainer seeded from SettingsRepository):
    //    cold start in StorageMode.webdav receives 304 Not Modified and parses cached TDF only once (skipping baseline parse & merge).
    container1.dispose();
    parseCount = 0;
    final container2 = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settingsRepository),
        clockProvider.overrideWithValue(() => currentTime),
        tdfServiceProvider.overrideWithValue(
          _CountingTdfService(() => parseCount++),
        ),
      ],
    );
    addTearDown(container2.dispose);

    final restartedBoard = await container2.read(taskNotifierProvider.future);
    expect(restartedBoard.allTasks.single.title, equals('Initial Task'));
    expect(get200Count, equals(1));
    expect(get304Count, equals(2));
    expect(
      parseCount,
      equals(1),
      reason: 'Cold start with 304 Not Modified must parse cached TDF once and skip baseline re-parse',
    );
    expect(putCount, equals(0));

    // 4. Local mutation with concurrent remote edit between GET (304) and PUT (412 Precondition Failed)
    //    retries by fetching the updated remote TDF (200 OK), merging both tasks, and succeeding on retry PUT.
    injectConcurrentRemoteEditOnNextPut = true;
    currentTime = DateTime.utc(2026, 11, 1, 10);
    await container2
        .read(taskNotifierProvider.notifier)
        .addTask('Local Mutated Task', targetTier: TaskTier.someday);

    final mergedAfter412 = container2.read(taskNotifierProvider).requireValue;
    expect(
      mergedAfter412.allTasks.map((task) => task.title),
      containsAll(<String>[
        'Initial Task',
        'Concurrent Server Task',
        'Local Mutated Task',
      ]),
      reason: '412 Precondition Failed on PUT must re-fetch, 3-way merge, and retry saveTdf',
    );
    expect(container2.read(syncStateProvider).errorMessage, isNull);
    expect(get200Count, equals(2));
    expect(putCount, equals(2));
  });

  test('TaskSyncPipeline.runSyncWithStatus sets SyncState.hasOpenConflict when TdfSyncOutcomeException is thrown', () async {
    final settingsRepository = InMemorySettingsRepository(
      const WebDavConfig(storageMode: StorageMode.local),
    );
    const baselineTdf =
        'tdf 0.6.0\n\n'
        'queue {\n'
        '    modified 2026-11-01 10:00:00\n'
        '    task cflTask001\n'
        '}\n\n'
        'task cflTask001 {\n'
        '    name "Baseline Title"\n'
        '    created 2026-11-01 10:00:00\n'
        '    modified 2026-11-01 10:00:00\n'
        '}\n';
    const externalDeletedTdf =
        'tdf 0.6.0\n\n'
        'deleted {\n'
        '    generation 0\n'
        '    task cflTask001 2026-11-01 10:05:00\n'
        '}\n\n'
        'queue {\n'
        '    modified 2026-11-01 10:05:00\n'
        '}\n';
    var currentDisk = baselineTdf;

    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settingsRepository),
        clockProvider.overrideWithValue(
          () => DateTime.utc(2026, 11, 1, 10, 10),
        ),
        localFileRepositoryProvider.overrideWith(
          (ref) => _InMemorySyncLocalRepository(
            config:
                ref.watch(webDavConfigProvider).asData?.value ??
                const WebDavConfig(),
            getTdf: () => currentDisk,
            setTdf: (value) => currentDisk = value,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final initialBoard = await container.read(taskNotifierProvider.future);
    final editedBoard = initialBoard.updateTask(
      'cflTask001',
      title: 'Concurrent Local Edit',
      currentDate: DateTime.utc(2026, 11, 1, 10, 6),
      localEvaluationTime: DateTime(2026, 11, 1, 10, 6),
    );
    currentDisk = externalDeletedTdf;

    final runConflictSync = container.read(
      Provider<Future<TaskBoard> Function()>(
        (ref) =>
            () => TaskSyncPipeline.runSyncWithStatus(
              ref,
              const WebDavConfig(storageMode: StorageMode.local),
              pendingDeletedLabelTimestamps: <String, DateTime>{},
              candidateBoard: editedBoard,
            ),
      ),
    );
    await expectLater(runConflictSync, throwsA(isA<TdfSyncOutcomeException>()));

    final syncState = container.read(syncStateProvider);
    expect(
      syncState.hasOpenConflict,
      isTrue,
      reason:
          'TdfSyncOutcomeException must mark SyncState.hasOpenConflict == true',
    );
    expect(syncState.errorMessage, contains('deletionConflict'));
  });

  test('TaskSyncPipeline.synchronize scopes baseline across external task/label/location deletions, generation bumps, and same-timestamp external edits without false deletionConflict or overwrite', () async {
    const gen0Initial =
        'tdf 0.6.0\n\n'
        'deleted {\n'
        '    generation 0\n'
        '}\n\n'
        'queue {\n'
        '    modified 2026-11-14 10:00:00\n'
        '    task sameTs0001\n'
        '    task keepTsk001\n'
        '}\n\n'
        'location locDel0001 {\n'
        '    name "Office"\n'
        '    coordinates 52.5200 13.4050\n'
        '    source "gps"\n'
        '    radius 150\n'
        '    modified 2026-11-14 10:00:00\n'
        '}\n\n'
        'label lblDel0001 {\n'
        '    name "Deprecated"\n'
        '    color "#AA3344"\n'
        '    modified 2026-11-14 10:00:00\n'
        '}\n\n'
        'task delTask001 {\n'
        '    name "Deleted Externally"\n'
        '    created 2026-11-14 10:00:00\n'
        '    modified 2026-11-14 10:00:00\n'
        '}\n\n'
        'task sameTs0001 {\n'
        '    name "Alpha Original"\n'
        '    created 2026-11-14 10:00:00\n'
        '    modified 2026-11-14 10:00:00\n'
        '}\n\n'
        'task keepTsk001 {\n'
        '    name "Keep Existing"\n'
        '    created 2026-11-14 10:00:00\n'
        '    modified 2026-11-14 10:00:00\n'
        '}\n';

    var currentDisk = gen0Initial;
    var clockTime = DateTime.utc(2026, 11, 14, 10, 0);
    final settingsRepository = InMemorySettingsRepository(
      const WebDavConfig(storageMode: StorageMode.local),
    );
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settingsRepository),
        clockProvider.overrideWithValue(() => clockTime),
        localFileRepositoryProvider.overrideWith(
          (ref) => _InMemorySyncLocalRepository(
            config:
                ref.watch(webDavConfigProvider).asData?.value ??
                const WebDavConfig(),
            getTdf: () => currentDisk,
            setTdf: (value) => currentDisk = value,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final originBoard = await container.read(taskNotifierProvider.future);
    expect(originBoard.deletedBlock.generation, equals(0));

    // User queues an optimistic Someday addTask on top of originBoard BEFORE external reconcile finishes (without modifying queueBlock).
    clockTime = DateTime.utc(2026, 11, 14, 10, 2);
    final candidateBoard = originBoard.addTask(
      'Queued User Task',
      id: 'usrQueue01',
      targetTier: TaskTier.someday,
      currentDate: clockTime,
      localEvaluationTime: clockTime,
    );

    // Case A: Same generation (0 -> 0) external deletions + same-timestamp external task & queue edits!
    const externalSameGenTdf =
        'tdf 0.6.0\n\n'
        'deleted {\n'
        '    generation 0\n'
        '    task delTask001 2026-11-14 10:01:00\n'
        '    label lblDel0001 2026-11-14 10:01:00\n'
        '    location locDel0001 2026-11-14 10:01:00\n'
        '}\n\n'
        'queue {\n'
        '    modified 2026-11-14 10:00:00\n'
        '    task keepTsk001\n'
        '}\n\n'
        'task sameTs0001 {\n'
        '    name "Zulu Same Timestamp"\n'
        '    created 2026-11-14 10:00:00\n'
        '    modified 2026-11-14 10:00:00\n'
        '}\n\n'
        'task keepTsk001 {\n'
        '    name "Keep Existing"\n'
        '    created 2026-11-14 10:00:00\n'
        '    modified 2026-11-14 10:00:00\n'
        '}\n';
    currentDisk = externalSameGenTdf;

    final runExternalReconcile = container.read(
      Provider<Future<TaskBoard> Function()>(
        (ref) =>
            () => TaskSyncPipeline.synchronize(
              ref,
              const WebDavConfig(storageMode: StorageMode.local),
              pendingDeletedLabelTimestamps: <String, DateTime>{},
              candidateBoard: originBoard,
            ),
      ),
    );
    final afterExternal = await runExternalReconcile();
    expect(afterExternal.findTask('delTask001'), isNull);
    expect(
      afterExternal.findTask('sameTs0001')?.title,
      equals('Zulu Same Timestamp'),
    );
    expect(afterExternal.queueBlock.taskIds.contains('sameTs0001'), isFalse);

    // Queued user mutation runs against same-generation external deletion + same-timestamp edit:
    final runQueuedMutation = container.read(
      Provider<Future<TaskBoard> Function()>(
        (ref) =>
            () => TaskSyncPipeline.synchronize(
              ref,
              const WebDavConfig(storageMode: StorageMode.local),
              pendingDeletedLabelTimestamps: <String, DateTime>{},
              candidateBoard: candidateBoard,
              candidateOriginBoard: originBoard,
            ),
      ),
    );
    final convergedSameGen = await runQueuedMutation();
    expect(
      convergedSameGen.findTask('usrQueue01')?.title,
      equals('Queued User Task'),
    );
    expect(
      convergedSameGen.findTask('delTask001'),
      isNull,
      reason: 'Externally deleted task untouched by user must remain deleted without false deletionConflict',
    );
    expect(
      convergedSameGen.labels.where((label) => label.id == 'lblDel0001'),
      isEmpty,
      reason: 'Externally deleted label untouched by user must remain deleted',
    );
    expect(
      convergedSameGen.locations.where((loc) => loc.id == 'locDel0001'),
      isEmpty,
      reason:
          'Externally deleted location untouched by user must remain deleted',
    );
    expect(
      convergedSameGen.findTask('sameTs0001')?.title,
      equals('Zulu Same Timestamp'),
      reason: 'Same-timestamp external title edit must not be overwritten by stale candidateBoard copy',
    );
    expect(
      convergedSameGen.queueBlock.taskIds.contains('sameTs0001'),
      isFalse,
      reason: 'Same-timestamp external queue removal must not be undone by stale candidateBoard queue',
    );

    // Case B: External reconcile bumps deleted.generation (0 -> 1) and retires sameTs0001 without a tombstone while mutations are queued from generation 0:
    const externalBumpedGenTdf =
        'tdf 0.6.0\n\n'
        'deleted {\n'
        '    generation 1\n'
        '    task delTask001 2026-11-14 10:01:00\n'
        '}\n\n'
        'queue {\n'
        '    modified 2026-11-14 10:00:00\n'
        '    task keepTsk001\n'
        '}\n\n'
        'task keepTsk001 {\n'
        '    name "Keep Existing"\n'
        '    created 2026-11-14 10:00:00\n'
        '    modified 2026-11-14 10:00:00\n'
        '}\n\n'
        'task usrQueue01 {\n'
        '    name "Queued User Task"\n'
        '    created 2026-11-14 10:02:00\n'
        '    modified 2026-11-14 10:02:00\n'
        '}\n';
    currentDisk = externalBumpedGenTdf;
    final afterGenBump = await container.read(
      Provider<Future<TaskBoard> Function()>(
        (ref) =>
            () => TaskSyncPipeline.synchronize(
              ref,
              const WebDavConfig(storageMode: StorageMode.local),
              pendingDeletedLabelTimestamps: <String, DateTime>{},
              candidateBoard: convergedSameGen,
            ),
      ),
    )();
    expect(afterGenBump.deletedBlock.generation, equals(1));
    expect(afterGenBump.findTask('sameTs0001'), isNull);
    expect(afterGenBump.deletedBlock.findTaskRecord('sameTs0001'), isNull);

    clockTime = DateTime.utc(2026, 11, 14, 10, 4);
    final candidateEditedRetired = convergedSameGen.updateTask(
      'sameTs0001',
      title: 'Edited Retired Task',
      currentDate: clockTime,
      localEvaluationTime: clockTime,
    );
    await expectLater(
      () => container.read(
        Provider<Future<TaskBoard> Function()>(
          (ref) =>
              () => TaskSyncPipeline.synchronize(
                ref,
                const WebDavConfig(storageMode: StorageMode.local),
                pendingDeletedLabelTimestamps: <String, DateTime>{},
                candidateBoard: candidateEditedRetired,
                candidateOriginBoard: convergedSameGen,
              ),
        ),
      )(),
      throwsA(
        isA<TdfSyncOutcomeException>().having(
          (error) => error.kind,
          'kind',
          TdfSyncOutcomeKind.recoveryRequired,
        ),
      ),
    );

    final candidateGen0 = convergedSameGen.addTask(
      'Queued Across Gen Bump',
      id: 'usrGenBmp1',
      targetTier: TaskTier.someday,
      currentDate: clockTime,
      localEvaluationTime: clockTime,
    );
    final convergedGenBump = await container.read(
      Provider<Future<TaskBoard> Function()>(
        (ref) =>
            () => TaskSyncPipeline.synchronize(
              ref,
              const WebDavConfig(storageMode: StorageMode.local),
              pendingDeletedLabelTimestamps: <String, DateTime>{},
              candidateBoard: candidateGen0,
              candidateOriginBoard: convergedSameGen,
            ),
      ),
    )();
    expect(convergedGenBump.deletedBlock.generation, equals(1));
    expect(convergedGenBump.findTask('sameTs0001'), isNull);
    expect(convergedGenBump.deletedBlock.findTaskRecord('sameTs0001'), isNull);
    expect(
      convergedGenBump.findTask('usrGenBmp1')?.title,
      equals('Queued Across Gen Bump'),
      reason: 'Queued mutation originating at generation 0 must converge cleanly after external generation 0 -> 1 bump without syncGenerationRollback or recoveryRequired',
    );
  });

  test('Refreshing at 2026-11-11 12:00:01 cleans expired suspended across local disk and loopback WebDAV (200 OK and 304 Not Modified) and performs zero writes on second refresh at 12:00:05', () async {
    HttpOverrides.global = null;
    const tdfService = TdfService();
    final initialSeedBoard = tdfService.parse(
      'tdf 0.7.0\n\n'
      'queue {\n'
      '    modified 2026-11-11 10:00:00\n'
      '    task suspCln001\n'
      '}\n\n'
      'task suspCln001 {\n'
      '    name      "Deferred Cleanup Task"\n'
      '    created   2026-11-11 10:00:00\n'
      '    modified  2026-11-11 10:00:00\n'
      '    suspended 2026-11-11 12:00:00 "Wait"\n'
      '}\n',
      evaluationTime: DateTime.utc(2026, 11, 11, 11, 59),
      localEvaluationTime: DateTime.utc(2026, 11, 11, 11, 59),
    );
    final canonicalDeferredTdf = tdfService.serialize(initialSeedBoard);

    // 1. StorageMode.local: refresh at 12:00:01 cleans & writes once; refresh at 12:00:05 skips write.
    final localDir = await Directory.systemTemp.createTemp(
      'tiertask_sync_susp_local_',
    );
    addTearDown(() => localDir.delete(recursive: true));
    final localFile = File('${localDir.path}/tasks.tdf');
    await localFile.writeAsString(canonicalDeferredTdf, flush: true);

    var localClock = DateTime.utc(2026, 11, 11, 11, 59);
    var localSaveCalls = 0;
    const localOnlyConfig = WebDavConfig(
      storageMode: StorageMode.local,
      localFilePath: 'tasks.tdf',
    );
    final localSettings = InMemorySettingsRepository(localOnlyConfig);
    final localContainer = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(localSettings),
        clockProvider.overrideWithValue(() => localClock),
        localFileRepositoryProvider.overrideWith(
          (ref) => _CountingSaveLocalRepository(
            config: localOnlyConfig,
            baseDirectoryPath: localDir.path,
            onSave: () => localSaveCalls++,
          ),
        ),
      ],
    );
    addTearDown(localContainer.dispose);

    final loadedBeforeExpiry = await localContainer.read(
      taskNotifierProvider.future,
    );
    expect(
      loadedBeforeExpiry.findTask('suspCln001')?.suspendedNote,
      equals('Wait'),
      reason:
          'Before 12:00:00 expiry, suspended and suspendedNote remain intact',
    );
    expect(
      localSaveCalls,
      equals(0),
      reason: 'Canonical file before expiry must not rewrite disk on load',
    );

    localClock = DateTime.utc(2026, 11, 11, 12, 0, 1);
    await localContainer.read(taskNotifierProvider.notifier).syncFromRemote();
    final cleanedLocalBoard = localContainer
        .read(taskNotifierProvider)
        .requireValue;
    final cleanedLocalTask = cleanedLocalBoard.findTask('suspCln001');
    expect(cleanedLocalTask?.suspendedAt, isNull);
    expect(cleanedLocalTask?.suspendedNote, isNull);
    expect(
      cleanedLocalTask?.modifiedAt,
      equals(DateTime.utc(2026, 11, 11, 12, 0, 1)),
    );
    expect(
      localSaveCalls,
      equals(1),
      reason:
          'Refresh at 12:00:01 must persist cleaned TDF 0.7.0 to local disk',
    );
    expect(await localFile.readAsString(), isNot(contains('suspended')));

    localClock = DateTime.utc(2026, 11, 11, 12, 0, 5);
    await localContainer.read(taskNotifierProvider.notifier).syncFromRemote();
    expect(
      localSaveCalls,
      equals(1),
      reason: 'Second refresh at 12:00:05 must perform zero local disk writes',
    );

    // 2. StorageMode.webdav via loopback HttpServer: 200 OK cleanup + 304 Not Modified cleanup + zero writes at 12:00:05.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    var remoteTdf = canonicalDeferredTdf;
    var remoteEtag = '"etag-initial"';
    var get200Count = 0;
    var get304Count = 0;
    var putCount = 0;

    server.listen((HttpRequest request) async {
      if (request.method == 'GET') {
        final ifNoneMatch = request.headers.value(
          HttpHeaders.ifNoneMatchHeader,
        );
        if (ifNoneMatch == remoteEtag) {
          get304Count++;
          request.response.statusCode = HttpStatus.notModified;
          request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
          await request.response.close();
          return;
        }
        get200Count++;
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
        request.response.write(remoteTdf);
        await request.response.close();
        return;
      }
      if (request.method == 'PUT') {
        putCount++;
        remoteTdf = await utf8.decoder.bind(request).join();
        remoteEtag = '"etag-put-$putCount"';
        request.response.statusCode = HttpStatus.noContent;
        request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
        await request.response.close();
      }
    });

    final webdavConfig = WebDavConfig(
      storageMode: StorageMode.webdav,
      serverUrl: 'http://127.0.0.1:${server.port}',
      username: 'alice',
      password: 'secret',
      filePath: 'tasks.tdf',
    );

    // 2a. Initial 200 OK at 12:00:01 cleans and PUTs; second refresh at 12:00:05 (304) performs zero PUTs.
    var webdavClock = DateTime.utc(2026, 11, 11, 12, 0, 1);
    final webdavSettings200 = InMemorySettingsRepository(webdavConfig);
    final webdavContainer200 = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(webdavSettings200),
        clockProvider.overrideWithValue(() => webdavClock),
      ],
    );
    addTearDown(webdavContainer200.dispose);

    final cleaned200Board = await webdavContainer200.read(
      taskNotifierProvider.future,
    );
    expect(cleaned200Board.findTask('suspCln001')?.suspendedAt, isNull);
    expect(get200Count, equals(1));
    expect(
      putCount,
      equals(1),
      reason: '200 OK refresh at 12:00:01 must PUT cleaned TDF 0.7.0 to WebDAV',
    );
    expect(remoteTdf, isNot(contains('suspended')));

    webdavClock = DateTime.utc(2026, 11, 11, 12, 0, 5);
    await webdavContainer200
        .read(taskNotifierProvider.notifier)
        .syncFromRemote();
    expect(get304Count, equals(1));
    expect(
      putCount,
      equals(1),
      reason: 'Second WebDAV refresh at 12:00:05 must perform zero PUTs',
    );

    // 2b. StorageMode.both: sync at 11:59:00 (no PUT), then 304 Not Modified at 12:00:01 cleans & writes both, then 12:00:05 performs zero writes.
    remoteTdf = canonicalDeferredTdf;
    remoteEtag = '"etag-both-v1"';
    get200Count = 0;
    get304Count = 0;
    putCount = 0;

    final bothDir = await Directory.systemTemp.createTemp(
      'tiertask_sync_susp_both_',
    );
    addTearDown(() => bothDir.delete(recursive: true));
    await File('${bothDir.path}/tasks.tdf')
        .writeAsString(canonicalDeferredTdf, flush: true);
    var bothLocalSaves = 0;
    var bothClock = DateTime.utc(2026, 11, 11, 11, 59);
    final bothLoopbackConfig = WebDavConfig(
      storageMode: StorageMode.both,
      localFilePath: 'tasks.tdf',
      serverUrl: 'http://127.0.0.1:${server.port}',
      username: 'alice',
      password: 'secret',
      filePath: 'tasks.tdf',
    );
    final bothSettings = InMemorySettingsRepository(bothLoopbackConfig);
    final bothContainer = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(bothSettings),
        clockProvider.overrideWithValue(() => bothClock),
        localFileRepositoryProvider.overrideWith(
          (ref) => _CountingSaveLocalRepository(
            config: bothLoopbackConfig,
            baseDirectoryPath: bothDir.path,
            onSave: () => bothLocalSaves++,
          ),
        ),
      ],
    );
    addTearDown(bothContainer.dispose);

    await bothContainer.read(taskNotifierProvider.future);
    expect(putCount, equals(0));
    expect(bothLocalSaves, equals(0));

    bothClock = DateTime.utc(2026, 11, 11, 12, 0, 1);
    await bothContainer.read(taskNotifierProvider.notifier).syncFromRemote();
    expect(
      get304Count,
      equals(1),
      reason:
          'Refresh at 12:00:01 receives 304 Not Modified from loopback WebDAV',
    );
    expect(
      putCount,
      equals(1),
      reason: '304 Not Modified with newly expired suspended must PUT cleaned TDF 0.7.0',
    );
    expect(
      bothLocalSaves,
      equals(1),
      reason: 'Stage 2 cleanup must converge cleaned TDF 0.7.0 to local disk',
    );
    expect(remoteTdf, isNot(contains('suspended')));
    expect(
      await File('${bothDir.path}/tasks.tdf').readAsString(),
      equals(remoteTdf),
    );

    final bothWorkspace = await bothContainer.read(
      activeWorkspaceProvider.future,
    );
    final syncedState = await bothSettings.loadWorkspaceSyncState(
      bothWorkspace.id,
    );
    expect(syncedState.remoteEtag, equals('"etag-put-1"'));
    expect(syncedState.lastSyncedRemoteTdf, equals(remoteTdf));
    expect(syncedState.lastSyncedLocalTdf, equals(remoteTdf));
    expect(syncedState.localSourceDigest, isNotNull);

    bothClock = DateTime.utc(2026, 11, 11, 12, 0, 5);
    await bothContainer.read(taskNotifierProvider.notifier).syncFromRemote();
    expect(
      putCount,
      equals(1),
      reason: 'Subsequent refresh at 12:00:05 must perform zero WebDAV PUTs',
    );
    expect(
      bothLocalSaves,
      equals(1),
      reason:
          'Subsequent refresh at 12:00:05 must perform zero local disk writes',
    );
  });

  test('Opening and syncing an existing 0.6.0 workspace with open repeat + due + finite suspended < due preserves leadDays and non-midnight repeat-time in tdf 0.7.0', () async {
    const legacy060Tdf =
        'tdf 0.6.0\n\n'
        'queue {\n'
        '    modified 2026-11-11 10:00:00\n'
        '    task repMig0001\n'
        '}\n\n'
        'task repMig0001 {\n'
        '    name      "Monthly Rent"\n'
        '    created   2026-11-01 08:00:00\n'
        '    modified  2026-11-11 10:00:00\n'
        '    suspended 2026-11-11 12:00:00\n'
        '    due       2026-11-20 14:30:00\n'
        '    repeat    1 months\n'
        '}\n';

    var localTdf = legacy060Tdf;
    var remoteTdf = legacy060Tdf;
    // Sync at 12:00:01 UTC in manual +02:00 timezone:
    // suspended local = 2026-11-11 14:00:00, due local = 2026-11-20 16:30:00 -> lead 9 days, repeat-time 16:30!
    // Wait: in 0.6.0 -> 0.7.0 extraction, <repeat-time> comes from due's local wall-clock (16:30) or suspended? Let's verify both leadDays and non-midnight clock!
    final syncTime = DateTime.utc(2026, 11, 11, 12, 0, 1);
    const manualTzConfig = WebDavConfig(
      storageMode: StorageMode.both,
      localFilePath: 'tasks.tdf',
      serverUrl: 'https://cloud.example.com/dav/',
      username: 'alice',
      password: 'secret',
      filePath: 'tasks.tdf',
      timeZoneMode: AppTimeZoneMode.manual,
      manualTimeZoneOffsetMinutes: 120,
    );
    final container = createSyncContainer(
      config: manualTzConfig,
      settingsRepository: InMemorySettingsRepository(manualTzConfig),
      clock: () => syncTime,
      getLocal: () => localTdf,
      setLocal: (value) => localTdf = value,
      getRemote: () => remoteTdf,
      setRemote: (value) => remoteTdf = value,
      isOnline: () => true,
    );
    addTearDown(container.dispose);

    final board = await container.read(taskNotifierProvider.future);
    final migratedTask = board.findTask('repMig0001');
    expect(migratedTask, isNotNull);
    expect(
      migratedTask?.repeatRule?.leadDays,
      equals(9),
      reason: '0.6.0 -> 0.7.0 upgrade must extract 9-day local lead window using workspace TdfTimeZoneContext without throwing ImportContextRequired',
    );
    expect(
      migratedTask?.repeatRule?.clock.isMidnight,
      isFalse,
      reason: '0.6.0 -> 0.7.0 upgrade must preserve non-midnight local repeat clock',
    );
    expect(
      migratedTask?.suspendedAt,
      isNull,
      reason: 'Expired 12:00:00 suspended deferral is simultaneously cleaned at 12:00:01 after extracting leadDays',
    );
    expect(localTdf, startsWith('tdf 0.7.0\n'));
    expect(localTdf, contains('lead 9 days'));
    expect(remoteTdf, equals(localTdf));

    // Also verify AppTimeZoneMode.system succeeds deterministically without ImportContextRequired.
    var autoLocalTdf = legacy060Tdf;
    const systemTzConfig = WebDavConfig(
      storageMode: StorageMode.local,
      localFilePath: 'tasks.tdf',
      timeZoneMode: AppTimeZoneMode.automatic,
    );
    final autoContainer = createSyncContainer(
      config: systemTzConfig,
      settingsRepository: InMemorySettingsRepository(systemTzConfig),
      clock: () => syncTime,
      getLocal: () => autoLocalTdf,
      setLocal: (value) => autoLocalTdf = value,
      getRemote: () => '',
      setRemote: (_) {},
      isOnline: () => false,
    );
    addTearDown(autoContainer.dispose);
    final autoBoard = await autoContainer.read(taskNotifierProvider.future);
    expect(
      autoBoard.findTask('repMig0001')?.repeatRule?.leadDays,
      greaterThan(0),
    );
    expect(autoLocalTdf, startsWith('tdf 0.7.0\n'));
  });

  test('StorageMode.both stage-fair sync defers Stage 1 block cleanup so expired local suspended never inflates modified ahead of remote 11:30:00 note edit at 12:05:00', () async {
    // Subcase 1: Cold/2-way and 3-way sync at 12:05:00 where local task has older note (10:00:00) + expired suspended (12:00:00)
    // and remote edited task note at 11:30:00.
    var localTdf =
        'tdf 0.7.0\n\n'
        'queue {\n'
        '    modified 2026-11-11 10:00:00\n'
        '    task fair000001\n'
        '    task other00002\n'
        '}\n\n'
        'task fair000001 {\n'
        '    name      "Stage Fair Task"\n'
        '    note      "Stale Local Note"\n'
        '    created   2026-11-11 09:00:00\n'
        '    modified  2026-11-11 10:00:00\n'
        '    suspended 2026-11-11 12:00:00 "Wait"\n'
        '}\n\n'
        'task other00002 {\n'
        '    name     "Other Task"\n'
        '    created  2026-11-11 09:00:00\n'
        '    modified 2026-11-11 10:00:00\n'
        '}\n';
    var remoteTdf =
        'tdf 0.7.0\n\n'
        'queue {\n'
        '    modified 2026-11-11 10:00:00\n'
        '    task fair000001\n'
        '    task other00002\n'
        '}\n\n'
        'task fair000001 {\n'
        '    name      "Stage Fair Task"\n'
        '    note      "Remote Newer Note At 11:30"\n'
        '    created   2026-11-11 09:00:00\n'
        '    modified  2026-11-11 11:30:00\n'
        '    suspended 2026-11-11 12:00:00 "Wait"\n'
        '}\n\n'
        'task other00002 {\n'
        '    name     "Other Task"\n'
        '    created  2026-11-11 09:00:00\n'
        '    modified 2026-11-11 10:00:00\n'
        '}\n';

    var currentTime = DateTime.utc(2026, 11, 11, 12, 5);
    final settingsRepository = InMemorySettingsRepository(bothConfig);
    final container = createSyncContainer(
      config: bothConfig,
      settingsRepository: settingsRepository,
      clock: () => currentTime,
      getLocal: () => localTdf,
      setLocal: (value) => localTdf = value,
      getRemote: () => remoteTdf,
      setRemote: (value) => remoteTdf = value,
      isOnline: () => true,
    );
    addTearDown(container.dispose);

    final mergedBoard = await container.read(taskNotifierProvider.future);
    final mergedFair = mergedBoard.findTask('fair000001');
    expect(
      mergedFair?.note,
      equals('Remote Newer Note At 11:30'),
      reason: 'Stage 1 must defer block cleanup so local modified (10:00:00) is not inflated to 12:05:00 ahead of remote 11:30:00 note edit',
    );
    expect(
      mergedFair?.suspendedAt,
      isNull,
      reason: 'Stage 2 must strip the expired 12:00:00 suspended deferral after selecting remote winner',
    );
    expect(localTdf, equals(remoteTdf));
    expect(localTdf, contains('Remote Newer Note At 11:30'));
    expect(localTdf, isNot(contains('suspended')));

    // Subcase 2: Optimistic mutation to other00002 at 12:25:00 while bystander fair000001 has a newly expired suspended (12:20:00)
    // and remote edited fair000001's note at 12:15:00.
    currentTime = DateTime.utc(2026, 11, 11, 12, 10);
    await container
        .read(taskNotifierProvider.notifier)
        .updateTask(
          'fair000001',
          title: 'Stage Fair Task',
          note: 'Baseline Note 12:10',
          suspendedAt: DateTime.utc(2026, 11, 11, 12, 20),
        );

    // Remote edits fair000001's note at 12:15:00 (still carrying suspended 12:20:00).
    remoteTdf = remoteTdf
        .replaceFirst('Baseline Note 12:10', 'Remote Bystander Edit 12:15')
        .replaceFirst(
          'modified  2026-11-11 12:10',
          'modified  2026-11-11 12:15',
        );

    // At 12:25:00, user mutates other00002 locally (which runs TaskBoardMutator block cleanup on bystander fair000001 in candidateBoard!).
    currentTime = DateTime.utc(2026, 11, 11, 12, 25);
    await container
        .read(taskNotifierProvider.notifier)
        .updateTask('other00002', title: 'Updated Other At 12:25');

    final afterBystanderSync = container
        .read(taskNotifierProvider)
        .requireValue;
    expect(
      afterBystanderSync.findTask('other00002')?.title,
      equals('Updated Other At 12:25'),
    );
    expect(
      afterBystanderSync.findTask('fair000001')?.note,
      equals('Remote Bystander Edit 12:15'),
      reason: 'Optimistic mutation to other00002 must not inflate untouched bystander fair000001 modifiedAt ahead of remote 12:15 edit',
    );
    expect(afterBystanderSync.findTask('fair000001')?.suspendedAt, isNull);
  });

  test('Concurrent local repeat completion and remote history set edits merge without data loss', () async {
    var currentTime = DateTime.utc(2026, 11, 11, 8, 0);
    var isOnline = true;
    var localTdf =
        'tdf 0.7.0\n\n'
        'queue {\n'
        '    modified 2026-11-11 08:00:00\n'
        '    task repHist001\n'
        '}\n\n'
        'task repHist001 {\n'
        '    name     "Daily Standup"\n'
        '    created  2026-11-11 08:00:00\n'
        '    modified 2026-11-11 08:00:00\n'
        '    due      2026-11-11 09:00:00\n'
        '    repeat   1 days 09:00\n'
        '    history  2026-11-11 08:00:00 "Initial log"\n'
        '}\n';
    var remoteTdf = localTdf;
    final settingsRepository = InMemorySettingsRepository(bothConfig);

    final container1 = createSyncContainer(
      config: bothConfig,
      settingsRepository: settingsRepository,
      clock: () => currentTime,
      getLocal: () => localTdf,
      setLocal: (value) => localTdf = value,
      getRemote: () => remoteTdf,
      setRemote: (value) => remoteTdf = value,
      isOnline: () => isOnline,
    );
    await container1.read(taskNotifierProvider.future);

    // Go offline and complete the recurring task locally at 10:00:00.
    isOnline = false;
    currentTime = DateTime.utc(2026, 11, 11, 10, 0);
    await container1
        .read(taskNotifierProvider.notifier)
        .completeTask('repHist001');
    container1.dispose();

    // Meanwhile on remote, a collaborator adds two history entries at 09:30:00.
    remoteTdf =
        'tdf 0.7.0\n\n'
        'queue {\n'
        '    modified 2026-11-11 08:00:00\n'
        '    task repHist001\n'
        '}\n\n'
        'task repHist001 {\n'
        '    name     "Daily Standup"\n'
        '    created  2026-11-11 08:00:00\n'
        '    modified 2026-11-11 09:30:00\n'
        '    due      2026-11-11 09:00:00\n'
        '    repeat   1 days 09:00\n'
        '    history  2026-11-11 08:00:00 "Initial log"\n'
        '    history  2026-11-11 09:15:00 "Remote note A"\n'
        '    history  2026-11-11 09:30:00 "Remote note B"\n'
        '}\n';

    // Reconnect at 10:05:00 and sync.
    isOnline = true;
    currentTime = DateTime.utc(2026, 11, 11, 10, 5);
    final container2 = createSyncContainer(
      config: bothConfig,
      settingsRepository: settingsRepository,
      clock: () => currentTime,
      getLocal: () => localTdf,
      setLocal: (value) => localTdf = value,
      getRemote: () => remoteTdf,
      setRemote: (value) => remoteTdf = value,
      isOnline: () => isOnline,
    );
    addTearDown(container2.dispose);

    final converged = await container2.read(taskNotifierProvider.future);
    final mergedTask = converged.findTask('repHist001');
    expect(mergedTask?.completions, equals(1));
    expect(mergedTask?.isCompleted, isFalse);
    expect(
      mergedTask?.history.map((entry) => entry.text).toList(),
      equals(<String>['Initial log', 'Remote note A', 'Remote note B']),
      reason: 'Concurrent local repeat completion and remote history additions must merge without data loss',
    );
    expect(localTdf, equals(remoteTdf));
  });

  test('Queued optimistic mutations across deleted.generation advancement ignore automatic block cleanup on retired entities, strip retired blocked references on surviving candidate tasks, and flag real edits on retired tasks as recoveryRequired', () async {
    const tdfService = TdfService();
    final t10 = DateTime.utc(2026, 11, 11, 10, 0);
    final t12 = DateTime.utc(2026, 11, 11, 12, 0);

    // Build generation 0 origin board at 10:00 where:
    // - retBlkr001 is ALREADY completed at 09:00 (so retTask002's blocked reference is resolved if cleanup runs),
    // - retTask002 has suspended 11:00 (so at 12:00 its suspended is expired!), references retLbl0001 and retLoc0001,
    // - survDep003 is blocked on retTask002.
    const gen0Raw =
        'tdf 0.7.0\n\n'
        'queue {\n'
        '    modified 2026-11-11 10:00:00\n'
        '    task retTask002\n'
        '    task survDep003\n'
        '}\n\n'
        'label retLbl0001 {\n'
        '    name     "Retired Label"\n'
        '    modified 2026-11-11 10:00:00\n'
        '}\n\n'
        'location retLoc0001 {\n'
        '    name        "Retired Office"\n'
        '    coordinates 48.137154 11.576124\n'
        '    radius      150\n'
        '    modified    2026-11-11 10:00:00\n'
        '}\n\n'
        'task retBlkr001 {\n'
        '    name        "Completed Blocker"\n'
        '    created     2026-11-11 08:00:00\n'
        '    modified    2026-11-11 09:00:00\n'
        '    finished    2026-11-11 09:00:00\n'
        '    completions 1\n'
        '}\n\n'
        'task retTask002 {\n'
        '    name      "Retired Bystander With Expired Deferral"\n'
        '    created   2026-11-11 08:00:00\n'
        '    modified  2026-11-11 10:00:00\n'
        '    suspended 2026-11-11 11:00:00 "Hold until 11"\n'
        '    labels    retLbl0001\n'
        '    blocked   retBlkr001\n'
        '    condition location retLoc0001\n'
        '}\n\n'
        'task survDep003 {\n'
        '    name     "Surviving Dependent"\n'
        '    created  2026-11-11 08:00:00\n'
        '    modified 2026-11-11 10:00:00\n'
        '    blocked  retTask002:1\n'
        '}\n';

    var diskTdf = gen0Raw;
    var clockTime = t10;
    const localConfig = WebDavConfig(
      storageMode: StorageMode.local,
      localFilePath: 'tasks.tdf',
    );
    final settingsRepository = InMemorySettingsRepository(localConfig);
    final container = createSyncContainer(
      config: localConfig,
      settingsRepository: settingsRepository,
      clock: () => clockTime,
      getLocal: () => diskTdf,
      setLocal: (value) => diskTdf = value,
      getRemote: () => '',
      setRemote: (_) {},
      isOnline: () => false,
    );
    addTearDown(container.dispose);

    final originBoard = tdfService.parse(
      gen0Raw,
      evaluationTime: t10,
      localEvaluationTime: t10,
    );
    // Establish baseline at generation 0.
    await container.read(
      Provider<Future<TaskBoard> Function()>(
        (ref) =>
            () => TaskSyncPipeline.synchronize(
              ref,
              localConfig,
              pendingDeletedLabelTimestamps: <String, DateTime>{},
            ),
      ),
    )();

    // Step 1 (ackGen 0 -> 1): at 12:00, user edits survDep003 on originBoard while disk advanced deleted.generation 0 -> 1.
    // Note: TaskBoardMutator.updateTask runs cleanupResolvedTaskBlocks at 12:00, which automatically
    // strips retTask002's expired suspended (11:00) and resolved blocked retBlkr001, bumping retTask002.modifiedAt to 12:00!
    clockTime = t12;
    final candidateWithBystanderCleanup = originBoard.updateTask(
      'survDep003',
      title: 'Edited Before Gen Ack',
      currentDate: t12,
      localEvaluationTime: t12,
    );
    expect(
      candidateWithBystanderCleanup.findTask('retTask002')?.modifiedAt,
      equals(t12),
      reason: 'Precondition: TaskBoardMutator cleaned bystander retTask002 at 12:00',
    );

    // External disk advanced deleted.generation from 0 -> 1 and pruned tombstones for retBlkr001, retTask002, retLbl0001, retLoc0001!
    const gen1DiskRaw =
        'tdf 0.7.0\n\n'
        'deleted {\n'
        '    generation 1\n'
        '}\n\n'
        'queue {\n'
        '    modified 2026-11-11 11:30:00\n'
        '    task survDep003\n'
        '}\n\n'
        'task survDep003 {\n'
        '    name     "Surviving Dependent"\n'
        '    created  2026-11-11 08:00:00\n'
        '    modified 2026-11-11 10:00:00\n'
        '}\n';
    diskTdf = gen1DiskRaw;

    final convergedGen1 = await container.read(
      Provider<Future<TaskBoard> Function()>(
        (ref) =>
            () => TaskSyncPipeline.synchronize(
              ref,
              localConfig,
              pendingDeletedLabelTimestamps: <String, DateTime>{},
              candidateBoard: candidateWithBystanderCleanup,
              candidateOriginBoard: originBoard,
            ),
      ),
    )();
    expect(convergedGen1.deletedBlock.generation, equals(1));
    expect(
      convergedGen1.findTask('retTask002'),
      isNull,
      reason: 'Untouched retired task whose only change was automatic block cleanup must retire cleanly without false RecoveryRequired',
    );
    expect(convergedGen1.findLabel('retLbl0001'), isNull);
    expect(convergedGen1.findLocation('retLoc0001'), isNull);
    expect(
      convergedGen1.findTask('survDep003')?.title,
      equals('Edited Before Gen Ack'),
    );
    final survivingDep = convergedGen1.findTask('survDep003');
    expect(
      survivingDep?.dependencies,
      isEmpty,
      reason: 'Resolved retired dependency retTask002:1 must be stripped after generation 0 -> 1 merge',
    );

    // Step 2 (originGen == 0 < storedGen == 1 <= storedAckGen == 1): a queued optimistic mutation built on
    // originBoard (generation 0) adding userAdd004 AND editing survDep003 (which still carries blocked retTask002:1 in originBoard)
    // must rebase onto storedBaseline (generation 1), keeping userAdd004 and stripping retTask002:1 without false RecoveryRequired!
    final t1205 = DateTime.utc(2026, 11, 11, 12, 5);
    clockTime = t1205;
    final queuedOnStaleGen0 = originBoard
        .addTask(
          'Queued User Task',
          id: 'userAdd004',
          targetTier: TaskTier.someday,
          currentDate: t1205,
          localEvaluationTime: t1205,
        )
        .updateTask(
          'survDep003',
          title: 'Queued Edit On Surviving Dependent',
          currentDate: t1205,
          localEvaluationTime: t1205,
        );
    expect(
      queuedOnStaleGen0
          .findTask('survDep003')
          ?.dependencies
          .map((dep) => dep.taskId),
      contains('retTask002'),
      reason: 'Precondition: stale generation-0 candidate still holds blocked retTask002:1 before rebase',
    );
    final rebasedGen1 = await container.read(
      Provider<Future<TaskBoard> Function()>(
        (ref) =>
            () => TaskSyncPipeline.synchronize(
              ref,
              localConfig,
              pendingDeletedLabelTimestamps: <String, DateTime>{},
              candidateBoard: queuedOnStaleGen0,
              candidateOriginBoard: originBoard,
            ),
      ),
    )();
    expect(
      rebasedGen1.findTask('userAdd004')?.title,
      equals('Queued User Task'),
    );
    expect(
      rebasedGen1.findTask('survDep003')?.title,
      equals('Queued Edit On Surviving Dependent'),
    );
    expect(
      rebasedGen1.findTask('survDep003')?.dependencies,
      isEmpty,
      reason: '_rebaseCandidateToGeneration must strip blocked retTask002:1 when rebasing stale generation-0 candidate onto generation-1 baseline',
    );

    // Also verify real user edit on retTask002 in queued Path 2 (originGen == 0 < storedGen == 1 <= storedAckGen == 1) triggers RecoveryRequired:
    final t1206 = DateTime.utc(2026, 11, 11, 12, 6);
    clockTime = t1206;
    final queuedRealEditOnRetired = originBoard.addTaskHistoryEntry(
      'retTask002',
      timestampUtc: t1206,
      text: 'Queued edit on retired task',
      currentDate: t1206,
      localEvaluationTime: t1206,
    );
    await expectLater(
      () => container.read(
        Provider<Future<TaskBoard> Function()>(
          (ref) =>
              () => TaskSyncPipeline.synchronize(
                ref,
                localConfig,
                pendingDeletedLabelTimestamps: <String, DateTime>{},
                candidateBoard: queuedRealEditOnRetired,
                candidateOriginBoard: originBoard,
              ),
        ),
      )(),
      throwsA(
        isA<TdfSyncOutcomeException>().having(
          (error) => error.kind,
          'kind',
          TdfSyncOutcomeKind.recoveryRequired,
        ),
      ),
      reason: 'Queued real edit on retired task across generation rebase must trigger RecoveryRequired',
    );

    // Conversely, an actual user history edit on retTask002 across generation 0 -> 1 MUST trigger RecoveryRequired!
    diskTdf = gen0Raw;
    clockTime = t10;
    final container2 = createSyncContainer(
      config: localConfig,
      settingsRepository: InMemorySettingsRepository(localConfig),
      clock: () => clockTime,
      getLocal: () => diskTdf,
      setLocal: (value) => diskTdf = value,
      getRemote: () => '',
      setRemote: (_) {},
      isOnline: () => false,
    );
    addTearDown(container2.dispose);
    await container2.read(
      Provider<Future<TaskBoard> Function()>(
        (ref) =>
            () => TaskSyncPipeline.synchronize(
              ref,
              localConfig,
              pendingDeletedLabelTimestamps: <String, DateTime>{},
            ),
      ),
    )();

    clockTime = t12;
    final candidateWithRealEditOnRetired = originBoard.addTaskHistoryEntry(
      'retTask002',
      timestampUtc: t12,
      text: 'User edited retired task history',
      currentDate: t12,
      localEvaluationTime: t12,
    );
    diskTdf = gen1DiskRaw;

    await expectLater(
      () => container2.read(
        Provider<Future<TaskBoard> Function()>(
          (ref) =>
              () => TaskSyncPipeline.synchronize(
                ref,
                localConfig,
                pendingDeletedLabelTimestamps: <String, DateTime>{},
                candidateBoard: candidateWithRealEditOnRetired,
                candidateOriginBoard: originBoard,
              ),
        ),
      )(),
      throwsA(
        isA<TdfSyncOutcomeException>().having(
          (error) => error.kind,
          'kind',
          TdfSyncOutcomeKind.recoveryRequired,
        ),
      ),
      reason: 'Real user edit to a retired task across deleted.generation advancement must trigger RecoveryRequired',
    );
  });
}

class _CountingSaveLocalRepository extends LocalFileRepository {
  _CountingSaveLocalRepository({
    required super.config,
    super.baseDirectoryPath,
    required this.onSave,
  });

  final void Function() onSave;

  @override
  Future<void> saveTdf(String tdfContent) async {
    onSave();
    await super.saveTdf(tdfContent);
  }
}
