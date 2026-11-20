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

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/l10n/storage_file_read_localization_extension.dart';
import 'package:tiertask/models/storage_file_read_status.dart';

void main() {
  test('StorageFileReadLocalizationExtension formats all targets, scopes, and failure details in English and German', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final de = lookupAppLocalizations(const Locale('de'));

    expect(
      en.storageFileTargetLabel(StorageFileTarget.local),
      equals('Local file'),
    );
    expect(
      en.storageFileTargetLabel(StorageFileTarget.remote),
      equals('Remote file'),
    );
    expect(
      de.storageFileTargetLabel(StorageFileTarget.local),
      equals('Lokale Datei'),
    );
    expect(
      de.storageFileTargetLabel(StorageFileTarget.remote),
      equals('Remote-Datei'),
    );

    const localOkRemoteUnsupported = StorageFileReadReport(
      local: StorageFileReadStatus.readable(StorageFileTarget.local),
      remote: StorageFileReadStatus.unsupportedVersion(
        StorageFileTarget.remote,
        version: '0.9.0',
      ),
    );
    expect(
      en.formatStorageFileReadMessage(localOkRemoteUnsupported),
      equals(
        'Only the remote file could not be read. The local file is intact.\n'
        'Local file: OK\n'
        'Remote file: Unsupported TDF version 0.9.0 (expected 0.8.0).',
      ),
    );
    expect(
      de.formatStorageFileReadMessage(localOkRemoteUnsupported),
      equals(
        'Nur die Remote-Datei konnte nicht gelesen werden. Die lokale Datei ist intakt.\n'
        'Lokale Datei: OK\n'
        'Remote-Datei: Nicht unterstützte TDF-Version 0.9.0 (erwartet: 0.8.0).',
      ),
    );

    const localFormatErrorRemoteOk = StorageFileReadReport(
      local: StorageFileReadStatus.unreadable(
        StorageFileTarget.local,
        detail: 'Unclosed block.',
        line: 3,
      ),
      remote: StorageFileReadStatus.readable(StorageFileTarget.remote),
    );
    expect(
      en.formatStorageFileReadMessage(localFormatErrorRemoteOk),
      equals(
        'Only the local file could not be read. The remote file is intact.\n'
        'Local file: Format error (line 3): Unclosed block.\n'
        'Remote file: OK',
      ),
    );
    expect(
      de.formatStorageFileReadMessage(localFormatErrorRemoteOk),
      equals(
        'Nur die lokale Datei konnte nicht gelesen werden. Die Remote-Datei ist intakt.\n'
        'Lokale Datei: Formatfehler (Zeile 3): Unclosed block.\n'
        'Remote-Datei: OK',
      ),
    );

    const bothFailedMixed = StorageFileReadReport(
      local: StorageFileReadStatus.unsupportedVersion(
        StorageFileTarget.local,
        version: '0.7.0',
      ),
      remote: StorageFileReadStatus.unreadable(
        StorageFileTarget.remote,
        detail: 'Authentication failed. (HTTP 401)',
      ),
    );
    expect(
      en.formatStorageFileReadMessage(bothFailedMixed),
      equals(
        'Both the local and remote files could not be read.\n'
        'Local file: Unsupported TDF version 0.7.0 (expected 0.8.0).\n'
        'Remote file: Authentication failed. (HTTP 401)',
      ),
    );
    expect(
      de.formatStorageFileReadMessage(bothFailedMixed),
      equals(
        'Die lokale Datei und die Remote-Datei konnten nicht gelesen werden.\n'
        'Lokale Datei: Nicht unterstützte TDF-Version 0.7.0 (erwartet: 0.8.0).\n'
        'Remote-Datei: Authentication failed. (HTTP 401)',
      ),
    );

    const localOnlyUnknownDetail = StorageFileReadReport(
      local: StorageFileReadStatus.unreadable(StorageFileTarget.local),
    );
    expect(
      en.formatStorageFileReadMessage(localOnlyUnknownDetail),
      equals(
        'The local file could not be read.\n'
        'Local file: Cannot be read',
      ),
    );
    expect(
      de.formatStorageFileReadMessage(localOnlyUnknownDetail),
      equals(
        'Die lokale Datei konnte nicht gelesen werden.\n'
        'Lokale Datei: Nicht lesbar',
      ),
    );

    const remoteOnlyFailed = StorageFileReadReport(
      remote: StorageFileReadStatus.unreadable(
        StorageFileTarget.remote,
        detail: 'Connection timed out.',
      ),
    );
    expect(
      en.formatStorageFileReadMessage(remoteOnlyFailed),
      equals(
        'The remote file could not be read.\n'
        'Remote file: Connection timed out.',
      ),
    );
    expect(
      de.formatStorageFileReadMessage(remoteOnlyFailed),
      equals(
        'Die Remote-Datei konnte nicht gelesen werden.\n'
        'Remote-Datei: Connection timed out.',
      ),
    );
  });
}
