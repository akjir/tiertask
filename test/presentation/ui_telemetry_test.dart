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
import 'package:tiertask/models/task_board_undo.dart';
import 'package:tiertask/presentation/ui_telemetry.dart';
import 'package:tiertask/services/app_logger.dart';

void main() {
  setUp(() {
    AppLogger.resetForTesting(clock: () => DateTime.utc(2026, 11, 21, 10));
  });

  tearDown(() {
    AppLogger.resetForTesting();
  });

  group('UiTelemetry', () {
    test('performs zero logging when diagnostics are disabled', () {
      expect(AppLogger.isEnabled, isFalse);

      UiTelemetry.logDialogOpened('log_viewer');
      UiTelemetry.logLabelColorPickerOpened('#112233');
      UiTelemetry.logLabelColorSelected('#AABBCC');
      UiTelemetry.logLabelHubOpened('lbl-1');
      UiTelemetry.logLabelNoteCopied(labelId: 'lbl-1', length: 42);
      UiTelemetry.logLocalTdfRenameConfirmed(
        fromFileName: 'tasks.tdf',
        toFileName: 'work.tdf',
      );
      UiTelemetry.logLocalTdfSelectConfirmed('work.tdf');
      UiTelemetry.logScreenOpened('EditLabelsScreen');
      UiTelemetry.logScreenOpened(
        'EditTaskScreen',
        entityKey: 'task',
        entityId: 't-1',
      );
      UiTelemetry.logTaskDetailsToggled(taskId: 't-1', isExpanded: true);
      UiTelemetry.logTaskIdCopied('t-1');
      UiTelemetry.logTaskInfoDialogOpened(
        taskId: 't-1',
        initialIndicatorKeyPrefix: 'due_task_indicator',
      );
      UiTelemetry.logTaskNoteCopied(128);
      UiTelemetry.logUndoShortcut(stackDepth: 2);
      UiTelemetry.logUndoSnackBarAction(
        taskId: 't-1',
        kind: TaskUndoActionKind.complete,
        sequence: 7,
      );
      UiTelemetry.logUndoSnackBarShown(
        taskId: 't-1',
        kind: TaskUndoActionKind.delete,
        sequence: 8,
      );
      UiTelemetry.logWipeTdfConfirmed(
        targetName: 'local',
        fileName: 'tasks.tdf',
        createBackup: true,
      );

      expect(AppLogger.lines, isEmpty);
    });

    test('emits exact redacted UI events when enabled at debug level', () {
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.debug,
        persistToDisk: false,
      );

      UiTelemetry.logDialogOpened('log_viewer');
      UiTelemetry.logLabelColorPickerOpened('#112233');
      UiTelemetry.logLabelColorPickerOpened(null);
      UiTelemetry.logLabelColorSelected('#AABBCC');
      UiTelemetry.logLabelHubOpened('lbl-1');
      UiTelemetry.logLabelNoteCopied(labelId: 'lbl-1', length: 42);
      UiTelemetry.logLocalTdfRenameConfirmed(
        fromFileName: 'tasks.tdf',
        toFileName: 'work.tdf',
      );
      UiTelemetry.logLocalTdfSelectConfirmed('work.tdf');
      UiTelemetry.logScreenOpened('SettingsScreen');
      UiTelemetry.logScreenOpened(
        'EditTaskScreen',
        entityKey: 'task',
        entityId: 't-9',
      );
      UiTelemetry.logTaskDetailsToggled(taskId: 't-9', isExpanded: true);
      UiTelemetry.logTaskIdCopied('t-9');
      UiTelemetry.logTaskInfoDialogOpened(taskId: 't-9');
      UiTelemetry.logTaskInfoDialogOpened(
        taskId: 't-9',
        initialIndicatorKeyPrefix: 'due_task_indicator',
      );
      UiTelemetry.logTaskNoteCopied(99);
      UiTelemetry.logUndoShortcut(stackDepth: 3);
      UiTelemetry.logUndoSnackBarAction(
        taskId: 't-9',
        kind: TaskUndoActionKind.downgrade,
        sequence: 4,
      );
      UiTelemetry.logUndoSnackBarShown(
        taskId: 't-9',
        kind: TaskUndoActionKind.complete,
        sequence: 5,
      );
      UiTelemetry.logWipeTdfConfirmed(
        targetName: 'remote',
        fileName: 'work.tdf',
        createBackup: false,
      );

      final logText = AppLogger.fullLogText;
      const expectedSubstrings = <String>[
        'ui.dialog.open | dialog=log_viewer',
        'Opened LabelColorPickerDialog initialHex=#112233',
        'Opened LabelColorPickerDialog initialHex=',
        'Selected custom label color hex=#AABBCC',
        'ui.label_hub.open | id=lbl-1',
        'label.note.copied | id=lbl-1 length=42',
        'Confirmed rename local TDF dialog from=tasks.tdf to=work.tdf',
        'Confirmed select local TDF dialog file=work.tdf',
        'Opened SettingsScreen',
        'Opened EditTaskScreen task=t-9',
        'Toggled task details task=t-9 expanded=true',
        'task.id.copied | task=t-9',
        'openTaskInfoDialog id=t-9 indicator=summary',
        'openTaskInfoDialog id=t-9 indicator=due_task_indicator',
        'task.note.copied | length=99',
        'ui.undo.shortcut | depth=3',
        'ui.undo.snackbar_action | id=t-9 kind=downgrade seq=4',
        'ui.undo.snackbar_shown | id=t-9 kind=complete seq=5',
        'Confirmed wipe TDF dialog target=remote file=work.tdf createBackup=false',
      ];
      for (final snippet in expectedSubstrings) {
        expect(
          logText,
          contains(snippet),
          reason: 'Expected UiTelemetry log output to contain: $snippet',
        );
      }
    });

    test('respects minimum log level for debug-only toggle events', () {
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.info,
        persistToDisk: false,
      );
      UiTelemetry.logTaskDetailsToggled(taskId: 't-1', isExpanded: false);
      expect(AppLogger.fullLogText, isNot(contains('Toggled task details')));
    });
  });
}
