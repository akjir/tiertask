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

void main() {
  testWidgets(
    'TierTask UI renders English tier names without Markdown prefixes by default and adds tasks via QuickAddBar',
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

      expect(find.text('TierTask'), findsOneWidget);
      expect(find.text('TierTask (T2)'), findsNothing);
      expect(find.text('Focus & Ready'), findsOneWidget);
      expect(find.text('Focus'), findsWidgets);
      expect(find.text('Ready'), findsWidgets);
      expect(find.text('Planned (Default)'), findsOneWidget);
      expect(find.text('Add new task to Planned...'), findsOneWidget);
      expect(
        find.textContaining('# ['),
        findsNothing,
        reason:
            'UI headings and chips must not display Markdown # [n] prefixes',
      );

      await tester.enterText(find.byType(TextField), 'New Focus Task');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('New Focus Task'), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
    },
  );

  testWidgets(
    'TierTask UI renders German tier names without Markdown prefixes when German language is selected',
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

      expect(find.text('TierTask'), findsOneWidget);
      expect(find.text('TierTask (T2)'), findsNothing);
      expect(find.text('Fokus & Bereit'), findsOneWidget);
      expect(find.text('Fokus'), findsWidgets);
      expect(find.text('Bereit'), findsWidgets);
      expect(find.text('Geplant (Standard)'), findsOneWidget);
      expect(
        find.text('Neue Aufgabe in Geplant hinzufügen...'),
        findsOneWidget,
      );
      expect(find.text('Hinzufügen'), findsOneWidget);
      expect(
        find.textContaining('# ['),
        findsNothing,
        reason: 'German UI headings and chips must not display Markdown # [n] prefixes',
      );
    },
  );

  testWidgets(
    'SettingsScreen switches display language between English and German',
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

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Language'), findsOneWidget);
      await tester.tap(find.text('Deutsch'));
      await tester.pumpAndSettle();

      expect(find.text('Sprache'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Fokus'), findsWidgets);
      expect(find.text('Geplant (Standard)'), findsOneWidget);
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
        appWidget.themeMode,
        equals(ThemeMode.system),
        reason: 'Default themeMode must be ThemeMode.system',
      );

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

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

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

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

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

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
}
