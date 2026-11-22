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
import 'package:tiertask/providers/ui_telemetry.dart';
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

      UiTelemetry.logConflictViewOpened('deletion');
      UiTelemetry.logDialogOpened('log_viewer');
      UiTelemetry.logEntityDraftCancelled('task');
      UiTelemetry.logEntityDraftCommitted('task');
      UiTelemetry.logEntityDraftOpened('task');
      UiTelemetry.logEscapeUnwound('search');
      UiTelemetry.logInlineEditFailed(
        kind: 'task',
        entityId: 't-1',
        section: 'title',
      );
      UiTelemetry.logInlineEditOpened(
        kind: 'task',
        entityId: 't-1',
        section: 'title',
      );
      UiTelemetry.logInlineEditSaved(
        kind: 'task',
        entityId: 't-1',
        section: 'title',
      );
      UiTelemetry.logLabelHubOpened('lbl-1');
      UiTelemetry.logLabelNoteCopied(labelId: 'lbl-1', length: 42);
      UiTelemetry.logLocalTdfRenameConfirmed(
        fromFileName: 'tasks.tdf',
        toFileName: 'work.tdf',
      );
      UiTelemetry.logLocalTdfSelectConfirmed('work.tdf');
      UiTelemetry.logPopScopeUnwound('drawer');
      UiTelemetry.logSettingsWebDavDraftDiscarded('route_change');
      UiTelemetry.logTaskDetailsToggled(taskId: 't-1', isExpanded: true);
      UiTelemetry.logTaskIdCopied('t-1');
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
      UiTelemetry.logViewChanged(
        from: 'tasks',
        to: 'settings',
        viaReturnContext: false,
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

      UiTelemetry.logConflictViewOpened('recovery');
      UiTelemetry.logDialogOpened('log_viewer');
      UiTelemetry.logEntityDraftCancelled('label');
      UiTelemetry.logEntityDraftCommitted('location');
      UiTelemetry.logEntityDraftOpened('task');
      UiTelemetry.logEscapeUnwound('inline_editor');
      UiTelemetry.logInlineEditFailed(
        kind: 'task',
        entityId: 't-9',
        section: 'due',
      );
      UiTelemetry.logInlineEditOpened(
        kind: 'task',
        entityId: 't-9',
        section: 'due',
      );
      UiTelemetry.logInlineEditSaved(
        kind: 'task',
        entityId: 't-9',
        section: 'due',
      );
      UiTelemetry.logLabelHubOpened('lbl-1');
      UiTelemetry.logLabelNoteCopied(labelId: 'lbl-1', length: 42);
      UiTelemetry.logLocalTdfRenameConfirmed(
        fromFileName: 'tasks.tdf',
        toFileName: 'work.tdf',
      );
      UiTelemetry.logLocalTdfSelectConfirmed('work.tdf');
      UiTelemetry.logPopScopeUnwound('label_picker');
      UiTelemetry.logSettingsWebDavDraftDiscarded('workspace_switch');
      UiTelemetry.logTaskDetailsToggled(taskId: 't-9', isExpanded: true);
      UiTelemetry.logTaskIdCopied('t-9');
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
      UiTelemetry.logViewChanged(
        from: 'labels',
        to: 'tasks',
        viaReturnContext: true,
      );
      UiTelemetry.logWipeTdfConfirmed(
        targetName: 'remote',
        fileName: 'work.tdf',
        createBackup: false,
      );

      final logText = AppLogger.fullLogText;
      const expectedSubstrings = <String>[
        'ui.resolution_view.open | kind=recovery',
        'ui.dialog.open | dialog=log_viewer',
        'ui.entity_draft_cancelled | kind=label',
        'ui.entity_draft_committed | kind=location',
        'ui.entity_draft_opened | kind=task',
        'ui.escape_unwound | layer=inline_editor',
        'ui.inline_edit_failed | kind=task entity_id=t-9 section=due',
        'ui.inline_edit_opened | kind=task entity_id=t-9 section=due',
        'ui.inline_edit_saved | kind=task entity_id=t-9 section=due',
        'ui.label_hub.open | id=lbl-1',
        'label.note.copied | id=lbl-1 length=42',
        'Confirmed rename local TDF dialog from=tasks.tdf to=work.tdf',
        'Confirmed select local TDF dialog file=work.tdf',
        'ui.pop_scope_unwound | layer=label_picker',
        'ui.settings_webdav_draft_discarded | reason=workspace_switch',
        'Toggled task details task=t-9 expanded=true',
        'task.id.copied | task=t-9',
        'task.note.copied | length=99',
        'ui.undo.shortcut | depth=3',
        'ui.undo.snackbar_action | id=t-9 kind=downgrade seq=4',
        'ui.undo.snackbar_shown | id=t-9 kind=complete seq=5',
        'ui.view_changed | from=labels to=tasks via_return_context=true',
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

    test('respects minimum log level for debug-only events', () {
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.info,
        persistToDisk: false,
      );
      UiTelemetry.logTaskDetailsToggled(taskId: 't-1', isExpanded: false);
      UiTelemetry.logEscapeUnwound('search');
      UiTelemetry.logInlineEditOpened(
        kind: 'task',
        entityId: 't-1',
        section: 'note',
      );
      UiTelemetry.logPopScopeUnwound('drawer');
      UiTelemetry.logInlineEditFailed(
        kind: 'task',
        entityId: 't-1',
        section: 'note',
      );

      final logText = AppLogger.fullLogText;
      expect(logText, isNot(contains('Toggled task details')));
      expect(logText, isNot(contains('ui.escape_unwound')));
      expect(logText, isNot(contains('ui.inline_edit_opened')));
      expect(logText, isNot(contains('ui.pop_scope_unwound')));
      expect(
        logText,
        contains(
          'ui.inline_edit_failed | kind=task entity_id=t-1 section=note',
        ),
      );
    });
  });
}
