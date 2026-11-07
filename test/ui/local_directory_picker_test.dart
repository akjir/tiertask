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
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
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
    'SettingsScreen removes direct local file name input, keeps resolved path preview, and renders Select, Move, Rename, and Delete buttons side-by-side',
    (WidgetTester tester) async {
      final initialFilePath =
          '${sourceDir.path}${Platform.pathSeparator}tasks.tdf';
      File(initialFilePath).writeAsStringSync('tdf 0.5.1\n', flush: true);
      File('${sourceDir.path}${Platform.pathSeparator}other.tdf')
          .writeAsStringSync('tdf 0.5.1\n', flush: true);

      final settingsRepository = InMemorySettingsRepository(
        WebDavConfig(
          localFilePath: initialFilePath,
          storageMode: StorageMode.local,
          language: AppLanguage.english,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepository),
            localStorageDirectoryPathProvider.overrideWithValue(sourceDir.path),
            supportsDirectoryPickerProvider.overrideWithValue(false),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();
      await openSettingsFromMenu(tester);

      expect(
        find.text('Local TDF File Name'),
        findsNothing,
        reason: 'Direct text input for Local TDF File Name must be removed',
      );
      expect(
        find.text('Resolved Local File Path:'),
        findsOneWidget,
        reason: 'Resolved path preview label must remain visible',
      );
      expect(
        find.text(initialFilePath),
        findsOneWidget,
        reason: 'Resolved path preview value must remain visible',
      );

      final selectBtn = find.byKey(
        const ValueKey('settings_select_local_button'),
      );
      final moveBtn = find.byKey(const ValueKey('settings_move_local_button'));
      final renameBtn = find.byKey(
        const ValueKey('settings_rename_local_button'),
      );
      final deleteBtn = find.byKey(
        const ValueKey('settings_wipe_local_button'),
      );

      await tester.ensureVisible(selectBtn);
      expect(selectBtn, findsOneWidget);
      expect(moveBtn, findsOneWidget);
      expect(renameBtn, findsOneWidget);
      expect(deleteBtn, findsOneWidget);

      expect(find.text('Select'), findsOneWidget);
      expect(find.text('Move'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      final selectRect = tester.getRect(selectBtn);
      final moveRect = tester.getRect(moveBtn);
      final renameRect = tester.getRect(renameBtn);
      final deleteRect = tester.getRect(deleteBtn);

      expect(
        selectRect.center.dy,
        closeTo(moveRect.center.dy, 1.0),
        reason:
            'Select and Move buttons must be aligned horizontally side-by-side',
      );
      expect(
        moveRect.center.dy,
        closeTo(renameRect.center.dy, 1.0),
        reason:
            'Move and Rename buttons must be aligned horizontally side-by-side',
      );
      expect(
        renameRect.center.dy,
        closeTo(deleteRect.center.dy, 1.0),
        reason: 'Rename and Delete buttons must be aligned horizontally side-by-side',
      );
      expect(
        selectRect.left,
        lessThan(moveRect.left),
        reason: 'Select must appear to the left of Move',
      );
      expect(
        moveRect.left,
        lessThan(renameRect.left),
        reason: 'Move must appear to the left of Rename',
      );
      expect(
        renameRect.left,
        lessThan(deleteRect.left),
        reason: 'Rename must appear to the left of Delete',
      );

      await tester.tap(selectBtn);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('select_local_tdf_dialog')),
        findsOneWidget,
        reason: 'Tapping Select on Android must open SelectLocalTdfDialog',
      );
      expect(find.text('other.tdf'), findsOneWidget);
      await tester.tap(find.text('other.tdf'));
      await tester.tap(
        find.byKey(const ValueKey('select_local_tdf_confirm_button')),
      );
      await tester.pumpAndSettle();

      final expectedOtherPath =
          '${sourceDir.path}${Platform.pathSeparator}other.tdf';
      expect(
        find.text(expectedOtherPath),
        findsOneWidget,
        reason: 'Selecting other.tdf must update resolved path preview',
      );
      expect(
        (await settingsRepository.loadConfig()).localFilePath,
        equals(expectedOtherPath),
      );
    },
  );

  testWidgets(
    'SettingsScreen Select, Move, and Rename buttons work on desktop and handle target conflicts safely',
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
      String? nextPickedFile;

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
            filePickerProvider.overrideWithValue(({
              String? initialDirectory,
              String? currentFileName,
            }) async {
              return nextPickedFile;
            }),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();
      await openSettingsFromMenu(tester);

      final selectButton = find.byKey(
        const ValueKey('settings_select_local_button'),
      );
      final moveButton = find.byKey(
        const ValueKey('settings_move_local_button'),
      );
      final renameButton = find.byKey(
        const ValueKey('settings_rename_local_button'),
      );

      await tester.ensureVisible(moveButton);
      expect(
        moveButton,
        findsOneWidget,
        reason: 'Move button must be visible on Linux and Windows',
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
      await tester.tap(moveButton);
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

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      Link(symlinkConflictPath).deleteSync();

      await tester.tap(moveButton);
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

      await tester.tap(renameButton);
      await tester.pumpAndSettle();

      final renameInput = find.byKey(const ValueKey('rename_local_tdf_input'));
      final renameConfirm = find.byKey(
        const ValueKey('rename_local_tdf_confirm_button'),
      );
      expect(renameInput, findsOneWidget);

      await tester.enterText(renameInput, 'renamed_tasks');
      await tester.pump();
      await tester.tap(renameConfirm);
      await tester.pumpAndSettle();

      final renamedPath =
          '${targetDir.path}${Platform.pathSeparator}renamed_tasks.tdf';
      expect(
        find.text('Local TDF file renamed.'),
        findsOneWidget,
        reason: 'Success banner must appear after renaming TDF file',
      );
      expect(
        find.text(renamedPath),
        findsOneWidget,
        reason:
            'Resolved path preview must show renamed file in same directory',
      );
      expect(
        File(symlinkConflictPath).existsSync(),
        isFalse,
        reason: 'Previous file name must no longer exist after rename',
      );
      expect(
        File(renamedPath).existsSync(),
        isTrue,
        reason: 'Renamed file must exist in the same directory',
      );

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      final newlySelectedPath =
          '${sourceDir.path}${Platform.pathSeparator}brand_new.tdf';
      nextPickedFile = newlySelectedPath;
      await tester.tap(selectButton);
      await tester.pumpAndSettle();

      expect(
        find.text('Local TDF file selected.'),
        findsOneWidget,
        reason:
            'Success banner must appear after selecting or creating TDF file',
      );
      expect(
        find.text(newlySelectedPath),
        findsOneWidget,
        reason: 'Resolved path preview must update to newly selected file',
      );
      expect(
        File(renamedPath).existsSync(),
        isTrue,
        reason: 'Select must not delete or move the previous TDF file',
      );
      expect(
        File(newlySelectedPath).existsSync(),
        isTrue,
        reason: 'Select must initialize the newly selected TDF file on disk',
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
