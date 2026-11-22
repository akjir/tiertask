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
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/app_build_profile.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/location_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/location_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';
import 'package:tiertask/repositories/window_control_repository.dart';
import 'package:tiertask/services/app_logger.dart';

import 'ui/test_helpers.dart';

/// Spy [WorkspaceUnloadCoordinator] recording pre-unload invocation counts.
class _SpyUnloadCoordinator extends WorkspaceUnloadCoordinator {
  int runBeforeUnloadCallCount = 0;

  @override
  Future<void> runBeforeUnload() {
    runBeforeUnloadCallCount++;
    return super.runBeforeUnload();
  }
}

/// Spy [LocalFileRepository] recording directory watch subscriptions without OS watchers.
class _SpyWatchLocalFileRepository extends LocalFileRepository {
  _SpyWatchLocalFileRepository({
    required super.config,
    super.baseDirectoryPath,
  });

  int watchCallCount = 0;

  @override
  bool get canWatchDirectory => true;

  @override
  bool directoryExists() => true;

  @override
  bool fileExists() => false;

  @override
  Future<String> loadTdf() async => '';

  @override
  Future<({String content, String? digest, bool exists})>
  readTdfWithDigest() async => (content: '', digest: null, exists: false);

  @override
  Future<void> saveTdf(String tdfContent) async {}

  @override
  Stream<void> watchTdfChanges() {
    watchCallCount++;
    return const Stream<void>.empty();
  }

  @override
  Future<T> withExclusiveTargetLock<T>(Future<T> Function() action) => action();
}

/// Spy [WebDavRepository] recording remote log uploads and deletions in memory.
class _SpyWebDavRepository extends WebDavRepository {
  _SpyWebDavRepository({required super.config});

  final List<String> deletedLogNames = <String>[];
  Future<void> Function(String logFileName)? onSaveLog;
  final List<String> savedLogNames = <String>[];
  bool throwOnSaveLog = false;

  @override
  Future<void> deleteLog(String logFileName) async {
    deletedLogNames.add(logFileName);
  }

  @override
  Future<String> fetchTdf() async => '';

  @override
  Future<void> saveLog(String logFileName, [String? logContent]) async {
    savedLogNames.add(logFileName);
    if (onSaveLog case final callback?) {
      await callback(logFileName);
    }
    if (throwOnSaveLog) {
      throw const WebDavException('Simulated remote log upload failure');
    }
  }

  @override
  Future<void> saveTdf(String tdfContent) async {}
}

void main() {
  final fixedUtc = DateTime.utc(2026, 11, 22, 12);

  group('registerGlobalErrorHandlers', () {
    setUp(() {
      AppLogger.resetForTesting(clock: () => fixedUtc);
      AppLogger.setEnabled(
        true,
        persistToDisk: false,
        minimumLevel: LogLevel.info,
      );
    });

    tearDown(AppLogger.resetForTesting);

    test('FlutterError.onError logs a [CRASH] entry without throwing and forwards to presentError', () {
      final previousOnError = FlutterError.onError;
      final previousPresentError = FlutterError.presentError;
      final previousPlatformOnError = PlatformDispatcher.instance.onError;
      addTearDown(() {
        FlutterError.onError = previousOnError;
        FlutterError.presentError = previousPresentError;
        PlatformDispatcher.instance.onError = previousPlatformOnError;
      });

      final presented = <FlutterErrorDetails>[];
      FlutterError.presentError = presented.add;

      registerGlobalErrorHandlers();

      final handler = FlutterError.onError;
      expect(
        handler,
        isNotNull,
        reason: 'registerGlobalErrorHandlers must install FlutterError.onError',
      );
      if (handler != null) {
        final explicitDetails = FlutterErrorDetails(
          exception: StateError('Synthetic framework crash'),
          stack: StackTrace.current,
        );
        expect(
          () => handler(explicitDetails),
          returnsNormally,
          reason: 'FlutterError.onError must capture crashes without throwing',
        );
        final nullStackDetails = FlutterErrorDetails(
          exception: ArgumentError('Crash without explicit stack'),
        );
        expect(
          () => handler(nullStackDetails),
          returnsNormally,
          reason: 'FlutterError.onError must fall back to StackTrace.current when details.stack is null',
        );
      }

      expect(presented.length, equals(2));
      expect(AppLogger.hasCrashedInSession, isTrue);
      expect(
        AppLogger.lines.any(
          (line) =>
              line.contains('[CRASH]') &&
              line.contains('crash.unhandled') &&
              line.contains('Synthetic framework crash'),
        ),
        isTrue,
        reason: 'FlutterError.onError must record a [CRASH] entry for explicit stack details',
      );
      expect(
        AppLogger.lines.any(
          (line) =>
              line.contains('[CRASH]') &&
              line.contains('Crash without explicit stack'),
        ),
        isTrue,
        reason: 'FlutterError.onError must record a [CRASH] entry when stack is null',
      );
      expect(
        AppLogger.lines.any(
          (line) => line.contains('[CRASH]') && line.contains('crash.stack'),
        ),
        isTrue,
        reason: 'FlutterError.onError must record stack trace frames',
      );
    });

    test('PlatformDispatcher.instance.onError logs a [CRASH] entry and returns true', () {
      final previousOnError = FlutterError.onError;
      final previousPlatformOnError = PlatformDispatcher.instance.onError;
      addTearDown(() {
        FlutterError.onError = previousOnError;
        PlatformDispatcher.instance.onError = previousPlatformOnError;
      });

      registerGlobalErrorHandlers();

      final platformHandler = PlatformDispatcher.instance.onError;
      expect(
        platformHandler,
        isNotNull,
        reason: 'registerGlobalErrorHandlers must install PlatformDispatcher.instance.onError',
      );
      if (platformHandler != null) {
        final handled = platformHandler(
          StateError('Synthetic isolate failure'),
          StackTrace.current,
        );
        expect(
          handled,
          isTrue,
          reason: 'PlatformDispatcher.instance.onError must return true to prevent unhandled termination',
        );
      }

      expect(AppLogger.hasCrashedInSession, isTrue);
      expect(
        AppLogger.lines.any(
          (line) =>
              line.contains('[CRASH]') &&
              line.contains('crash.unhandled') &&
              line.contains('Synthetic isolate failure'),
        ),
        isTrue,
        reason:
            'PlatformDispatcher.instance.onError must record a [CRASH] entry',
      );
    });
  });

  group('TierTaskApp Lifecycle & Background Services', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tiertask_main_test_');
      AppLogger.resetForTesting(clock: () => fixedUtc);
    });

    tearDown(() async {
      AppLogger.resetForTesting();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets(
      'flushes remote WebDAV log on paused/hidden only when diagnostics and WebDAV log storage are configured, skips inactive and local mode, and deduplicates in-flight flushes',
      (tester) async {
        const initialConfig = WebDavConfig(
          serverUrl: 'https://cloud.example.com',
          username: 'alice',
          password: 'secret-password',
          storageMode: StorageMode.local,
          language: AppLanguage.english,
          diagnosticsEnabled: true,
          logStorageMode: StorageMode.both,
        );
        final webDavSpy = _SpyWebDavRepository(config: initialConfig);
        final container = await _pumpTierTaskApp(
          tester,
          tempDir: tempDir,
          config: initialConfig,
          webDavRepository: webDavSpy,
          nowUtc: fixedUtc,
        );

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        expect(
          webDavSpy.savedLogNames,
          isEmpty,
          reason: 'AppLifecycleState.inactive must not trigger immediate WebDAV log upload',
        );

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(
          webDavSpy.savedLogNames,
          isEmpty,
          reason:
              'AppLifecycleState.resumed must not trigger WebDAV log upload',
        );

        // Deduplicate concurrent hidden -> paused transitions while a remote upload is in flight.
        final flushGate = Completer<void>();
        webDavSpy.onSaveLog = (_) => flushGate.future;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await tester.pump();
        expect(
          webDavSpy.savedLogNames.length,
          equals(1),
          reason: 'AppLifecycleState.hidden must trigger remote WebDAV log flush when configured',
        );

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(
          webDavSpy.savedLogNames.length,
          equals(1),
          reason: 'Concurrent paused transition must reuse the in-flight remote log flush',
        );

        flushGate.complete();
        await tester.pump();
        webDavSpy.onSaveLog = null;

        // Subsequent hidden and paused transitions each start a fresh upload once idle.
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await tester.pump();
        expect(
          webDavSpy.savedLogNames.length,
          equals(2),
          reason: 'AppLifecycleState.hidden must trigger remote WebDAV log flush when idle',
        );

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(
          webDavSpy.savedLogNames.length,
          equals(3),
          reason: 'AppLifecycleState.paused must trigger remote WebDAV log flush when idle',
        );

        // Background flush failures are swallowed cleanly and do not wedge future flushes.
        webDavSpy.throwOnSaveLog = true;
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await tester.pump();
        expect(webDavSpy.savedLogNames.length, equals(4));

        webDavSpy.throwOnSaveLog = false;
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(
          webDavSpy.savedLogNames.length,
          equals(5),
          reason: 'A failed remote log flush must clear _inFlightRemoteLogFlush so later flushes run',
        );

        // Return to resumed via valid Flutter lifecycle transitions before switching logStorageMode to local.
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        final countBeforeLocalMode = webDavSpy.savedLogNames.length;

        final configNotifier = container.read(webDavConfigProvider.notifier);
        await configNotifier.updateLogStorageMode(StorageMode.local);
        await tester.pump();

        for (final state in const <AppLifecycleState>[
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
          await tester.pump();
          expect(
            webDavSpy.savedLogNames.length,
            equals(countBeforeLocalMode),
            reason:
                'Lifecycle $state must skip WebDAV upload when logStorageMode is local',
          );
        }

        // Disabling diagnostics skips remote upload even when logStorageMode uses WebDAV.
        await configNotifier.updateConfig(
          initialConfig.copyWith(
            diagnosticsEnabled: false,
            logStorageMode: StorageMode.webdav,
          ),
        );
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(
          webDavSpy.savedLogNames.length,
          equals(countBeforeLocalMode),
          reason: 'Lifecycle hidden/paused must skip WebDAV upload when diagnosticsEnabled is false',
        );

        // Missing WebDAV credentials/URL skips remote upload even when diagnostics and WebDAV log storage are enabled.
        await configNotifier.updateConfig(
          const WebDavConfig(
            language: AppLanguage.english,
            diagnosticsEnabled: true,
            logStorageMode: StorageMode.webdav,
          ),
        );
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(
          webDavSpy.savedLogNames.length,
          equals(countBeforeLocalMode),
          reason: 'Lifecycle hidden/paused must skip WebDAV upload when WebDAV is not configured',
        );

        // Restore resumed lifecycle state before teardown.
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();

        await _disposeTierTaskApp(tester, container);
      },
    );

    testWidgets(
      '_BackgroundServicesHost keeps diagnosticsEnabledProvider and localFileWatcherProvider active without rebuilding MaterialApp when diagnostics toggle',
      (tester) async {
        const initialConfig = WebDavConfig(language: AppLanguage.english);
        final watchSpy = _SpyWatchLocalFileRepository(
          config: initialConfig,
          baseDirectoryPath: tempDir.path,
        );
        final container = await _pumpTierTaskApp(
          tester,
          tempDir: tempDir,
          config: initialConfig,
          localFileRepository: watchSpy,
          nowUtc: fixedUtc,
        );

        expect(
          watchSpy.watchCallCount,
          greaterThanOrEqualTo(1),
          reason: '_BackgroundServicesHost must keep localFileWatcherProvider subscribed on mount',
        );
        expect(
          AppLogger.isEnabled,
          isFalse,
          reason: 'AppLogger starts disabled when diagnosticsEnabled is false',
        );

        final initialMaterialApp = tester.widget<MaterialApp>(
          find.byType(MaterialApp),
        );

        final configNotifier = container.read(webDavConfigProvider.notifier);
        await configNotifier.updateDiagnosticsEnabled(true);
        await tester.pump();

        expect(
          AppLogger.isEnabled,
          isTrue,
          reason: '_BackgroundServicesHost must keep diagnosticsEnabledProvider active on toggle on',
        );
        expect(
          identical(
            tester.widget<MaterialApp>(find.byType(MaterialApp)),
            initialMaterialApp,
          ),
          isTrue,
          reason: 'Enabling diagnostics must not rebuild MaterialApp',
        );

        await configNotifier.updateDiagnosticsEnabled(false);
        await tester.pump();

        expect(
          AppLogger.isEnabled,
          isFalse,
          reason: '_BackgroundServicesHost must deactivate AppLogger when diagnostics toggles off',
        );
        expect(
          identical(
            tester.widget<MaterialApp>(find.byType(MaterialApp)),
            initialMaterialApp,
          ),
          isTrue,
          reason: 'Disabling diagnostics must not rebuild MaterialApp',
        );

        // Positive control: updating a watched theme property does rebuild MaterialApp.
        await configNotifier.updateThemeMode(AppThemeMode.dark);
        await tester.pump();
        expect(
          identical(
            tester.widget<MaterialApp>(find.byType(MaterialApp)),
            initialMaterialApp,
          ),
          isFalse,
          reason: 'Changing appThemeModeProvider must rebuild MaterialApp',
        );

        await _disposeTierTaskApp(tester, container);
      },
    );

    testWidgets(
      '_BackgroundServicesHost skips localFileWatcherProvider when supportsLocalFileWatchProvider is false while keeping diagnostics active',
      (tester) async {
        const initialConfig = WebDavConfig(
          language: AppLanguage.english,
          storageMode: StorageMode.local,
        );
        final watchSpy = _SpyWatchLocalFileRepository(
          config: initialConfig,
          baseDirectoryPath: tempDir.path,
        );
        final container = await _pumpTierTaskApp(
          tester,
          tempDir: tempDir,
          config: initialConfig,
          localFileRepository: watchSpy,
          nowUtc: fixedUtc,
          supportsLocalFileWatch: false,
        );

        expect(
          watchSpy.watchCallCount,
          equals(0),
          reason: '_BackgroundServicesHost must not subscribe localFileWatcherProvider when supportsLocalFileWatchProvider is false',
        );
        expect(AppLogger.isEnabled, isFalse);

        await container
            .read(webDavConfigProvider.notifier)
            .updateDiagnosticsEnabled(true);
        await tester.pump();
        expect(
          AppLogger.isEnabled,
          isTrue,
          reason: 'diagnosticsEnabledProvider must stay active when local file watching is unsupported',
        );
        expect(watchSpy.watchCallCount, equals(0));

        await container
            .read(webDavConfigProvider.notifier)
            .updateDiagnosticsEnabled(false);
        await tester.pump();

        await _disposeTierTaskApp(tester, container);
      },
    );

    testWidgets(
      'onExitRequested drains workspaceUnloadCoordinatorProvider before flushing AppLogger and returning AppExitResponse.exit',
      (tester) async {
        const initialConfig = WebDavConfig(
          language: AppLanguage.english,
          diagnosticsEnabled: true,
        );
        final unloadSpy = _SpyUnloadCoordinator();
        final container = await _pumpTierTaskApp(
          tester,
          tempDir: tempDir,
          config: initialConfig,
          unloadCoordinator: unloadSpy,
          nowUtc: fixedUtc,
        );

        final unloadGate = Completer<void>();
        final events = <String>[];
        final unregisterHook = unloadSpy.register(() async {
          events.add('unload.start');
          await unloadGate.future;
          AppLogger.event(
            LogLevel.info,
            LogTag.lifecycle,
            'test.unload_drained',
          );
          events.add('unload.done');
        });

        var exitCompleted = false;
        final exitFuture = WidgetsBinding.instance.handleRequestAppExit();
        unawaited(
          exitFuture.then((_) {
            exitCompleted = true;
          }),
        );
        await tester.pump();

        expect(unloadSpy.runBeforeUnloadCallCount, equals(1));
        expect(
          events,
          equals(const <String>['unload.start']),
          reason: 'onExitRequested must enter registered unload hooks before returning',
        );
        expect(
          exitCompleted,
          isFalse,
          reason: 'onExitRequested must wait for runBeforeUnload before returning AppExitResponse.exit',
        );
        expect(
          AppLogger.lines.any((line) => line.contains('session.exit')),
          isFalse,
          reason: 'AppLogger detached flush must wait until runBeforeUnload completes',
        );

        unloadGate.complete();
        final response = await exitFuture;
        await tester.pump();

        expect(response, equals(AppExitResponse.exit));
        expect(events, equals(const <String>['unload.start', 'unload.done']));

        final drainedIndex = AppLogger.lines.indexWhere(
          (line) => line.contains('test.unload_drained'),
        );
        final exitIndex = AppLogger.lines.indexWhere(
          (line) => line.contains('session.exit'),
        );
        expect(drainedIndex, greaterThanOrEqualTo(0));
        expect(exitIndex, greaterThan(drainedIndex));
        expect(
          File(AppLogger.logFilePath).readAsStringSync(),
          contains('session.exit'),
          reason: 'onExitRequested must flush session.exit to the local diagnostic log file',
        );

        // Unload hook exceptions must be logged and still allow AppLogger flush and exit.
        unregisterHook();
        final unregisterFailingHook = unloadSpy.register(
          () =>
              Future<void>.error(StateError('Simulated unload drain failure')),
        );
        addTearDown(unregisterFailingHook);

        final errorExitResponse = await WidgetsBinding.instance
            .handleRequestAppExit();
        await tester.pump();

        expect(errorExitResponse, equals(AppExitResponse.exit));
        expect(
          AppLogger.lines.any(
            (line) => line.contains('lifecycle.exit_flush_failed'),
          ),
          isTrue,
          reason: 'onExitRequested must record unload failures at warn level without blocking exit',
        );

        await _disposeTierTaskApp(tester, container);
      },
    );
  });
}

/// Unmounts [TierTaskApp] and disposes [container] so debounced timers close cleanly before test exit.
Future<void> _disposeTierTaskApp(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  container.dispose();
}

/// Pumps [TierTaskApp] with isolated in-memory providers and optional test spies.
Future<ProviderContainer> _pumpTierTaskApp(
  WidgetTester tester, {
  required Directory tempDir,
  required WebDavConfig config,
  required DateTime nowUtc,
  LocalFileRepository? localFileRepository,
  WebDavRepository? webDavRepository,
  WorkspaceUnloadCoordinator? unloadCoordinator,
  bool supportsLocalFileWatch = true,
}) async {
  const surfaceSize = Size(1280, 860);
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final settingsRepository = InMemorySettingsRepository(config);
  final container = ProviderContainer(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(settingsRepository),
      localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
      localFileRepositoryProvider.overrideWithValue(
        localFileRepository ??
            FakeLocalFileRepository(config: config, initialTdf: ''),
      ),
      webDavRepositoryProvider.overrideWithValue(
        webDavRepository ?? _SpyWebDavRepository(config: config),
      ),
      if (unloadCoordinator != null)
        workspaceUnloadCoordinatorProvider.overrideWithValue(unloadCoordinator),
      taskNotifierProvider.overrideWith(
        () => FakeTaskNotifier(TaskBoard.empty()),
      ),
      clockProvider.overrideWithValue(() => nowUtc),
      appBuildProfileProvider.overrideWithValue(AppBuildProfile.release),
      appVersionProvider.overrideWith((ref) => 'v0.4.0+4.abc1234'),
      supportsDirectoryPickerProvider.overrideWithValue(true),
      supportsDesktopWindowControlsProvider.overrideWithValue(true),
      supportsLocalFileWatchProvider.overrideWithValue(supportsLocalFileWatch),
      windowControlRepositoryProvider.overrideWithValue(
        FakeWindowControlRepository(),
      ),
      locationRepositoryProvider.overrideWithValue(FakeLocationRepository()),
    ],
  );
  addTearDown(container.dispose);

  await container.read(webDavConfigProvider.future);
  await container.read(appVersionProvider.future);
  await container.read(taskNotifierProvider.future);

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const TierTaskApp()),
  );
  await tester.pumpAndSettle();
  return container;
}
