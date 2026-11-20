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

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/models/storage_file_read_status.dart';
import 'package:tiertask/ui/widgets/file_read_status_info.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'FileReadStatusCard displays local-only, remote-only, and dual-storage statuses in English and German',
    (WidgetTester tester) async {
      const localOnlyReport = StorageFileReadReport(
        local: StorageFileReadStatus.unreadable(
          StorageFileTarget.local,
          detail: 'Unclosed block.',
          line: 4,
        ),
      );
      await pumpLeafWidget(
        tester,
        const FileReadStatusCard(report: localOnlyReport),
        locale: const Locale('en'),
      );

      expect(
        find.byKey(const ValueKey('file_read_status_card')),
        findsOneWidget,
      );
      expect(find.text('The local file could not be read.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('file_read_status_row_local')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('file_read_status_row_remote')),
        findsNothing,
      );
      expect(find.text('Local file'), findsOneWidget);
      expect(find.text('Cannot be read'), findsOneWidget);
      expect(
        find.text('Format error (line 4): Unclosed block.'),
        findsOneWidget,
      );

      const dualLocalOkRemoteFail = StorageFileReadReport(
        local: StorageFileReadStatus.readable(StorageFileTarget.local),
        remote: StorageFileReadStatus.unsupportedVersion(
          StorageFileTarget.remote,
          version: '0.9.0',
        ),
      );
      await pumpLeafWidget(
        tester,
        const FileReadStatusCard(report: dualLocalOkRemoteFail),
        locale: const Locale('de'),
      );

      expect(
        find.text(
          'Nur die Remote-Datei konnte nicht gelesen werden. Die lokale Datei ist intakt.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('file_read_status_row_local')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('file_read_status_row_remote')),
        findsOneWidget,
      );
      expect(find.text('Lokale Datei'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Remote-Datei'), findsOneWidget);
      expect(find.text('Nicht lesbar'), findsOneWidget);
      expect(
        find.text('Nicht unterstützte TDF-Version 0.9.0 (erwartet: 0.8.0).'),
        findsOneWidget,
      );

      const dualBothFailed = StorageFileReadReport(
        local: StorageFileReadStatus.unsupportedVersion(
          StorageFileTarget.local,
          version: '0.7.0',
        ),
        remote: StorageFileReadStatus.unreadable(
          StorageFileTarget.remote,
          detail: 'Authentication failed. (HTTP 401)',
        ),
      );
      await pumpLeafWidget(
        tester,
        const FileReadStatusCard(report: dualBothFailed),
        locale: const Locale('en'),
      );

      expect(
        find.text('Both the local and remote files could not be read.'),
        findsOneWidget,
      );
      expect(find.text('Cannot be read'), findsNWidgets(2));
      expect(
        find.text('Unsupported TDF version 0.7.0 (expected 0.8.0).'),
        findsOneWidget,
      );
      expect(find.text('Authentication failed. (HTTP 401)'), findsOneWidget);
    },
  );

  testWidgets(
    'FileReadStatusBannerContent renders compact summary and both active file rows for banners',
    (WidgetTester tester) async {
      const localFailRemoteOk = StorageFileReadReport(
        local: StorageFileReadStatus.unreadable(
          StorageFileTarget.local,
          detail: 'Permission denied',
        ),
        remote: StorageFileReadStatus.readable(StorageFileTarget.remote),
      );

      await pumpLeafWidget(
        tester,
        const FileReadStatusBannerContent(
          report: localFailRemoteOk,
          foregroundColor: Colors.white,
        ),
        locale: const Locale('en'),
      );

      expect(
        find.byKey(const ValueKey('file_read_banner_content')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('file_read_banner_row_local')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('file_read_banner_row_remote')),
        findsOneWidget,
      );
      expect(
        find.text(
          'Only the local file could not be read. The remote file is intact.',
        ),
        findsOneWidget,
      );
      expect(find.text('Local file: Permission denied'), findsOneWidget);
      expect(find.text('Remote file: OK'), findsOneWidget);
    },
  );
}
