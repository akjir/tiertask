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
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_board_evaluator.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/models/workspace_sync_state.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/local_file_watch_providers.dart';
import 'package:tiertask/providers/sync_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/services/tdf_service.dart';

class _ControllableWatchLocalRepository extends LocalFileRepository {
  _ControllableWatchLocalRepository({
    required super.config,
    super.baseDirectoryPath,
    required this.watchSupported,
    required this.onWatchListen,
    required this.streamFactory,
  });

  final void Function() onWatchListen;
  final Stream<void> Function() streamFactory;
  final bool watchSupported;

  @override
  bool get canWatchDirectory => watchSupported;

  @override
  Stream<void> watchTdfChanges() {
    if (!canWatchDirectory) {
      return const Stream<void>.empty();
    }
    onWatchListen();
    return streamFactory();
  }
}

class _CountingParseTdfService extends TdfService {
  const _CountingParseTdfService(this.onParse);

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
    bool evaluateTiers = true,
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
      evaluateTiers: evaluateTiers,
    );
  }
}

class _CountingWebDavRepository extends WebDavRepository {
  _CountingWebDavRepository({required super.config, required this.onRequest});

  final void Function() onRequest;
  String remoteContent = 'tdf 0.8.0\n';

  @override
  Future<String> fetchTdf() async {
    onRequest();
    return remoteContent;
  }

  @override
  Future<void> saveTdf(String tdfContent) async {
    onRequest();
    remoteContent = tdfContent;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalFileWatcherNotifier Lifecycle, Scoping, Debounce & Error Isolation', () {
    late Directory tempDir;

    setUp(() async {
      HttpOverrides.global = null;
      tempDir = await Directory.systemTemp.createTemp(
        'tiertask_watch_provider_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('scopes watch target across StorageMode and localWatchEnabled, suppresses cold-start/mode-switch catch-up, fires catch-up only on false->true toggle without AsyncLoading, and ignores unrelated preference edits', () async {
      var watchSubscribeCount = 0;
      var controller = StreamController<void>();
      addTearDown(() => controller.close());

      final settingsRepo = InMemorySettingsRepository(
        const WebDavConfig(
          serverUrl: 'https://cloud.example.com',
          username: 'example-user',
          password: 'example-password',
          storageMode: StorageMode.local,
        ),
      );
      var currentTime = DateTime.utc(2026, 11, 14, 13);
      final loadingTransitions = <bool>[];

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepo),
          localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
          localFileWatchDebounceProvider.overrideWithValue(
            const Duration(milliseconds: 5),
          ),
          clockProvider.overrideWithValue(() => currentTime),
          webDavRepositoryProvider.overrideWith(
            (ref) => _CountingWebDavRepository(
              config:
                  ref.watch(webDavConfigProvider).asData?.value ??
                  const WebDavConfig(),
              onRequest: () {},
            ),
          ),
          localFileRepositoryProvider.overrideWith((ref) {
            final cfg = _watchCurrentConfig(ref);
            return _ControllableWatchLocalRepository(
              config: cfg,
              baseDirectoryPath: tempDir.path,
              watchSupported: true,
              onWatchListen: () => watchSubscribeCount++,
              streamFactory: () => controller.stream,
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        localFileWatcherProvider,
        (_, _) {},
        fireImmediately: true,
      );

      // Cold start: before async workspace/config resolves, target is disabled with null resolvedLocalWatchEnabled.
      expect(container.read(localFileWatchTargetProvider).enabled, isFalse);

      await container.read(taskNotifierProvider.future);
      await container.pump();
      await pumpEventQueue();
      expect(container.read(localFileWatchTargetProvider).enabled, isTrue);
      expect(
        watchSubscribeCount,
        equals(1),
        reason: 'Initial resolution in StorageMode.local with localWatchEnabled=true must subscribe once',
      );

      final notifier = container.read(taskNotifierProvider.notifier);
      await notifier.addTask('Undo Preserved Task', id: 'uPres00001');
      await notifier.completeTask('uPres00001');
      expect(container.read(taskUndoStateProvider).canUndo, isTrue);

      container.listen(taskNotifierProvider, (_, next) {
        loadingTransitions.add(next.isLoading);
      });

      // Unrelated preference edits must NOT rebuild LocalFileWatcherNotifier or resubscribe.
      final configNotifier = container.read(webDavConfigProvider.notifier);
      await configNotifier.updateThemeMode(AppThemeMode.dark);
      await configNotifier.updateThemePalette(AppThemePalette.plumUmber);
      await configNotifier.updateLanguage(AppLanguage.german);
      await configNotifier.updateLocationEnabled(true);
      await configNotifier.updateTimeZoneMode(AppTimeZoneMode.manual);
      await configNotifier.updateDiagnosticsEnabled(true);
      await configNotifier.updateLogLevel(LogLevel.debug);
      await configNotifier.updateLogStorageMode(StorageMode.local);
      await configNotifier.updateDiagnosticsEnabled(false);
      expect(
        watchSubscribeCount,
        equals(1),
        reason: 'Unrelated preference updates must keep existing watch subscription intact',
      );

      // Switching to StorageMode.webdav disables watching; switching to StorageMode.both re-subscribes without false catch-up.
      controller = StreamController<void>();
      addTearDown(() => controller.close());
      await configNotifier.updateStorageMode(StorageMode.webdav);
      await container.pump();
      expect(container.read(localFileWatchTargetProvider).enabled, isFalse);
      await configNotifier.updateStorageMode(StorageMode.both);
      await container.read(taskNotifierProvider.future);
      await container.pump();
      expect(container.read(localFileWatchTargetProvider).enabled, isTrue);
      expect(watchSubscribeCount, equals(2));

      // Switch back to StorageMode.local, add undoable action, then toggle localWatchEnabled: true -> false -> true.
      controller = StreamController<void>();
      addTearDown(() => controller.close());
      await configNotifier.updateStorageMode(StorageMode.local);
      await container.read(taskNotifierProvider.future);
      await container.pump();
      await notifier.addTask('Toggle Undo Task', id: 'uTogl00001');
      await notifier.completeTask('uTogl00001');
      loadingTransitions.clear();

      await configNotifier.updateLocalWatchEnabled(false);
      await container.pump();
      expect(container.read(localFileWatchTargetProvider).enabled, isFalse);
      expect(
        loadingTransitions,
        isEmpty,
        reason: 'Toggling localWatchEnabled off must never rebuild TaskNotifier or flash AsyncLoading',
      );
      expect(
        container.read(taskUndoStateProvider).canUndo,
        isTrue,
        reason: 'Toggling localWatchEnabled must preserve undo stack',
      );

      // Save an external batch edit while watching is disabled.
      final localFile = File('${tempDir.path}/tasks.tdf');
      final disabledRaw = await localFile.readAsString();
      await localFile.writeAsString(
        '$disabledRaw\n'
        'task extWhileOf {\n'
        '    name "Saved While Watch Disabled"\n'
        '    created 2026-11-14 13:05:00\n'
        '    modified 2026-11-14 13:05:00\n'
        '}\n',
        flush: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 12));
      await pumpEventQueue();
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('extWhileOf'),
        isNull,
        reason: 'External edit must not auto-merge while localWatchEnabled is false',
      );

      // Re-enabling localWatchEnabled (false -> true) in the same workspace triggers catch-up merge without AsyncLoading!
      controller = StreamController<void>();
      addTearDown(() => controller.close());
      currentTime = DateTime.utc(2026, 11, 14, 13, 6);
      await configNotifier.updateLocalWatchEnabled(true);
      await container.pump();
      await _waitForCondition(
        container,
        () =>
            !container.read(syncStateProvider).isSyncing &&
            container
                    .read(taskNotifierProvider)
                    .asData
                    ?.value
                    .findTask('extWhileOf') !=
                null,
        reason:
            'Re-enabling localWatchEnabled must merge extWhileOf via catch-up',
      );
      expect(
        loadingTransitions.where((isLoading) => isLoading),
        isEmpty,
        reason: 'Re-enabling localWatchEnabled must merge in place without AsyncLoading',
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('extWhileOf')
            ?.title,
        equals('Saved While Watch Disabled'),
      );
      expect(
        container.read(taskUndoStateProvider).canUndo,
        isTrue,
        reason: 'Catch-up merge of unrelated external task must preserve undo stack',
      );
    });

    test('suppresses watching when canWatchDirectory is false without lastSyncedAt rebind loops, handles all AppLifecycleState values, and suppresses repeated syncs during open TdfSyncOutcomeException conflicts', () async {
      var unsupportedListenCount = 0;
      final unsupportedSettings = InMemorySettingsRepository();
      final unsupportedContainer = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(unsupportedSettings),
          localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
          localFileRepositoryProvider.overrideWith((ref) {
            final cfg =
                ref.watch(webDavConfigProvider).asData?.value ??
                const WebDavConfig();
            return _ControllableWatchLocalRepository(
              config: cfg,
              baseDirectoryPath: tempDir.path,
              watchSupported: false,
              onWatchListen: () => unsupportedListenCount++,
              streamFactory: () => const Stream<void>.empty(),
            );
          }),
        ],
      );
      addTearDown(unsupportedContainer.dispose);
      unsupportedContainer.listen(
        localFileWatcherProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await unsupportedContainer.read(taskNotifierProvider.future);
      await unsupportedContainer
          .read(taskNotifierProvider.notifier)
          .addTask('No Rebind Loop');
      expect(
        unsupportedContainer.read(localFileWatchTargetProvider).enabled,
        isFalse,
      );
      expect(unsupportedListenCount, equals(0));

      // Now test AppLifecycleState transitions and open conflict suppression.
      var webDavRequests = 0;
      var watchController = StreamController<void>();
      addTearDown(() => watchController.close());
      final conflictSettings = InMemorySettingsRepository(
        const WebDavConfig(
          serverUrl: 'https://cloud.example.com',
          username: 'example-user',
          password: 'example-password',
          filePath: 'conflict.tdf',
          localFilePath: 'conflict.tdf',
          storageMode: StorageMode.both,
        ),
      );
      var currentTime = DateTime.utc(2026, 11, 14, 14);
      final webDavRepo = _CountingWebDavRepository(
        config: const WebDavConfig(
          serverUrl: 'https://cloud.example.com',
          username: 'example-user',
          password: 'example-password',
          filePath: 'conflict.tdf',
          localFilePath: 'conflict.tdf',
          storageMode: StorageMode.both,
        ),
        onRequest: () => webDavRequests++,
      );

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(conflictSettings),
          localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
          localFileWatchDebounceProvider.overrideWithValue(
            const Duration(milliseconds: 5),
          ),
          clockProvider.overrideWithValue(() => currentTime),
          webDavRepositoryProvider.overrideWithValue(webDavRepo),
          localFileRepositoryProvider.overrideWith((ref) {
            final cfg = _watchCurrentConfig(ref);
            return _ControllableWatchLocalRepository(
              config: cfg,
              baseDirectoryPath: tempDir.path,
              watchSupported: true,
              onWatchListen: () {},
              streamFactory: () => watchController.stream,
            );
          }),
        ],
      );
      addTearDown(container.dispose);
      container.listen(
        localFileWatcherProvider,
        (_, _) {},
        fireImmediately: true,
      );

      await container.read(taskNotifierProvider.future);
      await container.pump();
      final notifier = container.read(taskNotifierProvider.notifier);
      await notifier.addTask('Conflict Base Task', id: 'cflBase001');

      // Desktop inactive/hidden/paused/detached must NOT close the stream or trigger catch-up requests.
      final localFile = File('${tempDir.path}/conflict.tdf');
      final baselineRaw = await localFile.readAsString();
      await localFile.writeAsString(
        '$baselineRaw\n'
        'task bgSaved001 {\n'
        '    name "Saved While Android Frozen"\n'
        '    created 2026-11-14 14:01:00\n'
        '    modified 2026-11-14 14:01:00\n'
        '}\n',
        flush: true,
      );
      final requestsBeforeInactive = webDavRequests;
      for (final nonResumeState in <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ]) {
        TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
          nonResumeState,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await pumpEventQueue();
      expect(
        webDavRequests,
        equals(requestsBeforeInactive),
        reason: 'Non-resumed lifecycle states must not trigger catch-up sync',
      );

      // AppLifecycleState.resumed triggers debounced catch-up and merges bgSaved001!
      currentTime = DateTime.utc(2026, 11, 14, 14, 2);
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await _waitForCondition(
        container,
        () =>
            !container.read(syncStateProvider).isSyncing &&
            container
                    .read(taskNotifierProvider)
                    .asData
                    ?.value
                    .findTask('bgSaved001') !=
                null,
        reason:
            'AppLifecycleState.resumed must trigger debounced catch-up merge',
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('bgSaved001')
            ?.title,
        equals('Saved While Android Frozen'),
      );

      // Trigger a TdfSyncOutcomeException (deletionConflict): edit cflBase001 on remote while deleting it externally on local disk.
      final remoteConflictedBoard = container
          .read(taskNotifierProvider)
          .requireValue
          .updateTask(
            'cflBase001',
            title: 'Remote Conflicting Edit',
            currentDate: DateTime.utc(2026, 11, 14, 14, 3),
            localEvaluationTime: DateTime(2026, 11, 14, 14, 3),
          );
      webDavRepo.remoteContent = container
          .read(tdfServiceProvider)
          .serialize(remoteConflictedBoard);
      const localDeletedConflict =
          'tdf 0.8.0\n\n'
          'deleted {\n'
          '    generation 0\n'
          '    task cflBase001 2026-11-14 14:04:00\n'
          '}\n\n'
          'queue {\n'
          '    modified 2026-11-14 14:04:00\n'
          '}\n\n'
          'task bgSaved001 {\n'
          '    name "Saved While Android Frozen"\n'
          '    created 2026-11-14 14:01:00\n'
          '    modified 2026-11-14 14:01:00\n'
          '}\n';
      await localFile.writeAsString(localDeletedConflict, flush: true);
      currentTime = DateTime.utc(2026, 11, 14, 14, 5);
      watchController.add(null);
      await _waitForCondition(
        container,
        () => container.read(syncStateProvider).hasOpenConflict,
        reason: 'Watch event must surface deletionConflict banner',
      );

      final enL10n = lookupAppLocalizations(const Locale('en'));
      expect(container.read(syncStateProvider).hasOpenConflict, isTrue);
      expect(
        container.read(syncStateProvider).errorMessage,
        equals(enL10n.syncConflictDeletionBanner),
        reason: 'Watch DeletionConflict must set localized syncConflictDeletionBanner instead of raw TdfSyncOutcomeException string',
      );

      // Repeated AppLifecycleState.resumed events while conflict is open and digest is unchanged perform 0 WebDAV requests!
      final requestsAfterConflict = webDavRequests;
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await pumpEventQueue();
      expect(
        webDavRequests,
        equals(requestsAfterConflict),
        reason: 'Repeated resumed events with unchanged _conflictWatchDigest must perform zero WebDAV requests',
      );
      expect(container.read(syncStateProvider).hasOpenConflict, isTrue);

      // Resolve deletionConflict via explicit undelete resolution, verifying conflict clears.
      currentTime = DateTime.utc(2026, 11, 14, 14, 6);
      await notifier.pushToRemote(
        remoteConflictedBoard,
        taskConflictResolutions: const <String, TdfDeletionResolution>{
          'cflBase001': TdfDeletionResolution.undelete,
        },
      );
      expect(container.read(syncStateProvider).hasOpenConflict, isFalse);

      // Also test real recoveryRequired conflict suppression (unacknowledged deleted.generation > 0 with unbaselined in-memory task) and recovery when external file changes to a clean digest.
      final convergedRaw = await localFile.readAsString();
      await conflictSettings.saveWorkspaceSyncState(
        'tasks',
        (await conflictSettings.loadWorkspaceSyncState('tasks'))
            .copyWith(clearLastSyncedLocalTdf: true),
      );
      await localFile.writeAsString(
        'tdf 0.8.0\n\n'
        'deleted {\n'
        '    generation 5\n'
        '}\n',
        flush: true,
      );
      currentTime = DateTime.utc(2026, 11, 14, 14, 7);
      watchController.add(null);
      await _waitForCondition(
        container,
        () => container.read(syncStateProvider).hasOpenConflict,
        reason: 'Watch event must surface recoveryRequired conflict banner',
      );
      expect(container.read(syncStateProvider).hasOpenConflict, isTrue);
      expect(
        container.read(syncStateProvider).errorMessage,
        equals(enL10n.syncConflictRecoveryBanner),
        reason: 'Watch RecoveryRequired must set localized syncConflictRecoveryBanner instead of raw TdfSyncOutcomeException string',
      );

      final requestsBeforeRecoveryResume = webDavRequests;
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await pumpEventQueue();
      expect(
        webDavRequests,
        equals(requestsBeforeRecoveryResume),
        reason: 'Open recoveryRequired conflict must suppress resumed background syncs while local digest is unchanged',
      );

      // Saving a new clean external file digest resumes reconciliation and clears hasOpenConflict!
      await localFile.writeAsString(
        '$convergedRaw\n'
        'task postCfl001 {\n'
        '    name "Resolved Conflict Task"\n'
        '    created 2026-11-14 14:07:30\n'
        '    modified 2026-11-14 14:07:30\n'
        '}\n',
        flush: true,
      );
      currentTime = DateTime.utc(2026, 11, 14, 14, 8);
      watchController.add(null);
      await _waitForCondition(
        container,
        () =>
            !container.read(syncStateProvider).isSyncing &&
            !container.read(syncStateProvider).hasOpenConflict &&
            container
                    .read(taskNotifierProvider)
                    .asData
                    ?.value
                    .findTask('postCfl001') !=
                null,
        reason: 'New clean external digest must clear conflict and merge postCfl001',
      );

      expect(container.read(syncStateProvider).hasOpenConflict, isFalse);
      expect(container.read(syncStateProvider).errorMessage, isNull);
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('postCfl001')
            ?.title,
        equals('Resolved Conflict Task'),
      );
    });

    test('coalesces 5 rapid writes into 1 parse, skips self-writes and 0-byte files, isolates malformed/unsupported TDF without repeat parses, recovers from startup AsyncError, and rebinds missing parent directory after first save', () async {
      if (!FileSystemEntity.isWatchSupported) {
        return;
      }

      // 1. Missing parent directory at startup -> created on first addTask save -> rebinds via syncStateProvider.lastSyncedAt and catches subsequent external edit!
      final nestedMissingDir = Directory('${tempDir.path}/nested/board_dir');
      var parseCount = 0;
      var currentTime = DateTime.utc(2026, 11, 14, 15);

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const WebDavConfig(
                localFilePath: 'live.tdf',
                storageMode: StorageMode.local,
              ),
            ),
          ),
          localStorageDirectoryPathProvider.overrideWithValue(
            nestedMissingDir.path,
          ),
          localFileWatchDebounceProvider.overrideWithValue(
            const Duration(milliseconds: 20),
          ),
          clockProvider.overrideWithValue(() => currentTime),
          tdfServiceProvider.overrideWithValue(
            _CountingParseTdfService(() => parseCount++),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(
        localFileWatcherProvider,
        (_, _) {},
        fireImmediately: true,
      );

      await container.read(taskNotifierProvider.future);
      expect(nestedMissingDir.existsSync(), isFalse);

      // First addTask creates nestedMissingDir and writes live.tdf; watcher rebinds via lastSyncedAt without self-triggering extra parses!
      final notifier = container.read(taskNotifierProvider.notifier);
      currentTime = DateTime.utc(2026, 11, 14, 15, 1);
      await notifier.addTask('Created Dir Task', id: 'dirCreate1');
      expect(nestedMissingDir.existsSync(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 45));
      final parsesAfterSelfWrite = parseCount;
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(
        parseCount,
        equals(parsesAfterSelfWrite),
        reason: 'Self-write must match localSourceDigest and perform zero extra TDF parses',
      );

      final liveFile = File('${nestedMissingDir.path}/live.tdf');
      final baseTdf = await liveFile.readAsString();

      // 2. 5 rapid external writes within debounce window coalesce into 1 reconciliation pass (<= 2 parses: local + baseline).
      parseCount = 0;
      for (var i = 1; i <= 5; i++) {
        liveFile.writeAsStringSync(
          '$baseTdf\n'
          'task burst00001 {\n'
          '    name "Burst Iteration $i"\n'
          '    created 2026-11-14 15:02:00\n'
          '    modified 2026-11-14 15:02:0$i\n'
          '}\n',
          flush: true,
        );
      }
      await _waitForCondition(
        container,
        () =>
            !container.read(syncStateProvider).isSyncing &&
            container
                    .read(taskNotifierProvider)
                    .asData
                    ?.value
                    .findTask('burst00001')
                    ?.title ==
                'Burst Iteration 5',
        reason: '5 burst writes must coalesce into Burst Iteration 5',
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('burst00001')
            ?.title,
        equals('Burst Iteration 5'),
      );
      expect(
        parseCount,
        lessThanOrEqualTo(2),
        reason: '5 burst writes must coalesce into a single synchronize pass (1 local parse + 1 baseline parse)',
      );

      // 3. 0-byte truncated external file aborts without clobbering memory or disk.
      liveFile.writeAsStringSync('', flush: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('burst00001')
            ?.title,
        equals('Burst Iteration 5'),
      );
      expect(
        liveFile.readAsStringSync(),
        isEmpty,
        reason: '0-byte external truncation must not be overwritten',
      );

      // 4. Malformed TDF (unclosed brace, control char, unsupported version) preserves board & disk and suppresses duplicate parses via _lastFailedWatchDigest.
      for (final badPayload in <String>[
        'tdf 0.8.0\n\ntask broken0001 {\n  name "Unclosed"\n',
        'tdf 0.8.0\n\ntask badCtrl001 {\n  name "Bad\x07Char"\n  created 2026-11-14 15:00:00\n  modified 2026-11-14 15:00:00\n}\n',
        'tdf 9.9.9\n',
      ]) {
        final previousError = container.read(syncStateProvider).errorMessage;
        liveFile.writeAsStringSync(badPayload, flush: true);
        await _waitForCondition(
          container,
          () {
            final nextError = container.read(syncStateProvider).errorMessage;
            return nextError != null && nextError != previousError;
          },
          reason: 'Malformed or unsupported external TDF must surface updated sync error',
        );
        expect(container.read(syncStateProvider).errorMessage, isNotNull);
        expect(
          container
              .read(taskNotifierProvider)
              .requireValue
              .findTask('burst00001'),
          isNotNull,
          reason: 'Malformed or unsupported external TDF must preserve existing in-memory board',
        );
        expect(
          liveFile.readAsStringSync(),
          equals(badPayload),
          reason: 'Malformed or unsupported external TDF must never be overwritten on disk',
        );

        final parsesAfterFirstBad = parseCount;
        expect(await notifier.reconcileExternalLocalChanges(), isFalse);
        expect(
          parseCount,
          equals(parsesAfterFirstBad),
          reason: '_lastFailedWatchDigest must suppress duplicate parses of identical broken digest',
        );
      }

      // Repairing the external file recovers, clears error, and resets _lastFailedWatchDigest.
      liveFile.writeAsStringSync(
        '$baseTdf\n'
        'task repaired01 {\n'
        '    name "Repaired External Task"\n'
        '    created 2026-11-14 15:05:00\n'
        '    modified 2026-11-14 15:05:00\n'
        '}\n',
        flush: true,
      );
      await _waitForCondition(
        container,
        () =>
            !container.read(syncStateProvider).isSyncing &&
            container.read(syncStateProvider).errorMessage == null &&
            container
                    .read(taskNotifierProvider)
                    .asData
                    ?.value
                    .findTask('repaired01') !=
                null,
        reason: 'Repairing external file must clear error and merge repaired01',
      );
      expect(container.read(syncStateProvider).errorMessage, isNull);
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('repaired01')
            ?.title,
        equals('Repaired External Task'),
      );

      // 5. Startup AsyncError recovery when corrupted startup file is repaired externally.
      final brokenStartupDir = Directory('${tempDir.path}/broken_startup')
        ..createSync(recursive: true);
      final startupFile = File('${brokenStartupDir.path}/startup.tdf')
        ..writeAsStringSync('tdf 0.8.0\n\ntask brokenStart {\n', flush: true);

      final errorContainer = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const WebDavConfig(
                localFilePath: 'startup.tdf',
                storageMode: StorageMode.local,
              ),
            ),
          ),
          localStorageDirectoryPathProvider.overrideWithValue(
            brokenStartupDir.path,
          ),
          localFileWatchDebounceProvider.overrideWithValue(
            const Duration(milliseconds: 15),
          ),
          clockProvider.overrideWithValue(() => currentTime),
        ],
      );
      addTearDown(errorContainer.dispose);
      errorContainer.listen(
        localFileWatcherProvider,
        (_, _) {},
        fireImmediately: true,
      );

      await expectLater(
        () => errorContainer.read(taskNotifierProvider.future),
        throwsA(anything),
      );
      await errorContainer.pump();
      expect(errorContainer.read(taskNotifierProvider).hasError, isTrue);

      startupFile.writeAsStringSync(
        'tdf 0.8.0\n\n'
        'task fixedStart {\n'
        '    name "Recovered Startup Board"\n'
        '    created 2026-11-14 15:06:00\n'
        '    modified 2026-11-14 15:06:00\n'
        '}\n',
        flush: true,
      );
      await _waitForCondition(
        errorContainer,
        () => errorContainer.read(taskNotifierProvider).hasValue,
        reason: 'Repairing corrupted startup file must recover taskNotifierProvider',
      );
      expect(errorContainer.read(taskNotifierProvider).hasValue, isTrue);
      expect(
        errorContainer
            .read(taskNotifierProvider)
            .requireValue
            .findTask('fixedStart')
            ?.title,
        equals('Recovered Startup Board'),
      );
    });

    test('real Directory.watch self-write and resumed after Stage 2 deletionConflict preserve _conflictWatchDigest and reconcile the next external file edit immediately', () async {
      if (!FileSystemEntity.isWatchSupported) {
        return;
      }
      var currentTime = DateTime.utc(2026, 11, 14, 16);
      const initialSharedTdf =
          'tdf 0.8.0\n\n'
          'queue {\n'
          '    modified 2026-11-14 16:00:00\n'
          '    task stage2Cf01\n'
          '}\n\n'
          'task stage2Cf01 {\n'
          '    name "Shared Baseline"\n'
          '    created 2026-11-14 16:00:00\n'
          '    modified 2026-11-14 16:00:00\n'
          '}\n';
      var remoteContent = initialSharedTdf;
      var remoteEtag = '"s2-v1"';
      var webDavRequests = 0;

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        webDavRequests++;
        if (request.method == 'GET') {
          if (request.headers.value(HttpHeaders.ifNoneMatchHeader) ==
              remoteEtag) {
            request.response
              ..statusCode = HttpStatus.notModified
              ..headers.set(HttpHeaders.etagHeader, remoteEtag);
            await request.response.close();
            return;
          }
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.set(HttpHeaders.etagHeader, remoteEtag)
            ..write(remoteContent);
          await request.response.close();
          return;
        }
        if (request.method == 'PUT') {
          remoteContent = await const SystemEncoding().decoder
              .bind(request)
              .join();
          remoteEtag = '"s2-v$webDavRequests"';
          request.response
            ..statusCode = HttpStatus.noContent
            ..headers.set(HttpHeaders.etagHeader, remoteEtag);
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
      });

      final watchedDir = Directory('${tempDir.path}/real_stage2_conflict')
        ..createSync(recursive: true);
      final localFile = File('${watchedDir.path}/tasks.tdf')
        ..writeAsStringSync(initialSharedTdf, flush: true);

      final settingsRepo = InMemorySettingsRepository(
        WebDavConfig(
          serverUrl: 'http://127.0.0.1:${server.port}',
          username: 'example-user',
          password: 'example-password',
          storageMode: StorageMode.both,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepo),
          localStorageDirectoryPathProvider.overrideWithValue(watchedDir.path),
          localFileWatchDebounceProvider.overrideWithValue(
            const Duration(milliseconds: 15),
          ),
          clockProvider.overrideWithValue(() => currentTime),
        ],
      );
      addTearDown(container.dispose);
      container.listen(
        localFileWatcherProvider,
        (_, _) {},
        fireImmediately: true,
      );

      await container.read(taskNotifierProvider.future);
      await container.pump();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Remote modifies stage2Cf01 while external local save deletes stage2Cf01 -> Stage 1 succeeds, Stage 2 throws deletionConflict!
      remoteContent =
          'tdf 0.8.0\n\n'
          'queue {\n'
          '    modified 2026-11-14 16:01:00\n'
          '    task stage2Cf01\n'
          '}\n\n'
          'task stage2Cf01 {\n'
          '    name "Remote Concurrent Edit"\n'
          '    created 2026-11-14 16:00:00\n'
          '    modified 2026-11-14 16:01:00\n'
          '}\n';
      remoteEtag = '"s2-v99"';

      currentTime = DateTime.utc(2026, 11, 14, 16, 2);
      await localFile.writeAsString(
        'tdf 0.8.0\n\n'
        'deleted {\n'
        '    generation 0\n'
        '    task stage2Cf01 2026-11-14 16:02:00\n'
        '}\n\n'
        'queue {\n'
        '    modified 2026-11-14 16:02:00\n'
        '}\n',
        flush: true,
      );

      // Wait for Stage 2 conflict to surface and for Stage 1's atomic self-write watch event to settle cleanly.
      await _waitForCondition(
        container,
        () => container.read(syncStateProvider).hasOpenConflict,
        reason: 'Stage 2 deletionConflict must open conflict state',
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(container.read(syncStateProvider).hasOpenConflict, isTrue);

      final requestsAfterStage2Conflict = webDavRequests;
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await pumpEventQueue();
      expect(
        webDavRequests,
        equals(requestsAfterStage2Conflict),
        reason: 'Self-write and resumed checks on unchanged Stage 1 digest must perform zero WebDAV requests',
      );
      expect(container.read(syncStateProvider).hasOpenConflict, isTrue);

      // Now user saves a NEW external .tdf file (D2 != D1) restoring stage2Cf01 + adding extAftCf01!
      currentTime = DateTime.utc(2026, 11, 14, 16, 3);
      await localFile.writeAsString(
        'tdf 0.8.0\n\n'
        'deleted {\n'
        '    generation 1\n'
        '}\n\n'
        'queue {\n'
        '    modified 2026-11-14 16:03:00\n'
        '    task stage2Cf01\n'
        '    task extAftCf01\n'
        '}\n\n'
        'task stage2Cf01 {\n'
        '    name "Externally Resolved Conflict"\n'
        '    created 2026-11-14 16:00:00\n'
        '    modified 2026-11-14 16:03:00\n'
        '}\n\n'
        'task extAftCf01 {\n'
        '    name "Saved After Open Conflict"\n'
        '    created 2026-11-14 16:03:00\n'
        '    modified 2026-11-14 16:03:00\n'
        '}\n',
        flush: true,
      );
      await _waitForCondition(
        container,
        () =>
            !container.read(syncStateProvider).isSyncing &&
            !container.read(syncStateProvider).hasOpenConflict &&
            container
                    .read(taskNotifierProvider)
                    .asData
                    ?.value
                    .findTask('extAftCf01') !=
                null,
        reason: 'New external digest after Stage 2 conflict must reconcile and clear conflict',
      );

      expect(
        container.read(syncStateProvider).hasOpenConflict,
        isFalse,
        reason: 'Saving a new external file digest after a Stage 2 conflict must reconcile immediately instead of being swallowed by _conflictWatchDigest == null',
      );
      final resolvedBoard = container.read(taskNotifierProvider).requireValue;
      expect(
        resolvedBoard.findTask('extAftCf01')?.title,
        equals('Saved After Open Conflict'),
      );
      expect(
        resolvedBoard.findTask('stage2Cf01')?.title,
        equals('Externally Resolved Conflict'),
      );
    });

    test('aborts in-flight external reconcile when StorageMode or localFilePath changes during loadWorkspaceSyncState await, and rebinds missing directory on offline first save in StorageMode.both', () async {
      if (!FileSystemEntity.isWatchSupported) {
        return;
      }
      var currentTime = DateTime.utc(2026, 11, 14, 17);
      final staleDir = Directory('${tempDir.path}/stale_guard')
        ..createSync(recursive: true);
      File('${staleDir.path}/tasks.tdf').writeAsStringSync(
        'tdf 0.8.0\n\n'
        'task initStal01 {\n'
        '    name "Initial Task"\n'
        '    created 2026-11-14 17:00:00\n'
        '    modified 2026-11-14 17:00:00\n'
        '}\n',
        flush: true,
      );

      Completer<void>? syncStateLoadGate;
      Completer<void>? syncStateLoadEntered;
      final gatedSettings = _SyncStateGateSettingsRepository(
        const WebDavConfig(
          serverUrl: 'https://cloud.example.com',
          username: 'example-user',
          password: 'example-password',
          storageMode: StorageMode.local,
        ),
        onLoadSyncState: () async {
          if (syncStateLoadEntered case final entered?
              when !entered.isCompleted) {
            entered.complete();
          }
          if (syncStateLoadGate case final gate?) {
            await gate.future;
          }
        },
      );

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(gatedSettings),
          localStorageDirectoryPathProvider.overrideWithValue(staleDir.path),
          clockProvider.overrideWithValue(() => currentTime),
          webDavRepositoryProvider.overrideWith(
            (ref) => _CountingWebDavRepository(
              config:
                  ref.watch(webDavConfigProvider).asData?.value ??
                  const WebDavConfig(),
              onRequest: () {},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(taskNotifierProvider.future);

      File('${staleDir.path}/tasks.tdf').writeAsStringSync(
        'tdf 0.8.0\n\n'
        'task staleExt01 {\n'
        '    name "Should Abort On Mode Switch"\n'
        '    created 2026-11-14 17:01:00\n'
        '    modified 2026-11-14 17:01:00\n'
        '}\n',
        flush: true,
      );

      syncStateLoadGate = Completer<void>();
      syncStateLoadEntered = Completer<void>();
      final notifier = container.read(taskNotifierProvider.notifier);
      final reconcileFuture = notifier.reconcileExternalLocalChanges();
      await syncStateLoadEntered.future.timeout(const Duration(seconds: 2));

      // Switch StorageMode to webdav (localWatchEnabled remains true in same workspace!) while loadWorkspaceSyncState is suspended!
      await container
          .read(webDavConfigProvider.notifier)
          .updateConfig(
            const WebDavConfig(
              serverUrl: 'https://cloud.example.com',
              username: 'example-user',
              password: 'example-password',
              storageMode: StorageMode.webdav,
            ),
          );
      syncStateLoadGate.complete();
      syncStateLoadGate = null;
      syncStateLoadEntered = null;

      final didReconcile = await reconcileFuture;
      expect(
        didReconcile,
        isFalse,
        reason: 'Switching StorageMode to webdav during pre-check await must abort stale local reconcile',
      );
      await container.read(taskNotifierProvider.future);
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('staleExt01'),
        isNull,
        reason: 'Aborted stale local reconcile must never merge local-only edits into WebDAV-only board',
      );

      // Part 2: Offline first-save missing-directory rebind in StorageMode.both!
      final offlineMissingDirPath = '${tempDir.path}/offline_missing_both';
      final offlineSettings = InMemorySettingsRepository(
        const WebDavConfig(
          serverUrl: 'http://127.0.0.1:1',
          username: 'example-user',
          password: 'example-password',
          storageMode: StorageMode.both,
        ),
      );
      final offlineContainer = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(offlineSettings),
          localStorageDirectoryPathProvider.overrideWithValue(
            offlineMissingDirPath,
          ),
          localFileWatchDebounceProvider.overrideWithValue(
            const Duration(milliseconds: 15),
          ),
          clockProvider.overrideWithValue(() => currentTime),
        ],
      );
      addTearDown(offlineContainer.dispose);
      offlineContainer.listen(
        localFileWatcherProvider,
        (_, _) {},
        fireImmediately: true,
      );

      await expectLater(
        () => offlineContainer.read(taskNotifierProvider.future),
        throwsA(anything),
      );
      await offlineContainer.pump();
      expect(Directory(offlineMissingDirPath).existsSync(), isFalse);

      // First addTask creates offlineMissingDirPath in Stage 1, then fails Stage 2 offline so lastSyncedAt stays null!
      currentTime = DateTime.utc(2026, 11, 14, 17, 5);
      await offlineContainer
          .read(taskNotifierProvider.notifier)
          .addTask('Created Offline Dir', id: 'offDir0001');
      expect(Directory(offlineMissingDirPath).existsSync(), isTrue);
      expect(offlineContainer.read(syncStateProvider).lastSyncedAt, isNull);
      await offlineContainer.pump();
      await Future<void>.delayed(const Duration(milliseconds: 25));

      // External edit in newly created directory must be detected by rebound Directory.watch even while WebDAV remains offline!
      currentTime = DateTime.utc(2026, 11, 14, 17, 6);
      await File('$offlineMissingDirPath/tasks.tdf').writeAsString(
        'tdf 0.8.0\n\n'
        'queue {\n'
        '    modified 2026-11-14 17:06:00\n'
        '    task offDir0001\n'
        '    task offExt0002\n'
        '}\n\n'
        'task offDir0001 {\n'
        '    name "Created Offline Dir"\n'
        '    created 2026-11-14 17:05:00\n'
        '    modified 2026-11-14 17:05:00\n'
        '}\n\n'
        'task offExt0002 {\n'
        '    name "Detected After Offline Dir Creation"\n'
        '    created 2026-11-14 17:06:00\n'
        '    modified 2026-11-14 17:06:00\n'
        '}\n',
        flush: true,
      );
      await _waitForCondition(
        offlineContainer,
        () =>
            !offlineContainer.read(syncStateProvider).isSyncing &&
            offlineContainer
                    .read(taskNotifierProvider)
                    .asData
                    ?.value
                    .findTask('offExt0002') !=
                null,
        reason: 'Rebound Directory.watch must detect offExt0002 after offline directory creation',
      );
      expect(
        offlineContainer
            .read(taskNotifierProvider)
            .requireValue
            .findTask('offExt0002')
            ?.title,
        equals('Detected After Offline Dir Creation'),
        reason: 'LocalFileWatcherNotifier must rebind missing directory when Stage 1 creates it even if Stage 2 fails offline and lastSyncedAt stays null',
      );
    });

    test('Directory.watch reconciles TDF 0.8.0 fields across Conflict -> Self-Write/Resume -> New External Input cycles and preserves/prunes undo stack accurately', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'tiertask_watch_v080_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final tdfFile = File('${tempDir.path}/tasks.tdf');

      var currentTime = DateTime.utc(2026, 11, 11, 12);
      await tdfFile.writeAsString(
        'tdf 0.8.0\n\n'
        'queue {\n'
        '    modified 2026-11-11 12:00:00\n'
        '    task blockerW01\n'
        '    task depWatch02\n'
        '    task suspWatch3\n'
        '    task conflict04\n'
        '    task otherHist5\n'
        '}\n\n'
        'label wlbl000001 {\n'
        '    name     "Docs"\n'
        '    link     "Spec" "https://docs.example.com"\n'
        '    modified 2026-11-11 12:00:00\n'
        '}\n\n'
        'task blockerW01 {\n'
        '    name     "Watch Blocker"\n'
        '    created  2026-11-11 11:00:00\n'
        '    modified 2026-11-11 12:00:00\n'
        '}\n\n'
        'task depWatch02 {\n'
        '    name     "Watch Dependent"\n'
        '    created  2026-11-11 11:00:00\n'
        '    modified 2026-11-11 12:00:00\n'
        '    due      2026-11-12 09:00:00 passive "Soft target"\n'
        '    labels   wlbl000001\n'
        '    blocked  blockerW01\n'
        '}\n\n'
        'task suspWatch3 {\n'
        '    name      "Expiring Watch Task"\n'
        '    created   2026-11-11 11:00:00\n'
        '    modified  2026-11-11 12:00:00\n'
        '    suspended 2026-11-11 12:02:00 "Hold 2 min"\n'
        '}\n\n'
        'task conflict04 {\n'
        '    name     "Conflict Target"\n'
        '    created  2026-11-11 11:00:00\n'
        '    modified 2026-11-11 12:00:00\n'
        '    history  2026-11-11 11:30:00 "Created entry"\n'
        '}\n\n'
        'task otherHist5 {\n'
        '    name     "Other History Task"\n'
        '    created  2026-11-11 11:00:00\n'
        '    modified 2026-11-11 12:00:00\n'
        '}\n',
        flush: true,
      );

      final settings = InMemorySettingsRepository();
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
          localFileWatchDebounceProvider.overrideWithValue(
            const Duration(milliseconds: 15),
          ),
          clockProvider.overrideWithValue(() => currentTime),
        ],
      );
      addTearDown(container.dispose);
      container.listen(
        localFileWatcherProvider,
        (_, _) {},
        fireImmediately: true,
      );

      final initialBoard = await container.read(taskNotifierProvider.future);
      expect(
        initialBoard.findLabel('wlbl000001')?.links.single.title,
        equals('Spec'),
      );
      expect(initialBoard.findTask('depWatch02')?.isDuePassive, isTrue);
      expect(
        initialBoard.findTask('depWatch02')?.dueNote,
        equals('Soft target'),
      );
      await container.pump();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // 1. Complete blockerW01 at 12:00:30 (captures stripped depWatch02 dependency in undo stack):
      currentTime = DateTime.utc(2026, 11, 11, 12, 0, 30);
      final notifier = container.read(taskNotifierProvider.notifier);
      await notifier.completeTask('blockerW01');
      expect(container.read(taskUndoStateProvider).canUndo, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 35));

      // 2. Advance clock to 12:03:00 (so suspWatch3's 12:02:00 suspended is expired!) and write an external
      // update adding history to otherHist5: real Directory.watch cleans suspWatch3 AND keeps blockerW01 undo intact!
      currentTime = DateTime.utc(2026, 11, 11, 12, 3);
      final currentDisk = await tdfFile.readAsString();
      await tdfFile.writeAsString(
        currentDisk.replaceFirst(
          'task otherHist5 {\n    name     "Other History Task"\n    created  2026-11-11 11:00\n    modified 2026-11-11 12:00\n}',
          'task otherHist5 {\n    name     "Other History Task"\n    created  2026-11-11 11:00\n    modified 2026-11-11 12:02:30\n    history  2026-11-11 12:02:30 "External history log"\n}',
        ),
        flush: true,
      );
      await _waitForCondition(
        container,
        () =>
            !container.read(syncStateProvider).isSyncing &&
            (container
                    .read(taskNotifierProvider)
                    .asData
                    ?.value
                    .findTask('otherHist5')
                    ?.history
                    .isNotEmpty ??
                false),
        reason: 'Directory.watch must reconcile external history entry on otherHist5',
      );

      final afterFirstWatch = container.read(taskNotifierProvider).requireValue;
      expect(
        afterFirstWatch.findTask('otherHist5')?.history.single.text,
        equals('External history log'),
      );
      expect(
        afterFirstWatch.findTask('suspWatch3')?.suspendedAt,
        isNull,
        reason: 'External watch reconcile at 12:03:00 must strip expired 12:02:00 suspended deferral',
      );
      expect(
        container.read(taskUndoStateProvider).canUndo,
        isTrue,
        reason: 'Automatic suspended cleanup on suspWatch3 during external watch reconcile must preserve blockerW01 undo entry',
      );

      // 3. Error -> Self-Write/Resume -> New External Input cycle:
      currentTime = DateTime.utc(2026, 11, 11, 12, 4);
      await tdfFile.writeAsString('tdf 0.8.0\ntask broken {{{{\n', flush: true);
      await _waitForCondition(
        container,
        () => container.read(syncStateProvider).errorMessage != null,
        reason: 'Malformed external .tdf must surface SyncState error during Directory.watch reconcile',
      );
      expect(
        container.read(syncStateProvider).errorMessage,
        isNotNull,
        reason: 'Malformed external .tdf must surface SyncState error during Directory.watch reconcile',
      );

      // Self-Write / Resume: repair file externally or via local self-write after restoring valid base + local history mutation:
      await tdfFile.writeAsString(
        const TdfService().serialize(afterFirstWatch),
        flush: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 45));
      currentTime = DateTime.utc(2026, 11, 11, 12, 5);
      await notifier.addTaskHistoryEntry(
        'conflict04',
        timestampUtc: DateTime.utc(2026, 11, 11, 12, 5),
        text: 'Self-write resumed history',
      );
      expect(container.read(syncStateProvider).errorMessage, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 35));

      // New External Input after self-write: externally add a history entry to depWatch02 (which is in blockerW01's previouslyBlockedDependencies!):
      currentTime = DateTime.utc(2026, 11, 11, 12, 6);
      final postSelfWriteDisk = await tdfFile.readAsString();
      final updatedDepBoard = const TdfService()
          .parse(
            postSelfWriteDisk,
            evaluationTime: currentTime,
            localEvaluationTime: currentTime,
          )
          .addTaskHistoryEntry(
            'depWatch02',
            timestampUtc: currentTime,
            text: 'External edit on previously blocked dependent',
            currentDate: currentTime,
            localEvaluationTime: currentTime,
          );
      await tdfFile.writeAsString(
        const TdfService().serialize(updatedDepBoard),
        flush: true,
      );
      await _waitForCondition(
        container,
        () =>
            !container.read(syncStateProvider).isSyncing &&
            (container
                    .read(taskNotifierProvider)
                    .asData
                    ?.value
                    .findTask('depWatch02')
                    ?.history
                    .isNotEmpty ??
                false),
        reason: 'Directory.watch must process new external input cleanly after Error -> Self-Write/Resume',
      );

      final finalBoard = container.read(taskNotifierProvider).requireValue;
      expect(
        finalBoard.findTask('depWatch02')?.history.single.text,
        equals('External edit on previously blocked dependent'),
        reason: 'Directory.watch must process new external input cleanly after Error -> Self-Write/Resume',
      );
      expect(
        container.read(taskUndoStateProvider).canUndo,
        isFalse,
        reason: 'External history edit on depWatch02 (in blockerW01 previouslyBlockedDependencies) must invalidate and prune blockerW01 undo entry',
      );
    });

    test('ignores stale watch stream onDone/onError callbacks after rebinding to a newer generation', () async {
      const config = WebDavConfig(
        storageMode: StorageMode.local,
        language: AppLanguage.english,
      );
      final firstStream = _ControllableCallbackStream();
      final secondStream = _ControllableCallbackStream();
      var streamIndex = 0;
      var listenCount = 0;
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(config),
          ),
          localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
          localFileWatchDebounceProvider.overrideWithValue(
            const Duration(milliseconds: 5),
          ),
          localFileRepositoryProvider.overrideWithValue(
            _StaleCloseWatchLocalRepository(
              config: config,
              baseDirectoryPath: tempDir.path,
              streamFactory: () {
                listenCount++;
                final current = streamIndex++;
                return current == 0 ? firstStream : secondStream;
              },
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final watchSub = container.listen(
        localFileWatcherProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(watchSub.close);
      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);
      await container.read(taskNotifierProvider.future);
      await pumpEventQueue();
      expect(listenCount, equals(1));

      // Emit an error on stream 1 so it marks _streamClosed = true, then trigger rebind to stream 2.
      firstStream.emitError(StateError('Transient watch drop'));
      container
          .read(syncStateProvider.notifier)
          .setSuccess(DateTime.utc(2026, 11, 11, 12));
      expect(
        listenCount,
        equals(2),
        reason: 'Rebind must open generation 2 stream after generation 1 erred',
      );

      // Late onDone from stale stream 1 arrives AFTER generation 2 stream is already active.
      firstStream.emitDone();

      // Subsequent sync completion must NOT rebind again because generation 2 is still open!
      container
          .read(syncStateProvider.notifier)
          .setSuccess(DateTime.utc(2026, 11, 11, 12, 1));
      expect(
        listenCount,
        equals(2),
        reason: 'Stale generation 1 onDone must not mark live generation 2 stream as closed',
      );
    });

    test('unrelated preference updates do not recompute localFileWatchTargetProvider', () async {
      var resolvePathCalls = 0;
      final settingsRepo = InMemorySettingsRepository(
        const WebDavConfig(
          storageMode: StorageMode.local,
          localFilePath: 'scoped_watch.tdf',
        ),
      );
      final countingRepo = _CountingResolveLocalRepository(
        config: const WebDavConfig(
          storageMode: StorageMode.local,
          localFilePath: 'scoped_watch.tdf',
        ),
        baseDirectoryPath: tempDir.path,
        onResolveFilePath: () => resolvePathCalls++,
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepo),
          localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
          localFileRepositoryProvider.overrideWithValue(countingRepo),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 14, 16)),
        ],
      );
      addTearDown(container.dispose);

      final targetSub = container.listen(
        localFileWatchTargetProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(targetSub.close);

      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);
      expect(container.read(localFileWatchTargetProvider).enabled, isTrue);

      resolvePathCalls = 0;
      final configNotifier = container.read(webDavConfigProvider.notifier);
      await configNotifier.updateThemePalette(AppThemePalette.plumUmber);
      await configNotifier.updateThemeMode(AppThemeMode.dark);
      await configNotifier.updateLanguage(AppLanguage.german);
      await configNotifier.updateDueLeadWindow(DueLeadWindow.days7);
      await configNotifier.updateTimeZoneMode(AppTimeZoneMode.manual);
      await configNotifier.updateLocationEnabled(true);
      await configNotifier.updateDiagnosticsEnabled(true);
      await configNotifier.updateDiagnosticsEnabled(false);
      await container.pump();
      container.read(localFileWatchTargetProvider);

      expect(
        resolvePathCalls,
        equals(0),
        reason: 'Unrelated preference edits must never recompute localFileWatchTargetProvider',
      );

      // Changing localWatchEnabled MUST recompute localFileWatchTargetProvider.
      await configNotifier.updateLocalWatchEnabled(false);
      await container.pump();
      expect(container.read(localFileWatchTargetProvider).enabled, isFalse);
      await configNotifier.updateLocalWatchEnabled(true);
      await container.pump();
      expect(container.read(localFileWatchTargetProvider).enabled, isTrue);
      expect(
        resolvePathCalls,
        greaterThan(0),
        reason: 'Toggling localWatchEnabled must recompute localFileWatchTargetProvider',
      );
    });
  });
}

class _CountingResolveLocalRepository extends LocalFileRepository {
  _CountingResolveLocalRepository({
    required super.config,
    super.baseDirectoryPath,
    required this.onResolveFilePath,
  });

  final void Function() onResolveFilePath;

  @override
  bool get canWatchDirectory => true;

  @override
  String? tryResolveFilePath() {
    onResolveFilePath();
    return super.tryResolveFilePath();
  }
}

class _ControllableCallbackStream extends Stream<void> {
  void Function()? _onDone;
  Function? _onError;

  void emitDone() => _onDone?.call();

  void emitError(Object error) {
    final handler = _onError;
    if (handler is void Function(Object)) {
      handler(error);
    } else if (handler is void Function(Object, StackTrace)) {
      handler(error, StackTrace.current);
    }
  }

  @override
  StreamSubscription<void> listen(
    void Function(void event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _onError = onError;
    _onDone = onDone;
    return const Stream<void>.empty().listen(null);
  }
}

class _StaleCloseWatchLocalRepository extends LocalFileRepository {
  _StaleCloseWatchLocalRepository({
    required super.config,
    super.baseDirectoryPath,
    required this.streamFactory,
  });

  final Stream<void> Function() streamFactory;

  @override
  bool get canWatchDirectory => true;

  @override
  bool directoryExists() => true;

  @override
  bool fileExists() => true;

  @override
  Future<String> loadTdf() async => 'tdf 0.8.0\n';

  @override
  Future<({String content, String? digest, bool exists})>
  readTdfWithDigest() async =>
      (content: 'tdf 0.8.0\n', digest: 'stub-digest', exists: true);

  @override
  Future<void> saveTdf(String tdfContent) async {}

  @override
  Stream<void> watchTdfChanges() => streamFactory();

  @override
  Future<T> withExclusiveTargetLock<T>(Future<T> Function() action) => action();
}

Future<void> _waitForCondition(
  ProviderContainer container,
  bool Function() predicate, {
  required String reason,
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (predicate()) {
    return;
  }
  final completer = Completer<void>();
  void check() {
    if (!completer.isCompleted && predicate()) {
      completer.complete();
    }
  }

  final taskSub = container.listen(taskNotifierProvider, (_, _) => check());
  final syncSub = container.listen(syncStateProvider, (_, _) => check());
  final targetSub = container.listen(
    localFileWatchTargetProvider,
    (_, _) => check(),
  );
  try {
    check();
    await completer.future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException(reason, timeout),
    );
  } finally {
    taskSub.close();
    syncSub.close();
    targetSub.close();
  }
}

WebDavConfig _watchCurrentConfig(Ref ref) =>
    ref.watch(webDavConfigProvider).asData?.value ??
    ref.watch(activeWorkspaceProvider).asData?.value.config ??
    const WebDavConfig();

class _SyncStateGateSettingsRepository extends InMemorySettingsRepository {
  _SyncStateGateSettingsRepository(
    super.initialConfig, {
    required this.onLoadSyncState,
  });

  final Future<void> Function() onLoadSyncState;

  @override
  Future<WorkspaceSyncState> loadWorkspaceSyncState(String workspaceId) async {
    await onLoadSyncState();
    return super.loadWorkspaceSyncState(workspaceId);
  }
}
