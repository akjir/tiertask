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

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';
import 'package:tiertask/services/app_logger.dart';

import 'test_helpers.dart';

class _DelayedWebDavRepository extends WebDavRepository {
  _DelayedWebDavRepository({required super.config, required this.fetchGate});

  final Future<void> Function() fetchGate;

  @override
  Future<String> fetchTdf() async {
    await fetchGate();
    return 'tdf 0.6.0\n';
  }

  @override
  Future<void> saveTdf(String tdfContent) async {}
}

void main() {
  testWidgets('SettingsScreen does not display Open Task Count section', (
    WidgetTester tester,
  ) async {
    const seededTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 10:00:00
  task 000001OkD2
  task 000002OkD2
  task 000003OkD2
}

label home00OkD2 {
  name "Home"
}
label officeOkD2 {
  name "Office"
}
label busin0OkD2 {
  name "Business"
  color "#EB06FF"
}
label persn0OkD2 {
  name "Personal"
}
task 000001OkD2 {
  name "Prepare quarterly report"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
  labels busin0OkD2 officeOkD2
}
task 000002OkD2 {
  name "Review client contract"
  created 2026-11-01 09:00
  queued 2026-11-01 09:00
  labels busin0OkD2 officeOkD2
}
task 000003OkD2 {
  name "Water plants"
  created 2026-11-01 10:00
  queued 2026-11-01 10:00
  labels persn0OkD2 home00OkD2
}
task 000004OkD2 {
  name "Archived invoice"
  created 2026-10-28 10:00
  queued 2026-10-28 10:00
  finished 2026-10-29 12:00
  completions 1
  labels busin0OkD2 officeOkD2
}
''';
    await _pumpSettingsApp(tester, initialTdf: seededTdf, openSettings: false);

    expect(find.text('FOCUS TASKS'), findsOneWidget);
    expect(
      find.text('CATEGORIES'),
      findsNothing,
      reason: 'Categories section must not appear on the landing page',
    );
    expect(
      find.text('LOCATIONS'),
      findsNothing,
      reason: 'Locations section must not appear on the landing page',
    );

    await openSettingsFromMenu(tester);

    expect(
      find.text('Open Task Count'),
      findsNothing,
      reason: 'Settings must not display the removed Open Task Count section',
    );
    expect(
      find.text('Gesamtzahl offener Aufgaben'),
      findsNothing,
      reason: 'Settings must not display the German Open Task Count section',
    );
  });

  testWidgets(
    'SettingsScreen switches display language between English and German via top-left menu',
    (WidgetTester tester) async {
      await _pumpSettingsApp(
        tester,
        config: const WebDavConfig(
          language: AppLanguage.english,
          storageMode: StorageMode.both,
        ),
      );

      expect(find.text('Language'), findsOneWidget);
      expect(find.text('WebDAV Synchronization'), findsOneWidget);
      expect(find.textContaining('Single Source of Truth'), findsNothing);

      await tester.tap(find.text('Deutsch'));
      await tester.pumpAndSettle();

      expect(find.text('Sprache'), findsOneWidget);
      expect(find.text('WebDAV-Synchronisation'), findsOneWidget);
      expect(find.textContaining('Single Source of Truth'), findsNothing);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Was steht an!'), findsNothing);
      expect(find.byKey(const ValueKey('top_bar_title')), findsNothing);
      expect(find.text('FOKUSAUFGABEN'), findsOneWidget);
      expect(find.textContaining('# ['), findsNothing);
    },
  );

  testWidgets(
    'SettingsScreen defaults to System theme and switches between System, Light, and Dark themes and storage modes',
    (WidgetTester tester) async {
      final settingsRepository = await _pumpSettingsApp(
        tester,
        openSettings: false,
      );

      MaterialApp appWidget = tester.widget<MaterialApp>(
        find.byType(MaterialApp),
      );
      expect(appWidget.title, equals('TierTask'));
      expect(appWidget.themeMode, equals(ThemeMode.system));

      await openSettingsFromMenu(tester);

      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      appWidget = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(appWidget.themeMode, equals(ThemeMode.dark));

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      appWidget = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(appWidget.themeMode, equals(ThemeMode.light));

      expect(find.text('Storage Mode'), findsOneWidget);
      expect(find.text('Local'), findsOneWidget);
      expect(find.text('WebDAV'), findsOneWidget);
      expect(find.text('Both'), findsOneWidget);
      expect(find.text('Local TDF File Name'), findsNothing);
      expect(find.text('Resolved Local File Path:'), findsOneWidget);

      await _tapVisible(tester, find.text('Both'));

      expect(find.text('Resolved Local File Path:'), findsOneWidget);
      expect(find.text('WebDAV Server URL'), findsOneWidget);
      expect(find.byType(ActionChip), findsNothing);
      expect(find.text('t2.tdf'), findsNothing);

      final localSectionCard = find.ancestor(
        of: find.text('Local TDF File'),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(
          of: localSectionCard,
          matching: find.text('Resolved Local File Path:'),
        ),
        findsOneWidget,
      );
      for (final buttonKey in [
        'settings_select_local_button',
        'settings_move_local_button',
        'settings_rename_local_button',
        'settings_wipe_local_button',
      ]) {
        expect(
          find.descendant(
            of: localSectionCard,
            matching: find.byKey(ValueKey(buttonKey)),
          ),
          findsOneWidget,
        );
      }

      final webdavSectionCard = find.ancestor(
        of: find.text('WebDAV Synchronization'),
        matching: find.byType(Card),
      );
      for (final label in [
        'WebDAV Server URL',
        'Username',
        'App Password / Password',
        'TDF File Name / Path',
      ]) {
        expect(
          find.descendant(
            of: webdavSectionCard,
            matching: find.widgetWithText(TextFormField, label),
          ),
          findsOneWidget,
        );
      }

      await _tapVisible(tester, find.text('Local'));
      expect(find.text('WebDAV Server URL'), findsNothing);

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('settings_rename_local_button')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('rename_local_tdf_input')),
        'custom_local_tasks.tdf',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('rename_local_tdf_confirm_button')),
      );
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('Save'));

      expect(find.text('Settings saved locally.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Settings saved locally.'), findsNothing);

      final savedConfig = await settingsRepository.loadConfig();
      expect(savedConfig.localFilePath, endsWith('custom_local_tasks.tdf'));
      expect(savedConfig.storageMode, equals(StorageMode.local));
      expect(savedConfig.themeMode, equals(AppThemeMode.light));
    },
  );

  testWidgets(
    'SettingsScreen disables Test Connection button in Local mode and never displays connection success when WebDAV is unconfigured',
    (WidgetTester tester) async {
      await _pumpSettingsApp(
        tester,
        config: const WebDavConfig(
          language: AppLanguage.english,
          storageMode: StorageMode.local,
        ),
      );

      final testConnectionButtonFinder = find.widgetWithText(
        FilledButton,
        'Test Connection / Sync Now',
      );
      await tester.ensureVisible(testConnectionButtonFinder);
      FilledButton testConnectionButton = tester.widget<FilledButton>(
        testConnectionButtonFinder,
      );
      expect(testConnectionButton.onPressed, isNull);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Settings saved locally.'), findsOneWidget);
      expect(
        find.text('Connection succeeded. TDF file synchronized with WebDAV.'),
        findsNothing,
      );

      await _tapVisible(tester, find.text('WebDAV'));
      expect(find.text('Settings saved locally.'), findsNothing);

      await tester.ensureVisible(testConnectionButtonFinder);
      testConnectionButton = tester.widget<FilledButton>(
        testConnectionButtonFinder,
      );
      expect(testConnectionButton.onPressed, isNotNull);

      await tester.tap(testConnectionButtonFinder);
      await tester.pumpAndSettle();

      expect(find.text('Please enter a server URL.'), findsOneWidget);
      expect(find.text('Please enter a username.'), findsOneWidget);
      expect(
        find.text('Please enter a password or app password.'),
        findsOneWidget,
      );
      expect(
        find.text('Connection succeeded. TDF file synchronized with WebDAV.'),
        findsNothing,
      );

      await _tapVisible(tester, find.text('Local'));

      await tester.ensureVisible(testConnectionButtonFinder);
      testConnectionButton = tester.widget<FilledButton>(
        testConnectionButtonFinder,
      );
      expect(testConnectionButton.onPressed, isNull);
    },
  );

  testWidgets(
    'SettingsScreen fades out save confirmation, connection success, and connection error banners after a few seconds',
    (WidgetTester tester) async {
      var shouldFailWebDav = false;
      await _pumpSettingsApp(
        tester,
        config: const WebDavConfig(
          language: AppLanguage.english,
          storageMode: StorageMode.webdav,
          serverUrl: 'https://cloud.example.com/remote.php/dav/files/alice/',
          username: 'alice',
          password: 'secret-app-password',
          filePath: 'tiertask.tdf',
        ),
        shouldFailWebDav: () => shouldFailWebDav,
      );

      final webdavSectionCard = find.ancestor(
        of: find.text('WebDAV Synchronization'),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(
          of: webdavSectionCard,
          matching: find.text('Resolved WebDAV Endpoint (GET / PUT):'),
        ),
        findsOneWidget,
      );

      await _tapVisible(tester, find.text('Save'));

      expect(find.text('Settings saved locally.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Settings saved locally.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Settings saved locally.'), findsNothing);

      final testConnectionButtonFinder = find.widgetWithText(
        FilledButton,
        'Test Connection / Sync Now',
      );
      await _tapVisible(tester, testConnectionButtonFinder);

      const successText =
          'Connection succeeded. TDF file synchronized with WebDAV.';
      expect(find.text(successText), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text(successText), findsNothing);

      shouldFailWebDav = true;
      await tester.tap(testConnectionButtonFinder);
      await tester.pumpAndSettle();

      const errorText =
          'Authentication failed. Please check username and app password. (HTTP 401)';
      expect(find.text(errorText), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text(errorText), findsNothing);
    },
  );

  testWidgets(
    'SettingsScreen switches Time Zone mode between Automatic and Manual and persists manual UTC offset',
    (WidgetTester tester) async {
      final settingsRepository = await _pumpSettingsApp(tester);

      expect(find.text('Time Zone'), findsOneWidget);
      expect(find.text('Automatic'), findsOneWidget);
      expect(find.text('Manual'), findsOneWidget);

      await _tapVisible(tester, find.text('Manual'));

      final savedConfig = await settingsRepository.loadConfig();
      expect(savedConfig.timeZoneMode, equals(AppTimeZoneMode.manual));
      expect(find.text('UTC Offset'), findsOneWidget);
    },
  );

  testWidgets(
    'SettingsScreen toggle enables and disables Diagnostic Log, reveals and hides the sidepanel Log button, and LogViewerDialog supports Copy, Scroll to Bottom, and Clear',
    (WidgetTester tester) async {
      final tempDir = Directory.systemTemp.createTempSync(
        'tiertask_ui_logger_',
      );
      addTearDown(() {
        AppLogger.resetForTesting();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      String? copiedClipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            final arguments = methodCall.arguments;
            if (arguments is Map<Object?, Object?>) {
              final text = arguments['text'];
              if (text is String) {
                copiedClipboardText = text;
              }
            }
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await _pumpSettingsApp(
        tester,
        openSettings: false,
        storageDirPath: tempDir.path,
        clock: DateTime.utc(2026, 11, 3, 22, 5, 14, 128),
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('drawer_diagnostic_log_tile')),
        findsNothing,
      );
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(
        const ValueKey('settings_diagnostics_switch'),
      );
      await _tapVisible(tester, switchFinder);

      final expectedFileName = AppLogger.formatLogFileName(
        utcNow: DateTime.utc(2026, 11, 3, 22, 5, 14, 128),
        platform: Platform.operatingSystem,
        workspaceId: 'tasks',
      );
      final logFile = File(
        '${tempDir.path}${Platform.pathSeparator}$expectedFileName',
      );
      expect(logFile.existsSync(), isTrue);
      expect(
        find.byKey(const ValueKey('settings_log_level_segmented')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings_log_storage_segmented')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings_open_log_viewer_button')),
        findsOneWidget,
      );

      AppLogger.warn(LogTag.sync, 'Simulated warning entry');
      AppLogger.error(LogTag.storage, 'Simulated error entry');
      AppLogger.crash(
        StateError('Simulated crash entry'),
        StackTrace.fromString('#0 crashFrame (main.dart:1)'),
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      final drawerLogTile = find.byKey(
        const ValueKey('drawer_diagnostic_log_tile'),
      );
      expect(drawerLogTile, findsOneWidget);

      await tester.tap(drawerLogTile);
      await tester.pumpAndSettle();

      expect(find.text('Diagnostic Log'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('log_viewer_metadata_card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('log_viewer_level_dropdown')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('log_viewer_tag_dropdown')),
        findsOneWidget,
      );
      expect(find.textContaining('Simulated warning entry'), findsOneWidget);
      expect(find.textContaining('Simulated error entry'), findsOneWidget);
      expect(find.textContaining('Simulated crash entry'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('log_viewer_scroll_bottom_button')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('log_viewer_copy_button')));
      await tester.pumpAndSettle();
      expect(copiedClipboardText, contains('Simulated warning entry'));

      await tester.tap(find.byKey(const ValueKey('log_viewer_clear_button')));
      await tester.pumpAndSettle();
      expect(
        find.text('No diagnostic log entries recorded yet.'),
        findsOneWidget,
      );
      expect(logFile.readAsStringSync(), isEmpty);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await openSettingsFromMenu(tester);
      await _tapVisible(tester, switchFinder);
      expect(logFile.existsSync(), isFalse);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('drawer_diagnostic_log_tile')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'SettingsScreen shows local watch switch in Local and Both modes, hides in WebDAV mode, renders EN/DE labels, disables while testing, and persists without reloading TaskBoard',
    (WidgetTester tester) async {
      const seededTdf =
          'tdf 0.6.0\n\n'
          'queue {\n'
          '  modified 2026-11-01 08:00:00\n'
          '  task 000001OkD2\n'
          '}\n\n'
          'task 000001OkD2 {\n'
          '  name "Keep Board Loaded"\n'
          '  created 2026-11-01 08:00:00\n'
          '  modified 2026-11-01 08:00:00\n'
          '}\n';
      const initialConfig = WebDavConfig(
        language: AppLanguage.english,
        storageMode: StorageMode.both,
        serverUrl: 'https://dav.example.com/remote.php/dav/files/alice',
        username: 'alice',
        password: 'secret-app-password',
      );
      final settingsRepository = InMemorySettingsRepository(initialConfig);
      Future<void> Function() currentFetchGate = () async {};
      var sawLoadingAfterReady = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepository),
            localFileRepositoryProvider.overrideWithValue(
              FakeLocalFileRepository(
                config: initialConfig,
                initialTdf: seededTdf,
              ),
            ),
            webDavRepositoryProvider.overrideWith((ref) {
              final currentConfig =
                  ref.watch(webDavConfigProvider).asData?.value ??
                  initialConfig;
              return _DelayedWebDavRepository(
                config: currentConfig,
                fetchGate: () => currentFetchGate(),
              );
            }),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: Consumer(
            builder: (context, ref, child) {
              ref.listen(taskNotifierProvider, (previous, next) {
                if ((previous?.hasValue ?? false) && next.isLoading) {
                  sawLoadingAfterReady = true;
                }
              });
              return child!;
            },
            child: const TierTaskApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await openSettingsFromMenu(tester);

      final switchFinder = find.byKey(
        const ValueKey('settings_local_watch_switch'),
      );
      await tester.ensureVisible(switchFinder);
      expect(
        switchFinder,
        findsOneWidget,
        reason: 'Switch must appear in StorageMode.both',
      );
      expect(
        tester.widget<Switch>(switchFinder).value,
        isTrue,
        reason: 'Switch must default to true',
      );
      expect(find.text('Watch for external file changes'), findsOneWidget);
      expect(
        find.text(
          'Automatically merge edits saved by external editors, scripts, or file-sync tools.',
        ),
        findsOneWidget,
      );

      sawLoadingAfterReady = false;
      await _tapVisible(tester, switchFinder);
      expect(
        tester.widget<Switch>(switchFinder).value,
        isFalse,
        reason: 'Tapping switch must flip value to false',
      );
      expect(
        (await settingsRepository.loadConfig()).localWatchEnabled,
        isFalse,
        reason: 'Tapping switch must persist localWatchEnabled: false',
      );
      expect(
        sawLoadingAfterReady,
        isFalse,
        reason: 'Toggling localWatchEnabled must not reload TaskNotifier',
      );

      await _tapVisible(tester, switchFinder);
      expect(tester.widget<Switch>(switchFinder).value, isTrue);
      expect((await settingsRepository.loadConfig()).localWatchEnabled, isTrue);
      expect(sawLoadingAfterReady, isFalse);

      await _tapVisible(tester, find.text('Deutsch'));
      await tester.ensureVisible(switchFinder);
      expect(find.text('Externe Dateiänderungen überwachen'), findsOneWidget);
      expect(
        find.text(
          'Änderungen durch externe Editoren, Skripte oder Datei-Synchronisation automatisch zusammenführen.',
        ),
        findsOneWidget,
      );
      await _tapVisible(tester, find.text('English'));

      await _tapVisible(tester, find.text('WebDAV'));
      expect(
        switchFinder,
        findsNothing,
        reason: 'Switch must hide in StorageMode.webdav',
      );

      await _tapVisible(tester, find.text('Local'));
      await tester.ensureVisible(switchFinder);
      expect(
        switchFinder,
        findsOneWidget,
        reason: 'Switch must appear in StorageMode.local',
      );

      await _tapVisible(tester, find.text('Both'));
      final syncGate = Completer<void>();
      currentFetchGate = () => syncGate.future;

      final syncButton = find.widgetWithText(
        FilledButton,
        'Test Connection / Sync Now',
      );
      await tester.tap(syncButton);
      await tester.pump();

      await tester.ensureVisible(switchFinder);
      expect(
        tester.widget<Switch>(switchFinder).onChanged,
        isNull,
        reason: 'Switch must be disabled while _isTesting is true',
      );

      syncGate.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<Switch>(switchFinder).onChanged,
        isNotNull,
        reason: 'Switch must re-enable after _isTesting finishes',
      );

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
  );
}

/// Pumps [TierTaskApp] with shared settings overrides and optionally opens Settings.
Future<InMemorySettingsRepository> _pumpSettingsApp(
  WidgetTester tester, {
  WebDavConfig config = const WebDavConfig(language: AppLanguage.english),
  String? initialTdf,
  bool Function()? shouldFailWebDav,
  String? storageDirPath,
  DateTime? clock,
  bool openSettings = true,
}) async {
  final settingsRepository = InMemorySettingsRepository(config);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settingsRepository),
        if (initialTdf != null)
          localFileRepositoryProvider.overrideWithValue(
            FakeLocalFileRepository(config: config, initialTdf: initialTdf),
          ),
        if (shouldFailWebDav != null)
          webDavRepositoryProvider.overrideWith((ref) {
            final currentConfig =
                ref.watch(webDavConfigProvider).asData?.value ??
                const WebDavConfig();
            return FakeWebDavRepository(
              config: currentConfig,
              shouldFail: shouldFailWebDav,
            );
          }),
        if (storageDirPath != null)
          localStorageDirectoryPathProvider.overrideWithValue(storageDirPath),
        clockProvider.overrideWithValue(
          () => clock ?? DateTime.utc(2026, 11, 1),
        ),
      ],
      child: const TierTaskApp(),
    ),
  );
  await tester.pumpAndSettle();
  if (openSettings) {
    await openSettingsFromMenu(tester);
  }
  return settingsRepository;
}

/// Scrolls [finder] into view, taps it, and settles animations.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
