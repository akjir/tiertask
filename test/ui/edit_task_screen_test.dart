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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/link_launcher_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/ui/edit_task_screen.dart';

import 'test_helpers.dart';

void main() {
  testWidgets(
    'Right-side task edit button and QuickAddBar Advanced button open the dedicated EditTaskScreen panel enforcing non-empty, non-duplicate names and shared fields',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 08:00:00
  task 000001OkD2
}

label home00OkD2 {
  name "Home"
  color "#00E5FF"
}
label officeOkD2 {
  name "Office"
  color "#FF9100"
}
label cit000OkD2 {
  name "IT"
  color "#2196F3"
}
label cops00OkD2 {
  name "Operations"
  color "#EB06FF"
}
task 000001OkD2 {
  name "Existing Server Audit"
  note "Initial audit note"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
  labels cit000OkD2 officeOkD2
  subtasks {
    step false "Check firewall rules"
  }
}
''';
      final fixedNow = DateTime.utc(2026, 11, 1, 12, 0);
      final container = await _pumpEditorApp(
        tester,
        initialTdf: seededTdf,
        clock: fixedNow,
      );

      final pillFinder = find.byKey(
        const ValueKey('tier_pill_focus_000001OkD2'),
      );
      final taskTitleFinder = find.text('Existing Server Audit');
      final completeButtonFinder = find.byKey(
        const ValueKey('complete_task_button_000001OkD2'),
      );
      final downgradeButtonFinder = find.byKey(
        const ValueKey('downgrade_task_button_000001OkD2'),
      );
      final editButtonFinder = find.byKey(
        const ValueKey('edit_task_button_000001OkD2'),
      );
      expect(pillFinder, findsOneWidget);
      expect(taskTitleFinder, findsOneWidget);
      expect(completeButtonFinder, findsOneWidget);

      final theme = Theme.of(tester.element(pillFinder));
      final squareContainers = tester
          .widgetList<Container>(
            find.descendant(
              of: completeButtonFinder,
              matching: find.byType(Container),
            ),
          )
          .toList();
      expect(squareContainers.length, equals(2));
      final outerDecoration =
          squareContainers.first.decoration as BoxDecoration?;
      final innerDecoration =
          squareContainers.last.decoration as BoxDecoration?;
      expect(
        outerDecoration?.color,
        equals(theme.colorScheme.primaryContainer),
      );
      expect(outerDecoration?.borderRadius, equals(BorderRadius.circular(10)));
      expect(innerDecoration?.shape, equals(BoxShape.circle));
      expect(innerDecoration?.border?.top.color, equals(Colors.white));
      expect(
        find.descendant(
          of: completeButtonFinder,
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsNothing,
      );
      expect(downgradeButtonFinder, findsOneWidget);
      expect(
        find.descendant(
          of: downgradeButtonFinder,
          matching: find.byIcon(Icons.chevron_right_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('edit_task_divider_000001OkD2')),
        findsNothing,
      );
      expect(editButtonFinder, findsOneWidget);
      expect(
        find.descendant(
          of: editButtonFinder,
          matching: find.byIcon(Icons.more_vert_rounded),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(completeButtonFinder).dx <
            tester.getTopLeft(taskTitleFinder).dx,
        isTrue,
      );
      expect(
        tester.getTopLeft(downgradeButtonFinder).dx >
                tester.getTopLeft(taskTitleFinder).dx &&
            tester.getTopRight(downgradeButtonFinder).dx <=
                tester.getTopLeft(editButtonFinder).dx,
        isTrue,
      );

      await tester.tap(taskTitleFinder);
      await tester.pumpAndSettle();
      expect(
        container
            .read(taskNotifierProvider)
            .value!
            .focus
            .map((task) => task.id),
        contains('000001OkD2'),
      );
      expect(find.byKey(const ValueKey('edit_task_screen')), findsNothing);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'quick_add_priority_button', settle: false);
      await _tapKey(tester, 'quick_add_advanced_button');

      final screenFinder = find.byKey(const ValueKey('edit_task_screen'));
      final titleInputFinder = find.byKey(
        const ValueKey('task_editor_title_input'),
      );
      final noteInputFinder = find.byKey(
        const ValueKey('task_editor_note_input'),
      );
      final saveButtonFinder = find.byKey(
        const ValueKey('task_editor_save_button'),
      );

      expect(screenFinder, findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      for (final cardKey in [
        'task_editor_details_card',
        'task_editor_scheduling_card',
        'task_editor_labels_card',
        'task_editor_subtasks_card',
        'task_editor_blocked_card',
        'task_editor_conditions_card',
      ]) {
        expect(
          find.byKey(ValueKey(cardKey)),
          findsOneWidget,
          reason: 'Expected editor card $cardKey to be rendered',
        );
      }
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Extended Task View'),
        ),
        findsOneWidget,
      );
      expect(find.byType(BackButton), findsOneWidget);

      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();
      expect(find.text('Please enter a task name.'), findsOneWidget);
      expect(screenFinder, findsOneWidget);

      await _submitTitleAndExpectError(
        tester,
        titleInputFinder,
        saveButtonFinder,
        '  existing server audit  ',
        'A task with this name already exists.',
      );
      expect(screenFinder, findsOneWidget);

      await tester.enterText(titleInputFinder, 'Rotate SSH Keys');
      await tester.enterText(noteInputFinder, 'Use ed25519 keys');
      await _tapKey(tester, 'task_editor_label_cops00OkD2', settle: false);
      await _tapKey(tester, 'task_editor_label_home00OkD2', settle: false);
      await _tapKey(tester, 'task_editor_auto_finish_toggle', settle: false);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_subtask_input')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_subtask_input')),
        'Generate keypair',
      );
      await tester.pump();
      await _tapKey(tester, 'task_editor_subtask_add_button', settle: false);
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      expect(screenFinder, findsNothing);
      expect(find.byKey(const ValueKey('quick_add_bar')), findsNothing);

      var board = container.read(taskNotifierProvider).value!;
      expect(board.focus.first.title, equals('Rotate SSH Keys'));
      expect(board.focus.first.note, equals('Use ed25519 keys'));
      expect(board.focus.first.labelIds, equals(['home00OkD2', 'cops00OkD2']));
      expect(board.focus.first.subtasksAutoFinish, isTrue);
      expect(
        board.focus.first.subtasks.map((step) => step.title),
        equals(['Generate keypair']),
      );

      await tester.tap(editButtonFinder);
      await tester.pumpAndSettle();

      expect(screenFinder, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Edit Task'),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(titleInputFinder).controller?.text,
        equals('Existing Server Audit'),
      );
      expect(
        tester.widget<TextField>(noteInputFinder).controller?.text,
        equals('Initial audit note'),
      );
      expect(find.text('Check firewall rules'), findsOneWidget);

      await _submitTitleAndExpectError(
        tester,
        titleInputFinder,
        saveButtonFinder,
        '   ',
        'Please enter a task name.',
      );
      await _submitTitleAndExpectError(
        tester,
        titleInputFinder,
        saveButtonFinder,
        'rotate ssh keys',
        'A task with this name already exists.',
      );

      await tester.enterText(titleInputFinder, 'Updated Server Audit');
      await tester.enterText(noteInputFinder, 'Updated audit note');
      await _tapKey(tester, 'task_editor_someday_button', settle: false);
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      expect(screenFinder, findsNothing);

      board = container.read(taskNotifierProvider).value!;
      expect(
        board.someday.map((task) => task.title),
        equals(['Updated Server Audit']),
      );
      expect(board.someday.single.note, equals('Updated audit note'));

      final rotateTaskId = board.focus.single.id;
      await _tapKey(tester, 'complete_task_button_$rotateTaskId');

      board = container.read(taskNotifierProvider).value!;
      expect(board.focus, isEmpty);
      expect(
        board.completed.map((task) => task.title),
        equals(['Rotate SSH Keys']),
      );

      await _tapKey(tester, 'tier_indicator_item_completed');

      expect(
        find.byKey(ValueKey('tier_pill_completed_$rotateTaskId')),
        findsOneWidget,
      );
      final completedButtonFinder = find.byKey(
        ValueKey('complete_task_button_$rotateTaskId'),
      );
      final completedCheckIcon = tester.widget<Icon>(
        find.descendant(
          of: completedButtonFinder,
          matching: find.byIcon(Icons.check_rounded),
        ),
      );
      expect(completedCheckIcon.color, equals(Colors.white));

      await tester.tap(completedButtonFinder);
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(board.completed, isEmpty);
      expect(board.focus.map((task) => task.id), equals([rotateTaskId]));
      expect(board.focus.single.isPriority, isFalse);
      expect(board.queueTaskIds, contains(rotateTaskId));

      await container
          .read(taskNotifierProvider.notifier)
          .completeTask(
            rotateTaskId,
            currentDate: fixedNow.add(const Duration(minutes: 10)),
          );
      await tester.pumpAndSettle();

      await _tapKey(tester, 'edit_task_button_$rotateTaskId');

      expect(screenFinder, findsOneWidget);
      final priorityChip = tester.widget<FilterChip>(
        find.byKey(const ValueKey('task_editor_priority_button')),
      );
      final somedayChip = tester.widget<FilterChip>(
        find.byKey(const ValueKey('task_editor_someday_button')),
      );
      expect(priorityChip.selected, isFalse);
      expect(somedayChip.selected, isFalse);

      await _expectLockedCompletedSubtask(
        tester,
        'task_editor_toggle_subtask_0',
      );

      final subtaskInputFinder = find.byKey(
        const ValueKey('task_editor_subtask_input'),
      );
      await _tapVisible(tester, subtaskInputFinder);
      await tester.enterText(subtaskInputFinder, 'Verify backup key');
      await tester.pumpAndSettle();
      await _tapKey(tester, 'task_editor_subtask_add_button');

      await _expectLockedCompletedSubtask(
        tester,
        'task_editor_toggle_subtask_1',
      );

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_remove_subtask_0')),
      );
      expect(find.text('Generate keypair'), findsNothing);
      expect(find.text('Verify backup key'), findsOneWidget);

      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(board.completed, isEmpty);
      expect(board.focus.single.id, equals(rotateTaskId));
      expect(board.focus.single.isPriority, isFalse);
      expect(
        board.focus.single.subtasks.map((step) => step.title),
        equals(['Verify backup key']),
      );
      expect(board.focus.single.subtasks.single.isCompleted, isFalse);

      await container
          .read(taskNotifierProvider.notifier)
          .completeTask(
            rotateTaskId,
            currentDate: fixedNow.add(const Duration(minutes: 20)),
          );
      await tester.pumpAndSettle();

      await _tapKey(tester, 'edit_task_button_$rotateTaskId');
      await _tapKey(tester, 'task_editor_priority_button', settle: false);
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(board.completed, isEmpty);
      expect(board.focus.single.id, equals(rotateTaskId));
      expect(board.focus.single.isPriority, isTrue);

      await _tapKey(tester, 'tier_indicator_item_focus');

      expect(
        find.byKey(ValueKey('repeat_task_indicator_$rotateTaskId')),
        findsNothing,
      );

      await _tapKey(tester, 'edit_task_button_$rotateTaskId');

      final repeatChipFinder = find.byKey(
        const ValueKey('task_editor_repeat_button'),
      );
      expect(repeatChipFinder, findsOneWidget);
      await tester.tap(repeatChipFinder);
      await tester.pumpAndSettle();

      final repeatCountFinder = find.byKey(
        const ValueKey('task_editor_repeat_count_input'),
      );
      expect(repeatCountFinder, findsOneWidget);
      await tester.enterText(repeatCountFinder, '0');
      await tester.pump();
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      expect(
        find.text('Please enter an interval between 1 and 3650.'),
        findsOneWidget,
      );

      await tester.enterText(repeatCountFinder, '2');
      await _tapKey(tester, 'task_editor_repeat_unit_weeks', settle: false);
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(
        board.focus.single.repeatRule,
        equals(const TaskRepeatRule(count: 2, unit: RepeatUnit.weeks)),
      );
      expect(
        find.byKey(ValueKey('summary_task_indicator_$rotateTaskId')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'EditTaskScreen adds, validates, opens, removes, and saves task links including pending link input on save',
    (WidgetTester tester) async {
      final fakeLauncher = FakeLinkLauncherRepository();
      final container = await _pumpEditorApp(
        tester,
        initialTdf: 'tdf 0.5.0\n\nqueue {\n  modified 2026-11-01 00:00:00\n}\n',
        clock: DateTime.utc(2026, 11, 1, 10, 0),
        linkLauncher: fakeLauncher,
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'quick_add_advanced_button');

      await tester.enterText(
        find.byKey(const ValueKey('task_editor_title_input')),
        'Upgrade Kubernetes cluster',
      );
      await tester.pump();

      final linkTitleFinder = find.byKey(
        const ValueKey('editor_link_title_input'),
      );
      final linkUriFinder = find.byKey(const ValueKey('editor_link_uri_input'));
      final addLinkButtonFinder = find.byKey(
        const ValueKey('editor_add_link_button'),
      );

      await tester.ensureVisible(addLinkButtonFinder);
      await tester.pumpAndSettle();
      await tester.enterText(linkTitleFinder, 'Runbook');
      await tester.enterText(linkUriFinder, 'not-a-valid-uri');
      await tester.pumpAndSettle();
      await _tapVisible(tester, addLinkButtonFinder);

      expect(
        find.byKey(const ValueKey('editor_link_error_text')),
        findsOneWidget,
      );

      await tester.enterText(linkUriFinder, 'https://example.com/k8s-runbook');
      await tester.pumpAndSettle();
      await _tapVisible(tester, addLinkButtonFinder);

      expect(
        find.byKey(const ValueKey('editor_link_error_text')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('editor_link_item_0')), findsOneWidget);

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('editor_open_link_0')),
      );
      expect(
        fakeLauncher.launchedUris,
        equals(['https://example.com/k8s-runbook']),
      );

      await tester.enterText(linkTitleFinder, 'Release Notes');
      await tester.enterText(
        linkUriFinder,
        'https://example.com/k8s-release-notes',
      );
      await tester.pump();

      await _tapKey(tester, 'task_editor_save_button');

      var board = container.read(taskNotifierProvider).value!;
      final createdTask = board.focus.single;
      expect(
        createdTask.links,
        equals(const [
          TaskLink(title: 'Runbook', uri: 'https://example.com/k8s-runbook'),
          TaskLink(
            title: 'Release Notes',
            uri: 'https://example.com/k8s-release-notes',
          ),
        ]),
      );

      await _tapKey(tester, 'edit_task_button_${createdTask.id}');
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('editor_remove_link_0')),
      );
      await _tapKey(tester, 'task_editor_save_button');

      board = container.read(taskNotifierProvider).value!;
      expect(
        board.focus.single.links,
        equals(const [
          TaskLink(
            title: 'Release Notes',
            uri: 'https://example.com/k8s-release-notes',
          ),
        ]),
      );
    },
  );

  testWidgets(
    'EditTaskScreen clears invalid suspended errors on input, enforces pending link and max-link bounds, and shows a SnackBar on link launch failure',
    (WidgetTester tester) async {
      final fakeLauncher = FakeLinkLauncherRepository(shouldThrow: true);
      final initialLinks = [
        for (var i = 0; i < TaskLink.maxLinksPerTask; i++)
          '  link "Doc $i" "https://example.com/doc-$i"',
      ].join('\n');
      await _pumpEditorApp(
        tester,
        initialTdf:
            'tdf 0.5.0\n\nqueue {\n  modified 2026-11-01 00:00:00\n  task 000001OkD2\n}\n\ntask 000001OkD2 {\n  name "Max Links Task"\n  created 2026-11-01 08:00\n  queued 2026-11-01 08:00\n$initialLinks\n}\n',
        clock: DateTime.utc(2026, 11, 1, 10, 0),
        linkLauncher: fakeLauncher,
      );

      await _tapKey(tester, 'edit_task_button_000001OkD2');

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_suspended_button')),
      );
      final suspendedInput = find.byKey(
        const ValueKey('task_editor_suspended_input'),
      );
      await tester.enterText(suspendedInput, 'invalid-date');
      await _tapKey(tester, 'task_editor_save_button');
      const suspendedError =
          'Enter a valid timestamp (YYYY-MM-DD or YYYY-MM-DD HH:MM).';
      expect(find.text(suspendedError), findsOneWidget);

      await tester.enterText(suspendedInput, '2026-12-01');
      await tester.pump();
      expect(find.text(suspendedError), findsNothing);

      final linkTitleFinder = find.byKey(
        const ValueKey('editor_link_title_input'),
      );
      final linkUriFinder = find.byKey(const ValueKey('editor_link_uri_input'));
      await tester.ensureVisible(linkUriFinder);
      await tester.enterText(linkTitleFinder, 'Overflow Link');
      await tester.enterText(linkUriFinder, 'https://example.com/overflow');
      await _tapKey(tester, 'task_editor_save_button');
      expect(
        find.text('Maximum of 20 links per task reached.'),
        findsOneWidget,
      );

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('editor_remove_link_0')),
      );
      await tester.enterText(linkUriFinder, 'invalid-pending-uri');
      await _tapKey(tester, 'task_editor_save_button');
      expect(
        find.text(
          'Enter both a link title and a valid URI with scheme (e.g. https://...).',
        ),
        findsOneWidget,
      );

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('editor_open_link_0')),
      );
      expect(find.text('Could not open link.'), findsOneWidget);
    },
  );

  testWidgets(
    'EditTaskScreen provides explanatory hover tooltips on Priority, Someday, Suspended, Repeat, and Auto-finish chips in English and German',
    (WidgetTester tester) async {
      await pumpLeafWidget(
        tester,
        const EditTaskScreen(),
        locale: const Locale('en'),
      );

      final priorityChip = tester.widget<FilterChip>(
        find.byKey(const ValueKey('task_editor_priority_button')),
      );
      final somedayChip = tester.widget<FilterChip>(
        find.byKey(const ValueKey('task_editor_someday_button')),
      );
      final suspendedChip = tester.widget<FilterChip>(
        find.byKey(const ValueKey('task_editor_suspended_button')),
      );
      final repeatChip = tester.widget<FilterChip>(
        find.byKey(const ValueKey('task_editor_repeat_button')),
      );
      final autoFinishChip = tester.widget<FilterChip>(
        find.byKey(const ValueKey('task_editor_auto_finish_toggle')),
      );

      expect(
        priorityChip.tooltip,
        equals(
          'Marks this task as priority so it is pulled into Focus or Ready ahead of standard tasks.',
        ),
        reason: 'Priority chip must explain priority pull behavior on hover',
      );
      expect(
        somedayChip.tooltip,
        equals(
          'Parks this task in the Someday backlog without pulling it into active tiers.',
        ),
        reason: 'Someday chip must explain Someday backlog behavior on hover',
      );
      expect(
        suspendedChip.tooltip,
        equals(
          'Defers this task to Blocked (optionally until a chosen timestamp) and disables condition evaluation while active.',
        ),
        reason: 'Suspended chip must explain deferral behavior on hover',
      );
      expect(
        repeatChip.tooltip,
        equals(
          'Automatically reschedules this task after the configured interval upon completion and resets all subtasks.',
        ),
        reason: 'Repeat chip must explain recurrence behavior on hover',
      );
      expect(
        autoFinishChip.tooltip,
        equals(
          'Automatically completes the entire task as soon as all subtasks are checked off.',
        ),
        reason: 'Auto-finish chip must explain automatic completion on hover',
      );

      await pumpLeafWidget(
        tester,
        const EditTaskScreen(),
        locale: const Locale('de'),
      );

      expect(
        find.byTooltip(
          'Markiert diese Aufgabe mit Priorität, sodass sie vor regulären Aufgaben in Fokus oder Bereit gezogen wird.',
        ),
        findsOneWidget,
        reason: 'Priority chip must provide German tooltip',
      );
      expect(
        find.byTooltip(
          'Parkt diese Aufgabe im Irgendwann-Backlog, ohne sie in aktive Stufen zu ziehen.',
        ),
        findsOneWidget,
        reason: 'Someday chip must provide German tooltip',
      );
      expect(
        find.byTooltip(
          'Stellt diese Aufgabe unter Blockiert zurück (optional bis zu einem gewählten Zeitpunkt) und deaktiviert währenddessen die Bedingungsauswertung.',
        ),
        findsOneWidget,
        reason: 'Suspended chip must provide German tooltip',
      );
      expect(
        find.byTooltip(
          'Plant diese Aufgabe beim Abschließen automatisch nach dem festgelegten Intervall neu ein und setzt alle Unteraufgaben zurück.',
        ),
        findsOneWidget,
        reason: 'Repeat chip must provide German tooltip',
      );
      expect(
        find.byTooltip(
          'Schließt die gesamte Aufgabe automatisch ab, sobald alle Unteraufgaben abgehakt sind.',
        ),
        findsOneWidget,
        reason: 'Auto-finish chip must provide German tooltip',
      );
    },
  );

  testWidgets(
    'EditTaskScreen supports due date/time input and preserves task origin across edits',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.6.0

queue {
  modified 2026-11-01 08:00
  task 000001OkD2
}

task 000001OkD2 {
  name "Imported Ticket"
  created 2026-11-01 08:00
  origin "jira" "OPS-99"
}
''';
      final fixedNow = DateTime.utc(2026, 11, 1, 12, 0);
      final container = await _pumpEditorApp(
        tester,
        initialTdf: seededTdf,
        clock: fixedNow,
      );

      await _tapKey(tester, 'edit_task_button_000001OkD2');

      final dueChipFinder = find.byKey(
        const ValueKey('task_editor_due_button'),
      );
      expect(dueChipFinder, findsOneWidget);
      await _tapVisible(tester, dueChipFinder);

      final dueInputFinder = find.byKey(
        const ValueKey('task_editor_due_input'),
      );
      expect(dueInputFinder, findsOneWidget);
      await tester.enterText(dueInputFinder, '2026-11-10 15:30');
      await tester.pump();

      await _tapKey(tester, 'task_editor_save_button');

      final board = container.read(taskNotifierProvider).requireValue;
      final updated = board.findTask('000001OkD2')!;
      expect(
        updated.dueAt,
        equals(DateTime.utc(2026, 11, 10, 15, 30)),
        reason: 'Saving a valid due timestamp must store dueAt on the task',
      );
      expect(
        updated.origin,
        equals(const TaskOrigin(namespace: 'jira', externalKey: 'OPS-99')),
        reason: 'Editing a task must preserve its origin attribute',
      );
    },
  );

  testWidgets(
    'EditTaskScreen shows Delete button only when editing an existing task and requires confirmation before deleting in English and German',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.6.0

queue {
  modified 2026-11-01 08:00:00
  task 000001OkD2
  task 000002OkD2
}

task 000001OkD2 {
  name "Audit Firewall"
  created 2026-11-01 08:00
  modified 2026-11-01 08:00
}
task 000002OkD2 {
  name "Rotate Certificates"
  created 2026-11-01 08:05
  modified 2026-11-01 08:05
}
''';
      final fixedNow = DateTime.utc(2026, 11, 1, 12, 0);
      final container = await _pumpEditorApp(
        tester,
        initialTdf: seededTdf,
        clock: fixedNow,
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'quick_add_advanced_button');

      expect(
        find.byKey(const ValueKey('task_editor_delete_button')),
        findsNothing,
        reason: 'Delete button must not be shown when creating a new task',
      );
      await _tapKey(tester, 'task_editor_cancel_button');

      await _tapKey(tester, 'edit_task_button_000001OkD2');

      final deleteButtonFinder = find.byKey(
        const ValueKey('task_editor_delete_button'),
      );
      expect(
        deleteButtonFinder,
        findsOneWidget,
        reason: 'Delete button must be shown when editing an existing task',
      );

      await tester.tap(deleteButtonFinder);
      await tester.pump();

      final dialogFinder = find.byKey(
        const ValueKey('delete_task_confirm_dialog'),
      );
      final confirmButtonFinder = find.byKey(
        const ValueKey('delete_task_confirm_button'),
      );
      expect(
        dialogFinder,
        findsOneWidget,
        reason: 'Tapping Delete must open the confirmation dialog',
      );
      expect(find.text('Delete Task'), findsOneWidget);
      expect(
        find.text(
          'Delete task "Audit Firewall"? This action can be undone while the workspace remains open.',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(confirmButtonFinder).onPressed,
        isNotNull,
        reason:
            'Confirm button must be immediately enabled without a 3s countdown',
      );
      expect(find.text('Delete (3s)'), findsNothing);
      expect(find.text('Delete'), findsWidgets);

      await _tapKey(tester, 'delete_task_cancel_button');
      expect(
        dialogFinder,
        findsNothing,
        reason: 'Cancelling confirmation must close the dialog',
      );
      expect(
        find.byKey(const ValueKey('edit_task_screen')),
        findsOneWidget,
        reason: 'Cancelling confirmation must keep EditTaskScreen open',
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('000001OkD2'),
        isNotNull,
        reason: 'Cancelling confirmation must not delete the task',
      );

      await tester.tap(deleteButtonFinder);
      await tester.pump();
      expect(
        tester.widget<FilledButton>(confirmButtonFinder).onPressed,
        isNotNull,
        reason: 'Re-opened confirmation dialog must have Delete enabled immediately',
      );
      await _tapKey(tester, 'delete_task_confirm_button');

      expect(
        find.byKey(const ValueKey('edit_task_screen')),
        findsNothing,
        reason: 'Confirming deletion must close EditTaskScreen',
      );
      expect(
        find.text('Deleted "Audit Firewall".'),
        findsOneWidget,
        reason: 'Undo SnackBar on HomeScreen must remain visible after EditTaskScreen pops',
      );
      expect(find.text('Undo'), findsOneWidget);
      final boardAfterFirstDelete = container
          .read(taskNotifierProvider)
          .requireValue;
      expect(
        boardAfterFirstDelete.findTask('000001OkD2'),
        isNull,
        reason: 'Confirmed task must be removed from the board',
      );
      expect(
        boardAfterFirstDelete.deletedBlock.findTaskRecord('000001OkD2'),
        isNotNull,
        reason: 'Confirmed task deletion must record a TDF tombstone',
      );

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('000001OkD2'),
        isNotNull,
        reason: 'Tapping Undo on SnackBar must restore the deleted task',
      );

      await container
          .read(webDavConfigProvider.notifier)
          .updateLanguage(AppLanguage.german);
      await tester.pumpAndSettle();

      await _tapKey(tester, 'edit_task_button_000002OkD2');
      await _tapKey(tester, 'task_editor_delete_button', settle: false);
      await tester.pumpAndSettle();

      expect(find.text('Aufgabe löschen'), findsOneWidget);
      expect(
        find.text(
          'Aufgabe „Rotate Certificates“ löschen? Diese Aktion kann rückgängig gemacht werden, solange der Arbeitsbereich geöffnet bleibt.',
        ),
        findsOneWidget,
      );
      expect(find.text('Löschen (3s)'), findsNothing);
      await _tapKey(tester, 'delete_task_confirm_button');

      expect(
        find.text('„Rotate Certificates“ gelöscht.'),
        findsOneWidget,
        reason: 'German Undo SnackBar must be shown on HomeScreen after delete',
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('000002OkD2'),
        isNull,
        reason: 'German confirmation must also delete the task',
      );
      await tester.tap(find.text('Rückgängig'));
      await tester.pumpAndSettle();
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('000002OkD2'),
        isNotNull,
        reason:
            'Tapping German Rückgängig action must restore the deleted task',
      );
    },
  );
}

/// Asserts that the subtask toggle identified by [key] is checked and remains locked when tapped.
Future<void> _expectLockedCompletedSubtask(
  WidgetTester tester,
  String key,
) async {
  final toggleFinder = find.byKey(ValueKey(key));
  final iconFinder = find.descendant(
    of: toggleFinder,
    matching: find.byIcon(Icons.check_circle_rounded),
  );
  expect(iconFinder, findsOneWidget);
  await tester.tap(toggleFinder);
  await tester.pumpAndSettle();
  expect(iconFinder, findsOneWidget);
}

/// Pumps [TierTaskApp] inside an [UncontrolledProviderScope] for task editor tests.
Future<ProviderContainer> _pumpEditorApp(
  WidgetTester tester, {
  required String initialTdf,
  required DateTime clock,
  LinkLauncherRepository? linkLauncher,
}) async {
  const config = WebDavConfig(language: AppLanguage.english);
  final container = ProviderContainer(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(
        InMemorySettingsRepository(config),
      ),
      localFileRepositoryProvider.overrideWith(
        (ref) =>
            FakeLocalFileRepository(config: config, initialTdf: initialTdf),
      ),
      if (linkLauncher != null)
        linkLauncherRepositoryProvider.overrideWithValue(linkLauncher),
      clockProvider.overrideWithValue(() => clock),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const TierTaskApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Enters [title] into [titleFinder], taps [saveFinder], and asserts [errorText] is visible.
Future<void> _submitTitleAndExpectError(
  WidgetTester tester,
  Finder titleFinder,
  Finder saveFinder,
  String title,
  String errorText,
) async {
  await tester.enterText(titleFinder, title);
  await tester.pump();
  await tester.tap(saveFinder);
  await tester.pumpAndSettle();
  expect(find.text(errorText), findsOneWidget);
}

/// Taps the widget with [ValueKey] [key] and pumps or settles.
Future<void> _tapKey(
  WidgetTester tester,
  String key, {
  bool settle = true,
}) async {
  await tester.tap(find.byKey(ValueKey(key)));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// Scrolls [finder] into view, taps it, and settles animations.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
