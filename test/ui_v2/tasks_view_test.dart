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

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/models/storage_file_read_status.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/presentation/app_shell_controller.dart';
import 'package:tiertask/presentation/floating_notice_controller.dart';
import 'package:tiertask/presentation/ui_v2_shell_models.dart';
import 'package:tiertask/providers/sync_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/ui_v2/views/tasks_view.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import '../ui/test_helpers.dart';
import 'test_helpers.dart';

final DateTime _fixedNowUtc = DateTime.utc(2026, 11, 10, 12, 0);

/// Task notifier double that suspends initial board loading on a [Completer] for loading-state tests.
class _CompleterTaskNotifier extends FakeTaskNotifier {
  /// Creates a [_CompleterTaskNotifier].
  _CompleterTaskNotifier(this.completer) : super(TaskBoard.empty());

  /// Completer controlling initial [build] resolution.
  final Completer<TaskBoard> completer;

  @override
  Future<TaskBoard> build() => completer.future;
}

/// Task notifier double that throws an error on initial load and records retry invocations.
class _FailingTaskNotifier extends FakeTaskNotifier {
  /// Creates a [_FailingTaskNotifier].
  _FailingTaskNotifier({required this.error, this.onBuildAttempt})
    : super(TaskBoard.empty());

  /// Error thrown on initial load.
  final Object error;

  /// Optional counter callback invoked on each [build] attempt.
  final VoidCallback? onBuildAttempt;

  @override
  Future<TaskBoard> build() async {
    onBuildAttempt?.call();
    throw error;
  }
}

/// Task notifier double that records manual [syncFromRemote] retries while keeping an in-memory board.
class _SpySyncTaskNotifier extends FakeTaskNotifier {
  /// Creates a [_SpySyncTaskNotifier].
  _SpySyncTaskNotifier(super.initialBoard, {required this.onSync});

  /// Callback invoked when [syncFromRemote] is triggered.
  final VoidCallback onSync;

  @override
  Future<void> syncFromRemote() async {
    onSync();
  }
}

/// Harness hosting [TasksView] above a pinned [TasksQuickAddDock] mirroring `UiAdaptiveAppShell`.
class _TasksHarness extends StatelessWidget {
  /// Creates a [_TasksHarness].
  const _TasksHarness({this.constrainToWidth});

  /// Optional max width simulating the main column beside the `244px` desktop sidebar.
  final double? constrainToWidth;

  @override
  Widget build(BuildContext context) {
    Widget content = const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: TasksView()),
        Padding(
          padding: EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 12.0),
          child: TasksQuickAddDock(),
        ),
      ],
    );
    if (constrainToWidth case final width?) {
      content = Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: content),
      );
    }
    return Scaffold(body: content);
  }
}

/// Builds a seeded [TaskBoard] from explicit [tasks], [labels], [locations], and [queueIds].
TaskBoard _buildBoard({
  List<TaskItem> tasks = const <TaskItem>[],
  List<TdfLabel> labels = const <TdfLabel>[],
  List<TdfLocation> locations = const <TdfLocation>[],
  List<String>? queueIds,
  DateTime? evaluationTime,
}) {
  final effectiveQueue =
      queueIds ??
      <String>[
        for (final task in tasks)
          if (!task.isCompleted) task.id,
      ];
  return TaskBoard.evaluate(
    tasks: tasks,
    labels: labels,
    locations: locations,
    queueBlock: TdfQueueBlock(taskIds: effectiveQueue),
    evaluationTime: evaluationTime ?? _fixedNowUtc,
  );
}

/// Sets both `tester.view.physicalSize` (`MediaQuery.sizeOf`) and `devicePixelRatio = 1.0` for responsive breakpoint tests.
void _setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  group('TasksView & TasksQuickAddDock responsive breakpoints', () {
    testWidgets(
      'enforces compact tier select, U-LAYOUT-004 inline filter placement, and Quick-Add collapse across 390/720/721/820/1280',
      (tester) async {
        const label = TdfLabel(id: 'lbl_work', name: 'Work', color: '#2196F3');
        final focusTask = TaskItem(
          id: 'tsk_focus',
          title: 'Write release notes',
          labelIds: const <String>['lbl_work'],
        );
        final board = _buildBoard(
          tasks: <TaskItem>[focusTask],
          labels: <TdfLabel>[label],
        );

        for (final width in <double>[390.0, 720.0, 721.0, 820.0, 1280.0]) {
          final isCompact = width <= 720.0;
          final size = Size(width, 860.0);
          _setViewport(tester, size);
          final container = await pumpV2Widget(
            tester,
            _TasksHarness(constrainToWidth: isCompact ? null : width - 244.0),
            board: board,
            nowUtc: _fixedNowUtc,
            surfaceSize: size,
          );

          container
              .read(appShellControllerProvider.notifier)
              .selectLabelFilter('lbl_work');
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason: 'Width $width must render without overflow exceptions',
          );
          expect(
            find.byKey(const ValueKey<String>('compact_tier_select')),
            isCompact ? findsOneWidget : findsNothing,
            reason:
                'Compact tier dropdown must appear iff width <= 720 (width=$width)',
          );

          final pageHeaderFinder = find.byKey(
            const ValueKey<String>('tasks_page_header'),
          );
          final inlineFilterInHeader = find.descendant(
            of: pageHeaderFinder,
            matching: find.text('Work'),
          );
          expect(
            inlineFilterInHeader,
            isCompact ? findsNothing : findsOneWidget,
            reason:
                'U-LAYOUT-004 hides inline header filter on compact Tasks view (width=$width)',
          );

          if (isCompact) {
            expect(
              find.text('+ New task'),
              findsOneWidget,
              reason:
                  'Compact viewport ($width) collapses Quick-Add to + New task',
            );
            expect(
              find.text('Open as draft'),
              findsNothing,
              reason: 'Expanded composer actions remain hidden while compact Quick-Add is collapsed',
            );

            // Opening Global Search hides compact tier dropdown and shows inline active filter.
            container.read(appShellControllerProvider.notifier).openSearch();
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey<String>('compact_tier_select')),
              findsNothing,
              reason: 'Compact tier select must hide during Global Search',
            );
            expect(
              inlineFilterInHeader,
              findsOneWidget,
              reason: 'U-LAYOUT-004 shows inline active-label filter inside compact Search heading',
            );
          } else {
            expect(
              find.text('+ New task'),
              findsNothing,
              reason:
                  'Desktop viewport ($width) keeps Quick-Add expanded permanently',
            );
            expect(
              find.text('Open as draft'),
              findsOneWidget,
              reason: 'Desktop Quick-Add exposes Open as draft button',
            );

            // Clicking inline active-label filter on desktop clears the label filter.
            await tester.tap(inlineFilterInHeader);
            await tester.pumpAndSettle();
            expect(
              container.read(appShellControllerProvider).activeLabelId,
              isNull,
              reason: 'Clicking desktop inline filter clears activeLabelId',
            );
          }
        }
      },
    );

    testWidgets(
      'compact tier dropdown switches tiers and + New task expands stacked composer',
      (tester) async {
        final focusTask = TaskItem(id: 'tsk_f', title: 'Focus item');
        final somedayTask = TaskItem(id: 'tsk_s', title: 'Someday item');
        final board = _buildBoard(
          tasks: <TaskItem>[focusTask, somedayTask],
          queueIds: const <String>['tsk_f'],
        );

        const compactSize = Size(390.0, 844.0);
        _setViewport(tester, compactSize);
        final container = await pumpV2Widget(
          tester,
          const _TasksHarness(),
          board: board,
          nowUtc: _fixedNowUtc,
          surfaceSize: compactSize,
        );

        expect(find.text('Focus item'), findsOneWidget);
        expect(find.text('Someday item'), findsNothing);

        await tester.tap(
          find.byKey(const ValueKey<String>('compact_tier_select')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Someday · 1').last);
        await tester.pumpAndSettle();

        expect(
          container.read(appShellControllerProvider).activeTier,
          equals(ShellTier.someday),
        );
        expect(find.text('Someday item'), findsOneWidget);

        await tester.tap(find.text('+ New task'));
        await tester.pumpAndSettle();

        expect(
          container.read(appShellControllerProvider).compactComposerOpen,
          isTrue,
        );
        expect(find.text('Open as draft'), findsOneWidget);
        expect(find.text('+ Add'), findsOneWidget);
      },
    );
  });

  group('TaskCard collapsed badges, overflow & context navigation', () {
    testWidgets(
      'renders assigned labels, primary badges, 3 capped secondary badges + "+N more" expanding card',
      (tester) async {
        const label = TdfLabel(id: 'lbl_ops', name: 'Ops', color: '#FF9100');
        final prereqTask = TaskItem(id: 'tsk_dep', title: 'Approve schema');
        final richTask = TaskItem(
          id: 'tsk_rich',
          title: 'Deploy migration',
          labelIds: const <String>['lbl_ops'],
          dueAt: DateTime.utc(2026, 11, 9, 10, 0),
          isPriority: true,
          isSuspendedForever: true,
          blockedByTaskIds: const <String>['tsk_dep'],
          conditions: <TaskCondition>[
            DayTaskCondition.fromWeekdays(const <int>[DateTime.monday]),
          ],
          subtasks: const <SubtaskItem>[
            SubtaskItem(title: 'Step 1', isCompleted: true),
            SubtaskItem(title: 'Step 2'),
          ],
          repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.weeks),
          note: 'Check rollback procedure',
          links: const <TaskLink>[
            TaskLink(title: 'Runbook', uri: 'https://example.com/runbook'),
          ],
          history: <TaskHistoryEntry>[
            TaskHistoryEntry(
              timestampUtc: DateTime.utc(2026, 11, 8, 9, 0),
              text: 'Prepared draft',
            ),
          ],
        );

        final board = _buildBoard(
          tasks: <TaskItem>[prereqTask, richTask],
          labels: <TdfLabel>[label],
          queueIds: const <String>['tsk_dep', 'tsk_rich'],
        );

        final container = await pumpV2Widget(
          tester,
          const _TasksHarness(),
          board: board,
          nowUtc: _fixedNowUtc,
        );

        // Rich task is suspended so it lands in Blocked tier.
        container
            .read(appShellControllerProvider.notifier)
            .selectTier(ShellTier.blocked);
        await tester.pumpAndSettle();

        final metadataFinder = find.byKey(
          const ValueKey<String>('task_collapsed_metadata_tsk_rich'),
        );
        expect(metadataFinder, findsOneWidget);

        // Verify strict U-CARD-005 order via rendered UiPill labels.
        final pills = tester
            .widgetList<UiPill>(
              find.descendant(
                of: metadataFinder,
                matching: find.byType(UiPill),
              ),
            )
            .toList(growable: false);

        expect(pills.length, equals(6));
        expect(pills[0].label, equals('Ops'));
        expect(pills[0].variant, equals(UiPillVariant.tag));
        expect(pills[1].label, startsWith('Overdue:'));
        expect(pills[1].tone, equals(UiPillTone.danger));
        expect(pills[2].label, equals('Priority'));
        expect(pills[2].tone, equals(UiPillTone.accent));
        expect(pills[3].label, equals('Suspended indefinitely'));
        expect(pills[4].label, equals('0/1 prerequisites'));
        // 9 total secondary badges -> 3 visible + "+6 more".
        expect(pills[5].label, equals('+6 more'));

        // Clicking the label chip navigates to Labels manager preserving returnContext.
        await tester.tap(
          find.byKey(
            const ValueKey<String>('task_label_chip_tsk_rich_lbl_ops'),
          ),
        );
        await tester.pumpAndSettle();

        final shellAfterNav = container.read(appShellControllerProvider);
        expect(shellAfterNav.view, equals(ShellView.labels));
        expect(
          shellAfterNav.expandedEntity,
          equals(const EntityRef(kind: EntityKind.label, id: 'lbl_ops')),
        );
        expect(shellAfterNav.returnContext, isNotNull);
        expect(shellAfterNav.returnContext?.tier, equals(ShellTier.blocked));

        // Navigate back and verify clicking "+6 more" expands the task card.
        container
            .read(appShellControllerProvider.notifier)
            .navigateBackFromReturnContext();
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('task_more_badges_tsk_rich')),
        );
        await tester.pumpAndSettle();

        expect(
          container.read(appShellControllerProvider).expandedEntity,
          equals(const EntityRef(kind: EntityKind.task, id: 'tsk_rich')),
        );
        expect(metadataFinder, findsNothing);
      },
    );

    testWidgets(
      'displays Tier primary badge ahead of Due during Global Search',
      (tester) async {
        final task = TaskItem(
          id: 'tsk_search',
          title: 'Audit firewall',
          dueAt: DateTime.utc(2026, 11, 20, 12, 0),
        );
        final board = _buildBoard(tasks: <TaskItem>[task]);

        final container = await pumpV2Widget(
          tester,
          const _TasksHarness(),
          board: board,
          nowUtc: _fixedNowUtc,
        );

        container.read(appShellControllerProvider.notifier).openSearch();
        await tester.pumpAndSettle();

        final metadataFinder = find.byKey(
          const ValueKey<String>('task_collapsed_metadata_tsk_search'),
        );
        final pills = tester
            .widgetList<UiPill>(
              find.descendant(
                of: metadataFinder,
                matching: find.byType(UiPill),
              ),
            )
            .toList(growable: false);

        expect(pills.length, equals(2));
        expect(pills[0].label, equals('Focus'));
        expect(pills[0].tone, equals(UiPillTone.soft));
        expect(pills[1].label, startsWith('Due:'));
      },
    );
  });

  group('Single-expand accordion, live controls & inline editors', () {
    testWidgets(
      'enforces single-expand, populated-only sections, live subtasks, placement switch, and History CRUD',
      (tester) async {
        final taskA = TaskItem(
          id: 'tsk_a',
          title: 'Task Alpha',
          subtasks: const <SubtaskItem>[
            SubtaskItem(title: 'First step'),
            SubtaskItem(title: 'Second step'),
          ],
        );
        final taskB = TaskItem(id: 'tsk_b', title: 'Task Beta');
        final board = _buildBoard(tasks: <TaskItem>[taskA, taskB]);

        await pumpV2Widget(
          tester,
          const _TasksHarness(),
          board: board,
          nowUtc: _fixedNowUtc,
        );

        // Expand Task Alpha.
        await tester.tap(find.text('Task Alpha'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('task_expanded_panel_tsk_a')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('task_subtasks_read_tsk_a')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('task_history_section_tsk_a')),
          findsOneWidget,
        );
        // Unpopulated sections must be omitted and surfaced as + Add chips.
        expect(
          find.byKey(const ValueKey<String>('task_due_read_tsk_a')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('task_add_due_tsk_a')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('task_direct_priority_tsk_a')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('task_direct_someday_tsk_a')),
          findsOneWidget,
        );

        // Live subtask checkbox commits immediately without Save/Cancel.
        await tester.tap(
          find.byKey(const ValueKey<String>('task_subtask_toggle_tsk_a_0')),
        );
        await tester.pumpAndSettle();
        expect(find.text('1 of 2 completed'), findsOneWidget);

        // Live History add, inline edit, and delete.
        final historyInput = find.descendant(
          of: find.byKey(const ValueKey<String>('history_add_text_tsk_a')),
          matching: find.byType(TextField),
        );
        await tester.enterText(historyInput, 'Started work');
        await tester.tap(
          find.byKey(const ValueKey<String>('history_add_button_tsk_a')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Started work'), findsOneWidget);
        expect(find.text('1 / 500'), findsOneWidget);

        // Toggle clock override field and verify duplicate validation rejects identical entry.
        await tester.tap(
          find.byKey(const ValueKey<String>('history_timestamp_toggle_tsk_a')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('history_add_timestamp_tsk_a')),
          findsOneWidget,
        );

        // Inline edit history entry.
        await tester.tap(find.byTooltip('Edit history entry'));
        await tester.pumpAndSettle();
        final editHistoryInput = find.descendant(
          of: find.byKey(const ValueKey<String>('history_edit_text_tsk_a_0')),
          matching: find.byType(TextField),
        );
        await tester.enterText(editHistoryInput, 'Finished phase one');
        await tester.tap(
          find.byKey(const ValueKey<String>('history_edit_save_tsk_a_0')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Finished phase one'), findsOneWidget);

        // Delete history entry.
        await tester.tap(find.byTooltip('Delete history entry'));
        await tester.pumpAndSettle();
        expect(find.text('Finished phase one'), findsNothing);
        expect(find.text('0 / 500'), findsOneWidget);

        // Direct 1-click Priority toggle promotes task and reveals Queue & Priority segmented control.
        final directPriority = find.byKey(
          const ValueKey<String>('task_direct_priority_tsk_a'),
        );
        await tester.ensureVisible(directPriority);
        await tester.tap(directPriority);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('task_placement_section_tsk_a')),
          findsOneWidget,
        );

        // Expanding Task Beta automatically collapses Task Alpha (strict single-expand).
        final taskBetaFinder = find.text('Task Beta');
        await tester.drag(
          find.byKey(const ValueKey<String>('tasks_scroll_view')),
          const Offset(0.0, -300.0),
        );
        await tester.pumpAndSettle();
        await tester.tap(taskBetaFinder);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('task_expanded_panel_tsk_a')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('task_expanded_panel_tsk_b')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'supports inline title editing, Repeat lead-days due gate, Suspended 2-way toggle, and Prerequisites cycle guard',
      (tester) async {
        final taskA = TaskItem(id: 'tsk_a', title: 'Base Task');
        final taskB = TaskItem(
          id: 'tsk_b',
          title: 'Dependent Task',
          blockedByTaskIds: const <String>['tsk_a'],
        );
        final board = _buildBoard(
          tasks: <TaskItem>[taskA, taskB],
          queueIds: const <String>['tsk_a', 'tsk_b'],
        );

        final container = await pumpV2Widget(
          tester,
          const _TasksHarness(),
          board: board,
          nowUtc: _fixedNowUtc,
        );

        await tester.tap(find.text('Base Task'));
        await tester.pumpAndSettle();

        // Inline title editor rejects duplicate title inline, then saves valid title on Enter.
        await tester.tap(
          find.byKey(const ValueKey<String>('task_edit_title_tsk_a')),
        );
        await tester.pumpAndSettle();
        final titleField = find.descendant(
          of: find.byKey(
            const ValueKey<String>('task_title_editor_input_tsk_a'),
          ),
          matching: find.byType(TextField),
        );
        await tester.enterText(titleField, 'Dependent Task');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(
          find.text('A task with this name already exists.'),
          findsOneWidget,
        );

        await tester.enterText(titleField, 'Base Task Renamed');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(find.text('Base Task Renamed'), findsOneWidget);

        // Open Repeat inline editor without a due date -> shows lead-days needs due hint.
        await tester.tap(
          find.byKey(const ValueKey<String>('task_add_repeat_tsk_a')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Set a due date to configure preparation lead days.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Open Prerequisites editor -> Dependent Task would create a cycle and shows Cycle prevented.
        await tester.tap(
          find.byKey(const ValueKey<String>('task_add_prerequisites_tsk_a')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Dependent Task'), findsOneWidget);
        expect(find.text('Cycle prevented'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Open Suspended editor -> switch to Indefinitely and save -> task moves to Blocked tier.
        await tester.tap(
          find.byKey(const ValueKey<String>('task_add_suspended_tsk_a')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Indefinitely'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        final updatedBoard = container.read(taskNotifierProvider).value;
        expect(updatedBoard?.findTask('tsk_a')?.isSuspendedForever, isTrue);
      },
    );

    testWidgets(
      'supports inline Subtasks auto-finish, Due save/clear, Downgrade chevron, inline Delete confirm, and History timestamp toggle + duplicate guard',
      (tester) async {
        final taskOne = TaskItem(id: 'tsk_one', title: 'Ship v2 UI');
        final taskTwo = TaskItem(id: 'tsk_two', title: 'Write changelog');
        final taskThree = TaskItem(id: 'tsk_three', title: 'Publish release');
        final taskFour = TaskItem(id: 'tsk_four', title: 'Verify checksums');
        final board = _buildBoard(
          tasks: <TaskItem>[taskOne, taskTwo, taskThree, taskFour],
          queueIds: const <String>[
            'tsk_one',
            'tsk_two',
            'tsk_three',
            'tsk_four',
          ],
        );

        final container = await pumpV2Widget(
          tester,
          const _TasksHarness(),
          board: board,
          nowUtc: _fixedNowUtc,
        );

        // Downgrade chevron on Focus task moves it out of Focus to Ready.
        final downgradeButton = find.byKey(
          const ValueKey<String>('task_downgrade_tsk_one'),
        );
        expect(downgradeButton, findsOneWidget);
        await tester.tap(downgradeButton);
        await tester.pumpAndSettle();
        expect(
          container
              .read(taskNotifierProvider)
              .value
              ?.focus
              .any((item) => item.id == 'tsk_one'),
          isFalse,
        );

        // Expand second task and configure Due date + note, save, then clear.
        await tester.tap(find.text('Write changelog'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('task_add_due_tsk_two')),
        );
        await tester.pumpAndSettle();
        final dueFields = find.descendant(
          of: find.byKey(const ValueKey<String>('task_due_edit_card')),
          matching: find.byType(TextField),
        );
        await tester.enterText(dueFields.first, '2026-11-12 09:30');
        await tester.enterText(dueFields.last, 'Before release cut');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('task_due_read_tsk_two')),
          findsOneWidget,
        );
        expect(find.text('Before release cut'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey<String>('task_due_edit_button_tsk_two')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('task_due_read_tsk_two')),
          findsNothing,
        );

        // Toggle History clock icon, add timestamped entry, then verify duplicate rejection inline.
        final clockToggle = find.byKey(
          const ValueKey<String>('history_timestamp_toggle_tsk_two'),
        );
        await tester.ensureVisible(clockToggle);
        await tester.tap(clockToggle);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('history_add_timestamp_tsk_two')),
          findsOneWidget,
        );
        final historyTextField = find.descendant(
          of: find.byKey(const ValueKey<String>('history_add_text_tsk_two')),
          matching: find.byType(TextField),
        );
        await tester.enterText(historyTextField, 'Drafted summary');
        await tester.tap(
          find.byKey(const ValueKey<String>('history_add_button_tsk_two')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Drafted summary'), findsOneWidget);

        await tester.enterText(historyTextField, 'Drafted summary');
        await tester.tap(
          find.byKey(const ValueKey<String>('history_add_button_tsk_two')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            'An identical history entry with this timestamp already exists.',
          ),
          findsOneWidget,
        );

        // Configure Subtasks with Auto-finish via inline editor, save, and auto-complete on last check.
        final addSubtasksChip = find.byKey(
          const ValueKey<String>('task_add_subtasks_tsk_two'),
        );
        await tester.ensureVisible(addSubtasksChip);
        await tester.tap(addSubtasksChip);
        await tester.pumpAndSettle();
        final subtaskInput = find.descendant(
          of: find.byKey(const ValueKey<String>('subtask_add_input_tsk_two')),
          matching: find.byType(TextField),
        );
        await tester.enterText(subtaskInput, 'Only step');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey<String>('subtask_auto_finish_toggle_tsk_two'),
          ),
        );
        await tester.pumpAndSettle();
        final saveSubtasksButton = find.text('Save');
        await tester.ensureVisible(saveSubtasksButton);
        await tester.tap(saveSubtasksButton);
        await tester.pumpAndSettle();

        final onlyStepCheckbox = find.byKey(
          const ValueKey<String>('task_subtask_toggle_tsk_two_0'),
        );
        await tester.ensureVisible(onlyStepCheckbox);
        await tester.tap(onlyStepCheckbox);
        await tester.pumpAndSettle();
        expect(
          container
              .read(taskNotifierProvider)
              .value
              ?.findTask('tsk_two')
              ?.isCompleted,
          isTrue,
        );

        // Inline Delete confirmation removes task from board.
        await tester.tap(find.text('Publish release'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Yes, delete'));
        await tester.pumpAndSettle();
        expect(
          container.read(taskNotifierProvider).value?.findTask('tsk_three'),
          isNull,
        );
      },
    );

    testWidgets(
      'uses inline searchable Labels picker on desktop, bottom sheet on compact, and routes Label/Location chips with returnContext',
      (tester) async {
        const label = TdfLabel(
          id: 'lbl_ctx',
          name: 'Backend',
          color: '#2196F3',
        );
        const location = TdfLocation(
          id: 'loc_office',
          name: 'Office HQ',
          latitude: 48.1351,
          longitude: 11.582,
          radius: 200,
        );
        final task = TaskItem(
          id: 'tsk_ctx',
          title: 'Review API contract',
          labelIds: const <String>['lbl_ctx'],
          conditions: const <TaskCondition>[
            LocationTaskCondition(locationIds: <String>['loc_office']),
          ],
        );
        final board = _buildBoard(
          tasks: <TaskItem>[task],
          labels: const <TdfLabel>[label],
          locations: const <TdfLocation>[location],
        );

        // Desktop: collapsed label chip navigates to Labels manager preserving returnContext.
        const desktopSize = Size(1280.0, 860.0);
        _setViewport(tester, desktopSize);
        final desktopContainer = await pumpV2Widget(
          tester,
          const _TasksHarness(),
          board: board,
          nowUtc: _fixedNowUtc,
          surfaceSize: desktopSize,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('task_label_chip_tsk_ctx_lbl_ctx')),
        );
        await tester.pumpAndSettle();
        expect(
          desktopContainer.read(appShellControllerProvider).view,
          equals(ShellView.labels),
        );
        expect(
          desktopContainer.read(appShellControllerProvider).returnContext,
          isNotNull,
        );

        // Return to Tasks, expand card, open desktop inline Labels picker, and tap Location chip.
        desktopContainer
            .read(appShellControllerProvider.notifier)
            .openView(ShellView.tasks);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Review API contract'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('task_labels_add_button_tsk_ctx')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('task_labels_picker_tsk_ctx')),
          findsOneWidget,
        );
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();

        final locationPill = find.text('Office HQ');
        await tester.ensureVisible(locationPill);
        await tester.tap(locationPill);
        await tester.pumpAndSettle();
        expect(
          desktopContainer.read(appShellControllerProvider).view,
          equals(ShellView.locations),
        );
        expect(
          desktopContainer.read(appShellControllerProvider).returnContext,
          isNotNull,
        );

        // Compact (390px): Labels Add opens compact modal bottom sheet rather than inline picker.
        const compactSize = Size(390.0, 844.0);
        _setViewport(tester, compactSize);
        await pumpV2Widget(
          tester,
          const _TasksHarness(),
          board: board,
          nowUtc: _fixedNowUtc,
          surfaceSize: compactSize,
        );
        await tester.tap(find.text('Review API contract'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('task_labels_add_button_tsk_ctx')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('task_labels_picker_tsk_ctx')),
          findsNothing,
        );
        expect(find.byType(UiSearchablePicker<String>), findsOneWidget);
      },
    );
  });

  group('Completed task read-only mode (U-CARD-004)', () {
    testWidgets(
      'hides edit pencils and + Add bar, disables subtasks, while keeping Restore, Copy ID, Delete, and live History',
      (tester) async {
        const label = TdfLabel(id: 'lbl_home', name: 'Home', color: '#4CAF50');
        final completedTask = TaskItem(
          id: 'tsk_done',
          title: 'Pay electric bill',
          isCompleted: true,
          completedAt: DateTime.utc(2026, 11, 9, 15, 0),
          labelIds: const <String>['lbl_home'],
          note: 'Paid via online banking',
          subtasks: const <SubtaskItem>[
            SubtaskItem(title: 'Download invoice', isCompleted: true),
          ],
          history: <TaskHistoryEntry>[
            TaskHistoryEntry(
              timestampUtc: DateTime.utc(2026, 11, 9, 14, 0),
              text: 'Received bill',
            ),
          ],
        );
        final board = _buildBoard(
          tasks: <TaskItem>[completedTask],
          labels: <TdfLabel>[label],
          queueIds: const <String>[],
        );

        String? copiedClipboardText;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                final args = call.arguments;
                if (args is Map<Object?, Object?>) {
                  copiedClipboardText = args['text'] as String?;
                }
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        final container = await pumpV2Widget(
          tester,
          const _TasksHarness(),
          board: board,
          nowUtc: _fixedNowUtc,
        );

        container
            .read(appShellControllerProvider.notifier)
            .selectTier(ShellTier.completed);
        await tester.pumpAndSettle();

        // Downgrade button must be hidden on completed tasks.
        expect(
          find.byKey(const ValueKey<String>('task_downgrade_tsk_done')),
          findsNothing,
        );

        await tester.tap(find.text('Pay electric bill'));
        await tester.pumpAndSettle();

        expect(find.text('Completed · restore task to edit'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('task_edit_title_tsk_done')),
          findsNothing,
        );
        expect(
          find.byKey(
            const ValueKey<String>('task_subtasks_edit_button_tsk_done'),
          ),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('task_add_fields_bar_tsk_done')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('task_labels_add_button_tsk_done')),
          findsNothing,
        );

        // Subtask checkbox is disabled on completed tasks.
        await tester.tap(
          find.byKey(const ValueKey<String>('task_subtask_toggle_tsk_done_0')),
        );
        await tester.pumpAndSettle();
        expect(
          container
              .read(taskNotifierProvider)
              .value
              ?.findTask('tsk_done')
              ?.subtasks
              .first
              .isCompleted,
          isTrue,
        );

        // Copy ID remains interactive.
        await tester.tap(find.byTooltip('Copy task ID'));
        await tester.pumpAndSettle();
        expect(copiedClipboardText, equals('tsk_done'));

        // Live History remains fully interactive even on Completed tasks!
        final historyField = find.descendant(
          of: find.byKey(const ValueKey<String>('history_add_text_tsk_done')),
          matching: find.byType(TextField),
        );
        await tester.ensureVisible(historyField);
        await tester.enterText(historyField, 'Archived receipt');
        await tester.tap(
          find.byKey(const ValueKey<String>('history_add_button_tsk_done')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Archived receipt'), findsOneWidget);

        // Restore circle button restores the completed task.
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('task_complete_tsk_done')),
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('task_complete_tsk_done')),
        );
        await tester.pumpAndSettle();

        expect(
          container
              .read(taskNotifierProvider)
              .value
              ?.findTask('tsk_done')
              ?.isCompleted,
          isFalse,
        );
      },
    );
  });

  group('Non-jumping Quick-Add & uncommitted Draft Card (U-CARD-006)', () {
    testWidgets(
      'adds task without switching tiers, preserves duplicate title, and seeds active label filter',
      (tester) async {
        const label = TdfLabel(id: 'lbl_dev', name: 'Dev', color: '#2196F3');
        final existingTask = TaskItem(
          id: 'tsk_existing',
          title: 'Existing Task',
          labelIds: const <String>['lbl_dev'],
        );
        final board = _buildBoard(
          tasks: <TaskItem>[existingTask],
          labels: <TdfLabel>[label],
        );

        final container = await pumpV2Widget(
          tester,
          const _TasksHarness(),
          board: board,
          nowUtc: _fixedNowUtc,
        );

        // Select label filter and switch to Completed tier.
        container
            .read(appShellControllerProvider.notifier)
            .selectLabelFilter('lbl_dev');
        container
            .read(appShellControllerProvider.notifier)
            .selectTier(ShellTier.completed);
        await tester.pumpAndSettle();

        // Active label filter auto-seeded Quick-Add draft label chip.
        expect(
          find.byKey(const ValueKey<String>('quick_add_label_chip_lbl_dev')),
          findsOneWidget,
        );

        final composerField = find.descendant(
          of: find.byKey(const ValueKey<String>('tasks_quick_add_composer')),
          matching: find.byType(TextField),
        );

        // Duplicate title triggers danger notice and preserves typed input.
        await tester.enterText(composerField, 'Existing Task');
        await tester.tap(find.text('+ Add'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(composerField).controller?.text,
          equals('Existing Task'),
        );
        expect(
          container.read(floatingNoticeControllerProvider)?.tone,
          equals(NoticeTone.danger),
        );

        // Unique title adds task, clears input, does NOT switch away from Completed tier or expand task.
        await tester.enterText(composerField, 'New Feature Spec');
        await tester.tap(find.text('+ Add'));
        await tester.pumpAndSettle();

        expect(
          tester.widget<TextField>(composerField).controller?.text,
          isEmpty,
        );
        expect(
          container.read(appShellControllerProvider).activeTier,
          equals(ShellTier.completed),
        );
        expect(
          container.read(appShellControllerProvider).expandedEntity,
          isNull,
        );
        final created = container
            .read(taskNotifierProvider)
            .value
            ?.allTasks
            .where((item) => item.title == 'New Feature Spec')
            .toList(growable: false);
        expect(created?.length, equals(1));
        expect(created?.first.labelIds, contains('lbl_dev'));

        // Clearing active label filter resets Quick-Add draft labels (U-LAYOUT-004).
        container
            .read(appShellControllerProvider.notifier)
            .selectLabelFilter(null);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('quick_add_label_chip_lbl_dev')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Open as draft opens TaskDraftCard seeded from Quick-Add, hides composer, and commits full task',
      (tester) async {
        final board = _buildBoard();
        final container = await pumpV2Widget(
          tester,
          const _TasksHarness(),
          board: board,
          nowUtc: _fixedNowUtc,
        );

        final composerField = find.descendant(
          of: find.byKey(const ValueKey<String>('tasks_quick_add_composer')),
          matching: find.byType(TextField),
        );
        await tester.enterText(composerField, 'Plan architecture');
        await tester.tap(find.text('Open as draft'));
        await tester.pumpAndSettle();

        // Draft Card is visible and Quick-Add composer is hidden.
        expect(
          find.byKey(const ValueKey<String>('task_draft_card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('tasks_quick_add_composer')),
          findsNothing,
        );

        final draftTitleField = find.descendant(
          of: find.byKey(const ValueKey<String>('task_draft_title_input')),
          matching: find.byType(TextField),
        );
        expect(
          tester.widget<TextField>(draftTitleField).controller?.text,
          equals('Plan architecture'),
        );

        // Open optional Note section inside Draft Card and enter a note.
        await tester.tap(
          find.byKey(const ValueKey<String>('draft_add_note_chip')),
        );
        await tester.pumpAndSettle();
        final draftNoteField = find.descendant(
          of: find.byKey(const ValueKey<String>('draft_note_card')),
          matching: find.byType(TextField),
        );
        await tester.enterText(draftNoteField, 'Include dependency DAG');

        // Commit draft.
        final createButton = find.byKey(
          const ValueKey<String>('task_draft_create_button'),
        );
        await tester.ensureVisible(createButton);
        await tester.tap(createButton);
        await tester.pumpAndSettle();

        // Draft closes, Quick-Add composer reappears, and task is persisted.
        expect(
          find.byKey(const ValueKey<String>('task_draft_card')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('tasks_quick_add_composer')),
          findsOneWidget,
        );
        final savedBoard = container.read(taskNotifierProvider).value;
        final savedTask = savedBoard?.allTasks
            .where((item) => item.title == 'Plan architecture')
            .firstOrNull;
        expect(savedTask, isNotNull);
        expect(savedTask?.note, equals('Include dependency DAG'));

        // Cancelling a Draft Card closes it and restores TasksQuickAddDock without persisting.
        await tester.tap(find.text('Open as draft'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('task_draft_card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('tasks_quick_add_composer')),
          findsNothing,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('task_draft_card')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('tasks_quick_add_composer')),
          findsOneWidget,
        );
      },
    );
  });

  group('Operational states & status banners (U-UX-007)', () {
    testWidgets(
      'renders initial loading banner and hides Quick-Add composer until board resolves',
      (tester) async {
        final completer = Completer<TaskBoard>();
        await pumpV2Widget(
          tester,
          const _TasksHarness(),
          taskNotifierFactory: () => _CompleterTaskNotifier(completer),
          settle: false,
        );

        expect(
          find.byKey(const ValueKey<String>('tasks_loading_banner')),
          findsOneWidget,
        );
        expect(find.text('Loading workspace...'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('tasks_quick_add_composer')),
          findsNothing,
        );

        completer.complete(_buildBoard());
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('tasks_loading_banner')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('tasks_quick_add_composer')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'renders full-screen file-read error with diagnostics, Settings route, Retry action, and hidden composer',
      (tester) async {
        var attempts = 0;
        const report = StorageFileReadReport(
          local: StorageFileReadStatus.unreadable(
            StorageFileTarget.local,
            detail: 'Unexpected token',
            line: 4,
          ),
          remote: StorageFileReadStatus.unsupportedVersion(
            StorageFileTarget.remote,
            version: '9.0.0',
          ),
        );
        const failure = StorageFileReadException(
          'Both files failed',
          report: report,
        );

        final container = await pumpV2Widget(
          tester,
          const _TasksHarness(),
          taskNotifierFactory: () => _FailingTaskNotifier(
            error: failure,
            onBuildAttempt: () => attempts++,
          ),
        );

        expect(
          find.byKey(const ValueKey<String>('tasks_full_error_banner')),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const ValueKey<String>('tasks_full_error_diagnostics_card'),
          ),
          findsOneWidget,
        );
        expect(find.text('Local file'), findsOneWidget);
        expect(find.text('Remote file'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('tasks_quick_add_composer')),
          findsNothing,
        );

        final attemptsBeforeRetry = attempts;
        await tester.tap(
          find.byKey(const ValueKey<String>('tasks_full_error_retry_button')),
        );
        await tester.pumpAndSettle();
        expect(attempts, greaterThan(attemptsBeforeRetry));

        await tester.tap(
          find.byKey(
            const ValueKey<String>('tasks_full_error_settings_button'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).view,
          equals(ShellView.settings),
        );
      },
    );

    testWidgets(
      'renders unconfigured WebDAV, dismissible sync error, partial file read, conflict, and recovery banners',
      (tester) async {
        var syncTriggered = 0;
        final container = await pumpV2Widget(
          tester,
          const _TasksHarness(),
          config: const WebDavConfig(
            storageMode: StorageMode.both,
            language: AppLanguage.english,
          ),
          taskNotifierFactory: () => _SpySyncTaskNotifier(
            _buildBoard(),
            onSync: () => syncTriggered++,
          ),
        );

        // 1. Unconfigured WebDAV banner routes Configure -> Settings.
        expect(
          find.byKey(
            const ValueKey<String>('tasks_status_banner_unconfiguredWebDav'),
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Configure'));
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).view,
          equals(ShellView.settings),
        );
        container
            .read(appShellControllerProvider.notifier)
            .openView(ShellView.tasks);
        await tester.pumpAndSettle();

        // 2. Sync error banner supports Retry and Dismiss.
        container
            .read(syncStateProvider.notifier)
            .setError('Connection timed out');
        await tester.pumpAndSettle();
        final syncBannerFinder = find.byKey(
          const ValueKey<String>('tasks_status_banner_syncError'),
        );
        expect(syncBannerFinder, findsOneWidget);

        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(syncTriggered, equals(1));

        await tester.tap(
          find.descendant(
            of: syncBannerFinder,
            matching: find.byTooltip('Dismiss'),
          ),
        );
        await tester.pumpAndSettle();
        expect(syncBannerFinder, findsNothing);

        // 3. Partial file-read banner renders sublines and dismisses cleanly.
        container
            .read(syncStateProvider.notifier)
            .setError(
              'Local failed',
              fileReadReport: const StorageFileReadReport(
                local: StorageFileReadStatus.unreadable(
                  StorageFileTarget.local,
                  detail: 'Corrupt header',
                  line: 1,
                ),
                remote: StorageFileReadStatus.readable(
                  StorageFileTarget.remote,
                ),
              ),
            );
        await tester.pumpAndSettle();
        final partialBannerFinder = find.byKey(
          const ValueKey<String>('tasks_status_banner_partialFileRead'),
        );
        expect(partialBannerFinder, findsOneWidget);
        await tester.tap(
          find.descendant(
            of: partialBannerFinder,
            matching: find.byTooltip('Dismiss'),
          ),
        );
        await tester.pumpAndSettle();
        expect(partialBannerFinder, findsNothing);

        // 4. Deletion conflict banner routes Resolve conflict -> ShellView.conflict.
        container
            .read(syncStateProvider.notifier)
            .setConflict(
              'Deletion conflict',
              outcome: const TdfSyncOutcomeException(
                kind: TdfSyncOutcomeKind.deletionConflict,
                message: 'Deletion conflict',
                conflictedTaskIds: <String>['tsk_c1'],
              ),
            );
        await tester.pumpAndSettle();
        expect(
          find.byKey(
            const ValueKey<String>('tasks_status_banner_deletionConflict'),
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Resolve conflict'));
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).view,
          equals(ShellView.conflict),
        );

        // 5. Recovery required banner routes Open recovery -> ShellView.recovery.
        container
            .read(appShellControllerProvider.notifier)
            .openView(ShellView.tasks);
        container
            .read(syncStateProvider.notifier)
            .setConflict(
              'Recovery required',
              outcome: const TdfSyncOutcomeException(
                kind: TdfSyncOutcomeKind.recoveryRequired,
                message: 'Recovery required',
                ambiguousTaskIds: <String>['tsk_r1'],
              ),
            );
        await tester.pumpAndSettle();
        expect(
          find.byKey(
            const ValueKey<String>('tasks_status_banner_recoveryRequired'),
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Open recovery'));
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).view,
          equals(ShellView.recovery),
        );
      },
    );
  });
}
