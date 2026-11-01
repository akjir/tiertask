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
import 'package:tiertask/repositories/webdav_repository.dart';

/// Fake [WebDavRepository] for deterministic widget tests of connection status banners.
class _FakeWebDavRepository extends WebDavRepository {
  /// Creates a [_FakeWebDavRepository].
  _FakeWebDavRepository({required super.config, required this.shouldFail});

  /// Callback returning whether WebDAV operations should throw a [WebDavException].
  final bool Function() shouldFail;

  @override
  Future<String> fetchMarkdown() async {
    if (shouldFail()) {
      throw const WebDavException(
        'Authentication failed. Please check username and app password.',
        statusCode: 401,
      );
    }
    return '';
  }

  @override
  Future<void> saveMarkdown(String markdownContent) async {
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
    'Landing page renders greeting, focus tasks only, category and location cards with solid color bars, top-right search, and top-left menu',
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
        findsOneWidget,
        reason: 'Categories section must appear on the landing page',
      );
      expect(
        find.text('LOCATIONS'),
        findsOneWidget,
        reason: 'Locations section must appear on the landing page',
      );
      expect(find.text('Business'), findsOneWidget);
      expect(
        find.text('40 tasks'),
        findsNothing,
        reason: 'Category total task count must be hidden when showOpenTaskCount is off by default',
      );
      expect(find.text('Personal'), findsOneWidget);
      expect(
        find.text('18 tasks'),
        findsNothing,
        reason: 'Category total task count must be hidden when showOpenTaskCount is off by default',
      );
      expect(find.text('Home'), findsOneWidget);
      expect(
        find.text('12 tasks'),
        findsNothing,
        reason: 'Location total task count must be hidden when showOpenTaskCount is off by default',
      );
      expect(find.text('Office'), findsOneWidget);
      expect(
        find.text('24 tasks'),
        findsNothing,
        reason: 'Location total task count must be hidden when showOpenTaskCount is off by default',
      );
      expect(
        find.byType(LinearProgressIndicator),
        findsNothing,
        reason: 'Category and location cards must not render a done progress indicator',
      );
      expect(
        find.byKey(const ValueKey('accent_bar_category_business')),
        findsOneWidget,
        reason: 'Category card must render a solid colored line bar',
      );
      expect(
        find.byKey(const ValueKey('accent_bar_location_home')),
        findsOneWidget,
        reason: 'Location card must render a solid colored line bar',
      );

      final greetingDy = tester.getTopLeft(find.text("What's up!")).dy;
      final focusDy = tester.getTopLeft(find.text('FOCUS TASKS')).dy;
      final categoriesDy = tester.getTopLeft(find.text('CATEGORIES')).dy;
      final locationsDy = tester.getTopLeft(find.text('LOCATIONS')).dy;

      expect(
        greetingDy < focusDy,
        isTrue,
        reason: 'Greeting must appear above Focus tasks',
      );
      expect(
        focusDy < categoriesDy,
        isTrue,
        reason: 'Focus tasks must appear above Categories',
      );
      expect(
        categoriesDy < locationsDy,
        isTrue,
        reason: 'Categories must appear above Locations',
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Daily meeting with team');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

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
    'Landing page renders German labels and exposes secondary tiers and actions in the top-left menu',
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
      expect(find.text('KATEGORIEN'), findsOneWidget);
      expect(find.text('ORTE'), findsOneWidget);
      expect(
        find.text('40 Aufgaben'),
        findsNothing,
        reason: 'German category task count must be hidden by default when showOpenTaskCount is off',
      );
      expect(
        find.text('18 Aufgaben'),
        findsNothing,
        reason: 'German category task count must be hidden by default when showOpenTaskCount is off',
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
    'SettingsScreen defaults open task count display to Off and toggles total task count on category and location cards',
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

      expect(
        find.text('40 tasks'),
        findsNothing,
        reason: 'Total task count must be hidden by default on category cards',
      );
      expect(
        find.text('12 tasks'),
        findsNothing,
        reason: 'Total task count must be hidden by default on location cards',
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

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(
        find.text('40 tasks'),
        findsOneWidget,
        reason: 'Enabling showOpenTaskCount must display total tasks on Business category card',
      );
      expect(
        find.text('18 tasks'),
        findsOneWidget,
        reason: 'Enabling showOpenTaskCount must display total tasks on Personal category card',
      );
      expect(
        find.text('12 tasks'),
        findsOneWidget,
        reason: 'Enabling showOpenTaskCount must display total tasks on Home location card',
      );
      expect(
        find.text('24 tasks'),
        findsOneWidget,
        reason: 'Enabling showOpenTaskCount must display total tasks on Office location card',
      );

      await _openSettingsFromMenu(tester);
      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();

      savedConfig = await settingsRepository.loadConfig();
      expect(
        savedConfig.showOpenTaskCount,
        isFalse,
        reason: 'Selecting Off must persist showOpenTaskCount as false',
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(
        find.text('40 tasks'),
        findsNothing,
        reason: 'Disabling showOpenTaskCount must hide total tasks on category cards',
      );
      expect(
        find.text('12 tasks'),
        findsNothing,
        reason: 'Disabling showOpenTaskCount must hide total tasks on location cards',
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
      expect(find.text('Local Markdown File Name'), findsOneWidget);

      await tester.ensureVisible(find.text('Both'));
      await tester.tap(find.text('Both'));
      await tester.pumpAndSettle();

      expect(
        find.text('Local Markdown File Name'),
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
        find.widgetWithText(TextFormField, 'Local Markdown File Name'),
        'custom_local_tasks.md',
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
        equals('custom_local_tasks.md'),
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
        find.text(
          'Connection succeeded. Markdown file synchronized with WebDAV.',
        ),
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
        find.text(
          'Connection succeeded. Markdown file synchronized with WebDAV.',
        ),
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
          filePath: 'tiertask.md',
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
          'Connection succeeded. Markdown file synchronized with WebDAV.';
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
    'QuickAddBar renders input field, mutually exclusive Priority and Someday toggles, Advanced button, and enables Add only when text is entered',
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

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final inputFinder = find.byKey(const ValueKey('quick_add_input'));
      final priorityFinder = find.byKey(
        const ValueKey('quick_add_priority_button'),
      );
      final somedayFinder = find.byKey(
        const ValueKey('quick_add_someday_button'),
      );
      final advancedFinder = find.byKey(
        const ValueKey('quick_add_advanced_button'),
      );
      final submitFinder = find.byKey(
        const ValueKey('quick_add_submit_button'),
      );

      expect(
        inputFinder,
        findsOneWidget,
        reason: 'QuickAddBar must render the task input field',
      );
      expect(
        priorityFinder,
        findsOneWidget,
        reason: 'QuickAddBar must render the Priority toggle button',
      );
      expect(
        somedayFinder,
        findsOneWidget,
        reason: 'QuickAddBar must render the Someday toggle button',
      );
      expect(
        advancedFinder,
        findsOneWidget,
        reason: 'QuickAddBar must render the Advanced button',
      );
      expect(
        submitFinder,
        findsOneWidget,
        reason: 'QuickAddBar must render the Add submit button',
      );
      expect(
        find.widgetWithText(ChoiceChip, 'Ready'),
        findsNothing,
        reason: 'Old Ready tier chip must not appear in QuickAddBar',
      );
      expect(
        find.widgetWithText(ChoiceChip, 'Blocked'),
        findsNothing,
        reason: 'Old Blocked tier chip must not appear in QuickAddBar',
      );

      FilledButton submitButton = tester.widget<FilledButton>(submitFinder);
      expect(
        submitButton.onPressed,
        isNull,
        reason: 'Add button must be disabled when input field is empty',
      );

      await tester.enterText(inputFinder, '   ');
      await tester.pump();
      submitButton = tester.widget<FilledButton>(submitFinder);
      expect(
        submitButton.onPressed,
        isNull,
        reason: 'Add button must remain disabled when input is whitespace only',
      );

      ChoiceChip priorityChip = tester.widget<ChoiceChip>(priorityFinder);
      ChoiceChip somedayChip = tester.widget<ChoiceChip>(somedayFinder);
      expect(priorityChip.selected, isFalse);
      expect(somedayChip.selected, isFalse);
      expect(
        priorityChip.backgroundColor,
        equals(const Color(0xFF344FA1)),
        reason: 'Priority chip unselected background must match landing page canvas color',
      );
      expect(
        priorityChip.selectedColor,
        equals(const Color(0xFFEB06FF)),
        reason: 'Priority chip selected color must match landing page magenta accent',
      );
      expect(
        somedayChip.backgroundColor,
        equals(const Color(0xFF344FA1)),
        reason: 'Someday chip unselected background must match landing page canvas color',
      );
      expect(
        somedayChip.selectedColor,
        equals(const Color(0xFF2196F3)),
        reason:
            'Someday chip selected color must match landing page blue accent',
      );

      final inputField = tester.widget<TextField>(inputFinder);
      expect(
        inputField.decoration?.fillColor,
        equals(const Color(0xFF344FA1)),
        reason: 'Task input fill color must match landing page canvas color',
      );
      expect(
        inputField.style?.color,
        equals(Colors.white),
        reason: 'Task input text color must be white on dark navy background',
      );
      expect(
        inputField.decoration?.hintStyle?.color,
        equals(const Color(0xFF9BA8E5)),
        reason:
            'Task input hint color must match landing page muted label color',
      );

      await tester.tap(priorityFinder);
      await tester.pump();
      priorityChip = tester.widget<ChoiceChip>(priorityFinder);
      somedayChip = tester.widget<ChoiceChip>(somedayFinder);
      expect(
        priorityChip.selected,
        isTrue,
        reason: 'Tapping Priority must enable Priority',
      );
      expect(
        somedayChip.selected,
        isFalse,
        reason: 'Someday must remain off when Priority is enabled',
      );

      await tester.tap(somedayFinder);
      await tester.pump();
      priorityChip = tester.widget<ChoiceChip>(priorityFinder);
      somedayChip = tester.widget<ChoiceChip>(somedayFinder);
      expect(
        somedayChip.selected,
        isTrue,
        reason: 'Tapping Someday must enable Someday',
      );
      expect(
        priorityChip.selected,
        isFalse,
        reason: 'Enabling Someday must automatically disable Priority',
      );

      await tester.tap(priorityFinder);
      await tester.pump();
      priorityChip = tester.widget<ChoiceChip>(priorityFinder);
      somedayChip = tester.widget<ChoiceChip>(somedayFinder);
      expect(
        priorityChip.selected,
        isTrue,
        reason: 'Tapping Priority while Someday is active must enable Priority',
      );
      expect(
        somedayChip.selected,
        isFalse,
        reason: 'Enabling Priority must automatically disable Someday',
      );

      await tester.tap(priorityFinder);
      await tester.pump();
      priorityChip = tester.widget<ChoiceChip>(priorityFinder);
      somedayChip = tester.widget<ChoiceChip>(somedayFinder);
      expect(
        priorityChip.selected,
        isFalse,
        reason: 'Tapping active Priority must toggle it off',
      );
      expect(somedayChip.selected, isFalse);

      await tester.tap(somedayFinder);
      await tester.pump();
      await tester.enterText(inputFinder, 'Future idea');
      await tester.pump();

      submitButton = tester.widget<FilledButton>(submitFinder);
      expect(
        submitButton.onPressed,
        isNotNull,
        reason: 'Add button must be enabled when non-empty text is entered',
      );

      await tester.tap(submitFinder);
      await tester.pumpAndSettle();

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
    'QuickAddBar Advanced button opens extended view where subtasks can be defined, removed, and saved',
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

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final inputFinder = find.byKey(const ValueKey('quick_add_input'));
      await tester.enterText(inputFinder, 'Deploy release');
      await tester.tap(find.byKey(const ValueKey('quick_add_priority_button')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('quick_add_advanced_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('Extended Task View'),
        findsOneWidget,
        reason: 'Tapping Advanced must open the extended task creation view',
      );
      expect(
        find.text('Subtasks'),
        findsOneWidget,
        reason: 'Extended view must display the Subtasks section',
      );

      final subtaskInputFinder = find.byKey(
        const ValueKey('quick_add_subtask_input'),
      );
      final subtaskAddFinder = find.byKey(
        const ValueKey('quick_add_subtask_add_button'),
      );
      expect(subtaskInputFinder, findsOneWidget);
      expect(subtaskAddFinder, findsOneWidget);

      final subtaskField = tester.widget<TextField>(subtaskInputFinder);
      expect(
        subtaskField.decoration?.fillColor,
        equals(const Color(0xFF344FA1)),
        reason: 'Subtask input fill color must match landing page canvas color',
      );
      expect(
        subtaskField.style?.color,
        equals(Colors.white),
        reason:
            'Subtask input text color must be white on dark navy background',
      );

      await tester.enterText(subtaskInputFinder, 'Run test suite');
      await tester.pump();
      await tester.tap(subtaskAddFinder);
      await tester.pump();

      await tester.enterText(subtaskInputFinder, 'Draft temporary notes');
      await tester.pump();
      await tester.tap(subtaskAddFinder);
      await tester.pump();

      await tester.enterText(subtaskInputFinder, 'Tag git release');
      await tester.pump();
      await tester.tap(subtaskAddFinder);
      await tester.pump();

      expect(find.text('Run test suite'), findsOneWidget);
      expect(find.text('Draft temporary notes'), findsOneWidget);
      expect(find.text('Tag git release'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('quick_add_remove_subtask_1')),
      );
      await tester.pump();
      expect(
        find.text('Draft temporary notes'),
        findsNothing,
        reason: 'Removing a subtask in extended view must delete it from list',
      );

      await tester.tap(find.byKey(const ValueKey('quick_add_submit_button')));
      await tester.pumpAndSettle();

      final board = container.read(taskNotifierProvider).value!;
      expect(board.focus.length, equals(1));
      final createdTask = board.focus.first;
      expect(createdTask.title, equals('Deploy release'));
      expect(
        createdTask.isPriority,
        isTrue,
        reason: 'Task created with Priority enabled must set isPriority true',
      );
      expect(
        createdTask.subtasks.map((subtask) => subtask.title),
        equals(['Run test suite', 'Tag git release']),
        reason: 'Created task must store the defined subtasks in order',
      );
    },
  );
}
