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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/sync_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';
import 'package:tiertask/services/tdf_service.dart';

class _InMemorySyncLocalRepository extends LocalFileRepository {
  _InMemorySyncLocalRepository({
    required super.config,
    required this.getTdf,
    required this.setTdf,
  });

  final String Function() getTdf;
  final void Function(String value) setTdf;

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
    required SettingsRepository settingsRepo,
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
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
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
    final settingsRepo = InMemorySettingsRepository();
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(settingsRepo)],
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
    expect(
      container.read(syncStateProvider).errorMessage,
      equals('Connection failed'),
    );

    notifier.clearError();
    expect(container.read(syncStateProvider).errorMessage, isNull);
    expect(container.read(syncStateProvider).lastSyncedAt, equals(syncedAt));

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
    final settingsRepo = InMemorySettingsRepository(bothConfig);

    final container = createSyncContainer(
      settingsRepo: settingsRepo,
      clock: () => currentTime,
      getLocal: () => localTdf,
      setLocal: (val) => localTdf = val,
      getRemote: () => remoteTdf,
      setRemote: (val) => remoteTdf = val,
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
    expect(localTdf, contains('tdf 0.5.1'));
  });

  test('Offline WebDAV save failure preserves local file sync and merges per-entity when connection returns', () async {
    var currentTime = DateTime.utc(2026, 11, 1, 8);
    var isOnline = true;
    var localTdf =
        'tdf 0.5.0\n\nqueue {\n  modified 2026-11-01 08:00:00\n  task 000001OkD2\n  task 000002OkD2\n}\n\nlabel ops000OkD2 {\n  name "Ops"\n  modified 2026-11-01 08:00:00\n}\n\ntask 000001OkD2 {\n  name "Task One"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 08:00:00\n  queued 2026-11-01 08:00:00\n}\n\ntask 000002OkD2 {\n  name "Task Two"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 08:00:00\n  queued 2026-11-01 08:00:00\n}\n';
    var remoteTdf = localTdf;
    final settingsRepo = InMemorySettingsRepository(bothConfig);

    final container1 = createSyncContainer(
      settingsRepo: settingsRepo,
      clock: () => currentTime,
      getLocal: () => localTdf,
      setLocal: (val) => localTdf = val,
      getRemote: () => remoteTdf,
      setRemote: (val) => remoteTdf = val,
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
    expect(localTdf, contains('finished 2026-11-01 09:00'));

    remoteTdf = 'tdf 0.5.0\n\nqueue {\n  modified 2026-11-01 08:00:00\n  task 000001OkD2\n  task 000002OkD2\n}\n\nlabel ops000OkD2 {\n  name "Ops"\n  modified 2026-11-01 08:00:00\n}\n\ntask 000001OkD2 {\n  name "Task One"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 08:00:00\n  queued 2026-11-01 08:00:00\n}\n\ntask 000002OkD2 {\n  name "Task Two Updated On Remote"\n  created 2026-11-01 08:00:00\n  modified 2026-11-01 09:30:00\n  queued 2026-11-01 08:00:00\n}\n';

    container1.dispose();
    isOnline = true;
    currentTime = DateTime.utc(2026, 11, 1, 10);
    final container2 = createSyncContainer(
      settingsRepo: settingsRepo,
      clock: () => currentTime,
      getLocal: () => localTdf,
      setLocal: (val) => localTdf = val,
      getRemote: () => remoteTdf,
      setRemote: (val) => remoteTdf = val,
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
    final syncStateAfter = await settingsRepo.loadWorkspaceSyncState(
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
    final settingsRepo = InMemorySettingsRepository(bothConfig);

    final container = createSyncContainer(
      settingsRepo: settingsRepo,
      clock: () => currentTime,
      getLocal: () => localTdf,
      setLocal: (val) {
        localSaveCount++;
        localTdf = val;
      },
      getRemote: () => remoteTdf,
      setRemote: (val) {
        remoteSaveCount++;
        remoteTdf = val;
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
    expect(localTdf, startsWith('tdf 0.5.1\n'));
    expect(remoteTdf, equals(localTdf));
  });

  test('Unsupported TDF version on remote, local, or both stops retrying, never overwrites unreadable files, and surfaces localized update recommendations', () async {
    const service = TdfService();
    expect(
      () => service.parse('tdf 0.6.0\n'),
      throwsA(
        isA<TdfException>()
            .having(
              (error) => error.kind,
              'kind',
              equals(TdfErrorKind.unsupportedVersion),
            )
            .having((error) => error.sourceVersion, 'sourceVersion', '0.6.0')
            .having((error) => error.targetVersion, 'targetVersion', '0.5.1'),
      ),
    );

    final currentTime = DateTime.utc(2026, 11, 1, 12);
    var remoteFetchCount = 0;
    var remoteSaveCount = 0;
    var remoteTdf = 'tdf 0.6.0\n';
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
      settingsRepo: InMemorySettingsRepository(webDavDeConfig),
      clock: () => currentTime,
      getLocal: () => '',
      setLocal: (_) {},
      getRemote: () {
        remoteFetchCount++;
        return remoteTdf;
      },
      setRemote: (val) {
        remoteSaveCount++;
        remoteTdf = val;
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
        'Die Remote-Datei verwendet die nicht unterstützte Dateiversion 0.6.0. Bitte aktualisieren Sie TierTask auf eine neuere Version.',
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
      settingsRepo: InMemorySettingsRepository(bothEnConfig),
      clock: () => currentTime,
      getLocal: () => 'tdf 0.6.0\n',
      setLocal: (_) => localFailSaveCount++,
      getRemote: () => 'tdf 0.5.1\n',
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
        'The local file uses unsupported file version 0.6.0. Please update TierTask to a newer version.',
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
      settingsRepo: InMemorySettingsRepository(bothDeConfig),
      clock: () => currentTime,
      getLocal: () => 'tdf 0.6.0\n',
      setLocal: (_) {},
      getRemote: () {
        bothFailRemoteFetchCount++;
        return 'tdf 0.7.0\n';
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
        'Die lokale Datei und die Remote-Datei verwenden die nicht unterstützte Dateiversion 0.6.0 / 0.7.0. Bitte aktualisieren Sie TierTask auf eine neuere Version.',
      ),
    );
  });
}
