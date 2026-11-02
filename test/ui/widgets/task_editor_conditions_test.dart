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
    'EditTaskScreen supports Suspended with date/time pickers, search-based multi-select Prerequisite tasks (blocked), and Activation Conditions (any, day, time with pickers, location)',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.2.0

label office {
  name "Office"
  color "#2196F3"
  condition {
    day mon
    time 09:00 17:00
  }
}
task t001 {
  name "Prepare Database Migration"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
}
task t002 {
  name "Prepare Backup Verification"
  created 2026-11-01 08:05
  queued 2026-11-01 08:05
}
task t003 {
  name "Write Release Notes"
  created 2026-11-01 08:10
  queued 2026-11-01 08:10
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

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick_add_advanced_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('edit_task_screen')),
        findsOneWidget,
        reason: 'Advanced button must open EditTaskScreen',
      );

      final titleInputFinder = find.byKey(
        const ValueKey('task_editor_title_input'),
      );
      final saveButtonFinder = find.byKey(
        const ValueKey('task_editor_save_button'),
      );
      final suspendedButtonFinder = find.byKey(
        const ValueKey('task_editor_suspended_button'),
      );

      await tester.enterText(titleInputFinder, 'Deferred Release');
      await tester.tap(find.byKey(const ValueKey('task_editor_label_office')));
      await tester.pump();

      final conditionAnyToggle = find.byKey(
        const ValueKey('task_editor_condition_any_toggle'),
      );
      await tester.ensureVisible(conditionAnyToggle);
      await tester.tap(conditionAnyToggle);
      await tester.pump();

      await tester.ensureVisible(suspendedButtonFinder);
      await tester.tap(suspendedButtonFinder);
      await tester.pump();

      final suspendedInputFinder = find.byKey(
        const ValueKey('task_editor_suspended_input'),
      );
      final suspendedDatePickerBtn = find.byKey(
        const ValueKey('task_editor_suspended_date_picker_button'),
      );
      final suspendedTimePickerBtn = find.byKey(
        const ValueKey('task_editor_suspended_time_picker_button'),
      );
      expect(
        suspendedInputFinder,
        findsOneWidget,
        reason: 'Enabling Suspended must reveal the optional suspended timestamp input',
      );
      expect(
        suspendedDatePickerBtn,
        findsOneWidget,
        reason:
            'Suspended timestamp field must offer a modern date picker button',
      );
      expect(
        suspendedTimePickerBtn,
        findsOneWidget,
        reason:
            'Suspended timestamp field must offer a modern time picker button',
      );
      expect(
        find.byKey(const ValueKey('task_editor_conditions_disabled_hint')),
        findsOneWidget,
        reason: 'Enabling Suspended must display notice that evaluation of all other conditions is disabled',
      );

      await tester.enterText(suspendedInputFinder, 'not-a-date');
      await tester.pump();
      await tester.ensureVisible(saveButtonFinder);
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a valid timestamp (YYYY-MM-DD or YYYY-MM-DD HH:MM).'),
        findsOneWidget,
        reason: 'Invalid suspended timestamp must show validation error',
      );

      await tester.ensureVisible(suspendedDatePickerBtn);
      await tester.tap(suspendedDatePickerBtn);
      await tester.pumpAndSettle();
      expect(
        find.byType(DatePickerDialog),
        findsOneWidget,
        reason: 'Tapping the date picker button must open a Material 3 DatePickerDialog',
      );
      await tester.tap(find.text('5'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(suspendedInputFinder).controller?.text,
        equals('2026-11-05'),
        reason: 'Selecting a date in the date picker must populate YYYY-MM-DD',
      );

      await tester.tap(suspendedTimePickerBtn);
      await tester.pumpAndSettle();
      expect(
        find.byType(TimePickerDialog),
        findsOneWidget,
        reason: 'Tapping the time picker button must open a Material 3 TimePickerDialog',
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(suspendedInputFinder).controller?.text,
        equals('2026-11-05 09:00'),
        reason:
            'Confirming the time picker must append HH:MM to the selected date',
      );

      final clearSuspendedBtn = find.byKey(
        const ValueKey('task_editor_suspended_clear_button'),
      );
      expect(
        clearSuspendedBtn,
        findsOneWidget,
        reason: 'Non-empty suspended field must display a clear button',
      );
      await tester.tap(clearSuspendedBtn);
      await tester.pump();
      expect(
        tester.widget<TextField>(suspendedInputFinder).controller?.text,
        isEmpty,
        reason: 'Tapping clear button must empty the suspended timestamp input',
      );

      await tester.enterText(suspendedInputFinder, '2026-11-05 08:30');
      await tester.pump();
      await tester.ensureVisible(saveButtonFinder);
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      var board = container.read(taskNotifierProvider).value!;
      expect(
        board.blocked.map((task) => task.title),
        equals(['Deferred Release']),
        reason: 'Suspended task must appear under Blocked even when condition any is set',
      );
      final deferredTask = board.blocked.single;
      expect(
        deferredTask.suspendedAt,
        equals(DateTime.utc(2026, 11, 5, 8, 30)),
      );

      await tester.tap(
        find.byKey(const ValueKey('tier_indicator_item_blocked')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('edit_task_button_${deferredTask.id}')),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(suspendedButtonFinder);
      await tester.tap(suspendedButtonFinder);
      await tester.pump();

      final blockedSearchFinder = find.byKey(
        const ValueKey('task_editor_blocked_search_input'),
      );
      final prereqChipT001 = find.byKey(
        const ValueKey('task_editor_blocked_t001'),
      );
      final prereqChipT002 = find.byKey(
        const ValueKey('task_editor_blocked_t002'),
      );
      final prereqChipT003 = find.byKey(
        const ValueKey('task_editor_blocked_t003'),
      );

      await tester.ensureVisible(blockedSearchFinder);
      expect(
        prereqChipT001,
        findsNothing,
        reason: 'Unselected tasks must not be listed in Prerequisite Tasks before searching',
      );
      expect(
        prereqChipT002,
        findsNothing,
        reason: 'Unselected tasks must not be listed in Prerequisite Tasks before searching',
      );
      expect(
        prereqChipT003,
        findsNothing,
        reason: 'Unselected tasks must not be listed in Prerequisite Tasks before searching',
      );

      await tester.enterText(blockedSearchFinder, 'prepare');
      await tester.pump();

      expect(
        prereqChipT001,
        findsOneWidget,
        reason: 'Searching by name must suggest matching task t001',
      );
      expect(
        prereqChipT002,
        findsOneWidget,
        reason: 'Searching by name must suggest matching task t002',
      );
      expect(
        prereqChipT003,
        findsNothing,
        reason:
            'Non-matching task t003 must not be suggested for query "prepare"',
      );

      await tester.ensureVisible(prereqChipT001);
      await tester.tap(prereqChipT001);
      await tester.pump();
      await tester.ensureVisible(prereqChipT002);
      await tester.tap(prereqChipT002);
      await tester.pump();

      final clearSearchBtn = find.byKey(
        const ValueKey('task_editor_blocked_search_clear_button'),
      );
      expect(clearSearchBtn, findsOneWidget);
      await tester.tap(clearSearchBtn);
      await tester.pump();

      expect(
        prereqChipT001,
        findsOneWidget,
        reason: 'Selected prerequisite t001 must remain visible as a selected chip after clearing search',
      );
      expect(
        prereqChipT002,
        findsOneWidget,
        reason: 'Selected prerequisite t002 must remain visible as a selected chip after clearing search',
      );

      await tester.ensureVisible(prereqChipT002);
      await tester.tap(prereqChipT002);
      await tester.pump();
      expect(
        prereqChipT002,
        findsNothing,
        reason: 'Tapping a selected prerequisite chip when search is empty must deselect and hide it',
      );

      await tester.ensureVisible(conditionAnyToggle);
      await tester.tap(conditionAnyToggle);
      await tester.pump();

      final daySunChip = find.byKey(
        const ValueKey('task_editor_condition_day_sun'),
      );
      await tester.ensureVisible(daySunChip);
      await tester.tap(daySunChip);
      await tester.pump();

      final startPickerBtn = find.byKey(
        const ValueKey('task_editor_time_start_picker_button'),
      );
      final endPickerBtn = find.byKey(
        const ValueKey('task_editor_time_end_picker_button'),
      );
      await tester.ensureVisible(startPickerBtn);
      await tester.tap(startPickerBtn);
      await tester.pumpAndSettle();
      expect(
        find.byType(TimePickerDialog),
        findsOneWidget,
        reason: 'Start time picker button must open TimePickerDialog',
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('task_editor_time_start_input')),
            )
            .controller
            ?.text,
        equals('09:00'),
        reason:
            'Confirming start time picker must populate start time controller',
      );

      await tester.tap(endPickerBtn);
      await tester.pumpAndSettle();
      expect(
        find.byType(TimePickerDialog),
        findsOneWidget,
        reason: 'End time picker button must open TimePickerDialog',
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('task_editor_time_end_input')),
            )
            .controller
            ?.text,
        equals('17:00'),
        reason: 'Confirming end time picker must populate end time controller',
      );

      await tester.enterText(
        find.byKey(const ValueKey('task_editor_time_start_input')),
        '10:00',
      );
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_time_end_input')),
        '16:00',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('task_editor_add_time_condition_button')),
      );
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const ValueKey('task_editor_location_lat_input')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_location_lat_input')),
        '50.9787',
      );
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_location_lon_input')),
        '11.0328',
      );
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_location_radius_input')),
        '150',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('task_editor_add_location_condition_button')),
      );
      await tester.pump();

      await tester.ensureVisible(saveButtonFinder);
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      final updatedDeferred = board.findTask(deferredTask.id)!;
      expect(
        updatedDeferred.suspendedAt,
        isNull,
        reason: 'Disabling Suspended in EditTaskScreen must clear suspendedAt',
      );
      expect(
        updatedDeferred.blockedByTaskIds,
        equals(['t001']),
        reason: 'Selected prerequisite task must be stored on blockedByTaskIds',
      );
      expect(
        updatedDeferred.conditions.length,
        equals(3),
        reason: 'Day, time window, and location conditions must be saved on the task',
      );

      await tester.tap(find.byKey(const ValueKey('tier_indicator_item_focus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit_task_button_t001')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(blockedSearchFinder);
      await tester.enterText(blockedSearchFinder, 'Deferred Release');
      await tester.pump();

      final cycleChipFinder = find.byKey(
        ValueKey('task_editor_blocked_${deferredTask.id}'),
      );
      final cycleChip = tester.widget<FilterChip>(cycleChipFinder);
      expect(
        cycleChip.onSelected,
        isNull,
        reason: 'EditTaskScreen must disable prerequisite suggestions that would create a circular dependency',
      );
    },
  );
}
