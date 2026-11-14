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
import 'package:tiertask/models/task_board.dart';
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

class _CountingWebDavRepository extends WebDavRepository {
  _CountingWebDavRepository({required super.config, required this.onRequest});

  final void Function() onRequest;
  String remoteContent = 'tdf 0.6.0\n';

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

  group(
    'LocalFileWatcherNotifier Lifecycle, Scoping, Debounce & Error Isolation',
    () {
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
            filePath: 'tasks.tdf',
            localFilePath: 'tasks.tdf',
            storageMode: StorageMode.local,
            localWatchEnabled: true,
          ),
        );
        var currentTime = DateTime.utc(2026, 11, 14, 13, 0);
        final loadingTransitions = <bool>[];

        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepo),
            localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
            localFileWatchDebounceProvider.overrideWithValue(
              const Duration(milliseconds: 20),
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
              final cfg = resolveCurrentConfig(ref);
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
        await Future<void>.delayed(const Duration(milliseconds: 40));
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
        await configNotifier.updateThemePalette(AppThemePalette.navy);
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
        await Future<void>.delayed(const Duration(milliseconds: 40));
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
        await Future<void>.delayed(const Duration(milliseconds: 60));
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
        final unsupportedSettings = InMemorySettingsRepository(
          const WebDavConfig(storageMode: StorageMode.local),
        );
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
        var currentTime = DateTime.utc(2026, 11, 14, 14, 0);
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
              const Duration(milliseconds: 20),
            ),
            clockProvider.overrideWithValue(() => currentTime),
            webDavRepositoryProvider.overrideWithValue(webDavRepo),
            localFileRepositoryProvider.overrideWith((ref) {
              final cfg = resolveCurrentConfig(ref);
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
        await Future<void>.delayed(const Duration(milliseconds: 50));
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
        await Future<void>.delayed(const Duration(milliseconds: 60));
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
            'tdf 0.6.0\n\n'
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
        await Future<void>.delayed(const Duration(milliseconds: 60));

        expect(container.read(syncStateProvider).hasOpenConflict, isTrue);

        // Repeated AppLifecycleState.resumed events while conflict is open and digest is unchanged perform 0 WebDAV requests!
        final requestsAfterConflict = webDavRequests;
        TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
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
          (await conflictSettings.loadWorkspaceSyncState('tasks')).copyWith(
            clearLastSyncedLocalTdf: true,
            acknowledgedLocalGeneration: 0,
          ),
        );
        await localFile.writeAsString(
          'tdf 0.6.0\n\n'
          'deleted {\n'
          '    generation 5\n'
          '}\n',
          flush: true,
        );
        currentTime = DateTime.utc(2026, 11, 14, 14, 7);
        watchController.add(null);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(container.read(syncStateProvider).hasOpenConflict, isTrue);

        final requestsBeforeRecoveryResume = webDavRequests;
        TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
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
        await Future<void>.delayed(const Duration(milliseconds: 60));

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
        var currentTime = DateTime.utc(2026, 11, 14, 15, 0);

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
              const Duration(milliseconds: 50),
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
        await Future<void>.delayed(const Duration(milliseconds: 140));
        final parsesAfterSelfWrite = parseCount;
        await Future<void>.delayed(const Duration(milliseconds: 100));
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
        await Future<void>.delayed(const Duration(milliseconds: 220));
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
        await Future<void>.delayed(const Duration(milliseconds: 160));
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
          'tdf 0.6.0\n\ntask broken0001 {\n  name "Unclosed"\n',
          'tdf 0.6.0\n\ntask badCtrl001 {\n  name "Bad\x07Char"\n  created 2026-11-14 15:00:00\n  modified 2026-11-14 15:00:00\n}\n',
          'tdf 9.9.9\n',
        ]) {
          liveFile.writeAsStringSync(badPayload, flush: true);
          await Future<void>.delayed(const Duration(milliseconds: 160));
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
        await Future<void>.delayed(const Duration(milliseconds: 180));
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
          ..writeAsStringSync('tdf 0.6.0\n\ntask brokenStart {\n', flush: true);

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
              const Duration(milliseconds: 40),
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
          'tdf 0.6.0\n\n'
          'task fixedStart {\n'
          '    name "Recovered Startup Board"\n'
          '    created 2026-11-14 15:06:00\n'
          '    modified 2026-11-14 15:06:00\n'
          '}\n',
          flush: true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 180));
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
        var currentTime = DateTime.utc(2026, 11, 14, 16, 0);
        const initialSharedTdf =
            'tdf 0.6.0\n\n'
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
            filePath: 'tasks.tdf',
            localFilePath: 'tasks.tdf',
            storageMode: StorageMode.both,
            localWatchEnabled: true,
          ),
        );
        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepo),
            localStorageDirectoryPathProvider.overrideWithValue(
              watchedDir.path,
            ),
            localFileWatchDebounceProvider.overrideWithValue(
              const Duration(milliseconds: 30),
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
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Remote modifies stage2Cf01 while external local save deletes stage2Cf01 -> Stage 1 succeeds, Stage 2 throws deletionConflict!
        remoteContent =
            'tdf 0.6.0\n\n'
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
          'tdf 0.6.0\n\n'
          'deleted {\n'
          '    generation 0\n'
          '    task stage2Cf01 2026-11-14 16:02:00\n'
          '}\n\n'
          'queue {\n'
          '    modified 2026-11-14 16:02:00\n'
          '}\n',
          flush: true,
        );

        // Wait long enough for BOTH the external write event AND Stage 1's own atomic self-write watch event to settle!
        await Future<void>.delayed(const Duration(milliseconds: 180));
        expect(container.read(syncStateProvider).hasOpenConflict, isTrue);

        final requestsAfterStage2Conflict = webDavRequests;
        TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          webDavRequests,
          equals(requestsAfterStage2Conflict),
          reason: 'Self-write and resumed checks on unchanged Stage 1 digest must perform zero WebDAV requests',
        );
        expect(container.read(syncStateProvider).hasOpenConflict, isTrue);

        // Now user saves a NEW external .tdf file (D2 != D1) restoring stage2Cf01 + adding extAftCf01!
        currentTime = DateTime.utc(2026, 11, 14, 16, 3);
        await localFile.writeAsString(
          'tdf 0.6.0\n\n'
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
        await Future<void>.delayed(const Duration(milliseconds: 220));

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
        var currentTime = DateTime.utc(2026, 11, 14, 17, 0);
        final staleDir = Directory('${tempDir.path}/stale_guard')
          ..createSync(recursive: true);
        File('${staleDir.path}/tasks.tdf').writeAsStringSync(
          'tdf 0.6.0\n\n'
          'task initStal01 {\n'
          '    name "Initial Task"\n'
          '    created 2026-11-14 17:00:00\n'
          '    modified 2026-11-14 17:00:00\n'
          '}\n',
          flush: true,
        );

        Completer<void>? syncStateLoadGate;
        final gatedSettings = _SyncStateGateSettingsRepository(
          const WebDavConfig(
            serverUrl: 'https://cloud.example.com',
            username: 'example-user',
            password: 'example-password',
            filePath: 'tasks.tdf',
            localFilePath: 'tasks.tdf',
            storageMode: StorageMode.local,
            localWatchEnabled: true,
          ),
          onLoadSyncState: () async {
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
          'tdf 0.6.0\n\n'
          'task staleExt01 {\n'
          '    name "Should Abort On Mode Switch"\n'
          '    created 2026-11-14 17:01:00\n'
          '    modified 2026-11-14 17:01:00\n'
          '}\n',
          flush: true,
        );

        syncStateLoadGate = Completer<void>();
        final notifier = container.read(taskNotifierProvider.notifier);
        final reconcileFuture = notifier.reconcileExternalLocalChanges();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Switch StorageMode to webdav (localWatchEnabled remains true in same workspace!) while loadWorkspaceSyncState is suspended!
        await container
            .read(webDavConfigProvider.notifier)
            .updateConfig(
              const WebDavConfig(
                serverUrl: 'https://cloud.example.com',
                username: 'example-user',
                password: 'example-password',
                filePath: 'tasks.tdf',
                localFilePath: 'tasks.tdf',
                storageMode: StorageMode.webdav,
                localWatchEnabled: true,
              ),
            );
        syncStateLoadGate.complete();
        syncStateLoadGate = null;

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
            filePath: 'tasks.tdf',
            localFilePath: 'tasks.tdf',
            storageMode: StorageMode.both,
            localWatchEnabled: true,
          ),
        );
        final offlineContainer = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(offlineSettings),
            localStorageDirectoryPathProvider.overrideWithValue(
              offlineMissingDirPath,
            ),
            localFileWatchDebounceProvider.overrideWithValue(
              const Duration(milliseconds: 30),
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
        await Future<void>.delayed(const Duration(milliseconds: 80));

        // External edit in newly created directory must be detected by rebound Directory.watch even while WebDAV remains offline!
        currentTime = DateTime.utc(2026, 11, 14, 17, 6);
        await File('$offlineMissingDirPath/tasks.tdf').writeAsString(
          'tdf 0.6.0\n\n'
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
        await Future<void>.delayed(const Duration(milliseconds: 200));
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
    },
  );
}

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
