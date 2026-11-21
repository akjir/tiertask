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

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/presentation/app_shell_controller.dart';
import 'package:tiertask/presentation/log_viewer_controller.dart';
import 'package:tiertask/presentation/ui_v2_shell_models.dart';
import 'package:tiertask/presentation/workspace_v2_controller.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/ui_v2/views/settings_view.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import '../ui/test_helpers.dart';
import 'test_helpers.dart';

class _ControlledSettingsRepository extends InMemorySettingsRepository {
  _ControlledSettingsRepository(super.initialConfig);

  Completer<void>? saveGate;

  @override
  Future<void> saveConfig(WebDavConfig config) async {
    if (saveGate case final gate?) {
      await gate.future;
    }
    await super.saveConfig(config);
  }
}

class _SpyLocalFileRepository extends FakeLocalFileRepository {
  _SpyLocalFileRepository({
    required super.config,
    super.initialTdf = 'tdf 0.8.0\n',
    this.existingFileNames = const <String>['tasks.tdf', 'archive.tdf'],
    this.pickedDirectoryPath,
    this.pickedFilePath,
  });

  final List<String> existingFileNames;
  int pickDirectoryCalls = 0;
  int pickTdfFileCalls = 0;
  String? pickedDirectoryPath;
  String? pickedFilePath;

  @override
  List<String> listTdfFileNamesInDirectory() => existingFileNames;

  @override
  Future<String?> pickDirectory({String? initialDirectory}) async {
    pickDirectoryCalls++;
    return pickedDirectoryPath;
  }

  @override
  Future<String?> pickTdfFile({
    String? initialDirectory,
    String? currentFileName,
  }) async {
    pickTdfFileCalls++;
    return pickedFilePath;
  }
}

class _SpySettingsTaskNotifier extends FakeTaskNotifier {
  _SpySettingsTaskNotifier();

  final List<WebDavConfig> selectedLocalConfigs = <WebDavConfig>[];
  final List<WebDavConfig> testedConfigs = <WebDavConfig>[];
  Completer<void>? testSyncGate;

  @override
  Future<void> selectLocalFile(WebDavConfig newConfig) async {
    selectedLocalConfigs.add(newConfig);
    await ref.read(webDavConfigProvider.notifier).updateConfig(newConfig);
  }

  @override
  Future<void> testConnectionAndSync(WebDavConfig config) async {
    if (testSyncGate case final gate?) {
      await gate.future;
    }
    testedConfigs.add(config);
    await ref.read(webDavConfigProvider.notifier).updateConfig(config);
  }
}

class _SettingsTestFrame extends StatelessWidget {
  const _SettingsTestFrame({this.scrollController});

  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: SettingsView(scrollController: scrollController)),
          const SettingsActionDock(),
        ],
      ),
    );
  }
}

void main() {
  final localizations = lookupAppLocalizations(const Locale('en'));

  const configuredBoth = WebDavConfig(
    serverUrl: 'https://cloud.example.com',
    username: 'alice',
    password: 'app-password-secret',
    filePath: 'notes/tasks.tdf',
    localFilePath: 'tasks.tdf',
    storageMode: StorageMode.both,
    language: AppLanguage.english,
  );

  Future<void> scrollToAndTap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  setUp(() {
    AppLogger.resetForTesting(clock: () => DateTime.utc(2026, 11, 21, 12, 0));
  });

  tearDown(() {
    AppLogger.resetForTesting();
  });

  group('SettingsView auto-saved cards and immediate commits', () {
    testWidgets(
      'renders Auto-saved badges without Switch widgets and commits preferences immediately',
      (tester) async {
        final settingsRepository = InMemorySettingsRepository(
          const WebDavConfig(
            language: AppLanguage.english,
            themeMode: AppThemeMode.system,
            themePalette: AppThemePalette.calm,
            timeZoneMode: AppTimeZoneMode.automatic,
            dueLeadWindow: DueLeadWindow.hours24,
            locationEnabled: false,
            diagnosticsEnabled: false,
            storageMode: StorageMode.local,
            localWatchEnabled: true,
          ),
        );

        final container = await pumpV2Widget(
          tester,
          const _SettingsTestFrame(),
          settingsRepository: settingsRepository,
        );

        expect(find.text(localizations.settingsTitle), findsOneWidget);
        expect(
          find.text(
            localizations.settingsWorkspaceSubtitle(AppWorkspace.defaultName),
          ),
          findsOneWidget,
        );
        expect(
          find.byType(Switch),
          findsNothing,
          reason: 'U-COMP-002 forbids Material sliding Switch widgets',
        );
        expect(
          find.text(localizations.settingsAutoSavedBadge),
          findsNWidgets(9),
          reason: '8 preference cards plus Local TDF File card carry Auto-saved pills',
        );

        // Language commits immediately.
        await scrollToAndTap(
          tester,
          find.descendant(
            of: find.byKey(const ValueKey<String>('settings_language_control')),
            matching: find.text(localizations.languageGerman),
          ),
        );
        expect(
          (await settingsRepository.loadConfig()).language,
          equals(AppLanguage.german),
        );

        // Appearance commits immediately.
        await scrollToAndTap(
          tester,
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('settings_theme_mode_control'),
            ),
            matching: find.text(localizations.themeDark),
          ),
        );
        expect(
          (await settingsRepository.loadConfig()).themeMode,
          equals(AppThemeMode.dark),
        );

        // Color Palette Calm -> Plum Umber commits immediately.
        await scrollToAndTap(
          tester,
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('settings_theme_palette_control'),
            ),
            matching: find.text(localizations.themePalettePlumUmber),
          ),
        );
        expect(
          (await settingsRepository.loadConfig()).themePalette,
          equals(AppThemePalette.plumUmber),
        );

        // Time Zone Manual reveals all 37 supported UTC offsets and commits immediately.
        expect(
          find.byKey(const ValueKey<String>('settings_timezone_offset_select')),
          findsNothing,
          reason: 'UTC offset select stays hidden in Automatic mode',
        );
        await scrollToAndTap(
          tester,
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('settings_timezone_mode_control'),
            ),
            matching: find.text(localizations.timeZoneModeManual),
          ),
        );
        final offsetFieldFinder = find.byKey(
          const ValueKey<String>('settings_timezone_offset_select'),
        );
        expect(offsetFieldFinder, findsOneWidget);
        final offsetField = tester.widget<UiField>(offsetFieldFinder);
        expect(
          offsetField.selectOptions.length,
          equals(WebDavConfig.supportedUtcOffsetMinutes.length),
          reason: 'Manual UTC offset select must expose all 37 offsets',
        );
        expect(offsetField.selectOptions.length, equals(37));
        expect(offsetField.selectOptions.first.label, equals('UTC-12:00'));
        expect(offsetField.selectOptions.last.label, equals('UTC+14:00'));

        final offsetDropdown = find.descendant(
          of: offsetFieldFinder,
          matching: find.byType(DropdownButton<String>),
        );
        await scrollToAndTap(tester, offsetDropdown);
        await tester.tap(find.text('UTC+05:30').last);
        await tester.pumpAndSettle();
        expect(
          (await settingsRepository.loadConfig()).manualTimeZoneOffsetMinutes,
          equals(330),
        );

        // Deadline Prioritization exposes all 6 ShellDueLeadOption choices and commits immediately.
        final dueLeadFieldFinder = find.byKey(
          const ValueKey<String>('settings_due_lead_select'),
        );
        final dueLeadField = tester.widget<UiField>(dueLeadFieldFinder);
        expect(
          dueLeadField.selectOptions.length,
          equals(ShellDueLeadOption.values.length),
        );
        final dueLeadDropdown = find.descendant(
          of: dueLeadFieldFinder,
          matching: find.byType(DropdownButton<String>),
        );
        await scrollToAndTap(tester, dueLeadDropdown);
        await tester.tap(find.text(localizations.dueLeadWindow48Hours).last);
        await tester.pumpAndSettle();
        expect(
          (await settingsRepository.loadConfig()).dueLeadWindow,
          equals(DueLeadWindow.hours48),
        );

        // Foreground Location 2-way segmented control commits immediately.
        await scrollToAndTap(
          tester,
          find.descendant(
            of: find.byKey(const ValueKey<String>('settings_location_control')),
            matching: find.text(localizations.locationOn),
          ),
        );
        expect((await settingsRepository.loadConfig()).locationEnabled, isTrue);

        // Diagnostic Logging checkbox reveals Min Level, Log Storage, and Diagnostic Log viewer trigger.
        expect(
          find.byKey(const ValueKey<String>('settings_log_level_select')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('settings_open_log_viewer_button')),
          findsNothing,
        );
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey<String>('settings_diagnostics_toggle')),
        );
        expect(
          (await settingsRepository.loadConfig()).diagnosticsEnabled,
          isTrue,
        );

        final logLevelFieldFinder = find.byKey(
          const ValueKey<String>('settings_log_level_select'),
        );
        final logStorageFieldFinder = find.byKey(
          const ValueKey<String>('settings_log_storage_select'),
        );
        expect(logLevelFieldFinder, findsOneWidget);
        expect(logStorageFieldFinder, findsOneWidget);
        expect(
          tester.widget<UiField>(logLevelFieldFinder).selectOptions.length,
          equals(DiagnosticLogLevel.values.length),
        );
        expect(
          tester.widget<UiField>(logStorageFieldFinder).selectOptions.length,
          equals(ShellStorageMode.values.length),
        );

        await scrollToAndTap(
          tester,
          find.descendant(
            of: logLevelFieldFinder,
            matching: find.byType(DropdownButton<String>),
          ),
        );
        await tester.tap(find.text(localizations.logLevelDebug).last);
        await tester.pumpAndSettle();
        expect(
          (await settingsRepository.loadConfig()).logLevel,
          equals(LogLevel.debug),
        );

        await scrollToAndTap(
          tester,
          find.descendant(
            of: logStorageFieldFinder,
            matching: find.byType(DropdownButton<String>),
          ),
        );
        await tester.tap(find.text(localizations.logStorageBoth).last);
        await tester.pumpAndSettle();
        expect(
          (await settingsRepository.loadConfig()).logStorageMode,
          equals(StorageMode.both),
        );

        // Local Watch checkbox commits immediately.
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey<String>('settings_local_watch_toggle')),
        );
        expect(
          (await settingsRepository.loadConfig()).localWatchEnabled,
          isFalse,
        );

        // Tapping Diagnostic Log button routes shell to ShellView.logs.
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey<String>('settings_open_log_viewer_button')),
        );
        expect(
          container.read(appShellControllerProvider).view,
          equals(ShellView.logs),
        );
      },
    );

    testWidgets('Back to tasks header link routes shell to ShellView.tasks', (
      tester,
    ) async {
      final container = await pumpV2Widget(tester, const _SettingsTestFrame());
      container
          .read(appShellControllerProvider.notifier)
          .openView(ShellView.settings);
      await tester.pumpAndSettle();

      await tester.tap(find.text(localizations.actionBackToTasks));
      await tester.pumpAndSettle();

      expect(
        container.read(appShellControllerProvider).view,
        equals(ShellView.tasks),
      );
    });
  });

  group('WebDAV dirty flow, validation, dock emphasis swap, and local reset', () {
    testWidgets(
      'shows Unsaved changes in card and dock, swaps Save/Test emphasis, preserves caret, and clears on Local mode',
      (tester) async {
        final settingsRepository = _ControlledSettingsRepository(
          configuredBoth,
        );
        final spyTaskNotifier = _SpySettingsTaskNotifier();

        await pumpV2Widget(
          tester,
          const _SettingsTestFrame(),
          settingsRepository: settingsRepository,
          taskNotifierFactory: () => spyTaskNotifier,
        );

        final saveFinder = find.byKey(
          const ValueKey<String>('settings_dock_save_button'),
        );
        final testSyncFinder = find.byKey(
          const ValueKey<String>('settings_dock_test_sync_button'),
        );

        // Clean initial state: no dirty pill, Save is secondary, Test & Sync is primary and enabled.
        expect(
          find.text(localizations.settingsUnsavedChangesBadge),
          findsNothing,
        );
        expect(
          tester.widget<UiButton>(saveFinder).variant,
          equals(UiButtonVariant.secondary),
        );
        expect(
          tester.widget<UiButton>(testSyncFinder).variant,
          equals(UiButtonVariant.primary),
        );
        expect(tester.widget<UiButton>(testSyncFinder).onPressed, isNotNull);
        expect(
          find.text(
            'https://cloud.example.com/remote.php/dav/files/alice/notes/tasks.tdf',
          ),
          findsOneWidget,
        );

        // Password field is obscured initially and reveals when toggling visibility button.
        final passwordFieldFinder = find.byKey(
          const ValueKey<String>('settings_webdav_password_field'),
        );
        await tester.ensureVisible(passwordFieldFinder);
        await tester.pumpAndSettle();
        final passwordTextField = tester.widget<TextField>(
          find.descendant(
            of: passwordFieldFinder,
            matching: find.byType(TextField),
          ),
        );
        expect(passwordTextField.obscureText, isTrue);
        await tester.tap(find.byTooltip(localizations.tooltipShowPassword));
        await tester.pumpAndSettle();
        final revealedPasswordField = tester.widget<TextField>(
          find.descendant(
            of: passwordFieldFinder,
            matching: find.byType(TextField),
          ),
        );
        expect(revealedPasswordField.obscureText, isFalse);
        expect(
          find.byTooltip(localizations.tooltipHidePassword),
          findsOneWidget,
        );

        // Editing Server URL marks WebDAV dirty, shows pill in BOTH WebDAV card and dock, swaps emphasis, and updates live endpoint.
        final serverUrlFieldFinder = find.byKey(
          const ValueKey<String>('settings_webdav_server_url_field'),
        );
        await tester.ensureVisible(serverUrlFieldFinder);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: serverUrlFieldFinder,
            matching: find.byType(TextField),
          ),
          'https://next.example.com',
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('settings_webdav_unsaved_badge')),
          findsOneWidget,
          reason: 'WebDAV card header must display Unsaved changes pill',
        );
        expect(
          find.byKey(const ValueKey<String>('settings_dock_unsaved_badge')),
          findsOneWidget,
          reason: 'SettingsActionDock must display Unsaved changes pill',
        );
        expect(
          find.text(localizations.settingsUnsavedChangesBadge),
          findsNWidgets(2),
        );
        expect(
          tester.widget<UiButton>(saveFinder).variant,
          equals(UiButtonVariant.primary),
          reason: 'Save promotes to primary when WebDAV draft is dirty',
        );
        expect(
          tester.widget<UiButton>(testSyncFinder).variant,
          equals(UiButtonVariant.secondary),
          reason: 'Test & Sync demotes to secondary when WebDAV draft is dirty',
        );
        expect(
          find.text(
            'https://next.example.com/remote.php/dav/files/alice/notes/tasks.tdf',
          ),
          findsOneWidget,
        );

        // Mid-string caret preservation while typing in Server URL.
        final urlEditable = tester.widget<TextField>(
          find.descendant(
            of: serverUrlFieldFinder,
            matching: find.byType(TextField),
          ),
        );
        final urlController = urlEditable.controller;
        expect(urlController, isNotNull);
        urlController?.value = const TextEditingValue(
          text: 'https://eu-next.example.com',
          selection: TextSelection.collapsed(offset: 11),
        );
        urlEditable.onChanged?.call('https://eu-next.example.com');
        await tester.pump();
        expect(
          urlController?.selection,
          equals(const TextSelection.collapsed(offset: 11)),
          reason: 'External controller sync must preserve caret while typing',
        );

        // Switching Storage Mode to Local immediately clears dirty state, hides WebDAV card, and disables Test & Sync.
        await scrollToAndTap(
          tester,
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('settings_storage_mode_control'),
            ),
            matching: find.text(localizations.storageModeLocal),
          ),
        );
        expect(
          find.text(localizations.settingsUnsavedChangesBadge),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('settings_webdav_card')),
          findsNothing,
        );
        expect(
          tester.widget<UiButton>(saveFinder).variant,
          equals(UiButtonVariant.secondary),
        );
        expect(
          tester.widget<UiButton>(testSyncFinder).variant,
          equals(UiButtonVariant.primary),
        );
        expect(
          tester.widget<UiButton>(testSyncFinder).onPressed,
          isNull,
          reason: 'Test Connection / Sync Now must be disabled in local mode',
        );

        // Switching back to Both re-mounts WebDAV card synced cleanly to persisted URL.
        await scrollToAndTap(
          tester,
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('settings_storage_mode_control'),
            ),
            matching: find.text(localizations.storageModeBoth),
          ),
        );
        expect(
          find.byKey(const ValueKey<String>('settings_webdav_card')),
          findsOneWidget,
        );
        final resetUrlController = tester
            .widget<TextField>(
              find.descendant(
                of: serverUrlFieldFinder,
                matching: find.byType(TextField),
              ),
            )
            .controller;
        expect(resetUrlController?.text, equals('https://cloud.example.com'));

        // Explicit Save with mid-flight loading frame commits draft and displays dismissible success banner.
        await tester.ensureVisible(serverUrlFieldFinder);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: serverUrlFieldFinder,
            matching: find.byType(TextField),
          ),
          'https://saved.example.com',
        );
        await tester.pumpAndSettle();

        final saveGate = Completer<void>();
        settingsRepository.saveGate = saveGate;
        await tester.tap(saveFinder);
        await tester.pump();

        expect(
          tester.widget<UiButton>(saveFinder).isLoading,
          isTrue,
          reason: 'Save button shows loading spinner while dirty save runs',
        );
        expect(tester.widget<UiButton>(saveFinder).onPressed, isNull);
        expect(tester.widget<UiButton>(testSyncFinder).isLoading, isFalse);
        expect(tester.widget<UiButton>(testSyncFinder).onPressed, isNull);

        saveGate.complete();
        settingsRepository.saveGate = null;
        await tester.pumpAndSettle();

        expect(
          find.text(localizations.settingsUnsavedChangesBadge),
          findsNothing,
        );
        expect(find.text(localizations.credentialsSavedBanner), findsOneWidget);
        expect(
          tester.widget<UiButton>(saveFinder).variant,
          equals(UiButtonVariant.secondary),
        );
        expect(
          tester.widget<UiButton>(testSyncFinder).variant,
          equals(UiButtonVariant.primary),
        );

        // Dismiss top status banner.
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('settings_status_banner')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey<String>('settings_status_banner')),
            matching: find.byTooltip(localizations.actionDismiss),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('settings_status_banner')),
          findsNothing,
        );

        // Test Connection / Sync Now shows mid-flight loading state and success banner on completion.
        final syncGate = Completer<void>();
        spyTaskNotifier.testSyncGate = syncGate;
        await tester.tap(testSyncFinder);
        await tester.pump();

        expect(
          tester.widget<UiButton>(testSyncFinder).isLoading,
          isTrue,
          reason:
              'Test & Sync button shows loading spinner while clean sync runs',
        );
        expect(tester.widget<UiButton>(saveFinder).isLoading, isFalse);

        syncGate.complete();
        spyTaskNotifier.testSyncGate = null;
        await tester.pumpAndSettle();

        expect(spyTaskNotifier.testedConfigs.length, equals(1));
        expect(
          spyTaskNotifier.testedConfigs.single.serverUrl,
          equals('https://saved.example.com'),
        );
        expect(
          find.text(localizations.connectionSuccessBanner),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'displays inline field validation errors and top danger banner for invalid URL, userinfo, and remote path',
      (tester) async {
        await pumpV2Widget(
          tester,
          const _SettingsTestFrame(),
          config: const WebDavConfig(
            storageMode: StorageMode.webdav,
            language: AppLanguage.english,
          ),
        );

        // Local TDF File card is hidden in WebDAV-only storage mode.
        expect(
          find.byKey(const ValueKey<String>('settings_local_card')),
          findsNothing,
        );

        // Enter URL with embedded userinfo and traversal remote path while leaving credentials empty.
        final serverUrlField = find.byKey(
          const ValueKey<String>('settings_webdav_server_url_field'),
        );
        final filePathField = find.byKey(
          const ValueKey<String>('settings_webdav_file_path_field'),
        );
        await tester.ensureVisible(serverUrlField);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(of: serverUrlField, matching: find.byType(TextField)),
          'https://user:pass@cloud.example.com',
        );
        await tester.ensureVisible(filePathField);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(of: filePathField, matching: find.byType(TextField)),
          '../escape.tdf',
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('settings_dock_save_button')),
        );
        await tester.pumpAndSettle();

        expect(
          tester.widget<UiField>(serverUrlField).errorText,
          equals(localizations.webDavUrlUserinfoError),
        );
        expect(
          tester
              .widget<UiField>(
                find.byKey(
                  const ValueKey<String>('settings_webdav_username_field'),
                ),
              )
              .errorText,
          equals(localizations.usernameErrorEmpty),
        );
        expect(
          tester
              .widget<UiField>(
                find.byKey(
                  const ValueKey<String>('settings_webdav_password_field'),
                ),
              )
              .errorText,
          equals(localizations.passwordErrorEmpty),
        );
        expect(
          tester.widget<UiField>(filePathField).errorText,
          equals(localizations.webDavPathInvalidError),
        );

        final bannerFinder = find.byKey(
          const ValueKey<String>('settings_status_banner'),
        );
        expect(bannerFinder, findsOneWidget);
        final banner = tester.widget<UiBanner>(bannerFinder);
        expect(banner.tone, equals(UiBannerTone.danger));
        expect(banner.message, equals(localizations.webDavUrlUserinfoError));

        // Invalid non-HTTP(S) scheme shows errorInvalidServerUrl inline and in banner.
        await tester.ensureVisible(serverUrlField);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(of: serverUrlField, matching: find.byType(TextField)),
          'ftp://cloud.example.com',
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('settings_dock_save_button')),
        );
        await tester.pumpAndSettle();

        expect(
          tester.widget<UiField>(serverUrlField).errorText,
          equals(localizations.errorInvalidServerUrl),
        );
        expect(
          tester.widget<UiBanner>(bannerFinder).message,
          equals(localizations.errorInvalidServerUrl),
        );

        // Wipe Remote button stays disabled when WebDAV is not configured.
        final wipeRemoteButton = tester.widget<UiButton>(
          find.byKey(const ValueKey<String>('settings_wipe_remote_button')),
        );
        expect(wipeRemoteButton.onPressed, isNull);
      },
    );
  });

  group('Capability-gated Local actions, modals, and responsive viewports', () {
    for (final viewportCase in const <({String name, Size size})>[
      (name: 'compact 390x844', size: Size(390, 844)),
      (name: 'expanded 1280x860', size: Size(1280, 860)),
    ]) {
      testWidgets(
        'enables native Move and Select at ${viewportCase.name} when supportsNativeDirectoryPicker is true',
        (tester) async {
          final spyLocalRepo = _SpyLocalFileRepository(
            config: configuredBoth,
            pickedDirectoryPath: null,
            pickedFilePath: '/tmp/selected.tdf',
          );
          final spyTaskNotifier = _SpySettingsTaskNotifier();

          await pumpV2Widget(
            tester,
            const _SettingsTestFrame(),
            config: configuredBoth,
            localFileRepository: spyLocalRepo,
            taskNotifierFactory: () => spyTaskNotifier,
            supportsNativeDirectoryPicker: true,
            surfaceSize: viewportCase.size,
          );

          final moveFinder = find.byKey(
            const ValueKey<String>('settings_move_local_button'),
          );
          final selectFinder = find.byKey(
            const ValueKey<String>('settings_select_local_button'),
          );
          final moveButton = tester.widget<UiButton>(moveFinder);
          expect(
            moveButton.onPressed,
            isNotNull,
            reason:
                'Move must stay enabled on ${viewportCase.name} when native picker is supported',
          );
          expect(moveButton.tooltip, isNull);

          await scrollToAndTap(tester, moveFinder);
          expect(
            spyLocalRepo.pickDirectoryCalls,
            equals(1),
            reason: 'Move invokes native directory picker when supported',
          );

          await scrollToAndTap(tester, selectFinder);
          expect(
            spyLocalRepo.pickTdfFileCalls,
            equals(1),
            reason: 'Select invokes native file picker when supported',
          );
          expect(
            find.byKey(const ValueKey<String>('select_local_file_modal')),
            findsNothing,
          );
          expect(
            spyTaskNotifier.selectedLocalConfigs.single.localFilePath,
            equals('/tmp/selected.tdf'),
          );
        },
      );

      testWidgets(
        'disables Move with desktop tooltip and opens Select modal at ${viewportCase.name} when supportsNativeDirectoryPicker is false',
        (tester) async {
          final spyLocalRepo = _SpyLocalFileRepository(
            config: configuredBoth,
            existingFileNames: const <String>['tasks.tdf', 'work.tdf'],
          );

          await pumpV2Widget(
            tester,
            const _SettingsTestFrame(),
            config: configuredBoth,
            localFileRepository: spyLocalRepo,
            supportsNativeDirectoryPicker: false,
            surfaceSize: viewportCase.size,
          );

          final moveFinder = find.byKey(
            const ValueKey<String>('settings_move_local_button'),
          );
          final selectFinder = find.byKey(
            const ValueKey<String>('settings_select_local_button'),
          );
          final moveButton = tester.widget<UiButton>(moveFinder);
          expect(
            moveButton.onPressed,
            isNull,
            reason:
                'Move must be disabled on ${viewportCase.name} when native picker is unsupported',
          );
          expect(
            moveButton.tooltip,
            equals(localizations.settingsMoveDesktopOnlyTooltip),
          );

          await scrollToAndTap(tester, selectFinder);
          expect(
            spyLocalRepo.pickTdfFileCalls,
            equals(0),
            reason:
                'Select must open in-app modal instead of native file picker',
          );
          expect(
            find.byKey(const ValueKey<String>('select_local_file_modal')),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets(
      'opens Rename, Wipe Local, and Wipe Remote modals with active workspace filenames',
      (tester) async {
        await pumpV2Widget(
          tester,
          const _SettingsTestFrame(),
          config: configuredBoth,
        );

        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey<String>('settings_rename_local_button')),
        );
        expect(
          find.byKey(const ValueKey<String>('rename_local_file_modal')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('rename_local_file_cancel_button')),
        );
        await tester.pumpAndSettle();

        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey<String>('settings_wipe_local_button')),
        );
        expect(
          find.byKey(const ValueKey<String>('wipe_local_tdf_modal')),
          findsOneWidget,
        );
        expect(find.text(localizations.wipeLocalDialogTitle), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey<String>('wipe_tdf_cancel_button')),
        );
        await tester.pumpAndSettle();

        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey<String>('settings_wipe_remote_button')),
        );
        final wipeRemoteModal = find.byKey(
          const ValueKey<String>('wipe_remote_tdf_modal'),
        );
        expect(wipeRemoteModal, findsOneWidget);
        expect(
          find.descendant(
            of: wipeRemoteModal,
            matching: find.text(localizations.wipeRemoteDialogTitle),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'attaches caller ScrollController and collapses preference and local action grids cleanly across breakpoints',
      (tester) async {
        final scrollController = ScrollController();
        addTearDown(scrollController.dispose);

        // Expanded 1280x860: 2 columns for preferences, 4 columns for local actions, 2 columns for WebDAV fields.
        await pumpV2Widget(
          tester,
          _SettingsTestFrame(scrollController: scrollController),
          config: configuredBoth,
          surfaceSize: const Size(1280, 860),
          presetId: 'plum_umber',
          themeMode: ThemeMode.dark,
        );
        expect(scrollController.hasClients, isTrue);

        final langRectExpanded = tester.getRect(
          find.byKey(const ValueKey<String>('settings_language_card')),
        );
        final appearRectExpanded = tester.getRect(
          find.byKey(const ValueKey<String>('settings_appearance_card')),
        );
        expect(
          langRectExpanded.top,
          equals(appearRectExpanded.top),
          reason:
              'Expanded (>820px) preference grid places 2 cards side by side',
        );

        final selectRectExpanded = tester.getRect(
          find.byKey(const ValueKey<String>('settings_select_local_button')),
        );
        final wipeRectExpanded = tester.getRect(
          find.byKey(const ValueKey<String>('settings_wipe_local_button')),
        );
        expect(
          selectRectExpanded.top,
          equals(wipeRectExpanded.top),
          reason: 'Expanded (>720px) local actions grid places all 4 actions in one row',
        );

        // Compact 390x844: 1 column for preferences, 2x2 for local actions.
        await tester.binding.setSurfaceSize(const Size(390, 844));
        await tester.pumpAndSettle();

        final langRectCompact = tester.getRect(
          find.byKey(const ValueKey<String>('settings_language_card')),
        );
        final appearRectCompact = tester.getRect(
          find.byKey(const ValueKey<String>('settings_appearance_card')),
        );
        expect(
          appearRectCompact.top,
          greaterThan(langRectCompact.top),
          reason: 'Compact (<=820px) preference grid collapses to 1 column',
        );

        final selectRectCompact = tester.getRect(
          find.byKey(const ValueKey<String>('settings_select_local_button')),
        );
        final moveRectCompact = tester.getRect(
          find.byKey(const ValueKey<String>('settings_move_local_button')),
        );
        final renameRectCompact = tester.getRect(
          find.byKey(const ValueKey<String>('settings_rename_local_button')),
        );
        expect(
          selectRectCompact.top,
          equals(moveRectCompact.top),
          reason: 'Compact (<=720px) local actions grid places Select and Move on row 1',
        );
        expect(
          renameRectCompact.top,
          greaterThan(selectRectCompact.top),
          reason: 'Compact (<=720px) local actions grid wraps Rename onto row 2 (2x2)',
        );
      },
    );

    testWidgets(
      're-syncs WebDAV controllers and header subtitle cleanly on workspace switch',
      (tester) async {
        final settingsRepository = InMemorySettingsRepository(configuredBoth);
        final secondWorkspace = await settingsRepository.createWorkspace(
          'Client Board',
          config: const WebDavConfig(
            serverUrl: 'https://client.example.org',
            username: 'bob',
            password: 'client-password',
            filePath: 'client.tdf',
            localFilePath: 'client_board.tdf',
            storageMode: StorageMode.both,
            language: AppLanguage.english,
          ),
          activate: false,
        );

        final container = await pumpV2Widget(
          tester,
          const _SettingsTestFrame(),
          settingsRepository: settingsRepository,
        );

        // Dirty current workspace draft before switching workspaces.
        final serverUrlField = find.byKey(
          const ValueKey<String>('settings_webdav_server_url_field'),
        );
        await tester.ensureVisible(serverUrlField);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(of: serverUrlField, matching: find.byType(TextField)),
          'https://unsaved-dirty.example.com',
        );
        await tester.pumpAndSettle();
        expect(
          find.text(localizations.settingsUnsavedChangesBadge),
          findsNWidgets(2),
        );

        await container
            .read(workspaceV2ControllerProvider.notifier)
            .switchWorkspace(secondWorkspace.id);
        await tester.pumpAndSettle();

        expect(
          find.text(localizations.settingsWorkspaceSubtitle('Client Board')),
          findsOneWidget,
        );
        expect(
          find.text(localizations.settingsUnsavedChangesBadge),
          findsNothing,
        );
        final syncedUrl = tester
            .widget<TextField>(
              find.descendant(
                of: serverUrlField,
                matching: find.byType(TextField),
              ),
            )
            .controller
            ?.text;
        expect(syncedUrl, equals('https://client.example.org'));
      },
    );
  });
}
