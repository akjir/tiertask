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

import 'package:flutter/gestures.dart';
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
    'Task pill displays darker right-side indicators for priority, repeat, and subtasks regardless of subtask completion state, distinct from action button icons',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.4.0

task all000OkD2 priority {
  name "Priority Repeating Checklist Task"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
  repeat 1 weeks
  subtasks {
    step false "Unchecked step"
    step true "Checked step"
  }
}
task donesbOkD2 {
  name "All Checked Subtasks Task"
  created 2026-11-01 08:05
  queued 2026-11-01 08:05
  subtasks {
    step true "Already completed step"
  }
}
task plain0OkD2 {
  name "Plain Task Without Indicators"
  created 2026-11-01 08:10
  queued 2026-11-01 08:10
}
''';
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
          clockProvider.overrideWithValue(
            () => DateTime.utc(2026, 11, 1, 12, 0),
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

      final priorityIndicatorFinder = find.byKey(
        const ValueKey('priority_task_indicator_all000OkD2'),
      );
      final repeatIndicatorFinder = find.byKey(
        const ValueKey('repeat_task_indicator_all000OkD2'),
      );
      final subtasksIndicatorFinder = find.byKey(
        const ValueKey('subtasks_task_indicator_all000OkD2'),
      );

      expect(
        priorityIndicatorFinder,
        findsOneWidget,
        reason: 'Priority task must display the priority indicator icon',
      );
      expect(
        repeatIndicatorFinder,
        findsOneWidget,
        reason: 'Repeating task must display the repeat indicator icon',
      );
      expect(
        subtasksIndicatorFinder,
        findsOneWidget,
        reason: 'Task with subtasks must display the subtasks indicator icon',
      );

      expect(
        find.byKey(const ValueKey('subtasks_task_indicator_donesbOkD2')),
        findsOneWidget,
        reason: 'Task with subtasks must display the subtasks indicator even when all subtasks are checked',
      );
      expect(
        find.byKey(const ValueKey('priority_task_indicator_donesbOkD2')),
        findsNothing,
        reason: 'Non-priority task must not display the priority indicator',
      );
      expect(
        find.byKey(const ValueKey('repeat_task_indicator_donesbOkD2')),
        findsNothing,
        reason: 'Non-repeating task must not display the repeat indicator',
      );

      expect(
        find.byKey(const ValueKey('priority_task_indicator_plain0OkD2')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('repeat_task_indicator_plain0OkD2')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('subtasks_task_indicator_plain0OkD2')),
        findsNothing,
      );

      final pillContext = tester.element(
        find.byKey(const ValueKey('tier_pill_focus_all000OkD2')),
      );
      final colorScheme = Theme.of(pillContext).colorScheme;
      final expectedIndicatorColor = colorScheme.onSurfaceVariant.withValues(
        alpha: 0.55,
      );

      final priorityIcon = tester.widget<Icon>(priorityIndicatorFinder);
      final repeatIcon = tester.widget<Icon>(repeatIndicatorFinder);
      final subtasksIcon = tester.widget<Icon>(subtasksIndicatorFinder);
      final downgradeButtonIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('downgrade_task_button_all000OkD2')),
          matching: find.byType(Icon),
        ),
      );
      final editButtonIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('edit_task_button_all000OkD2')),
          matching: find.byType(Icon),
        ),
      );

      expect(priorityIcon.icon, equals(Icons.bolt_rounded));
      expect(repeatIcon.icon, equals(Icons.repeat_rounded));
      expect(subtasksIcon.icon, equals(Icons.checklist_rounded));

      for (final indicator in [priorityIcon, repeatIcon, subtasksIcon]) {
        expect(
          indicator.color,
          equals(expectedIndicatorColor),
          reason: 'Passive task indicators must use the darker dimmed onSurfaceVariant color',
        );
        expect(
          indicator.color,
          isNot(equals(downgradeButtonIcon.color)),
          reason: 'Passive task indicators must be visually distinct from action button icons',
        );
        expect(
          indicator.size,
          lessThan(downgradeButtonIcon.size!),
          reason: 'Passive task indicators must be smaller than interactive action button icons',
        );
        expect(indicator.size, lessThan(editButtonIcon.size!));
      }

      final titleRight = tester
          .getTopRight(find.text('Priority Repeating Checklist Task'))
          .dx;
      final priorityLeft = tester.getTopLeft(priorityIndicatorFinder).dx;
      final subtasksRight = tester.getTopRight(subtasksIndicatorFinder).dx;
      final downgradeLeft = tester
          .getTopLeft(
            find.byKey(const ValueKey('downgrade_task_button_all000OkD2')),
          )
          .dx;

      expect(
        priorityLeft >= titleRight,
        isTrue,
        reason: 'Indicators must be positioned on the right side of the title',
      );
      expect(
        subtasksRight <= downgradeLeft,
        isTrue,
        reason:
            'Indicators must be positioned to the left of the action buttons',
      );
    },
  );

  testWidgets(
    'Tapping a task pill with subtasks animates subtasks downward, shifts subsequent tasks down, toggles subtasks on and off, and collapses on second tap',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.4.0

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
          clockProvider.overrideWithValue(
            () => DateTime.utc(2026, 11, 1, 12, 0),
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

      final step0Finder = find.byKey(
        const ValueKey('subtask_step_000001OkD2_0'),
      );
      final step1Finder = find.byKey(
        const ValueKey('subtask_step_000001OkD2_1'),
      );
      final secondTaskPillFinder = find.byKey(
        const ValueKey('tier_pill_focus_000002OkD2'),
      );

      expect(
        step0Finder,
        findsNothing,
        reason: 'Subtasks must be collapsed initially',
      );
      expect(step1Finder, findsNothing);

      final initialSecondTaskTop = tester.getTopLeft(secondTaskPillFinder).dy;

      await tester.tap(find.text('Deploy release candidate'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));

      final midAnimationSecondTaskTop = tester
          .getTopLeft(secondTaskPillFinder)
          .dy;
      expect(
        midAnimationSecondTaskTop > initialSecondTaskTop,
        isTrue,
        reason: 'Downward expansion animation must progressively shift the following task pill downward',
      );

      await tester.pumpAndSettle();

      final expandedSecondTaskTop = tester.getTopLeft(secondTaskPillFinder).dy;
      expect(
        expandedSecondTaskTop > midAnimationSecondTaskTop,
        isTrue,
        reason: 'Completed expansion must shift the following task pill to its full offset below the subtasks',
      );
      expect(
        step0Finder,
        findsOneWidget,
        reason: 'First subtask must be visible when expanded',
      );
      expect(
        step1Finder,
        findsOneWidget,
        reason: 'Second subtask must be visible when expanded',
      );
      expect(find.text('Prepare backup'), findsOneWidget);
      expect(find.text('Verify checksum'), findsOneWidget);

      await tester.tap(step0Finder);
      await tester.pumpAndSettle();

      var board = container.read(taskNotifierProvider).value!;
      expect(
        board.findTask('000001OkD2')!.subtasks[0].isCompleted,
        isTrue,
        reason: 'Tapping an unchecked subtask must mark it as completed',
      );
      expect(
        board.findTask('000001OkD2')!.subtasks[1].isCompleted,
        isFalse,
        reason: 'Other subtasks must remain unchanged',
      );
      expect(
        find.byKey(const ValueKey('subtasks_task_indicator_000001OkD2')),
        findsOneWidget,
        reason: 'Subtasks indicator icon must remain visible when a subtask is checked',
      );

      await tester.tap(step1Finder);
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(
        board
            .findTask('000001OkD2')!
            .subtasks
            .every((step) => step.isCompleted),
        isTrue,
        reason: 'Tapping the second subtask must mark all subtasks completed',
      );
      expect(
        find.byKey(const ValueKey('subtasks_task_indicator_000001OkD2')),
        findsOneWidget,
        reason: 'Subtasks indicator icon must remain visible when all subtasks are checked',
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

      expect(
        step0Finder,
        findsNothing,
        reason: 'Tapping the same task again must collapse its subtasks',
      );
      expect(step1Finder, findsNothing);
      expect(
        tester.getTopLeft(secondTaskPillFinder).dy,
        closeTo(initialSecondTaskTop, 0.01),
        reason: 'Collapsing subtasks must shift subsequent tasks back to their initial position',
      );

      await tester.tap(
        find.byKey(const ValueKey('complete_task_button_000001OkD2')),
      );
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(
        board.completed.map((task) => task.id),
        equals(['000001OkD2']),
        reason: 'Completing 000001OkD2 must move it to Completed',
      );
      expect(
        board
            .findTask('000001OkD2')!
            .subtasks
            .every((step) => step.isCompleted),
        isTrue,
        reason: 'Completing a task with subtasks must mark all subtasks as completed',
      );

      await tester.tap(
        find.byKey(const ValueKey('tier_indicator_item_completed')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Deploy release candidate'));
      await tester.pumpAndSettle();

      expect(
        step0Finder,
        findsOneWidget,
        reason: 'Completed task must still allow viewing its subtasks',
      );
      await tester.tap(step0Finder);
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(
        board
            .findTask('000001OkD2')!
            .subtasks
            .every((step) => step.isCompleted),
        isTrue,
        reason: 'Tapping a subtask of a completed task must not unlock or uncheck the subtask',
      );

      await tester.tap(
        find.byKey(const ValueKey('complete_task_button_000001OkD2')),
      );
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(
        board.completed,
        isEmpty,
        reason: 'Tapping the completion button in Completed must restore 000001OkD2',
      );
      expect(
        board
            .findTask('000001OkD2')!
            .subtasks
            .every((step) => !step.isCompleted),
        isTrue,
        reason: 'Reopening a completed task must reopen all of its subtasks',
      );
    },
  );

  testWidgets(
    'Checking all expanded subtasks on a task with subtasks auto-finish completes the task automatically and differentiates subtask indicator icons and hover tooltips',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.4.0

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
          clockProvider.overrideWithValue(
            () => DateTime.utc(2026, 11, 1, 12, 0),
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

      final autoSubtasksIcon = tester.widget<Icon>(
        find.byKey(const ValueKey('subtasks_task_indicator_auto00OkD2')),
      );
      final manualSubtasksIcon = tester.widget<Icon>(
        find.byKey(const ValueKey('subtasks_task_indicator_manualOkD2')),
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

      final priorityTooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byKey(const ValueKey('priority_task_indicator_auto00OkD2')),
          matching: find.byType(Tooltip),
        ),
      );
      final repeatTooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byKey(const ValueKey('repeat_task_indicator_auto00OkD2')),
          matching: find.byType(Tooltip),
        ),
      );
      final autoSubtasksTooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byKey(const ValueKey('subtasks_task_indicator_auto00OkD2')),
          matching: find.byType(Tooltip),
        ),
      );
      final manualSubtasksTooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byKey(const ValueKey('subtasks_task_indicator_manualOkD2')),
          matching: find.byType(Tooltip),
        ),
      );

      expect(priorityTooltip.message, equals('Priority'));
      expect(repeatTooltip.message, equals('Repeating task'));
      expect(autoSubtasksTooltip.message, equals('Subtasks (auto-finish)'));
      expect(manualSubtasksTooltip.message, equals('Subtasks'));

      final mouseGesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouseGesture.addPointer(location: Offset.zero);
      addTearDown(mouseGesture.removePointer);

      await mouseGesture.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey('repeat_task_indicator_auto00OkD2')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Repeating task'),
        findsOneWidget,
        reason: 'Hovering the mouse over the repeat indicator must display its tooltip',
      );

      await container
          .read(webDavConfigProvider.notifier)
          .updateLanguage(AppLanguage.german);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Tooltip>(
              find.ancestor(
                of: find.byKey(
                  const ValueKey('priority_task_indicator_auto00OkD2'),
                ),
                matching: find.byType(Tooltip),
              ),
            )
            .message,
        equals('Priorität'),
      );
      expect(
        tester
            .widget<Tooltip>(
              find.ancestor(
                of: find.byKey(
                  const ValueKey('repeat_task_indicator_auto00OkD2'),
                ),
                matching: find.byType(Tooltip),
              ),
            )
            .message,
        equals('Wiederkehrende Aufgabe'),
      );
      expect(
        tester
            .widget<Tooltip>(
              find.ancestor(
                of: find.byKey(
                  const ValueKey('subtasks_task_indicator_auto00OkD2'),
                ),
                matching: find.byType(Tooltip),
              ),
            )
            .message,
        equals('Unteraufgaben (automatisch abschließen)'),
      );
      expect(
        tester
            .widget<Tooltip>(
              find.ancestor(
                of: find.byKey(
                  const ValueKey('subtasks_task_indicator_manualOkD2'),
                ),
                matching: find.byType(Tooltip),
              ),
            )
            .message,
        equals('Unteraufgaben'),
      );

      await tester.tap(find.text('Auto Finish Checklist Task'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('subtask_step_auto00OkD2_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('subtask_step_auto00OkD2_1')));
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
    },
  );
}
