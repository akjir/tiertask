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
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
    bool pruneExpiredCompleted = false,
  }) {
    onParse();
    return super.parse(
      tdfContent,
      evaluationTime: evaluationTime,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      activeLabelId: activeLabelId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
      pruneExpiredCompleted: pruneExpiredCompleted,
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
    expect(localTdf, contains('tdf 0.6.0'));
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
    expect(localTdf, startsWith('tdf 0.6.0\n'));
    expect(remoteTdf, equals(localTdf));
  });

  test('Unsupported TDF version on remote, local, or both stops retrying, never overwrites unreadable files, and surfaces localized update recommendations', () async {
    const service = TdfService();
    expect(
      () => service.parse('tdf 0.7.0\n'),
      throwsA(
        isA<TdfException>()
            .having(
              (error) => error.kind,
              'kind',
              equals(TdfErrorKind.unsupportedVersion),
            )
            .having((error) => error.sourceVersion, 'sourceVersion', '0.7.0')
            .having((error) => error.targetVersion, 'targetVersion', '0.6.0'),
      ),
    );

    final currentTime = DateTime.utc(2026, 11, 1, 12);
    var remoteFetchCount = 0;
    var remoteSaveCount = 0;
    var remoteTdf = 'tdf 0.7.0\n';
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
        'Die Remote-Datei verwendet die nicht unterstützte Dateiversion 0.7.0. Bitte aktualisieren Sie TierTask auf eine neuere Version.',
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
      getLocal: () => 'tdf 0.7.0\n',
      setLocal: (_) => localFailSaveCount++,
      getRemote: () => 'tdf 0.6.0\n',
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
        'The local file uses unsupported file version 0.7.0. Please update TierTask to a newer version.',
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
      getLocal: () => 'tdf 0.7.0\n',
      setLocal: (_) {},
      getRemote: () {
        bothFailRemoteFetchCount++;
        return 'tdf 0.8.0\n';
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
        'Die lokale Datei und die Remote-Datei verwenden die nicht unterstützte Dateiversion 0.7.0 / 0.8.0. Bitte aktualisieren Sie TierTask auf eine neuere Version.',
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
        'tdf 0.6.0\n\nqueue {\n    modified 2026-11-01 08:00:00\n    task 000001OkD2\n}\n\ntask 000001OkD2 {\n    name     "Initial Task"\n    created  2026-11-01 08:00\n    modified 2026-11-01 08:00\n}\n';
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
          remoteTdf = 'tdf 0.6.0\n\nqueue {\n    modified 2026-11-01 08:00:00\n    task 000001OkD2\n}\n\ntask 000001OkD2 {\n    name     "Initial Task"\n    created  2026-11-01 08:00\n    modified 2026-11-01 08:00\n}\n\ntask 000002OkD2 {\n    name     "Concurrent Server Task"\n    created  2026-11-01 09:30\n    modified 2026-11-01 09:30\n}\n';
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
}
