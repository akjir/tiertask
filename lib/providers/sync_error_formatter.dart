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

import 'package:flutter/foundation.dart';

import '../l10n/app_localizations.dart';
import '../l10n/storage_file_read_localization_extension.dart';
import '../l10n/tier_localization_extension.dart';
import '../models/app_workspace.dart';
import '../models/storage_file_read_status.dart';
import '../models/tdf_error.dart';
import '../models/tdf_sync_metadata.dart';
import '../repositories/local_file_repository.dart';
import '../repositories/webdav_repository.dart';
import '../services/app_logger.dart';

/// Read-only exception contract carrying a [StorageFileReadReport] for localized formatting without creating provider import cycles.
abstract interface class StorageFileReadError implements Exception {
  /// Sanitized fallback summary message when [report] produces empty localized text.
  String get message;

  /// Structured per-target readability diagnostic report.
  StorageFileReadReport get report;
}

/// Centralized stateless formatter mapping synchronization, storage, settings, and TDF domain errors into sanitized localized messages.
@immutable
class SyncErrorFormatter {
  /// Prevents instantiation of [SyncErrorFormatter].
  const SyncErrorFormatter._();

  /// Formats a settings storage, sync, or workspace [error] into a sanitized localized status banner message.
  static String formatSettingsError(
    Object error,
    AppLocalizations localizations,
  ) => _formatKnownError(error, localizations) ?? AppLogger.sanitize('$error');

  /// Formats a sanitized localized message for synchronization or resolution [error], wrapping unknown failures as load or save errors.
  static String formatSyncError(
    Object error,
    AppLocalizations localizations, {
    bool isSave = false,
  }) {
    if (_formatKnownError(error, localizations) case final formatted?) {
      return formatted;
    }
    final details = AppLogger.sanitize('$error');
    return isSave
        ? localizations.errorUnexpectedSave(details)
        : localizations.errorUnexpectedLoad(details);
  }

  /// Maps a [TdfSyncOutcomeException] exhaustively to its localized banner message.
  static String formatSyncOutcomeMessage(
    TdfSyncOutcomeException outcome,
    AppLocalizations localizations,
  ) {
    return switch (outcome.kind) {
      TdfSyncOutcomeKind.deletionConflict =>
        localizations.syncConflictDeletionBanner,
      TdfSyncOutcomeKind.recoveryRequired =>
        localizations.syncConflictRecoveryBanner,
      TdfSyncOutcomeKind.syncGenerationRollback =>
        localizations.syncErrorGenerationRollbackBanner,
    };
  }

  /// Maps a domain [TdfErrorKind] exhaustively into a sanitized localized persistence failure message.
  static String mapTdfExceptionMessage(
    TdfErrorKind kind,
    AppLocalizations localizations,
  ) {
    return switch (kind) {
      TdfErrorKind.circularDependency =>
        localizations.prerequisiteCyclePreventedHint,
      TdfErrorKind.emptyText => localizations.taskNameErrorEmpty,
      TdfErrorKind.invalidColor => localizations.labelColorErrorInvalid,
      TdfErrorKind.invalidCondition => localizations.conditionTimeErrorInvalid,
      TdfErrorKind.invalidNumber => localizations.repeatErrorInvalid,
      TdfErrorKind.invalidUri => localizations.linkErrorInvalid,
      TdfErrorKind.limitExceeded => localizations.errorLocalFileTooLarge,
      TdfErrorKind.unexpectedToken => localizations.schedulingNoteErrorInvalid,
      TdfErrorKind.unknownLocationReference =>
        localizations.conditionLocationErrorInvalid,
      TdfErrorKind.duplicateDirective ||
      TdfErrorKind.duplicateIdentifier ||
      TdfErrorKind.invalidBlockHeader ||
      TdfErrorKind.invalidBoolean ||
      TdfErrorKind.invalidCompletionState ||
      TdfErrorKind.invalidEscapeSequence ||
      TdfErrorKind.invalidIdentifier ||
      TdfErrorKind.invalidQueueMembership ||
      TdfErrorKind.invalidTime ||
      TdfErrorKind.invalidTimestamp ||
      TdfErrorKind.missingDirectiveArgument ||
      TdfErrorKind.missingRequiredDirective ||
      TdfErrorKind.missingVersionHeader ||
      TdfErrorKind.unclosedBlock ||
      TdfErrorKind.unexpectedClosingBrace ||
      TdfErrorKind.unexpectedRootDirective ||
      TdfErrorKind.unknownBlockType ||
      TdfErrorKind.unknownDirective ||
      TdfErrorKind.unknownLabelReference ||
      TdfErrorKind.unsupportedVersion ||
      TdfErrorKind.unterminatedString =>
        localizations.taskSuspendedErrorInvalid,
    };
  }

  /// Formats recognized sync, storage, workspace, and TDF exceptions, or returns `null` for unclassified errors.
  static String? _formatKnownError(
    Object error,
    AppLocalizations localizations,
  ) {
    return switch (error) {
      final TdfSyncOutcomeException outcome => formatSyncOutcomeMessage(
        outcome,
        localizations,
      ),
      final StorageFileReadError fileReadError => _formatStorageFileReadError(
        fileReadError,
        localizations,
      ),
      final LocalFileException localFileError => AppLogger.sanitize(
        localFileError.message,
      ),
      final WebDavException webDavError => AppLogger.sanitize('$webDavError'),
      final WorkspaceException workspaceError =>
        localizations.localizeWorkspaceError(workspaceError),
      final TdfException tdfError => AppLogger.sanitize(tdfError.message),
      _ => null,
    };
  }

  /// Formats a [StorageFileReadError] using its structured [StorageFileReadReport] or sanitized fallback message.
  static String _formatStorageFileReadError(
    StorageFileReadError error,
    AppLocalizations localizations,
  ) {
    final formatted = localizations.formatStorageFileReadMessage(error.report);
    if (formatted.isNotEmpty) {
      return AppLogger.sanitize(formatted);
    }
    return AppLogger.sanitize(error.message);
  }
}
