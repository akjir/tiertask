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
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/app_version_repository.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/app_logger.dart';

void main() {
  final fixedDate = DateTime.utc(2026, 11, 1, 12, 0);

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

    test('WebDavConfigNotifier updates preferences synchronously without dropping through AsyncLoading', () async {
      final settingsRepository = InMemorySettingsRepository(
        const WebDavConfig(
          language: AppLanguage.english,
          themePalette: AppThemePalette.calm,
          themeMode: AppThemeMode.light,
          storageMode: StorageMode.both,
          serverUrl: 'https://cloud.example.com',
          username: 'alice',
          password: 'secret',
          filePath: 'tasks.tdf',
          localFilePath: 'tasks.tdf',
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
          themePalette: AppThemePalette.calm,
          themeMode: AppThemeMode.light,
          storageMode: StorageMode.both,
          serverUrl: 'https://cloud.example.com',
          username: 'alice',
          password: 'secret',
          filePath: 'tasks.tdf',
          localFilePath: 'tasks.tdf',
          diagnosticsEnabled: true,
          logLevel: LogLevel.info,
          logStorageMode: StorageMode.local,
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
  });
}

class _GateableSettingsRepository extends InMemorySettingsRepository {
  _GateableSettingsRepository(super.initialConfig, {required this.onSave});

  final Future<void> Function() onSave;

  @override
  Future<void> saveConfig(WebDavConfig config) async {
    await onSave();
    await super.saveConfig(config);
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
