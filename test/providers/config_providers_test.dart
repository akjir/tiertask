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
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
        expect(AppLanguage.fromId(2), equals(AppLanguage.german));
        expect(AppLanguage.fromId(1), equals(AppLanguage.english));
        expect(AppLanguage.fromId(0), equals(AppLanguage.system));
        expect(AppLanguage.fromId(99), equals(AppLanguage.system));
      },
    );

    test('resolves AppThemeMode and StorageMode binary IDs with system and local tasks.tdf defaults', () {
      expect(AppThemeMode.fromId(1), equals(AppThemeMode.light));
      expect(AppThemeMode.fromId(2), equals(AppThemeMode.dark));
      expect(AppThemeMode.fromId(0), equals(AppThemeMode.system));
      expect(AppThemeMode.fromId(99), equals(AppThemeMode.system));

      expect(StorageMode.fromId(0), equals(StorageMode.local));
      expect(StorageMode.fromId(1), equals(StorageMode.webdav));
      expect(StorageMode.fromId(2), equals(StorageMode.both));
      expect(StorageMode.fromId(99), equals(StorageMode.local));

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

      expect(enMessageKeys, contains('sectionReadyTasks'));
      expect(enMessageKeys, contains('sectionLabels'));
      expect(enMessageKeys, contains('drawerLabels'));
      expect(enMessageKeys, contains('emptyLabelsHint'));
      expect(deMessageKeys, equals(enMessageKeys));

      for (final key in enMessageKeys) {
        _expectArbKeyMetadata(enDecoded, key);
      }
    });

    test('Linux, Windows, and Android platform runners and manifests display TierTask as the taskbar and window title', () {
      final linuxRunner = File('linux/runner/my_application.cc')
          .readAsStringSync();
      expect(
        linuxRunner,
        contains('gtk_header_bar_set_title(header_bar, "TierTask");'),
      );
      expect(
        linuxRunner,
        contains('gtk_window_set_title(window, "TierTask");'),
      );
      expect(linuxRunner, contains('g_set_application_name("TierTask");'));

      final windowsMain = File('windows/runner/main.cpp').readAsStringSync();
      expect(windowsMain, contains('window.Create(L"TierTask", origin, size)'));

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
        equals(AppThemePalette.slate),
      );
      expect(container.read(diagnosticsEnabledProvider), isFalse);

      final notifier = container.read(webDavConfigProvider.notifier);
      await notifier.updateLanguage(AppLanguage.german);
      expect(container.read(appLocaleProvider), equals(const Locale('de')));

      await notifier.updateThemeMode(AppThemeMode.dark);
      expect(container.read(appThemeModeProvider), equals(AppThemeMode.dark));

      await notifier.updateThemePalette(AppThemePalette.navy);
      expect(
        container.read(appThemePaletteProvider),
        equals(AppThemePalette.navy),
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
        'tdf 0.5.1\n\ntask 000001OkD2 {\n    name "Keep Safe"\n    created 2026-11-01 08:00:00\n    modified 2026-11-01 08:00:00\n}\n',
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
  });
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
