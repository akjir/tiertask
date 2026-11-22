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

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/l10n/tier_localization_extension.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/storage_file_read_status.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/settings_draft_providers.dart';
import 'package:tiertask/providers/shell_providers.dart';
import 'package:tiertask/providers/sync_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/services/tdf_service.dart';

import '../ui/test_helpers.dart';

class _DelayedBuildWebDavConfigNotifier extends WebDavConfigNotifier {
  _DelayedBuildWebDavConfigNotifier({
    required this.loadGate,
    required this.loadedConfig,
  });

  final Completer<void> loadGate;
  final WebDavConfig loadedConfig;

  @override
  Future<WebDavConfig> build() async {
    await loadGate.future;
    return loadedConfig;
  }
}

class _DelayedWorkspaceSettingsRepository extends InMemorySettingsRepository {
  _DelayedWorkspaceSettingsRepository(super.initialConfig);

  final List<Completer<void>> saveGates = <Completer<void>>[];
  final List<WebDavConfig> persistedConfigs = <WebDavConfig>[];
  WorkspaceException? errorToThrow;

  @override
  Future<void> saveConfig(WebDavConfig config) async {
    if (saveGates.isNotEmpty) {
      await saveGates.removeAt(0).future;
    }
    if (errorToThrow case final error?) {
      throw error;
    }
    persistedConfigs.add(config);
    await super.saveConfig(config);
  }
}

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
  Future<void> updateStorageMode(StorageMode storageMode) async {
    calls.add('updateStorageMode:${storageMode.name}');
    if (pendingUpdateCompleter case final completer?) {
      await completer.future;
    }
    if (updateErrorToThrow case final error?) {
      throw error;
    }
    final current = state.asData?.value ?? initialConfig;
    state = AsyncData<WebDavConfig>(current.copyWith(storageMode: storageMode));
  }

  @override
  Future<void> updateThemeMode(AppThemeMode themeMode) async {
    calls.add('updateThemeMode:${themeMode.name}');
    if (pendingUpdateCompleter case final completer?) {
      await completer.future;
    }
    if (updateErrorToThrow case final error?) {
      throw error;
    }
    final current = state.asData?.value ?? initialConfig;
    state = AsyncData<WebDavConfig>(current.copyWith(themeMode: themeMode));
  }

  @override
  Future<void> updateThemePalette(AppThemePalette themePalette) async {
    calls.add('updateThemePalette:${themePalette.name}');
    if (pendingUpdateCompleter case final completer?) {
      await completer.future;
    }
    if (updateErrorToThrow case final error?) {
      throw error;
    }
    final current = state.asData?.value ?? initialConfig;
    state = AsyncData<WebDavConfig>(
      current.copyWith(themePalette: themePalette),
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

  group('SettingsDraftState value model and computed getters', () {
    test('supports equality, hashCode, copyWith clear flags, computed busy getters, endpointPreview, and password redaction', () {
      const bannerA = SettingsStatusBanner(
        tone: SettingsBannerTone.success,
        message: 'Saved',
      );
      const bannerB = SettingsStatusBanner(
        tone: SettingsBannerTone.success,
        message: 'Saved',
      );
      expect(bannerA, equals(bannerB));
      expect(bannerA.hashCode, equals(bannerB.hashCode));
      expect(
        bannerA,
        isNot(
          equals(
            const SettingsStatusBanner(
              tone: SettingsBannerTone.warning,
              message: 'Saved',
            ),
          ),
        ),
      );

      const base = SettingsDraftState(
        serverUrl: 'https://cloud.example.com',
        username: 'alice',
        password: 'super-secret-password',
        filePath: 'notes/tasks.tdf',
        isDirty: true,
        serverUrlError: 'bad url',
        usernameError: 'bad user',
        passwordError: 'bad pass',
        filePathError: 'bad path',
        statusBanner: bannerA,
        busyOperation: SettingsBusyOperation.idle,
        resolvedLocalPathPreview: '/tmp/tasks.tdf',
      );

      final identicalCopy = base.copyWith();
      expect(identicalCopy, equals(base));
      expect(identicalCopy.hashCode, equals(base.hashCode));
      expect(base.isBusy, isFalse);
      expect(base.isSavingWebDav, isFalse);
      expect(base.isTestingConnection, isFalse);
      expect(base.isStorageOperationBusy, isFalse);
      expect(
        base.endpointPreview,
        equals(
          'https://cloud.example.com/remote.php/dav/files/alice/notes/tasks.tdf',
        ),
      );
      expect(
        base.toString(),
        isNot(contains('super-secret-password')),
        reason: 'SettingsDraftState.toString must redact WebDAV password',
      );
      expect(base.toString(), contains('[REDACTED]'));

      final saving = base.copyWith(
        busyOperation: SettingsBusyOperation.saveWebDav,
      );
      expect(saving.isBusy, isTrue);
      expect(saving.isSavingWebDav, isTrue);
      expect(saving.isTestingConnection, isFalse);
      expect(saving.isStorageOperationBusy, isFalse);

      final testing = base.copyWith(
        busyOperation: SettingsBusyOperation.testConnectionAndSync,
      );
      expect(testing.isBusy, isTrue);
      expect(testing.isSavingWebDav, isFalse);
      expect(testing.isTestingConnection, isTrue);
      expect(testing.isStorageOperationBusy, isFalse);

      final storageBusy = base.copyWith(
        busyOperation: SettingsBusyOperation.storageOperation,
      );
      expect(storageBusy.isBusy, isTrue);
      expect(storageBusy.isSavingWebDav, isFalse);
      expect(storageBusy.isTestingConnection, isFalse);
      expect(storageBusy.isStorageOperationBusy, isTrue);

      final cleared = base.copyWith(
        clearServerUrlError: true,
        clearUsernameError: true,
        clearPasswordError: true,
        clearFilePathError: true,
        clearStatusBanner: true,
        clearResolvedLocalPathPreview: true,
      );
      expect(cleared.serverUrlError, isNull);
      expect(cleared.usernameError, isNull);
      expect(cleared.passwordError, isNull);
      expect(cleared.filePathError, isNull);
      expect(cleared.statusBanner, isNull);
      expect(cleared.resolvedLocalPathPreview, isNull);
      expect(cleared, isNot(equals(base)));

      const emptyEndpoint = SettingsDraftState(serverUrl: '');
      expect(emptyEndpoint.endpointPreview, isEmpty);
    });
  });

  group('SettingsDraftNotifier hydration, local preview, and zero keystroke allocation', () {
    test('hydrates from persisted config, updates resolvedLocalPathPreview only on local path changes, and never allocates LocalFileRepository on WebDAV keystrokes or unrelated preferences', () async {
      var localRepositoryBuildCount = 0;
      final settingsRepository = InMemorySettingsRepository(configuredWebDav);
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          localStorageDirectoryPathProvider.overrideWithValue('/tmp/tt'),
          webDavRepositoryProvider.overrideWithValue(
            FakeWebDavRepository(
              config: configuredWebDav,
              shouldFail: () => false,
            ),
          ),
          localFileRepositoryProvider.overrideWith((ref) {
            localRepositoryBuildCount++;
            final slice = ref.watch(
              webDavConfigProvider.select((asyncConfig) {
                final config = asyncConfig.asData?.value;
                if (config == null) {
                  return null;
                }
                return (
                  localFilePath: config.localFilePath,
                  language: config.language,
                  storageMode: config.storageMode,
                );
              }),
            );
            final config = slice == null
                ? const WebDavConfig()
                : WebDavConfig(
                    localFilePath: slice.localFilePath,
                    language: slice.language,
                    storageMode: slice.storageMode,
                  );
            return LocalFileRepository(
              config: config,
              baseDirectoryPath: ref.watch(localStorageDirectoryPathProvider),
              buildProfile: ref.watch(appBuildProfileProvider),
            );
          }),
          taskNotifierProvider.overrideWith(_RecordingTaskNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);

      final subscription = container.listen(settingsDraftProvider, (_, _) {});
      addTearDown(subscription.close);

      final initial = container.read(settingsDraftProvider);
      expect(initial.serverUrl, equals('https://cloud.example.com'));
      expect(initial.username, equals('alice'));
      expect(initial.password, equals('super-secret-password'));
      expect(initial.filePath, equals('notes/tasks.tdf'));
      expect(initial.isDirty, isFalse);
      expect(
        initial.resolvedLocalPathPreview,
        equals('/tmp/tt${Platform.pathSeparator}tasks.tdf'),
      );
      expect(localRepositoryBuildCount, equals(1));

      final notifier = container.read(settingsDraftProvider.notifier);

      // WebDAV keystrokes must NEVER rebuild localFileRepositoryProvider.
      for (var i = 0; i < 10; i++) {
        notifier.updateWebDavDraft(
          serverUrl: 'https://edit-$i.example.com',
          username: 'user$i',
          filePath: 'folder/board-$i.tdf',
        );
      }
      expect(
        localRepositoryBuildCount,
        equals(1),
        reason: 'WebDAV keystrokes must not construct LocalFileRepository',
      );
      expect(container.read(settingsDraftProvider).isDirty, isTrue);

      // Unrelated auto-saved preferences must NEVER rebuild localFileRepositoryProvider or wipe dirty WebDAV draft.
      var draftNotificationsDuringPreferences = 0;
      final preferenceCounterSub = container.listen(
        settingsDraftProvider,
        (_, _) => draftNotificationsDuringPreferences++,
      );
      addTearDown(preferenceCounterSub.close);

      final configNotifier = container.read(webDavConfigProvider.notifier);
      await configNotifier.updateThemeMode(AppThemeMode.dark);
      await configNotifier.updateThemePalette(AppThemePalette.plumUmber);
      await configNotifier.updateTimeZoneMode(AppTimeZoneMode.manual);
      await configNotifier.updateManualTimeZoneOffsetMinutes(120);
      await configNotifier.updateDueLeadWindow(DueLeadWindow.hours48);
      await configNotifier.updateLocationEnabled(true);
      await configNotifier.updateLogStorageMode(StorageMode.both);
      await configNotifier.updateDiagnosticsEnabled(true);
      await configNotifier.updateLogLevel(LogLevel.debug);
      await configNotifier.updateLocalWatchEnabled(false);

      final afterPreferences = container.read(settingsDraftProvider);
      container.read(localFileRepositoryProvider);
      expect(
        localRepositoryBuildCount,
        equals(1),
        reason: 'Unrelated preferences must not rebuild LocalFileRepository',
      );
      expect(
        draftNotificationsDuringPreferences,
        equals(0),
        reason: 'Unrelated preferences must not trigger settingsDraftProvider rebuilds',
      );
      expect(afterPreferences.isDirty, isTrue);
      expect(
        afterPreferences.serverUrl,
        equals('https://edit-9.example.com'),
        reason: 'Unrelated preferences must not clobber dirty WebDAV draft',
      );

      // Updating localFilePath DOES update resolvedLocalPathPreview while keeping dirty WebDAV draft.
      await configNotifier.updateConfig(
        container
            .read(webDavConfigProvider)
            .requireValue
            .copyWith(localFilePath: 'renamed.tdf'),
      );
      final afterLocalPathChange = container.read(settingsDraftProvider);
      expect(
        afterLocalPathChange.resolvedLocalPathPreview,
        equals('/tmp/tt${Platform.pathSeparator}renamed.tdf'),
      );
      expect(localRepositoryBuildCount, equals(2));
      expect(afterLocalPathChange.isDirty, isTrue);
    });

    test('hydrates draft fields when webDavConfigProvider resolves asynchronously after build', () async {
      final loadGate = Completer<void>();
      final settingsRepository = InMemorySettingsRepository(configuredWebDav);
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          webDavConfigProvider.overrideWith(() {
            return _DelayedBuildWebDavConfigNotifier(
              loadGate: loadGate,
              loadedConfig: configuredWebDav,
            );
          }),
          localStorageDirectoryPathProvider.overrideWithValue('/tmp/async'),
          taskNotifierProvider.overrideWith(_RecordingTaskNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(settingsDraftProvider, (_, _) {});
      addTearDown(subscription.close);

      expect(container.read(settingsDraftProvider).serverUrl, isEmpty);

      loadGate.complete();
      await container.read(webDavConfigProvider.future);

      final hydrated = container.read(settingsDraftProvider);
      expect(hydrated.serverUrl, equals('https://cloud.example.com'));
      expect(hydrated.username, equals('alice'));
      expect(hydrated.password, equals('super-secret-password'));
      expect(hydrated.filePath, equals('notes/tasks.tdf'));
      expect(hydrated.isDirty, isFalse);
      expect(
        hydrated.resolvedLocalPathPreview,
        equals('/tmp/async${Platform.pathSeparator}tasks.tdf'),
      );
    });
  });

  group(
    'SettingsDraftNotifier dirty tracking, silent discard, and autoDispose',
    () {
      test('tracks dirty state, clears edited field error only, and discards on StorageMode.local via setStorageMode or direct config update', () async {
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
            taskNotifierProvider.overrideWith(_RecordingTaskNotifier.new),
          ],
        );
        addTearDown(container.dispose);
        await container.read(activeWorkspaceProvider.future);
        await container.read(webDavConfigProvider.future);
        final subscription = container.listen(settingsDraftProvider, (_, _) {});
        addTearDown(subscription.close);

        final notifier = container.read(settingsDraftProvider.notifier);

        // No-op call with all null fields is ignored.
        var notificationCount = 0;
        final counterSub = container.listen(
          settingsDraftProvider,
          (_, _) => notificationCount++,
        );
        addTearDown(counterSub.close);
        notifier.updateWebDavDraft();
        expect(notificationCount, equals(0));

        // Edit and revert clears isDirty.
        notifier.updateWebDavDraft(serverUrl: 'https://temp.example.com');
        expect(container.read(settingsDraftProvider).isDirty, isTrue);
        notifier.updateWebDavDraft(serverUrl: 'https://cloud.example.com');
        expect(
          container.read(settingsDraftProvider).isDirty,
          isFalse,
          reason: 'Reverting draft back to persisted values clears dirty state',
        );

        // Trigger validation errors on all 4 fields.
        notifier.updateWebDavDraft(
          serverUrl: 'https://user:pass@cloud.example.com',
          username: '',
          password: '',
          filePath: '../secret.tdf',
        );
        final failed = await notifier.saveWebDavDraft();
        expect(failed, isA<ActionValidationFailed>());
        var draft = container.read(settingsDraftProvider);
        expect(draft.serverUrlError, isNotNull);
        expect(draft.usernameError, isNotNull);
        expect(draft.passwordError, isNotNull);
        expect(draft.filePathError, isNotNull);
        expect(draft.statusBanner?.tone, equals(SettingsBannerTone.danger));

        // Editing 3 fields clears only those 3 errors and clears statusBanner.
        notifier.updateWebDavDraft(
          serverUrl: 'https://next.example.com',
          username: 'bob',
          filePath: 'work/board.tdf',
        );
        draft = container.read(settingsDraftProvider);
        expect(draft.serverUrlError, isNull);
        expect(draft.usernameError, isNull);
        expect(draft.filePathError, isNull);
        expect(draft.passwordError, isNotNull);
        expect(draft.statusBanner, isNull);
        expect(
          draft.endpointPreview,
          equals(
            'https://next.example.com/remote.php/dav/files/bob/work/board.tdf',
          ),
        );

        // Switching to StorageMode.local via setStorageMode silently discards draft and logs once.
        final switchResult = await notifier.setStorageMode(StorageMode.local);
        expect(switchResult, isA<ActionSucceeded>());
        draft = container.read(settingsDraftProvider);
        expect(draft.isDirty, isFalse);
        expect(draft.serverUrl, equals('https://cloud.example.com'));
        expect(draft.username, equals('alice'));
        expect(draft.password, equals('super-secret-password'));
        expect(draft.filePath, equals('notes/tasks.tdf'));
        expect(draft.serverUrlError, isNull);
        expect(draft.usernameError, isNull);
        expect(draft.passwordError, isNull);
        expect(draft.filePathError, isNull);
        final localDiscardLogs = AppLogger.lines
            .where(
              (line) =>
                  line.contains('ui.settings_webdav_draft_discarded') &&
                  line.contains('reason=storage_mode_local'),
            )
            .toList();
        expect(
          localDiscardLogs,
          hasLength(1),
          reason:
              'Switching to local mode must log discard telemetry exactly once',
        );

        // Switch back to StorageMode.both, dirty draft again, then trigger direct updateStorageMode(local).
        AppLogger.clear();
        await notifier.setStorageMode(StorageMode.both);
        notifier.updateWebDavDraft(
          serverUrl: 'https://direct-discard.example.com',
        );
        expect(container.read(settingsDraftProvider).isDirty, isTrue);

        await container
            .read(webDavConfigProvider.notifier)
            .updateStorageMode(StorageMode.local);
        draft = container.read(settingsDraftProvider);
        expect(draft.isDirty, isFalse);
        expect(draft.serverUrl, equals('https://cloud.example.com'));
        expect(
          AppLogger.lines.any(
            (line) =>
                line.contains('ui.settings_webdav_draft_discarded') &&
                line.contains('reason=storage_mode_local'),
          ),
          isTrue,
        );
      });

      test('silently discards dirty WebDAV edits on navigation away from settings, on workspace switch, and on manual discard', () async {
        enableInMemoryLogger();
        final settingsRepository = InMemorySettingsRepository(configuredWebDav);
        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepository),
            localStorageDirectoryPathProvider.overrideWithValue('/tmp/ws'),
            taskNotifierProvider.overrideWith(_RecordingTaskNotifier.new),
          ],
        );
        addTearDown(container.dispose);
        await container.read(activeWorkspaceProvider.future);
        await container.read(webDavConfigProvider.future);
        final shellSub = container.listen(shellProvider, (_, _) {});
        final draftSub = container.listen(settingsDraftProvider, (_, _) {});
        addTearDown(shellSub.close);
        addTearDown(draftSub.close);

        final shellNotifier = container.read(shellProvider.notifier);
        final draftNotifier = container.read(settingsDraftProvider.notifier);

        // Enter Settings, dirty draft + validation error, then leave Settings.
        shellNotifier.openView(ShellView.settings);
        draftNotifier.updateWebDavDraft(serverUrl: 'ftp://bad.example.com');
        await draftNotifier.saveWebDavDraft();
        expect(container.read(settingsDraftProvider).isDirty, isTrue);
        expect(container.read(settingsDraftProvider).serverUrlError, isNotNull);

        shellNotifier.openView(ShellView.tasks);
        var draft = container.read(settingsDraftProvider);
        expect(draft.isDirty, isFalse);
        expect(draft.serverUrl, equals('https://cloud.example.com'));
        expect(draft.serverUrlError, isNull);
        expect(
          AppLogger.lines.any(
            (line) =>
                line.contains('ui.settings_webdav_draft_discarded') &&
                line.contains('reason=navigation'),
          ),
          isTrue,
        );

        // Re-enter Settings, dirty draft again, and switch to a StorageMode.local workspace.
        AppLogger.clear();
        shellNotifier.openView(ShellView.settings);
        draftNotifier.updateWebDavDraft(
          serverUrl: 'https://dirty-before-switch.example.com',
        );
        expect(container.read(settingsDraftProvider).isDirty, isTrue);

        const secondWorkspaceConfig = WebDavConfig(
          serverUrl: 'https://personal.example.com',
          username: 'carol',
          password: 'personal-password',
          filePath: 'personal.tdf',
          localFilePath: 'personal.tdf',
          storageMode: StorageMode.local,
        );
        await container
            .read(activeWorkspaceProvider.notifier)
            .createWorkspace(
              'Personal',
              config: secondWorkspaceConfig,
              activate: true,
            );
        await container.read(webDavConfigProvider.future);

        draft = container.read(settingsDraftProvider);
        expect(draft.isDirty, isFalse);
        expect(draft.serverUrl, equals('https://personal.example.com'));
        expect(draft.username, equals('carol'));
        expect(
          draft.resolvedLocalPathPreview,
          equals('/tmp/ws${Platform.pathSeparator}personal.tdf'),
        );
        expect(
          AppLogger.lines.any(
            (line) =>
                line.contains('ui.settings_webdav_draft_discarded') &&
                line.contains('reason=workspace_switch'),
          ),
          isTrue,
          reason: 'Workspace switch to local workspace must log workspace_switch, not storage_mode_local',
        );

        // Manual discard resets edits and logs reason=manual.
        AppLogger.clear();
        draftNotifier.updateWebDavDraft(username: 'edited');
        expect(container.read(settingsDraftProvider).isDirty, isTrue);
        draftNotifier.discardWebDavDraft();
        expect(container.read(settingsDraftProvider).isDirty, isFalse);
        expect(container.read(settingsDraftProvider).username, equals('carol'));
        expect(
          AppLogger.lines.any(
            (line) =>
                line.contains('ui.settings_webdav_draft_discarded') &&
                line.contains('reason=manual'),
          ),
          isTrue,
        );

        // Leaving Settings with stale validation errors while not dirty clears errors without logging draft discard.
        const unconfiguredWebDav = WebDavConfig(
          localFilePath: 'blank_webdav.tdf',
          filePath: 'blank_webdav.tdf',
          storageMode: StorageMode.both,
          language: AppLanguage.english,
        );
        await container
            .read(activeWorkspaceProvider.notifier)
            .createWorkspace(
              'BlankWebDav',
              config: unconfiguredWebDav,
              activate: true,
            );
        await container.read(webDavConfigProvider.future);
        AppLogger.clear();
        shellNotifier.openView(ShellView.settings);
        expect(
          await draftNotifier.saveWebDavDraft(),
          isA<ActionValidationFailed>(),
        );
        expect(container.read(settingsDraftProvider).isDirty, isFalse);
        expect(container.read(settingsDraftProvider).serverUrlError, isNotNull);

        shellNotifier.openView(ShellView.tasks);
        expect(container.read(settingsDraftProvider).serverUrlError, isNull);
        expect(
          AppLogger.lines.any(
            (line) => line.contains('ui.settings_webdav_draft_discarded'),
          ),
          isFalse,
          reason: 'Clean draft with stale validation errors must not log draft discard on navigation',
        );

        // Switching to StorageMode.local while not dirty clears stale errors without logging draft discard.
        shellNotifier.openView(ShellView.settings);
        expect(
          await draftNotifier.saveWebDavDraft(),
          isA<ActionValidationFailed>(),
        );
        expect(container.read(settingsDraftProvider).serverUrlError, isNotNull);
        await draftNotifier.setStorageMode(StorageMode.local);
        expect(container.read(settingsDraftProvider).serverUrlError, isNull);
        expect(
          AppLogger.lines.any(
            (line) => line.contains('ui.settings_webdav_draft_discarded'),
          ),
          isFalse,
        );
      });

      test('autoDisposes when listeners detach and handles disposal mid-flight without throwing', () async {
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
            taskNotifierProvider.overrideWith(_RecordingTaskNotifier.new),
          ],
        );
        addTearDown(container.dispose);
        await container.read(activeWorkspaceProvider.future);
        await container.read(webDavConfigProvider.future);

        final subscription = container.listen(settingsDraftProvider, (_, _) {});
        final notifier = container.read(settingsDraftProvider.notifier);
        notifier.updateWebDavDraft(
          serverUrl: 'https://unsaved-disposed.example.com',
        );
        notifier.showErrorBanner('Transient error');
        expect(container.read(settingsDraftProvider).isDirty, isTrue);

        // Start suspended save, then close all listeners so .autoDispose tears down the provider.
        final inFlightSave = notifier.saveWebDavDraft();
        subscription.close();
        await Future<void>.delayed(Duration.zero);

        completer.complete();
        final result = await inFlightSave;
        expect(result, isA<ActionSucceeded>());

        // Re-subscribing after autoDispose starts from fresh clean state.
        final freshSub = container.listen(settingsDraftProvider, (_, _) {});
        addTearDown(freshSub.close);
        final freshState = container.read(settingsDraftProvider);
        expect(freshState.isDirty, isFalse);
        expect(freshState.statusBanner, isNull);
        expect(freshState.busyOperation, equals(SettingsBusyOperation.idle));
      });
    },
  );

  group('SettingsDraftNotifier WebDAV validation, save, and testConnectionAndSync (M-URI-PATH-EDGE-TESTS)', () {
    test('rejects empty credentials, invalid server URLs, embedded userinfo, and traversal/control remote paths', () async {
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
          taskNotifierProvider.overrideWith(_RecordingTaskNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);
      final subscription = container.listen(settingsDraftProvider, (_, _) {});
      addTearDown(subscription.close);

      final notifier = container.read(settingsDraftProvider.notifier);

      // Empty serverUrl, username, and password produce per-field errors and danger banner.
      notifier.updateWebDavDraft(
        serverUrl: '   ',
        username: '  ',
        password: '',
        filePath: 'tasks.tdf',
      );
      final emptyResult = await notifier.saveWebDavDraft();
      expect(emptyResult, isA<ActionValidationFailed>());
      if (emptyResult case final ActionValidationFailed failure) {
        expect(failure.message, equals(localizations.serverUrlErrorEmpty));
        expect(
          failure.fieldErrors,
          equals(<String, String>{
            'serverUrl': localizations.serverUrlErrorEmpty,
            'username': localizations.usernameErrorEmpty,
            'password': localizations.passwordErrorEmpty,
          }),
        );
      }
      var draft = container.read(settingsDraftProvider);
      expect(draft.serverUrlError, equals(localizations.serverUrlErrorEmpty));
      expect(draft.usernameError, equals(localizations.usernameErrorEmpty));
      expect(draft.passwordError, equals(localizations.passwordErrorEmpty));
      expect(draft.filePathError, isNull);
      expect(
        draft.statusBanner,
        equals(
          SettingsStatusBanner(
            tone: SettingsBannerTone.danger,
            message: localizations.serverUrlErrorEmpty,
          ),
        ),
      );

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
        (
          input: 'https://cloud.example.com/./dav',
          expectedError: localizations.errorInvalidServerUrl,
        ),
      ];

      for (final testCase in invalidServerUrlCases) {
        notifier.updateWebDavDraft(
          serverUrl: testCase.input,
          username: 'alice',
          password: 'secret',
          filePath: 'tasks.tdf',
        );
        final result = await notifier.saveWebDavDraft();
        expect(
          result,
          isA<ActionValidationFailed>(),
          reason:
              'Expected validation failure for serverUrl "${testCase.input}"',
        );
        draft = container.read(settingsDraftProvider);
        expect(
          draft.serverUrlError,
          equals(testCase.expectedError),
          reason: 'Unexpected serverUrlError for "${testCase.input}"',
        );
        expect(
          draft.statusBanner?.tone,
          equals(SettingsBannerTone.danger),
          reason: 'Expected danger banner for "${testCase.input}"',
        );
      }

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
        notifier.updateWebDavDraft(
          serverUrl: 'https://cloud.example.com',
          username: 'alice',
          password: 'secret',
          filePath: badPath,
        );
        final result = await notifier.saveWebDavDraft();
        expect(
          result,
          isA<ActionValidationFailed>(),
          reason: 'Expected validation failure for remote filePath "$badPath"',
        );
        draft = container.read(settingsDraftProvider);
        expect(
          draft.filePathError,
          equals(localizations.webDavPathInvalidError),
          reason: 'Expected webDavPathInvalidError for "$badPath"',
        );
      }
      expect(configNotifier.calls, isEmpty);
    });

    test('saves valid WebDAV draft with default filename fallback, handles errors, and tests connection and sync', () async {
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
      final subscription = container.listen(settingsDraftProvider, (_, _) {});
      addTearDown(subscription.close);

      final notifier = container.read(settingsDraftProvider.notifier);

      // Valid save with blank filePath falls back to defaultFileName and trims fields.
      notifier.updateWebDavDraft(
        serverUrl: '  https://dav.example.com:8443/nextcloud  ',
        username: '  bob  ',
        password: 'app-password',
        filePath: '   ',
      );
      final saveResult = await notifier.saveWebDavDraft();
      expect(
        saveResult,
        equals(
          ActionSucceeded(noticeMessage: localizations.credentialsSavedBanner),
        ),
      );
      var draft = container.read(settingsDraftProvider);
      expect(draft.isDirty, isFalse);
      expect(draft.serverUrl, equals('https://dav.example.com:8443/nextcloud'));
      expect(draft.username, equals('bob'));
      expect(draft.filePath, equals(WebDavConfig.defaultFileName));
      expect(
        draft.statusBanner,
        equals(
          SettingsStatusBanner(
            tone: SettingsBannerTone.success,
            message: localizations.credentialsSavedBanner,
          ),
        ),
      );

      // Save failure preserves dirty edits and shows danger banner.
      notifier.updateWebDavDraft(serverUrl: 'https://fail-save.example.com');
      configNotifier.updateErrorToThrow = const WorkspaceException(
        WorkspaceErrorKind.credentialStorageUnavailable,
        'locked',
      );
      final failedSave = await notifier.saveWebDavDraft();
      expect(failedSave, isA<ActionPersistFailed>());
      expect(container.read(settingsDraftProvider).isDirty, isTrue);
      expect(
        container.read(settingsDraftProvider).statusBanner?.tone,
        equals(SettingsBannerTone.danger),
      );
      configNotifier.updateErrorToThrow = null;

      // Test connection and sync succeeds and updates banner.
      notifier.updateWebDavDraft(
        serverUrl: 'https://sync.example.com',
        filePath: 'team/tasks.tdf',
      );
      final syncResult = await notifier.testConnectionAndSync();
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
      expect(container.read(settingsDraftProvider).isDirty, isFalse);
      expect(
        container.read(settingsDraftProvider).statusBanner,
        equals(
          SettingsStatusBanner(
            tone: SettingsBannerTone.success,
            message: localizations.connectionSuccessBanner,
          ),
        ),
      );

      // Test connection and sync failure shows sanitized danger banner.
      taskNotifier.testSyncErrorToThrow = const WebDavException(
        'Authentication failed',
        statusCode: 401,
      );
      final syncFailure = await notifier.testConnectionAndSync();
      expect(syncFailure, isA<ActionPersistFailed>());
      expect(
        container.read(settingsDraftProvider).statusBanner,
        equals(
          const SettingsStatusBanner(
            tone: SettingsBannerTone.danger,
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
      final readFailure = await notifier.testConnectionAndSync();
      expect(readFailure, isA<ActionPersistFailed>());
      expect(
        container.read(settingsDraftProvider).statusBanner?.tone,
        equals(SettingsBannerTone.danger),
      );
      expect(
        container.read(settingsDraftProvider).statusBanner?.message,
        contains('Unexpected token'),
      );

      // Blocked in local storage mode.
      taskNotifier.testSyncErrorToThrow = null;
      final callCountBeforeLocal = taskNotifier.calls.length;
      await notifier.setStorageMode(StorageMode.local);
      final blockedInLocal = await notifier.testConnectionAndSync();
      expect(
        blockedInLocal,
        equals(
          ActionValidationFailed(
            message: localizations.errorWebDavNotConfigured,
          ),
        ),
      );
      expect(taskNotifier.calls.length, equals(callCountBeforeLocal));
    });
  });

  group(
    'SettingsDraftNotifier savePreference optimistic non-blocking behavior',
    () {
      test('allows concurrent optimistic preference toggles without setting isBusy and surfaces localized WorkspaceException danger banner', () async {
        final delayedRepo = _DelayedWorkspaceSettingsRepository(
          configuredWebDav,
        );
        final gate1 = Completer<void>();
        final gate2 = Completer<void>();
        delayedRepo.saveGates.addAll(<Completer<void>>[gate1, gate2]);

        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(delayedRepo),
            appLocaleProvider.overrideWithValue(const Locale('en')),
            taskNotifierProvider.overrideWith(_RecordingTaskNotifier.new),
          ],
        );
        addTearDown(container.dispose);
        await container.read(activeWorkspaceProvider.future);
        await container.read(webDavConfigProvider.future);
        final subscription = container.listen(settingsDraftProvider, (_, _) {});
        addTearDown(subscription.close);

        final draftNotifier = container.read(settingsDraftProvider.notifier);

        // Show a prior danger banner so we can verify successful savePreference clears it.
        draftNotifier.showErrorBanner('Stale failure');
        expect(
          container.read(settingsDraftProvider).statusBanner,
          equals(
            const SettingsStatusBanner(
              tone: SettingsBannerTone.danger,
              message: 'Stale failure',
            ),
          ),
        );

        // Fire two rapid preference toggles concurrently while disk writes are suspended.
        final firstToggle = draftNotifier.savePreference(
          (configNotifier) =>
              configNotifier.updateThemePalette(AppThemePalette.plumUmber),
        );
        final secondToggle = draftNotifier.savePreference(
          (configNotifier) => configNotifier.updateThemeMode(AppThemeMode.dark),
        );

        // Neither click is blocked and settingsDraftProvider NEVER enters busy state!
        expect(
          container.read(settingsDraftProvider).isBusy,
          isFalse,
          reason:
              'Auto-saved preferences must never lock UI controls via isBusy',
        );
        expect(
          container.read(settingsDraftProvider).busyOperation,
          equals(SettingsBusyOperation.idle),
        );

        // Both optimistic changes are already visible in webDavConfigProvider.
        final midFlightConfig = container
            .read(webDavConfigProvider)
            .requireValue;
        expect(midFlightConfig.themePalette, equals(AppThemePalette.plumUmber));
        expect(midFlightConfig.themeMode, equals(AppThemeMode.dark));

        gate1.complete();
        gate2.complete();
        expect(await firstToggle, equals(const ActionSucceeded()));
        expect(await secondToggle, equals(const ActionSucceeded()));
        expect(delayedRepo.persistedConfigs, hasLength(2));
        expect(
          delayedRepo.persistedConfigs.last.themePalette,
          equals(AppThemePalette.plumUmber),
        );
        expect(
          delayedRepo.persistedConfigs.last.themeMode,
          equals(AppThemeMode.dark),
        );
        expect(
          container.read(settingsDraftProvider).statusBanner,
          isNull,
          reason:
              'Successful savePreference must clear any prior danger banner',
        );

        // WorkspaceException displays localized danger banner and returns ActionPersistFailed.
        const failure = WorkspaceException(
          WorkspaceErrorKind.settingsPersistenceFailed,
          'disk full',
        );
        delayedRepo.errorToThrow = failure;
        final failed = await draftNotifier.savePreference(
          (configNotifier) =>
              configNotifier.updateThemeMode(AppThemeMode.light),
          locale: const Locale('de'),
        );
        final expectedMessage = lookupAppLocalizations(const Locale('de'))
            .localizeWorkspaceError(failure);
        expect(failed, equals(ActionPersistFailed(message: expectedMessage)));
        expect(
          container.read(settingsDraftProvider).statusBanner,
          equals(
            SettingsStatusBanner(
              tone: SettingsBannerTone.danger,
              message: expectedMessage,
            ),
          ),
        );

        draftNotifier.dismissStatusBanner();
        expect(container.read(settingsDraftProvider).statusBanner, isNull);
      });
    },
  );

  group('SettingsDraftNotifier capability-gated local storage and destructive wipes', () {
    test('supports list, native select, move, rename, and local/remote wipe when supportsDirectoryPickerProvider is true', () async {
      enableInMemoryLogger();
      final localizations = lookupAppLocalizations(const Locale('en'));
      final tempDirectory = Directory.systemTemp.createTempSync(
        'tiertask_settings_draft_',
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
          supportsDirectoryPickerProvider.overrideWithValue(true),
          localStorageDirectoryPathProvider.overrideWithValue(
            tempDirectory.path,
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
      final subscription = container.listen(settingsDraftProvider, (_, _) {});
      addTearDown(subscription.close);

      final notifier = container.read(settingsDraftProvider.notifier);

      // Dirty WebDAV draft must survive local file operations.
      notifier.updateWebDavDraft(
        serverUrl: 'https://dirty-local-ops.example.com',
      );
      expect(container.read(settingsDraftProvider).isDirty, isTrue);

      // List directory .tdf filenames.
      expect(
        notifier.listLocalTdfFileNames(),
        equals(const <String>['alpha.tdf', 'tasks.tdf']),
      );

      // Native select cancelled is a clean no-op.
      nativePickedFile = null;
      expect(await notifier.selectLocalFile(), equals(const ActionSucceeded()));
      expect(taskNotifier.calls, isEmpty);

      // Native select confirmed updates local path, logs telemetry, shows banner.
      nativePickedFile = '${tempDirectory.path}${separator}alpha.tdf';
      final selectResult = await notifier.selectLocalFile();
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
        container.read(settingsDraftProvider).resolvedLocalPathPreview,
        equals('${tempDirectory.path}${separator}alpha.tdf'),
      );
      expect(
        AppLogger.lines.any(
          (line) =>
              line.contains('Confirmed select local TDF dialog file=alpha.tdf'),
        ),
        isTrue,
      );

      // Move cancelled or unchanged directory returns no-op.
      nativePickedDirectory = null;
      final callCountBeforeCancel = configNotifier.calls.length;
      expect(
        await notifier.moveLocalDirectory(),
        equals(const ActionSucceeded()),
      );
      nativePickedDirectory = tempDirectory.path;
      expect(
        await notifier.moveLocalDirectory(),
        equals(const ActionSucceeded()),
      );
      expect(configNotifier.calls.length, equals(callCountBeforeCancel));

      // Move local directory follows host Platform.pathSeparator even when defaultTargetPlatform differs.
      final mismatchedPlatform = Platform.isWindows
          ? TargetPlatform.android
          : TargetPlatform.windows;
      debugDefaultTargetPlatformOverride = mismatchedPlatform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      nativePickedDirectory = '/mock/moved';
      final moveResult = await notifier.moveLocalDirectory();
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

      // Move error maps cleanly to danger banner.
      nativePickedDirectory = '/mock/fail-move';
      configNotifier.changeLocationErrorToThrow = const LocalFileException(
        'Destination already exists',
      );
      final failedMove = await notifier.moveLocalDirectory();
      expect(
        failedMove,
        equals(
          const ActionPersistFailed(message: 'Destination already exists'),
        ),
      );
      expect(
        container.read(settingsDraftProvider).statusBanner?.tone,
        equals(SettingsBannerTone.danger),
      );
      configNotifier.changeLocationErrorToThrow = null;

      // Rename rejects invalid local filenames (M-URI-PATH-EDGE-TESTS).
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
        final invalidRename = await notifier.renameLocalFile(badName);
        expect(
          invalidRename,
          isA<ActionValidationFailed>(),
          reason: 'Expected renameLocalFile to reject "$badName"',
        );
        expect(
          container.read(settingsDraftProvider).statusBanner?.message,
          equals(localizations.localFileNameErrorInvalid),
          reason: 'Expected localFileNameErrorInvalid for "$badName"',
        );
      }

      // Unchanged filename is a clean no-op.
      final callCountBeforeNoop = configNotifier.calls.length;
      expect(
        await notifier.renameLocalFile('alpha'),
        equals(const ActionSucceeded()),
      );
      expect(configNotifier.calls.length, equals(callCountBeforeNoop));

      // Valid rename appends .tdf, calls changeLocalFileLocation, logs telemetry, shows banner.
      final renameResult = await notifier.renameLocalFile('renamed');
      expect(
        renameResult,
        equals(
          ActionSucceeded(noticeMessage: localizations.localFileRenamedBanner),
        ),
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
      final failedRename = await notifier.renameLocalFile('other');
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
      final wipeLocalResult = await notifier.wipeLocalFile(createBackup: true);
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
      final failedLocalWipe = await notifier.wipeLocalFile(createBackup: false);
      expect(
        failedLocalWipe,
        equals(const ActionPersistFailed(message: 'Permission denied')),
      );
      taskNotifier.wipeLocalErrorToThrow = null;

      // Wipe remote file logs telemetry and shows success banner.
      final wipeRemoteResult = await notifier.wipeRemoteFile(
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
      final failedRemoteWipe = await notifier.wipeRemoteFile(
        createBackup: true,
      );
      expect(
        failedRemoteWipe,
        equals(
          const ActionPersistFailed(message: 'Server unavailable (HTTP 503)'),
        ),
      );

      // Dirty WebDAV draft survived all local & remote storage operations.
      expect(container.read(settingsDraftProvider).isDirty, isTrue);
      expect(
        container.read(settingsDraftProvider).serverUrl,
        equals('https://dirty-local-ops.example.com'),
      );
    });

    test('gates moveLocalDirectory, selects by bare filename, and rejects invalid wipe paths when supportsDirectoryPickerProvider is false', () async {
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
      final subscription = container.listen(settingsDraftProvider, (_, _) {});
      addTearDown(subscription.close);

      final notifier = container.read(settingsDraftProvider.notifier);

      final moveBlocked = await notifier.moveLocalDirectory();
      expect(
        moveBlocked,
        equals(
          ActionValidationFailed(
            message: localizations.settingsMoveDesktopOnlyTooltip,
          ),
        ),
      );
      expect(directoryPickerCalled, isFalse);

      expect(await notifier.selectLocalFile(), isA<ActionValidationFailed>());
      expect(
        await notifier.selectLocalFile(chosenFileName: '../outside.tdf'),
        isA<ActionValidationFailed>(),
      );

      final selected = await notifier.selectLocalFile(chosenFileName: 'work');
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

      final wipeRemoteBlocked = await notifier.wipeRemoteFile(
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

      // Invalid local path blocks wipeLocalFile cleanly with danger banner.
      await configNotifier.updateConfig(
        localOnlyConfig.copyWith(localFilePath: '../invalid.tdf'),
      );
      final wipeLocalBlocked = await notifier.wipeLocalFile(
        createBackup: false,
      );
      expect(
        wipeLocalBlocked,
        equals(
          ActionValidationFailed(
            message: localizations.errorInvalidLocalFilePath,
          ),
        ),
      );
      expect(
        container.read(settingsDraftProvider).statusBanner?.tone,
        equals(SettingsBannerTone.danger),
      );
    });

    test('preserves bare filename on rename when no base directory or path separator exists', () async {
      const bareConfig = WebDavConfig(
        localFilePath: 'tasks.tdf',
        storageMode: StorageMode.local,
        language: AppLanguage.english,
      );
      final configNotifier = _RecordingWebDavConfigNotifier(
        initialConfig: bareConfig,
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(bareConfig),
          ),
          webDavConfigProvider.overrideWith(() => configNotifier),
          localStorageDirectoryPathProvider.overrideWithValue(null),
          appLocaleProvider.overrideWithValue(const Locale('en')),
          taskNotifierProvider.overrideWith(_RecordingTaskNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);
      final subscription = container.listen(settingsDraftProvider, (_, _) {});
      addTearDown(subscription.close);

      final result = await container
          .read(settingsDraftProvider.notifier)
          .renameLocalFile('notes');
      expect(result, isA<ActionSucceeded>());
      expect(
        configNotifier.calls.last,
        equals('changeLocalFileLocation:notes.tdf'),
      );
    });
  });

  group('SettingsDraftNotifier mid-flight Completer busy guards (M-REAL-MECHANICS-TESTS)', () {
    test('sets saveWebDav busy state, ignores duplicate WebDAV submits while suspended, and clears busy on completion', () async {
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
          taskNotifierProvider.overrideWith(_RecordingTaskNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);
      final subscription = container.listen(settingsDraftProvider, (_, _) {});
      addTearDown(subscription.close);

      final notifier = container.read(settingsDraftProvider.notifier);
      notifier.updateWebDavDraft(serverUrl: 'https://inflight.example.com');

      final firstSave = notifier.saveWebDavDraft();
      final midFlight = container.read(settingsDraftProvider);
      expect(midFlight.isBusy, isTrue);
      expect(midFlight.isSavingWebDav, isTrue);
      expect(midFlight.busyOperation, equals(SettingsBusyOperation.saveWebDav));

      // Duplicate concurrent submit is ignored while busy.
      final duplicate = await notifier.saveWebDavDraft();
      expect(duplicate, equals(const ActionSucceeded()));
      expect(
        configNotifier.calls,
        equals(const <String>['updateConfig']),
        reason: 'Busy guard must block concurrent duplicate WebDAV saves',
      );

      completer.complete();
      expect(await firstSave, isA<ActionSucceeded>());

      final settled = container.read(settingsDraftProvider);
      expect(settled.isBusy, isFalse);
      expect(settled.isDirty, isFalse);
      expect(settled.serverUrl, equals('https://inflight.example.com'));
    });

    test('drops stale completion banner when workspace switches across await boundary', () async {
      final completer = Completer<void>();
      final settingsRepository = InMemorySettingsRepository(configuredWebDav);
      final taskNotifier = _RecordingTaskNotifier(TaskBoard.empty())
        ..pendingActionCompleter = completer;
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          localStorageDirectoryPathProvider.overrideWithValue('/tmp/switch'),
          taskNotifierProvider.overrideWith(() => taskNotifier),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(webDavConfigProvider.future);
      await container.read(taskNotifierProvider.future);
      final subscription = container.listen(settingsDraftProvider, (_, _) {});
      addTearDown(subscription.close);

      final notifier = container.read(settingsDraftProvider.notifier);
      final wipeFuture = notifier.wipeLocalFile(createBackup: false);
      expect(
        container.read(settingsDraftProvider).isStorageOperationBusy,
        isTrue,
      );

      await container
          .read(activeWorkspaceProvider.notifier)
          .createWorkspace(
            'Secondary',
            config: const WebDavConfig(localFilePath: 'secondary.tdf'),
            activate: true,
          );
      await container.read(webDavConfigProvider.future);

      expect(container.read(settingsDraftProvider).isBusy, isFalse);
      expect(
        container.read(settingsDraftProvider).resolvedLocalPathPreview,
        equals('/tmp/switch${Platform.pathSeparator}secondary.tdf'),
      );

      completer.complete();
      await wipeFuture;
      final settled = container.read(settingsDraftProvider);
      expect(settled.statusBanner, isNull);
      expect(settled.isBusy, isFalse);
    });

    test('sets testConnectionAndSync busy state mid-flight and blocks concurrent actions until settled', () async {
      final completer = Completer<void>();
      final configNotifier = _RecordingWebDavConfigNotifier(
        initialConfig: configuredWebDav,
      );
      final taskNotifier = _RecordingTaskNotifier()
        ..pendingActionCompleter = completer;
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
      final subscription = container.listen(settingsDraftProvider, (_, _) {});
      addTearDown(subscription.close);

      final notifier = container.read(settingsDraftProvider.notifier);
      final pendingSync = notifier.testConnectionAndSync();
      final midFlight = container.read(settingsDraftProvider);
      expect(midFlight.isBusy, isTrue);
      expect(midFlight.isTestingConnection, isTrue);
      expect(
        midFlight.busyOperation,
        equals(SettingsBusyOperation.testConnectionAndSync),
      );

      // Concurrent blocking calls return cleanly without firing duplicate writes.
      expect(await notifier.saveWebDavDraft(), equals(const ActionSucceeded()));
      expect(
        await notifier.wipeLocalFile(createBackup: false),
        equals(const ActionSucceeded()),
      );
      expect(taskNotifier.calls, hasLength(1));

      completer.complete();
      expect(await pendingSync, isA<ActionSucceeded>());
      expect(container.read(settingsDraftProvider).isBusy, isFalse);
      expect(
        container.read(settingsDraftProvider).isTestingConnection,
        isFalse,
      );
    });
  });
}
