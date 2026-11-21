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

import '../models/task_board_undo.dart';
import '../services/app_logger.dart';

/// Stateless presentation telemetry facade encapsulating redacted [LogTag.ui] events.
class UiTelemetry {
  /// Prevents instantiation of [UiTelemetry].
  const UiTelemetry._();

  /// Logs opening a conflict or recovery resolution view for [kind].
  static void logConflictViewOpened(String kind) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'ui.resolution_view.open',
      fields: <String, Object?>{'kind': kind},
    );
  }

  /// Logs opening a modal dialog identified by [dialogName].
  static void logDialogOpened(String dialogName) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'ui.dialog.open',
      fields: <String, Object?>{'dialog': dialogName},
    );
  }

  /// Logs cancelling an uncommitted entity draft card of [kind].
  static void logEntityDraftCancelled(String kind) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'ui.entity_draft_cancelled',
      fields: <String, Object?>{'kind': kind},
    );
  }

  /// Logs committing an uncommitted entity draft card of [kind].
  static void logEntityDraftCommitted(String kind) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'ui.entity_draft_committed',
      fields: <String, Object?>{'kind': kind},
    );
  }

  /// Logs opening an uncommitted entity draft card of [kind].
  static void logEntityDraftOpened(String kind) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'ui.entity_draft_opened',
      fields: <String, Object?>{'kind': kind},
    );
  }

  /// Logs unwinding desktop `Escape` layer [layer].
  static void logEscapeUnwound(String layer) {
    if (!AppLogger.shouldLog(LogLevel.debug)) {
      return;
    }
    AppLogger.event(
      LogLevel.debug,
      LogTag.ui,
      'ui.escape_unwound',
      fields: <String, Object?>{'layer': layer},
    );
  }

  /// Logs an inline section edit failure on [kind] [entityId] [section].
  static void logInlineEditFailed({
    required String kind,
    required String entityId,
    required String section,
  }) {
    if (!AppLogger.shouldLog(LogLevel.warn)) {
      return;
    }
    AppLogger.event(
      LogLevel.warn,
      LogTag.ui,
      'ui.inline_edit_failed',
      fields: <String, Object?>{
        'kind': kind,
        'entity_id': entityId,
        'section': section,
      },
    );
  }

  /// Logs opening an inline section editor on [kind] [entityId] [section].
  static void logInlineEditOpened({
    required String kind,
    required String entityId,
    required String section,
  }) {
    if (!AppLogger.shouldLog(LogLevel.debug)) {
      return;
    }
    AppLogger.event(
      LogLevel.debug,
      LogTag.ui,
      'ui.inline_edit_opened',
      fields: <String, Object?>{
        'kind': kind,
        'entity_id': entityId,
        'section': section,
      },
    );
  }

  /// Logs saving an inline section editor on [kind] [entityId] [section].
  static void logInlineEditSaved({
    required String kind,
    required String entityId,
    required String section,
  }) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'ui.inline_edit_saved',
      fields: <String, Object?>{
        'kind': kind,
        'entity_id': entityId,
        'section': section,
      },
    );
  }

  /// Logs opening the label context hub modal for [labelId].
  static void logLabelHubOpened(String labelId) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'ui.label_hub.open',
      fields: <String, Object?>{'id': labelId},
    );
  }

  /// Logs copying a label note to the clipboard using only redacted [labelId] and character [length].
  static void logLabelNoteCopied({
    required String labelId,
    required int length,
  }) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'label.note.copied',
      fields: <String, Object?>{'id': labelId, 'length': length},
    );
  }

  /// Logs confirming a local `.tdf` rename dialog from [fromFileName] to [toFileName].
  static void logLocalTdfRenameConfirmed({
    required String fromFileName,
    required String toFileName,
  }) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.info(
      LogTag.ui,
      'Confirmed rename local TDF dialog from=$fromFileName to=$toFileName',
    );
  }

  /// Logs confirming a local `.tdf` selection dialog with [fileName].
  static void logLocalTdfSelectConfirmed(String fileName) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.info(
      LogTag.ui,
      'Confirmed select local TDF dialog file=$fileName',
    );
  }

  /// Logs unwinding an Android `PopScope` back layer [layer].
  static void logPopScopeUnwound(String layer) {
    if (!AppLogger.shouldLog(LogLevel.debug)) {
      return;
    }
    AppLogger.event(
      LogLevel.debug,
      LogTag.ui,
      'ui.pop_scope_unwound',
      fields: <String, Object?>{'layer': layer},
    );
  }

  /// Logs silently discarding unsaved WebDAV settings edits for [reason].
  static void logSettingsWebDavDraftDiscarded(String reason) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'ui.settings_webdav_draft_discarded',
      fields: <String, Object?>{'reason': reason},
    );
  }

  /// Logs expanding or collapsing inline task details for [taskId] at debug level.
  static void logTaskDetailsToggled({
    required String taskId,
    required bool isExpanded,
  }) {
    if (!AppLogger.shouldLog(LogLevel.debug)) {
      return;
    }
    AppLogger.debug(
      LogTag.ui,
      'Toggled task details task=$taskId expanded=$isExpanded',
    );
  }

  /// Logs copying [taskId] to the system clipboard.
  static void logTaskIdCopied(String taskId) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'task.id.copied',
      fields: <String, Object?>{'task': taskId},
    );
  }

  /// Logs copying a task note to the clipboard using only its redacted character [length].
  static void logTaskNoteCopied(int length) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'task.note.copied',
      fields: <String, Object?>{'length': length},
    );
  }

  /// Logs triggering the desktop `Ctrl+Z` undo shortcut at [stackDepth].
  static void logUndoShortcut({required int stackDepth}) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'ui.undo.shortcut',
      fields: <String, Object?>{'depth': stackDepth},
    );
  }

  /// Logs tapping the floating undo SnackBar action for [taskId], [kind], and [sequence].
  static void logUndoSnackBarAction({
    required String taskId,
    required TaskUndoActionKind kind,
    required int sequence,
  }) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'ui.undo.snackbar_action',
      fields: <String, Object?>{
        'id': taskId,
        'kind': kind.name,
        'seq': sequence,
      },
    );
  }

  /// Logs presenting the floating undo SnackBar for [taskId], [kind], and [sequence].
  static void logUndoSnackBarShown({
    required String taskId,
    required TaskUndoActionKind kind,
    required int sequence,
  }) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'ui.undo.snackbar_shown',
      fields: <String, Object?>{
        'id': taskId,
        'kind': kind.name,
        'seq': sequence,
      },
    );
  }

  /// Logs switching the active shell view from [from] to [to].
  static void logViewChanged({
    required String from,
    required String to,
    required bool viaReturnContext,
  }) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'ui.view_changed',
      fields: <String, Object?>{
        'from': from,
        'to': to,
        'via_return_context': viaReturnContext,
      },
    );
  }

  /// Logs confirming a wipe `.tdf` dialog for [targetName], [fileName], and [createBackup].
  static void logWipeTdfConfirmed({
    required String targetName,
    required String fileName,
    required bool createBackup,
  }) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.info(
      LogTag.ui,
      'Confirmed wipe TDF dialog target=$targetName file=$fileName createBackup=$createBackup',
    );
  }
}
