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
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/ui/widgets/task_info_dialog.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'TaskInfoDialog formats indefinite, multi-day, multi-hour, minute-only, and elapsed suspension durations',
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
        find.text('Elapsed (2026-10-31 10:00)'),
        findsOneWidget,
        reason: 'Past suspension timestamp must display Elapsed status',
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
    },
  );
}
