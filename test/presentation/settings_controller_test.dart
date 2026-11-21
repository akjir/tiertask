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

import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/l10n/tier_localization_extension.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/settings_codec.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/presentation/log_viewer_controller.dart';
import 'package:tiertask/presentation/settings_controller.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/app_logger.dart';

class _RecordingWebDavConfigNotifier extends WebDavConfigNotifier {
  _RecordingWebDavConfigNotifier({required this.initialConfig});

  final WebDavConfig initialConfig;
  WorkspaceException? errorToThrow;
  final List<String> calls = <String>[];

  @override
  Future<WebDavConfig> build() async => initialConfig;

  @override
  Future<void> updateConfig(WebDavConfig newConfig) async {
    calls.add('updateConfig');
    if (errorToThrow case final error?) {
      throw error;
    }
    state = AsyncData<WebDavConfig>(newConfig);
  }

  @override
  Future<void> updateDiagnosticsEnabled(bool diagnosticsEnabled) async {
    calls.add('updateDiagnosticsEnabled:$diagnosticsEnabled');
    if (errorToThrow case final error?) {
      throw error;
    }
    final current = state.asData?.value ?? initialConfig;
    state = AsyncData<WebDavConfig>(
      current.copyWith(diagnosticsEnabled: diagnosticsEnabled),
    );
  }

  @override
  Future<void> updateDueLeadWindow(DueLeadWindow dueLeadWindow) async {
    calls.add('updateDueLeadWindow:${dueLeadWindow.name}');
    final current = state.asData?.value ?? initialConfig;
    state = AsyncData<WebDavConfig>(
      current.copyWith(dueLeadWindow: dueLeadWindow),
    );
  }

  @override
  Future<void> updateLocalWatchEnabled(bool localWatchEnabled) async {
    calls.add('updateLocalWatchEnabled:$localWatchEnabled');
    final current = state.asData?.value ?? initialConfig;
    state = AsyncData<WebDavConfig>(
      current.copyWith(localWatchEnabled: localWatchEnabled),
    );
  }

  @override
  Future<void> updateLogLevel(LogLevel logLevel) async {
    calls.add('updateLogLevel:${logLevel.label}');
    final current = state.asData?.value ?? initialConfig;
    state = AsyncData<WebDavConfig>(current.copyWith(logLevel: logLevel));
  }

  @override
  Future<void> updateLogStorageMode(StorageMode logStorageMode) async {
    calls.add('updateLogStorageMode:${logStorageMode.name}');
    final current = state.asData?.value ?? initialConfig;
    state = AsyncData<WebDavConfig>(
      current.copyWith(logStorageMode: logStorageMode),
    );
  }
}

void main() {
  group('SettingsController log-level bridging and picker capability', () {
    test(
      'round-trips every configurable DiagnosticLogLevel with WebDavConfig',
      () {
        const base = WebDavConfig();
        for (final level in DiagnosticLogLevel.configurableLevels) {
          final updated = SettingsController.withLogLevel(base, level);
          expect(
            SettingsController.readLogLevel(updated),
            equals(level),
            reason: 'Expected round-trip for $level',
          );
        }
      },
    );

    test(
      'exposes supportsNativeDirectoryPickerProvider and controller getter',
      () {
        final container = ProviderContainer(
          overrides: [supportsDirectoryPickerProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);

        expect(container.read(supportsNativeDirectoryPickerProvider), isTrue);
        expect(
          container
              .read(settingsControllerProvider)
              .supportsNativeDirectoryPicker,
          isTrue,
        );
      },
    );
  });

  group('SettingsController startup recovery notice', () {
    test('returns null when no notice exists and localizes backup/quarantine notices once', () {
      final emptyContainer = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(),
          ),
        ],
      );
      addTearDown(emptyContainer.dispose);
      expect(
        emptyContainer
            .read(settingsControllerProvider)
            .consumeStartupRecoveryNotice(),
        isNull,
      );

      for (final locale in const <Locale>[Locale('en'), Locale('de')]) {
        final localizations = lookupAppLocalizations(locale);
        final backupContainer = ProviderContainer(
          overrides: [
            appLocaleProvider.overrideWithValue(locale),
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository.withRecoveryNotice(
                recoveryNotice: const SettingsRecoveryNotice(
                  kind: SettingsRecoveryKind.recoveredFromBackup,
                ),
              ),
            ),
          ],
        );
        addTearDown(backupContainer.dispose);
        final backupController = backupContainer.read(
          settingsControllerProvider,
        );
        expect(
          backupController.consumeStartupRecoveryNotice(),
          equals(localizations.settingsRecoveredFromBackupNotice),
          reason: 'Recovered backup notice mismatch for ${locale.languageCode}',
        );
        expect(backupController.consumeStartupRecoveryNotice(), isNull);

        final quarantineContainer = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository.withRecoveryNotice(
                recoveryNotice: const SettingsRecoveryNotice(
                  kind: SettingsRecoveryKind.resetAfterQuarantine,
                ),
              ),
            ),
          ],
        );
        addTearDown(quarantineContainer.dispose);
        expect(
          quarantineContainer
              .read(settingsControllerProvider)
              .consumeStartupRecoveryNotice(locale: locale),
          equals(localizations.settingsResetAfterQuarantineNotice),
          reason:
              'Reset after quarantine notice mismatch for ${locale.languageCode}',
        );
      }
    });
  });

  group('SettingsController local storage paths and pickers', () {
    test(
      'resolves preview path, lists directory files, and picks directory/file',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'tiertask_settings_ctrl_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final sep = Platform.pathSeparator;
        File('${tempDir.path}${sep}alpha.tdf').writeAsStringSync('tdf 0.8.0\n');
        File('${tempDir.path}${sep}tasks.tdf').writeAsStringSync('tdf 0.8.0\n');

        String? pickedDirectory = '/mock/moved';
        String? pickedFile = '/mock/other/selected.tdf';
        String? capturedInitialDir;
        String? capturedFileName;

        final container = ProviderContainer(
          overrides: [
            localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
            localFileRepositoryProvider.overrideWithValue(
              LocalFileRepository(
                config: WebDavConfig(
                  localFilePath: '${tempDir.path}${sep}tasks.tdf',
                ),
                baseDirectoryPath: tempDir.path,
              ),
            ),
            directoryPickerProvider.overrideWithValue(({
              String? initialDirectory,
            }) async {
              capturedInitialDir = initialDirectory;
              return pickedDirectory;
            }),
            filePickerProvider.overrideWithValue(({
              String? initialDirectory,
              String? currentFileName,
            }) async {
              capturedInitialDir = initialDirectory;
              capturedFileName = currentFileName;
              return pickedFile;
            }),
          ],
        );
        addTearDown(container.dispose);

        final controller = container.read(settingsControllerProvider);
        const config = WebDavConfig(localFilePath: 'tasks.tdf');

        expect(
          controller.resolvePreviewLocalPath(config),
          equals('${tempDir.path}${sep}tasks.tdf'),
        );
        expect(
          controller.listLocalTdfFileNames(),
          equals(const <String>['alpha.tdf', 'tasks.tdf']),
        );

        final moved = await controller.pickLocalDirectory(config);
        expect(capturedInitialDir, equals(tempDir.path));
        expect(moved, equals('/mock/moved${sep}tasks.tdf'));

        // Unchanged or cancelled directory picker returns null.
        pickedDirectory = tempDir.path;
        expect(await controller.pickLocalDirectory(config), isNull);
        pickedDirectory = null;
        expect(await controller.pickLocalDirectory(config), isNull);

        final selected = await controller.pickNativeLocalFile(config);
        expect(capturedFileName, equals('tasks.tdf'));
        expect(selected, equals('/mock/other/selected.tdf'));

        expect(
          controller.resolveChosenLocalFileName(config, 'renamed.tdf'),
          equals('${tempDir.path}${sep}renamed.tdf'),
        );

        // Must always follow host Platform.pathSeparator even when Flutter's
        // defaultTargetPlatform differs (e.g., TargetPlatform.android during Windows tests).
        final mismatchedPlatform = Platform.isWindows
            ? TargetPlatform.android
            : TargetPlatform.windows;
        debugDefaultTargetPlatformOverride = mismatchedPlatform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        pickedDirectory = '/mock/moved';
        expect(
          await controller.pickLocalDirectory(config),
          equals('/mock/moved${sep}tasks.tdf'),
          reason: 'pickLocalDirectory must use host Platform.pathSeparator regardless of defaultTargetPlatform',
        );
        expect(
          controller.resolveChosenLocalFileName(config, 'renamed.tdf'),
          equals('${tempDir.path}${sep}renamed.tdf'),
          reason: 'resolveChosenLocalFileName must use host Platform.pathSeparator regardless of defaultTargetPlatform',
        );
      },
    );

    test('resolveChosenLocalFileName preserves bare filename when no base directory or separator exists', () {
      final container = ProviderContainer(
        overrides: [localStorageDirectoryPathProvider.overrideWithValue(null)],
      );
      addTearDown(container.dispose);

      final controller = container.read(settingsControllerProvider);
      expect(
        controller.resolveChosenLocalFileName(
          const WebDavConfig(localFilePath: 'tasks.tdf'),
          'notes.tdf',
        ),
        equals('notes.tdf'),
      );
    });
  });

  group('SettingsController.savePreferenceChange', () {
    test('routes specialized preference diffs and maps WorkspaceException failures', () async {
      const base = WebDavConfig();
      final notifier = _RecordingWebDavConfigNotifier(initialConfig: base);
      final container = ProviderContainer(
        overrides: [
          webDavConfigProvider.overrideWith(() => notifier),
          appLocaleProvider.overrideWithValue(const Locale('en')),
        ],
      );
      addTearDown(container.dispose);
      await container.read(webDavConfigProvider.future);

      final controller = container.read(settingsControllerProvider);

      final diagResult = await controller.savePreferenceChange(
        previous: base,
        next: base.copyWith(diagnosticsEnabled: true),
      );
      expect(diagResult, isA<SettingsPreferenceSaved>());
      expect(notifier.calls.last, equals('updateDiagnosticsEnabled:true'));

      await controller.savePreferenceChange(
        previous: base,
        next: base.copyWith(dueLeadWindow: DueLeadWindow.hours48),
      );
      expect(notifier.calls.last, equals('updateDueLeadWindow:hours48'));

      await controller.savePreferenceChange(
        previous: base,
        next: base.copyWith(localWatchEnabled: false),
      );
      expect(notifier.calls.last, equals('updateLocalWatchEnabled:false'));

      await controller.savePreferenceChange(
        previous: base,
        next: base.copyWith(logLevel: LogLevel.debug),
      );
      expect(notifier.calls.last, equals('updateLogLevel:DEBUG'));

      await controller.savePreferenceChange(
        previous: base,
        next: base.copyWith(logStorageMode: StorageMode.both),
      );
      expect(notifier.calls.last, equals('updateLogStorageMode:both'));

      await controller.savePreferenceChange(
        previous: base,
        next: base.copyWith(themeMode: AppThemeMode.dark),
      );
      expect(notifier.calls.last, equals('updateConfig'));

      notifier.errorToThrow = const WorkspaceException(
        WorkspaceErrorKind.duplicateFilePath,
        'Duplicate path',
      );
      final failed = await controller.savePreferenceChange(
        previous: base,
        next: base.copyWith(themeMode: AppThemeMode.light),
        locale: const Locale('de'),
      );
      expect(failed, isA<SettingsPreferenceSaveFailed>());
      expect(
        (failed as SettingsPreferenceSaveFailed).localizedMessage,
        equals(
          lookupAppLocalizations(const Locale('de')).localizeWorkspaceError(
            const WorkspaceException(
              WorkspaceErrorKind.duplicateFilePath,
              'Duplicate path',
            ),
          ),
        ),
      );
    });
  });
}
