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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';

import 'test_helpers.dart';

void main() {
  testWidgets(
    'SettingsScreen defaults open task count display to Off and persists open task count preference',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.2.0

label home {
  name "Home"
}
label office {
  name "Office"
}
label business {
  name "Business"
  color "#EB06FF"
}
label personal {
  name "Personal"
}
task t001 {
  name "Prepare quarterly report"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
  labels business office
}
task t002 {
  name "Review client contract"
  created 2026-11-01 09:00
  queued 2026-11-01 09:00
  labels business office
}
task t003 {
  name "Water plants"
  created 2026-11-01 10:00
  queued 2026-11-01 10:00
  labels personal home
}
task t004 {
  name "Archived invoice"
  created 2026-10-28 10:00
  queued 2026-10-28 10:00
  finished 2026-10-29 12:00
  labels business office
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
        findsOneWidget,
        reason: 'Settings must display the Open Task Count section',
      );
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('On'), findsOneWidget);

      await tester.ensureVisible(find.text('On'));
      await tester.tap(find.text('On'));
      await tester.pumpAndSettle();

      var savedConfig = await settingsRepository.loadConfig();
      expect(
        savedConfig.showOpenTaskCount,
        isTrue,
        reason: 'Selecting On must persist showOpenTaskCount as true',
      );

      await tester.ensureVisible(find.text('Off'));
      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();

      savedConfig = await settingsRepository.loadConfig();
      expect(
        savedConfig.showOpenTaskCount,
        isFalse,
        reason: 'Selecting Off must persist showOpenTaskCount as false',
      );
    },
  );

  testWidgets(
    'SettingsScreen switches display language between English and German via top-left menu',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(
                const WebDavConfig(language: AppLanguage.english),
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
      await tester.tap(find.text('Deutsch'));
      await tester.pumpAndSettle();

      expect(find.text('Sprache'), findsOneWidget);

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
        of: find.text('WebDAV Synchronization (Single Source of Truth)'),
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
        of: find.text('WebDAV Synchronization (Single Source of Truth)'),
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
}
