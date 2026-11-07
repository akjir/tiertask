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
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';

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
  test('Two-stage save pipeline merges external local file edits first and then merges with WebDAV on save', () async {
    var currentTime = DateTime.utc(2026, 11, 1, 9);
    var localTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 08:00:00
  task 000001OkD2
}

label work00OkD2 {
  name "Work"
  modified 2026-11-01 08:00:00
}

task 000001OkD2 {
  name "Initial Task"
  created 2026-11-01 08:00:00
  modified 2026-11-01 08:00:00
  queued 2026-11-01 08:00:00
}
''';
    var remoteTdf = localTdf;

    const bothConfig = WebDavConfig(
      storageMode: StorageMode.both,
      localFilePath: 'tasks.tdf',
      serverUrl: 'https://cloud.example.com/dav/',
      username: 'alice',
      password: 'secret',
      filePath: 'tasks.tdf',
    );
    final settingsRepo = InMemorySettingsRepository(bothConfig);

    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        clockProvider.overrideWithValue(() => currentTime),
        localFileRepositoryProvider.overrideWith(
          (ref) => _InMemorySyncLocalRepository(
            config: bothConfig,
            getTdf: () => localTdf,
            setTdf: (val) => localTdf = val,
          ),
        ),
        webDavRepositoryProvider.overrideWith(
          (ref) => _InMemorySyncWebDavRepository(
            config: bothConfig,
            getTdf: () => remoteTdf,
            setTdf: (val) => remoteTdf = val,
            isOnline: () => true,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final initialBoard = await container.read(taskNotifierProvider.future);
    expect(
      initialBoard.allTasks.map((task) => task.title),
      contains('Initial Task'),
    );

    // External local file edit adds 000002OkD2 while remote edit renames label "work00OkD2" -> "Enterprise"
    localTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 09:30:00
  task 000001OkD2
  task 000002OkD2
}

label work00OkD2 {
  name "Work"
  modified 2026-11-01 08:00:00
}

task 000001OkD2 {
  name "Initial Task"
  created 2026-11-01 08:00:00
  modified 2026-11-01 08:00:00
  queued 2026-11-01 08:00:00
}

task 000002OkD2 {
  name "External Local Task"
  created 2026-11-01 09:30:00
  modified 2026-11-01 09:30:00
  queued 2026-11-01 09:30:00
}
''';
    remoteTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 08:00:00
  task 000001OkD2
}

label work00OkD2 {
  name "Enterprise"
  modified 2026-11-01 09:45:00
}

task 000001OkD2 {
  name "Initial Task"
  created 2026-11-01 08:00:00
  modified 2026-11-01 08:00:00
  queued 2026-11-01 08:00:00
}
''';

    // User saves an in-memory mutation (adding a task) at 10:00 UTC.
    currentTime = DateTime.utc(2026, 11, 1, 10);
    await container
        .read(taskNotifierProvider.notifier)
        .addTask('In-Memory Task', targetTier: TaskTier.someday);

    final mergedBoard = container.read(taskNotifierProvider).requireValue;
    final titles = mergedBoard.allTasks.map((task) => task.title).toList();
    expect(
      titles,
      containsAll(<String>[
        'Initial Task',
        'External Local Task',
        'In-Memory Task',
      ]),
      reason: 'Saving in-memory change must merge external local file and WebDAV entities',
    );
    expect(
      mergedBoard.labels
          .where((label) => label.id == 'work00OkD2')
          .firstOrNull
          ?.name,
      equals('Enterprise'),
      reason:
          'Newer remote label modification must be preserved during save sync',
    );
    expect(
      localTdf,
      equals(remoteTdf),
      reason: 'Local file and WebDAV must converge to identical TDF after two-stage sync',
    );
    expect(
      localTdf,
      contains('tdf 0.5.1'),
      reason: 'Output header must use TDF 0.5.1',
    );
  });

  test('Offline WebDAV save failure preserves local file sync and merges per-entity when connection returns', () async {
    var currentTime = DateTime.utc(2026, 11, 1, 8);
    var isOnline = true;
    var localTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 08:00:00
  task 000001OkD2
  task 000002OkD2
}

label ops000OkD2 {
  name "Ops"
  modified 2026-11-01 08:00:00
}

task 000001OkD2 {
  name "Task One"
  created 2026-11-01 08:00:00
  modified 2026-11-01 08:00:00
  queued 2026-11-01 08:00:00
}

task 000002OkD2 {
  name "Task Two"
  created 2026-11-01 08:00:00
  modified 2026-11-01 08:00:00
  queued 2026-11-01 08:00:00
}
''';
    var remoteTdf = localTdf;

    const bothConfig = WebDavConfig(
      storageMode: StorageMode.both,
      localFilePath: 'tasks.tdf',
      serverUrl: 'https://cloud.example.com/dav/',
      username: 'alice',
      password: 'secret',
      filePath: 'tasks.tdf',
    );
    final settingsRepo = InMemorySettingsRepository(bothConfig);

    ProviderContainer createContainer() {
      return ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepo),
          clockProvider.overrideWithValue(() => currentTime),
          localFileRepositoryProvider.overrideWith(
            (ref) => _InMemorySyncLocalRepository(
              config: bothConfig,
              getTdf: () => localTdf,
              setTdf: (val) => localTdf = val,
            ),
          ),
          webDavRepositoryProvider.overrideWith(
            (ref) => _InMemorySyncWebDavRepository(
              config: bothConfig,
              getTdf: () => remoteTdf,
              setTdf: (val) => remoteTdf = val,
              isOnline: () => isOnline,
            ),
          ),
        ],
      );
    }

    final container1 = createContainer();
    await container1.read(taskNotifierProvider.future);

    // Connection drops; user completes 000001OkD2 and deletes label 'ops000OkD2' locally at 09:00 UTC.
    isOnline = false;
    currentTime = DateTime.utc(2026, 11, 1, 9);
    await container1
        .read(taskNotifierProvider.notifier)
        .completeTask('000001OkD2');
    await container1
        .read(taskNotifierProvider.notifier)
        .deleteLabel('ops000OkD2');

    expect(
      container1.read(syncStateProvider).errorMessage,
      isNotNull,
      reason: 'Offline WebDAV save must surface sync error banner',
    );
    expect(
      localTdf,
      contains('finished 2026-11-01 09:00'),
      reason:
          'Stage 1 local file must still be updated while WebDAV is offline',
    );

    // Meanwhile on WebDAV, another device updates 000002OkD2 at 09:30 UTC.
    remoteTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 08:00:00
  task 000001OkD2
  task 000002OkD2
}

label ops000OkD2 {
  name "Ops"
  modified 2026-11-01 08:00:00
}

task 000001OkD2 {
  name "Task One"
  created 2026-11-01 08:00:00
  modified 2026-11-01 08:00:00
  queued 2026-11-01 08:00:00
}

task 000002OkD2 {
  name "Task Two Updated On Remote"
  created 2026-11-01 08:00:00
  modified 2026-11-01 09:30:00
  queued 2026-11-01 08:00:00
}
''';

    // Simulate app restart before WebDAV reconnects, then reconnect and press Sync.
    container1.dispose();
    isOnline = true;
    currentTime = DateTime.utc(2026, 11, 1, 10);
    final container2 = createContainer();
    addTearDown(container2.dispose);

    final convergedBoard = await container2.read(taskNotifierProvider.future);
    expect(
      convergedBoard.allTasks
          .where((task) => task.id == '000001OkD2')
          .firstOrNull
          ?.isCompleted,
      isTrue,
      reason:
          'Offline local completion of 000001OkD2 must survive WebDAV merge',
    );
    expect(
      convergedBoard.allTasks
          .where((task) => task.id == '000002OkD2')
          .firstOrNull
          ?.title,
      equals('Task Two Updated On Remote'),
      reason: 'Concurrent remote edit of 000002OkD2 must survive WebDAV merge',
    );
    expect(
      convergedBoard.labels
          .where((label) => label.id == 'ops000OkD2')
          .firstOrNull,
      isNull,
      reason: 'Offline label deletion persisted in deleted block and WorkspaceSyncState must delete unmodified remote label',
    );

    final activeWorkspace = await container2.read(
      activeWorkspaceProvider.future,
    );
    final syncStateAfter = await settingsRepo.loadWorkspaceSyncState(
      activeWorkspace.id,
    );
    expect(
      syncStateAfter.deletedLabelTimestamps,
      isEmpty,
      reason: 'deletedLabelTimestamps must be pruned once both Local and WebDAV stages succeed',
    );
  });

  test('Explicitly importing a legacy tdf 0.3.0 document via TaskNotifier.importLegacyTdf migrates IDs via SHA-256 Base62, resets sync baseline per Section 10.1, and syncs tdf 0.5.0 to local and WebDAV storage', () async {
    final currentTime = DateTime.utc(2026, 11, 1, 12);
    const legacyTdf = '''
tdf 0.3.0

label l_work00_OkD2 {
  name "Work"
  modified 2026-11-01 08:00
}

task t_000001_OkD2 {
  name "Legacy First Task"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
  labels l_work00_OkD2
}

task t002 {
  name "Legacy Blocked Task"
  created 2026-11-01 08:30
  queued 2026-11-01 08:30
  blocked t_000001_OkD2
  labels l_work00_OkD2
}
''';
    var localTdf = 'tdf 0.5.0\n';
    var remoteTdf = 'tdf 0.5.0\n';
    var localSaveCount = 0;
    var remoteSaveCount = 0;

    const bothConfig = WebDavConfig(
      storageMode: StorageMode.both,
      localFilePath: 'tasks.tdf',
      serverUrl: 'https://cloud.example.com/dav/',
      username: 'alice',
      password: 'secret',
      filePath: 'tasks.tdf',
    );
    final settingsRepo = InMemorySettingsRepository(bothConfig);

    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        clockProvider.overrideWithValue(() => currentTime),
        localFileRepositoryProvider.overrideWith(
          (ref) => _InMemorySyncLocalRepository(
            config: bothConfig,
            getTdf: () => localTdf,
            setTdf: (val) {
              localSaveCount++;
              localTdf = val;
            },
          ),
        ),
        webDavRepositoryProvider.overrideWith(
          (ref) => _InMemorySyncWebDavRepository(
            config: bothConfig,
            getTdf: () => remoteTdf,
            setTdf: (val) {
              remoteSaveCount++;
              remoteTdf = val;
            },
            isOnline: () => true,
          ),
        ),
      ],
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

    expect(convertedLabelId.length, equals(10));
    expect(convertedFirstTaskId.length, equals(10));
    expect(convertedSecondTaskId.length, equals(10));
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
    expect(localTdf, contains('label $convertedLabelId {'));
    expect(localTdf, contains('task $convertedFirstTaskId {'));
    expect(localTdf, contains('task $convertedSecondTaskId {'));
    expect(localTdf, contains('blocked $convertedFirstTaskId'));
    expect(localTdf, contains('labels $convertedLabelId'));
  });
}
