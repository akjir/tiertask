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
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/l10n/tier_localization_extension.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/storage_file_read_status.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/presentation/app_shell_controller.dart';
import 'package:tiertask/presentation/log_viewer_controller.dart';
import 'package:tiertask/presentation/settings_controller.dart';
import 'package:tiertask/presentation/shell_models.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/sync_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/services/tdf_service.dart';

import '../ui/test_helpers.dart';

class _RecordingWebDavConfigNotifier extends WebDavConfigNotifier {
  _RecordingWebDavConfigNotifier({required this.initialConfig});

  final WebDavConfig initialConfig;
  final List<String> calls = <String>[];
  Object? changeLocationErrorToThrow;
  Completer<void>? pendingUpdateCompleter;
  WorkspaceException? updateErrorToThrow;

  @override
  Future<WebDavConfig> build() async => initialConfig;

  @override
  Future<void> changeLocalFileLocation(WebDavConfig newConfig) async {
    calls.add('changeLocalFileLocation:${newConfig.localFilePath}');
    if (pendingUpdateCompleter case final completer?) {
      await completer.future;
    }
    if (changeLocationErrorToThrow case final error?) {
      throw error;
    }
    state = AsyncData<WebDavConfig>(newConfig);
  }

  @override
  Future<void> updateConfig(WebDavConfig newConfig) async {
    calls.add('updateConfig');
    if (pendingUpdateCompleter case final completer?) {
      await completer.future;
    }
    if (updateErrorToThrow case final error?) {
      throw error;
    }
    state = AsyncData<WebDavConfig>(newConfig);
  }

  @override
  Future<void> updateDiagnosticsEnabled(bool diagnosticsEnabled) async {
    calls.add('updateDiagnosticsEnabled:$diagnosticsEnabled');
    if (updateErrorToThrow case final error?) {
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
    if (updateErrorToThrow case final error?) {
      throw error;
    }
    final current = state.asData?.value ?? initialConfig;
    state = AsyncData<WebDavConfig>(
      current.copyWith(dueLeadWindow: dueLeadWindow),
    );
  }

  @override
  Future<void> updateLocalWatchEnabled(bool localWatchEnabled) async {
    calls.add('updateLocalWatchEnabled:$localWatchEnabled');
    if (updateErrorToThrow case final error?) {
      throw error;
    }
    final current = state.asData?.value ?? initialConfig;
    state = AsyncData<WebDavConfig>(
      current.copyWith(localWatchEnabled: localWatchEnabled),
    );
  }

  @override
  Future<void> updateLogLevel(LogLevel logLevel) async {
    calls.add('updateLogLevel:${logLevel.label}');
    if (updateErrorToThrow case final error?) {
      throw error;
    }
    final current = state.asData?.value ?? initialConfig;
    state = AsyncData<WebDavConfig>(current.copyWith(logLevel: logLevel));
  }

  @override
  Future<void> updateLogStorageMode(StorageMode logStorageMode) async {
    calls.add('updateLogStorageMode:${logStorageMode.name}');
    if (updateErrorToThrow case final error?) {
      throw error;
    }
    final current = state.asData?.value ?? initialConfig;
    state = AsyncData<WebDavConfig>(
      current.copyWith(logStorageMode: logStorageMode),
    );
  }
}

class _RecordingTaskNotifier extends FakeTaskNotifier {
  _RecordingTaskNotifier([super.initialBoard]);

  final List<String> calls = <String>[];
  WebDavConfig? lastSelectedLocalConfig;
  WebDavConfig? lastTestedConfig;
  bool? lastWipeCreateBackup;
  Completer<void>? pendingActionCompleter;
  Object? selectLocalErrorToThrow;
  Object? testSyncErrorToThrow;
  Object? wipeLocalErrorToThrow;
  Object? wipeRemoteErrorToThrow;

  @override
  Future<void> selectLocalFile(WebDavConfig newConfig) async {
    calls.add('selectLocalFile:${newConfig.localFilePath}');
    lastSelectedLocalConfig = newConfig;
    if (pendingActionCompleter case final completer?) {
      await completer.future;
    }
    if (selectLocalErrorToThrow case final error?) {
      throw error;
    }
    await ref.read(webDavConfigProvider.notifier).updateConfig(newConfig);
  }

  @override
  Future<void> testConnectionAndSync(WebDavConfig config) async {
    calls.add('testConnectionAndSync:${config.serverUrl}');
    lastTestedConfig = config;
    if (pendingActionCompleter case final completer?) {
      await completer.future;
    }
    if (testSyncErrorToThrow case final error?) {
      throw error;
    }
    await ref.read(webDavConfigProvider.notifier).updateConfig(config);
  }

  @override
  Future<void> wipeLocalFile(
    WebDavConfig config, {
    bool createBackup = false,
  }) async {
    calls.add('wipeLocalFile:$createBackup');
    lastWipeCreateBackup = createBackup;
    if (pendingActionCompleter case final completer?) {
      await completer.future;
    }
    if (wipeLocalErrorToThrow case final error?) {
      throw error;
    }
  }

  @override
  Future<void> wipeRemoteFile(
    WebDavConfig config, {
    bool createBackup = false,
  }) async {
    calls.add('wipeRemoteFile:$createBackup');
    lastWipeCreateBackup = createBackup;
    if (pendingActionCompleter case final completer?) {
      await completer.future;
    }
    if (wipeRemoteErrorToThrow case final error?) {
      throw error;
    }
  }
}

void main() {
  const configuredWebDav = WebDavConfig(
    serverUrl: 'https://cloud.example.com',
    username: 'alice',
    password: 'super-secret-password',
    filePath: 'notes/tasks.tdf',
    localFilePath: 'tasks.tdf',
    storageMode: StorageMode.both,
    language: AppLanguage.english,
  );

  void enableInMemoryLogger() {
    AppLogger.setEnabled(
      true,
      minimumLevel: LogLevel.debug,
      persistToDisk: false,
    );
    AppLogger.clear();
  }

  tearDown(() {
    AppLogger.setEnabled(false);
    AppLogger.clear();
  });

  group('SettingsController projection and value models', () {
    test(
      'projects all 37 supported UTC offsets and initial workspace settings',
      () async {
        final settingsRepository = InMemorySettingsRepository(configuredWebDav);
        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepository),
            supportsDirectoryPickerProvider.overrideWithValue(true),
            localStorageDirectoryPathProvider.overrideWithValue('/tmp/tt'),
            localFileRepositoryProvider.overrideWith(
              (ref) => FakeLocalFileRepository(
                config: configuredWebDav,
                initialTdf: 'tdf ${TdfService.supportedVersion}\n',
              ),
            ),
            taskNotifierProvider.overrideWith(_RecordingTaskNotifier.new),
          ],
        );
        addTearDown(container.dispose);
        await container.read(activeWorkspaceProvider.future);
        await container.read(webDavConfigProvider.future);

        final viewModel = container.read(settingsControllerProvider);
        expect(viewModel.workspaceName, equals(AppWorkspace.defaultName));
        expect(viewModel.supportedUtcOffsets, hasLength(37));
        for (
          var i = 0;
          i < WebDavConfig.supportedUtcOffsetMinutes.length;
          i++
        ) {
          final minutes = WebDavConfig.supportedUtcOffsetMinutes[i];
          expect(
            viewModel.supportedUtcOffsets[i],
            equals(
              UtcOffsetOptionViewModel(
                offsetMinutes: minutes,
                label: WebDavConfig.formatUtcOffset(minutes),
              ),
            ),
            reason: 'UTC offset entry mismatch at index $i ($minutes)',
          );
        }
        expect(viewModel.language, equals(ShellLanguageOption.english));
        expect(viewModel.themeMode, equals(ShellThemeMode.system));
        expect(viewModel.themePalette, equals(AppThemePresetKey.calm));
        expect(viewModel.timeZoneMode, equals(ShellTimeZoneMode.automatic));
        expect(viewModel.manualTimeZoneOffsetMinutes, equals(0));
        expect(viewModel.dueLeadWindow, equals(ShellDueLeadOption.hours24));
        expect(viewModel.locationEnabled, isFalse);
        expect(viewModel.diagnosticsEnabled, isFalse);
        expect(viewModel.logLevel, equals(DiagnosticLogLevel.info));
        expect(viewModel.logStorageMode, equals(ShellStorageMode.local));
        expect(viewModel.storageMode, equals(ShellStorageMode.both));
        expect(viewModel.localFileName, equals('tasks.tdf'));
        expect(viewModel.localFileBaseName, equals('tasks'));
        expect(
          viewModel.resolvedLocalPath,
          equals('/tmp/tt${Platform.pathSeparator}tasks.tdf'),
        );
        expect(viewModel.localWatchEnabled, isTrue);
        expect(viewModel.supportsNativeDirectoryPicker, isTrue);
        expect(viewModel.webDavServerUrl, equals('https://cloud.example.com'));
        expect(viewModel.webDavUsername, equals('alice'));
        expect(viewModel.webDavPassword, equals('super-secret-password'));
        expect(viewModel.webDavFilePath, equals('notes/tasks.tdf'));
        expect(viewModel.remoteFileBaseName, equals('tasks'));
        expect(
          viewModel.resolvedWebDavEndpoint,
          equals(
            'https://cloud.example.com/remote.php/dav/files/alice/notes/tasks.tdf',
          ),
        );
        expect(viewModel.isWebDavDirty, isFalse);
        expect(viewModel.isWebDavConfigured, isTrue);
        expect(viewModel.canTestConnectionAndSync, isTrue);
        expect(viewModel.isBusy, isFalse);
        expect(viewModel.serverUrlError, isNull);
        expect(viewModel.usernameError, isNull);
        expect(viewModel.passwordError, isNull);
        expect(viewModel.filePathError, isNull);
        expect(viewModel.statusBanner, isNull);
        expect(
          viewModel.toString(),
          isNot(contains('super-secret-password')),
          reason: 'SettingsViewModel.toString must redact WebDAV password',
        );
      },
    );

    test('supports value equality, hashCode, and copyWith clear flags on view models', () {
      const offsetA = UtcOffsetOptionViewModel(
        offsetMinutes: 60,
        label: 'UTC+01:00',
      );
      const offsetB = UtcOffsetOptionViewModel(
        offsetMinutes: 60,
        label: 'UTC+01:00',
      );
      expect(offsetA, equals(offsetB));
      expect(offsetA.hashCode, equals(offsetB.hashCode));

      const bannerA = SettingsStatusBannerViewModel(
        tone: BannerTone.success,
        message: 'Saved',
      );
      const bannerB = SettingsStatusBannerViewModel(
        tone: BannerTone.success,
        message: 'Saved',
      );
      expect(bannerA, equals(bannerB));
      expect(bannerA.hashCode, equals(bannerB.hashCode));

      final base = SettingsViewModel(
        workspaceName: 'Tasks',
        language: ShellLanguageOption.system,
        themeMode: ShellThemeMode.system,
        themePalette: AppThemePresetKey.calm,
        timeZoneMode: ShellTimeZoneMode.automatic,
        manualTimeZoneOffsetMinutes: 0,
        supportedUtcOffsets: const <UtcOffsetOptionViewModel>[offsetA],
        dueLeadWindow: ShellDueLeadOption.hours24,
        locationEnabled: false,
        diagnosticsEnabled: false,
        logLevel: DiagnosticLogLevel.info,
        logStorageMode: ShellStorageMode.local,
        activeLogFileName: '',
        storageMode: ShellStorageMode.local,
        localFileName: 'tasks.tdf',
        localFileBaseName: 'tasks',
        resolvedLocalPath: '/tmp/tasks.tdf',
        localWatchEnabled: true,
        supportsNativeDirectoryPicker: true,
        webDavServerUrl: '',
        webDavUsername: '',
        webDavPassword: '',
        webDavFilePath: 'tasks.tdf',
        remoteFileBaseName: 'tasks',
        resolvedWebDavEndpoint: '',
        isWebDavDirty: false,
        isWebDavConfigured: false,
        canTestConnectionAndSync: false,
        isBusy: false,
        serverUrlError: 'bad url',
        usernameError: 'bad user',
        passwordError: 'bad pass',
        filePathError: 'bad path',
        statusBanner: bannerA,
      );
      final identicalCopy = base.copyWith();
      expect(identicalCopy, equals(base));
      expect(identicalCopy.hashCode, equals(base.hashCode));

      final cleared = base.copyWith(
        clearServerUrlError: true,
        clearUsernameError: true,
        clearPasswordError: true,
        clearFilePathError: true,
        clearStatusBanner: true,
      );
      expect(cleared.serverUrlError, isNull);
      expect(cleared.usernameError, isNull);
      expect(cleared.passwordError, isNull);
      expect(cleared.filePathError, isNull);
      expect(cleared.statusBanner, isNull);
      expect(cleared, isNot(equals(base)));
    });
  });

  group('SettingsController auto-saved preferences and rollback', () {
    test('persists every auto-saved preference exhaustively without clobbering dirty WebDAV draft', () async {
      final configNotifier = _RecordingWebDavConfigNotifier(
        initialConfig: configuredWebDav,
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(configuredWebDav),
          ),
          webDavConfigProvider.overrideWith(() => configNotifier),
          appLocaleProvider.overrideWithValue(const Locale('en')),
          diagnosticsEnabledProvider.overrideWithValue(true),
          taskNotifierProvider.overrideWith(_RecordingTaskNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);
      final subscription = container.listen(
        settingsControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      final controller = container.read(settingsControllerProvider.notifier);
      controller.updateWebDavDraft(serverUrl: 'https://unsaved.example.com');
      expect(container.read(settingsControllerProvider).isWebDavDirty, isTrue);

      for (final option in ShellLanguageOption.values) {
        final result = await controller.setLanguage(option);
        expect(
          result,
          isA<ActionSucceeded>(),
          reason: 'setLanguage failed for $option',
        );
        expect(
          container.read(settingsControllerProvider).language,
          equals(option),
          reason: 'language state mismatch for $option',
        );
      }

      for (final mode in ShellThemeMode.values) {
        final result = await controller.setThemeMode(mode);
        expect(
          result,
          isA<ActionSucceeded>(),
          reason: 'setThemeMode failed for $mode',
        );
        expect(
          container.read(settingsControllerProvider).themeMode,
          equals(mode),
          reason: 'themeMode state mismatch for $mode',
        );
      }

      for (final palette in AppThemePresetKey.values) {
        final result = await controller.setThemePalette(palette);
        expect(
          result,
          isA<ActionSucceeded>(),
          reason: 'setThemePalette failed for $palette',
        );
        expect(
          container.read(settingsControllerProvider).themePalette,
          equals(palette),
          reason: 'themePalette state mismatch for $palette',
        );
      }

      for (final timeZoneMode in ShellTimeZoneMode.values) {
        final result = await controller.setTimeZoneMode(timeZoneMode);
        expect(
          result,
          isA<ActionSucceeded>(),
          reason: 'setTimeZoneMode failed for $timeZoneMode',
        );
        expect(
          container.read(settingsControllerProvider).timeZoneMode,
          equals(timeZoneMode),
          reason: 'timeZoneMode state mismatch for $timeZoneMode',
        );
      }

      await controller.setManualTimeZoneOffsetMinutes(330);
      expect(
        container.read(settingsControllerProvider).manualTimeZoneOffsetMinutes,
        equals(330),
      );
      await controller.setManualTimeZoneOffsetMinutes(9999);
      expect(
        container.read(settingsControllerProvider).manualTimeZoneOffsetMinutes,
        equals(WebDavConfig.maxUtcOffsetMinutes),
      );

      for (final window in ShellDueLeadOption.values) {
        final result = await controller.setDueLeadWindow(window);
        expect(
          result,
          isA<ActionSucceeded>(),
          reason: 'setDueLeadWindow failed for $window',
        );
        expect(
          container.read(settingsControllerProvider).dueLeadWindow,
          equals(window),
          reason: 'dueLeadWindow state mismatch for $window',
        );
      }

      await controller.setLocationEnabled(true);
      expect(
        container.read(settingsControllerProvider).locationEnabled,
        isTrue,
      );
      await controller.setDiagnosticsEnabled(true);
      expect(
        container.read(settingsControllerProvider).diagnosticsEnabled,
        isTrue,
      );
      for (final level in DiagnosticLogLevel.configurableLevels) {
        await controller.setLogLevel(level);
        expect(
          container.read(settingsControllerProvider).logLevel,
          equals(level),
          reason: 'logLevel mismatch for $level',
        );
      }
      for (final logMode in ShellStorageMode.values) {
        await controller.setLogStorageMode(logMode);
        expect(
          container.read(settingsControllerProvider).logStorageMode,
          equals(logMode),
          reason: 'logStorageMode mismatch for $logMode',
        );
      }
      await controller.setLocalWatchEnabled(false);
      expect(
        container.read(settingsControllerProvider).localWatchEnabled,
        isFalse,
      );

      // Unsaved WebDAV draft must survive non-local preference auto-saves and never leak into persisted config.
      final stateAfterAutoSaves = container.read(settingsControllerProvider);
      expect(stateAfterAutoSaves.isWebDavDirty, isTrue);
      expect(
        stateAfterAutoSaves.webDavServerUrl,
        equals('https://unsaved.example.com'),
      );
      expect(
        container.read(webDavConfigProvider).requireValue.serverUrl,
        equals('https://cloud.example.com'),
        reason: 'Auto-saved preferences must not commit unsaved WebDAV edits',
      );
    });

    test('keeps persisted state intact and displays localized danger banner when WorkspaceException occurs', () async {
      final configNotifier = _RecordingWebDavConfigNotifier(
        initialConfig: configuredWebDav,
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(configuredWebDav),
          ),
          webDavConfigProvider.overrideWith(() => configNotifier),
          appLocaleProvider.overrideWithValue(const Locale('en')),
          diagnosticsEnabledProvider.overrideWithValue(true),
          taskNotifierProvider.overrideWith(_RecordingTaskNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);

      const failure = WorkspaceException(
        WorkspaceErrorKind.settingsPersistenceFailed,
        'disk full',
      );
      configNotifier.updateErrorToThrow = failure;

      final controller = container.read(settingsControllerProvider.notifier);
      final result = await controller.setThemeMode(
        ShellThemeMode.dark,
        locale: const Locale('de'),
      );
      final expectedMessage = lookupAppLocalizations(const Locale('de'))
          .localizeWorkspaceError(failure);

      expect(result, equals(ActionPersistFailed(message: expectedMessage)));
      final viewModel = container.read(settingsControllerProvider);
      expect(
        viewModel.themeMode,
        equals(ShellThemeMode.system),
        reason: 'Failed auto-save must keep previously persisted themeMode',
      );
      expect(
        viewModel.statusBanner,
        equals(
          SettingsStatusBannerViewModel(
            tone: BannerTone.danger,
            message: expectedMessage,
          ),
        ),
      );

      controller.dismissStatusBanner();
      expect(container.read(settingsControllerProvider).statusBanner, isNull);
    });
  });

  group('SettingsController WebDAV dirty draft and silent discard', () {
    test('tracks dirty state, updates live endpoint preview, clears field error on edit, and resets when switching to local mode', () async {
      enableInMemoryLogger();
      final configNotifier = _RecordingWebDavConfigNotifier(
        initialConfig: configuredWebDav,
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(configuredWebDav),
          ),
          webDavConfigProvider.overrideWith(() => configNotifier),
          appLocaleProvider.overrideWithValue(const Locale('en')),
          diagnosticsEnabledProvider.overrideWithValue(true),
          taskNotifierProvider.overrideWith(_RecordingTaskNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);
      final subscription = container.listen(
        settingsControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      final controller = container.read(settingsControllerProvider.notifier);
      controller.updateWebDavDraft(serverUrl: 'https://temp.example.com');
      expect(container.read(settingsControllerProvider).isWebDavDirty, isTrue);
      controller.updateWebDavDraft(serverUrl: 'https://cloud.example.com');
      expect(
        container.read(settingsControllerProvider).isWebDavDirty,
        isFalse,
        reason: 'Reverting draft back to persisted values clears dirty state',
      );

      controller.updateWebDavDraft(
        serverUrl: 'https://invalid-user:pass@cloud.example.com',
        username: '',
        password: '',
        filePath: '../secret.tdf',
      );
      expect(container.read(settingsControllerProvider).isWebDavDirty, isTrue);

      // Trigger validation errors on all 4 fields.
      final validationResult = await controller.saveWebDavDraft();
      expect(validationResult, isA<ActionValidationFailed>());
      var viewModel = container.read(settingsControllerProvider);
      expect(viewModel.serverUrlError, isNotNull);
      expect(viewModel.usernameError, isNotNull);
      expect(viewModel.passwordError, isNotNull);
      expect(viewModel.filePathError, isNotNull);

      // Editing serverUrl clears only serverUrlError and updates live endpoint preview.
      controller.updateWebDavDraft(
        serverUrl: 'https://next.example.com',
        username: 'bob',
        filePath: 'work/board.tdf',
      );
      viewModel = container.read(settingsControllerProvider);
      expect(viewModel.serverUrlError, isNull);
      expect(viewModel.usernameError, isNull);
      expect(viewModel.filePathError, isNull);
      expect(viewModel.passwordError, isNotNull);
      expect(
        viewModel.resolvedWebDavEndpoint,
        equals(
          'https://next.example.com/remote.php/dav/files/bob/work/board.tdf',
        ),
      );
      expect(viewModel.remoteFileBaseName, equals('board'));

      // Switching to local mode IMMEDIATELY clears dirty state, re-hydrates draft fields, and clears errors.
      final switchResult = await controller.setStorageMode(
        ShellStorageMode.local,
      );
      expect(switchResult, isA<ActionSucceeded>());
      viewModel = container.read(settingsControllerProvider);
      expect(viewModel.storageMode, equals(ShellStorageMode.local));
      expect(viewModel.isWebDavDirty, isFalse);
      expect(viewModel.canTestConnectionAndSync, isFalse);
      expect(viewModel.webDavServerUrl, equals('https://cloud.example.com'));
      expect(viewModel.webDavUsername, equals('alice'));
      expect(viewModel.webDavPassword, equals('super-secret-password'));
      expect(viewModel.webDavFilePath, equals('notes/tasks.tdf'));
      expect(viewModel.serverUrlError, isNull);
      expect(viewModel.usernameError, isNull);
      expect(viewModel.passwordError, isNull);
      expect(viewModel.filePathError, isNull);
      expect(
        AppLogger.lines.any(
          (line) =>
              line.contains('ui.settings_webdav_draft_discarded') &&
              line.contains('reason=storage_mode_local'),
        ),
        isTrue,
      );
    });

    test('silently discards dirty WebDAV edits on navigation away from settings and on workspace switch', () async {
      enableInMemoryLogger();
      final settingsRepository = InMemorySettingsRepository(configuredWebDav);
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          diagnosticsEnabledProvider.overrideWithValue(true),
          localFileRepositoryProvider.overrideWith(
            (ref) => FakeLocalFileRepository(
              config: configuredWebDav,
              initialTdf: 'tdf ${TdfService.supportedVersion}\n',
            ),
          ),
          taskNotifierProvider.overrideWith(_RecordingTaskNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);
      final shellSubscription = container.listen(
        appShellControllerProvider,
        (_, _) {},
      );
      final settingsSubscription = container.listen(
        settingsControllerProvider,
        (_, _) {},
      );
      addTearDown(shellSubscription.close);
      addTearDown(settingsSubscription.close);

      final shellController = container.read(
        appShellControllerProvider.notifier,
      );
      final settingsController = container.read(
        settingsControllerProvider.notifier,
      );

      // Navigate into Settings, dirty draft + validation error, then leave Settings.
      shellController.openView(ShellView.settings);
      settingsController.updateWebDavDraft(serverUrl: 'ftp://bad.example.com');
      await settingsController.saveWebDavDraft();
      expect(container.read(settingsControllerProvider).isWebDavDirty, isTrue);
      expect(
        container.read(settingsControllerProvider).serverUrlError,
        isNotNull,
      );

      shellController.openView(ShellView.tasks);
      var viewModel = container.read(settingsControllerProvider);
      expect(viewModel.isWebDavDirty, isFalse);
      expect(viewModel.webDavServerUrl, equals('https://cloud.example.com'));
      expect(viewModel.serverUrlError, isNull);
      expect(
        AppLogger.lines.any(
          (line) =>
              line.contains('ui.settings_webdav_draft_discarded') &&
              line.contains('reason=navigation'),
        ),
        isTrue,
      );

      // Re-enter Settings, dirty draft again, and switch workspace.
      AppLogger.clear();
      shellController.openView(ShellView.settings);
      settingsController.updateWebDavDraft(
        serverUrl: 'https://dirty-before-switch.example.com',
      );
      expect(container.read(settingsControllerProvider).isWebDavDirty, isTrue);

      const secondWorkspaceConfig = WebDavConfig(
        serverUrl: 'https://personal.example.com',
        username: 'carol',
        password: 'personal-password',
        filePath: 'personal.tdf',
        localFilePath: 'personal.tdf',
        storageMode: StorageMode.both,
      );
      await container
          .read(activeWorkspaceProvider.notifier)
          .createWorkspace(
            'Personal',
            config: secondWorkspaceConfig,
            activate: true,
          );
      await container.read(webDavConfigProvider.future);

      viewModel = container.read(settingsControllerProvider);
      expect(viewModel.workspaceName, equals('Personal'));
      expect(viewModel.isWebDavDirty, isFalse);
      expect(viewModel.webDavServerUrl, equals('https://personal.example.com'));
      expect(viewModel.webDavUsername, equals('carol'));
      expect(viewModel.localFileName, equals('personal.tdf'));
      expect(
        AppLogger.lines.any(
          (line) =>
              line.contains('ui.settings_webdav_draft_discarded') &&
              line.contains('reason=workspace_switch'),
        ),
        isTrue,
      );

      // Manual discard resets edits and logs reason=manual.
      AppLogger.clear();
      settingsController.updateWebDavDraft(username: 'edited');
      expect(container.read(settingsControllerProvider).isWebDavDirty, isTrue);
      settingsController.discardWebDavDraft();
      expect(container.read(settingsControllerProvider).isWebDavDirty, isFalse);
      expect(
        container.read(settingsControllerProvider).webDavUsername,
        equals('carol'),
      );
      expect(
        AppLogger.lines.any(
          (line) =>
              line.contains('ui.settings_webdav_draft_discarded') &&
              line.contains('reason=manual'),
        ),
        isTrue,
      );
    });
  });

  group('SettingsController WebDAV validation, save, and sync (M-URI-PATH-EDGE-TESTS)', () {
    test('rejects invalid server URLs, userinfo, empty credentials, and traversal/control remote paths', () async {
      final localizations = lookupAppLocalizations(const Locale('en'));
      final configNotifier = _RecordingWebDavConfigNotifier(
        initialConfig: configuredWebDav,
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(configuredWebDav),
          ),
          webDavConfigProvider.overrideWith(() => configNotifier),
          appLocaleProvider.overrideWithValue(const Locale('en')),
          diagnosticsEnabledProvider.overrideWithValue(true),
          taskNotifierProvider.overrideWith(_RecordingTaskNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);

      final controller = container.read(settingsControllerProvider.notifier);

      // Empty serverUrl, username, and password produce per-field errors and danger banner.
      controller.updateWebDavDraft(
        serverUrl: '   ',
        username: '  ',
        password: '',
        filePath: 'tasks.tdf',
      );
      final emptyResult = await controller.saveWebDavDraft();
      expect(emptyResult, isA<ActionValidationFailed>());
      final emptyFailure = emptyResult as ActionValidationFailed;
      expect(emptyFailure.message, equals(localizations.serverUrlErrorEmpty));
      expect(
        emptyFailure.fieldErrors,
        equals(<String, String>{
          'serverUrl': localizations.serverUrlErrorEmpty,
          'username': localizations.usernameErrorEmpty,
          'password': localizations.passwordErrorEmpty,
        }),
      );
      var viewModel = container.read(settingsControllerProvider);
      expect(
        viewModel.serverUrlError,
        equals(localizations.serverUrlErrorEmpty),
      );
      expect(viewModel.usernameError, equals(localizations.usernameErrorEmpty));
      expect(viewModel.passwordError, equals(localizations.passwordErrorEmpty));
      expect(viewModel.filePathError, isNull);
      expect(
        viewModel.statusBanner,
        equals(
          SettingsStatusBannerViewModel(
            tone: BannerTone.danger,
            message: localizations.serverUrlErrorEmpty,
          ),
        ),
      );

      // Server URL URI edge cases.
      final invalidServerUrlCases = <({String input, String expectedError})>[
        (
          input: 'cloud.example.com',
          expectedError: localizations.errorInvalidServerUrl,
        ),
        (
          input: 'ftp://cloud.example.com',
          expectedError: localizations.errorInvalidServerUrl,
        ),
        (
          input: 'file:///etc/passwd',
          expectedError: localizations.errorInvalidServerUrl,
        ),
        (input: 'https://', expectedError: localizations.errorInvalidServerUrl),
        (
          input: 'http:///dav/tasks.tdf',
          expectedError: localizations.errorInvalidServerUrl,
        ),
        (
          input: 'https://user:pass@cloud.example.com',
          expectedError: localizations.webDavUrlUserinfoError,
        ),
        (
          input: 'https://user@cloud.example.com',
          expectedError: localizations.webDavUrlUserinfoError,
        ),
        (
          input: 'https://@cloud.example.com',
          expectedError: localizations.webDavUrlUserinfoError,
        ),
        (
          input: 'https://cloud.example.com?token=1',
          expectedError: localizations.errorInvalidServerUrl,
        ),
        (
          input: 'https://cloud.example.com#section',
          expectedError: localizations.errorInvalidServerUrl,
        ),
        (
          input: 'https://cloud.example.com\n',
          expectedError: localizations.errorInvalidServerUrl,
        ),
        (
          input: 'https://cloud.example.com/\x00',
          expectedError: localizations.errorInvalidServerUrl,
        ),
        (
          input: r'https://cloud.example.com\dav',
          expectedError: localizations.errorInvalidServerUrl,
        ),
        (
          input: 'https://cloud.example.com/../secret',
          expectedError: localizations.errorInvalidServerUrl,
        ),
      ];

      for (final testCase in invalidServerUrlCases) {
        controller.updateWebDavDraft(
          serverUrl: testCase.input,
          username: 'alice',
          password: 'secret',
          filePath: 'tasks.tdf',
        );
        final result = await controller.saveWebDavDraft();
        expect(
          result,
          isA<ActionValidationFailed>(),
          reason:
              'Expected validation failure for serverUrl "${testCase.input}"',
        );
        viewModel = container.read(settingsControllerProvider);
        expect(
          viewModel.serverUrlError,
          equals(testCase.expectedError),
          reason: 'Unexpected serverUrlError for "${testCase.input}"',
        );
        expect(
          viewModel.statusBanner?.tone,
          equals(BannerTone.danger),
          reason: 'Expected danger banner for "${testCase.input}"',
        );
      }

      // Remote filePath traversal, separator, and control character edge cases.
      final invalidRemotePaths = <String>[
        '..',
        '../tasks.tdf',
        'folder/../tasks.tdf',
        'tasks..tdf',
        '.',
        './tasks.tdf',
        r'folder\tasks.tdf',
        'tasks\x00.tdf',
        'tasks\n.tdf',
        'tasks\r.tdf',
        'tasks\t.tdf',
        'tasks\x7F.tdf',
        '///',
        'tasks.tdf?raw=1',
        'tasks.tdf#top',
      ];
      for (final badPath in invalidRemotePaths) {
        controller.updateWebDavDraft(
          serverUrl: 'https://cloud.example.com',
          username: 'alice',
          password: 'secret',
          filePath: badPath,
        );
        final result = await controller.saveWebDavDraft();
        expect(
          result,
          isA<ActionValidationFailed>(),
          reason: 'Expected validation failure for remote filePath "$badPath"',
        );
        viewModel = container.read(settingsControllerProvider);
        expect(
          viewModel.filePathError,
          equals(localizations.webDavPathInvalidError),
          reason: 'Expected webDavPathInvalidError for "$badPath"',
        );
      }
      expect(configNotifier.calls, isEmpty);
    });

    test('saves valid WebDAV draft with default filename fallback and tests connection and sync', () async {
      final localizations = lookupAppLocalizations(const Locale('en'));
      final configNotifier = _RecordingWebDavConfigNotifier(
        initialConfig: configuredWebDav,
      );
      final taskNotifier = _RecordingTaskNotifier();
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(configuredWebDav),
          ),
          webDavConfigProvider.overrideWith(() => configNotifier),
          appLocaleProvider.overrideWithValue(const Locale('en')),
          taskNotifierProvider.overrideWith(() => taskNotifier),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);
      await container.read(taskNotifierProvider.future);

      final controller = container.read(settingsControllerProvider.notifier);

      // Valid save with blank filePath falls back to defaultFileName.
      controller.updateWebDavDraft(
        serverUrl: '  https://dav.example.com:8443/nextcloud  ',
        username: '  bob  ',
        password: 'app-password',
        filePath: '   ',
      );
      final saveResult = await controller.saveWebDavDraft();
      expect(
        saveResult,
        equals(
          ActionSucceeded(noticeMessage: localizations.credentialsSavedBanner),
        ),
      );
      var viewModel = container.read(settingsControllerProvider);
      expect(viewModel.isWebDavDirty, isFalse);
      expect(
        viewModel.webDavServerUrl,
        equals('https://dav.example.com:8443/nextcloud'),
      );
      expect(viewModel.webDavUsername, equals('bob'));
      expect(viewModel.webDavFilePath, equals(WebDavConfig.defaultFileName));
      expect(
        viewModel.statusBanner,
        equals(
          SettingsStatusBannerViewModel(
            tone: BannerTone.success,
            message: localizations.credentialsSavedBanner,
          ),
        ),
      );

      // Save failure preserves dirty edits and shows danger banner.
      controller.updateWebDavDraft(serverUrl: 'https://fail-save.example.com');
      configNotifier.updateErrorToThrow = const WorkspaceException(
        WorkspaceErrorKind.credentialStorageUnavailable,
        'locked',
      );
      final failedSave = await controller.saveWebDavDraft();
      expect(failedSave, isA<ActionPersistFailed>());
      expect(container.read(settingsControllerProvider).isWebDavDirty, isTrue);
      expect(
        container.read(settingsControllerProvider).statusBanner?.tone,
        equals(BannerTone.danger),
      );
      configNotifier.updateErrorToThrow = null;

      // Test connection and sync succeeds and updates banner.
      controller.updateWebDavDraft(
        serverUrl: 'https://sync.example.com',
        filePath: 'team/tasks.tdf',
      );
      final syncResult = await controller.testConnectionAndSync();
      expect(
        syncResult,
        equals(
          ActionSucceeded(noticeMessage: localizations.connectionSuccessBanner),
        ),
      );
      expect(
        taskNotifier.lastTestedConfig?.serverUrl,
        equals('https://sync.example.com'),
      );
      expect(container.read(settingsControllerProvider).isWebDavDirty, isFalse);
      expect(
        container.read(settingsControllerProvider).statusBanner,
        equals(
          SettingsStatusBannerViewModel(
            tone: BannerTone.success,
            message: localizations.connectionSuccessBanner,
          ),
        ),
      );

      // Test connection and sync failure shows danger banner with sanitized error.
      taskNotifier.testSyncErrorToThrow = const WebDavException(
        'Authentication failed',
        statusCode: 401,
      );
      final syncFailure = await controller.testConnectionAndSync();
      expect(syncFailure, isA<ActionPersistFailed>());
      expect(
        container.read(settingsControllerProvider).statusBanner,
        equals(
          const SettingsStatusBannerViewModel(
            tone: BannerTone.danger,
            message: 'Authentication failed (HTTP 401)',
          ),
        ),
      );

      // StorageFileReadException formats structured readability message.
      const report = StorageFileReadReport(
        remote: StorageFileReadStatus.unreadable(
          StorageFileTarget.remote,
          detail: 'Unexpected token',
          line: 4,
        ),
      );
      taskNotifier.testSyncErrorToThrow = const StorageFileReadException(
        'Read failed',
        report: report,
      );
      final readFailure = await controller.testConnectionAndSync();
      expect(readFailure, isA<ActionPersistFailed>());
      expect(
        container.read(settingsControllerProvider).statusBanner?.tone,
        equals(BannerTone.danger),
      );
      expect(
        container.read(settingsControllerProvider).statusBanner?.message,
        contains('Unexpected token'),
      );

      // Disabled in local storage mode.
      taskNotifier.testSyncErrorToThrow = null;
      final callCountBeforeLocal = taskNotifier.calls.length;
      await controller.setStorageMode(ShellStorageMode.local);
      final blockedInLocal = await controller.testConnectionAndSync();
      expect(blockedInLocal, isA<ActionValidationFailed>());
      expect(taskNotifier.calls.length, equals(callCountBeforeLocal));
    });
  });

  group('SettingsController capability-gated local storage and destructive wipes', () {
    test('supports native picker select, move, rename, and local/remote wipe when supportsNativeDirectoryPicker is true', () async {
      enableInMemoryLogger();
      final localizations = lookupAppLocalizations(const Locale('en'));
      final tempDirectory = Directory.systemTemp.createTempSync(
        'tiertask_settings_',
      );
      addTearDown(() {
        if (tempDirectory.existsSync()) {
          tempDirectory.deleteSync(recursive: true);
        }
      });
      final separator = Platform.pathSeparator;
      File('${tempDirectory.path}${separator}alpha.tdf')
          .writeAsStringSync('tdf ${TdfService.supportedVersion}\n');
      File('${tempDirectory.path}${separator}tasks.tdf')
          .writeAsStringSync('tdf ${TdfService.supportedVersion}\n');

      String? nativePickedFile = '${tempDirectory.path}${separator}alpha.tdf';
      String? nativePickedDirectory = '/mock/moved';

      final configNotifier = _RecordingWebDavConfigNotifier(
        initialConfig: configuredWebDav,
      );
      final taskNotifier = _RecordingTaskNotifier();
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(configuredWebDav),
          ),
          webDavConfigProvider.overrideWith(() => configNotifier),
          appLocaleProvider.overrideWithValue(const Locale('en')),
          diagnosticsEnabledProvider.overrideWithValue(true),
          supportsDirectoryPickerProvider.overrideWithValue(true),
          localStorageDirectoryPathProvider.overrideWithValue(
            tempDirectory.path,
          ),
          localFileRepositoryProvider.overrideWithValue(
            LocalFileRepository(
              config: configuredWebDav,
              baseDirectoryPath: tempDirectory.path,
            ),
          ),
          filePickerProvider.overrideWithValue(
            ({String? initialDirectory, String? currentFileName}) async =>
                nativePickedFile,
          ),
          directoryPickerProvider.overrideWithValue(
            ({String? initialDirectory}) async => nativePickedDirectory,
          ),
          taskNotifierProvider.overrideWith(() => taskNotifier),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);
      await container.read(taskNotifierProvider.future);

      final controller = container.read(settingsControllerProvider.notifier);

      // List directory .tdf filenames.
      expect(
        controller.listLocalTdfFileNames(),
        equals(const <String>['alpha.tdf', 'tasks.tdf']),
      );

      // Native Select cancelled returns succeeded without calling TaskNotifier.
      nativePickedFile = null;
      final cancelSelect = await controller.selectLocalFile();
      expect(cancelSelect, equals(const ActionSucceeded()));
      expect(taskNotifier.calls, isEmpty);

      // Native Select confirmed selects file and shows banner.
      nativePickedFile = '${tempDirectory.path}${separator}alpha.tdf';
      final selectResult = await controller.selectLocalFile();
      expect(
        selectResult,
        equals(
          ActionSucceeded(noticeMessage: localizations.localFileSelectedBanner),
        ),
      );
      expect(
        taskNotifier.lastSelectedLocalConfig?.localFilePath,
        equals('${tempDirectory.path}${separator}alpha.tdf'),
      );
      expect(
        container.read(settingsControllerProvider).localFileName,
        equals('alpha.tdf'),
      );
      expect(
        container.read(settingsControllerProvider).localFileBaseName,
        equals('alpha'),
      );

      // Move cancelled returns succeeded without calling changeLocalFileLocation.
      nativePickedDirectory = null;
      final callCountBeforeMoveCancel = configNotifier.calls.length;
      expect(
        await controller.moveLocalDirectory(),
        equals(const ActionSucceeded()),
      );
      expect(configNotifier.calls.length, equals(callCountBeforeMoveCancel));

      // Move local directory succeeds and maps errors cleanly.
      nativePickedDirectory = '/mock/moved';
      final moveResult = await controller.moveLocalDirectory();
      expect(
        moveResult,
        equals(
          ActionSucceeded(
            noticeMessage: localizations.localDirectoryMovedBanner,
          ),
        ),
      );
      expect(
        configNotifier.calls.last,
        equals('changeLocalFileLocation:/mock/moved${separator}alpha.tdf'),
      );

      nativePickedDirectory = '/mock/fail-move';
      configNotifier.changeLocationErrorToThrow = const LocalFileException(
        'Destination already exists',
      );
      final failedMove = await controller.moveLocalDirectory();
      expect(
        failedMove,
        equals(
          const ActionPersistFailed(message: 'Destination already exists'),
        ),
      );
      expect(
        container.read(settingsControllerProvider).statusBanner?.tone,
        equals(BannerTone.danger),
      );
      configNotifier.changeLocationErrorToThrow = null;

      // Rename local file rejects invalid names (M-URI-PATH-EDGE-TESTS).
      final invalidLocalFileNames = <String>[
        '',
        '   ',
        '.',
        '..',
        '.tdf',
        '../evil.tdf',
        'nested/work.tdf',
        r'nested\work.tdf',
        'bad..name.tdf',
        'C:work.tdf',
        'work\x00.tdf',
        'work.tdf\n',
        'work\t.tdf',
      ];
      for (final badName in invalidLocalFileNames) {
        final invalidRename = await controller.renameLocalFile(badName);
        expect(
          invalidRename,
          isA<ActionValidationFailed>(),
          reason: 'Expected renameLocalFile to reject "$badName"',
        );
        expect(
          container.read(settingsControllerProvider).statusBanner?.message,
          equals(localizations.localFileNameErrorInvalid),
          reason: 'Expected localFileNameErrorInvalid for "$badName"',
        );
      }

      // Unchanged filename is a clean no-op.
      final callCountBeforeNoop = configNotifier.calls.length;
      expect(
        await controller.renameLocalFile('alpha'),
        equals(const ActionSucceeded()),
      );
      expect(configNotifier.calls.length, equals(callCountBeforeNoop));

      // Valid rename appends .tdf, calls changeLocalFileLocation, logs telemetry, shows banner.
      final renameResult = await controller.renameLocalFile('renamed');
      expect(
        renameResult,
        equals(
          ActionSucceeded(noticeMessage: localizations.localFileRenamedBanner),
        ),
      );
      expect(
        container.read(settingsControllerProvider).localFileName,
        equals('renamed.tdf'),
      );
      expect(
        AppLogger.lines.any(
          (line) => line.contains(
            'Confirmed rename local TDF dialog from=alpha.tdf to=renamed.tdf',
          ),
        ),
        isTrue,
      );

      // Rename WorkspaceException maps cleanly to danger banner.
      const duplicateError = WorkspaceException(
        WorkspaceErrorKind.duplicateFilePath,
        'Duplicate',
      );
      configNotifier.changeLocationErrorToThrow = duplicateError;
      final failedRename = await controller.renameLocalFile('other');
      expect(
        failedRename,
        equals(
          ActionPersistFailed(
            message: localizations.localizeWorkspaceError(duplicateError),
          ),
        ),
      );
      configNotifier.changeLocationErrorToThrow = null;

      // Wipe local file logs telemetry and shows success banner.
      final wipeLocalResult = await controller.wipeLocalFile(
        createBackup: true,
      );
      expect(
        wipeLocalResult,
        equals(
          ActionSucceeded(noticeMessage: localizations.localFileWipedBanner),
        ),
      );
      expect(taskNotifier.lastWipeCreateBackup, isTrue);
      expect(
        AppLogger.lines.any(
          (line) => line.contains(
            'Confirmed wipe TDF dialog target=local file=renamed.tdf createBackup=true',
          ),
        ),
        isTrue,
      );

      // Wipe local error maps cleanly to danger banner.
      taskNotifier.wipeLocalErrorToThrow = const LocalFileException(
        'Permission denied',
      );
      final failedLocalWipe = await controller.wipeLocalFile(
        createBackup: false,
      );
      expect(
        failedLocalWipe,
        equals(const ActionPersistFailed(message: 'Permission denied')),
      );
      taskNotifier.wipeLocalErrorToThrow = null;

      // Wipe remote file logs telemetry and shows success banner.
      final wipeRemoteResult = await controller.wipeRemoteFile(
        createBackup: false,
      );
      expect(
        wipeRemoteResult,
        equals(
          ActionSucceeded(noticeMessage: localizations.remoteFileWipedBanner),
        ),
      );
      expect(taskNotifier.lastWipeCreateBackup, isFalse);
      expect(
        AppLogger.lines.any(
          (line) => line.contains(
            'Confirmed wipe TDF dialog target=remote file=tasks.tdf createBackup=false',
          ),
        ),
        isTrue,
      );

      // Wipe remote error maps cleanly.
      taskNotifier.wipeRemoteErrorToThrow = const WebDavException(
        'Server unavailable',
        statusCode: 503,
      );
      final failedRemoteWipe = await controller.wipeRemoteFile(
        createBackup: true,
      );
      expect(
        failedRemoteWipe,
        equals(
          const ActionPersistFailed(message: 'Server unavailable (HTTP 503)'),
        ),
      );
    });

    test('gates moveLocalDirectory and selects by filename when supportsNativeDirectoryPicker is false', () async {
      final localizations = lookupAppLocalizations(const Locale('en'));
      const localOnlyConfig = WebDavConfig(
        localFilePath: 'tasks.tdf',
        storageMode: StorageMode.local,
        language: AppLanguage.english,
      );
      var directoryPickerCalled = false;
      final configNotifier = _RecordingWebDavConfigNotifier(
        initialConfig: localOnlyConfig,
      );
      final taskNotifier = _RecordingTaskNotifier();
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(localOnlyConfig),
          ),
          webDavConfigProvider.overrideWith(() => configNotifier),
          appLocaleProvider.overrideWithValue(const Locale('en')),
          supportsDirectoryPickerProvider.overrideWithValue(false),
          localStorageDirectoryPathProvider.overrideWithValue('/app/data'),
          directoryPickerProvider.overrideWithValue(({
            String? initialDirectory,
          }) async {
            directoryPickerCalled = true;
            return '/should/not/be/called';
          }),
          taskNotifierProvider.overrideWith(() => taskNotifier),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);
      await container.read(taskNotifierProvider.future);

      final controller = container.read(settingsControllerProvider.notifier);
      expect(
        container
            .read(settingsControllerProvider)
            .supportsNativeDirectoryPicker,
        isFalse,
      );

      // Move is capability-gated on platforms without native directory picker.
      final moveBlocked = await controller.moveLocalDirectory();
      expect(
        moveBlocked,
        equals(
          ActionValidationFailed(
            message: localizations.settingsMoveDesktopOnlyTooltip,
          ),
        ),
      );
      expect(directoryPickerCalled, isFalse);

      // Select without chosenFileName rejects when native picker is unsupported.
      final missingName = await controller.selectLocalFile();
      expect(missingName, isA<ActionValidationFailed>());

      // Select with invalid filename rejects.
      final invalidChosen = await controller.selectLocalFile(
        chosenFileName: '../outside.tdf',
      );
      expect(invalidChosen, isA<ActionValidationFailed>());

      // Select with valid bare name appends .tdf and resolves in app data directory.
      final selected = await controller.selectLocalFile(chosenFileName: 'work');
      expect(
        selected,
        equals(
          ActionSucceeded(noticeMessage: localizations.localFileSelectedBanner),
        ),
      );
      expect(
        taskNotifier.lastSelectedLocalConfig?.localFilePath,
        equals('/app/data${Platform.pathSeparator}work.tdf'),
      );

      // Wipe remote rejects when WebDAV is not configured / local mode.
      final wipeRemoteBlocked = await controller.wipeRemoteFile(
        createBackup: false,
      );
      expect(
        wipeRemoteBlocked,
        equals(
          ActionValidationFailed(
            message: localizations.errorWebDavNotConfigured,
          ),
        ),
      );
    });
  });

  group('SettingsController mid-flight Completer busy guard (M-REAL-MECHANICS-TESTS)', () {
    test('sets isBusy during suspended WebDAV save, ignores duplicate concurrent submits, and clears isBusy on completion', () async {
      final completer = Completer<void>();
      final configNotifier = _RecordingWebDavConfigNotifier(
        initialConfig: configuredWebDav,
      )..pendingUpdateCompleter = completer;
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(configuredWebDav),
          ),
          webDavConfigProvider.overrideWith(() => configNotifier),
          appLocaleProvider.overrideWithValue(const Locale('en')),
          diagnosticsEnabledProvider.overrideWithValue(true),
          taskNotifierProvider.overrideWith(_RecordingTaskNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);

      final controller = container.read(settingsControllerProvider.notifier);
      controller.updateWebDavDraft(serverUrl: 'https://inflight.example.com');

      final firstFuture = controller.saveWebDavDraft();
      final midFlight = container.read(settingsControllerProvider);
      expect(midFlight.isBusy, isTrue);
      expect(midFlight.canTestConnectionAndSync, isFalse);

      // Concurrent duplicate submit and preference toggle must be ignored while busy.
      final duplicateResult = await controller.saveWebDavDraft();
      expect(duplicateResult, equals(const ActionSucceeded()));
      final concurrentPref = await controller.setThemeMode(ShellThemeMode.dark);
      expect(concurrentPref, equals(const ActionSucceeded()));
      expect(
        configNotifier.calls,
        equals(const <String>['updateConfig']),
        reason: 'Busy guard must block concurrent duplicate writes',
      );

      completer.complete();
      final firstResult = await firstFuture;
      expect(firstResult, isA<ActionSucceeded>());

      final settled = container.read(settingsControllerProvider);
      expect(settled.isBusy, isFalse);
      expect(settled.canTestConnectionAndSync, isTrue);
      expect(settled.isWebDavDirty, isFalse);
      expect(settled.webDavServerUrl, equals('https://inflight.example.com'));
    });

    test('drops stale completion banner when workspace switches across await boundary', () async {
      final completer = Completer<void>();
      final settingsRepository = InMemorySettingsRepository(configuredWebDav);
      final taskNotifier = _RecordingTaskNotifier(TaskBoard.empty())
        ..pendingActionCompleter = completer;
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          localFileRepositoryProvider.overrideWith(
            (ref) => FakeLocalFileRepository(
              config: configuredWebDav,
              initialTdf: 'tdf ${TdfService.supportedVersion}\n',
            ),
          ),
          taskNotifierProvider.overrideWith(() => taskNotifier),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);
      await container.read(taskNotifierProvider.future);
      final subscription = container.listen(
        settingsControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      final controller = container.read(settingsControllerProvider.notifier);
      final wipeFuture = controller.wipeLocalFile(createBackup: false);
      expect(container.read(settingsControllerProvider).isBusy, isTrue);

      // Switch workspace while wipe is still in flight.
      await container
          .read(activeWorkspaceProvider.notifier)
          .createWorkspace(
            'Secondary',
            config: const WebDavConfig(localFilePath: 'secondary.tdf'),
            activate: true,
          );
      await container.read(webDavConfigProvider.future);

      expect(container.read(settingsControllerProvider).isBusy, isFalse);
      expect(
        container.read(settingsControllerProvider).workspaceName,
        equals('Secondary'),
      );

      // Complete stale in-flight wipe; it must not overwrite Secondary workspace's statusBanner.
      completer.complete();
      await wipeFuture;
      final finalState = container.read(settingsControllerProvider);
      expect(finalState.workspaceName, equals('Secondary'));
      expect(finalState.statusBanner, isNull);
      expect(finalState.isBusy, isFalse);
    });

    test('applies optimistic preference update during suspended save, exposes preference busy operation, rolls back on failure, and ignores no-op re-selection', () async {
      final saveGate = Completer<void>();
      final configNotifier = _RecordingWebDavConfigNotifier(
        initialConfig: configuredWebDav,
      )..pendingUpdateCompleter = saveGate;
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(configuredWebDav),
          ),
          webDavConfigProvider.overrideWith(() => configNotifier),
          appLocaleProvider.overrideWithValue(const Locale('en')),
          diagnosticsEnabledProvider.overrideWithValue(false),
          taskNotifierProvider.overrideWith(_RecordingTaskNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);
      final sub = container.listen(settingsControllerProvider, (_, _) {});
      addTearDown(sub.close);

      final controller = container.read(settingsControllerProvider.notifier);

      // No-op tap on already-selected palette performs zero persistence calls.
      final noopResult = await controller.setThemePalette(
        AppThemePresetKey.calm,
      );
      expect(noopResult, equals(const ActionSucceeded()));
      expect(
        configNotifier.calls,
        isEmpty,
        reason: 'Selecting the already-active palette must not persist or toggle busy state',
      );

      // Switching to Plum Umber updates themePalette optimistically while saving.
      final pendingPalette = controller.setThemePalette(
        AppThemePresetKey.plumUmber,
      );
      final midFlight = container.read(settingsControllerProvider);
      expect(
        midFlight.themePalette,
        equals(AppThemePresetKey.plumUmber),
        reason: 'Preference click must optimistically show the chosen value immediately without flashing back',
      );
      expect(midFlight.isBusy, isTrue);
      expect(midFlight.busyOperation, equals(SettingsBusyOperation.preference));
      expect(
        midFlight.isPreferenceControlDisabled,
        isFalse,
        reason: 'Short preference auto-saves must not visually dim/disable preference controls',
      );

      saveGate.complete();
      final saveResult = await pendingPalette;
      expect(saveResult, equals(const ActionSucceeded()));
      final settled = container.read(settingsControllerProvider);
      expect(settled.themePalette, equals(AppThemePresetKey.plumUmber));
      expect(settled.isBusy, isFalse);
      expect(settled.busyOperation, equals(SettingsBusyOperation.idle));

      // On persistence failure, optimistic preference rolls back cleanly with a danger banner.
      configNotifier
        ..pendingUpdateCompleter = null
        ..updateErrorToThrow = const WorkspaceException(
          WorkspaceErrorKind.invalidFilePath,
          'disk full',
        );
      final failedResult = await controller.setThemeMode(ShellThemeMode.dark);
      expect(failedResult, isA<ActionPersistFailed>());
      final afterFailure = container.read(settingsControllerProvider);
      expect(
        afterFailure.themeMode,
        equals(ShellThemeMode.system),
        reason: 'Failed preference persistence must roll back optimistic themeMode to previous value',
      );
      expect(afterFailure.isBusy, isFalse);
      expect(afterFailure.statusBanner?.tone, equals(BannerTone.danger));
    });
  });
}
