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

  /// Logs opening the custom label color picker dialog with optional [initialHex].
  static void logLabelColorPickerOpened(String? initialHex) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.info(
      LogTag.ui,
      'Opened LabelColorPickerDialog initialHex=${initialHex ?? ''}',
    );
  }

  /// Logs confirming a custom label color [selectedHex] in the color picker dialog.
  static void logLabelColorSelected(String selectedHex) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.info(LogTag.ui, 'Selected custom label color hex=$selectedHex');
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

  /// Logs navigating to [screenName] with optional redacted [entityKey] and [entityId].
  static void logScreenOpened(
    String screenName, {
    String? entityKey,
    String? entityId,
  }) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    final message = (entityKey != null && entityId != null)
        ? 'Opened $screenName $entityKey=$entityId'
        : 'Opened $screenName';
    AppLogger.info(LogTag.ui, message);
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

  /// Logs opening the task info modal for [taskId] and optional [initialIndicatorKeyPrefix].
  static void logTaskInfoDialogOpened({
    required String taskId,
    String? initialIndicatorKeyPrefix,
  }) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.info(
      LogTag.ui,
      'openTaskInfoDialog id=$taskId indicator=${initialIndicatorKeyPrefix ?? "summary"}',
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
