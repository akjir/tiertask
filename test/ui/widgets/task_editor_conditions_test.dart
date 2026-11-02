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
    'TaskEditorDialog supports setting and editing Suspended, Prerequisite tasks (blocked), and Activation Conditions (any, day, time, location) while Suspended disables condition evaluation and places the task in Blocked',
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

      expect(
        find.byKey(const ValueKey('task_editor_suspended_input')),
        findsOneWidget,
        reason: 'Enabling Suspended must reveal the optional suspended timestamp input',
      );
      expect(
        find.byKey(const ValueKey('task_editor_conditions_disabled_hint')),
        findsOneWidget,
        reason: 'Enabling Suspended must display notice that evaluation of all other conditions is disabled',
      );

      await tester.enterText(
        find.byKey(const ValueKey('task_editor_suspended_input')),
        'not-a-date',
      );
      await tester.pump();
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a valid timestamp (YYYY-MM-DD or YYYY-MM-DD HH:MM).'),
        findsOneWidget,
        reason: 'Invalid suspended timestamp must show validation error',
      );

      await tester.enterText(
        find.byKey(const ValueKey('task_editor_suspended_input')),
        '2026-11-05 08:30',
      );
      await tester.pump();
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

      final prereqChipFinder = find.byKey(
        const ValueKey('task_editor_blocked_t001'),
      );
      await tester.ensureVisible(prereqChipFinder);
      await tester.tap(prereqChipFinder);
      await tester.pump();

      await tester.ensureVisible(conditionAnyToggle);
      await tester.tap(conditionAnyToggle);
      await tester.pump();

      final daySunChip = find.byKey(
        const ValueKey('task_editor_condition_day_sun'),
      );
      await tester.ensureVisible(daySunChip);
      await tester.tap(daySunChip);
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const ValueKey('task_editor_time_start_input')),
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

      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      final updatedDeferred = board.findTask(deferredTask.id)!;
      expect(
        updatedDeferred.suspendedAt,
        isNull,
        reason:
            'Disabling Suspended in TaskEditorDialog must clear suspendedAt',
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

      final cycleChipFinder = find.byKey(
        ValueKey('task_editor_blocked_${deferredTask.id}'),
      );
      final cycleChip = tester.widget<FilterChip>(cycleChipFinder);
      expect(
        cycleChip.onSelected,
        isNull,
        reason: 'TaskEditorDialog must disable prerequisite chips that would create a circular dependency',
      );
    },
  );
}
