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

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/local_file_watch_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/tdf_service.dart';
import 'package:tiertask/ui/widgets/task_info_dialog.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'TaskInfoDialog formats indefinite, multi-day, multi-hour, and minute-only suspension durations and hides expired suspension',
    (WidgetTester tester) async {
      final now = DateTime.utc(2026, 11, 1, 12, 0);
      const config = WebDavConfig(
        language: AppLanguage.english,
        timeZoneMode: AppTimeZoneMode.manual,
        manualTimeZoneOffsetMinutes: 0,
      );

      final foreverTask = TaskItem(
        id: 'suspFor001',
        title: 'Indefinite Suspended Task',
        createdAt: now,
        isSuspendedForever: true,
      );
      await pumpLeafWidget(
        tester,
        TaskInfoDialog(
          task: foreverTask,
          initialIndicatorKeyPrefix: 'suspended_task_indicator',
        ),
        board: TaskBoard(blocked: [foreverTask]),
        config: config,
        clock: () => now,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Task Information'),
        findsOneWidget,
        reason: 'Dialog header must show localized Task Information title',
      );
      expect(find.text('Indefinite Suspended Task'), findsOneWidget);
      expect(
        find.text('Indefinitely'),
        findsOneWidget,
        reason: 'Indefinite suspension must display Indefinitely',
      );

      final daysHoursTask = TaskItem(
        id: 'suspDay002',
        title: 'Days And Hours Suspended Task',
        createdAt: now,
        suspendedAt: DateTime.utc(2026, 11, 4, 15, 0),
      );
      await pumpLeafWidget(
        tester,
        TaskInfoDialog(task: daysHoursTask),
        board: TaskBoard(blocked: [daysHoursTask]),
        config: config,
        clock: () => now,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Until 2026-11-04 15:00 (3 d 3 h remaining)'),
        findsOneWidget,
        reason: 'Multi-day suspension must display target timestamp and days/hours remaining',
      );

      final hoursMinutesTask = TaskItem(
        id: 'suspHrs003',
        title: 'Hours And Minutes Suspended Task',
        createdAt: now,
        suspendedAt: DateTime.utc(2026, 11, 1, 14, 30),
      );
      await pumpLeafWidget(
        tester,
        TaskInfoDialog(task: hoursMinutesTask),
        board: TaskBoard(blocked: [hoursMinutesTask]),
        config: config,
        clock: () => now,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Until 2026-11-01 14:30 (2 h 30 min remaining)'),
        findsOneWidget,
        reason: 'Same-day multi-hour suspension must display hours and minutes remaining',
      );

      final minutesOnlyTask = TaskItem(
        id: 'suspMin004',
        title: 'Minutes Only Suspended Task',
        createdAt: now,
        suspendedAt: DateTime.utc(2026, 11, 1, 12, 45),
      );
      await pumpLeafWidget(
        tester,
        TaskInfoDialog(task: minutesOnlyTask),
        board: TaskBoard(blocked: [minutesOnlyTask]),
        config: config,
        clock: () => now,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Until 2026-11-01 12:45 (45 min remaining)'),
        findsOneWidget,
        reason: 'Sub-hour suspension must display minutes remaining',
      );

      final elapsedTask = TaskItem(
        id: 'suspElp005',
        title: 'Elapsed Suspended Task',
        createdAt: now,
        suspendedAt: DateTime.utc(2026, 10, 31, 10, 0),
      );
      await pumpLeafWidget(
        tester,
        TaskInfoDialog(task: elapsedTask),
        board: TaskBoard(focus: [elapsedTask]),
        config: config,
        clock: () => now,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('task_info_section_suspended_task_indicator'),
        ),
        findsNothing,
        reason:
            'Past suspension timestamp <= nowUtc must hide Suspended section',
      );
      expect(
        find.text('Suspended'),
        findsNothing,
        reason: 'Past suspension timestamp must not render Suspended header',
      );

      final exactBoundaryTask = TaskItem(
        id: 'suspBnd006',
        title: 'Boundary Suspended Task',
        createdAt: now,
        suspendedAt: now,
      );
      await pumpLeafWidget(
        tester,
        TaskInfoDialog(task: exactBoundaryTask),
        board: TaskBoard(focus: [exactBoundaryTask]),
        config: config,
        clock: () => now,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('task_info_section_suspended_task_indicator'),
        ),
        findsNothing,
        reason:
            'Exact suspendedAt == nowUtc boundary must hide Suspended section',
      );
    },
  );

  testWidgets(
    'TaskInfoDialog renders subtasks completion progress, auto-finish status, prerequisites, conditions, repeat, due, labels, note, and links',
    (WidgetTester tester) async {
      final now = DateTime.utc(2026, 11, 1, 12, 0);
      const config = WebDavConfig(
        language: AppLanguage.english,
        timeZoneMode: AppTimeZoneMode.manual,
        manualTimeZoneOffsetMinutes: 0,
      );
      const officeLocation = TdfLocation(
        id: 'locOffice1',
        name: 'Berlin Office',
        latitude: 52.52,
        longitude: 13.405,
        radius: 250,
      );
      const workLabel = TdfLabel(
        id: 'lblWork001',
        name: 'Engineering',
        color: '#2196F3',
      );
      final donePrereq = TaskItem(
        id: 'preDone001',
        title: 'Provision Database',
        createdAt: now,
        isCompleted: true,
        completedAt: now,
        completions: 1,
      );
      final openPrereq = TaskItem(
        id: 'preOpen002',
        title: 'Approve Firewall Rule',
        createdAt: now,
        completions: 0,
      );
      final fullTask = TaskItem(
        id: 'fullTsk001',
        title: 'Deploy Production Cluster',
        note: 'Coordinate rollout with SRE team',
        createdAt: now,
        isPriority: true,
        completions: 3,
        dueAt: DateTime.utc(2026, 11, 3, 18, 0),
        repeatRule: const TaskRepeatRule(count: 2, unit: RepeatUnit.weeks),
        labelIds: const ['lblWork001'],
        dependencies: const [
          TdfTaskDependency(taskId: 'preDone001', requiredCompletion: 1),
          TdfTaskDependency(taskId: 'preOpen002', requiredCompletion: 1),
        ],
        links: const [
          TaskLink(title: 'Runbook', uri: 'https://example.com/runbook'),
          TaskLink(title: 'Dashboard', uri: 'https://example.com/dash'),
        ],
        conditions: [
          DayTaskCondition.fromWeekdays(const [
            DateTime.monday,
            DateTime.wednesday,
          ]),
          const TimeWindowTaskCondition(
            startMinutes: 540,
            endMinutes: 1020,
            startToken: '09:00',
            endToken: '17:00',
          ),
          LocationTaskCondition.fromIds(const ['locOffice1']),
        ],
        subtasksAutoFinish: true,
        subtasks: const [
          SubtaskItem(title: 'Step 1', isCompleted: true),
          SubtaskItem(title: 'Step 2', isCompleted: false),
          SubtaskItem(title: 'Step 3', isCompleted: false),
          SubtaskItem(title: 'Step 4', isCompleted: false),
        ],
      );

      final board = TaskBoard(
        blocked: [fullTask],
        focus: [openPrereq],
        completed: [donePrereq],
        labels: const [workLabel],
        locations: const [officeLocation],
      );

      await pumpLeafWidget(
        tester,
        TaskInfoDialog(
          task: fullTask,
          initialIndicatorKeyPrefix: 'subtasks_task_indicator',
        ),
        board: board,
        config: config,
        clock: () => now,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('1 of 4 completed'),
        findsOneWidget,
        reason: 'Subtasks section must display 1 of 4 completed',
      );
      expect(
        find.text('Auto-finish enabled'),
        findsOneWidget,
        reason: 'Subtasks section must indicate when auto-finish is enabled',
      );
      final progressBar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progressBar.value, closeTo(0.25, 0.001));

      expect(find.text('Prioritized in queue'), findsOneWidget);
      expect(
        find.text('2026-11-03 18:00 (2 d 6 h remaining)'),
        findsOneWidget,
        reason: 'Due section must display deadline and remaining duration',
      );
      expect(
        find.text('1 of 2 satisfied'),
        findsOneWidget,
        reason: 'Prerequisite tasks section must display satisfied count',
      );
      expect(find.textContaining('Provision Database'), findsOneWidget);
      expect(find.textContaining('Approve Firewall Rule'), findsOneWidget);

      expect(find.textContaining('Mon, Wed'), findsOneWidget);
      expect(find.textContaining('09:00 - 17:00'), findsOneWidget);
      expect(find.textContaining('Berlin Office'), findsOneWidget);

      expect(find.textContaining('Every 2 Weeks'), findsOneWidget);
      expect(find.textContaining('Completed 3 times'), findsOneWidget);
      expect(find.text('Engineering'), findsOneWidget);
      expect(find.text('Coordinate rollout with SRE team'), findsOneWidget);
      expect(find.text('2 links'), findsOneWidget);
      expect(find.textContaining('Runbook'), findsOneWidget);
      expect(find.textContaining('Dashboard'), findsOneWidget);

      expect(
        find.byKey(const ValueKey('task_info_section_subtasks_task_indicator')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('task_info_dialog_close_button')),
        findsOneWidget,
      );

      final unblockedOneShotTask = TaskItem(
        id: 'unblkShot1',
        title: 'Satisfied Dependency Task',
        note: 'Already unblocked',
        createdAt: now,
        dependencies: const [
          TdfTaskDependency(taskId: 'preDone001', requiredCompletion: 1),
          TdfTaskDependency(taskId: 'delPrereq9', requiredCompletion: 1),
        ],
      );
      final boardWithTombstone = TaskBoard(
        focus: [unblockedOneShotTask, openPrereq],
        completed: [donePrereq],
        deletedBlock: TdfDeletedBlock(
          generation: 1,
          tasks: [
            TdfDeletedTaskRecord(
              taskId: 'delPrereq9',
              deletedAt: DateTime.utc(2026, 10, 30, 8, 0),
            ),
          ],
        ),
      );
      await pumpLeafWidget(
        tester,
        TaskInfoDialog(task: unblockedOneShotTask),
        board: boardWithTombstone,
        config: config,
        clock: () => now,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('task_info_section_blocked_by_task_indicator'),
        ),
        findsNothing,
        reason: 'TaskInfoDialog must hide Blocked By section when all dependencies are satisfied or tombstoned',
      );

      final mixedDeletedAndOpenTask = TaskItem(
        id: 'mixDelOpn2',
        title: 'Blocked With Deleted Sibling Prereq',
        createdAt: now,
        dependencies: const [
          TdfTaskDependency(taskId: 'delPrereq9', requiredCompletion: 1),
          TdfTaskDependency(taskId: 'preOpen002', requiredCompletion: 1),
        ],
      );
      await pumpLeafWidget(
        tester,
        TaskInfoDialog(task: mixedDeletedAndOpenTask),
        board: boardWithTombstone.copyWith(blocked: [mixedDeletedAndOpenTask]),
        config: config,
        clock: () => now,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('0 of 1 satisfied'),
        findsOneWidget,
        reason: 'Tombstoned prerequisite must be excluded from Blocked By progress count',
      );
      expect(
        find.textContaining('delPrereq9'),
        findsNothing,
        reason: 'Tombstoned prerequisite raw ID must not render in Blocked By details',
      );
      expect(find.textContaining('Approve Firewall Rule'), findsOneWidget);
    },
  );

  testWidgets(
    'TaskInfoDialog renders interactive label ActionChips stacking LabelHubDialog, reflects live edits and real Directory.watch external link updates/retirements, and preserves task undo entries across updateLabel',
    (WidgetTester tester) async {
      late Directory tempDir;
      late File tdfFile;
      await tester.runAsync(() async {
        tempDir = await Directory.systemTemp.createTemp(
          'tiertask_hub_watch_ui_',
        );
        tdfFile = File('${tempDir.path}/tasks.tdf');
        await tdfFile.writeAsString(
          'tdf 0.7.0\n\n'
          'queue {\n'
          '    modified 2026-11-11 12:00:00\n'
          '    task tskUndoOk1\n'
          '    task tskExecOk2\n'
          '}\n\n'
          'label lblOps0001 {\n'
          '    name     "Ops Runbook"\n'
          '    color    "#FF9800"\n'
          '    note     "Initial ops note"\n'
          '    modified 2026-11-11 12:00:00\n'
          '    link     "Dashboard" "https://ops.example.com/dash"\n'
          '}\n\n'
          'task tskUndoOk1 {\n'
          '    name     "Undoable Sibling Task"\n'
          '    created  2026-11-11 11:00:00\n'
          '    modified 2026-11-11 12:00:00\n'
          '}\n\n'
          'task tskExecOk2 {\n'
          '    name     "Deploy Service"\n'
          '    created  2026-11-11 11:05:00\n'
          '    modified 2026-11-11 12:00:00\n'
          '    labels   lblOps0001\n'
          '}\n',
          flush: true,
        );
      });
      addTearDown(() async {
        await tester.runAsync(() async {
          if (tempDir.existsSync()) {
            await tempDir.delete(recursive: true);
          }
        });
      });

      var currentTime = DateTime.utc(2026, 11, 11, 12, 0);
      const watchConfig = WebDavConfig(
        language: AppLanguage.english,
        storageMode: StorageMode.local,
        localFilePath: 'tasks.tdf',
        localWatchEnabled: true,
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(watchConfig),
          ),
          localStorageDirectoryPathProvider.overrideWithValue(tempDir.path),
          localFileWatchDebounceProvider.overrideWithValue(
            const Duration(milliseconds: 25),
          ),
          clockProvider.overrideWithValue(() => currentTime),
        ],
      );
      addTearDown(() async {
        await tester.runAsync(() async {
          container.dispose();
        });
      });
      late TaskItem deployTask;
      await tester.runAsync(() async {
        container.listen(
          localFileWatcherProvider,
          (_, _) {},
          fireImmediately: true,
        );
        final initialBoard = await container.read(taskNotifierProvider.future);
        deployTask = initialBoard.findTask('tskExecOk2')!;
        await Future<void>.delayed(const Duration(milliseconds: 60));

        // Complete sibling task tskUndoOk1 so an unrelated entry sits on the TEP-007 undo stack.
        currentTime = DateTime.utc(2026, 11, 11, 12, 0, 30);
        await container
            .read(taskNotifierProvider.notifier)
            .completeTask('tskUndoOk1');
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      expect(
        container.read(taskUndoStateProvider).canUndo,
        isTrue,
        reason: 'Completing sibling task must record an undo entry',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  key: const ValueKey('open_task_info_btn'),
                  onPressed: () =>
                      showTaskInfoDialog(context, task: deployTask),
                  child: const Text('Open Task Info'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open_task_info_btn')));
      await tester.pumpAndSettle();

      final chipFinder = find.byKey(
        const ValueKey('task_info_label_chip_lblOps0001'),
      );
      expect(
        chipFinder,
        findsOneWidget,
        reason: 'TaskInfoDialog must render assigned labels as interactive ActionChips',
      );
      expect(tester.widget<ActionChip>(chipFinder).onPressed, isNotNull);

      // Tap label ActionChip -> stacks LabelHubDialog above TaskInfoDialog!
      await tester.tap(chipFinder);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('label_hub_dialog')), findsOneWidget);
      expect(find.text('Initial ops note'), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);

      // Edit label via LabelHubDialog -> EditLabelScreen -> Save -> updates BOTH LabelHubDialog and TaskInfoDialog while preserving unrelated task undo!
      currentTime = DateTime.utc(2026, 11, 11, 12, 1);
      await tester.tap(find.byKey(const ValueKey('label_hub_edit_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('task_editor_title_input')),
        'Ops Core Runbook',
      );
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_note_input')),
        'Updated ops note',
      );
      final linkTitleField = find.byKey(
        const ValueKey('editor_link_title_input'),
      );
      await tester.ensureVisible(linkTitleField);
      await tester.enterText(linkTitleField, 'Pager');
      await tester.enterText(
        find.byKey(const ValueKey('editor_link_uri_input')),
        'https://ops.example.com/pager',
      );
      await tester.pump();
      final addLinkBtn = find.byKey(const ValueKey('editor_add_link_button'));
      await tester.ensureVisible(addLinkBtn);
      await tester.tap(addLinkBtn);
      await tester.pump();

      final saveBtn = find.byKey(const ValueKey('task_editor_save_button'));
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();

      expect(
        container.read(taskUndoStateProvider).canUndo,
        isTrue,
        reason:
            'Updating label metadata must preserve unrelated task undo entries',
      );
      expect(find.text('Ops Core Runbook'), findsWidgets);
      expect(find.text('Updated ops note'), findsOneWidget);
      expect(find.text('Pager'), findsOneWidget);

      // External .tdf edit via real Directory.watch adds a third link -> LabelHubDialog updates live!
      currentTime = DateTime.utc(2026, 11, 11, 12, 2);
      await tester.runAsync(() async {
        final onDisk = await tdfFile.readAsString();
        final parsedDisk = const TdfService().parse(
          onDisk,
          evaluationTime: currentTime,
        );
        final updatedDisk = const TdfService().serialize(
          parsedDisk.updateLabel(
            'lblOps0001',
            links: const <TaskLink>[
              TaskLink(title: 'Dashboard', uri: 'https://ops.example.com/dash'),
              TaskLink(title: 'Pager', uri: 'https://ops.example.com/pager'),
              TaskLink(title: 'Postmortems', uri: 'https://ops.example.com/pm'),
            ],
            currentDate: currentTime,
          ),
        );
        await tdfFile.writeAsString(updatedDisk, flush: true);
        await Future<void>.delayed(const Duration(milliseconds: 220));
      });
      await tester.pump(const Duration(milliseconds: 60));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Postmortems'),
        findsOneWidget,
        reason: 'External Directory.watch update to label.links must update open LabelHubDialog live',
      );

      // External .tdf retirement (tombstone in deleted block) via real Directory.watch -> LabelHubDialog safely auto-dismisses while TaskInfoDialog remains open!
      currentTime = DateTime.utc(2026, 11, 11, 12, 3);
      await tester.runAsync(() async {
        final onDisk = await tdfFile.readAsString();
        final parsedDisk = const TdfService().parse(
          onDisk,
          evaluationTime: currentTime,
        );
        final retiredDisk = const TdfService().serialize(
          parsedDisk.deleteLabel('lblOps0001', currentDate: currentTime),
        );
        await tdfFile.writeAsString(retiredDisk, flush: true);
        await Future<void>.delayed(const Duration(milliseconds: 220));
      });
      await tester.pump(const Duration(milliseconds: 60));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('label_hub_dialog')),
        findsNothing,
        reason: 'LabelHubDialog must auto-dismiss when its label is retired externally via Directory.watch',
      );
      expect(
        find.byType(TaskInfoDialog),
        findsOneWidget,
        reason: 'Underlying TaskInfoDialog must remain open when stacked LabelHubDialog auto-dismisses',
      );
      expect(
        find.byKey(const ValueKey('task_info_label_chip_lblOps0001')),
        findsNothing,
        reason: 'Underlying TaskInfoDialog must reactively remove retired label chip',
      );
    },
  );
}
