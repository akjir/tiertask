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

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/l10n/app_localizations_de.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/app_version_repository.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';
import 'package:tiertask/services/app_logger.dart';

void main() {
  final fixedDate = DateTime.utc(2026, 11, 1, 12);

  group('AppLanguage, AppThemeMode, StorageMode & WebDavConfig Resolution', () {
    test(
      'resolves English as default and honors German or System locale settings',
      () {
        expect(
          AppLanguage.system.resolveLocale(const Locale('de', 'DE')),
          equals(const Locale('de')),
        );
        expect(
          AppLanguage.system.resolveLocale(const Locale('en', 'US')),
          equals(const Locale('en')),
        );
        expect(
          AppLanguage.system.resolveLocale(const Locale('fr', 'FR')),
          equals(const Locale('en')),
        );
        expect(
          AppLanguage.system.resolveLocale(null),
          equals(const Locale('en')),
        );
        expect(
          AppLanguage.english.resolveLocale(const Locale('de', 'DE')),
          equals(const Locale('en')),
        );
        expect(
          AppLanguage.german.resolveLocale(const Locale('en', 'US')),
          equals(const Locale('de')),
        );
        expect(AppLanguage.tryParseJson('german'), equals(AppLanguage.german));
        expect(
          AppLanguage.tryParseJson('english'),
          equals(AppLanguage.english),
        );
        expect(AppLanguage.tryParseJson('system'), equals(AppLanguage.system));
        expect(AppLanguage.tryParseJson('unknown'), isNull);
      },
    );

    test('resolves AppThemeMode and StorageMode JSON tokens with system and local tasks.tdf defaults', () {
      expect(AppThemeMode.tryParseJson('light'), equals(AppThemeMode.light));
      expect(AppThemeMode.tryParseJson('dark'), equals(AppThemeMode.dark));
      expect(AppThemeMode.tryParseJson('system'), equals(AppThemeMode.system));
      expect(AppThemeMode.tryParseJson('unknown'), isNull);

      expect(StorageMode.tryParseJson('local'), equals(StorageMode.local));
      expect(StorageMode.tryParseJson('webdav'), equals(StorageMode.webdav));
      expect(StorageMode.tryParseJson('both'), equals(StorageMode.both));
      expect(StorageMode.tryParseJson('unknown'), isNull);

      const defaultConfig = WebDavConfig();
      expect(defaultConfig.themeMode, equals(AppThemeMode.system));
      expect(defaultConfig.storageMode, equals(StorageMode.local));
      expect(
        defaultConfig.localFilePath,
        equals('tasks.tdf'),
        reason: 'Default localFilePath must be tasks.tdf',
      );
      expect(
        defaultConfig.filePath,
        equals('tasks.tdf'),
        reason: 'Default remote filePath must be tasks.tdf',
      );
      expect(defaultConfig.isConfigured, isTrue);
    });
  });

  group('Localization ARB Metadata & Key Parity', () {
    test('every message key in app_en.arb defines @key metadata with a non-empty description and matches app_de.arb keys', () {
      final enRaw = File('lib/l10n/app_en.arb').readAsStringSync();
      final deRaw = File('lib/l10n/app_de.arb').readAsStringSync();
      final enDecoded = jsonDecode(enRaw);
      final deDecoded = jsonDecode(deRaw);

      expect(enDecoded, isA<Map<String, Object?>>());
      expect(deDecoded, isA<Map<String, Object?>>());
      if (enDecoded is! Map<String, Object?> ||
          deDecoded is! Map<String, Object?>) {
        return;
      }

      final enMessageKeys = <String>[
        for (final key in enDecoded.keys)
          if (!key.startsWith('@')) key,
      ];
      final deMessageKeys = <String>[
        for (final key in deDecoded.keys)
          if (!key.startsWith('@')) key,
      ];

      expect(enMessageKeys, contains('tier2Name'));
      expect(enMessageKeys, contains('sectionTasksTitle'));
      expect(enMessageKeys, contains('drawerLabels'));
      expect(enMessageKeys, contains('emptyLabelsHint'));
      expect(deMessageKeys, equals(enMessageKeys));

      for (final key in enMessageKeys) {
        _expectArbKeyMetadata(enDecoded, key);
      }
    });

    test('Linux, Windows, and Android platform runners and manifests display TierTask as the taskbar and window title and configure frameless desktop chrome', () {
      final linuxRunner = File('linux/runner/my_application.cc')
          .readAsStringSync();
      expect(linuxRunner, contains('gtk_window_set_decorated(window, FALSE);'));
      expect(linuxRunner, isNot(contains('gtk_header_bar_new')));
      expect(
        linuxRunner,
        contains('gtk_window_set_title(window, "TierTask");'),
      );
      expect(linuxRunner, contains('g_set_application_name("TierTask");'));
      expect(linuxRunner, contains('"de.akjir.tiertask/window_controls"'));

      final windowsMain = File('windows/runner/main.cpp').readAsStringSync();
      expect(windowsMain, contains('window.Create(L"TierTask", origin, size)'));

      final windowsWindow = File('windows/runner/win32_window.cpp')
          .readAsStringSync();
      expect(windowsWindow, contains('case WM_NCCALCSIZE:'));
      expect(windowsWindow, contains('DwmExtendFrameIntoClientArea'));

      final windowsFlutterWindow = File('windows/runner/flutter_window.cpp')
          .readAsStringSync();
      expect(
        windowsFlutterWindow,
        contains('"de.akjir.tiertask/window_controls"'),
      );

      final windowsResource = File('windows/runner/Runner.rc')
          .readAsStringSync();
      expect(
        windowsResource,
        contains('VALUE "FileDescription", "TierTask" "\\0"'),
      );

      final androidManifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(androidManifest, contains('android:label="TierTask"'));
    });
  });

  group('WebDavConfigNotifier & Preference Providers', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tiertask_config_prov_');
    });

    tearDown(() async {
      AppLogger.setEnabled(
        false,
        sink: const LocalFileLogSink(),
        logFilePath: '',
      );
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('updates language, themeMode, themePalette, timeZone, storageMode, and diagnosticsEnabled reactively', () async {
      final settingsRepo = InMemorySettingsRepository(
        const WebDavConfig(
          language: AppLanguage.english,
          password: 'super-secret-password',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepo),
          localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
          clockProvider.overrideWithValue(() => fixedDate),
          appVersionRepositoryProvider.overrideWithValue(
            const FakeAppVersionRepository(version: 'v0.1.0+99.abcdef0'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(webDavConfigProvider.future);
      expect(
        await container.read(appVersionProvider.future),
        equals('v0.1.0+99.abcdef0'),
      );
      expect(container.read(appLocaleProvider), equals(const Locale('en')));
      expect(container.read(appThemeModeProvider), equals(AppThemeMode.system));
      expect(
        container.read(appThemePaletteProvider),
        equals(AppThemePalette.calm),
      );
      expect(container.read(diagnosticsEnabledProvider), isFalse);

      final notifier = container.read(webDavConfigProvider.notifier);
      await notifier.updateLanguage(AppLanguage.german);
      expect(container.read(appLocaleProvider), equals(const Locale('de')));

      await notifier.updateThemeMode(AppThemeMode.dark);
      expect(container.read(appThemeModeProvider), equals(AppThemeMode.dark));

      await notifier.updateThemePalette(AppThemePalette.plumUmber);
      expect(
        container.read(appThemePaletteProvider),
        equals(AppThemePalette.plumUmber),
      );

      await notifier.updateTimeZoneMode(AppTimeZoneMode.manual);
      await notifier.updateManualTimeZoneOffsetMinutes(120);
      await notifier.updateStorageMode(StorageMode.both);
      final updatedConfig = container.read(webDavConfigProvider).requireValue;
      expect(updatedConfig.timeZoneMode, equals(AppTimeZoneMode.manual));
      expect(updatedConfig.manualTimeZoneOffsetMinutes, equals(120));
      expect(updatedConfig.storageMode, equals(StorageMode.both));

      await notifier.updateDiagnosticsEnabled(true);
      expect(container.read(diagnosticsEnabledProvider), isTrue);
      expect(AppLogger.isEnabled, isTrue);
      final logFile = File(
        LocalFileRepository.resolveLogFilePath(
          baseDirectoryPath: tempDir.path,
          utcNow: fixedDate.toUtc(),
          platform: Platform.operatingSystem,
          workspaceId: 'tasks',
        ),
      );
      expect(
        await logFile.exists(),
        isTrue,
        reason: 'Enabling diagnostics must write startup log to dated log file',
      );

      await notifier.updateLogLevel(LogLevel.debug);
      expect(
        container.read(webDavConfigProvider).requireValue.logLevel,
        equals(LogLevel.debug),
      );
      expect(AppLogger.minimumLevel, equals(LogLevel.debug));

      await notifier.updateLogStorageMode(StorageMode.both);
      expect(
        container.read(webDavConfigProvider).requireValue.logStorageMode,
        equals(StorageMode.both),
      );
      expect(
        AppLogger.fullLogText,
        contains('log_storage=both min_level=DEBUG'),
        reason:
            'Updating logStorageMode and logLevel must refresh @meta header',
      );

      await notifier.updateDiagnosticsEnabled(false);
      expect(container.read(diagnosticsEnabledProvider), isFalse);
      expect(AppLogger.isEnabled, isFalse);
      expect(
        await logFile.exists(),
        isFalse,
        reason: 'Disabling diagnostics must immediately delete dated log file',
      );

      expect(
        container.read(webDavConfigProvider).requireValue.localWatchEnabled,
        isTrue,
      );
      await notifier.updateLocalWatchEnabled(false);
      expect(
        container.read(webDavConfigProvider).requireValue.localWatchEnabled,
        isFalse,
      );
      expect(
        (await settingsRepo.loadConfig()).localWatchEnabled,
        isFalse,
        reason:
            'updateLocalWatchEnabled(false) must persist to SettingsRepository',
      );
      await notifier.updateLocalWatchEnabled(true);
      expect(
        container.read(webDavConfigProvider).requireValue.localWatchEnabled,
        isTrue,
      );

      expect(
        container.read(boundaryTickProvider),
        equals(0),
        reason: 'boundaryTickProvider must initialize at 0',
      );
      container.read(boundaryTickProvider.notifier).increment();
      container.read(boundaryTickProvider.notifier).increment();
      expect(
        container.read(boundaryTickProvider),
        equals(2),
        reason: 'BoundaryTickNotifier.increment() must advance monotonically',
      );

      await notifier.updateDiagnosticsEnabled(true);
      for (final window in DueLeadWindow.values) {
        await notifier.updateDueLeadWindow(window);
        expect(
          container.read(webDavConfigProvider).requireValue.dueLeadWindow,
          equals(window),
          reason: 'updateDueLeadWindow(${window.name}) must update state',
        );
        expect(
          (await settingsRepo.loadConfig()).dueLeadWindow,
          equals(window),
          reason: 'updateDueLeadWindow(${window.name}) must persist to storage',
        );
      }
      expect(
        AppLogger.fullLogText,
        contains('due_lead=days7'),
        reason: 'config.update log event must record due_lead field',
      );

      // Verify per-workspace isolation across workspace switches:
      await notifier.updateDueLeadWindow(DueLeadWindow.off);
      final workWorkspace = await container
          .read(activeWorkspaceProvider.notifier)
          .createWorkspace(
            'Engineering',
            config: const WebDavConfig(
              localFilePath: 'engineering.tdf',
              filePath: 'engineering.tdf',
              dueLeadWindow: DueLeadWindow.hours48,
            ),
            activate: true,
          );
      expect(
        (await container.read(webDavConfigProvider.future)).dueLeadWindow,
        equals(DueLeadWindow.hours48),
        reason: 'Activated Engineering workspace must expose hours48',
      );
      await container
          .read(activeWorkspaceProvider.notifier)
          .switchWorkspace('tasks');
      expect(
        (await container.read(webDavConfigProvider.future)).dueLeadWindow,
        equals(DueLeadWindow.off),
        reason: 'Switching back to Tasks must restore DueLeadWindow.off',
      );
      await container
          .read(activeWorkspaceProvider.notifier)
          .switchWorkspace(workWorkspace.id);
      expect(
        (await container.read(webDavConfigProvider.future)).dueLeadWindow,
        equals(DueLeadWindow.hours48),
        reason:
            'Switching back to Engineering must restore DueLeadWindow.hours48',
      );
      await notifier.updateDiagnosticsEnabled(false);
    });
  });

  group('WebDavConfigNotifier.changeLocalFileLocation & Atomic Rollback', () {
    late Directory sourceDir;
    late Directory targetDir;

    setUp(() async {
      sourceDir = await Directory.systemTemp.createTemp('tiertask_cfg_src_');
      targetDir = await Directory.systemTemp.createTemp('tiertask_cfg_dst_');
    });

    tearDown(() async {
      if (await sourceDir.exists()) {
        await sourceDir.delete(recursive: true);
      }
      if (await targetDir.exists()) {
        await targetDir.delete(recursive: true);
      }
    });

    test('moves file on success, rejects existing target file, and rolls back file move on WorkspaceException duplicate path', () async {
      final initialFilePath =
          '${sourceDir.path}${Platform.pathSeparator}tasks.tdf';
      await File(initialFilePath).writeAsString(
        'tdf 0.8.0\n\ntask 000001OkD2 {\n    name "Keep Safe"\n    created 2026-11-01 08:00:00\n    modified 2026-11-01 08:00:00\n}\n',
        flush: true,
      );

      final settingsRepository = InMemorySettingsRepository(
        WebDavConfig(
          localFilePath: initialFilePath,
          storageMode: StorageMode.local,
          language: AppLanguage.english,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
        ],
      );
      addTearDown(container.dispose);

      await container.read(webDavConfigProvider.future);

      final conflictPath =
          '${targetDir.path}${Platform.pathSeparator}tasks.tdf';
      await File(conflictPath).writeAsString('do not overwrite', flush: true);

      await expectLater(
        () => container
            .read(webDavConfigProvider.notifier)
            .changeLocalFileLocation(
              WebDavConfig(
                localFilePath: conflictPath,
                storageMode: StorageMode.local,
                language: AppLanguage.english,
              ),
            ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains('A file already exists at the target path'),
          ),
        ),
        reason: 'changeLocalFileLocation must throw LocalFileException when target file already exists',
      );

      final configAfterFailedMove = await container.read(
        webDavConfigProvider.future,
      );
      expect(
        configAfterFailedMove.localFilePath,
        equals(initialFilePath),
        reason: 'Failed directory move must leave persisted localFilePath unchanged',
      );
      expect(
        await File(initialFilePath).exists(),
        isTrue,
        reason: 'Original file must remain in place after failed move',
      );

      await File(conflictPath).delete();

      await container
          .read(webDavConfigProvider.notifier)
          .changeLocalFileLocation(
            WebDavConfig(
              localFilePath: conflictPath,
              storageMode: StorageMode.local,
              language: AppLanguage.english,
            ),
          );

      final configAfterSuccess = await container.read(
        webDavConfigProvider.future,
      );
      expect(
        configAfterSuccess.localFilePath,
        equals(conflictPath),
        reason: 'Successful directory move must update persisted localFilePath',
      );
      expect(
        await File(initialFilePath).exists(),
        isFalse,
        reason: 'Original file must be removed after successful move',
      );
      expect(
        await File(conflictPath).exists(),
        isTrue,
        reason: 'File must exist at new target path after successful move',
      );

      final secondWorkspacePath =
          '${sourceDir.path}${Platform.pathSeparator}second.tdf';
      await container
          .read(activeWorkspaceProvider.notifier)
          .createWorkspace(
            'Second Workspace',
            config: WebDavConfig(
              localFilePath: secondWorkspacePath,
              filePath: 'second.tdf',
            ),
          );

      await expectLater(
        () => container
            .read(webDavConfigProvider.notifier)
            .changeLocalFileLocation(
              WebDavConfig(
                localFilePath: secondWorkspacePath,
                storageMode: StorageMode.local,
                language: AppLanguage.english,
              ),
            ),
        throwsA(
          isA<LocalFileException>().having(
            (error) => error.message,
            'message',
            contains('Another workspace already uses this TDF file path'),
          ),
        ),
        reason: 'Colliding with another workspace localFilePath must be rolled back and rejected',
      );
      expect(
        await File(conflictPath).exists(),
        isTrue,
        reason: 'Moved file must be rolled back to conflictPath when workspace validation fails',
      );
    });

    test('supportsDesktopWindowControlsProvider is true on Linux and Windows and false on Android', () {
      const cases = <(TargetPlatform, bool)>[
        (TargetPlatform.linux, true),
        (TargetPlatform.windows, true),
        (TargetPlatform.android, false),
      ];

      for (final (platform, expected) in cases) {
        debugDefaultTargetPlatformOverride = platform;
        final container = ProviderContainer();
        try {
          expect(
            container.read(supportsDesktopWindowControlsProvider),
            equals(expected),
            reason:
                'Platform $platform desktop window controls support must be $expected',
          );
        } finally {
          container.dispose();
          debugDefaultTargetPlatformOverride = null;
        }
      }
    });

    test('supportsLocalFileWatchProvider is true on Linux and Windows and false on Android', () {
      const cases = <(TargetPlatform, bool)>[
        (TargetPlatform.linux, true),
        (TargetPlatform.windows, true),
        (TargetPlatform.android, false),
      ];

      for (final (platform, expected) in cases) {
        debugDefaultTargetPlatformOverride = platform;
        final container = ProviderContainer();
        try {
          expect(
            container.read(supportsLocalFileWatchProvider),
            equals(expected),
            reason:
                'Platform $platform local file watch support must be $expected',
          );
        } finally {
          container.dispose();
          debugDefaultTargetPlatformOverride = null;
        }
      }
    });

    test('WebDavConfigNotifier updates preferences synchronously without dropping through AsyncLoading', () async {
      final settingsRepository = InMemorySettingsRepository(
        const WebDavConfig(
          language: AppLanguage.english,
          themeMode: AppThemeMode.light,
          storageMode: StorageMode.both,
          serverUrl: 'https://cloud.example.com',
          username: 'alice',
          password: 'secret',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
        ],
      );
      addTearDown(container.dispose);

      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);

      final emissions = <AsyncValue<WebDavConfig>>[];
      final subscription = container.listen<AsyncValue<WebDavConfig>>(
        webDavConfigProvider,
        (_, next) => emissions.add(next),
      );
      addTearDown(subscription.close);

      await container
          .read(webDavConfigProvider.notifier)
          .updateThemePalette(AppThemePalette.plumUmber);
      await container
          .read(webDavConfigProvider.notifier)
          .updateThemeMode(AppThemeMode.dark);
      await container
          .read(webDavConfigProvider.notifier)
          .updateLanguage(AppLanguage.german);
      await Future<void>.delayed(Duration.zero);

      expect(
        emissions.any((state) => state is AsyncLoading<WebDavConfig>),
        isFalse,
        reason: 'Preference updates must never drop webDavConfigProvider through AsyncLoading (asData == null)',
      );
      final current = container.read(webDavConfigProvider).requireValue;
      expect(current.themePalette, equals(AppThemePalette.plumUmber));
      expect(current.themeMode, equals(AppThemeMode.dark));
      expect(current.language, equals(AppLanguage.german));
    });

    test('non-storage preference updates preserve repository instances, avoid redundant log rewrites, serialize concurrent toggles, and roll back failed saves', () async {
      AppLogger.resetForTesting();
      addTearDown(AppLogger.resetForTesting);

      Completer<void>? saveGate;
      var shouldFailSave = false;
      final settingsRepository = _GateableSettingsRepository(
        const WebDavConfig(
          language: AppLanguage.english,
          themeMode: AppThemeMode.light,
          storageMode: StorageMode.both,
          serverUrl: 'https://cloud.example.com',
          username: 'alice',
          password: 'secret',
          diagnosticsEnabled: true,
        ),
        onSave: () async {
          if (saveGate case final gate?) {
            await gate.future;
          }
          if (shouldFailSave) {
            throw const WorkspaceException(
              WorkspaceErrorKind.settingsPersistenceFailed,
              'Simulated disk failure',
            );
          }
        },
      );
      final tempDir = await Directory.systemTemp.createTemp(
        'tiertask_cfg_diag_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
          clockProvider.overrideWithValue(() => fixedDate),
        ],
      );
      addTearDown(container.dispose);

      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);

      final diagSub = container.listen(diagnosticsEnabledProvider, (_, _) {});
      addTearDown(diagSub.close);
      final webDavRepoBefore = container.read(webDavRepositoryProvider);
      final localRepoBefore = container.read(localFileRepositoryProvider);
      final logRevisionBefore = AppLogger.revision.value;

      // Fire two rapid preference toggles while the first disk save is suspended.
      saveGate = Completer<void>();
      final notifier = container.read(webDavConfigProvider.notifier);
      final firstFuture = notifier.updateThemePalette(
        AppThemePalette.plumUmber,
      );
      final secondFuture = notifier.updateThemeMode(AppThemeMode.dark);

      final midFlight = container.read(webDavConfigProvider).requireValue;
      expect(
        midFlight.themePalette,
        equals(AppThemePalette.plumUmber),
        reason: 'First optimistic update must be visible immediately',
      );
      expect(
        midFlight.themeMode,
        equals(AppThemeMode.dark),
        reason: 'Second rapid preference update must compose on top of first without dropping clicks',
      );

      saveGate.complete();
      saveGate = null;
      await Future.wait(<Future<void>>[firstFuture, secondFuture]);

      final afterBoth = container.read(webDavConfigProvider).requireValue;
      expect(afterBoth.themePalette, equals(AppThemePalette.plumUmber));
      expect(afterBoth.themeMode, equals(AppThemeMode.dark));
      final persisted = await settingsRepository.loadConfig();
      expect(persisted.themePalette, equals(AppThemePalette.plumUmber));
      expect(persisted.themeMode, equals(AppThemeMode.dark));

      expect(
        container.read(webDavRepositoryProvider),
        same(webDavRepoBefore),
        reason: 'UI preference toggles must not recreate WebDavRepository and wipe ETag cache',
      );
      expect(
        container.read(localFileRepositoryProvider),
        same(localRepoBefore),
        reason: 'UI preference toggles must not recreate LocalFileRepository',
      );
      // Updating theme palette/mode emits config.update log lines, but must not rewrite header in place redundantly.
      expect(
        AppLogger.revision.value,
        lessThanOrEqualTo(logRevisionBefore + 2),
        reason: 'Non-logger preference updates must not trigger redundant AppLogger.setEnabled header rewrites',
      );

      // Failed persistence must roll back optimistic state cleanly.
      shouldFailSave = true;
      await expectLater(
        notifier.updateThemeMode(AppThemeMode.system),
        throwsA(isA<WorkspaceException>()),
      );
      expect(
        container.read(webDavConfigProvider).requireValue.themeMode,
        equals(AppThemeMode.dark),
        reason: 'Failed preference persistence must roll back optimistic state',
      );
    });

    test('syncLogToWebDavNow honors logStorageMode.usesWebDav and routes saveLog/deleteLog through webDavRepositoryProvider', () async {
      AppLogger.resetForTesting(clock: () => fixedDate);
      addTearDown(() => AppLogger.resetForTesting());

      const localLogConfig = WebDavConfig(
        serverUrl: 'https://cloud.example.com',
        username: 'alice',
        password: 'secret',
        storageMode: StorageMode.both,
        diagnosticsEnabled: true,
      );
      final spyWebDav = _SpyLogWebDavRepository(config: localLogConfig);
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(localLogConfig),
          ),
          webDavRepositoryProvider.overrideWithValue(spyWebDav),
          clockProvider.overrideWithValue(() => fixedDate),
        ],
      );
      addTearDown(container.dispose);

      await container.read(webDavConfigProvider.future);
      final notifier = container.read(webDavConfigProvider.notifier);

      await notifier.syncLogToWebDavNow();
      expect(
        spyWebDav.saveLogCalls,
        isEmpty,
        reason: 'syncLogToWebDavNow must never upload logs when logStorageMode is local-only',
      );

      await notifier.updateLogStorageMode(StorageMode.both);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        spyWebDav.saveLogCalls,
        hasLength(1),
        reason: 'Switching logStorageMode to both must upload logs via injected webDavRepositoryProvider',
      );

      await notifier.syncLogToWebDavNow();
      expect(
        spyWebDav.saveLogCalls,
        hasLength(2),
        reason: 'syncLogToWebDavNow must route uploads through webDavRepositoryProvider when usesWebDav is true',
      );

      await notifier.updateDiagnosticsEnabled(false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        spyWebDav.deleteLogCalls,
        hasLength(1),
        reason: 'Disabling diagnostics must delete remote log via injected webDavRepositoryProvider',
      );
    });

    test('updateLogStorageMode catches background syncLogToWebDavNow failures and logs a warning without uncaught errors', () async {
      AppLogger.resetForTesting(clock: () => fixedDate);
      addTearDown(() => AppLogger.resetForTesting());

      const initialConfig = WebDavConfig(
        serverUrl: 'https://cloud.example.com',
        username: 'alice',
        password: 'secret',
        storageMode: StorageMode.both,
        diagnosticsEnabled: true,
      );
      final spyWebDav = _SpyLogWebDavRepository(
        config: initialConfig,
        saveLogError: const WebDavException('Simulated log upload timeout'),
      );
      final uncaughtErrors = <Object>[];

      await runZonedGuarded(
        () async {
          final container = ProviderContainer(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(
                InMemorySettingsRepository(initialConfig),
              ),
              webDavRepositoryProvider.overrideWithValue(spyWebDav),
              clockProvider.overrideWithValue(() => fixedDate),
            ],
          );
          addTearDown(container.dispose);
          AppLogger.setEnabled(
            true,
            minimumLevel: LogLevel.info,
            persistToDisk: false,
          );
          await container.read(webDavConfigProvider.future);
          await container
              .read(webDavConfigProvider.notifier)
              .updateLogStorageMode(StorageMode.webdav);
          await Future<void>.delayed(const Duration(milliseconds: 30));
        },
        (error, _) {
          uncaughtErrors.add(error);
        },
      );

      expect(
        uncaughtErrors,
        isEmpty,
        reason: 'updateLogStorageMode must catch fire-and-forget syncLogToWebDavNow failures',
      );
      expect(
        AppLogger.lines.any(
          (line) =>
              line.contains('[WARN ]') &&
              line.contains('log.webdav.sync_failed'),
        ),
        isTrue,
        reason: 'Failed background WebDAV log upload must be logged at LogLevel.warn',
      );
    });

    test('queued updateConfig #2 failure rolls back to succeeded write #1 instead of stale pre-queue config', () async {
      final firstGate = Completer<void>();
      var saveAttempt = 0;
      final settingsRepository = _GateableSettingsRepository(
        const WebDavConfig(
          language: AppLanguage.english,
          themeMode: AppThemeMode.light,
        ),
        onSave: () async {
          saveAttempt++;
          if (saveAttempt == 1) {
            await firstGate.future;
            return;
          }
          throw const WorkspaceException(
            WorkspaceErrorKind.settingsPersistenceFailed,
            'Write #2 failed',
          );
        },
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          clockProvider.overrideWithValue(() => fixedDate),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(webDavConfigProvider, (_, _) {});
      addTearDown(sub.close);

      await container.read(webDavConfigProvider.future);
      final notifier = container.read(webDavConfigProvider.notifier);

      final firstWrite = notifier.updateThemePalette(AppThemePalette.plumUmber);
      final secondWrite = notifier.updateThemeMode(AppThemeMode.dark);

      firstGate.complete();
      await firstWrite;
      await expectLater(secondWrite, throwsA(isA<WorkspaceException>()));

      final resolved = container.read(webDavConfigProvider).requireValue;
      expect(
        resolved.themePalette,
        equals(AppThemePalette.plumUmber),
        reason: 'Write #2 failure must preserve succeeded Write #1 themePalette instead of rolling back to C0',
      );
      expect(
        resolved.themeMode,
        equals(AppThemeMode.light),
        reason: 'Write #2 failure must roll back only its own themeMode edit',
      );
    });

    test('queued Workspace A config write drains before switching to Workspace B and never corrupts Workspace B', () async {
      final saveGate = Completer<void>();
      var gatedFirstSave = false;
      final settingsRepository = _GateableSettingsRepository(
        const WebDavConfig(
          language: AppLanguage.english,
          themeMode: AppThemeMode.light,
        ),
        onSave: () async {
          if (!gatedFirstSave) {
            gatedFirstSave = true;
            await saveGate.future;
          }
        },
      );
      await settingsRepository.createWorkspace(
        'Work',
        id: 'work',
        config: const WebDavConfig(
          language: AppLanguage.german,
          localFilePath: 'work.tdf',
          filePath: 'work.tdf',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          clockProvider.overrideWithValue(() => fixedDate),
        ],
      );
      addTearDown(container.dispose);
      final configSub = container.listen(webDavConfigProvider, (_, _) {});
      addTearDown(configSub.close);

      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);

      // Start a slow write on Workspace A ("tasks"), then immediately switch to Workspace B ("work").
      final writeOnA = container
          .read(webDavConfigProvider.notifier)
          .updateThemeMode(AppThemeMode.dark);
      var switchCompleted = false;
      final switchToB = container
          .read(activeWorkspaceProvider.notifier)
          .switchWorkspace('work')
          .then((workspace) {
            switchCompleted = true;
            return workspace;
          });

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        switchCompleted,
        isFalse,
        reason: 'switchWorkspace must wait for WorkspaceUnloadCoordinator to drain pending Workspace A config writes',
      );

      saveGate.complete();
      await writeOnA;
      final switched = await switchToB;

      expect(switched.id, equals('work'));
      expect(
        switched.config.themeMode,
        equals(AppThemeMode.system),
        reason: 'Workspace B config must never be overwritten by queued Workspace A write',
      );
      expect(
        container.read(webDavConfigProvider).requireValue.themeMode,
        equals(AppThemeMode.system),
      );

      // Switching back to Workspace A must show A's persisted dark mode.
      final backToA = await container
          .read(activeWorkspaceProvider.notifier)
          .switchWorkspace('tasks');
      expect(backToA.config.themeMode, equals(AppThemeMode.dark));

      // Direct updateConfigForWorkspace for inactive Workspace B must persist ONLY to B without overwriting active Workspace A.
      await container
          .read(activeWorkspaceProvider.notifier)
          .updateConfigForWorkspace(
            'work',
            switched.config.copyWith(themePalette: AppThemePalette.plumUmber),
          );
      expect(
        container.read(activeWorkspaceProvider).requireValue.id,
        equals('tasks'),
      );
      expect(
        container.read(webDavConfigProvider).requireValue.themePalette,
        equals(AppThemePalette.calm),
        reason: 'Targeted config persistence for inactive Workspace B must not mutate active Workspace A',
      );
      final reloadedB = await container
          .read(activeWorkspaceProvider.notifier)
          .switchWorkspace('work');
      expect(reloadedB.config.themePalette, equals(AppThemePalette.plumUmber));
    });

    test('changeLocalFileLocation drains WorkspaceUnloadCoordinator before moving file and survives mid-flight disposal', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'tiertask_move_drain_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final sourcePath = '${tempDir.path}${Platform.pathSeparator}old.tdf';
      final targetPath = '${tempDir.path}${Platform.pathSeparator}new.tdf';
      await File(sourcePath).writeAsString('tdf 0.8.0\n', flush: true);

      final unloadGate = Completer<void>();
      var unloadDrainedBeforeMove = false;
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              WebDavConfig(
                storageMode: StorageMode.local,
                localFilePath: sourcePath,
              ),
            ),
          ),
          clockProvider.overrideWithValue(() => fixedDate),
        ],
      );
      addTearDown(container.dispose);

      await container.read(webDavConfigProvider.future);
      final unregister = container
          .read(workspaceUnloadCoordinatorProvider)
          .register(() async {
            await unloadGate.future;
            unloadDrainedBeforeMove = !await File(targetPath).exists();
          });
      addTearDown(unregister);

      final moveFuture = container
          .read(webDavConfigProvider.notifier)
          .changeLocalFileLocation(
            WebDavConfig(
              storageMode: StorageMode.local,
              localFilePath: targetPath,
            ),
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        await File(targetPath).exists(),
        isFalse,
        reason: 'changeLocalFileLocation must not move the file until unload hooks finish draining',
      );

      unloadGate.complete();
      await moveFuture;
      expect(unloadDrainedBeforeMove, isTrue);
      expect(await File(targetPath).exists(), isTrue);

      // Mid-flight disposal during unload drain must exit cleanly without throwing UnmountedRefException.
      final disposeGate = Completer<void>();
      final disposeContainer = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              WebDavConfig(
                storageMode: StorageMode.local,
                localFilePath: targetPath,
              ),
            ),
          ),
          clockProvider.overrideWithValue(() => fixedDate),
        ],
      );
      await disposeContainer.read(webDavConfigProvider.future);
      disposeContainer
          .read(workspaceUnloadCoordinatorProvider)
          .register(() => disposeGate.future);
      final abortedMove = disposeContainer
          .read(webDavConfigProvider.notifier)
          .changeLocalFileLocation(
            WebDavConfig(
              storageMode: StorageMode.local,
              localFilePath: sourcePath,
            ),
          );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      disposeContainer.dispose();
      disposeGate.complete();
      await expectLater(abortedMove, completes);
      expect(
        await File(targetPath).exists(),
        isTrue,
        reason: 'Aborted move after disposal must leave the file in place',
      );
    });

    test('webDavRepositoryProvider closes pooled HttpClient on dispose and binding change, while language switches preserve WebDavRepository ETag cache and LocalFileRepository instance', () async {
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.set(HttpHeaders.etagHeader, '"etag-v1"')
          ..write('tdf 0.8.0\n');
        await request.response.close();
      });

      final createdClients = <_CloseTrackingHttpClient>[];
      await HttpOverrides.runWithHttpOverrides(() async {
        final settingsRepo = InMemorySettingsRepository(
          WebDavConfig(
            language: AppLanguage.english,
            storageMode: StorageMode.both,
            serverUrl: 'http://127.0.0.1:${server.port}',
            username: 'alice',
            password: 'secret',
          ),
        );
        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepo),
            localStorageDirectoryPathProvider.overrideWithValue(sourceDir.path),
            clockProvider.overrideWithValue(() => fixedDate),
          ],
        );

        await container.read(activeWorkspaceProvider.future);
        await container.read(webDavConfigProvider.future);

        final webDavSub = container.listen(webDavRepositoryProvider, (_, _) {});
        final localSub = container.listen(
          localFileRepositoryProvider,
          (_, _) {},
        );
        final webDavBefore = container.read(webDavRepositoryProvider);
        final localBefore = container.read(localFileRepositoryProvider);

        await webDavBefore.fetchTdf();
        expect(webDavBefore.cachedEtag, equals('"etag-v1"'));
        expect(createdClients, hasLength(1));
        expect(createdClients.single.closeCalls, equals(0));

        // Language switch en -> de must NOT recreate WebDavRepository or LocalFileRepository, nor close pooled HttpClient.
        await container
            .read(webDavConfigProvider.notifier)
            .updateLanguage(AppLanguage.german);
        final webDavAfterLang = container.read(webDavRepositoryProvider);
        final localAfterLang = container.read(localFileRepositoryProvider);
        expect(
          webDavAfterLang,
          same(webDavBefore),
          reason: 'Switching language must preserve WebDavRepository instance and ETag cache',
        );
        expect(webDavAfterLang.cachedEtag, equals('"etag-v1"'));
        expect(createdClients.single.closeCalls, equals(0));
        expect(
          localAfterLang,
          same(localBefore),
          reason:
              'Switching language must preserve LocalFileRepository instance',
        );
        expect(
          () => localAfterLang.renameTdf('../bad.tdf'),
          throwsA(
            isA<LocalFileException>().having(
              (error) => error.message,
              'message',
              equals(AppLocalizationsDe().localFileNameErrorInvalid),
            ),
          ),
          reason: 'Preserved LocalFileRepository must still localize errors dynamically in German',
        );

        // Changing serverUrl recreates WebDavRepository and closes the old pooled HttpClient.
        final nextConfig = container
            .read(webDavConfigProvider)
            .requireValue
            .copyWith(filePath: 'other.tdf');
        await container
            .read(webDavConfigProvider.notifier)
            .updateConfig(nextConfig);
        final webDavAfterPathChange = container.read(webDavRepositoryProvider);
        expect(webDavAfterPathChange, isNot(same(webDavBefore)));
        expect(
          createdClients.first.closeCalls,
          equals(1),
          reason: 'Replacing webDavRepositoryProvider must close the prior pooled HttpClient',
        );

        await webDavAfterPathChange.fetchTdf();
        expect(createdClients, hasLength(2));
        expect(createdClients.last.closeCalls, equals(0));

        webDavSub.close();
        localSub.close();
        container.dispose();
        expect(
          createdClients.last.closeCalls,
          equals(1),
          reason: 'Disposing ProviderContainer must close webDavRepositoryProvider pooled HttpClient',
        );
      }, _TrackingHttpOverrides(createdClients));
    });

    test('toggling diagnosticsEnabled while diagnosticsEnabledProvider is watched invokes AppLogger.setEnabled exactly once per toggle', () async {
      AppLogger.resetForTesting(clock: () => fixedDate);
      addTearDown(AppLogger.resetForTesting);

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const WebDavConfig(language: AppLanguage.english),
            ),
          ),
          localStorageDirectoryPathProvider.overrideWithValue(sourceDir.path),
          clockProvider.overrideWithValue(() => fixedDate),
        ],
      );
      addTearDown(container.dispose);

      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);
      final diagSub = container.listen(diagnosticsEnabledProvider, (_, _) {});
      addTearDown(diagSub.close);

      final notifier = container.read(webDavConfigProvider.notifier);
      expect(
        notifier.loggerSyncApplyCountForTesting,
        equals(0),
        reason: 'Disabled startup must not invoke AppLogger.setEnabled',
      );

      await notifier.updateDiagnosticsEnabled(true);
      expect(container.read(diagnosticsEnabledProvider), isTrue);
      expect(AppLogger.isEnabled, isTrue);
      expect(
        notifier.loggerSyncApplyCountForTesting,
        equals(1),
        reason: 'Enabling diagnostics must invoke AppLogger.setEnabled exactly once',
      );

      await notifier.updateDiagnosticsEnabled(false);
      expect(container.read(diagnosticsEnabledProvider), isFalse);
      expect(AppLogger.isEnabled, isFalse);
      expect(
        notifier.loggerSyncApplyCountForTesting,
        equals(2),
        reason: 'Disabling diagnostics must invoke AppLogger.setEnabled exactly once',
      );
    });
  });
}

class _TrackingHttpOverrides extends HttpOverrides {
  _TrackingHttpOverrides(this.createdClients);

  final List<_CloseTrackingHttpClient> createdClients;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = _CloseTrackingHttpClient(super.createHttpClient(context));
    createdClients.add(client);
    return client;
  }
}

class _CloseTrackingHttpClient implements HttpClient {
  _CloseTrackingHttpClient(this._delegate);

  final HttpClient _delegate;
  int closeCalls = 0;

  @override
  Duration? get connectionTimeout => _delegate.connectionTimeout;

  @override
  set connectionTimeout(Duration? value) {
    _delegate.connectionTimeout = value;
  }

  @override
  void close({bool force = false}) {
    closeCalls++;
    _delegate.close(force: force);
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _delegate.getUrl(url);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _delegate.openUrl(method, url);

  @override
  Future<HttpClientRequest> putUrl(Uri url) => _delegate.putUrl(url);

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _delegate.deleteUrl(url);

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _GateableSettingsRepository extends InMemorySettingsRepository {
  _GateableSettingsRepository(super.initialConfig, {required this.onSave});

  final Future<void> Function() onSave;

  @override
  Future<void> saveConfig(WebDavConfig config) async {
    await onSave();
    await super.saveConfig(config);
  }

  @override
  Future<void> saveConfigForWorkspace(
    String workspaceId,
    WebDavConfig config,
  ) async {
    await onSave();
    await super.saveConfigForWorkspace(workspaceId, config);
  }
}

class _SpyLogWebDavRepository extends WebDavRepository {
  _SpyLogWebDavRepository({required super.config, this.saveLogError});

  final List<String> deleteLogCalls = <String>[];
  final List<String> saveLogCalls = <String>[];
  final Exception? saveLogError;

  @override
  Future<void> deleteLog(String logFileName) async {
    deleteLogCalls.add(logFileName);
  }

  @override
  Future<void> saveLog(String logFileName, [String? logContent]) async {
    saveLogCalls.add(logFileName);
    if (saveLogError case final error?) {
      throw error;
    }
  }
}

/// Verifies that [arbMap] defines an `@<key>` metadata map with a non-empty description.
void _expectArbKeyMetadata(Map<String, Object?> arbMap, String key) {
  final metadataKey = '@$key';
  final metadata = arbMap[metadataKey];
  expect(
    metadata,
    isA<Map<String, Object?>>(),
    reason:
        'The message with key "$key" must have $metadataKey metadata defined',
  );
  if (metadata is! Map<String, Object?>) {
    return;
  }

  final description = metadata['description'];
  expect(
    description,
    isA<String>(),
    reason: 'Metadata $metadataKey must define a description string',
  );
  if (description is String) {
    expect(
      description.trim(),
      isNotEmpty,
      reason: 'Metadata $metadataKey description must not be empty',
    );
  }
}
