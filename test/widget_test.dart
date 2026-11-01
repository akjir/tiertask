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

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tiertask/main.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';
import 'package:tiertask/ui/widgets/tier_page_indicator.dart';

/// Fake [LocalFileRepository] returning an in-memory `.tdf` document for widget tests.
class _FakeLocalFileRepository extends LocalFileRepository {
  /// Creates a [_FakeLocalFileRepository].
  _FakeLocalFileRepository({required super.config, required this.initialTdf});

  /// Initial `.tdf` content returned by [loadTdf] before any mutations are saved.
  String initialTdf;

  @override
  Future<String> loadTdf() async => initialTdf;

  @override
  Future<void> saveTdf(String tdfContent) async {
    initialTdf = tdfContent;
  }
}

/// Fake [WebDavRepository] for deterministic widget tests of connection status banners.
class _FakeWebDavRepository extends WebDavRepository {
  /// Creates a [_FakeWebDavRepository].
  _FakeWebDavRepository({required super.config, required this.shouldFail});

  /// Callback returning whether WebDAV operations should throw a [WebDavException].
  final bool Function() shouldFail;

  @override
  Future<String> fetchTdf() async {
    if (shouldFail()) {
      throw const WebDavException(
        'Authentication failed. Please check username and app password.',
        statusCode: 401,
      );
    }
    return '';
  }

  @override
  Future<void> saveTdf(String tdfContent) async {
    if (shouldFail()) {
      throw const WebDavException(
        'Authentication failed while saving. Please check app password.',
        statusCode: 401,
      );
    }
  }
}

/// Opens the top-left navigation drawer and navigates to SettingsScreen.
Future<void> _openSettingsFromMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu_rounded));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Landing page hides categories and locations when none exist and renders greeting, focus tasks, top-right search, and top-left menu',
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

      expect(
        find.byIcon(Icons.menu_rounded),
        findsOneWidget,
        reason: 'Top-left corner must display the menu button',
      );
      expect(
        find.byIcon(Icons.search_rounded),
        findsOneWidget,
        reason: 'Top-right corner must display the search button',
      );
      expect(
        find.byIcon(Icons.sync_rounded),
        findsNothing,
        reason: 'Sync button must be hidden in the top bar when StorageMode.local is active',
      );
      expect(
        find.byIcon(Icons.settings_outlined),
        findsNothing,
        reason: 'Settings icon must reside inside the top-left menu, not on the landing page header',
      );

      expect(
        find.text("What's up!"),
        findsOneWidget,
        reason: 'Landing page must display the greeting at the top',
      );
      expect(
        find.textContaining('Olivia'),
        findsNothing,
        reason: 'Greeting must not contain the name Olivia',
      );
      expect(
        find.text('FOCUS TASKS'),
        findsOneWidget,
        reason: 'Focus tasks section must appear on the landing page',
      );
      expect(
        find.text('CATEGORIES'),
        findsNothing,
        reason:
            'Categories section must be hidden when no categories are defined',
      );
      expect(
        find.text('LOCATIONS'),
        findsNothing,
        reason:
            'Locations section must be hidden when no locations are defined',
      );
      expect(
        find.byKey(const ValueKey('accent_bar_category_business')),
        findsNothing,
        reason:
            'No category card accent bar must render when categories are empty',
      );
      expect(
        find.byKey(const ValueKey('accent_bar_location_home')),
        findsNothing,
        reason:
            'No location card accent bar must render when locations are empty',
      );

      final greetingDy = tester.getTopLeft(find.text("What's up!")).dy;
      final focusDy = tester.getTopLeft(find.text('FOCUS TASKS')).dy;

      expect(
        greetingDy < focusDy,
        isTrue,
        reason: 'Greeting must appear above Focus tasks',
      );

      expect(
        find.byKey(const ValueKey('bottom_nav_bar')),
        findsNothing,
        reason: 'Persistent bottom navigation bar must not be rendered',
      );
      expect(
        find.byKey(const ValueKey('quick_add_bar')),
        findsNothing,
        reason: 'QuickAddBar must be hidden until the add button is pressed',
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(
        find.byType(FloatingActionButton),
        findsNothing,
        reason: 'Add button must disappear when QuickAddBar opens',
      );
      expect(
        find.byKey(const ValueKey('quick_add_bar')),
        findsOneWidget,
        reason: 'Clicking the add button must show QuickAddBar at the bottom',
      );

      await tester.enterText(
        find.byKey(const ValueKey('quick_add_input')),
        'Daily meeting with team',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('quick_add_bar')),
        findsNothing,
        reason: 'Submitting a task must close QuickAddBar',
      );
      expect(
        find.byType(FloatingActionButton),
        findsOneWidget,
        reason: 'Closing QuickAddBar must restore the add button',
      );
      expect(
        find.text('Daily meeting with team'),
        findsOneWidget,
        reason: 'Added task must appear in the Focus tasks section on the landing page',
      );

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Nonexistent');
      await tester.pumpAndSettle();
      expect(
        find.text('Daily meeting with team'),
        findsNothing,
        reason: 'Search query must filter Focus tasks on the landing page',
      );

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(
        find.text('Daily meeting with team'),
        findsOneWidget,
        reason: 'Closing search must restore all Focus tasks',
      );
    },
  );

  testWidgets(
    'Landing page and side panel omit Categories and Locations even when defined in TDF',
    (WidgetTester tester) async {
      const categoriesAndLocationsTdf = '''
location home {
  name "Home"
  color "#00E5FF"
}
category business {
  name "Business"
  color "#EB06FF"
}
task t001 {
  name "Prepare quarterly report"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
  categories business
  locations home
}
''';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(
                const WebDavConfig(language: AppLanguage.english),
              ),
            ),
            localFileRepositoryProvider.overrideWith(
              (ref) => _FakeLocalFileRepository(
                config: const WebDavConfig(language: AppLanguage.english),
                initialTdf: categoriesAndLocationsTdf,
              ),
            ),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.text('Prepare quarterly report'),
        findsOneWidget,
        reason: 'Focus task must render on the landing page',
      );
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
      expect(
        find.text('Business'),
        findsNothing,
        reason: 'Category cards must not appear on the landing page',
      );
      expect(
        find.text('Home'),
        findsNothing,
        reason: 'Location cards must not appear on the landing page',
      );
      expect(
        find.byKey(const ValueKey('accent_bar_category_business')),
        findsNothing,
        reason: 'Category accent bar must not appear on the landing page',
      );
      expect(
        find.byKey(const ValueKey('accent_bar_location_home')),
        findsNothing,
        reason: 'Location accent bar must not appear on the landing page',
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('drawer_categories_tile')),
        findsNothing,
        reason: 'Side panel must not contain the Categories item',
      );
      expect(
        find.byKey(const ValueKey('drawer_locations_tile')),
        findsNothing,
        reason: 'Side panel must not contain the Locations item',
      );
      expect(
        find.text('Categories'),
        findsNothing,
        reason: 'Side panel must not display Categories label',
      );
      expect(
        find.text('Locations'),
        findsNothing,
        reason: 'Side panel must not display Locations label',
      );
      expect(
        find.text('Ready'),
        findsOneWidget,
        reason: 'Side panel must still expose secondary tiers',
      );
      expect(
        find.text('Settings'),
        findsOneWidget,
        reason: 'Side panel must still expose Settings',
      );
    },
  );

  testWidgets(
    'Landing page renders German labels, hides empty categories and locations, and exposes secondary tiers in the top-left menu',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(
                const WebDavConfig(language: AppLanguage.german),
              ),
            ),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Was steht an!'), findsOneWidget);
      expect(find.textContaining('Olivia'), findsNothing);
      expect(find.text('FOKUSAUFGABEN'), findsOneWidget);
      expect(
        find.text('KATEGORIEN'),
        findsNothing,
        reason: 'German categories heading must be hidden when none exist',
      );
      expect(
        find.text('ORTE'),
        findsNothing,
        reason: 'German locations heading must be hidden when none exist',
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Bereit'), findsOneWidget);
      expect(find.text('Geplant'), findsOneWidget);
      expect(find.text('Blockiert'), findsOneWidget);
      expect(find.text('Irgendwann'), findsOneWidget);
      expect(find.text('Erledigt'), findsOneWidget);
      expect(find.text('Einstellungen'), findsOneWidget);
    },
  );

  testWidgets(
    'SettingsScreen defaults open task count display to Off and persists open task count preference',
    (WidgetTester tester) async {
      const seededTdf = '''
location home {
  name "Home"
}
location office {
  name "Office"
}
category business {
  name "Business"
  color "#EB06FF"
}
category personal {
  name "Personal"
}
task t001 {
  name "Prepare quarterly report"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
  categories business
  locations office
}
task t002 {
  name "Review client contract"
  created 2026-11-01 09:00
  queued 2026-11-01 09:00
  categories business
  locations office
}
task t003 {
  name "Water plants"
  created 2026-11-01 10:00
  queued 2026-11-01 10:00
  categories personal
  locations home
}
task t004 {
  name "Archived invoice"
  created 2026-10-28 10:00
  queued 2026-10-28 10:00
  finished 2026-10-29 12:00
  categories business
  locations office
}
''';
      final settingsRepository = InMemorySettingsRepository(
        const WebDavConfig(language: AppLanguage.english),
      );
      final fakeLocalRepo = _FakeLocalFileRepository(
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

      await _openSettingsFromMenu(tester);

      expect(
        find.text('Open Task Count'),
        findsOneWidget,
        reason: 'Settings must display the Open Task Count section',
      );
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('On'), findsOneWidget);

      await tester.tap(find.text('On'));
      await tester.pumpAndSettle();

      var savedConfig = await settingsRepository.loadConfig();
      expect(
        savedConfig.showOpenTaskCount,
        isTrue,
        reason: 'Selecting On must persist showOpenTaskCount as true',
      );

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
    'Top-right bar shows sync icon next to search only when WebDAV or Both storage mode is selected',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(
                const WebDavConfig(
                  language: AppLanguage.english,
                  storageMode: StorageMode.local,
                ),
              ),
            ),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.byIcon(Icons.sync_rounded),
        findsNothing,
        reason: 'Local mode must not display the sync icon in the top bar',
      );

      await _openSettingsFromMenu(tester);
      await tester.ensureVisible(find.text('WebDAV'));
      await tester.tap(find.text('WebDAV'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(
        find.byIcon(Icons.sync_rounded),
        findsOneWidget,
        reason: 'WebDAV mode must display the sync icon in the top-right bar',
      );

      await _openSettingsFromMenu(tester);
      await tester.ensureVisible(find.text('Both'));
      await tester.tap(find.text('Both'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(
        find.byIcon(Icons.sync_rounded),
        findsOneWidget,
        reason: 'Both mode must display the sync icon in the top-right bar',
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

      await _openSettingsFromMenu(tester);

      expect(find.text('Language'), findsOneWidget);
      await tester.tap(find.text('Deutsch'));
      await tester.pumpAndSettle();

      expect(find.text('Sprache'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Was steht an!'), findsOneWidget);
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

      await _openSettingsFromMenu(tester);

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

      await _openSettingsFromMenu(tester);

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
              return _FakeWebDavRepository(
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

      await _openSettingsFromMenu(tester);

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
    'Clicking the add button replaces it with the inline QuickAddBar containing input, Priority, Someday, Categories, Locations, no-op Advanced, and Cancel buttons',
    (WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const WebDavConfig(language: AppLanguage.english),
            ),
          ),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('bottom_nav_bar')),
        findsNothing,
        reason: 'Old bottom navigation bar must be removed',
      );
      expect(
        find.byType(FloatingActionButton),
        findsOneWidget,
        reason: 'Only the circular add button must be visible initially',
      );
      expect(
        find.byKey(const ValueKey('quick_add_bar')),
        findsNothing,
        reason: 'QuickAddBar must be hidden initially',
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(
        find.byType(FloatingActionButton),
        findsNothing,
        reason: 'Add button must disappear when clicked',
      );

      final barFinder = find.byKey(const ValueKey('quick_add_bar'));
      final inputFinder = find.byKey(const ValueKey('quick_add_input'));
      final priorityFinder = find.byKey(
        const ValueKey('quick_add_priority_button'),
      );
      final somedayFinder = find.byKey(
        const ValueKey('quick_add_someday_button'),
      );
      final categoriesFinder = find.byKey(
        const ValueKey('quick_add_categories_button'),
      );
      final locationsFinder = find.byKey(
        const ValueKey('quick_add_locations_button'),
      );
      final advancedFinder = find.byKey(
        const ValueKey('quick_add_advanced_button'),
      );
      final cancelFinder = find.byKey(
        const ValueKey('quick_add_cancel_button'),
      );

      expect(barFinder, findsOneWidget);
      expect(inputFinder, findsOneWidget);
      expect(priorityFinder, findsOneWidget);
      expect(somedayFinder, findsOneWidget);
      expect(categoriesFinder, findsOneWidget);
      expect(locationsFinder, findsOneWidget);
      expect(advancedFinder, findsOneWidget);
      expect(cancelFinder, findsOneWidget);

      final inputDx = tester.getTopLeft(inputFinder).dx;
      final priorityDx = tester.getTopLeft(priorityFinder).dx;
      final somedayDx = tester.getTopLeft(somedayFinder).dx;
      final categoriesDx = tester.getTopLeft(categoriesFinder).dx;
      final locationsDx = tester.getTopLeft(locationsFinder).dx;
      final advancedDx = tester.getTopLeft(advancedFinder).dx;
      final cancelDx = tester.getTopLeft(cancelFinder).dx;

      expect(
        inputDx < priorityDx &&
            priorityDx < somedayDx &&
            somedayDx < categoriesDx &&
            categoriesDx < locationsDx &&
            locationsDx < advancedDx &&
            advancedDx < cancelDx,
        isTrue,
        reason: 'QuickAddBar items must be ordered left-to-right: input, priority, someday, categories, locations, advanced, cancel',
      );

      final priorityIconFinder = find.descendant(
        of: priorityFinder,
        matching: find.byType(Icon),
      );
      final somedayIconFinder = find.descendant(
        of: somedayFinder,
        matching: find.byType(Icon),
      );
      expect(
        tester.widget<Icon>(priorityIconFinder).color,
        equals(const Color(0xFF9BA8E5)),
        reason: 'Priority icon must be muted when unselected',
      );
      expect(
        tester.widget<Icon>(somedayIconFinder).color,
        equals(const Color(0xFF9BA8E5)),
        reason: 'Someday icon must be muted when unselected',
      );

      await tester.tap(priorityFinder);
      await tester.pump();
      expect(
        tester.widget<Icon>(priorityIconFinder).color,
        equals(const Color(0xFFEB06FF)),
        reason: 'Tapping Priority must highlight the Priority button',
      );
      expect(
        tester.widget<Icon>(somedayIconFinder).color,
        equals(const Color(0xFF9BA8E5)),
        reason: 'Someday must remain unselected when Priority is active',
      );

      await tester.tap(somedayFinder);
      await tester.pump();
      expect(
        tester.widget<Icon>(somedayIconFinder).color,
        equals(const Color(0xFF2196F3)),
        reason: 'Tapping Someday must highlight the Someday button',
      );
      expect(
        tester.widget<Icon>(priorityIconFinder).color,
        equals(const Color(0xFF9BA8E5)),
        reason: 'Enabling Someday must automatically turn off Priority',
      );

      await tester.tap(advancedFinder);
      await tester.pumpAndSettle();
      expect(
        find.text('Extended Task View'),
        findsNothing,
        reason: 'Advanced button must be a no-op and not open an extended view',
      );
      expect(
        barFinder,
        findsOneWidget,
        reason: 'QuickAddBar must remain open after tapping Advanced',
      );

      await tester.enterText(inputFinder, 'Draft to cancel');
      await tester.pump();
      await tester.tap(cancelFinder);
      await tester.pumpAndSettle();

      expect(
        barFinder,
        findsNothing,
        reason: 'Tapping Cancel must close QuickAddBar',
      );
      expect(
        find.byType(FloatingActionButton),
        findsOneWidget,
        reason: 'Tapping Cancel must restore the add button',
      );
      expect(
        container.read(taskNotifierProvider).value!.focus,
        isEmpty,
        reason: 'Cancelling must not add a task',
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(somedayFinder);
      await tester.pump();
      await tester.enterText(inputFinder, 'Future idea');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('quick_add_submit_button')));
      await tester.pumpAndSettle();

      expect(
        barFinder,
        findsNothing,
        reason: 'Submitting a task must close QuickAddBar',
      );
      expect(
        find.byType(FloatingActionButton),
        findsOneWidget,
        reason: 'Submitting a task must restore the add button',
      );

      final boardAfterSomeday = container.read(taskNotifierProvider).value!;
      expect(
        boardAfterSomeday.someday.map((task) => task.title),
        equals(['Future idea']),
        reason: 'Submitting with Someday active must add task to Someday tier',
      );
      expect(boardAfterSomeday.focus, isEmpty);
    },
  );

  testWidgets(
    'QuickAddBar Categories and Locations buttons expand upward menus to select multiple categories and locations',
    (WidgetTester tester) async {
      const seededContextsTdf = '''
location home {
  name "Home"
  color "#00E5FF"
}
location office {
  name "Office"
  color "#FF9100"
}
category c_it {
  name "IT"
  color "#2196F3"
}
category c_ops {
  name "Operations"
  color "#EB06FF"
}
category c_hr {
  name "HR"
  color "#4CAF50"
}
''';
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const WebDavConfig(language: AppLanguage.english),
            ),
          ),
          localFileRepositoryProvider.overrideWith(
            (ref) => _FakeLocalFileRepository(
              config: const WebDavConfig(language: AppLanguage.english),
              initialTdf: seededContextsTdf,
            ),
          ),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final barFinder = find.byKey(const ValueKey('quick_add_bar'));
      final categoriesButton = find.byKey(
        const ValueKey('quick_add_categories_button'),
      );
      final locationsButton = find.byKey(
        const ValueKey('quick_add_locations_button'),
      );
      final categoriesMenu = find.byKey(
        const ValueKey('quick_add_categories_menu'),
      );
      final locationsMenu = find.byKey(
        const ValueKey('quick_add_locations_menu'),
      );

      expect(
        categoriesMenu,
        findsNothing,
        reason: 'Categories upward menu must be closed initially',
      );
      expect(
        locationsMenu,
        findsNothing,
        reason: 'Locations upward menu must be closed initially',
      );

      await tester.tap(categoriesButton);
      await tester.pumpAndSettle();

      expect(
        categoriesMenu,
        findsOneWidget,
        reason:
            'Tapping Categories button must expand the categories menu upward',
      );
      expect(
        locationsMenu,
        findsNothing,
        reason: 'Locations menu must remain closed when Categories is open',
      );
      expect(
        tester.getBottomLeft(categoriesMenu).dy <=
            tester.getTopLeft(barFinder).dy + 4.0,
        isTrue,
        reason: 'Categories menu must expand upward above QuickAddBar',
      );
      expect(
        tester.widget<Material>(categoriesMenu).clipBehavior,
        equals(Clip.antiAlias),
        reason: 'Categories menu Material must clip ink highlights to its rounded border',
      );

      final catItOption = find.byKey(const ValueKey('quick_add_category_c_it'));
      final catOpsOption = find.byKey(
        const ValueKey('quick_add_category_c_ops'),
      );
      final catHrOption = find.byKey(const ValueKey('quick_add_category_c_hr'));
      expect(catItOption, findsOneWidget);
      expect(catOpsOption, findsOneWidget);
      expect(catHrOption, findsOneWidget);

      final catItInkWell = tester.widget<InkWell>(
        find.descendant(of: catItOption, matching: find.byType(InkWell)),
      );
      expect(
        catItInkWell.borderRadius,
        isNotNull,
        reason: 'Category option InkWell must define a borderRadius so press/focus highlight does not overlap rounded corners',
      );

      await tester.tap(catItOption);
      await tester.pump();
      await tester.tap(catOpsOption);
      await tester.pump();

      await tester.tap(find.text("What's up!"));
      await tester.pumpAndSettle();
      expect(
        categoriesMenu,
        findsNothing,
        reason: 'Tapping outside the Categories menu must close it',
      );

      await tester.tap(locationsButton);
      await tester.pumpAndSettle();

      expect(
        categoriesMenu,
        findsNothing,
        reason: 'Opening Locations menu must keep Categories menu closed',
      );
      expect(
        locationsMenu,
        findsOneWidget,
        reason:
            'Tapping Locations button must expand the locations menu upward',
      );
      expect(
        tester.getBottomLeft(locationsMenu).dy <=
            tester.getTopLeft(barFinder).dy + 4.0,
        isTrue,
        reason: 'Locations menu must expand upward above QuickAddBar',
      );
      expect(
        tester.widget<Material>(locationsMenu).clipBehavior,
        equals(Clip.antiAlias),
        reason: 'Locations menu Material must clip ink highlights to its rounded border',
      );

      final locHomeOption = find.byKey(
        const ValueKey('quick_add_location_home'),
      );
      final locOfficeOption = find.byKey(
        const ValueKey('quick_add_location_office'),
      );
      expect(locHomeOption, findsOneWidget);
      expect(locOfficeOption, findsOneWidget);

      final locHomeInkWell = tester.widget<InkWell>(
        find.descendant(of: locHomeOption, matching: find.byType(InkWell)),
      );
      expect(
        locHomeInkWell.borderRadius,
        isNotNull,
        reason: 'Location option InkWell must define a borderRadius so press/focus highlight does not overlap rounded corners',
      );

      await tester.tap(locHomeOption);
      await tester.pump();
      await tester.tap(locOfficeOption);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('quick_add_input')));
      await tester.pumpAndSettle();
      expect(
        locationsMenu,
        findsNothing,
        reason: 'Tapping outside the Locations menu must close it',
      );

      await tester.enterText(
        find.byKey(const ValueKey('quick_add_input')),
        'Audit hybrid network',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('quick_add_submit_button')));
      await tester.pumpAndSettle();

      final board = container.read(taskNotifierProvider).value!;
      expect(board.focus.length, equals(1));
      final createdTask = board.focus.single;
      expect(createdTask.title, equals('Audit hybrid network'));
      expect(
        createdTask.categoryIds,
        equals(['c_it', 'c_ops']),
        reason: 'Created task must store all selected categories',
      );
      expect(
        createdTask.locationIds,
        equals(['home', 'office']),
        reason: 'Created task must store all selected locations',
      );
    },
  );

  testWidgets(
    'Navigation drawer opens secondary tier sheets for Ready, Planned, Blocked (including suspended), Someday, and Completed without a bottom navigation bar',
    (WidgetTester tester) async {
      const secondaryTiersTdf = '''
task f1 {
  name "Focus Task 1"
  created 2026-11-01 07:00
  queued 2026-11-01 07:00
}
task f2 {
  name "Focus Task 2"
  created 2026-11-01 07:05
  queued 2026-11-01 07:05
}
task f3 {
  name "Focus Task 3"
  created 2026-11-01 07:10
  queued 2026-11-01 07:10
}
task r1 {
  name "Ready Task 1"
  created 2026-11-01 07:15
  queued 2026-11-01 07:15
}
task r2 {
  name "Ready Task 2"
  created 2026-11-01 07:20
  queued 2026-11-01 07:20
}
task r3 {
  name "Ready Task 3"
  created 2026-11-01 07:25
  queued 2026-11-01 07:25
}
task r4 {
  name "Ready Task 4"
  created 2026-11-01 07:30
  queued 2026-11-01 07:30
}
task r5 {
  name "Ready Task 5"
  created 2026-11-01 07:35
  queued 2026-11-01 07:35
}
task p1 {
  name "Planned Backlog Task"
  created 2026-11-01 07:40
  queued 2026-11-01 07:40
}
task blk_dep {
  name "Blocked Prerequisite Task"
  created 2026-11-01 07:45
  queued 2026-11-01 07:45
  blocked f1
}
task blk_susp {
  name "Suspended Deferred Task"
  created 2026-11-01 07:50
  queued 2026-11-01 07:50
  suspended 2026-11-05 09:00
}
task smd1 {
  name "Someday Idea Task"
  created 2026-11-01 08:00
}
task cmp1 {
  name "Completed Archive Task"
  created 2026-10-28 08:00
  queued 2026-10-28 08:00
  finished 2026-10-29 10:00
}
''';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(
                const WebDavConfig(language: AppLanguage.english),
              ),
            ),
            localFileRepositoryProvider.overrideWith(
              (ref) => _FakeLocalFileRepository(
                config: const WebDavConfig(language: AppLanguage.english),
                initialTdf: secondaryTiersTdf,
              ),
            ),
            clockProvider.overrideWithValue(
              () => DateTime.utc(2026, 11, 1, 12, 0),
            ),
          ],
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('bottom_nav_bar')),
        findsNothing,
        reason: 'Bottom navigation bar must be removed',
      );
      expect(
        find.byType(FloatingActionButton),
        findsOneWidget,
        reason: 'Only the add button must be displayed at the bottom',
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blocked'));
      await tester.pumpAndSettle();

      expect(
        find.text('Blocked Prerequisite Task'),
        findsOneWidget,
        reason:
            'Blocked tier sheet must display tasks blocked by prerequisites',
      );
      expect(
        find.text('Suspended Deferred Task'),
        findsOneWidget,
        reason: 'Blocked tier sheet must also display suspended tasks',
      );
    },
  );

  testWidgets(
    'Bottom tier indicator renders above QuickAddBar when add button is pressed, updates active icon when sliding across tiers, and jumps to target pane via wave wheel on long-press drag',
    (WidgetTester tester) async {
      const allTiersTdf = '''
task f1 {
  name "Focus Pane Task"
  created 2026-11-01 07:00
  queued 2026-11-01 07:00
}
task f2 {
  name "Focus Pane Task 2"
  created 2026-11-01 07:05
  queued 2026-11-01 07:05
}
task f3 {
  name "Focus Pane Task 3"
  created 2026-11-01 07:10
  queued 2026-11-01 07:10
}
task r1 {
  name "Ready Pane Task"
  created 2026-11-01 07:15
  queued 2026-11-01 07:15
}
task r2 {
  name "Ready Pane Task 2"
  created 2026-11-01 07:20
  queued 2026-11-01 07:20
}
task r3 {
  name "Ready Pane Task 3"
  created 2026-11-01 07:25
  queued 2026-11-01 07:25
}
task r4 {
  name "Ready Pane Task 4"
  created 2026-11-01 07:30
  queued 2026-11-01 07:30
}
task r5 {
  name "Ready Pane Task 5"
  created 2026-11-01 07:35
  queued 2026-11-01 07:35
}
task p1 {
  name "Planned Pane Task"
  created 2026-11-01 07:40
  queued 2026-11-01 07:40
}
task blk1 {
  name "Blocked Pane Task"
  created 2026-11-01 07:45
  queued 2026-11-01 07:45
  blocked f1
}
task susp1 {
  name "Suspended Pane Task"
  created 2026-11-01 07:50
  queued 2026-11-01 07:50
  suspended 2026-11-05 09:00
}
task smd1 {
  name "Someday Pane Task"
  created 2026-11-01 08:00
}
task cmp1 {
  name "Completed Pane Task"
  created 2026-10-28 08:00
  queued 2026-10-28 08:00
  finished 2026-10-29 10:00
}
''';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(
                const WebDavConfig(language: AppLanguage.english),
              ),
            ),
            localFileRepositoryProvider.overrideWith(
              (ref) => _FakeLocalFileRepository(
                config: const WebDavConfig(language: AppLanguage.english),
                initialTdf: allTiersTdf,
              ),
            ),
            clockProvider.overrideWithValue(
              () => DateTime.utc(2026, 11, 1, 12, 0),
            ),
          ],
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();

      final indicatorFinder = find.byKey(const ValueKey('tier_page_indicator'));
      expect(
        indicatorFinder,
        findsOneWidget,
        reason: 'Bottom tier indicator must be rendered at the bottom edge',
      );

      final focusItem = find.byKey(const ValueKey('tier_indicator_item_focus'));
      final readyItem = find.byKey(const ValueKey('tier_indicator_item_ready'));
      final plannedItem = find.byKey(
        const ValueKey('tier_indicator_item_planned'),
      );
      final blockedItem = find.byKey(
        const ValueKey('tier_indicator_item_blocked'),
      );
      final somedayItem = find.byKey(
        const ValueKey('tier_indicator_item_someday'),
      );
      final completedItem = find.byKey(
        const ValueKey('tier_indicator_item_completed'),
      );

      expect(focusItem, findsOneWidget);
      expect(readyItem, findsOneWidget);
      expect(plannedItem, findsOneWidget);
      expect(blockedItem, findsOneWidget);
      expect(somedayItem, findsOneWidget);
      expect(completedItem, findsOneWidget);

      final focusDx = tester.getCenter(focusItem).dx;
      final readyDx = tester.getCenter(readyItem).dx;
      final plannedDx = tester.getCenter(plannedItem).dx;
      final blockedDx = tester.getCenter(blockedItem).dx;
      final somedayDx = tester.getCenter(somedayItem).dx;
      final completedDx = tester.getCenter(completedItem).dx;

      expect(
        focusDx < readyDx &&
            readyDx < plannedDx &&
            plannedDx < blockedDx &&
            blockedDx < somedayDx &&
            somedayDx < completedDx,
        isTrue,
        reason: 'Tier indicator items must be ordered left-to-right: Focus, Ready, Planned, Blocked, Someday, Completed',
      );

      expect(
        find.byKey(const ValueKey('tier_indicator_icon_focus')),
        findsOneWidget,
        reason: 'Active Focus tier must render an icon instead of a dot',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_dot_focus')),
        findsNothing,
        reason: 'Active Focus tier must not render a dot',
      );
      for (final inactiveName in [
        'ready',
        'planned',
        'blocked',
        'someday',
        'completed',
      ]) {
        expect(
          find.byKey(ValueKey('tier_indicator_dot_$inactiveName')),
          findsOneWidget,
          reason: 'Inactive tier $inactiveName must render a dot',
        );
        expect(
          find.byKey(ValueKey('tier_indicator_icon_$inactiveName')),
          findsNothing,
          reason: 'Inactive tier $inactiveName must not render an icon',
        );
      }

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final quickAddBarFinder = find.byKey(const ValueKey('quick_add_bar'));
      expect(quickAddBarFinder, findsOneWidget);
      expect(
        indicatorFinder,
        findsOneWidget,
        reason: 'Tier indicator must remain visible when QuickAddBar is open',
      );
      expect(
        tester.getBottomLeft(indicatorFinder).dy <=
            tester.getTopLeft(quickAddBarFinder).dy + 1.0,
        isTrue,
        reason: 'Tier indicator must be positioned above QuickAddBar when the add button is pressed',
      );

      await tester.tap(find.byKey(const ValueKey('quick_add_cancel_button')));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(
        find.text('Ready Pane Task'),
        findsOneWidget,
        reason: 'Sliding right-to-left from Focus must display Ready tier pane',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_icon_ready')),
        findsOneWidget,
        reason: 'Sliding to Ready must display the Ready icon in the indicator',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_dot_focus')),
        findsOneWidget,
        reason: 'Focus must become a dot after sliding to Ready',
      );

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(
        find.text('Planned Pane Task'),
        findsOneWidget,
        reason: 'Sliding again must display Planned tier pane',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_icon_planned')),
        findsOneWidget,
        reason: 'Planned tier must display its icon when active',
      );

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(
        find.text('Blocked Pane Task'),
        findsOneWidget,
        reason: 'Sliding to Blocked pane must show blocked tasks',
      );
      expect(
        find.text('Suspended Pane Task'),
        findsOneWidget,
        reason: 'Blocked pane must also show suspended tasks',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_icon_blocked')),
        findsOneWidget,
        reason: 'Blocked tier must display its icon when active',
      );

      final gesture = await tester.startGesture(tester.getCenter(blockedItem));
      await tester.pump(const Duration(milliseconds: 600));

      final waveLabelFinder = find.byKey(
        const ValueKey('tier_indicator_wave_label'),
      );
      expect(
        waveLabelFinder,
        findsOneWidget,
        reason:
            'Holding the indicator must display the tier name above the wave',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_wave_arc')),
        findsNothing,
        reason: 'Connecting line and dark-blue bottom wave background must not be rendered',
      );
      final waveLabelContainer = tester.widget<Container>(waveLabelFinder);
      final waveLabelDecoration =
          waveLabelContainer.decoration as BoxDecoration?;
      expect(
        waveLabelDecoration?.border,
        isNull,
        reason: 'Overlay tier name label must not have a border',
      );
      expect(
        find.descendant(of: waveLabelFinder, matching: find.text('Blocked')),
        findsOneWidget,
        reason:
            'Wave label must initially show Blocked while holding over Blocked',
      );

      final focusDotFinder = find.byKey(
        const ValueKey('tier_indicator_dot_focus'),
      );
      final readyDotFinder = find.byKey(
        const ValueKey('tier_indicator_dot_ready'),
      );
      final plannedDotFinder = find.byKey(
        const ValueKey('tier_indicator_dot_planned'),
      );
      final somedayDotFinder = find.byKey(
        const ValueKey('tier_indicator_dot_someday'),
      );
      final completedDotFinder = find.byKey(
        const ValueKey('tier_indicator_dot_completed'),
      );

      final focusDotSize = tester.getSize(focusDotFinder);
      final readyDotSize = tester.getSize(readyDotFinder);
      final plannedDotSize = tester.getSize(plannedDotFinder);
      final somedayDotSize = tester.getSize(somedayDotFinder);
      final completedDotSize = tester.getSize(completedDotFinder);
      expect(
        plannedDotSize.width,
        closeTo(focusDotSize.width * 1.5, 0.01),
        reason: 'Left neighbor dot (Planned) adjacent to active Blocked tier must be 1.5x base dot size during wave effect',
      );
      expect(
        somedayDotSize.width,
        closeTo(focusDotSize.width * 1.5, 0.01),
        reason: 'Right neighbor dot (Someday) adjacent to active Blocked tier must be 1.5x base dot size during wave effect',
      );
      expect(
        readyDotSize.width,
        closeTo(focusDotSize.width, 0.01),
        reason: 'Non-adjacent dots must keep the base dot size',
      );
      expect(
        completedDotSize.width,
        closeTo(focusDotSize.width, 0.01),
        reason: 'Non-adjacent dots must keep the base dot size',
      );

      final plannedDotDecoration =
          tester.widget<Container>(plannedDotFinder).decoration
              as BoxDecoration?;
      final focusDotDecoration =
          tester.widget<Container>(focusDotFinder).decoration as BoxDecoration?;
      expect(
        plannedDotDecoration?.color,
        equals(TierPageIndicator.intermediateColor),
        reason: 'Larger adjacent wave dots must use the intermediate color between inactive dot and active icon',
      );
      expect(
        focusDotDecoration?.color,
        equals(TierPageIndicator.inactiveDotColor),
        reason: 'Non-adjacent dots must use the standard inactive dot color',
      );

      final blockedWaveDy = tester.getCenter(blockedItem).dy;
      final focusWaveDy = tester.getCenter(focusItem).dy;
      expect(
        blockedWaveDy < focusWaveDy,
        isTrue,
        reason: 'Held tier item in the wave crest must be lifted higher (smaller dy) than distant items',
      );

      final completedTarget = tester.getCenter(completedItem);
      await gesture.moveTo(completedTarget);
      await tester.pump();

      expect(
        find.descendant(of: waveLabelFinder, matching: find.text('Completed')),
        findsOneWidget,
        reason: 'Dragging the held indicator to Completed must update the wave label to Completed',
      );
      final somedayNeighborSize = tester.getSize(
        find.byKey(const ValueKey('tier_indicator_dot_someday')),
      );
      final blockedNonNeighborSize = tester.getSize(
        find.byKey(const ValueKey('tier_indicator_dot_blocked')),
      );
      expect(
        somedayNeighborSize.width,
        closeTo(blockedNonNeighborSize.width * 1.5, 0.01),
        reason: 'Adjacent neighbor dot (Someday) next to Completed must be 1.5x base size',
      );
      final completedWaveDy = tester.getCenter(completedItem).dy;
      final readyWaveDy = tester.getCenter(readyItem).dy;
      expect(
        completedWaveDy < readyWaveDy,
        isTrue,
        reason: 'Moving the wave to Completed must lift the Completed item higher than distant items',
      );

      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        waveLabelFinder,
        findsNothing,
        reason: 'Releasing the indicator must hide the wave label',
      );
      expect(
        find.text('Completed Pane Task'),
        findsOneWidget,
        reason: 'Releasing the indicator on Completed must jump directly to the Completed pane',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_icon_completed')),
        findsOneWidget,
        reason:
            'Completed tier must display its icon after jumping to Completed',
      );

      final mouseGesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouseGesture.addPointer(location: Offset.zero);
      addTearDown(mouseGesture.removePointer);

      await mouseGesture.moveTo(tester.getCenter(somedayItem));
      await tester.pumpAndSettle();

      expect(
        tester.getCenter(somedayItem).dy,
        closeTo(tester.getCenter(focusItem).dy, 0.1),
        reason: 'Desktop mouse-over must keep indicator items flat without vertical wave displacement',
      );
      final hoveredSomedayIconFinder = find.byKey(
        const ValueKey('tier_indicator_icon_someday'),
      );
      expect(
        hoveredSomedayIconFinder,
        findsOneWidget,
        reason: 'Desktop mouse-over on an inactive indicator must display its icon instead of a dot',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_dot_someday')),
        findsNothing,
        reason: 'Desktop mouse-over on an inactive indicator must replace the dot with the icon',
      );
      final hoveredSomedayIcon = tester.widget<Icon>(hoveredSomedayIconFinder);
      final activeCompletedIcon = tester.widget<Icon>(
        find.byKey(const ValueKey('tier_indicator_icon_completed')),
      );
      expect(
        hoveredSomedayIcon.color,
        equals(TierPageIndicator.intermediateColor),
        reason: 'Hovered indicator icon must be rendered in the color between the active icon color and inactive dot color',
      );
      expect(
        activeCompletedIcon.color,
        equals(TierPageIndicator.activeIconColor),
        reason: 'Active indicator icon must keep the active icon color',
      );
      expect(
        find.descendant(of: indicatorFinder, matching: find.text('Someday')),
        findsOneWidget,
        reason: 'Desktop mouse-over must display the hovered tier name without wave animation',
      );

      await tester.tap(somedayItem);
      await tester.pumpAndSettle();

      expect(
        find.text('Someday Pane Task'),
        findsOneWidget,
        reason: 'Clicking a tier indicator item on desktop must jump to that tier pane',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_icon_someday')),
        findsOneWidget,
        reason: 'Someday tier must display its icon after selecting Someday',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(
        find.text('Blocked Pane Task'),
        findsOneWidget,
        reason: 'Pressing Left Arrow on desktop must navigate to the previous tier pane (Blocked)',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_icon_blocked')),
        findsOneWidget,
        reason: 'Active indicator icon must update to Blocked after Left Arrow',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(
        find.text('Someday Pane Task'),
        findsOneWidget,
        reason: 'Pressing Right Arrow on desktop must navigate to the next tier pane (Someday)',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_icon_someday')),
        findsOneWidget,
        reason:
            'Active indicator icon must update to Someday after Right Arrow',
      );
    },
  );
}
