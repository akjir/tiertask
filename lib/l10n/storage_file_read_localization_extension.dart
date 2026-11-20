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

import '../models/storage_file_read_status.dart';
import 'app_localizations.dart';

/// Maps [StorageFileReadReport] and [StorageFileReadStatus] values to localized
/// summaries and per-file readability diagnostics via [AppLocalizations].
extension StorageFileReadLocalizationExtension on AppLocalizations {
  /// Formats a single-line status string (`<target>: <status>`) for [entry].
  String formatStorageFileReadLine(StorageFileReadStatus entry) {
    final targetLabel = storageFileTargetLabel(entry.target);
    final statusText = storageFileReadEntryText(entry);
    return fileReadStatusEntryLine(targetLabel, statusText);
  }

  /// Formats a complete multi-line summary and per-file status message for [report].
  String formatStorageFileReadMessage(StorageFileReadReport report) {
    final buffer = StringBuffer();
    if (report.failureScope case final scope?) {
      buffer.write(storageFileReadSummary(scope));
    }
    for (final entry in report.activeEntries) {
      if (buffer.isNotEmpty) {
        buffer.write('\n');
      }
      buffer.write(formatStorageFileReadLine(entry));
    }
    return buffer.toString();
  }

  /// Returns the localized per-file error reason for [entry], or `null` when [entry] is readable.
  String? storageFileReadEntryReason(StorageFileReadStatus entry) {
    return switch (entry.state) {
      StorageFileReadState.readable => null,
      StorageFileReadState.unsupportedVersion =>
        fileReadReasonUnsupportedVersion(entry.unsupportedVersion ?? '?'),
      StorageFileReadState.unreadable => _formatUnreadableReason(entry),
    };
  }

  /// Returns the localized status text (`OK` or detailed failure reason) for [entry].
  String storageFileReadEntryText(StorageFileReadStatus entry) {
    if (entry.isReadable) {
      return fileReadStatusOk;
    }
    return storageFileReadEntryReason(entry) ?? fileReadStatusUnreadable;
  }

  /// Returns the localized high-level summary sentence for [scope].
  String storageFileReadSummary(StorageReadFailureScope scope) {
    return switch (scope) {
      StorageReadFailureScope.localOnly => fileReadSummaryLocalOnly,
      StorageReadFailureScope.remoteOnly => fileReadSummaryRemoteOnly,
      StorageReadFailureScope.localFailedRemoteOk =>
        fileReadSummaryLocalFailedRemoteOk,
      StorageReadFailureScope.remoteFailedLocalOk =>
        fileReadSummaryRemoteFailedLocalOk,
      StorageReadFailureScope.bothFailed => fileReadSummaryBothFailed,
    };
  }

  /// Returns the localized display name for [target] (`Local file` or `Remote file`).
  String storageFileTargetLabel(StorageFileTarget target) {
    return switch (target) {
      StorageFileTarget.local => fileReadTargetLocal,
      StorageFileTarget.remote => fileReadTargetRemote,
    };
  }

  /// Formats the error reason for an unreadable [entry], distinguishing line-indexed TDF errors from I/O or network details.
  String? _formatUnreadableReason(StorageFileReadStatus entry) {
    final detail = entry.detail?.trim();
    if (entry.line case final line?) {
      final safeDetail = (detail == null || detail.isEmpty)
          ? fileReadStatusUnreadable
          : detail;
      return fileReadReasonTdfFormat(line.toString(), safeDetail);
    }
    if (detail == null || detail.isEmpty) {
      return null;
    }
    return detail;
  }
}
