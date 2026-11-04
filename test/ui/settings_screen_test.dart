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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/app_logger.dart';

import 'test_helpers.dart';

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
    final settingsRepository = InMemorySettingsRepository(
      const WebDavConfig(language: AppLanguage.english),
    );
    final fakeLocalRepo = FakeLocalFileRepository(
      config: const WebDavConfig(language: AppLanguage.english),
      initialTdf: seededTdf,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          localFileRepositoryProvider.overrideWithValue(fakeLocalRepo),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
        ],
        child: const TierTaskApp(),
      ),
    );

    await tester.pumpAndSettle();

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
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(
                const WebDavConfig(
                  language: AppLanguage.english,
                  storageMode: StorageMode.both,
                ),
              ),
            ),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );

      await tester.pumpAndSettle();

      await openSettingsFromMenu(tester);

      expect(find.text('Language'), findsOneWidget);
      expect(
        find.text('WebDAV Synchronization'),
        findsOneWidget,
        reason: 'English WebDAV section title must display WebDAV Synchronization without Single Source of Truth',
      );
      expect(
        find.textContaining('Single Source of Truth'),
        findsNothing,
        reason:
            'English settings screen must not mention Single Source of Truth',
      );
      await tester.tap(find.text('Deutsch'));
      await tester.pumpAndSettle();

      expect(find.text('Sprache'), findsOneWidget);
      expect(
        find.text('WebDAV-Synchronisation'),
        findsOneWidget,
        reason: 'German WebDAV section title must display WebDAV-Synchronisation without Single Source of Truth',
      );
      expect(
        find.textContaining('Single Source of Truth'),
        findsNothing,
        reason:
            'German settings screen must not mention Single Source of Truth',
      );

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
      final settingsRepository = InMemorySettingsRepository(
        const WebDavConfig(language: AppLanguage.english),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepository),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );

      await tester.pumpAndSettle();

      MaterialApp appWidget = tester.widget<MaterialApp>(
        find.byType(MaterialApp),
      );
      expect(
        appWidget.title,
        equals('TierTask'),
        reason: 'MaterialApp title must be TierTask',
      );
      expect(
        appWidget.themeMode,
        equals(ThemeMode.system),
        reason: 'Default themeMode must be ThemeMode.system',
      );

      await openSettingsFromMenu(tester);

      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      appWidget = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        appWidget.themeMode,
        equals(ThemeMode.dark),
        reason: 'Selecting Dark must update MaterialApp themeMode to dark',
      );

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      appWidget = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        appWidget.themeMode,
        equals(ThemeMode.light),
        reason: 'Selecting Light must update MaterialApp themeMode to light',
      );

      expect(find.text('Storage Mode'), findsOneWidget);
      expect(find.text('Local'), findsOneWidget);
      expect(find.text('WebDAV'), findsOneWidget);
      expect(find.text('Both'), findsOneWidget);
      expect(find.text('Local TDF File Name'), findsOneWidget);

      await tester.ensureVisible(find.text('Both'));
      await tester.tap(find.text('Both'));
      await tester.pumpAndSettle();

      expect(
        find.text('Local TDF File Name'),
        findsOneWidget,
        reason: 'Both mode must show local file name field',
      );
      expect(
        find.text('WebDAV Server URL'),
        findsOneWidget,
        reason: 'Both mode must also show WebDAV server URL field',
      );
      expect(
        find.byType(ActionChip),
        findsNothing,
        reason: 'Preset file name recommendation buttons (tasks.tdf, t2.tdf) must not be rendered in either storage section',
      );
      expect(
        find.text('t2.tdf'),
        findsNothing,
        reason: 't2.tdf recommendation button must not be rendered',
      );

      final localSectionCard = find.ancestor(
        of: find.text('Local TDF File'),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(
          of: localSectionCard,
          matching: find.widgetWithText(TextFormField, 'Local TDF File Name'),
        ),
        findsOneWidget,
        reason: 'Local TDF File Name field must be grouped inside the Local TDF File card',
      );

      final webdavSectionCard = find.ancestor(
        of: find.text('WebDAV Synchronization'),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(
          of: webdavSectionCard,
          matching: find.widgetWithText(TextFormField, 'WebDAV Server URL'),
        ),
        findsOneWidget,
        reason: 'WebDAV Server URL field must be grouped inside the WebDAV Synchronization card',
      );
      expect(
        find.descendant(
          of: webdavSectionCard,
          matching: find.widgetWithText(TextFormField, 'Username'),
        ),
        findsOneWidget,
        reason: 'Username field must be grouped inside the WebDAV Synchronization card',
      );
      expect(
        find.descendant(
          of: webdavSectionCard,
          matching: find.widgetWithText(
            TextFormField,
            'App Password / Password',
          ),
        ),
        findsOneWidget,
        reason: 'Password field must be grouped inside the WebDAV Synchronization card',
      );
      expect(
        find.descendant(
          of: webdavSectionCard,
          matching: find.widgetWithText(TextFormField, 'TDF File Name / Path'),
        ),
        findsOneWidget,
        reason: 'TDF File Name / Path field must be grouped inside the WebDAV Synchronization card',
      );

      await tester.ensureVisible(find.text('Local'));
      await tester.tap(find.text('Local'));
      await tester.pumpAndSettle();

      expect(
        find.text('WebDAV Server URL'),
        findsNothing,
        reason: 'Local-only mode must hide WebDAV server URL field',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Local TDF File Name'),
        'custom_local_tasks.tdf',
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        find.text('Settings saved locally.'),
        findsOneWidget,
        reason: 'Save confirmation banner must appear immediately after saving',
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(
        find.text('Settings saved locally.'),
        findsNothing,
        reason: 'Save confirmation banner must fade out and disappear after a few seconds',
      );

      final savedConfig = await settingsRepository.loadConfig();
      expect(
        savedConfig.localFilePath,
        equals('custom_local_tasks.tdf'),
        reason:
            'Saving settings in Local mode must persist custom localFilePath',
      );
      expect(
        savedConfig.storageMode,
        equals(StorageMode.local),
        reason: 'Saving settings in Local mode must persist StorageMode.local',
      );
      expect(
        savedConfig.themeMode,
        equals(AppThemeMode.light),
        reason: 'Saving settings must preserve selected AppThemeMode.light',
      );
    },
  );

  testWidgets(
    'SettingsScreen disables Test Connection button in Local mode and never displays connection success when WebDAV is unconfigured',
    (WidgetTester tester) async {
      final settingsRepository = InMemorySettingsRepository(
        const WebDavConfig(
          language: AppLanguage.english,
          storageMode: StorageMode.local,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepository),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );

      await tester.pumpAndSettle();

      await openSettingsFromMenu(tester);

      final testConnectionButtonFinder = find.widgetWithText(
        FilledButton,
        'Test Connection / Sync Now',
      );
      await tester.ensureVisible(testConnectionButtonFinder);
      FilledButton testConnectionButton = tester.widget<FilledButton>(
        testConnectionButtonFinder,
      );
      expect(
        testConnectionButton.onPressed,
        isNull,
        reason: 'Test Connection / Sync Now button must be disabled when StorageMode.local is selected',
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        find.text('Settings saved locally.'),
        findsOneWidget,
        reason: 'Saving in Local mode must display credentialsSavedBanner',
      );
      expect(
        find.text('Connection succeeded. TDF file synchronized with WebDAV.'),
        findsNothing,
        reason: 'Local mode must never display WebDAV connectionSuccessBanner',
      );

      await tester.ensureVisible(find.text('WebDAV'));
      await tester.tap(find.text('WebDAV'));
      await tester.pumpAndSettle();

      expect(
        find.text('Settings saved locally.'),
        findsNothing,
        reason: 'Switching storage mode must clear any previous status banner',
      );

      await tester.ensureVisible(testConnectionButtonFinder);
      testConnectionButton = tester.widget<FilledButton>(
        testConnectionButtonFinder,
      );
      expect(
        testConnectionButton.onPressed,
        isNotNull,
        reason: 'Test Connection / Sync Now button must be enabled when StorageMode.webdav is selected',
      );

      await tester.tap(testConnectionButtonFinder);
      await tester.pumpAndSettle();

      expect(
        find.text('Please enter a server URL.'),
        findsOneWidget,
        reason: 'Empty server URL must trigger validation error',
      );
      expect(
        find.text('Please enter a username.'),
        findsOneWidget,
        reason: 'Empty username must trigger validation error',
      );
      expect(
        find.text('Please enter a password or app password.'),
        findsOneWidget,
        reason: 'Empty password must trigger validation error',
      );
      expect(
        find.text('Connection succeeded. TDF file synchronized with WebDAV.'),
        findsNothing,
        reason: 'Connection success banner must never appear when WebDAV fields are empty or invalid',
      );

      await tester.ensureVisible(find.text('Local'));
      await tester.tap(find.text('Local'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(testConnectionButtonFinder);
      testConnectionButton = tester.widget<FilledButton>(
        testConnectionButtonFinder,
      );
      expect(
        testConnectionButton.onPressed,
        isNull,
        reason: 'Switching back to Local mode must disable Test Connection / Sync Now button again',
      );
    },
  );

  testWidgets(
    'SettingsScreen fades out save confirmation, connection success, and connection error banners after a few seconds',
    (WidgetTester tester) async {
      var shouldFailWebDav = false;
      final settingsRepository = InMemorySettingsRepository(
        const WebDavConfig(
          language: AppLanguage.english,
          storageMode: StorageMode.webdav,
          serverUrl: 'https://cloud.example.com/remote.php/dav/files/alice/',
          username: 'alice',
          password: 'secret-app-password',
          filePath: 'tiertask.tdf',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepository),
            webDavRepositoryProvider.overrideWith((ref) {
              final config =
                  ref.watch(webDavConfigProvider).asData?.value ??
                  const WebDavConfig();
              return FakeWebDavRepository(
                config: config,
                shouldFail: () => shouldFailWebDav,
              );
            }),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );

      await tester.pumpAndSettle();

      await openSettingsFromMenu(tester);

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
        reason: 'Resolved WebDAV endpoint preview must be grouped inside the WebDAV Synchronization card',
      );

      final saveButtonFinder = find.text('Save');
      await tester.ensureVisible(saveButtonFinder);
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      expect(
        find.text('Settings saved locally.'),
        findsOneWidget,
        reason: 'Save banner must appear immediately after tapping Save',
      );
      await tester.pump(const Duration(seconds: 2));
      expect(
        find.text('Settings saved locally.'),
        findsOneWidget,
        reason: 'Save banner must remain visible before timeout elapses',
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
        find.text('Settings saved locally.'),
        findsNothing,
        reason: 'Save banner must fade out after timeout elapses',
      );

      final testConnectionButtonFinder = find.widgetWithText(
        FilledButton,
        'Test Connection / Sync Now',
      );
      await tester.ensureVisible(testConnectionButtonFinder);
      await tester.tap(testConnectionButtonFinder);
      await tester.pumpAndSettle();

      const successText =
          'Connection succeeded. TDF file synchronized with WebDAV.';
      expect(
        find.text(successText),
        findsOneWidget,
        reason: 'Connection success banner must appear after successful Test Connection',
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(
        find.text(successText),
        findsNothing,
        reason: 'Connection success banner must fade out after a few seconds',
      );

      shouldFailWebDav = true;
      await tester.tap(testConnectionButtonFinder);
      await tester.pumpAndSettle();

      const errorText =
          'Authentication failed. Please check username and app password. (HTTP 401)';
      expect(
        find.text(errorText),
        findsOneWidget,
        reason:
            'Connection error banner must appear when Test Connection fails',
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(
        find.text(errorText),
        findsNothing,
        reason: 'Connection error banner must fade out after a few seconds',
      );
    },
  );

  testWidgets(
    'SettingsScreen switches Time Zone mode between Automatic and Manual and persists manual UTC offset',
    (WidgetTester tester) async {
      final settingsRepository = InMemorySettingsRepository(
        const WebDavConfig(language: AppLanguage.english),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepository),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );

      await tester.pumpAndSettle();
      await openSettingsFromMenu(tester);

      expect(
        find.text('Time Zone'),
        findsOneWidget,
        reason: 'SettingsScreen must display the Time Zone section card',
      );
      expect(find.text('Automatic'), findsOneWidget);
      expect(find.text('Manual'), findsOneWidget);

      await tester.ensureVisible(find.text('Manual'));
      await tester.tap(find.text('Manual'));
      await tester.pumpAndSettle();

      var savedConfig = await settingsRepository.loadConfig();
      expect(
        savedConfig.timeZoneMode,
        equals(AppTimeZoneMode.manual),
        reason: 'Selecting Manual must persist AppTimeZoneMode.manual',
      );
      expect(
        find.text('UTC Offset'),
        findsOneWidget,
        reason: 'Manual time zone mode must reveal the UTC Offset selector',
      );
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
            final args = methodCall.arguments;
            if (args is Map<Object?, Object?>) {
              final text = args['text'];
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

      final settingsRepository = InMemorySettingsRepository(
        const WebDavConfig(language: AppLanguage.english),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepository),
            localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
            clockProvider.overrideWithValue(
              () => DateTime.utc(2026, 11, 3, 22, 5, 14, 128),
            ),
          ],
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('drawer_diagnostic_log_tile')),
        findsNothing,
        reason: 'Diagnostic Log drawer button must be hidden when disabled',
      );
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(
        const ValueKey('settings_diagnostics_switch'),
      );
      await tester.ensureVisible(switchFinder);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      final logFile = File(
        '${tempDir.path}${Platform.pathSeparator}tiertask.log',
      );
      expect(
        logFile.existsSync(),
        isTrue,
        reason: 'Enabling Diagnostic Log in Settings must create tiertask.log',
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
      expect(
        drawerLogTile,
        findsOneWidget,
        reason:
            'Diagnostic Log drawer button must appear when logging is enabled',
      );

      await tester.tap(drawerLogTile);
      await tester.pumpAndSettle();

      expect(
        find.text('Diagnostic Log'),
        findsOneWidget,
        reason: 'LogViewerDialog must display the Diagnostic Log title',
      );
      expect(
        find.textContaining('Simulated warning entry'),
        findsOneWidget,
        reason: 'LogViewerDialog must display WARN entries',
      );
      expect(
        find.textContaining('Simulated error entry'),
        findsOneWidget,
        reason: 'LogViewerDialog must display ERROR entries',
      );
      expect(
        find.textContaining('Simulated crash entry'),
        findsOneWidget,
        reason: 'LogViewerDialog must display CRASH entries',
      );

      await tester.tap(
        find.byKey(const ValueKey('log_viewer_scroll_bottom_button')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('log_viewer_copy_button')));
      await tester.pumpAndSettle();
      expect(
        copiedClipboardText,
        contains('Simulated warning entry'),
        reason: 'Copy All button must copy the log text to the clipboard',
      );

      await tester.tap(find.byKey(const ValueKey('log_viewer_clear_button')));
      await tester.pumpAndSettle();
      expect(
        find.text('No diagnostic log entries recorded yet.'),
        findsOneWidget,
        reason:
            'Clear Log button must empty the log buffer and show empty hint',
      );
      expect(
        logFile.readAsStringSync(),
        isEmpty,
        reason: 'Clear Log button must truncate tiertask.log to 0 bytes',
      );

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await openSettingsFromMenu(tester);
      await tester.ensureVisible(switchFinder);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(
        logFile.existsSync(),
        isFalse,
        reason:
            'Toggling Diagnostic Log OFF in Settings must delete tiertask.log',
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('drawer_diagnostic_log_tile')),
        findsNothing,
        reason:
            'Toggling Diagnostic Log OFF must hide the sidepanel Log button',
      );
    },
  );
}
