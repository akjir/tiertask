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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';

import 'test_helpers.dart';

void main() {
  late Directory sourceDir;
  late Directory targetDir;

  setUp(() {
    sourceDir = Directory.systemTemp.createTempSync('tiertask_ui_src_');
    targetDir = Directory.systemTemp.createTempSync('tiertask_ui_dst_');
  });

  tearDown(() {
    if (sourceDir.existsSync()) {
      sourceDir.deleteSync(recursive: true);
    }
    if (targetDir.existsSync()) {
      targetDir.deleteSync(recursive: true);
    }
  });

  testWidgets(
    'SettingsScreen hides Change Directory button on Android and shows it on desktop (Linux/Windows)',
    (WidgetTester tester) async {
      final settingsRepository = InMemorySettingsRepository(
        const WebDavConfig(language: AppLanguage.english),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepository),
            supportsDirectoryPickerProvider.overrideWithValue(false),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();
      await openSettingsFromMenu(tester);

      expect(
        find.text('Change Directory'),
        findsNothing,
        reason: 'Change Directory button must not be rendered on Android',
      );
    },
  );

  testWidgets(
    'SettingsScreen Change Directory button moves .tdf file on desktop and keeps directory unchanged with detailed error when target has a file, folder, or symlink',
    (WidgetTester tester) async {
      final initialFilePath =
          '${sourceDir.path}${Platform.pathSeparator}tasks.tdf';
      File(initialFilePath).writeAsStringSync(
        'tdf 0.5.0\n\nqueue {\n    modified 2026-11-01 08:00:00\n    task 000001OkD2\n}\n\ntask 000001OkD2 {\n    name "Desktop Task"\n    created 2026-11-01 08:00\n    queued 2026-11-01 08:00\n}\n',
        flush: true,
      );

      final settingsRepository = InMemorySettingsRepository(
        WebDavConfig(
          localFilePath: initialFilePath,
          storageMode: StorageMode.local,
          language: AppLanguage.english,
        ),
      );

      String? nextPickedDirectory;
      String? lastInitialDirectory;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepository),
            supportsDirectoryPickerProvider.overrideWithValue(true),
            directoryPickerProvider.overrideWithValue(({
              String? initialDirectory,
            }) async {
              lastInitialDirectory = initialDirectory;
              return nextPickedDirectory;
            }),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();
      await openSettingsFromMenu(tester);

      final changeDirButton = find.widgetWithText(
        OutlinedButton,
        'Change Directory',
      );
      await tester.ensureVisible(changeDirButton);
      expect(
        changeDirButton,
        findsOneWidget,
        reason: 'Change Directory button must be visible on Linux and Windows',
      );
      expect(
        find.text(initialFilePath),
        findsOneWidget,
        reason: 'Resolved path preview must display initial file path',
      );

      final symlinkConflictPath =
          '${targetDir.path}${Platform.pathSeparator}tasks.tdf';
      Link(symlinkConflictPath)
          .createSync('${targetDir.path}${Platform.pathSeparator}nowhere');

      nextPickedDirectory = targetDir.path;
      await tester.tap(changeDirButton);
      await tester.pumpAndSettle();

      expect(
        lastInitialDirectory,
        equals(sourceDir.path),
        reason:
            'Native picker must receive current directory as initialDirectory',
      );
      expect(
        find.textContaining(
          'A symbolic link already exists at the target path',
        ),
        findsOneWidget,
        reason:
            'Symlink conflict at target path must display exact error banner',
      );
      expect(
        find.text(initialFilePath),
        findsOneWidget,
        reason: 'Resolved path preview must remain unchanged after failed move',
      );
      expect(
        (await settingsRepository.loadConfig()).localFilePath,
        equals(initialFilePath),
        reason:
            'Persisted localFilePath must remain unchanged after failed move',
      );

      Link(symlinkConflictPath).deleteSync();

      await tester.tap(changeDirButton);
      await tester.pumpAndSettle();

      expect(
        find.text('Local TDF directory updated and file moved.'),
        findsOneWidget,
        reason:
            'Success banner must appear after moving TDF file to new directory',
      );
      expect(
        find.text(symlinkConflictPath),
        findsOneWidget,
        reason: 'Resolved path preview must update to new directory path',
      );
      expect(
        (await settingsRepository.loadConfig()).localFilePath,
        equals(symlinkConflictPath),
        reason: 'Persisted localFilePath must update to new directory path',
      );
      expect(
        File(initialFilePath).existsSync(),
        isFalse,
        reason: 'Old TDF file must be moved out of sourceDir',
      );
      expect(
        File(symlinkConflictPath).existsSync(),
        isTrue,
        reason: 'TDF file must exist in targetDir',
      );

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      nextPickedDirectory = null;
      await tester.tap(changeDirButton);
      await tester.pumpAndSettle();

      expect(
        find.text(symlinkConflictPath),
        findsOneWidget,
        reason: 'Cancelling native directory picker must keep current resolved path unchanged',
      );
      expect(
        (await settingsRepository.loadConfig()).localFilePath,
        equals(symlinkConflictPath),
        reason: 'Cancelling native directory picker must keep persisted localFilePath unchanged',
      );
    },
  );

  testWidgets(
    'SettingsScreen keeps Save and Test Connection buttons fixed at bottom like EditTaskScreen and floats status banner above them without scrolling',
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
            supportsDirectoryPickerProvider.overrideWithValue(true),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();
      await openSettingsFromMenu(tester);

      final saveButton = find.widgetWithText(OutlinedButton, 'Save');
      final syncButton = find.widgetWithText(
        FilledButton,
        'Test Connection / Sync Now',
      );
      final scrollView = find.byType(SingleChildScrollView);

      expect(
        find.descendant(of: scrollView, matching: saveButton),
        findsNothing,
        reason: 'Save button must be fixed outside SingleChildScrollView like EditTaskScreen',
      );
      expect(
        find.descendant(of: scrollView, matching: syncButton),
        findsNothing,
        reason: 'Test Connection / Sync Now button must be fixed outside SingleChildScrollView',
      );

      final initialSaveRect = tester.getRect(saveButton);
      final initialSyncRect = tester.getRect(syncButton);

      await tester.drag(scrollView, const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(
        tester.getRect(saveButton),
        equals(initialSaveRect),
        reason: 'Save button must remain at fixed bottom position on scroll',
      );
      expect(
        tester.getRect(syncButton),
        equals(initialSyncRect),
        reason: 'Test Connection / Sync Now button must remain at fixed bottom position on scroll',
      );

      await tester.drag(scrollView, const Offset(0, 300));
      await tester.pumpAndSettle();

      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      final bannerFinder = find.text('Settings saved locally.');
      expect(
        bannerFinder,
        findsOneWidget,
        reason: 'Status banner must be visible when at top of scroll view',
      );
      expect(
        find.descendant(of: scrollView, matching: bannerFinder),
        findsNothing,
        reason: 'Status banner must float outside SingleChildScrollView',
      );

      final bannerRectBeforeScroll = tester.getRect(bannerFinder);
      expect(
        bannerRectBeforeScroll.bottom,
        lessThanOrEqualTo(initialSaveRect.top),
        reason: 'Floating status banner must be positioned above Save button',
      );
      expect(
        tester.getRect(saveButton),
        equals(initialSaveRect),
        reason: 'Floating status banner must not shift Save button position when shown',
      );

      await tester.drag(scrollView, const Offset(0, -250));
      await tester.pump();

      expect(
        tester.getRect(bannerFinder),
        equals(bannerRectBeforeScroll),
        reason: 'Floating status banner must stay at fixed coordinates above action buttons while scrolling',
      );

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
  );
}
