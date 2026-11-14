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

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/link_launcher_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/ui/widgets/tier_task_pill.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'Tapping a task pill with subtasks animates subtasks downward, shifts subsequent tasks down, toggles subtasks on and off, and collapses on second tap',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 08:05:00
  task 000001OkD2
  task 000002OkD2
}

task 000001OkD2 {
  name "Deploy release candidate"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
  subtasks {
    step false "Prepare backup"
    step false "Verify checksum"
  }
}
task 000002OkD2 {
  name "Update status page"
  created 2026-11-01 08:05
  queued 2026-11-01 08:05
}
''';
      final container = await _pumpSeededApp(tester, seededTdf);

      final step0Finder = _byKey('subtask_step_000001OkD2_0');
      final step1Finder = _byKey('subtask_step_000001OkD2_1');
      final secondTaskPillFinder = _byKey('tier_pill_focus_000002OkD2');

      _expectNone(step0Finder, 'Subtasks must be collapsed initially');
      expect(step1Finder, findsNothing);

      final initialSecondTaskTop = tester.getTopLeft(secondTaskPillFinder).dy;

      await tester.tap(find.text('Deploy release candidate'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));

      final midAnimationSecondTaskTop = tester
          .getTopLeft(secondTaskPillFinder)
          .dy;
      _expectTrue(
        midAnimationSecondTaskTop > initialSecondTaskTop,
        'Downward expansion animation must progressively shift the following task pill downward',
      );

      await tester.pumpAndSettle();

      final expandedSecondTaskTop = tester.getTopLeft(secondTaskPillFinder).dy;
      _expectTrue(
        expandedSecondTaskTop > midAnimationSecondTaskTop,
        'Completed expansion must shift the following task pill to its full offset below the subtasks',
      );
      _expectOne(step0Finder, 'First subtask must be visible when expanded');
      _expectOne(step1Finder, 'Second subtask must be visible when expanded');
      expect(find.text('Prepare backup'), findsOneWidget);
      expect(find.text('Verify checksum'), findsOneWidget);

      await tester.tap(step0Finder);
      await tester.pumpAndSettle();

      var board = container.read(taskNotifierProvider).value!;
      _expectTrue(
        board.findTask('000001OkD2')!.subtasks[0].isCompleted,
        'Tapping an unchecked subtask must mark it as completed',
      );
      expect(
        board.findTask('000001OkD2')!.subtasks[1].isCompleted,
        isFalse,
        reason: 'Other subtasks must remain unchanged',
      );
      _expectOne(
        _byKey('subtasks_task_indicator_000001OkD2'),
        'Subtasks indicator icon must remain visible when a subtask is checked',
      );

      await tester.tap(step1Finder);
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      _expectTrue(
        board
            .findTask('000001OkD2')!
            .subtasks
            .every((step) => step.isCompleted),
        'Tapping the second subtask must mark all subtasks completed',
      );
      _expectOne(
        _byKey('subtasks_task_indicator_000001OkD2'),
        'Subtasks indicator icon must remain visible when all subtasks are checked',
      );

      await tester.tap(step0Finder);
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(
        board.findTask('000001OkD2')!.subtasks[0].isCompleted,
        isFalse,
        reason: 'Tapping a checked subtask again must uncheck it',
      );

      await tester.tap(find.text('Deploy release candidate'));
      await tester.pumpAndSettle();

      _expectNone(
        step0Finder,
        'Tapping the same task again must collapse its subtasks',
      );
      expect(step1Finder, findsNothing);
      expect(
        tester.getTopLeft(secondTaskPillFinder).dy,
        closeTo(initialSecondTaskTop, 0.01),
        reason: 'Collapsing subtasks must shift subsequent tasks back to their initial position',
      );

      await tester.tap(_byKey('complete_task_button_000001OkD2'));
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(
        board.completed.map((task) => task.id),
        equals(['000001OkD2']),
        reason: 'Completing 000001OkD2 must move it to Completed',
      );
      _expectTrue(
        board
            .findTask('000001OkD2')!
            .subtasks
            .every((step) => step.isCompleted),
        'Completing a task with subtasks must mark all subtasks as completed',
      );

      await tester.tap(_byKey('tier_indicator_item_completed'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Deploy release candidate'));
      await tester.pumpAndSettle();

      _expectOne(
        step0Finder,
        'Completed task must still allow viewing its subtasks',
      );
      await tester.tap(step0Finder);
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      _expectTrue(
        board
            .findTask('000001OkD2')!
            .subtasks
            .every((step) => step.isCompleted),
        'Tapping a subtask of a completed task must not unlock or uncheck the subtask',
      );

      await tester.tap(_byKey('complete_task_button_000001OkD2'));
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(
        board.completed,
        isEmpty,
        reason: 'Tapping the completion button in Completed must restore 000001OkD2',
      );
      _expectTrue(
        board
            .findTask('000001OkD2')!
            .subtasks
            .every((step) => !step.isCompleted),
        'Reopening a completed task must reopen all of its subtasks',
      );
    },
  );

  testWidgets(
    'Checking all expanded subtasks on a task with subtasks auto-finish completes the task automatically and differentiates subtask indicator icons and hover tooltips',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 08:05:00
  task auto00OkD2
  task manualOkD2
}

task auto00OkD2 priority {
  name "Auto Finish Checklist Task"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
  repeat 1 weeks
  subtasks auto-finish {
    step false "Final verification step"
    step false "Second step"
  }
}
task manualOkD2 {
  name "Manual Subtasks Task"
  created 2026-11-01 08:05
  queued 2026-11-01 08:05
  subtasks {
    step false "Manual step"
  }
}
''';
      final container = await _pumpSeededApp(tester, seededTdf);

      final autoSubtasksIcon = tester.widget<Icon>(
        _byKey('subtasks_task_indicator_auto00OkD2'),
      );
      final manualSubtasksIcon = tester.widget<Icon>(
        _byKey('subtasks_task_indicator_manualOkD2'),
      );

      expect(
        manualSubtasksIcon.icon,
        equals(Icons.checklist_rounded),
        reason: 'Standard subtasks indicator without auto-finish must use checklist_rounded',
      );
      expect(
        autoSubtasksIcon.icon,
        equals(Icons.fact_check_outlined),
        reason: 'Auto-finish subtasks indicator must use fact_check_outlined to distinguish tasks closed by subtasks',
      );
      expect(
        autoSubtasksIcon.icon,
        isNot(equals(manualSubtasksIcon.icon)),
        reason: 'Subtasks with and without auto-finish must display distinct indicator icons',
      );

      _expectTooltip(tester, 'priority_task_indicator_auto00OkD2', 'Priority');
      _expectTooltip(
        tester,
        'repeat_task_indicator_auto00OkD2',
        'Repeating task',
      );
      _expectTooltip(
        tester,
        'subtasks_task_indicator_auto00OkD2',
        'Subtasks (auto-finish)',
      );
      _expectTooltip(tester, 'subtasks_task_indicator_manualOkD2', 'Subtasks');

      final mouseGesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouseGesture.addPointer(location: Offset.zero);
      addTearDown(mouseGesture.removePointer);

      await mouseGesture.moveTo(
        tester.getCenter(_byKey('repeat_task_indicator_auto00OkD2')),
      );
      await tester.pumpAndSettle();
      _expectOne(
        find.text('Repeating task'),
        'Hovering the mouse over the repeat indicator must display its tooltip',
      );

      await container
          .read(webDavConfigProvider.notifier)
          .updateLanguage(AppLanguage.german);
      await tester.pumpAndSettle();

      _expectTooltip(tester, 'priority_task_indicator_auto00OkD2', 'Priorität');
      _expectTooltip(
        tester,
        'repeat_task_indicator_auto00OkD2',
        'Wiederkehrende Aufgabe',
      );
      _expectTooltip(
        tester,
        'subtasks_task_indicator_auto00OkD2',
        'Unteraufgaben (automatisch abschließen)',
      );
      _expectTooltip(
        tester,
        'subtasks_task_indicator_manualOkD2',
        'Unteraufgaben',
      );

      final firstTaskFinder = _byKey('tier_pill_focus_auto00OkD2');
      final secondTaskFinder = _byKey('tier_pill_focus_manualOkD2');
      final initialFirstTaskTop = tester.getTopLeft(firstTaskFinder).dy;
      final collapsedSecondTaskTop = tester.getTopLeft(secondTaskFinder).dy;

      await tester.tap(find.text('Auto Finish Checklist Task'));
      await tester.pumpAndSettle();

      final expandedSecondTaskTop = tester.getTopLeft(secondTaskFinder).dy;
      expect(expandedSecondTaskTop > collapsedSecondTaskTop, isTrue);

      await tester.tap(_byKey('subtask_step_auto00OkD2_0'));
      await tester.pumpAndSettle();

      await tester.tap(_byKey('subtask_step_auto00OkD2_1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));

      final midSubgroupCollapseTop = tester.getTopLeft(secondTaskFinder).dy;
      _expectTrue(
        midSubgroupCollapseTop < expandedSecondTaskTop &&
            midSubgroupCollapseTop > collapsedSecondTaskTop,
        'Stage 1 of subtask auto-finish must collapse the subtask subgroup first while shifting lower tasks upward',
      );
      _expectOne(
        _byKey('subtask_step_auto00OkD2_1'),
        'Subtask rows must still be visible while the subgroup is collapsing during Stage 1',
      );

      await tester.pump(const Duration(milliseconds: 110));

      _expectNone(
        _byKey('subtask_step_auto00OkD2_0'),
        'Subtask subgroup must be completely closed before Stage 2 task removal starts',
      );
      _expectOne(
        firstTaskFinder,
        'Parent task pill must still be present when Stage 2 task removal begins',
      );
      expect(
        tester.getTopLeft(secondTaskFinder).dy,
        closeTo(collapsedSecondTaskTop, 0.5),
        reason: 'Lower task must reach the collapsed-subgroup offset right as Stage 1 finishes',
      );

      await tester.pump(const Duration(milliseconds: 130));

      final midRemovalSecondTaskTop = tester.getTopLeft(secondTaskFinder).dy;
      _expectTrue(
        midRemovalSecondTaskTop < collapsedSecondTaskTop &&
            midRemovalSecondTaskTop > initialFirstTaskTop,
        'Stage 2 task removal animation must progressively slide lower tasks upward into the removed task slot',
      );

      await tester.pumpAndSettle();

      final board = container.read(taskNotifierProvider).value!;
      expect(
        board.focus.map((task) => task.id),
        equals(['manualOkD2']),
        reason: 'Auto-finished recurring task must leave Focus and reschedule into Blocked when all steps are done',
      );
      expect(
        board.blocked.map((task) => task.id),
        equals(['auto00OkD2']),
        reason: 'Auto-finished recurring task must move to Blocked',
      );
      expect(
        tester.getTopLeft(secondTaskFinder).dy,
        closeTo(initialFirstTaskTop, 0.01),
        reason: 'After task removal completes, the lower task must rest at the exact top position of the removed task',
      );
    },
  );

  testWidgets(
    'Task pill displays passive link indicator, expands link rows on tap, launches URIs via LinkLauncherRepository, and shows SnackBar on launch failure',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 08:00:00
  task lnk001OkD2
}

task lnk001OkD2 {
  name "Review architecture docs"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
  link "Architecture Spec" "https://example.com/arch"
  link "Issue Tracker" "https://example.com/issues/10"
}
''';
      final fakeLauncher = FakeLinkLauncherRepository();
      await _pumpSeededApp(tester, seededTdf, linkLauncher: fakeLauncher);

      final linksIndicatorFinder = _byKey('links_task_indicator_lnk001OkD2');
      _expectOne(
        linksIndicatorFinder,
        'Task with links must display the passive link indicator icon',
      );
      final linksIcon = tester.widget<Icon>(linksIndicatorFinder);
      expect(linksIcon.icon, equals(Icons.link_rounded));

      final link0Finder = _byKey('task_link_lnk001OkD2_0');
      final link1Finder = _byKey('task_link_lnk001OkD2_1');
      _expectNone(link0Finder, 'Task links must be collapsed initially');

      await tester.tap(find.text('Review architecture docs'));
      await tester.pumpAndSettle();

      expect(link0Finder, findsOneWidget);
      expect(link1Finder, findsOneWidget);
      expect(find.text('Architecture Spec'), findsOneWidget);
      expect(find.text('Issue Tracker'), findsOneWidget);

      await tester.tap(link0Finder);
      await tester.pumpAndSettle();
      expect(
        fakeLauncher.launchedUris,
        equals(['https://example.com/arch']),
        reason:
            'Tapping a link row must launch its URI via LinkLauncherRepository',
      );

      fakeLauncher.shouldThrow = true;
      await tester.tap(link1Finder);
      await tester.pumpAndSettle();
      _expectOne(
        find.text('Could not open link.'),
        'Failed link launch must display a localized error SnackBar',
      );
    },
  );

  testWidgets(
    'Task pill displays passive note indicator, expands note-only tasks, and renders expanded note above links and subtasks with leading icon',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 08:10:00
  task all001OkD2
  task not001OkD2
  task plain1OkD2
}

task not001OkD2 {
  name "Note Only Task"
  note "Standalone note content"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
}
task all001OkD2 priority {
  name "Full Details Task"
  note "Top level task note"
  created 2026-11-01 08:05
  queued 2026-11-01 08:05
  repeat 1 days
  link "Design Doc" "https://example.com/design"
  subtasks {
    step false "First checklist item"
  }
}
task plain1OkD2 {
  name "No Note Task"
  created 2026-11-01 08:10
  queued 2026-11-01 08:10
}
''';
      await _pumpSeededApp(tester, seededTdf);

      final noteOnlyIndicatorFinder = _byKey('note_task_indicator_not001OkD2');
      final fullSummaryIndicatorFinder = _byKey(
        'summary_task_indicator_all001OkD2',
      );
      final plainNoteIndicatorFinder = _byKey('note_task_indicator_plain1OkD2');

      _expectOne(
        noteOnlyIndicatorFinder,
        'Task with note must display the passive note indicator icon',
      );
      _expectOne(
        fullSummaryIndicatorFinder,
        'Task with 5 indicators (priority, repeat, note, links, subtasks) must collapse into the single summary indicator icon',
      );
      _expectNone(
        _byKey('note_task_indicator_all001OkD2'),
        'Individual note indicator must be hidden when collapsed into the summary indicator icon',
      );
      _expectNone(
        plainNoteIndicatorFinder,
        'Task without a note must not display the note indicator icon',
      );

      final noteIndicatorIcon = tester.widget<Icon>(noteOnlyIndicatorFinder);
      expect(noteIndicatorIcon.icon, equals(Icons.notes_rounded));
      _expectTooltip(tester, 'note_task_indicator_not001OkD2', 'Note');
      _expectTooltip(
        tester,
        'summary_task_indicator_all001OkD2',
        'Task information (5 indicators)',
      );

      final noteOnlyRowFinder = _byKey('task_note_not001OkD2');
      _expectNone(noteOnlyRowFinder, 'Note row must be collapsed initially');

      await tester.tap(find.text('Note Only Task'));
      await tester.pumpAndSettle();

      _expectOne(
        noteOnlyRowFinder,
        'Tapping a note-only task pill must expand its note row',
      );
      expect(find.text('Standalone note content'), findsOneWidget);
      _expectOne(
        find.descendant(
          of: noteOnlyRowFinder,
          matching: find.byIcon(Icons.notes_rounded),
        ),
        'Expanded note row must display a leading note icon',
      );

      await tester.tap(find.text('Note Only Task'));
      await tester.pumpAndSettle();
      _expectNone(
        noteOnlyRowFinder,
        'Tapping an expanded note-only task pill must collapse it',
      );

      final fullNoteRowFinder = _byKey('task_note_all001OkD2');
      final fullLinkRowFinder = _byKey('task_link_all001OkD2_0');
      final fullSubtaskRowFinder = _byKey('subtask_step_all001OkD2_0');

      await tester.tap(find.text('Full Details Task'));
      await tester.pumpAndSettle();

      expect(fullNoteRowFinder, findsOneWidget);
      expect(fullLinkRowFinder, findsOneWidget);
      expect(fullSubtaskRowFinder, findsOneWidget);

      final noteTop = tester.getTopLeft(fullNoteRowFinder).dy;
      final linkTop = tester.getTopLeft(fullLinkRowFinder).dy;
      final subtaskTop = tester.getTopLeft(fullSubtaskRowFinder).dy;

      _expectTrue(
        noteTop < linkTop,
        'Expanded note row must always be rendered above links',
      );
      _expectTrue(
        linkTop < subtaskTop,
        'Expanded links must always be rendered above subtasks',
      );
    },
  );

  testWidgets(
    'Expanded task note displays a right-aligned copy button that copies the note to the clipboard, shows a localized SnackBar, and keeps the note expanded',
    (WidgetTester tester) async {
      String? copiedClipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            final arguments = methodCall.arguments;
            if (arguments is Map<Object?, Object?>) {
              final text = arguments['text'];
              if (text is String) {
                copiedClipboardText = text;
              }
            }
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      const noteContent =
          'First line of runbook\nSecond line with #hash & "quotes"';
      final taskWithNote = TaskItem(
        id: 'cpy001OkD2',
        title: 'Task With Copyable Note',
        note: noteContent,
      );
      final taskWithoutNote = TaskItem(
        id: 'sub001OkD2',
        title: 'Subtasks Only Task',
        subtasks: const [SubtaskItem(title: 'Step one')],
      );

      await pumpLeafWidget(
        tester,
        Column(
          children: [
            TierTaskPill(
              canDowngrade: true,
              isCompleted: false,
              task: taskWithNote,
            ),
            TierTaskPill(
              canDowngrade: false,
              isCompleted: false,
              task: taskWithoutNote,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final noteRowFinder = _byKey('task_note_cpy001OkD2');
      final copyButtonFinder = _byKey('copy_task_note_cpy001OkD2');
      _expectNone(
        copyButtonFinder,
        'Copy button must not be rendered while the task note is collapsed',
      );

      await tester.tap(find.text('Subtasks Only Task'));
      await tester.pumpAndSettle();
      _expectNone(
        _byKey('copy_task_note_sub001OkD2'),
        'Expanding a task without a note must not render a note copy button',
      );

      await tester.tap(find.text('Task With Copyable Note'));
      await tester.pumpAndSettle();

      _expectOne(
        noteRowFinder,
        'Note row must be rendered when the task is expanded',
      );
      _expectOne(
        copyButtonFinder,
        'Expanded note row must render a copy button',
      );
      _expectOne(
        find.descendant(
          of: copyButtonFinder,
          matching: find.byIcon(Icons.copy_rounded),
        ),
        'Note copy button must display Icons.copy_rounded',
      );

      final copyButtonWidget = tester.widget<IconButton>(copyButtonFinder);
      expect(
        copyButtonWidget.tooltip,
        equals('Copy note'),
        reason: 'English tooltip must describe copying the note',
      );

      final noteTextRight = tester.getTopRight(find.text(noteContent)).dx;
      final copyButtonLeft = tester.getTopLeft(copyButtonFinder).dx;
      final copyButtonCenterX = tester.getCenter(copyButtonFinder).dx;
      final editButtonCenterX = tester
          .getCenter(_byKey('edit_task_button_cpy001OkD2'))
          .dx;

      _expectTrue(
        copyButtonLeft >= noteTextRight,
        'Copy button must be placed on the right side of the expanded note text',
      );
      expect(
        copyButtonCenterX,
        closeTo(editButtonCenterX, 1.0),
        reason: 'Copy button must align horizontally with the trailing action column on the right side of the task pill',
      );

      await tester.tap(copyButtonFinder);
      await tester.pumpAndSettle();

      expect(
        copiedClipboardText,
        equals(noteContent),
        reason: 'Tapping the copy button must copy the exact task note text',
      );
      _expectOne(
        find.text('Note copied to clipboard.'),
        'Copying the task note must display a confirmation SnackBar',
      );
      _expectOne(
        noteRowFinder,
        'Tapping the copy button must keep the task note expanded',
      );
    },
  );

  testWidgets(
    'Expanded task note copy button uses German tooltip and SnackBar strings when German locale is active',
    (WidgetTester tester) async {
      String? copiedClipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            final arguments = methodCall.arguments;
            if (arguments is Map<Object?, Object?>) {
              final text = arguments['text'];
              if (text is String) {
                copiedClipboardText = text;
              }
            }
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      final taskWithNote = TaskItem(
        id: 'deu001OkD2',
        title: 'Aufgabe mit Notiz',
        note: 'Wichtige Notiz',
      );

      await pumpLeafWidget(
        tester,
        TierTaskPill(
          canDowngrade: false,
          isCompleted: false,
          task: taskWithNote,
        ),
        locale: const Locale('de'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Aufgabe mit Notiz'));
      await tester.pumpAndSettle();

      final copyButtonFinder = _byKey('copy_task_note_deu001OkD2');
      final copyButtonWidget = tester.widget<IconButton>(copyButtonFinder);
      expect(
        copyButtonWidget.tooltip,
        equals('Notiz kopieren'),
        reason: 'German tooltip must be localized',
      );

      await tester.tap(copyButtonFinder);
      await tester.pumpAndSettle();

      expect(
        copiedClipboardText,
        equals('Wichtige Notiz'),
        reason: 'German locale copy button must copy the note text',
      );
      _expectOne(
        find.text('Notiz in die Zwischenablage kopiert.'),
        'German confirmation SnackBar must be localized',
      );
    },
  );

  testWidgets(
    'Plain tasks expand on tap to reveal a subtle top-most task ID row, collapse cleanly on second tap or Stage 1 completion, and render above notes, links, and subtasks',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.6.0

queue {
  modified 2026-11-01 08:10:00
  task pln001OkD2
  task ful001OkD2
}

task pln001OkD2 {
  name "Plain Title Only Task"
  created 2026-11-01 08:00
}
task ful001OkD2 {
  name "Full Details With Id Task"
  note "Detailed task note"
  created 2026-11-01 08:05
  link "Spec" "https://example.com/spec"
  subtasks {
    step false "Verify ID row order"
  }
}
''';
      final container = await _pumpSeededApp(tester, seededTdf);

      final plainIdRowFinder = _byKey('task_id_pln001OkD2');
      final plainCopyIdFinder = _byKey('copy_task_id_pln001OkD2');
      final secondPillFinder = _byKey('tier_pill_focus_ful001OkD2');

      _expectNone(
        plainIdRowFinder,
        'Task ID row must not be rendered while a plain task pill is collapsed',
      );
      _expectNone(
        plainCopyIdFinder,
        'Task ID copy button must not be rendered while collapsed',
      );
      _expectNone(
        _byKey('summary_task_indicator_pln001OkD2'),
        'Plain task must not display any passive status indicator icon for its ID',
      );

      final initialSecondTop = tester.getTopLeft(secondPillFinder).dy;

      await tester.tap(find.text('Plain Title Only Task'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));

      final midExpandSecondTop = tester.getTopLeft(secondPillFinder).dy;
      _expectTrue(
        midExpandSecondTop > initialSecondTop,
        'Expanding a plain task pill must smoothly shift lower tasks downward',
      );

      await tester.pumpAndSettle();

      final expandedSecondTop = tester.getTopLeft(secondPillFinder).dy;
      _expectTrue(
        expandedSecondTop > midExpandSecondTop,
        'Settled plain task expansion must reach full downward offset',
      );
      _expectOne(
        plainIdRowFinder,
        'Tapping a plain task pill must expand its task ID row',
      );
      _expectOne(
        plainCopyIdFinder,
        'Expanded plain task pill must render its task ID copy button',
      );
      _expectOne(
        find.text('ID: pln001OkD2'),
        'Expanded task ID row must display the formatted task ID label',
      );
      _expectOne(
        find.descendant(
          of: plainIdRowFinder,
          matching: find.byIcon(Icons.tag_rounded),
        ),
        'Expanded task ID row must render a subtle leading tag icon',
      );

      await tester.tap(find.text('Plain Title Only Task'));
      await tester.pumpAndSettle();

      _expectNone(
        plainIdRowFinder,
        'Tapping an expanded plain task pill a second time must collapse its ID row',
      );
      expect(
        tester.getTopLeft(secondPillFinder).dy,
        closeTo(initialSecondTop, 0.01),
        reason: 'Collapsing a plain task pill must restore subsequent tasks to their exact initial offset',
      );

      await tester.tap(find.text('Plain Title Only Task'));
      await tester.pumpAndSettle();
      _expectOne(plainIdRowFinder, 'Plain task must re-expand before closing');

      await tester.tap(_byKey('complete_task_button_pln001OkD2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      _expectOne(
        plainIdRowFinder,
        'Stage 1 completion of an expanded plain task must animate ID collapse before removal',
      );
      await tester.pumpAndSettle();

      expect(
        container.read(taskNotifierProvider).value!.completed.single.id,
        equals('pln001OkD2'),
        reason: 'Completing expanded plain task must move it to Completed',
      );

      await tester.tap(find.text('Full Details With Id Task'));
      await tester.pumpAndSettle();

      final fullIdRowFinder = _byKey('task_id_ful001OkD2');
      final fullNoteRowFinder = _byKey('task_note_ful001OkD2');
      final fullLinkRowFinder = _byKey('task_link_ful001OkD2_0');
      final fullSubtaskRowFinder = _byKey('subtask_step_ful001OkD2_0');

      _expectOne(fullIdRowFinder, 'Expanded full task must render task ID row');
      final idTop = tester.getTopLeft(fullIdRowFinder).dy;
      final noteTop = tester.getTopLeft(fullNoteRowFinder).dy;
      final linkTop = tester.getTopLeft(fullLinkRowFinder).dy;
      final subtaskTop = tester.getTopLeft(fullSubtaskRowFinder).dy;

      _expectTrue(
        idTop < noteTop,
        'Task ID row must be rendered at the very top above the task note',
      );
      _expectTrue(
        noteTop < linkTop && linkTop < subtaskTop,
        'Note, link, and subtask ordering below the task ID row must remain intact',
      );

      final idTextWidget = tester.widget<Text>(find.text('ID: ful001OkD2'));
      final noteTextWidget = tester.widget<Text>(
        find.text('Detailed task note'),
      );
      final titleTextWidget = tester.widget<Text>(
        find.text('Full Details With Id Task'),
      );
      final idCopyIcon = tester.widget<Icon>(
        find.descendant(
          of: _byKey('copy_task_id_ful001OkD2'),
          matching: find.byIcon(Icons.copy_rounded),
        ),
      );
      final noteCopyIcon = tester.widget<Icon>(
        find.descendant(
          of: _byKey('copy_task_note_ful001OkD2'),
          matching: find.byIcon(Icons.copy_rounded),
        ),
      );

      expect(
        idTextWidget.style!.fontSize!,
        lessThan(noteTextWidget.style!.fontSize!),
        reason: 'Task ID text must use a smaller font size than the task note',
      );
      expect(
        noteTextWidget.style!.fontSize!,
        lessThan(titleTextWidget.style!.fontSize!),
        reason: 'Task note font size must remain smaller than the task title',
      );
      expect(
        idTextWidget.style!.color!.a,
        lessThan(noteTextWidget.style!.color!.a),
        reason: 'Task ID text color must have lower opacity than the task note to stay visually subtle',
      );
      expect(
        idCopyIcon.size!,
        lessThan(noteCopyIcon.size!),
        reason: 'Task ID copy icon must be smaller than the note copy icon',
      );
      expect(
        idCopyIcon.color!.a,
        lessThan(noteCopyIcon.color!.a),
        reason:
            'Task ID copy icon must have lower opacity than the note copy icon',
      );

      await tester.tap(_byKey('tier_indicator_item_completed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plain Title Only Task'));
      await tester.pumpAndSettle();
      _expectOne(
        _byKey('task_id_pln001OkD2'),
        'Completed plain task must still expand on tap to expose its task ID',
      );
    },
  );

  testWidgets(
    'Task ID copy button aligns with the right action column, copies raw task ID in English and German, logs task.id.copied, and handles unmount while Clipboard.setData is suspended',
    (WidgetTester tester) async {
      String? copiedClipboardText;
      Completer<void>? pendingClipboardWrite;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            final arguments = methodCall.arguments;
            if (arguments is Map<Object?, Object?>) {
              final text = arguments['text'];
              if (text is String) {
                copiedClipboardText = text;
              }
            }
            if (pendingClipboardWrite case final completer?) {
              await completer.future;
            }
          }
          return null;
        },
      );
      AppLogger.clear();
      AppLogger.setEnabled(
        true,
        persistToDisk: false,
        minimumLevel: LogLevel.info,
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        AppLogger.setEnabled(false, persistToDisk: false);
        AppLogger.clear();
      });

      final englishTask = TaskItem(id: 'idc001OkD2', title: 'Copyable ID Task');

      await pumpLeafWidget(
        tester,
        TierTaskPill(canDowngrade: true, isCompleted: false, task: englishTask),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Copyable ID Task'));
      await tester.pumpAndSettle();

      final idRowFinder = _byKey('task_id_idc001OkD2');
      final copyIdButtonFinder = _byKey('copy_task_id_idc001OkD2');
      _expectOne(copyIdButtonFinder, 'Expanded task ID copy button must exist');

      final copyIdButtonWidget = tester.widget<IconButton>(copyIdButtonFinder);
      expect(
        copyIdButtonWidget.tooltip,
        equals('Copy task ID'),
        reason: 'English tooltip must describe copying the task ID',
      );

      final idLabelRight = tester.getTopRight(find.text('ID: idc001OkD2')).dx;
      final copyButtonLeft = tester.getTopLeft(copyIdButtonFinder).dx;
      final copyButtonCenterX = tester.getCenter(copyIdButtonFinder).dx;
      final editButtonCenterX = tester
          .getCenter(_byKey('edit_task_button_idc001OkD2'))
          .dx;

      _expectTrue(
        copyButtonLeft >= idLabelRight,
        'Task ID copy button must sit to the right of the ID label text',
      );
      expect(
        copyButtonCenterX,
        closeTo(editButtonCenterX, 1.0),
        reason: 'Task ID copy button must align horizontally with the trailing action column',
      );

      await tester.tap(copyIdButtonFinder);
      await tester.pumpAndSettle();

      expect(
        copiedClipboardText,
        equals('idc001OkD2'),
        reason: 'Copying the task ID must write only the raw 10-character Base62 ID without the ID prefix',
      );
      _expectOne(
        find.text('Task ID copied to clipboard.'),
        'Copying the task ID must display a localized confirmation SnackBar',
      );
      _expectOne(
        idRowFinder,
        'Tapping the task ID copy button must keep the task card expanded',
      );
      expect(
        AppLogger.fullLogText,
        contains('task.id.copied | task=idc001OkD2'),
        reason:
            'Copying a task ID must emit a structured UI diagnostic log event',
      );

      final germanTask = TaskItem(
        id: 'deuId1OkD2',
        title: 'Aufgabe ohne Details',
      );
      await pumpLeafWidget(
        tester,
        TierTaskPill(canDowngrade: false, isCompleted: false, task: germanTask),
        locale: const Locale('de'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Aufgabe ohne Details'));
      await tester.pumpAndSettle();

      final germanCopyButtonFinder = _byKey('copy_task_id_deuId1OkD2');
      final germanCopyWidget = tester.widget<IconButton>(
        germanCopyButtonFinder,
      );
      expect(
        germanCopyWidget.tooltip,
        equals('Aufgaben-ID kopieren'),
        reason: 'German tooltip for copying the task ID must be localized',
      );

      await tester.tap(germanCopyButtonFinder);
      await tester.pumpAndSettle();

      expect(
        copiedClipboardText,
        equals('deuId1OkD2'),
        reason: 'German copy action must copy the raw task ID',
      );
      _expectOne(
        find.text('Aufgaben-ID in die Zwischenablage kopiert.'),
        'German confirmation SnackBar for copying the task ID must be localized',
      );

      pendingClipboardWrite = Completer<void>();
      await tester.tap(germanCopyButtonFinder);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      pendingClipboardWrite.complete();
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Unmounting TierTaskPill while Clipboard.setData is suspended must not throw unmounted BuildContext errors',
      );
    },
  );
}

/// Finds a widget by its string [ValueKey].
Finder _byKey(String key) => find.byKey(ValueKey(key));

/// Asserts that [finder] matches zero widgets with [reason].
void _expectNone(Finder finder, String reason) =>
    expect(finder, findsNothing, reason: reason);

/// Asserts that [finder] matches exactly one widget with [reason].
void _expectOne(Finder finder, String reason) =>
    expect(finder, findsOneWidget, reason: reason);

/// Asserts that the [Tooltip.message] wrapping [key] equals [expected].
void _expectTooltip(WidgetTester tester, String key, String expected) {
  final tooltip = tester.widget<Tooltip>(
    find.ancestor(of: _byKey(key), matching: find.byType(Tooltip)),
  );
  expect(tooltip.message, equals(expected));
}

/// Asserts that [actual] is `true` with [reason].
void _expectTrue(bool actual, String reason) =>
    expect(actual, isTrue, reason: reason);

/// Pumps [TierTaskApp] seeded with [seededTdf] and optional [linkLauncher] at `2026-11-01 12:00` UTC.
Future<ProviderContainer> _pumpSeededApp(
  WidgetTester tester,
  String seededTdf, {
  LinkLauncherRepository? linkLauncher,
}) async {
  const config = WebDavConfig(language: AppLanguage.english);
  final container = ProviderContainer(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(
        InMemorySettingsRepository(config),
      ),
      localFileRepositoryProvider.overrideWith(
        (ref) => FakeLocalFileRepository(config: config, initialTdf: seededTdf),
      ),
      if (linkLauncher != null)
        linkLauncherRepositoryProvider.overrideWithValue(linkLauncher),
      clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1, 12, 0)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const TierTaskApp()),
  );
  await tester.pumpAndSettle();
  return container;
}
