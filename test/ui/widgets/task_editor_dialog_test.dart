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
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'Right-side task edit button and QuickAddBar Advanced button open the shared TaskEditorDialog enforcing non-empty, non-duplicate names and shared fields',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.2.0

label home {
  name "Home"
  color "#00E5FF"
}
label office {
  name "Office"
  color "#FF9100"
}
label c_it {
  name "IT"
  color "#2196F3"
}
label c_ops {
  name "Operations"
  color "#EB06FF"
}
task t001 {
  name "Existing Server Audit"
  note "Initial audit note"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
  labels c_it office
  subtasks {
    step false "Check firewall rules"
  }
}
''';
      final fixedNow = DateTime.utc(2026, 11, 1, 12, 0);
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const WebDavConfig(language: AppLanguage.english),
            ),
          ),
          localFileRepositoryProvider.overrideWith(
            (ref) => FakeLocalFileRepository(
              config: const WebDavConfig(language: AppLanguage.english),
              initialTdf: seededTdf,
            ),
          ),
          clockProvider.overrideWithValue(() => fixedNow),
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

      final pillFinder = find.byKey(const ValueKey('tier_pill_focus_t001'));
      final taskTitleFinder = find.text('Existing Server Audit');
      final completeButtonFinder = find.byKey(
        const ValueKey('complete_task_button_t001'),
      );
      final downgradeButtonFinder = find.byKey(
        const ValueKey('downgrade_task_button_t001'),
      );
      final dividerFinder = find.byKey(
        const ValueKey('edit_task_divider_t001'),
      );
      final editButtonFinder = find.byKey(
        const ValueKey('edit_task_button_t001'),
      );
      expect(pillFinder, findsOneWidget);
      expect(taskTitleFinder, findsOneWidget);
      expect(
        completeButtonFinder,
        findsOneWidget,
        reason:
            'Task pill must display a clickable completion circle at the front',
      );
      expect(
        downgradeButtonFinder,
        findsOneWidget,
        reason: 'Task pill must display a downward arrow button to the left of the right-side gap',
      );
      expect(
        find.descendant(
          of: downgradeButtonFinder,
          matching: find.byIcon(Icons.arrow_downward_rounded),
        ),
        findsOneWidget,
        reason: 'Downgrade button must display a downward arrow icon',
      );
      expect(
        dividerFinder,
        findsOneWidget,
        reason: 'Task pill must display a semi-transparent vertical divider before the edit button',
      );
      expect(
        editButtonFinder,
        findsOneWidget,
        reason: 'Task pill must display an edit button on the right side',
      );
      expect(
        tester.getTopLeft(completeButtonFinder).dx <
            tester.getTopLeft(taskTitleFinder).dx,
        isTrue,
        reason: 'Completion circle must be positioned at the front before the task title',
      );
      expect(
        tester.getTopLeft(downgradeButtonFinder).dx >
                tester.getTopLeft(taskTitleFinder).dx &&
            tester.getTopRight(downgradeButtonFinder).dx <=
                tester.getTopLeft(dividerFinder).dx,
        isTrue,
        reason: 'Downgrade arrow button must be positioned to the right of the task title and to the left of the vertical gap',
      );
      expect(
        tester.getTopLeft(dividerFinder).dx >=
                tester.getTopRight(downgradeButtonFinder).dx &&
            tester.getTopRight(dividerFinder).dx <=
                tester.getTopLeft(editButtonFinder).dx,
        isTrue,
        reason: 'Vertical divider must be positioned between the downgrade button and the edit button',
      );
      final pillCardFinder = find
          .descendant(of: pillFinder, matching: find.byType(Material))
          .first;
      expect(
        tester.getTopLeft(dividerFinder).dy,
        closeTo(tester.getTopLeft(pillCardFinder).dy, 0.01),
        reason: 'Vertical divider must start flush at the very top edge of the task pill card',
      );
      expect(
        tester.getBottomLeft(dividerFinder).dy,
        closeTo(tester.getBottomLeft(pillCardFinder).dy, 0.01),
        reason: 'Vertical divider must extend flush to the very bottom edge of the task pill card',
      );
      final dividerContainer = tester.widget<Container>(dividerFinder);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(
        dividerContainer.color,
        equals(scaffold.backgroundColor),
        reason: 'Vertical gap before the edit button must match the screen background color',
      );
      expect(
        tester.getSize(dividerFinder).width,
        equals(3.0),
        reason:
            'Vertical gap before the edit button must have a width of 3.0px',
      );

      await tester.tap(taskTitleFinder);
      await tester.pumpAndSettle();
      expect(
        container
            .read(taskNotifierProvider)
            .value!
            .focus
            .map((task) => task.id),
        contains('t001'),
        reason:
            'Tapping the task title or pill body must not complete the task',
      );
      expect(
        find.byKey(const ValueKey('task_editor_dialog')),
        findsNothing,
        reason: 'Tapping the task title or pill body must not open TaskEditorDialog',
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('quick_add_priority_button')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('quick_add_advanced_button')));
      await tester.pumpAndSettle();

      final dialogFinder = find.byKey(const ValueKey('task_editor_dialog'));
      final titleInputFinder = find.byKey(
        const ValueKey('task_editor_title_input'),
      );
      final noteInputFinder = find.byKey(
        const ValueKey('task_editor_note_input'),
      );
      final saveButtonFinder = find.byKey(
        const ValueKey('task_editor_save_button'),
      );

      expect(
        dialogFinder,
        findsOneWidget,
        reason: 'Tapping Advanced in QuickAddBar must open TaskEditorDialog',
      );
      expect(find.text('Extended Task View'), findsOneWidget);

      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();
      expect(
        find.text('Please enter a task name.'),
        findsOneWidget,
        reason: 'Saving with an empty name in create mode must show error',
      );
      expect(dialogFinder, findsOneWidget);

      await tester.enterText(titleInputFinder, '  existing server audit  ');
      await tester.pump();
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();
      expect(
        find.text('A task with this name already exists.'),
        findsOneWidget,
        reason: 'Saving a duplicate name in create mode must show error',
      );
      expect(dialogFinder, findsOneWidget);

      await tester.enterText(titleInputFinder, 'Rotate SSH Keys');
      await tester.enterText(noteInputFinder, 'Use ed25519 keys');
      await tester.tap(find.byKey(const ValueKey('task_editor_label_c_ops')));
      await tester.tap(find.byKey(const ValueKey('task_editor_label_home')));
      await tester.tap(
        find.byKey(const ValueKey('task_editor_auto_finish_toggle')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_subtask_input')),
        'Generate keypair',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('task_editor_subtask_add_button')),
      );
      await tester.pump();

      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      expect(
        dialogFinder,
        findsNothing,
        reason: 'Saving a valid new task must close TaskEditorDialog',
      );
      expect(
        find.byKey(const ValueKey('quick_add_bar')),
        findsNothing,
        reason: 'Creating a task via extended mode must also close QuickAddBar',
      );

      var board = container.read(taskNotifierProvider).value!;
      expect(
        board.focus.first.title,
        equals('Rotate SSH Keys'),
        reason: 'Created priority task must be at the top of Focus',
      );
      expect(board.focus.first.note, equals('Use ed25519 keys'));
      expect(board.focus.first.labelIds, equals(['home', 'c_ops']));
      expect(board.focus.first.subtasksAutoFinish, isTrue);
      expect(
        board.focus.first.subtasks.map((step) => step.title),
        equals(['Generate keypair']),
      );

      await tester.tap(editButtonFinder);
      await tester.pumpAndSettle();

      expect(
        dialogFinder,
        findsOneWidget,
        reason: 'Clicking the edit button on a task pill must open the same shared TaskEditorDialog',
      );
      expect(find.text('Edit Task'), findsOneWidget);
      expect(
        tester.widget<TextField>(titleInputFinder).controller?.text,
        equals('Existing Server Audit'),
        reason: 'Edit dialog must pre-fill the task title',
      );
      expect(
        tester.widget<TextField>(noteInputFinder).controller?.text,
        equals('Initial audit note'),
        reason: 'Edit dialog must pre-fill the task note',
      );
      expect(
        find.text('Check firewall rules'),
        findsOneWidget,
        reason: 'Edit dialog must pre-fill existing subtasks',
      );

      await tester.enterText(titleInputFinder, '   ');
      await tester.pump();
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();
      expect(
        find.text('Please enter a task name.'),
        findsOneWidget,
        reason: 'Edit dialog must reject empty task names',
      );

      await tester.enterText(titleInputFinder, 'rotate ssh keys');
      await tester.pump();
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();
      expect(
        find.text('A task with this name already exists.'),
        findsOneWidget,
        reason: 'Edit dialog must reject duplicate task names',
      );

      await tester.enterText(titleInputFinder, 'Updated Server Audit');
      await tester.enterText(noteInputFinder, 'Updated audit note');
      await tester.tap(
        find.byKey(const ValueKey('task_editor_someday_button')),
      );
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      expect(
        dialogFinder,
        findsNothing,
        reason: 'Saving valid edits must close TaskEditorDialog',
      );

      board = container.read(taskNotifierProvider).value!;
      expect(
        board.someday.map((task) => task.title),
        equals(['Updated Server Audit']),
        reason: 'Edited task with Someday enabled must move to Someday with its new title',
      );
      expect(board.someday.single.note, equals('Updated audit note'));

      final rotateTaskId = board.focus.single.id;
      await tester.tap(
        find.byKey(ValueKey('complete_task_button_$rotateTaskId')),
      );
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(
        board.focus,
        isEmpty,
        reason: 'Tapping the front completion circle must remove the task from Focus',
      );
      expect(
        board.completed.map((task) => task.title),
        equals(['Rotate SSH Keys']),
        reason: 'Tapping the front completion circle must check off the task into Completed',
      );

      await tester.tap(
        find.byKey(const ValueKey('tier_indicator_item_completed')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ValueKey('tier_pill_completed_$rotateTaskId')),
        findsOneWidget,
        reason:
            'Completed task pill must be rendered in the Completed tier pane',
      );

      await tester.tap(
        find.byKey(ValueKey('complete_task_button_$rotateTaskId')),
      );
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(
        board.completed,
        isEmpty,
        reason: 'Tapping the completion circle on a completed task must restore it out of Completed',
      );
      expect(
        board.focus.map((task) => task.id),
        equals([rotateTaskId]),
        reason: 'Restored Planned task must cascade into open Focus slot',
      );
      expect(
        board.focus.single.isPriority,
        isFalse,
        reason: 'Restoring to Planned via completion circle must strip the priority flag per Section 6.5',
      );
      expect(
        board.focus.single.queuedAt,
        equals(fixedNow),
        reason: 'Restoring to Planned via completion circle must set queued to now per Section 6.5',
      );

      await container
          .read(taskNotifierProvider.notifier)
          .completeTask(
            rotateTaskId,
            currentDate: fixedNow.add(const Duration(minutes: 10)),
          );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('edit_task_button_$rotateTaskId')));
      await tester.pumpAndSettle();

      expect(
        dialogFinder,
        findsOneWidget,
        reason:
            'Tapping edit on a completed task pill must open TaskEditorDialog',
      );
      final priorityChip = tester.widget<FilterChip>(
        find.byKey(const ValueKey('task_editor_priority_button')),
      );
      final somedayChip = tester.widget<FilterChip>(
        find.byKey(const ValueKey('task_editor_someday_button')),
      );
      expect(
        priorityChip.selected,
        isFalse,
        reason: 'Editing a completed task must default to Planned (Priority unselected) per Section 6.5',
      );
      expect(
        somedayChip.selected,
        isFalse,
        reason: 'Editing a completed task must default to Planned (Someday unselected) per Section 6.5',
      );

      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(
        board.completed,
        isEmpty,
        reason: 'Saving a completed task in TaskEditorDialog with default mode must restore it to Planned',
      );
      expect(board.focus.single.id, equals(rotateTaskId));
      expect(board.focus.single.isPriority, isFalse);

      await container
          .read(taskNotifierProvider.notifier)
          .completeTask(
            rotateTaskId,
            currentDate: fixedNow.add(const Duration(minutes: 20)),
          );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('edit_task_button_$rotateTaskId')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('task_editor_priority_button')),
      );
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(
        board.completed,
        isEmpty,
        reason: 'Saving a completed task with Priority selected must restore it to Focus',
      );
      expect(board.focus.single.id, equals(rotateTaskId));
      expect(board.focus.single.isPriority, isTrue);
    },
  );
}
