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
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_board_evaluator.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_error.dart';
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
import 'package:tiertask/services/sha256_service.dart';
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
  Future<({String content, String? digest, bool exists})>
  readTdfWithDigest() async {
    final content = getTdf();
    final exists = content.isNotEmpty;
    final digest = exists ? Sha256Service.hashHex(utf8.encode(content)) : null;
    return (content: content, digest: digest, exists: exists);
  }

  @override
  Future<void> saveTdf(String tdfContent) async => setTdf(tdfContent);

  @override
  Future<T> withExclusiveTargetLock<T>(Future<T> Function() action) => action();
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
        'tdf 0.8.0\n\nqueue {\n  modified 2026-11-01 08:00:00\n  task 000001OkD2\n}\n\nlabel work00OkD2 {\n  name "Work"\n  modified 2026-11-01 08:00:00\n}\n\ntask 000001OkD2 {\n  name "Initial Task"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 08:00:00\n}\n';
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

    localTdf = 'tdf 0.8.0\n\nqueue {\n  modified 2026-11-01 09:30:00\n  task 000001OkD2\n  task 000002OkD2\n}\n\nlabel work00OkD2 {\n  name "Work"\n  modified 2026-11-01 08:00:00\n}\n\ntask 000001OkD2 {\n  name "Initial Task"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 08:00:00\n}\n\ntask 000002OkD2 {\n  name "External Local Task"\n  created 2026-11-01 09:30:00\n  modified 2026-11-01 09:30:00\n}\n';
    remoteTdf = 'tdf 0.8.0\n\nqueue {\n  modified 2026-11-01 08:00:00\n  task 000001OkD2\n}\n\nlabel work00OkD2 {\n  name "Enterprise"\n  modified 2026-11-01 09:45:00\n}\n\ntask 000001OkD2 {\n  name "Initial Task"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 08:00:00\n}\n';

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
    expect(localTdf, contains('tdf 0.8.0'));
  });

  test('Offline WebDAV save failure preserves local file sync and merges per-entity when connection returns', () async {
    var currentTime = DateTime.utc(2026, 11, 1, 8);
    var isOnline = true;
    var localTdf =
        'tdf 0.8.0\n\nqueue {\n  modified 2026-11-01 08:00:00\n  task 000001OkD2\n  task 000002OkD2\n}\n\nlabel ops000OkD2 {\n  name "Ops"\n  modified 2026-11-01 08:00:00\n}\n\ntask 000001OkD2 {\n  name "Task One"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 08:00:00\n}\n\ntask 000002OkD2 {\n  name "Task Two"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 08:00:00\n}\n';
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

    remoteTdf = 'tdf 0.8.0\n\nqueue {\n  modified 2026-11-01 08:00:00\n  task 000001OkD2\n  task 000002OkD2\n}\n\nlabel ops000OkD2 {\n  name "Ops"\n  modified 2026-11-01 08:00:00\n}\n\ntask 000001OkD2 {\n  name "Task One"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 08:00:00\n}\n\ntask 000002OkD2 {\n  name "Task Two Updated On Remote"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 09:30:00\n}\n';

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
    expect(
      convergedBoard.deletedBlock.findLabelRecord('ops000OkD2'),
      isNotNull,
    );

    final activeWorkspace = await container2.read(
      activeWorkspaceProvider.future,
    );
    final syncStateAfter = await settingsRepository.loadWorkspaceSyncState(
      activeWorkspace.id,
    );
    expect(syncStateAfter.acknowledgedRemoteGeneration, equals(0));
  });

  test('Unsupported TDF version on remote, local, or both stops retrying, never overwrites unreadable files, and surfaces localized update recommendations', () async {
    const service = TdfService();
    expect(
      () => service.parse('tdf 0.9.0\n'),
      throwsA(
        isA<TdfException>()
            .having(
              (error) => error.kind,
              'kind',
              equals(TdfErrorKind.unsupportedVersion),
            )
            .having((error) => error.sourceVersion, 'sourceVersion', '0.9.0')
            .having((error) => error.message, 'message', contains('0.8.0')),
      ),
    );

    final currentTime = DateTime.utc(2026, 11, 1, 12);
    var remoteFetchCount = 0;
    var remoteSaveCount = 0;
    var remoteTdf = 'tdf 0.9.0\n';
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
        'Die Remote-Datei verwendet die nicht unterstützte TDF-Version 0.9.0 (erwartet: 0.8.0).',
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
      getRemote: () => 'tdf 0.8.0\n',
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
        'The local file uses unsupported TDF version 0.7.0 (expected 0.8.0).',
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
        'Die lokale Datei und die Remote-Datei verwenden die nicht unterstützte TDF-Version 0.7.0 / 0.9.0 (erwartet: 0.8.0).',
      ),
    );
  });

  test('TaskSyncPipeline.runSyncWithStatus records exact UTC clockProvider timestamp in syncStateProvider.lastSyncedAt', () async {
    final fixedClock = DateTime(2026, 11, 1, 14, 30, 15);
    var localTdf = 'tdf 0.8.0\n';
    var remoteTdf = 'tdf 0.8.0\n';
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
        'tdf 0.8.0\n\nqueue {\n  modified 2026-11-01 08:00:00\n  task 000001OkD2\n}\n\ntask 000001OkD2 {\n  name "Local Surviving Task"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 08:00:00\n}\n';
    var remoteTdf =
        'tdf 0.8.0\n\nqueue {\n  modified 2026-11-01 09:00:00\n  task 000002OkD2\n}\n\ntask 000002OkD2 {\n  name "Remote Surviving Task"\n  created 2026-11-01 09:00:00\n  modified 2026-11-01 09:00:00\n}\n';
    final settingsRepository = InMemorySettingsRepository(bothConfig);
    final activeWorkspace = await settingsRepository.loadActiveWorkspace();
    const dummyDigest =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    await settingsRepository.saveWorkspaceSyncState(
      activeWorkspace.id,
      WorkspaceSyncState(
        lastSyncedLocalTdf: 'corrupted_header_without_version\n{{{',
        lastSyncedRemoteTdf: 'tdf 0.8.0\ntask broken {\n',
        acknowledgedLocalGeneration: 3,
        acknowledgedRemoteGeneration: 3,
        localSourceDigest: dummyDigest,
        remoteSourceDigest: dummyDigest,
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

  test('Universal 3-retry CAS-merge loop resolves concurrent local file edits before save and aborts after maxCasRetries', () async {
    expect(TaskSyncPipeline.maxCasRetries, equals(3));
    var currentTime = DateTime.utc(2026, 11, 1, 10);
    var localTdf =
        'tdf 0.8.0\n\nqueue {\n  modified 2026-11-01 08:00:00\n  task 000001OkD2\n}\n\ntask 000001OkD2 {\n  name "Base Task"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 08:00:00\n}\n';
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
        'tdf 0.8.0\n\nqueue {\n    modified 2026-11-01 08:00:00\n    task 000001OkD2\n}\n\ntask 000001OkD2 {\n    name     "Initial Task"\n    created  2026-11-01 08:00\n    modified 2026-11-01 08:00\n}\n';
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
          remoteTdf = 'tdf 0.8.0\n\nqueue {\n    modified 2026-11-01 08:00:00\n    task 000001OkD2\n}\n\ntask 000001OkD2 {\n    name     "Initial Task"\n    created  2026-11-01 08:00\n    modified 2026-11-01 08:00\n}\n\ntask 000002OkD2 {\n    name     "Concurrent Server Task"\n    created  2026-11-01 09:30\n    modified 2026-11-01 09:30\n}\n';
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

  test('TaskSyncPipeline.runSyncWithStatus sets SyncState.hasOpenConflict and localized banner when TdfSyncOutcomeException is thrown', () async {
    final settingsRepository = InMemorySettingsRepository(
      const WebDavConfig(
        storageMode: StorageMode.local,
        language: AppLanguage.english,
      ),
    );
    const baselineTdf =
        'tdf 0.8.0\n\n'
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
        'tdf 0.8.0\n\n'
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
              const WebDavConfig(
                storageMode: StorageMode.local,
                language: AppLanguage.english,
              ),
              candidateBoard: editedBoard,
            ),
      ),
    );
    await expectLater(runConflictSync, throwsA(isA<TdfSyncOutcomeException>()));

    final syncState = container.read(syncStateProvider);
    final enL10n = lookupAppLocalizations(const Locale('en'));
    expect(
      syncState.hasOpenConflict,
      isTrue,
      reason:
          'TdfSyncOutcomeException must mark SyncState.hasOpenConflict == true',
    );
    expect(syncState.errorMessage, equals(enL10n.syncConflictDeletionBanner));
  });

  test('TaskSyncPipeline.synchronize scopes baseline across external task/label/location deletions, generation bumps, and same-timestamp external edits without false deletionConflict or overwrite', () async {
    const gen0Initial =
        'tdf 0.8.0\n\n'
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
        'tdf 0.8.0\n\n'
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
        'tdf 0.8.0\n\n'
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
      'tdf 0.8.0\n\n'
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

  test('Opening and syncing an existing 0.8.0 workspace with open repeat + due + anchor + expired suspended preserves leadDays, anchor, and non-midnight repeat-time', () async {
    const existing080Tdf =
        'tdf 0.8.0\n\n'
        'queue {\n'
        '    modified 2026-11-11 10:00:00\n'
        '    task repMig0001\n'
        '}\n\n'
        'task repMig0001 {\n'
        '    name      "Monthly Rent"\n'
        '    created   2026-11-01 08:00:00\n'
        '    modified  2026-11-11 10:00:00\n'
        '    suspended 2026-11-11 12:00:00\n'
        '    due       2026-11-20 14:30:00 anchor 2026-11-20 16:30\n'
        '    repeat    1 months 16:30 lead 9 days\n'
        '}\n';

    var localTdf = existing080Tdf;
    var remoteTdf = existing080Tdf;
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
    expect(migratedTask?.repeatRule?.leadDays, equals(9));
    expect(migratedTask?.repeatRule?.clock.isMidnight, isFalse);
    expect(
      migratedTask?.dueAnchor,
      equals(TdfLocalDateTime(2026, 11, 20, 16, 30, 0)),
    );
    expect(migratedTask?.suspendedAt, isNull);
    expect(localTdf, startsWith('tdf 0.8.0\n'));
    expect(localTdf, contains('lead 9 days'));
    expect(localTdf, contains('anchor 2026-11-20 16:30'));
    expect(remoteTdf, equals(localTdf));

    var autoLocalTdf = existing080Tdf;
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
    expect(autoBoard.findTask('repMig0001')?.repeatRule?.leadDays, equals(9));
    expect(autoLocalTdf, startsWith('tdf 0.8.0\n'));
  });

  test('StorageMode.both stage-fair sync defers Stage 1 block cleanup so expired local suspended never inflates modified ahead of remote 11:30:00 note edit at 12:05:00', () async {
    // Subcase 1: Cold/2-way and 3-way sync at 12:05:00 where local task has older note (10:00:00) + expired suspended (12:00:00)
    // and remote edited task note at 11:30:00.
    var localTdf =
        'tdf 0.8.0\n\n'
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
        'tdf 0.8.0\n\n'
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
        'tdf 0.8.0\n\n'
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
        'tdf 0.8.0\n\n'
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

    const gen0Raw =
        'tdf 0.8.0\n\n'
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
            () => TaskSyncPipeline.synchronize(ref, localConfig),
      ),
    )();

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

    const gen1DiskRaw =
        'tdf 0.8.0\n\n'
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
            () => TaskSyncPipeline.synchronize(ref, localConfig),
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

  test('Comment-prefixed external .tdf loads on local disk and WebDAV perform zero writes, store canonical tdf 0.8.0 baselines, and record raw SHA-256 digests', () async {
    const commentedLocal =
        '# External editor header comment\n'
        '# Second comment line\n'
        'tdf 0.8.0\n\n'
        'queue {\n'
        '    modified 2026-11-11 08:00:00\n'
        '    task extCmt0001\n'
        '}\n\n'
        'task extCmt0001 {\n'
        '    name     "Commented External Task" # inline comment\n'
        '    created  2026-11-11 08:00:00\n'
        '    modified 2026-11-11 08:00:00\n'
        '}\n';
    final expectedRawDigest = Sha256Service.hashHex(
      utf8.encode(commentedLocal),
    );
    var localTdf = commentedLocal;
    var remoteTdf = commentedLocal;
    var localSaves = 0;
    var remoteSaves = 0;
    final settings = InMemorySettingsRepository(bothConfig);
    final container = createSyncContainer(
      config: bothConfig,
      settingsRepository: settings,
      clock: () => DateTime.utc(2026, 11, 11, 9, 0),
      getLocal: () => localTdf,
      setLocal: (value) {
        localSaves++;
        localTdf = value;
      },
      getRemote: () => remoteTdf,
      setRemote: (value) {
        remoteSaves++;
        remoteTdf = value;
      },
      isOnline: () => true,
    );
    addTearDown(container.dispose);

    final loaded = await container.read(taskNotifierProvider.future);
    expect(
      loaded.findTask('extCmt0001')?.title,
      equals('Commented External Task'),
    );
    expect(
      localSaves,
      equals(0),
      reason: 'Read-only load of clean comment-prefixed local .tdf must not overwrite external comments',
    );
    expect(
      remoteSaves,
      equals(0),
      reason: 'Read-only load of clean comment-prefixed WebDAV .tdf must not PUT over external comments',
    );
    expect(localTdf, startsWith('# External editor header comment\n'));
    expect(remoteTdf, startsWith('# External editor header comment\n'));

    final workspace = await container.read(activeWorkspaceProvider.future);
    final syncState = await settings.loadWorkspaceSyncState(workspace.id);
    expect(syncState.lastSyncedLocalTdf, isNotNull);
    expect(syncState.lastSyncedLocalTdf, startsWith('tdf 0.8.0\n'));
    expect(syncState.lastSyncedRemoteTdf, isNotNull);
    expect(syncState.lastSyncedRemoteTdf, startsWith('tdf 0.8.0\n'));
    expect(syncState.localSourceDigest, equals(expectedRawDigest));
    expect(syncState.remoteSourceDigest, equals(expectedRawDigest));
  });

  test('TaskSyncPipeline.resolveWorkspaceTimeZone returns TdfTimeZoneContext.systemLocal() in automatic mode and fixedOffset in manual mode (TDF-CTX-001)', () {
    const autoConfig = WebDavConfig(timeZoneMode: AppTimeZoneMode.automatic);
    final autoZone = TaskSyncPipeline.resolveWorkspaceTimeZone(
      autoConfig,
      DateTime.utc(2026, 1, 15, 12),
    );
    expect(
      autoZone,
      equals(const TdfTimeZoneContext.systemLocal()),
      reason: 'Automatic mode must return systemLocal() rather than freezing a single UTC instant fixedOffset',
    );

    const manualConfig = WebDavConfig(
      timeZoneMode: AppTimeZoneMode.manual,
      manualTimeZoneOffsetMinutes: -300,
    );
    final manualZone = TaskSyncPipeline.resolveWorkspaceTimeZone(
      manualConfig,
      DateTime.utc(2026, 1, 15, 12),
    );
    expect(
      manualZone,
      equals(TdfTimeZoneContext.fixedOffset(const Duration(minutes: -300))),
    );
  });

  test('Authoritative TDF-PUB-004 retention pruning runs in StorageMode.local (including unchanged-digest refresh and Step 3 retries with single generation increment) and is deferred in StorageMode.both Stage 1 while offline', () async {
    const expiredRetentionTdf =
        'tdf 0.8.0\n\n'
        'deleted {\n'
        '    generation 0\n'
        '    task expDelT001 2026-09-01 08:00:00 2\n'
        '    label expDelL001 2026-09-01 08:00:00\n'
        '}\n\n'
        'queue {\n'
        '    modified 2026-11-10 08:00:00\n'
        '    task openKeep01\n'
        '}\n\n'
        'task doneOld001 {\n'
        '    name        "Old Completed GC Target"\n'
        '    created     2026-09-01 08:00:00\n'
        '    modified    2026-09-10 08:00:00\n'
        '    finished    2026-09-10 08:00:00\n'
        '    completions 4\n'
        '}\n\n'
        'task doneNew002 {\n'
        '    name        "Recent Completed With Expired Blocker"\n'
        '    created     2026-11-05 08:00:00\n'
        '    modified    2026-11-05 09:00:00\n'
        '    finished    2026-11-05 09:00:00\n'
        '    completions 1\n'
        '    blocked     expDelT001\n'
        '}\n\n'
        'task openKeep01 {\n'
        '    name      "Open With Expired Suspended And Blocker"\n'
        '    created   2026-11-05 08:00:00\n'
        '    modified  2026-11-05 08:00:00\n'
        '    suspended 2026-11-14 12:00:00 "Expired hold"\n'
        '    blocked   expDelT001\n'
        '}\n';

    // 1. StorageMode.both while WebDAV is offline: Stage 1 (deferred) MUST NOT prune >30d tombstones/Completed, MUST NOT advance generation, and MUST NOT inflate/strip suspended <= now!
    var bothLocalTdf = expiredRetentionTdf;
    final evalTime = DateTime.utc(2026, 11, 15, 12, 0);
    var bothEvalTime = DateTime.utc(2026, 9, 25, 12, 0);
    var bothOnline = true;
    final bothOfflineContainer = createSyncContainer(
      config: bothConfig,
      settingsRepository: InMemorySettingsRepository(bothConfig),
      clock: () => bothEvalTime,
      getLocal: () => bothLocalTdf,
      setLocal: (value) => bothLocalTdf = value,
      getRemote: () => expiredRetentionTdf,
      setRemote: (_) {},
      isOnline: () => bothOnline,
    );
    addTearDown(bothOfflineContainer.dispose);

    final initialBothBoard = await bothOfflineContainer.read(
      taskNotifierProvider.future,
    );
    bothOnline = false;
    bothEvalTime = evalTime;
    final offlineCandidate = initialBothBoard.copyWith(
      someday: <TaskItem>[
        ...initialBothBoard.someday,
        TaskItem(
          id: 'offAdd0001',
          title: 'Offline Addition',
          createdAt: evalTime,
          modifiedAt: evalTime,
        ),
      ],
    );
    await bothOfflineContainer
        .read(taskNotifierProvider.notifier)
        .pushToRemote(offlineCandidate, fallbackBoard: initialBothBoard);
    final offlineDiskParsed = const TdfService().parse(
      bothLocalTdf,
      evaluationTime: evalTime,
    );
    expect(
      offlineDiskParsed.deletedBlock.generation,
      equals(0),
      reason: 'StorageMode.both Stage 1 while offline must never advance deleted.generation',
    );
    expect(
      offlineDiskParsed.deletedBlock.findTaskRecord('expDelT001'),
      isNotNull,
      reason:
          'StorageMode.both Stage 1 while offline must retain >30d tombstones',
    );
    expect(
      offlineDiskParsed.findTask('doneOld001'),
      isNotNull,
      reason: 'StorageMode.both Stage 1 while offline must retain >30d Completed tasks',
    );
    expect(
      offlineDiskParsed.findTask('openKeep01')?.suspendedAt,
      equals(DateTime.utc(2026, 11, 14, 12, 0)),
      reason: 'StorageMode.both Stage 1 while offline must defer suspended <= now cleanup',
    );

    // 2. StorageMode.local: authoritative local stage GCs >30d Completed into deleted, expires >30d tombstones, strips blocked across Completed + Open, and increments generation ONCE even across Step 3 contention retry!
    const localOnlyConfig = WebDavConfig(
      storageMode: StorageMode.local,
      localFilePath: 'tasks.tdf',
    );
    var localDisk = expiredRetentionTdf;
    var localReadCount = 0;
    var injectedRetryExpiredLocation = false;
    final localSettings = InMemorySettingsRepository(localOnlyConfig);
    final localContainer = createSyncContainer(
      config: localOnlyConfig,
      settingsRepository: localSettings,
      clock: () => evalTime,
      getLocal: () {
        localReadCount++;
        if (localReadCount == 2 && !injectedRetryExpiredLocation) {
          injectedRetryExpiredLocation = true;
          localDisk = localDisk.replaceFirst(
            'label expDelL001 2026-09-01 08:00:00\n',
            'label expDelL001 2026-09-01 08:00:00\n    location expDelLoc1 2026-09-02 08:00:00\n',
          );
        }
        return localDisk;
      },
      setLocal: (value) => localDisk = value,
      getRemote: () => '',
      setRemote: (_) {},
      isOnline: () => false,
    );
    addTearDown(localContainer.dispose);

    final prunedBoard = await localContainer.read(taskNotifierProvider.future);
    expect(
      prunedBoard.deletedBlock.generation,
      equals(1),
      reason: 'Multiple expired tombstones across initial pass and Step 3 retry must increment generation at most once (0 -> 1)',
    );
    expect(prunedBoard.findTask('doneOld001'), isNull);
    expect(
      prunedBoard.deletedBlock.findTaskRecord('doneOld001')?.deletedAt,
      equals(evalTime),
    );
    expect(
      prunedBoard.deletedBlock
          .findTaskRecord('doneOld001')
          ?.completionsCheckpoint,
      equals(4),
    );
    expect(prunedBoard.deletedBlock.findTaskRecord('expDelT001'), isNull);
    expect(prunedBoard.deletedBlock.findLabelRecord('expDelL001'), isNull);
    expect(prunedBoard.deletedBlock.findLocationRecord('expDelLoc1'), isNull);
    expect(prunedBoard.findTask('doneNew002')?.dependencies, isEmpty);
    expect(prunedBoard.findTask('openKeep01')?.dependencies, isEmpty);
    expect(prunedBoard.findTask('openKeep01')?.suspendedAt, isNull);
  });

  test('StorageMode.both Stage 1 Step 3 local contention retry under TdfCleanupMode.deferred keeps local task.modified at T11 so remote T12 wins in Stage 2 before stamping T100', () async {
    final t10 = DateTime.utc(2026, 11, 11, 10, 0);
    final t11 = DateTime.utc(2026, 11, 11, 11, 0);
    final t12 = DateTime.utc(2026, 11, 11, 12, 0);
    final t50 = DateTime.utc(2026, 11, 11, 15, 0);
    final t100 = DateTime.utc(2026, 11, 11, 20, 0);

    var localDisk =
        'tdf 0.8.0\n\n'
        'queue {\n'
        '    modified 2026-11-11 10:00:00\n'
        '    task retryFair1\n'
        '}\n\n'
        'task retryFair1 {\n'
        '    name      "Local T11 Note"\n'
        '    created   2026-11-11 10:00:00\n'
        '    modified  2026-11-11 11:00:00\n'
        '    suspended 2026-11-11 15:00:00 "Expired at T100"\n'
        '}\n';
    var remoteDisk =
        'tdf 0.8.0\n\n'
        'queue {\n'
        '    modified 2026-11-11 10:00:00\n'
        '    task retryFair1\n'
        '}\n\n'
        'task retryFair1 {\n'
        '    name      "Remote T12 Winner"\n'
        '    created   2026-11-11 10:00:00\n'
        '    modified  2026-11-11 12:00:00\n'
        '    suspended 2026-11-11 15:00:00 "Expired at T100"\n'
        '}\n';
    expect(t10.isBefore(t11) && t11.isBefore(t12) && t12.isBefore(t50), isTrue);

    var readCalls = 0;
    var injectedLocalContention = false;
    final container = createSyncContainer(
      config: bothConfig,
      settingsRepository: InMemorySettingsRepository(bothConfig),
      clock: () => t100,
      getLocal: () {
        readCalls++;
        if (readCalls == 2 && !injectedLocalContention) {
          injectedLocalContention = true;
          localDisk =
              '$localDisk\n'
              'task extSide002 {\n'
              '    name     "Concurrent Local Contention Task"\n'
              '    created  2026-11-11 11:30:00\n'
              '    modified 2026-11-11 11:30:00\n'
              '}\n';
        }
        return localDisk;
      },
      setLocal: (value) => localDisk = value,
      getRemote: () => remoteDisk,
      setRemote: (value) => remoteDisk = value,
      isOnline: () => true,
    );
    addTearDown(container.dispose);

    final converged = await container.read(taskNotifierProvider.future);
    final winner = converged.findTask('retryFair1');
    expect(
      winner?.title,
      equals('Remote T12 Winner'),
      reason: 'Stage 1 Step 3 retry must run in deferred cleanupMode keeping retryFair1 at T11 so remote T12 wins in Stage 2',
    );
    expect(winner?.suspendedAt, isNull);
    expect(winner?.modifiedAt, equals(t100));
    expect(converged.findTask('extSide002'), isNotNull);
  });

  test('StorageMode.both Stage 2 -> Stage 3 symmetric generation refresh handles Stage 2 retention bump (g -> g + 1) while external local writer edits local disk at g without false SyncGenerationRollback or tombstone resurrection', () async {
    const initialSynced =
        'tdf 0.8.0\n\n'
        'deleted {\n'
        '    generation 0\n'
        '    task expTomb001 2026-09-01 08:00:00\n'
        '}\n\n'
        'queue {\n'
        '    modified 2026-09-20 08:00:00\n'
        '    task keepShared\n'
        '}\n\n'
        'task keepShared {\n'
        '    name     "Shared Task"\n'
        '    created  2026-09-20 08:00:00\n'
        '    modified 2026-09-20 08:00:00\n'
        '}\n';

    var localDisk = initialSynced;
    var remoteDisk = initialSynced;
    var currentTime = DateTime.utc(2026, 9, 25, 12, 0);
    var injectConcurrentLocalDuringStage2 = false;

    final settings = InMemorySettingsRepository(bothConfig);
    final container = createSyncContainer(
      config: bothConfig,
      settingsRepository: settings,
      clock: () => currentTime,
      getLocal: () => localDisk,
      setLocal: (value) => localDisk = value,
      getRemote: () => remoteDisk,
      setRemote: (value) {
        remoteDisk = value;
        if (injectConcurrentLocalDuringStage2) {
          injectConcurrentLocalDuringStage2 = false;
          // External local writer modifies keepShared on localDisk (still at generation 0 with expTomb001!) while Stage 2 just saved generation 1 to WebDAV!
          localDisk = initialSynced
              .replaceFirst('"Shared Task"', '"Edited Locally During Stage 2"')
              .replaceFirst(
                'modified 2026-09-20 08:00:00\n}',
                'modified 2026-11-15 11:59:00\n}',
              );
        }
      },
      isOnline: () => true,
    );
    addTearDown(container.dispose);

    // 1. Sync at 2026-09-25 (< 30 days): generation stays 0, expTomb001 acknowledged at gen 0.
    final initialBoard = await container.read(taskNotifierProvider.future);
    expect(initialBoard.deletedBlock.generation, equals(0));
    expect(initialBoard.deletedBlock.findTaskRecord('expTomb001'), isNotNull);

    // 2. Advance past 30 days (2026-11-15): Stage 1 (deferred) keeps generation 0; Stage 2 (finalStage) expires expTomb001 (0 -> 1); during Stage 2 PUT, external local writer edits localDisk at generation 0; Stage 3 converges without SyncGenerationRollback or resurrecting expTomb001!
    currentTime = DateTime.utc(2026, 11, 15, 12, 0);
    injectConcurrentLocalDuringStage2 = true;
    await container.read(taskNotifierProvider.notifier).syncFromRemote();

    expect(container.read(syncStateProvider).hasOpenConflict, isFalse);
    expect(container.read(syncStateProvider).errorMessage, isNull);
    final converged = container.read(taskNotifierProvider).requireValue;
    expect(converged.deletedBlock.generation, equals(1));
    expect(
      converged.deletedBlock.findTaskRecord('expTomb001'),
      isNull,
      reason: 'Expired tombstone retired in Stage 2 must not be resurrected by Stage 3 local disk at generation 0',
    );
    expect(
      converged.findTask('keepShared')?.title,
      equals('Edited Locally During Stage 2'),
    );
  });

  test('External local file deletion when localSourceDigest != null and loopL has live entities throws RecoveryRequired without recreating target file (TDF-PUB-003 Step 3)', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'tiertask_ext_delete_recovery_',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final targetFile = File('${tempDir.path}/tasks.tdf');
    await targetFile.writeAsString(
      'tdf 0.8.0\n\n'
      'queue {\n'
      '    modified 2026-11-01 08:00:00\n'
      '    task liveKeep01\n'
      '}\n\n'
      'task liveKeep01 {\n'
      '    name     "Must Not Silently Recreate"\n'
      '    created  2026-11-01 08:00:00\n'
      '    modified 2026-11-01 08:00:00\n'
      '}\n',
      flush: true,
    );

    const localConfig = WebDavConfig(
      storageMode: StorageMode.local,
      localFilePath: 'tasks.tdf',
    );
    final settings = InMemorySettingsRepository(localConfig);
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1, 9, 0)),
        localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
      ],
    );
    addTearDown(container.dispose);

    await container.read(taskNotifierProvider.future);
    expect(await targetFile.exists(), isTrue);

    // Externally delete <target> while localSourceDigest != null and board has live entities:
    await targetFile.delete();
    expect(await targetFile.exists(), isFalse);

    await expectLater(
      () => container.read(
        Provider<Future<TaskBoard> Function()>(
          (ref) =>
              () => TaskSyncPipeline.runSyncWithStatus(
                ref,
                localConfig,
                candidateBoard: container
                    .read(taskNotifierProvider)
                    .requireValue,
              ),
        ),
      )(),
      throwsA(
        isA<TdfSyncOutcomeException>()
            .having(
              (error) => error.kind,
              'kind',
              TdfSyncOutcomeKind.recoveryRequired,
            )
            .having(
              (error) => error.ambiguousTaskIds,
              'ambiguousTaskIds',
              contains('liveKeep01'),
            ),
      ),
    );
    expect(
      await targetFile.exists(),
      isFalse,
      reason: 'RecoveryRequired on external file removal must NOT recreate <target>',
    );
  });

  test('StorageMode.webdav HTTP 304 on queued optimistic mutation merges against cached remote baseline instead of wiping remote additions, edits, and generation bumps', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    const initialTdf =
        'tdf 0.8.0\n\n'
        'queue {\n'
        '    modified 2026-11-01 08:00:00\n'
        '    task tsk0000001\n'
        '    task tsk0000002\n'
        '    task tsk0000003\n'
        '    task tskRet0001\n'
        '}\n\n'
        'task tsk0000001 {\n'
        '    name     "Task One"\n'
        '    created  2026-11-01 08:00:00\n'
        '    modified 2026-11-01 08:00:00\n'
        '}\n\n'
        'task tsk0000002 {\n'
        '    name     "Task Two"\n'
        '    created  2026-11-01 08:00:00\n'
        '    modified 2026-11-01 08:00:00\n'
        '}\n\n'
        'task tsk0000003 {\n'
        '    name     "Task Three"\n'
        '    created  2026-11-01 08:00:00\n'
        '    modified 2026-11-01 08:00:00\n'
        '}\n\n'
        'task tskRet0001 {\n'
        '    name     "Retired Remote Task"\n'
        '    created  2026-11-01 08:00:00\n'
        '    modified 2026-11-01 08:00:00\n'
        '}\n';
    const remoteV2Tdf =
        'tdf 0.8.0\n\n'
        'deleted {\n'
        '    generation 1\n'
        '}\n\n'
        'queue {\n'
        '    modified 2026-11-01 09:00:00\n'
        '    task tsk0000001\n'
        '    task tsk0000002\n'
        '    task tsk0000003\n'
        '    task tskRem0001\n'
        '}\n\n'
        'task tsk0000001 {\n'
        '    name     "Task One Edited Remotely"\n'
        '    created  2026-11-01 08:00:00\n'
        '    modified 2026-11-01 09:00:00\n'
        '}\n\n'
        'task tsk0000002 {\n'
        '    name     "Task Two"\n'
        '    created  2026-11-01 08:00:00\n'
        '    modified 2026-11-01 08:00:00\n'
        '}\n\n'
        'task tsk0000003 {\n'
        '    name     "Task Three"\n'
        '    created  2026-11-01 08:00:00\n'
        '    modified 2026-11-01 08:00:00\n'
        '}\n\n'
        'task tskRem0001 {\n'
        '    name     "Remote Added Task"\n'
        '    created  2026-11-01 09:00:00\n'
        '    modified 2026-11-01 09:00:00\n'
        '}\n';

    var remoteTdf = initialTdf;
    var remoteEtag = '"etag-v1"';
    var get304Count = 0;
    var putCount = 0;
    var gateNextGet = false;
    final mut1GetStarted = Completer<void>();
    final releaseMut1Get = Completer<void>();

    server.listen((HttpRequest request) async {
      if (request.method == 'GET') {
        if (gateNextGet) {
          gateNextGet = false;
          mut1GetStarted.complete();
          await releaseMut1Get.future;
        }
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
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
        request.response.write(remoteTdf);
        await request.response.close();
        return;
      }
      if (request.method == 'PUT') {
        putCount++;
        final body = await utf8.decoder.bind(request).join();
        remoteTdf = body;
        remoteEtag = '"etag-put-$putCount"';
        request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      }
    });

    var currentTime = DateTime.utc(2026, 11, 1, 8, 30);
    final config = WebDavConfig(
      storageMode: StorageMode.webdav,
      serverUrl: 'http://${server.address.host}:${server.port}',
      username: 'alice',
      password: 'secret',
      filePath: 'tasks.tdf',
    );
    final settings = InMemorySettingsRepository(config);
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        clockProvider.overrideWithValue(() => currentTime),
      ],
    );
    addTearDown(container.dispose);

    await container.read(taskNotifierProvider.future);
    final notifier = container.read(taskNotifierProvider.notifier);

    // Remote server advances to v2 with a remote addition, edit, and generation 0 -> 1 retirement.
    remoteTdf = remoteV2Tdf;
    remoteEtag = '"etag-v2"';
    gateNextGet = true;

    currentTime = DateTime.utc(2026, 11, 1, 9, 10);
    final mutation1Future = notifier.updateTask(
      'tsk0000002',
      title: 'Task Two Local 1',
    );
    await mut1GetStarted.future;

    // Queue Mutation 2 against optimistic B_mut1 (which lacks v2 changes and still has gen 0 + tskRet0001).
    currentTime = DateTime.utc(2026, 11, 1, 9, 11);
    final mutation2Future = notifier.updateTask(
      'tsk0000003',
      title: 'Task Three Local 2',
    );
    releaseMut1Get.complete();
    await Future.wait(<Future<void>>[mutation1Future, mutation2Future]);

    expect(
      get304Count,
      greaterThanOrEqualTo(1),
      reason: 'Queued Mutation 2 must hit HTTP 304 Not Modified after Mutation 1 published v3',
    );
    final finalBoard = container.read(taskNotifierProvider).requireValue;
    expect(
      finalBoard.findTask('tskRem0001')?.title,
      equals('Remote Added Task'),
      reason: 'HTTP 304 on queued optimistic mutation must not wipe remote additions',
    );
    expect(
      finalBoard.findTask('tsk0000001')?.title,
      equals('Task One Edited Remotely'),
      reason: 'HTTP 304 on queued optimistic mutation must not roll back remote edits',
    );
    expect(
      finalBoard.findTask('tskRet0001'),
      isNull,
      reason: 'HTTP 304 on queued optimistic mutation must not resurrect tasks retired by generation bump',
    );
    expect(
      finalBoard.deletedBlock.generation,
      equals(1),
      reason: 'HTTP 304 on queued optimistic mutation must preserve remote deleted.generation',
    );
    expect(
      finalBoard.findTask('tsk0000002')?.title,
      equals('Task Two Local 1'),
    );
    expect(
      finalBoard.findTask('tsk0000003')?.title,
      equals('Task Three Local 2'),
    );
    expect(remoteTdf, contains('tskRem0001'));
    expect(remoteTdf, contains('Task One Edited Remotely'));
    expect(remoteTdf, contains('generation 1'));
    expect(remoteTdf, isNot(contains('tskRet0001')));
  });

  test('WebDAV 412 CAS retry uses fetched R1 baseline instead of stale R0 (preserving R2 deletions and scalar clears)', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    const remoteR0 =
        'tdf 0.8.0\n\n'
        'queue {\n'
        '    modified 2026-11-01 08:00:00\n'
        '    task tskA000001\n'
        '    task tskLoc0001\n'
        '}\n\n'
        'task tskA000001 {\n'
        '    name     "Task A"\n'
        '    created  2026-11-01 08:00:00\n'
        '    modified 2026-11-01 08:00:00\n'
        '}\n\n'
        'task tskLoc0001 {\n'
        '    name     "Local Target"\n'
        '    created  2026-11-01 08:00:00\n'
        '    modified 2026-11-01 08:00:00\n'
        '}\n';
    const remoteR1 =
        'tdf 0.8.0\n\n'
        'queue {\n'
        '    modified 2026-11-01 09:00:00\n'
        '    task tskA000001\n'
        '    task tskLoc0001\n'
        '    task tskB000001\n'
        '}\n\n'
        'task tskA000001 {\n'
        '    name     "Task A"\n'
        '    note     "Note From R1"\n'
        '    created  2026-11-01 08:00:00\n'
        '    modified 2026-11-01 09:00:00\n'
        '}\n\n'
        'task tskLoc0001 {\n'
        '    name     "Local Target"\n'
        '    created  2026-11-01 08:00:00\n'
        '    modified 2026-11-01 08:00:00\n'
        '}\n\n'
        'task tskB000001 {\n'
        '    name     "Task B Added In R1"\n'
        '    created  2026-11-01 09:00:00\n'
        '    modified 2026-11-01 09:00:00\n'
        '}\n';
    const remoteR2 =
        'tdf 0.8.0\n\n'
        'deleted {\n'
        '    generation 0\n'
        '    task tskB000001 2026-11-01 09:30:00\n'
        '}\n\n'
        'queue {\n'
        '    modified 2026-11-01 09:30:00\n'
        '    task tskA000001\n'
        '    task tskLoc0001\n'
        '}\n\n'
        'task tskA000001 {\n'
        '    name     "Task A"\n'
        '    created  2026-11-01 08:00:00\n'
        '    modified 2026-11-01 09:30:00\n'
        '}\n\n'
        'task tskLoc0001 {\n'
        '    name     "Local Target"\n'
        '    created  2026-11-01 08:00:00\n'
        '    modified 2026-11-01 08:00:00\n'
        '}\n';

    var remoteTdf = remoteR0;
    var remoteEtag = '"etag-r0"';
    var injectR2OnNextPut = false;
    var put412Count = 0;
    var put2xxCount = 0;

    server.listen((HttpRequest request) async {
      if (request.method == 'GET') {
        final ifNoneMatch = request.headers.value(
          HttpHeaders.ifNoneMatchHeader,
        );
        if (ifNoneMatch == remoteEtag) {
          request.response.statusCode = HttpStatus.notModified;
          request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
        request.response.write(remoteTdf);
        await request.response.close();
        return;
      }
      if (request.method == 'PUT') {
        final body = await utf8.decoder.bind(request).join();
        final ifMatch = request.headers.value(HttpHeaders.ifMatchHeader);
        if (injectR2OnNextPut) {
          injectR2OnNextPut = false;
          remoteTdf = remoteR2;
          remoteEtag = '"etag-r2"';
        }
        if (ifMatch != null && ifMatch != remoteEtag) {
          put412Count++;
          request.response.statusCode = HttpStatus.preconditionFailed;
          await request.response.close();
          return;
        }
        put2xxCount++;
        remoteTdf = body;
        remoteEtag = '"etag-put-$put2xxCount"';
        request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      }
    });

    var currentTime = DateTime.utc(2026, 11, 1, 8, 30);
    final config = WebDavConfig(
      storageMode: StorageMode.webdav,
      serverUrl: 'http://${server.address.host}:${server.port}',
      username: 'alice',
      password: 'secret',
      filePath: 'tasks.tdf',
    );
    final settings = InMemorySettingsRepository(config);
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        clockProvider.overrideWithValue(() => currentTime),
      ],
    );
    addTearDown(container.dispose);

    await container.read(taskNotifierProvider.future);

    // Advance remote to R1, and inject R2 between GET(R1) and PUT(If-Match: "etag-r1").
    remoteTdf = remoteR1;
    remoteEtag = '"etag-r1"';
    injectR2OnNextPut = true;

    currentTime = DateTime.utc(2026, 11, 1, 9, 40);
    await container
        .read(taskNotifierProvider.notifier)
        .updateTask('tskLoc0001', title: 'Local Target Updated');

    expect(put412Count, equals(1));
    expect(put2xxCount, equals(1));
    expect(
      container.read(syncStateProvider).hasOpenConflict,
      isFalse,
      reason: '412 retry against R1 baseline must not raise false DeletionConflict for tskB000001 deleted in R2',
    );
    expect(container.read(syncStateProvider).errorMessage, isNull);
    final converged = container.read(taskNotifierProvider).requireValue;
    expect(
      converged.findTask('tskB000001'),
      isNull,
      reason: 'Task B added in R1 and deleted in R2 must stay deleted after 412 CAS retry',
    );
    expect(converged.deletedBlock.findTaskRecord('tskB000001'), isNotNull);
    expect(
      converged.findTask('tskA000001')?.note ?? '',
      isEmpty,
      reason: 'Scalar clear of Task A note in R2 must not be overwritten by R1 note via stale R0 baseline',
    );
    expect(
      converged.findTask('tskLoc0001')?.title,
      equals('Local Target Updated'),
    );
  });

  test('WebDAV 412 CAS retry encountering external remote 404 deletion throws RecoveryRequired without silently wiping tasks', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    var remoteExists = true;
    var remoteTdf =
        'tdf 0.8.0\n\n'
        'queue {\n'
        '    modified 2026-11-01 08:00:00\n'
        '    task tskKeep001\n'
        '}\n\n'
        'task tskKeep001 {\n'
        '    name     "Keep Me"\n'
        '    created  2026-11-01 08:00:00\n'
        '    modified 2026-11-01 08:00:00\n'
        '}\n';
    var remoteEtag = '"etag-v1"';
    var deleteRemoteOnNextPut = false;
    var putSuccessCount = 0;

    server.listen((HttpRequest request) async {
      if (request.method == 'GET') {
        if (!remoteExists) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        final ifNoneMatch = request.headers.value(
          HttpHeaders.ifNoneMatchHeader,
        );
        if (ifNoneMatch == remoteEtag) {
          request.response.statusCode = HttpStatus.notModified;
          request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
        request.response.write(remoteTdf);
        await request.response.close();
        return;
      }
      if (request.method == 'PUT') {
        final body = await utf8.decoder.bind(request).join();
        if (deleteRemoteOnNextPut) {
          deleteRemoteOnNextPut = false;
          remoteExists = false;
          remoteTdf = '';
          request.response.statusCode = HttpStatus.preconditionFailed;
          await request.response.close();
          return;
        }
        putSuccessCount++;
        remoteExists = true;
        remoteTdf = body;
        remoteEtag = '"etag-put-$putSuccessCount"';
        request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      }
    });

    final config = WebDavConfig(
      storageMode: StorageMode.webdav,
      serverUrl: 'http://${server.address.host}:${server.port}',
      username: 'alice',
      password: 'secret',
      filePath: 'tasks.tdf',
    );
    final settings = InMemorySettingsRepository(config);
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1, 9, 0)),
      ],
    );
    addTearDown(container.dispose);

    final loaded = await container.read(taskNotifierProvider.future);
    final mutated = loaded.updateTask(
      'tskKeep001',
      title: 'Keep Me Edited',
      currentDate: DateTime.utc(2026, 11, 1, 9, 5),
    );
    deleteRemoteOnNextPut = true;

    await expectLater(
      () => container.read(
        Provider<Future<TaskBoard> Function()>(
          (ref) =>
              () => TaskSyncPipeline.runSyncWithStatus(
                ref,
                config,
                candidateBoard: mutated,
                candidateOriginBoard: loaded,
              ),
        ),
      )(),
      throwsA(
        isA<TdfSyncOutcomeException>()
            .having(
              (error) => error.kind,
              'kind',
              TdfSyncOutcomeKind.recoveryRequired,
            )
            .having(
              (error) => error.ambiguousTaskIds,
              'ambiguousTaskIds',
              contains('tskKeep001'),
            ),
      ),
    );
    expect(
      putSuccessCount,
      equals(0),
      reason: 'External 404 on 412 CAS retry must raise RecoveryRequired without overwriting remote',
    );
    expect(remoteExists, isFalse);
  });

  test('StorageMode.both persists Stage 2 committed WebDAV WorkspaceSyncState even when Stage 3 local convergence fails', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    const initialTdf =
        'tdf 0.8.0\n\n'
        'queue {\n'
        '    modified 2026-11-01 08:00:00\n'
        '    task tskInit001\n'
        '}\n\n'
        'task tskInit001 {\n'
        '    name     "Initial Task"\n'
        '    created  2026-11-01 08:00:00\n'
        '    modified 2026-11-01 08:00:00\n'
        '}\n';
    const remoteStage2Tdf =
        'tdf 0.8.0\n\n'
        'deleted {\n'
        '    generation 1\n'
        '}\n\n'
        'queue {\n'
        '    modified 2026-11-01 09:00:00\n'
        '    task tskInit001\n'
        '    task tskRem0002\n'
        '}\n\n'
        'task tskInit001 {\n'
        '    name     "Initial Task"\n'
        '    created  2026-11-01 08:00:00\n'
        '    modified 2026-11-01 08:00:00\n'
        '}\n\n'
        'task tskRem0002 {\n'
        '    name     "Remote Stage 2 Task"\n'
        '    created  2026-11-01 09:00:00\n'
        '    modified 2026-11-01 09:00:00\n'
        '}\n';

    var remoteTdf = initialTdf;
    var remoteEtag = '"etag-both-v1"';
    server.listen((HttpRequest request) async {
      if (request.method == 'GET') {
        final ifNoneMatch = request.headers.value(
          HttpHeaders.ifNoneMatchHeader,
        );
        if (ifNoneMatch == remoteEtag) {
          request.response.statusCode = HttpStatus.notModified;
          request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
        request.response.write(remoteTdf);
        await request.response.close();
        return;
      }
      if (request.method == 'PUT') {
        remoteTdf = await utf8.decoder.bind(request).join();
        remoteEtag = '"etag-both-put"';
        request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      }
    });

    final tempDir = await Directory.systemTemp.createTemp(
      'tiertask_both_stage3_fail_',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final bothConfig = WebDavConfig(
      storageMode: StorageMode.both,
      localFilePath: 'tasks.tdf',
      serverUrl: 'http://${server.address.host}:${server.port}',
      username: 'alice',
      password: 'secret',
      filePath: 'tasks.tdf',
    );
    final settings = InMemorySettingsRepository(bothConfig);
    var failLocalSave = false;
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1, 9, 30)),
        localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
        localFileRepositoryProvider.overrideWithValue(
          _FailableSaveLocalRepository(
            config: bothConfig,
            baseDirectoryPath: tempDir.path,
            shouldFailSave: () => failLocalSave,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    // 1. Converge initial state across local and remote.
    final loaded = await container.read(taskNotifierProvider.future);
    expect(loaded.findTask('tskInit001'), isNotNull);

    // 2. Remote advances to generation 1 with tskRem0002; Stage 3 local save fails.
    remoteTdf = remoteStage2Tdf;
    remoteEtag = '"etag-both-v2"';
    failLocalSave = true;

    await expectLater(
      () => container.read(
        Provider<Future<TaskBoard> Function()>(
          (ref) =>
              () => TaskSyncPipeline.synchronize(
                ref,
                bothConfig,
                candidateBoard: loaded,
              ),
        ),
      )(),
      throwsA(isA<LocalFileException>()),
    );

    final workspace = await container.read(activeWorkspaceProvider.future);
    final savedState = await settings.loadWorkspaceSyncState(workspace.id);
    expect(
      savedState.remoteEtag,
      equals('"etag-both-v2"'),
      reason: 'Stage 2 WebDAV ETag must be persisted before Stage 3 local convergence runs',
    );
    expect(
      savedState.acknowledgedRemoteGeneration,
      equals(1),
      reason: 'Stage 2 acknowledgedRemoteGeneration must survive Stage 3 local write failure',
    );
    expect(
      savedState.lastSyncedRemoteTdf,
      contains('tskRem0002'),
      reason: 'Stage 2 lastSyncedRemoteTdf must be durably committed before Stage 3 fails',
    );
    expect(
      savedState.remoteSourceDigest,
      equals(Sha256Service.hashHex(utf8.encode(remoteStage2Tdf))),
    );
  });

  test('External WebDAV HTTP 404 after prior sync throws RecoveryRequired without re-uploading, while fresh remoteSourceDigest == null still creates via PUT', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    var remoteExists = false;
    var remoteTdf = '';
    var remoteEtag = '"etag-init"';
    var putCount = 0;

    server.listen((HttpRequest request) async {
      if (request.method == 'GET') {
        if (!remoteExists) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        final ifNoneMatch = request.headers.value(
          HttpHeaders.ifNoneMatchHeader,
        );
        if (ifNoneMatch == remoteEtag) {
          request.response.statusCode = HttpStatus.notModified;
          request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
        request.response.write(remoteTdf);
        await request.response.close();
        return;
      }
      if (request.method == 'PUT') {
        putCount++;
        remoteExists = true;
        remoteTdf = await utf8.decoder.bind(request).join();
        remoteEtag = '"etag-put-$putCount"';
        request.response.headers.set(HttpHeaders.etagHeader, remoteEtag);
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      }
    });

    final config = WebDavConfig(
      storageMode: StorageMode.webdav,
      serverUrl: 'http://${server.address.host}:${server.port}',
      username: 'alice',
      password: 'secret',
      filePath: 'tasks.tdf',
    );
    final settings = InMemorySettingsRepository(config);
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1, 9, 0)),
      ],
    );
    addTearDown(container.dispose);

    // 1. Fresh WebDAV workspace (remoteSourceDigest == null) with 404 initializes and uploads via PUT.
    await container.read(taskNotifierProvider.future);
    await container
        .read(taskNotifierProvider.notifier)
        .addTask('Created On Fresh Remote', targetTier: TaskTier.someday);
    expect(remoteExists, isTrue);
    expect(putCount, equals(1));
    final createdBoard = container.read(taskNotifierProvider).requireValue;
    final createdTaskId = createdBoard.allTasks.single.id;

    // 2. Externally delete remote file (HTTP 404) while remoteSourceDigest != null: must throw RecoveryRequired without re-uploading.
    remoteExists = false;
    remoteTdf = '';
    final putsBeforeExternal404 = putCount;

    await expectLater(
      () => container.read(
        Provider<Future<TaskBoard> Function()>(
          (ref) =>
              () => TaskSyncPipeline.runSyncWithStatus(
                ref,
                config,
                candidateBoard: createdBoard,
              ),
        ),
      )(),
      throwsA(
        isA<TdfSyncOutcomeException>()
            .having(
              (error) => error.kind,
              'kind',
              TdfSyncOutcomeKind.recoveryRequired,
            )
            .having(
              (error) => error.ambiguousTaskIds,
              'ambiguousTaskIds',
              contains(createdTaskId),
            ),
      ),
    );
    expect(
      putCount,
      equals(putsBeforeExternal404),
      reason: 'External WebDAV 404 after prior sync must NOT silently re-upload the remote file',
    );
    expect(remoteExists, isFalse);

    // 3. Explicit RecoveryRequired resolution recovers the task with a fresh ID and uploads cleanly.
    final recovered = await container.read(
      Provider<Future<TaskBoard> Function()>(
        (ref) =>
            () => TaskSyncPipeline.runSyncWithStatus(
              ref,
              config,
              candidateBoard: createdBoard,
              taskRecoveryResolutions: <String, TdfRecoveryResolution>{
                createdTaskId: TdfRecoveryResolution.recoverAsNew,
              },
            ),
      ),
    )();
    expect(remoteExists, isTrue);
    expect(putCount, equals(putsBeforeExternal404 + 1));
    expect(recovered.allTasks.single.title, equals('Created On Fresh Remote'));
    expect(recovered.allTasks.single.id, isNot(equals(createdTaskId)));
  });
}

class _FailableSaveLocalRepository extends LocalFileRepository {
  _FailableSaveLocalRepository({
    required super.config,
    super.baseDirectoryPath,
    required this.shouldFailSave,
  });

  final bool Function() shouldFailSave;

  @override
  Future<void> saveTdf(String tdfContent) async {
    if (shouldFailSave()) {
      throw const LocalFileException('Simulated Stage 3 local save failure');
    }
    await super.saveTdf(tdfContent);
  }
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
