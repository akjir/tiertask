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
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/link_launcher_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'Task pill displays darker right-side indicators for priority, repeat, and subtasks regardless of subtask completion state, distinct from action button icons',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 08:10:00
  task all000OkD2
  task donesbOkD2
  task plain0OkD2
}

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

      final firstTaskFinder = find.byKey(
        const ValueKey('tier_pill_focus_auto00OkD2'),
      );
      final secondTaskFinder = find.byKey(
        const ValueKey('tier_pill_focus_manualOkD2'),
      );
      final initialFirstTaskTop = tester.getTopLeft(firstTaskFinder).dy;
      final collapsedSecondTaskTop = tester.getTopLeft(secondTaskFinder).dy;

      await tester.tap(find.text('Auto Finish Checklist Task'));
      await tester.pumpAndSettle();

      final expandedSecondTaskTop = tester.getTopLeft(secondTaskFinder).dy;
      expect(expandedSecondTaskTop > collapsedSecondTaskTop, isTrue);

      await tester.tap(find.byKey(const ValueKey('subtask_step_auto00OkD2_0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('subtask_step_auto00OkD2_1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));

      final midSubgroupCollapseTop = tester.getTopLeft(secondTaskFinder).dy;
      expect(
        midSubgroupCollapseTop < expandedSecondTaskTop &&
            midSubgroupCollapseTop > collapsedSecondTaskTop,
        isTrue,
        reason: 'Stage 1 of subtask auto-finish must collapse the subtask subgroup first while shifting lower tasks upward',
      );
      expect(
        find.byKey(const ValueKey('subtask_step_auto00OkD2_1')),
        findsOneWidget,
        reason: 'Subtask rows must still be visible while the subgroup is collapsing during Stage 1',
      );

      await tester.pump(const Duration(milliseconds: 110));

      expect(
        find.byKey(const ValueKey('subtask_step_auto00OkD2_0')),
        findsNothing,
        reason: 'Subtask subgroup must be completely closed before Stage 2 task removal starts',
      );
      expect(
        firstTaskFinder,
        findsOneWidget,
        reason: 'Parent task pill must still be present when Stage 2 task removal begins',
      );
      expect(
        tester.getTopLeft(secondTaskFinder).dy,
        closeTo(collapsedSecondTaskTop, 0.5),
        reason: 'Lower task must reach the collapsed-subgroup offset right as Stage 1 finishes',
      );

      await tester.pump(const Duration(milliseconds: 130));

      final midRemovalSecondTaskTop = tester.getTopLeft(secondTaskFinder).dy;
      expect(
        midRemovalSecondTaskTop < collapsedSecondTaskTop &&
            midRemovalSecondTaskTop > initialFirstTaskTop,
        isTrue,
        reason: 'Stage 2 task removal animation must progressively slide lower tasks upward into the removed task slot',
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
    'Closing, downgrading, and restoring tasks animate directionally, slide lower tasks upward, and animate auto-pulled upgraded tasks into the tier',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 08:15:00
  task f10000OkD2
  task f20000OkD2
  task f30000OkD2
  task r10000OkD2
}

task f10000OkD2 {
  name "Focus Task 1"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
}
task f20000OkD2 {
  name "Focus Task 2"
  created 2026-11-01 08:05
  queued 2026-11-01 08:05
  subtasks {
    step false "Subtask inside Focus 2"
  }
}
task f30000OkD2 {
  name "Focus Task 3"
  created 2026-11-01 08:10
  queued 2026-11-01 08:10
}
task r10000OkD2 {
  name "Ready Task 1"
  created 2026-11-01 08:15
  queued 2026-11-01 08:15
}
task c10000OkD2 {
  name "Completed Task 1"
  created 2026-10-30 08:00
  queued 2026-10-30 08:00
  finished 2026-10-31 09:00
  completions 1
}
task c20000OkD2 {
  name "Completed Task 2"
  created 2026-10-29 08:00
  queued 2026-10-29 08:00
  finished 2026-10-30 09:00
  completions 1
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

      final f1Finder = find.byKey(const ValueKey('tier_pill_focus_f10000OkD2'));
      final f2Finder = find.byKey(const ValueKey('tier_pill_focus_f20000OkD2'));
      final f3Finder = find.byKey(const ValueKey('tier_pill_focus_f30000OkD2'));
      final r1InFocusFinder = find.byKey(
        const ValueKey('tier_pill_focus_r10000OkD2'),
      );

      final slot1Top = tester.getTopLeft(f1Finder).dy;
      final slot2Top = tester.getTopLeft(f2Finder).dy;
      final initialF1MaterialLeft = tester
          .getTopLeft(
            find
                .descendant(of: f1Finder, matching: find.byType(Material))
                .first,
          )
          .dx;

      await tester.tap(
        find.byKey(const ValueKey('downgrade_task_button_f10000OkD2')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));

      final midDowngradeF1Left = tester
          .getTopLeft(
            find
                .descendant(of: f1Finder, matching: find.byType(Material))
                .first,
          )
          .dx;
      final midDowngradeF2Top = tester.getTopLeft(f2Finder).dy;

      expect(
        midDowngradeF1Left > initialF1MaterialLeft,
        isTrue,
        reason:
            'Downgrading a task via > must slide the task pill to the right',
      );
      expect(
        midDowngradeF2Top < slot2Top && midDowngradeF2Top > slot1Top,
        isTrue,
        reason:
            'Downgrading a task must progressively slide lower tasks upward',
      );

      await tester.pump(const Duration(milliseconds: 140));
      await tester.pump(const Duration(milliseconds: 120));

      expect(
        r1InFocusFinder,
        findsOneWidget,
        reason: 'Auto-pulled Ready task must upgrade into Focus when a slot vacates',
      );
      final r1EntryOpacity = tester
          .widget<Opacity>(
            find.descendant(
              of: r1InFocusFinder,
              matching: find.byType(Opacity),
            ),
          )
          .opacity;
      expect(
        r1EntryOpacity > 0.0 && r1EntryOpacity < 1.0,
        isTrue,
        reason: 'Upgraded auto-pulled task must animate its entry opacity from 0 to 1',
      );

      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(f2Finder).dy,
        closeTo(slot1Top, 0.01),
        reason: 'Second task must settle into slot 1 after downgrade completes',
      );

      await tester.tap(find.text('Focus Task 2'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('subtask_step_f20000OkD2_0')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('complete_task_button_f20000OkD2')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));

      expect(
        find.byKey(const ValueKey('subtask_step_f20000OkD2_0')),
        findsOneWidget,
        reason: 'Closing a task directly while its subtasks are expanded must collapse the subgroup first',
      );

      await tester.pump(const Duration(milliseconds: 110));
      expect(
        find.byKey(const ValueKey('subtask_step_f20000OkD2_0')),
        findsNothing,
        reason: 'Expanded subgroup must finish collapsing before Stage 2 direct task removal starts',
      );

      await tester.pump(const Duration(milliseconds: 130));

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('complete_task_button_f20000OkD2')),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
        reason: 'Closing a task directly must display the completion checkmark during the removal animation',
      );
      final midCompleteF3Top = tester.getTopLeft(f3Finder).dy;
      expect(
        midCompleteF3Top < slot2Top && midCompleteF3Top > slot1Top,
        isTrue,
        reason:
            'Direct task completion animation must slide lower tasks upward',
      );

      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(f3Finder).dy,
        closeTo(slot1Top, 0.01),
        reason: 'Third task must settle into slot 1 after second task closes',
      );

      await tester.tap(
        find.byKey(const ValueKey('tier_indicator_item_completed')),
      );
      await tester.pumpAndSettle();

      final c1Finder = find.byKey(
        const ValueKey('tier_pill_completed_c10000OkD2'),
      );
      final c2Finder = find.byKey(
        const ValueKey('tier_pill_completed_c20000OkD2'),
      );
      final c1InitialLeft = tester
          .getTopLeft(
            find
                .descendant(of: c1Finder, matching: find.byType(Material))
                .first,
          )
          .dx;
      final c1InitialTop = tester.getTopLeft(c1Finder).dy;
      final c2InitialTop = tester.getTopLeft(c2Finder).dy;

      await tester.tap(
        find.byKey(const ValueKey('complete_task_button_c10000OkD2')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));

      final midRestoreC1Left = tester
          .getTopLeft(
            find
                .descendant(of: c1Finder, matching: find.byType(Material))
                .first,
          )
          .dx;
      final midRestoreC2Top = tester.getTopLeft(c2Finder).dy;

      expect(
        midRestoreC1Left < c1InitialLeft,
        isTrue,
        reason: 'Restoring (upgrading) a task from Completed must slide the pill to the left',
      );
      expect(
        midRestoreC2Top < c2InitialTop && midRestoreC2Top > c1InitialTop,
        isTrue,
        reason: 'Restoring a completed task must slide lower completed tasks upward',
      );

      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(c2Finder).dy,
        closeTo(c1InitialTop, 0.01),
        reason: 'Remaining completed task must settle into the top slot after restore',
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
          linkLauncherRepositoryProvider.overrideWithValue(fakeLauncher),
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

      final linksIndicatorFinder = find.byKey(
        const ValueKey('links_task_indicator_lnk001OkD2'),
      );
      expect(
        linksIndicatorFinder,
        findsOneWidget,
        reason: 'Task with links must display the passive link indicator icon',
      );
      final linksIcon = tester.widget<Icon>(linksIndicatorFinder);
      expect(linksIcon.icon, equals(Icons.link_rounded));

      final link0Finder = find.byKey(const ValueKey('task_link_lnk001OkD2_0'));
      final link1Finder = find.byKey(const ValueKey('task_link_lnk001OkD2_1'));
      expect(
        link0Finder,
        findsNothing,
        reason: 'Task links must be collapsed initially',
      );

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
      expect(
        find.text('Could not open link.'),
        findsOneWidget,
        reason: 'Failed link launch must display a localized error SnackBar',
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

      final noteOnlyIndicatorFinder = find.byKey(
        const ValueKey('note_task_indicator_not001OkD2'),
      );
      final fullNoteIndicatorFinder = find.byKey(
        const ValueKey('note_task_indicator_all001OkD2'),
      );
      final plainNoteIndicatorFinder = find.byKey(
        const ValueKey('note_task_indicator_plain1OkD2'),
      );

      expect(
        noteOnlyIndicatorFinder,
        findsOneWidget,
        reason: 'Task with note must display the passive note indicator icon',
      );
      expect(
        fullNoteIndicatorFinder,
        findsOneWidget,
        reason: 'Task with note, links, and subtasks must display the passive note indicator icon',
      );
      expect(
        plainNoteIndicatorFinder,
        findsNothing,
        reason: 'Task without a note must not display the note indicator icon',
      );

      final noteIndicatorIcon = tester.widget<Icon>(noteOnlyIndicatorFinder);
      expect(noteIndicatorIcon.icon, equals(Icons.notes_rounded));

      final noteTooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: noteOnlyIndicatorFinder,
          matching: find.byType(Tooltip),
        ),
      );
      expect(noteTooltip.message, equals('Note'));

      final priorityLeft = tester
          .getTopLeft(
            find.byKey(const ValueKey('priority_task_indicator_all001OkD2')),
          )
          .dx;
      final repeatLeft = tester
          .getTopLeft(
            find.byKey(const ValueKey('repeat_task_indicator_all001OkD2')),
          )
          .dx;
      final noteLeft = tester.getTopLeft(fullNoteIndicatorFinder).dx;
      final linksLeft = tester
          .getTopLeft(
            find.byKey(const ValueKey('links_task_indicator_all001OkD2')),
          )
          .dx;
      final subtasksLeft = tester
          .getTopLeft(
            find.byKey(const ValueKey('subtasks_task_indicator_all001OkD2')),
          )
          .dx;

      expect(
        priorityLeft < repeatLeft &&
            repeatLeft < noteLeft &&
            noteLeft < linksLeft &&
            linksLeft < subtasksLeft,
        isTrue,
        reason: 'Passive indicators must be ordered Priority, Repeat, Note, Links, then Subtasks',
      );

      final noteOnlyRowFinder = find.byKey(
        const ValueKey('task_note_not001OkD2'),
      );
      expect(
        noteOnlyRowFinder,
        findsNothing,
        reason: 'Note row must be collapsed initially',
      );

      await tester.tap(find.text('Note Only Task'));
      await tester.pumpAndSettle();

      expect(
        noteOnlyRowFinder,
        findsOneWidget,
        reason: 'Tapping a note-only task pill must expand its note row',
      );
      expect(find.text('Standalone note content'), findsOneWidget);
      expect(
        find.descendant(
          of: noteOnlyRowFinder,
          matching: find.byIcon(Icons.notes_rounded),
        ),
        findsOneWidget,
        reason: 'Expanded note row must display a leading note icon',
      );

      await tester.tap(find.text('Note Only Task'));
      await tester.pumpAndSettle();
      expect(
        noteOnlyRowFinder,
        findsNothing,
        reason: 'Tapping an expanded note-only task pill must collapse it',
      );

      final fullNoteRowFinder = find.byKey(
        const ValueKey('task_note_all001OkD2'),
      );
      final fullLinkRowFinder = find.byKey(
        const ValueKey('task_link_all001OkD2_0'),
      );
      final fullSubtaskRowFinder = find.byKey(
        const ValueKey('subtask_step_all001OkD2_0'),
      );

      await tester.tap(find.text('Full Details Task'));
      await tester.pumpAndSettle();

      expect(fullNoteRowFinder, findsOneWidget);
      expect(fullLinkRowFinder, findsOneWidget);
      expect(fullSubtaskRowFinder, findsOneWidget);

      final noteTop = tester.getTopLeft(fullNoteRowFinder).dy;
      final linkTop = tester.getTopLeft(fullLinkRowFinder).dy;
      final subtaskTop = tester.getTopLeft(fullSubtaskRowFinder).dy;

      expect(
        noteTop < linkTop,
        isTrue,
        reason: 'Expanded note row must always be rendered above links',
      );
      expect(
        linkTop < subtaskTop,
        isTrue,
        reason: 'Expanded links must always be rendered above subtasks',
      );
    },
  );
}
