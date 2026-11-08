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
import 'package:tiertask/ui/widgets/wipe_tdf_dialog.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'SettingsScreen wipe local and remote buttons enforce typing file name without .tdf, allow cancelling anytime, and create .bak and .bak.001+ backups when checked',
    (WidgetTester tester) async {
      final tempDir = Directory.systemTemp.createTempSync('tiertask_wipe_ui_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final remoteFiles = <String, String>{
        '/remote.php/dav/files/alice/remote_board.tdf': '''
tdf 0.5.0

queue {
  modified 2026-11-01 08:00:00
  task 000002OkD2
}

task 000002OkD2 {
  name "Remote Task 1"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
}
''',
      };

      final localFile = File('${tempDir.path}/local_board.tdf');
      localFile.writeAsStringSync('''
tdf 0.5.0

queue {
  modified 2026-11-01 08:00:00
  task 000001OkD2
}

task 000001OkD2 {
  name "Local Task 1"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
}
''', flush: true);

      const config = WebDavConfig(
        serverUrl: 'https://cloud.example.com',
        username: 'alice',
        password: 'secret-password',
        filePath: 'remote_board.tdf',
        localFilePath: 'local_board.tdf',
        storageMode: StorageMode.both,
        language: AppLanguage.english,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(config),
            ),
            localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
            webDavRepositoryProvider.overrideWith((ref) {
              final activeConfig =
                  ref.watch(webDavConfigProvider).asData?.value ?? config;
              return FakeWebDavRepository(
                config: activeConfig,
                shouldFail: () => false,
                remoteStore: remoteFiles,
              );
            }),
            clockProvider.overrideWithValue(
              () => DateTime.utc(2026, 11, 1, 12),
            ),
          ],
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();

      await openSettingsFromMenu(tester);

      final wipeLocalButton = find.byKey(
        const ValueKey('settings_wipe_local_button'),
      );
      final wipeRemoteButton = find.byKey(
        const ValueKey('settings_wipe_remote_button'),
      );

      await tester.ensureVisible(wipeLocalButton);
      expect(
        wipeLocalButton,
        findsOneWidget,
        reason: 'Local storage card must render Wipe Local TDF File button',
      );
      await tester.ensureVisible(wipeRemoteButton);
      expect(
        wipeRemoteButton,
        findsOneWidget,
        reason: 'WebDAV storage card must render Wipe Remote TDF File button',
      );

      await tester.ensureVisible(wipeLocalButton);
      await tester.tap(wipeLocalButton);
      await tester.pumpAndSettle();

      final cancelButton = find.byKey(const ValueKey('wipe_tdf_cancel_button'));
      final confirmButton = find.byKey(
        const ValueKey('wipe_tdf_confirm_button'),
      );
      final confirmInput = find.byKey(const ValueKey('wipe_tdf_confirm_input'));
      final backupCheckbox = find.byKey(
        const ValueKey('wipe_tdf_backup_checkbox'),
      );

      expect(cancelButton, findsOneWidget);
      expect(confirmButton, findsOneWidget);
      expect(confirmInput, findsOneWidget);
      expect(backupCheckbox, findsOneWidget);

      expect(
        tester.widget<FilledButton>(confirmButton).onPressed,
        isNull,
        reason: 'Confirm button must be disabled when input is empty',
      );
      expect(
        tester.widget<TextButton>(cancelButton).onPressed,
        isNotNull,
        reason: 'Cancel button must always be enabled',
      );

      await tester.tap(cancelButton);
      await tester.pumpAndSettle();
      expect(
        localFile.readAsStringSync(),
        contains('Local Task 1'),
        reason:
            'Cancelling the wipe dialog must leave the local file untouched',
      );

      await tester.tap(wipeLocalButton);
      await tester.pumpAndSettle();

      await tester.enterText(confirmInput, 'local_board.tdf');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(confirmButton).onPressed,
        isNull,
        reason: 'Confirm button must remain disabled when .tdf extension is included',
      );

      await tester.enterText(confirmInput, 'wrong_name');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(confirmButton).onPressed,
        isNull,
        reason: 'Confirm button must remain disabled when name does not match',
      );

      await tester.enterText(confirmInput, 'local_board');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(confirmButton).onPressed,
        isNotNull,
        reason: 'Confirm button must become enabled once exact file name without .tdf is entered',
      );

      await tester.tap(backupCheckbox);
      await tester.pump();

      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      expect(
        find.text('Local TDF file wiped and re-initialized.'),
        findsOneWidget,
        reason: 'Wiping local file must show confirmation banner',
      );
      expect(
        localFile.readAsStringSync(),
        equals('tdf 0.6.0\n'),
        reason: 'Local file must be emptied to canonical tdf 0.6.0',
      );
      final localBak = File('${tempDir.path}/local_board.tdf.bak');
      expect(
        localBak.existsSync(),
        isTrue,
        reason: 'Checking backup checkbox must create .bak file',
      );
      expect(localBak.readAsStringSync(), contains('Local Task 1'));

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      localFile.writeAsStringSync('second local state', flush: true);
      await tester.ensureVisible(wipeLocalButton);
      await tester.tap(wipeLocalButton);
      await tester.pumpAndSettle();
      await tester.enterText(confirmInput, 'local_board');
      await tester.tap(backupCheckbox);
      await tester.pump();
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      final localBak001 = File('${tempDir.path}/local_board.tdf.bak.001');
      expect(
        localBak001.existsSync(),
        isTrue,
        reason: 'Second backup must create .bak.001 when .bak already exists',
      );
      expect(localBak001.readAsStringSync(), equals('second local state'));

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      await tester.ensureVisible(wipeRemoteButton);
      await tester.tap(wipeRemoteButton);
      await tester.pumpAndSettle();

      expect(
        tester.widget<FilledButton>(confirmButton).onPressed,
        isNull,
        reason: 'Remote confirm button must be disabled initially',
      );
      await tester.enterText(confirmInput, 'remote_board');
      await tester.tap(backupCheckbox);
      await tester.pump();
      expect(tester.widget<FilledButton>(confirmButton).onPressed, isNotNull);
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      expect(
        find.text('Remote TDF file wiped and re-initialized on WebDAV.'),
        findsOneWidget,
        reason: 'Wiping remote file must show confirmation banner',
      );
      expect(
        remoteFiles['/remote.php/dav/files/alice/remote_board.tdf'],
        equals('tdf 0.6.0\n'),
      );
      expect(
        remoteFiles['/remote.php/dav/files/alice/remote_board.tdf.bak'],
        contains('Remote Task 1'),
      );

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'WipeTdfDialog renders German strings and supports toggling backup via label row',
    (tester) async {
      expect(
        const WipeTdfDialogResult(createBackup: true),
        equals(const WipeTdfDialogResult(createBackup: true)),
      );
      expect(
        const WipeTdfDialogResult(createBackup: true).hashCode,
        equals(const WipeTdfDialogResult(createBackup: true).hashCode),
      );
      expect(
        const WipeTdfDialogResult(createBackup: true),
        isNot(equals(const WipeTdfDialogResult(createBackup: false))),
      );

      await pumpLeafWidget(
        tester,
        const WipeTdfDialog(
          target: WipeTdfTarget.local,
          fileName: 'aufgaben.tdf',
          expectedBaseName: 'aufgaben',
        ),
        locale: const Locale('de'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lokale TDF-Datei zurücksetzen'), findsOneWidget);
      expect(
        find.text(
          'Sicherungskopie (.bak / .bak.001+) anlegen, falls Datei vorhanden ist',
        ),
        findsOneWidget,
      );

      final checkboxFinder = find.byKey(
        const ValueKey('wipe_tdf_backup_checkbox'),
      );
      expect(tester.widget<Checkbox>(checkboxFinder).value, isFalse);

      await tester.tap(
        find.text(
          'Sicherungskopie (.bak / .bak.001+) anlegen, falls Datei vorhanden ist',
        ),
      );
      await tester.pump();
      expect(tester.widget<Checkbox>(checkboxFinder).value, isTrue);
    },
  );
}
