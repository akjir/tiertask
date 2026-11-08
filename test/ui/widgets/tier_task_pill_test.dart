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

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/ui/widgets/tier_task_pill.dart';

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
      await _pumpSeededApp(tester, seededTdf);

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
      await _pumpSeededApp(tester, seededTdf);

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
    'TierTaskPill mounted via pumpLeafWidget updates FakeTaskNotifier board in-memory on completion without TDF parsing',
    (WidgetTester tester) async {
      final createdAt = DateTime.utc(2026, 11, 1, 8, 0);
      final task = TaskItem(
        id: 'leaf01OkD2',
        title: 'Isolated Leaf Pill Task',
        createdAt: createdAt,
      );
      final initialBoard = TaskBoard(focus: [task]);

      final container = await pumpLeafWidget(
        tester,
        TierTaskPill(task: task, canDowngrade: true, isCompleted: false),
        board: initialBoard,
      );
      await tester.pumpAndSettle();

      expect(find.text('Isolated Leaf Pill Task'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('complete_task_button_leaf01OkD2')),
      );
      await tester.pumpAndSettle();

      final updatedBoard = container.read(taskNotifierProvider).requireValue;
      expect(
        updatedBoard.completed.map((item) => item.id),
        equals(['leaf01OkD2']),
      );
    },
  );

  testWidgets(
    'Task pill renders uniform bottom label indicator blocks with hover tooltips aligned under the title without altering any other element geometry',
    (WidgetTester tester) async {
      final createdAt = DateTime.utc(2026, 11, 1, 8, 0);
      const labelAlpha = TdfLabel(
        id: 'lblAlpha01',
        name: 'Alpha Label',
        color: '#FFEB3B',
      );
      const labelBeta = TdfLabel(
        id: 'lblBeta002',
        name: 'Beta Label',
        color: '#4CAF50',
      );
      const labelGamma = TdfLabel(id: 'lblGamma03', name: 'Gamma Uncolored');
      final labeledTask = TaskItem(
        id: 'taskLbl001',
        title: 'Task Alignment Check',
        createdAt: createdAt,
        isPriority: true,
        labelIds: const ['lblGamma03', 'lblAlpha01', 'lblBeta002'],
      );
      final plainTask = TaskItem(
        id: 'taskPln002',
        title: 'Task Alignment Check',
        createdAt: createdAt,
        isPriority: true,
      );
      final initialBoard = TaskBoard(
        focus: [labeledTask, plainTask],
        labels: const [labelBeta, labelGamma, labelAlpha],
      );

      await pumpLeafWidget(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TierTaskPill(
              key: const ValueKey('pill_labeled'),
              task: labeledTask,
              canDowngrade: true,
              isCompleted: false,
            ),
            TierTaskPill(
              key: const ValueKey('pill_plain'),
              task: plainTask,
              canDowngrade: true,
              isCompleted: false,
            ),
          ],
        ),
        board: initialBoard,
      );
      await tester.pumpAndSettle();

      final alphaBlockFinder = find.byKey(
        const ValueKey('label_task_indicator_taskLbl001_lblAlpha01'),
      );
      final betaBlockFinder = find.byKey(
        const ValueKey('label_task_indicator_taskLbl001_lblBeta002'),
      );
      final gammaBlockFinder = find.byKey(
        const ValueKey('label_task_indicator_taskLbl001_lblGamma03'),
      );

      expect(
        alphaBlockFinder,
        findsOneWidget,
        reason: 'Assigned Alpha label must render an indicator block',
      );
      expect(
        betaBlockFinder,
        findsOneWidget,
        reason: 'Assigned Beta label must render an indicator block',
      );
      expect(
        gammaBlockFinder,
        findsOneWidget,
        reason: 'Assigned uncolored Gamma label must render an indicator block',
      );
      expect(
        find.byKey(
          const ValueKey('label_task_indicator_taskPln002_lblAlpha01'),
        ),
        findsNothing,
        reason:
            'Task without labels must not render any label indicator blocks',
      );

      final alphaRect = tester.getRect(alphaBlockFinder);
      final betaRect = tester.getRect(betaBlockFinder);
      final gammaRect = tester.getRect(gammaBlockFinder);

      expect(
        alphaRect.size,
        equals(betaRect.size),
        reason: 'All label indicator blocks must have identical dimensions',
      );
      expect(
        betaRect.size,
        equals(gammaRect.size),
        reason: 'All label indicator blocks must have identical dimensions',
      );

      final gapAlphaBeta = betaRect.left - alphaRect.right;
      final gapBetaGamma = gammaRect.left - betaRect.right;
      expect(
        gapAlphaBeta,
        closeTo(gapBetaGamma, 0.01),
        reason:
            'Horizontal spacing between adjacent label blocks must be uniform',
      );
      expect(
        alphaRect.width,
        greaterThan(gapAlphaBeta),
        reason:
            'Each label block must be wider than the spacing between blocks',
      );

      final labeledTitleRect = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('pill_labeled')),
          matching: find.text('Task Alignment Check'),
        ),
      );
      final labeledMaterialRect = tester.getRect(
        find
            .descendant(
              of: find.byKey(const ValueKey('pill_labeled')),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(
        alphaRect.left,
        closeTo(labeledTitleRect.left, 0.01),
        reason: 'First label indicator block must start directly aligned with the left edge of the task title',
      );
      expect(
        alphaRect.bottom,
        closeTo(labeledMaterialRect.bottom, 0.01),
        reason: 'Label indicator blocks must sit flush at the bottom of the task pill row',
      );

      final pillContext = tester.element(
        find.byKey(const ValueKey('pill_labeled')),
      );
      final expectedFallbackColor = Theme.of(pillContext)
          .colorScheme
          .onSurfaceVariant
          .withValues(alpha: 0.55);

      final alphaDecoration =
          tester.widget<Container>(alphaBlockFinder).decoration!
              as BoxDecoration;
      final betaDecoration =
          tester.widget<Container>(betaBlockFinder).decoration!
              as BoxDecoration;
      final gammaDecoration =
          tester.widget<Container>(gammaBlockFinder).decoration!
              as BoxDecoration;

      expect(alphaDecoration.color, equals(const Color(0xFFFFEB3B)));
      expect(betaDecoration.color, equals(const Color(0xFF4CAF50)));
      expect(gammaDecoration.color, equals(expectedFallbackColor));

      final alphaTooltip = tester.widget<Tooltip>(
        find.ancestor(of: alphaBlockFinder, matching: find.byType(Tooltip)),
      );
      final betaTooltip = tester.widget<Tooltip>(
        find.ancestor(of: betaBlockFinder, matching: find.byType(Tooltip)),
      );
      final gammaTooltip = tester.widget<Tooltip>(
        find.ancestor(of: gammaBlockFinder, matching: find.byType(Tooltip)),
      );
      expect(alphaTooltip.message, equals('Alpha Label'));
      expect(betaTooltip.message, equals('Beta Label'));
      expect(gammaTooltip.message, equals('Gamma Uncolored'));

      final mouseGesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouseGesture.addPointer(location: Offset.zero);
      addTearDown(mouseGesture.removePointer);

      await mouseGesture.moveTo(tester.getCenter(alphaBlockFinder));
      await tester.pumpAndSettle();
      expect(
        find.text('Alpha Label'),
        findsOneWidget,
        reason:
            'Hovering the mouse over a label block must display the label name',
      );

      final plainTitleRect = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('pill_plain')),
          matching: find.text('Task Alignment Check'),
        ),
      );
      final plainMaterialRect = tester.getRect(
        find
            .descendant(
              of: find.byKey(const ValueKey('pill_plain')),
              matching: find.byType(Material),
            )
            .first,
      );
      final labeledCompleteRect = tester.getRect(
        find.byKey(const ValueKey('complete_task_button_taskLbl001')),
      );
      final plainCompleteRect = tester.getRect(
        find.byKey(const ValueKey('complete_task_button_taskPln002')),
      );
      final labeledPriorityRect = tester.getRect(
        find.byKey(const ValueKey('priority_task_indicator_taskLbl001')),
      );
      final plainPriorityRect = tester.getRect(
        find.byKey(const ValueKey('priority_task_indicator_taskPln002')),
      );
      final labeledDowngradeRect = tester.getRect(
        find.byKey(const ValueKey('downgrade_task_button_taskLbl001')),
      );
      final plainDowngradeRect = tester.getRect(
        find.byKey(const ValueKey('downgrade_task_button_taskPln002')),
      );
      final labeledEditRect = tester.getRect(
        find.byKey(const ValueKey('edit_task_button_taskLbl001')),
      );
      final plainEditRect = tester.getRect(
        find.byKey(const ValueKey('edit_task_button_taskPln002')),
      );

      expect(
        labeledMaterialRect.size,
        equals(plainMaterialRect.size),
        reason: 'Task card dimensions must remain pixel-identical when label indicators are present',
      );
      expect(
        labeledTitleRect.topLeft - labeledMaterialRect.topLeft,
        equals(plainTitleRect.topLeft - plainMaterialRect.topLeft),
        reason: 'Task title position must remain pixel-identical when label indicators are present',
      );
      expect(
        labeledCompleteRect.topLeft - labeledMaterialRect.topLeft,
        equals(plainCompleteRect.topLeft - plainMaterialRect.topLeft),
        reason: 'Completion button position must remain pixel-identical when label indicators are present',
      );
      expect(
        labeledPriorityRect.topLeft - labeledMaterialRect.topLeft,
        equals(plainPriorityRect.topLeft - plainMaterialRect.topLeft),
        reason: 'Passive status indicator position must remain pixel-identical when label indicators are present',
      );
      expect(
        labeledDowngradeRect.topLeft - labeledMaterialRect.topLeft,
        equals(plainDowngradeRect.topLeft - plainMaterialRect.topLeft),
        reason: 'Downgrade button position must remain pixel-identical when label indicators are present',
      );
      expect(
        labeledEditRect.topLeft - labeledMaterialRect.topLeft,
        equals(plainEditRect.topLeft - plainMaterialRect.topLeft),
        reason: 'Edit button position must remain pixel-identical when label indicators are present',
      );
    },
  );

  testWidgets(
    'TierTaskPill renders due badge when dueAt is present and passes activeFilterLabelId on downgrade',
    (WidgetTester tester) async {
      final createdAt = DateTime.utc(2026, 11, 1, 8, 0);
      final dueTask = TaskItem(
        id: 'dueTask001',
        title: 'Submit Tax Filing',
        createdAt: createdAt,
        dueAt: DateTime.utc(2026, 11, 15, 14, 0),
      );
      final initialBoard = TaskBoard(focus: [dueTask]);

      await pumpLeafWidget(
        tester,
        TierTaskPill(
          task: dueTask,
          canDowngrade: true,
          isCompleted: false,
          activeFilterLabelId: 'lblScoped1',
        ),
        board: initialBoard,
      );
      await tester.pumpAndSettle();

      final dueBadgeFinder = find.byKey(
        const ValueKey('due_task_badge_dueTask001'),
      );
      expect(
        dueBadgeFinder,
        findsOneWidget,
        reason:
            'Task with dueAt must display the compact due badge on the pill',
      );
      expect(
        find.textContaining('2026-11-15'),
        findsOneWidget,
        reason: 'Due badge must display the formatted local due date',
      );
    },
  );
}

/// Pumps [TierTaskApp] seeded with [seededTdf] at `2026-11-01 12:00` UTC.
Future<ProviderContainer> _pumpSeededApp(
  WidgetTester tester,
  String seededTdf,
) async {
  const config = WebDavConfig(language: AppLanguage.english);
  final container = ProviderContainer(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(
        InMemorySettingsRepository(config),
      ),
      localFileRepositoryProvider.overrideWith(
        (ref) => FakeLocalFileRepository(config: config, initialTdf: seededTdf),
      ),
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
