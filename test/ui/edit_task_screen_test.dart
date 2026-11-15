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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/link_launcher_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/services/tdf_service.dart';
import 'package:tiertask/ui/edit_task_screen.dart';
import 'package:tiertask/ui/widgets/task_editor_scheduling_card.dart';

import 'test_helpers.dart';

class _SuspendingLocalFileRepository extends FakeLocalFileRepository {
  _SuspendingLocalFileRepository({
    required super.config,
    required super.initialTdf,
  });

  Completer<void>? saveGate;

  @override
  Future<void> saveTdf(String tdfContent) async {
    if (saveGate case final gate?) {
      await gate.future;
    }
    await super.saveTdf(tdfContent);
  }
}

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

  testWidgets(
    'EditTaskScreen unchecks expired suspended on open, clears dead deferral on save, and preserves 0.7.0 fields',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.7.0

queue {
  modified 2026-11-01 08:00:00
  task expSusp001
  task actSusp002
  task forSusp003
}

task expSusp001 {
  name "Expired Deferral Task"
  created 2026-11-01 08:00
  repeat 2 weeks 09:30 lead 3 days
  suspended 2026-11-01 11:00:00 "Morning freeze"
  due 2026-11-10 15:30:00 passive "Soft customer target"
  history 2026-10-25 08:15:00 "Initial triage note"
  history 2026-10-28 14:00:00 "Escalated to SRE"
}

task actSusp002 {
  name "Active Deferral Task"
  created 2026-11-01 08:05
  suspended 2026-11-05 09:00:00 "Waiting on vendor"
  due 2026-11-12 18:00:00 passive "Board review target"
}

task forSusp003 {
  name "Forever Deferral Task"
  created 2026-11-01 08:06
  suspended forever "Wait on budget"
}
''';
      var currentClock = DateTime.utc(2026, 11, 1, 10, 0);
      const config = WebDavConfig(language: AppLanguage.english);
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(config),
          ),
          localFileRepositoryProvider.overrideWith(
            (ref) =>
                FakeLocalFileRepository(config: config, initialTdf: seededTdf),
          ),
          clockProvider.overrideWith(
            (ref) =>
                () => currentClock,
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('expSusp001')
            ?.suspendedAt,
        equals(DateTime.utc(2026, 11, 1, 11, 0)),
        reason: 'At 10:00 UTC load, 11:00 UTC deferral remains present on task',
      );

      currentClock = DateTime.utc(2026, 11, 1, 12, 0);
      container.invalidate(clockProvider);
      await tester.pumpAndSettle();

      await _tapKey(tester, 'tier_indicator_item_blocked');
      if (find
          .byKey(const ValueKey('edit_task_button_expSusp001'))
          .evaluate()
          .isEmpty) {
        await _tapKey(tester, 'tier_indicator_item_focus');
      }
      await _tapKey(tester, 'edit_task_button_expSusp001');

      final suspendedChip = tester.widget<FilterChip>(
        find.byKey(const ValueKey('task_editor_suspended_button')),
      );
      expect(
        suspendedChip.selected,
        isFalse,
        reason: 'Expired finite suspendedAt <= nowUtc must initialize Suspended unchecked',
      );
      expect(
        find.byKey(const ValueKey('task_editor_suspended_input')),
        findsNothing,
        reason:
            'Suspended input must be hidden when expired deferral is unchecked',
      );

      await tester.enterText(
        find.byKey(const ValueKey('task_editor_repeat_count_input')),
        '3',
      );
      await tester.pump();
      await _tapKey(tester, 'task_editor_save_button');

      var board = container.read(taskNotifierProvider).requireValue;
      var expTask = board.findTask('expSusp001')!;
      expect(
        expTask.suspendedAt,
        isNull,
        reason:
            'Saving must not re-persist an already-expired suspended timestamp',
      );
      expect(expTask.isSuspendedForever, isFalse);
      expect(
        expTask.suspendedNote,
        isNull,
        reason:
            'Expired deferral note must be cleared when Suspended is unchecked',
      );
      expect(
        expTask.history,
        equals([
          TaskHistoryEntry(
            timestampUtc: DateTime.utc(2026, 10, 25, 8, 15),
            text: 'Initial triage note',
          ),
          TaskHistoryEntry(
            timestampUtc: DateTime.utc(2026, 10, 28, 14, 0),
            text: 'Escalated to SRE',
          ),
        ]),
        reason:
            'Editing a task must preserve existing history entries untouched',
      );
      expect(
        expTask.repeatRule,
        equals(
          const TaskRepeatRule(
            count: 3,
            unit: RepeatUnit.weeks,
            clock: TdfRepeatClock(hour: 9, minute: 30),
            leadDays: 3,
          ),
        ),
        reason: 'Editing repeat interval must preserve existing leadDays and repeat clock',
      );
      expect(expTask.dueAt, equals(DateTime.utc(2026, 11, 10, 15, 30)));
      expect(
        expTask.isDuePassive,
        isTrue,
        reason: 'Keeping the same due timestamp must preserve isDuePassive',
      );
      expect(
        expTask.dueNote,
        equals('Soft customer target'),
        reason: 'Keeping due enabled must preserve dueNote',
      );

      await _tapKey(tester, 'edit_task_button_expSusp001');
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_due_input')),
        '2026-11-11 16:00',
      );
      await tester.pump();
      await _tapKey(tester, 'task_editor_save_button');

      board = container.read(taskNotifierProvider).requireValue;
      expTask = board.findTask('expSusp001')!;
      expect(expTask.dueAt, equals(DateTime.utc(2026, 11, 11, 16, 0)));
      expect(
        expTask.isDuePassive,
        isFalse,
        reason: 'Changing due to a different timestamp must reset isDuePassive to false',
      );
      expect(
        expTask.dueNote,
        equals('Soft customer target'),
        reason: 'Changing due while keeping due enabled must preserve dueNote',
      );

      await _tapKey(tester, 'edit_task_button_expSusp001');
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_due_button')),
      );
      await _tapKey(tester, 'task_editor_save_button');

      board = container.read(taskNotifierProvider).requireValue;
      expTask = board.findTask('expSusp001')!;
      expect(expTask.dueAt, isNull);
      expect(expTask.isDuePassive, isFalse);
      expect(
        expTask.dueNote,
        isNull,
        reason: 'Disabling due must clear dueNote',
      );

      await _tapKey(tester, 'tier_indicator_item_blocked');
      await _tapKey(tester, 'edit_task_button_actSusp002');

      final activeSuspendedChip = tester.widget<FilterChip>(
        find.byKey(const ValueKey('task_editor_suspended_button')),
      );
      expect(
        activeSuspendedChip.selected,
        isTrue,
        reason: 'Future suspendedAt > nowUtc must initialize Suspended checked',
      );
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_note_input')),
        'Updated context note',
      );
      await tester.pump();
      await _tapKey(tester, 'task_editor_save_button');

      board = container.read(taskNotifierProvider).requireValue;
      var actTask = board.findTask('actSusp002')!;
      expect(actTask.suspendedAt, equals(DateTime.utc(2026, 11, 5, 9, 0)));
      expect(
        actTask.suspendedNote,
        equals('Waiting on vendor'),
        reason:
            'Keeping Suspended enabled must preserve existing suspendedNote',
      );

      await _tapKey(tester, 'edit_task_button_actSusp002');
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_suspended_button')),
      );
      await _tapKey(tester, 'task_editor_save_button');

      board = container.read(taskNotifierProvider).requireValue;
      actTask = board.findTask('actSusp002')!;
      expect(actTask.suspendedAt, isNull);
      expect(
        actTask.suspendedNote,
        isNull,
        reason: 'Disabling Suspended must clear suspendedNote',
      );

      await _tapKey(tester, 'edit_task_button_forSusp003');
      final foreverSuspendedChip = tester.widget<FilterChip>(
        find.byKey(const ValueKey('task_editor_suspended_button')),
      );
      expect(
        foreverSuspendedChip.selected,
        isTrue,
        reason: 'suspended forever must initialize Suspended checked',
      );
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_note_input')),
        'Budget review Q1',
      );
      await tester.pump();
      await _tapKey(tester, 'task_editor_save_button');

      board = container.read(taskNotifierProvider).requireValue;
      final foreverTask = board.findTask('forSusp003')!;
      expect(foreverTask.isSuspendedForever, isTrue);
      expect(foreverTask.suspendedAt, isNull);
      expect(
        foreverTask.suspendedNote,
        equals('Wait on budget'),
        reason:
            'Keeping indefinite suspension enabled must preserve suspendedNote',
      );
    },
  );

  testWidgets(
    'EditTaskScreen manages task_editor_due_auto_prioritize_switch across new, passive, seconds/9999-12-31, Priority/due auto-resets, manual overrides, and completed tasks',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.7.0

queue {
  modified 2026-11-01 08:00:00
  task passSec001
  task maxDue0002
}

task passSec001 {
  name "Passive Subminute Task"
  created 2026-11-01 08:00:00
  modified 2026-11-01 08:00:00
  due 2026-11-10 14:30:45 passive "Keep note"
}

task maxDue0002 {
  name "Max Horizon Due Task"
  created 2026-11-01 08:00:00
  modified 2026-11-01 08:00:00
  due 9999-12-31 23:59:59 passive
}

task doneDue003 {
  name "Completed With Due"
  created 2026-10-25 08:00:00
  modified 2026-10-29 12:00:00
  finished 2026-10-29 12:00:00
  completions 1
  due 2026-10-30 12:00:00 passive
}
''';
      final container = await _pumpEditorApp(
        tester,
        initialTdf: seededTdf,
        clock: DateTime.utc(2026, 11, 1, 12),
      );
      final switchFinder = find.byKey(
        const ValueKey('task_editor_due_auto_prioritize_switch'),
      );

      // 1. New task via QuickAdd -> Advanced: hidden until Due is enabled, honors manual off on addTask.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'quick_add_advanced_button');
      expect(
        switchFinder,
        findsNothing,
        reason: 'Auto-prioritize switch must hide when Due is disabled',
      );

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_due_button')),
      );
      expect(switchFinder, findsOneWidget);
      expect(tester.widget<Switch>(switchFinder).value, isTrue);

      await _tapVisible(tester, switchFinder);
      expect(tester.widget<Switch>(switchFinder).value, isFalse);

      // Edit dueAt AFTER manual toggle -> manual choice (false) must stick!
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_due_input')),
        '2026-11-05 18:00',
      );
      await tester.pump();
      expect(
        tester.widget<Switch>(switchFinder).value,
        isFalse,
        reason: 'Manual switch override must not be clobbered by editing dueAt',
      );

      // Toggle Due off and back on -> resets autoPrioritizeDue to true.
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_due_button')),
      );
      expect(switchFinder, findsNothing);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_due_button')),
      );
      expect(tester.widget<Switch>(switchFinder).value, isTrue);
      await _tapVisible(tester, switchFinder);
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_due_input')),
        '2026-11-05 18:00',
      );
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_title_input')),
        'Informational Milestone',
      );
      await tester.pump();
      await _tapKey(tester, 'task_editor_save_button');

      var board = container.read(taskNotifierProvider).requireValue;
      final addedTask = board.allTasks.singleWhere(
        (task) => task.title == 'Informational Milestone',
      );
      expect(addedTask.dueAt, equals(DateTime.utc(2026, 11, 5, 18)));
      expect(
        addedTask.isDuePassive,
        isTrue,
        reason: 'addTask must honor manual auto-prioritize switch off',
      );

      // 2. Open passive task with sub-minute :45 seconds: initializes false and preserves :45 + passive when due untouched.
      await _tapKey(tester, 'edit_task_button_passSec001');
      expect(switchFinder, findsOneWidget);
      expect(tester.widget<Switch>(switchFinder).value, isFalse);
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_note_input')),
        'Touched note only',
      );
      await tester.pump();
      await _tapKey(tester, 'task_editor_save_button');

      board = container.read(taskNotifierProvider).requireValue;
      var passSecTask = board.findTask('passSec001')!;
      expect(
        passSecTask.dueAt,
        equals(DateTime.utc(2026, 11, 10, 14, 30, 45)),
        reason: 'Untouched due input must preserve sub-minute :SS seconds',
      );
      expect(passSecTask.isDuePassive, isTrue);
      expect(passSecTask.dueNote, equals('Keep note'));

      // 3. Open passive task with 9999-12-31 23:59:59: displays timestamp and preserves it on save!
      await _tapKey(tester, 'edit_task_button_maxDue0002');
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('task_editor_due_input')),
            )
            .controller
            ?.text,
        equals('9999-12-31 23:59:59'),
      );
      expect(tester.widget<Switch>(switchFinder).value, isFalse);
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_note_input')),
        'Far horizon note',
      );
      await tester.pump();
      await _tapKey(tester, 'task_editor_save_button');

      board = container.read(taskNotifierProvider).requireValue;
      final maxDueTask = board.findTask('maxDue0002')!;
      expect(
        maxDueTask.dueAt,
        equals(DateTime.utc(9999, 12, 31, 23, 59, 59)),
        reason: '9999-12-31 23:59:59 due must not be wiped by defaultSuspendedAt filter',
      );
      expect(maxDueTask.isDuePassive, isTrue);

      // 4. Toggling Priority chip on a passive task auto-resets switch to true -> saves isDuePassive == false.
      await _tapKey(tester, 'edit_task_button_passSec001');
      expect(tester.widget<Switch>(switchFinder).value, isFalse);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_priority_button')),
      );
      expect(
        tester.widget<Switch>(switchFinder).value,
        isTrue,
        reason: 'Toggling Priority chip on must auto-reset switch to true',
      );
      await _tapKey(tester, 'task_editor_save_button');

      board = container.read(taskNotifierProvider).requireValue;
      passSecTask = board.findTask('passSec001')!;
      expect(passSecTask.isPriority, isTrue);
      expect(passSecTask.isDuePassive, isFalse);

      // 5. Editing dueAt auto-resets passive -> active, then manual toggle off overrides back to passive.
      await _tapKey(tester, 'edit_task_button_maxDue0002');
      expect(tester.widget<Switch>(switchFinder).value, isFalse);
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_due_input')),
        '2026-11-12 09:00',
      );
      await tester.pump();
      expect(
        tester.widget<Switch>(switchFinder).value,
        isTrue,
        reason: 'Changing dueAt to a different timestamp must auto-reset switch to true',
      );
      await _tapVisible(tester, switchFinder);
      expect(tester.widget<Switch>(switchFinder).value, isFalse);
      await _tapKey(tester, 'task_editor_save_button');

      board = container.read(taskNotifierProvider).requireValue;
      expect(
        board.findTask('maxDue0002')!.isDuePassive,
        isTrue,
        reason:
            'Manual toggle off after dueAt edit must save isDuePassive == true',
      );

      // 6. Completed task hides task_editor_due_auto_prioritize_switch and preserves passive when due untouched.
      await _tapKey(tester, 'tier_indicator_item_completed');
      await _tapKey(tester, 'edit_task_button_doneDue003');
      expect(
        switchFinder,
        findsNothing,
        reason: 'Completed tasks must hide the auto-prioritize switch',
      );
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_note_input')),
        'Archive note',
      );
      await tester.pump();
      await _tapKey(tester, 'task_editor_save_button');

      board = container.read(taskNotifierProvider).requireValue;
      expect(board.findTask('doneDue003')!.isDuePassive, isTrue);
    },
  );

  test('TaskEditorSchedulingNoteField and TaskEditorRepeatField enforce zero-copy normalization, Unicode scalar and control-char bounds, and 0..3650 lead-day parsing', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final de = lookupAppLocalizations(const Locale('de'));

    // 1. normalizeSchedulingNote: empty & ASCII whitespace -> null; non-CR preserved identically; CRLF/CR collapsed.
    for (final blank in <String>['', '   ', '\t\n\r\n  ']) {
      expect(
        TaskEditorSchedulingNoteField.normalizeSchedulingNote(blank),
        isNull,
        reason: 'ASCII-whitespace-only note "$blank" must collapse to null',
      );
    }
    const nonBreaking = '\u00A0';
    expect(
      identical(
        TaskEditorSchedulingNoteField.normalizeSchedulingNote(nonBreaking),
        nonBreaking,
      ),
      isTrue,
      reason: 'U+00A0 graphic whitespace without CR must be returned zero-copy',
    );
    const cleanMultiLine = '  Keep spaces\t"quoted" #hash {brace}\nLine 2  ';
    expect(
      identical(
        TaskEditorSchedulingNoteField.normalizeSchedulingNote(cleanMultiLine),
        cleanMultiLine,
      ),
      isTrue,
      reason: 'LF multi-line note without CR must be returned zero-copy',
    );
    expect(
      TaskEditorSchedulingNoteField.normalizeSchedulingNote(
        'Line 1\r\nLine 2\rLine 3\r\n',
      ),
      equals('Line 1\nLine 2\nLine 3\n'),
    );

    // 2. validateSchedulingNote: scalar boundaries (0, 1, 2000 ASCII, 2000 astral, 2001) + illegal control chars & surrogates.
    expect(
      TaskEditorSchedulingNoteField.validateSchedulingNote(null, en),
      isNull,
    );
    expect(
      TaskEditorSchedulingNoteField.validateSchedulingNote('A', en),
      isNull,
    );
    expect(
      TaskEditorSchedulingNoteField.validateSchedulingNote('a' * 2000, en),
      isNull,
    );
    final astral2000 = '\u{1F4CB}' * 2000;
    expect(astral2000.length, equals(4000));
    expect(
      TaskEditorSchedulingNoteField.validateSchedulingNote(astral2000, en),
      isNull,
      reason: '2000 astral Unicode scalars (4000 UTF-16 code units) must pass',
    );
    expect(
      TaskEditorSchedulingNoteField.validateSchedulingNote('a' * 2001, en),
      equals('Note must not exceed 2,000 characters.'),
    );
    expect(
      TaskEditorSchedulingNoteField.validateSchedulingNote(
        '\u{1F4CB}' * 2001,
        de,
      ),
      equals('Notiz darf maximal 2.000 Zeichen lang sein.'),
    );
    expect(
      TaskEditorSchedulingNoteField.validateSchedulingNote(
        'Allowed\t\n\rcontrols',
        en,
      ),
      isNull,
    );
    for (final invalidControl in <String>[
      'Wait\x00now',
      'Due\x07bell',
      'Esc\x1Bseq',
      'Del\x7Fchar',
      String.fromCharCodes(<int>[0xD800]),
      String.fromCharCodes(<int>[0xDC00]),
    ]) {
      expect(
        TaskEditorSchedulingNoteField.validateSchedulingNote(
          invalidControl,
          en,
        ),
        equals('Note contains unsupported control characters.'),
        reason: 'Disallowed control or surrogate input must fail inline in EN',
      );
      expect(
        TaskEditorSchedulingNoteField.validateSchedulingNote(
          invalidControl,
          de,
        ),
        equals('Notiz enthält nicht unterstützte Steuerzeichen.'),
        reason: 'Disallowed control or surrogate input must fail inline in DE',
      );
    }

    // 3. parseRepeatCount, parseLeadDays, and parseRepeatRule boundaries.
    expect(
      TaskEditorRepeatField.parseRepeatCount(isRepeating: false, rawCount: '5'),
      isNull,
    );
    expect(
      TaskEditorRepeatField.parseRepeatCount(isRepeating: true, rawCount: '0'),
      isNull,
    );
    expect(
      TaskEditorRepeatField.parseRepeatCount(isRepeating: true, rawCount: '1'),
      equals(1),
    );
    expect(
      TaskEditorRepeatField.parseRepeatCount(
        isRepeating: true,
        rawCount: '3650',
      ),
      equals(3650),
    );
    expect(
      TaskEditorRepeatField.parseRepeatCount(
        isRepeating: true,
        rawCount: '3651',
      ),
      isNull,
    );

    expect(
      TaskEditorRepeatField.parseLeadDays(
        hasDue: false,
        isRepeating: true,
        rawLeadDays: '999999',
      ),
      equals(0),
      reason: 'Lead days must resolve to 0 whenever hasDue is false',
    );
    expect(
      TaskEditorRepeatField.parseLeadDays(
        hasDue: true,
        isRepeating: false,
        rawLeadDays: '14',
      ),
      equals(0),
    );
    for (final (raw, expected) in <(String, int?)>[
      ('', 0),
      ('   ', 0),
      ('0', 0),
      ('00', 0),
      ('1', 1),
      ('3650', 3650),
      ('000000000000000000003650', 3650),
      ('3651', null),
      ('-1', null),
      ('-0', null),
      ('+5', null),
      ('14.5', null),
      ('abc', null),
      ('0000000000000000000000001', null),
      ('999999999999999999999999', null),
    ]) {
      expect(
        TaskEditorRepeatField.parseLeadDays(
          hasDue: true,
          isRepeating: true,
          rawLeadDays: raw,
        ),
        equals(expected),
        reason: 'parseLeadDays("$raw") must return $expected',
      );
    }

    const customClock = TdfRepeatClock(hour: 8, minute: 30, second: 15);
    expect(
      TaskEditorRepeatField.parseRepeatRule(
        existingClock: customClock,
        hasDue: true,
        isRepeating: true,
        rawCount: '2',
        rawLeadDays: '10',
        unit: RepeatUnit.weeks,
      ),
      equals(
        const TaskRepeatRule(
          count: 2,
          unit: RepeatUnit.weeks,
          clock: customClock,
          leadDays: 10,
        ),
      ),
    );
    expect(
      TaskEditorRepeatField.parseRepeatRule(
        existingClock: customClock,
        hasDue: false,
        isRepeating: true,
        rawCount: '2',
        rawLeadDays: '10',
        unit: RepeatUnit.weeks,
      ),
      equals(
        const TaskRepeatRule(
          count: 2,
          unit: RepeatUnit.weeks,
          clock: customClock,
          leadDays: 0,
        ),
      ),
    );
  });

  testWidgets(
    'EditTaskScreen authors, validates, clears, and preserves suspendedNote, dueNote, and repeat leadDays across open, expired, CRLF, and Completed tasks',
    (WidgetTester tester) async {
      const tdfService = TdfService();
      final seededBoard = tdfService.parse(
        'tdf 0.7.0\n\n'
        'queue {\n'
        '  modified 2026-11-01 08:00:00\n'
        '  task crlfTask01\n'
        '  task expDead002\n'
        '}\n\n'
        'task crlfTask01 {\n'
        '  name "CRLF Preserved Task"\n'
        '  created 2026-11-01 08:00:00\n'
        '  modified 2026-11-01 08:00:00\n'
        '  suspended 2026-11-06 09:00:00 "Hold line 1\\r\\nHold line 2"\n'
        '  due 2026-11-12 17:00:00 passive "Due line 1\\r\\nDue line 2"\n'
        '}\n\n'
        'task expDead002 {\n'
        '  name "Elapsed Deferral Task"\n'
        '  created 2026-11-01 08:00:00\n'
        '  modified 2026-11-01 08:00:00\n'
        '  suspended 2026-11-01 09:00:00 "Stale morning deferral"\n'
        '}\n\n'
        'task doneNote03 {\n'
        '  name "Completed With Deadline Note"\n'
        '  created 2026-10-25 08:00:00\n'
        '  modified 2026-10-29 12:00:00\n'
        '  finished 2026-10-29 12:00:00\n'
        '  completions 1\n'
        '  due 2026-10-30 15:00:00 passive "Archived filing cutoff"\n'
        '}\n',
      );
      final initialSerialized = tdfService.serialize(seededBoard);
      final container = await _pumpEditorApp(
        tester,
        initialTdf: initialSerialized,
        clock: DateTime.utc(2026, 11, 1, 12, 0),
      );

      final suspNoteFinder = find.byKey(
        const ValueKey('task_editor_suspended_note_input'),
      );
      final suspNoteClearFinder = find.byKey(
        const ValueKey('task_editor_suspended_note_clear_button'),
      );
      final dueNoteFinder = find.byKey(
        const ValueKey('task_editor_due_note_input'),
      );
      final dueNoteClearFinder = find.byKey(
        const ValueKey('task_editor_due_note_clear_button'),
      );
      final leadDaysFinder = find.byKey(
        const ValueKey('task_editor_repeat_lead_days_input'),
      );
      final leadDaysClearFinder = find.byKey(
        const ValueKey('task_editor_repeat_lead_days_clear_button'),
      );

      // 1. New task: note & lead inputs hidden initially; blank suspended + note persists `suspended forever "<note>"`.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'quick_add_advanced_button');

      expect(suspNoteFinder, findsNothing);
      expect(dueNoteFinder, findsNothing);
      expect(leadDaysFinder, findsNothing);

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_suspended_button')),
      );
      expect(suspNoteFinder, findsOneWidget);
      final suspNoteField = tester.widget<TextField>(suspNoteFinder);
      expect(suspNoteField.minLines, equals(1));
      expect(suspNoteField.maxLines, equals(3));
      expect(suspNoteField.keyboardType, equals(TextInputType.multiline));
      expect(suspNoteField.textInputAction, equals(TextInputAction.newline));

      // Toggle Repeat on without Due -> leadDays remains hidden.
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_repeat_button')),
      );
      expect(leadDaysFinder, findsNothing);

      // Toggle Due on -> both dueNote and leadDays appear.
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_due_button')),
      );
      expect(dueNoteFinder, findsOneWidget);
      expect(leadDaysFinder, findsOneWidget);

      // Independent error validation on count, leadDays, suspendedNote, and dueNote.
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_title_input')),
        'Vendor Contract Renewal',
      );
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_due_input')),
        '2026-11-25 17:00',
      );
      await tester.enterText(suspNoteFinder, 'a' * 2001);
      await tester.enterText(dueNoteFinder, 'Bad\x07bell');
      await tester.enterText(leadDaysFinder, '3651');
      await tester.pump();
      await _tapKey(tester, 'task_editor_save_button');

      expect(
        find.byKey(const ValueKey('edit_task_screen')),
        findsOneWidget,
        reason: 'Invalid scheduling note or lead days must keep EditTaskScreen open',
      );
      expect(
        find.text('Note must not exceed 2,000 characters.'),
        findsOneWidget,
      );
      expect(
        find.text('Note contains unsupported control characters.'),
        findsOneWidget,
      );
      expect(
        find.text('Enter a whole number between 0 and 3650 days.'),
        findsOneWidget,
      );
      expect(
        find.text('Enter a valid interval between 1 and 3650.'),
        findsNothing,
        reason: 'Invalid leadDays must not mark a valid repeat count invalid',
      );

      // Editing each field clears its error; test delimiter injection + CRLF normalization + unfocused clear button visibility.
      const complexSuspNoteInput =
          'Waiting on "quote #412"\r\nPath C:\\legal\t{draft}\u00A0ok';
      const expectedSuspNote =
          'Waiting on "quote #412"\nPath C:\\legal\t{draft}\u00A0ok';
      const complexDueNote =
          'Sign PDF before 17:00 CET\nInclude #appendix {v2}';
      await tester.enterText(suspNoteFinder, complexSuspNoteInput);
      await tester.enterText(dueNoteFinder, complexDueNote);
      await tester.enterText(leadDaysFinder, '14');
      await tester.pump();
      expect(find.text('Note must not exceed 2,000 characters.'), findsNothing);
      expect(
        find.text('Note contains unsupported control characters.'),
        findsNothing,
      );
      expect(
        find.text('Enter a whole number between 0 and 3650 days.'),
        findsNothing,
      );

      // Focus title field -> unfocused clear buttons on populated note and lead fields stay visible!
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_title_input')),
      );
      expect(suspNoteClearFinder, findsOneWidget);
      expect(dueNoteClearFinder, findsOneWidget);
      expect(leadDaysClearFinder, findsOneWidget);

      // Toggle Due off and back on -> retains draft leadDays ('14') and dueNote in controllers during session!
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_due_button')),
      );
      expect(dueNoteFinder, findsNothing);
      expect(leadDaysFinder, findsNothing);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_due_button')),
      );
      expect(
        tester.widget<TextField>(leadDaysFinder).controller?.text,
        equals('14'),
      );
      expect(
        tester.widget<TextField>(dueNoteFinder).controller?.text,
        equals(complexDueNote),
      );

      await _tapKey(tester, 'task_editor_save_button');

      var board = container.read(taskNotifierProvider).requireValue;
      var created = board.allTasks.singleWhere(
        (task) => task.title == 'Vendor Contract Renewal',
      );
      expect(
        created.isSuspendedForever,
        isTrue,
        reason: 'Blank deferral timestamp on new task must persist suspended forever',
      );
      expect(created.suspendedAt, isNull);
      expect(created.suspendedNote, equals(expectedSuspNote));
      expect(created.dueAt, equals(DateTime.utc(2026, 11, 25, 17, 0)));
      expect(created.dueNote, equals(complexDueNote));
      expect(
        created.repeatRule,
        equals(
          const TaskRepeatRule(count: 1, unit: RepeatUnit.days, leadDays: 14),
        ),
      );

      // Round-trip serialized .tdf to verify delimiter escaping and `suspended forever "<note>"`.
      final roundTrip = tdfService.parse(tdfService.serialize(board));
      final reparsedCreated = roundTrip.findTask(created.id)!;
      expect(reparsedCreated.isSuspendedForever, isTrue);
      expect(reparsedCreated.suspendedNote, equals(expectedSuspNote));
      expect(reparsedCreated.dueNote, equals(complexDueNote));
      expect(reparsedCreated.repeatRule?.leadDays, equals(14));

      // 2. Clear buttons strip only suspendedNote / dueNote / leadDays while keeping parent directives active.
      await _tapKey(tester, 'tier_indicator_item_blocked');
      await _tapKey(tester, 'edit_task_button_${created.id}');
      await _tapVisible(tester, suspNoteClearFinder);
      await tester.enterText(dueNoteFinder, '   \n\t  ');
      await _tapVisible(tester, leadDaysClearFinder);
      await _tapKey(tester, 'task_editor_save_button');

      board = container.read(taskNotifierProvider).requireValue;
      created = board.findTask(created.id)!;
      expect(created.isSuspendedForever, isTrue);
      expect(
        created.suspendedNote,
        isNull,
        reason: 'Clearing deferral note must keep indefinite suspension active',
      );
      expect(created.dueAt, equals(DateTime.utc(2026, 11, 25, 17, 0)));
      expect(
        created.dueNote,
        isNull,
        reason: 'ASCII-whitespace-only deadline note must collapse to null',
      );
      expect(created.repeatRule?.leadDays, equals(0));

      // 3. Untouched CRLF notes loaded from .tdf preserve `\r\n` verbatim and do not bump modifiedAt on no-op save.
      await _tapKey(tester, 'edit_task_button_crlfTask01');
      expect(
        tester.widget<TextField>(suspNoteFinder).controller?.text,
        equals('Hold line 1\r\nHold line 2'),
      );
      expect(
        tester.widget<TextField>(dueNoteFinder).controller?.text,
        equals('Due line 1\r\nDue line 2'),
      );
      await _tapKey(tester, 'task_editor_save_button');

      board = container.read(taskNotifierProvider).requireValue;
      final crlfTask = board.findTask('crlfTask01')!;
      expect(crlfTask.suspendedNote, equals('Hold line 1\r\nHold line 2'));
      expect(crlfTask.dueNote, equals('Due line 1\r\nDue line 2'));
      expect(
        crlfTask.modifiedAt,
        equals(DateTime.utc(2026, 11, 1, 8, 0)),
        reason: 'Saving untouched CRLF scheduling notes must be a pure no-op without bumping modifiedAt',
      );

      // 4. Open task with elapsed finite deferral: re-enabling Suspended starts with clean empty deferral note.
      await _tapKey(tester, 'tier_indicator_item_focus');
      if (find
          .byKey(const ValueKey('edit_task_button_expDead002'))
          .evaluate()
          .isEmpty) {
        await _tapKey(tester, 'tier_indicator_item_ready');
      }
      await _tapKey(tester, 'edit_task_button_expDead002');
      expect(suspNoteFinder, findsNothing);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_suspended_button')),
      );
      expect(
        tester.widget<TextField>(suspNoteFinder).controller?.text,
        isEmpty,
        reason: 'Re-enabling Suspended after an elapsed deferral must not resurrect stale expired deferral text',
      );
      await _tapKey(tester, 'task_editor_cancel_button');

      // 5. Completed task displays dueNote directly below due timestamp (with auto-prioritize switch hidden) and allows editing it.
      await _tapKey(tester, 'tier_indicator_item_completed');
      await _tapKey(tester, 'edit_task_button_doneNote03');
      expect(
        find.byKey(const ValueKey('task_editor_due_auto_prioritize_switch')),
        findsNothing,
      );
      expect(dueNoteFinder, findsOneWidget);
      expect(
        tester.widget<TextField>(dueNoteFinder).controller?.text,
        equals('Archived filing cutoff'),
      );
      await _tapVisible(tester, dueNoteClearFinder);
      await _tapKey(tester, 'task_editor_save_button');

      board = container.read(taskNotifierProvider).requireValue;
      final doneTask = board.findTask('doneNote03')!;
      expect(doneTask.dueAt, equals(DateTime.utc(2026, 10, 30, 15, 0)));
      expect(doneTask.isDuePassive, isTrue);
      expect(doneTask.dueNote, isNull);
    },
  );

  testWidgets(
    'EditTaskScreen integrates Mode 2 rollover + Undo, custom repeat clock preservation, restoreTask lead reveal, 0001 horizon TdfException guard, mid-flight Completer, and AppLogger secret hygiene',
    (WidgetTester tester) async {
      AppLogger.resetForTesting(clock: () => DateTime.utc(2026, 11, 1, 12, 0));
      AppLogger.setEnabled(
        true,
        persistToDisk: false,
        minimumLevel: LogLevel.debug,
      );
      addTearDown(AppLogger.resetForTesting);

      const seededTdf = '''
tdf 0.7.0

queue {
  modified 2026-11-01 08:00:00
  task clkLead001
}

task clkLead001 {
  name "Clock Preserved Task"
  created 2026-11-01 08:00:00
  modified 2026-11-01 08:00:00
  due 2026-11-20 12:00:00 "Noon cutoff"
  repeat 2 weeks 08:30 lead 5 days
}

task doneRest02 {
  name "Completed Recurring Template"
  created 2026-10-15 08:00:00
  modified 2026-10-28 09:00:00
  finished 2026-10-28 09:00:00
  completions 1
  due 2026-10-30 17:00:00
  repeat 1 months 09:00 lead 5 days
}
''';
      var currentClock = DateTime.utc(2026, 11, 1, 12, 0);
      const config = WebDavConfig(
        language: AppLanguage.english,
        diagnosticsEnabled: true,
        timeZoneMode: AppTimeZoneMode.manual,
        manualTimeZoneOffsetMinutes: 0,
      );
      final repository = _SuspendingLocalFileRepository(
        config: config,
        initialTdf: seededTdf,
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(config),
          ),
          localFileRepositoryProvider.overrideWithValue(repository),
          clockProvider.overrideWith(
            (ref) =>
                () => currentClock,
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Custom <repeat-time> (08:30) preserved when updating leadDays from 5 to 10; mid-flight Completer & AppLogger secret hygiene.
      await _tapKey(tester, 'tier_indicator_item_planned');
      if (find
          .byKey(const ValueKey('edit_task_button_clkLead001'))
          .evaluate()
          .isEmpty) {
        await _tapKey(tester, 'tier_indicator_item_ready');
      }
      if (find
          .byKey(const ValueKey('edit_task_button_clkLead001'))
          .evaluate()
          .isEmpty) {
        await _tapKey(tester, 'tier_indicator_item_focus');
      }
      await _tapKey(tester, 'edit_task_button_clkLead001');

      final leadInput = find.byKey(
        const ValueKey('task_editor_repeat_lead_days_input'),
      );
      expect(tester.widget<TextField>(leadInput).controller?.text, equals('5'));
      await tester.enterText(leadInput, '10');
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_suspended_button')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_suspended_input')),
        '2026-11-05 09:00',
      );
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_suspended_note_input')),
        'SECRET_DEFER_TOKEN_991',
      );
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_due_note_input')),
        'SECRET_DUE_TOKEN_882',
      );
      await tester.pump();

      final saveGate = Completer<void>();
      repository.saveGate = saveGate;
      await tester.tap(find.byKey(const ValueKey('task_editor_save_button')));
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Mid-flight frame while saveTdf Completer is suspended must not throw',
      );
      saveGate.complete();
      repository.saveGate = null;
      await tester.pumpAndSettle();

      expect(
        repository.initialTdf,
        contains('2 weeks 08:30 lead 10 days'),
        reason: 'Updating leadDays must preserve existing 08:30 repeat clock in .tdf output',
      );
      expect(
        const TdfService()
            .parse(repository.initialTdf)
            .findTask('clkLead001')
            ?.repeatRule,
        equals(
          const TaskRepeatRule(
            count: 2,
            unit: RepeatUnit.weeks,
            clock: TdfRepeatClock(hour: 8, minute: 30),
            leadDays: 10,
          ),
        ),
      );
      final logDump = AppLogger.fullLogText;
      expect(logDump, contains('ui.edit_task.saved'));
      expect(logDump, contains('has_suspended_note=true'));
      expect(logDump, contains('has_due_note=true'));
      expect(logDump, contains('lead_days=10'));
      expect(
        logDump,
        isNot(contains('SECRET_DEFER_TOKEN_991')),
        reason: 'AppLogger must never record raw deferral note contents (P-SECRET-HYGIENE)',
      );
      expect(
        logDump,
        isNot(contains('SECRET_DUE_TOKEN_882')),
        reason: 'AppLogger must never record raw deadline note contents (P-SECRET-HYGIENE)',
      );

      // 2. Mode 2 completeTask rollover + TaskInfoDialog inspection + TEP-007 Undo recovery!
      await container
          .read(taskNotifierProvider.notifier)
          .completeTask('clkLead001');
      await tester.pumpAndSettle();

      var board = container.read(taskNotifierProvider).requireValue;
      final rolledTask = board.findTask('clkLead001')!;
      expect(rolledTask.dueAt, equals(DateTime.utc(2026, 12, 4, 12, 0)));
      expect(
        rolledTask.suspendedAt,
        equals(DateTime.utc(2026, 11, 24, 8, 30)),
        reason: 'Mode 2 rollover must set suspendedAt = (2026-12-04 - 10 days) at 08:30 repeat clock',
      );
      expect(
        rolledTask.suspendedNote,
        isNull,
        reason: 'Mode 2 completion rollover must clear one-off suspendedNote',
      );
      expect(rolledTask.dueNote, equals('SECRET_DUE_TOKEN_882'));
      expect(rolledTask.repeatRule?.leadDays, equals(10));

      await _tapKey(tester, 'tier_indicator_item_blocked');
      await _tapKey(tester, 'due_task_badge_clkLead001');
      expect(
        find.byKey(const ValueKey('task_info_suspended_note')),
        findsNothing,
      );
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('task_info_due_note')),
            )
            .data,
        equals('SECRET_DUE_TOKEN_882'),
      );
      expect(
        find.text('Preparation window opens 10 day(s) before due date'),
        findsOneWidget,
      );
      await _tapKey(tester, 'task_info_dialog_close_button');

      final undone = await container
          .read(taskNotifierProvider.notifier)
          .undoLastAction();
      await tester.pumpAndSettle();
      expect(undone, isTrue);
      board = container.read(taskNotifierProvider).requireValue;
      final restoredPreComplete = board.findTask('clkLead001')!;
      expect(
        restoredPreComplete.dueAt,
        equals(DateTime.utc(2026, 11, 20, 12, 0)),
      );
      expect(
        restoredPreComplete.suspendedAt,
        equals(DateTime.utc(2026, 11, 5, 9, 0)),
      );
      expect(
        restoredPreComplete.suspendedNote,
        equals('SECRET_DEFER_TOKEN_991'),
        reason: 'Undo must restore pre-completion one-off suspendedNote',
      );

      // 3. Restore Completed task with repeat ... lead 5 days -> strips due, hides lead input, and reveals '5' when Due is re-enabled; saving without Due resets leadDays to 0.
      await container
          .read(taskNotifierProvider.notifier)
          .restoreTask('doneRest02');
      await tester.pumpAndSettle();
      board = container.read(taskNotifierProvider).requireValue;
      expect(board.findTask('doneRest02')!.dueAt, isNull);
      expect(board.findTask('doneRest02')!.repeatRule?.leadDays, equals(5));

      await _tapKey(tester, 'tier_indicator_item_planned');
      if (find
          .byKey(const ValueKey('edit_task_button_doneRest02'))
          .evaluate()
          .isEmpty) {
        await _tapKey(tester, 'tier_indicator_item_ready');
      }
      if (find
          .byKey(const ValueKey('edit_task_button_doneRest02'))
          .evaluate()
          .isEmpty) {
        await _tapKey(tester, 'tier_indicator_item_focus');
      }
      await _tapKey(tester, 'edit_task_button_doneRest02');
      expect(
        leadInput,
        findsNothing,
        reason:
            'Restored Mode 1 task without Due must hide Preparation lead input',
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_due_button')),
      );
      expect(
        tester.widget<TextField>(leadInput).controller?.text,
        equals('5'),
        reason: 'Re-enabling Due on restored task must reveal stored leadDays ("5")',
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_due_button')),
      );
      await _tapKey(tester, 'task_editor_save_button');
      board = container.read(taskNotifierProvider).requireValue;
      expect(
        board.findTask('doneRest02')!.repeatRule?.leadDays,
        equals(0),
        reason: 'Saving while Due is disabled must normalize leadDays to 0',
      );

      // 4. Calendar 0001-01-01 underflow guard (`0001-01-03` due + `repeat 1 days` + `leadDays = 10` + `auto-finish` completed step at `0001-01-02`).
      currentClock = DateTime.utc(1, 1, 2, 12, 0);
      container.invalidate(clockProvider);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'quick_add_advanced_button');

      await tester.enterText(
        find.byKey(const ValueKey('task_editor_title_input')),
        'Horizon Underflow Task',
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_due_button')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_due_input')),
        '0001-01-03 12:00',
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_repeat_button')),
      );
      await tester.enterText(leadInput, '10');
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_auto_finish_toggle')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_subtask_input')),
        'Done step',
      );
      await tester.pump();
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_subtask_add_button')),
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('task_editor_toggle_subtask_0')),
      );
      await _tapKey(tester, 'task_editor_save_button');

      expect(
        find.byKey(const ValueKey('edit_task_screen')),
        findsOneWidget,
        reason: '0001-01-01 proleptic calendar underflow must be caught atomically without closing EditTaskScreen',
      );
      expect(
        find.text('Enter a whole number between 0 and 3650 days.'),
        findsOneWidget,
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .allTasks
            .any((task) => task.title == 'Horizon Underflow Task'),
        isFalse,
        reason: 'Rejected horizon underflow must leave TaskBoard untouched',
      );
      expect(AppLogger.fullLogText, contains('ui.edit_task.persist_rejected'));
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
