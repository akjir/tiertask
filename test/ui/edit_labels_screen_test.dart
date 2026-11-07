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
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';

import 'test_helpers.dart';

void main() {
  testWidgets(
    'Side panel removes tier items, displays Google Keep style Labels with Edit at top, task counts, label filtering, and Create new label opening EditLabelsScreen',
    (WidgetTester tester) async {
      const labelsTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 08:30:00
  task 000001OkD2
  task 000002OkD2
}

label home00OkD2 {
  name "Home"
  color "#00E5FF"
}
label busin0OkD2 {
  name "Business"
  color "#EB06FF"
}
task 000001OkD2 {
  name "Prepare quarterly report"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
  labels busin0OkD2 home00OkD2
}
task 000002OkD2 {
  name "Water garden plants"
  created 2026-11-01 08:30
  queued 2026-11-01 08:30
  labels home00OkD2
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
              initialTdf: labelsTdf,
            ),
          ),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
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
        find.text("What's up!"),
        findsNothing,
        reason: 'Legacy greeting must be removed from the landing page',
      );
      final topBarTitleFinder = find.byKey(const ValueKey('top_bar_title'));
      expect(
        topBarTitleFinder,
        findsNothing,
        reason: 'Top bar must not display TierTask or any title when no label is selected',
      );
      expect(
        find.text('TierTask'),
        findsNothing,
        reason: 'TierTask must not be rendered in the top bar',
      );
      expect(
        find.text('Prepare quarterly report'),
        findsOneWidget,
        reason: 'Focus task must render on the landing page',
      );
      expect(
        find.text('Water garden plants'),
        findsOneWidget,
        reason: 'Second Focus task must render on the landing page',
      );
      expect(
        find.text('LABELS'),
        findsNothing,
        reason: 'Labels section must not appear directly on the landing page',
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      for (final tierLabel in [
        'Focus',
        'Ready',
        'Planned',
        'Blocked',
        'Someday',
        'Completed',
      ]) {
        expect(
          find.descendant(
            of: find.byType(Drawer),
            matching: find.text(tierLabel),
          ),
          findsNothing,
          reason: 'Side panel must not contain tier item $tierLabel',
        );
      }

      expect(
        find.text('Labels'),
        findsOneWidget,
        reason: 'Side panel must display the Labels section header',
      );
      final editButtonFinder = find.byKey(
        const ValueKey('drawer_edit_labels_button'),
      );
      expect(
        editButtonFinder,
        findsOneWidget,
        reason: 'Side panel must display the Edit button at the top of Labels',
      );
      expect(find.text('Edit'), findsOneWidget);

      final homeTileFinder = find.byKey(
        const ValueKey('drawer_label_tile_home00OkD2'),
      );
      final businessTileFinder = find.byKey(
        const ValueKey('drawer_label_tile_busin0OkD2'),
      );
      final createLabelTileFinder = find.byKey(
        const ValueKey('drawer_create_label_tile'),
      );
      expect(homeTileFinder, findsOneWidget);
      expect(businessTileFinder, findsOneWidget);
      expect(createLabelTileFinder, findsOneWidget);
      expect(find.text('Create new label'), findsOneWidget);
      expect(
        tester.getTopLeft(businessTileFinder).dy <
            tester.getTopLeft(homeTileFinder).dy,
        isTrue,
        reason: 'Labels in the side panel must be sorted alphabetically (Business before Home)',
      );

      expect(
        find.descendant(of: homeTileFinder, matching: find.text('2')),
        findsOneWidget,
        reason: 'Home label tile in drawer must display task count 2',
      );
      expect(
        find.descendant(of: businessTileFinder, matching: find.text('1')),
        findsOneWidget,
        reason: 'Business label tile in drawer must display task count 1',
      );

      await tester.tap(businessTileFinder);
      await tester.pumpAndSettle();

      expect(
        find.text('TierTask'),
        findsNothing,
        reason: 'Selecting a label must replace TierTask in the top bar with the label name',
      );
      expect(
        find.text('Business'),
        findsOneWidget,
        reason: 'Selected label name must appear only once (in the top bar) and not above the tier section heading',
      );
      expect(
        find.descendant(of: topBarTitleFinder, matching: find.text('Business')),
        findsOneWidget,
        reason: 'Top bar header title must display the selected label name',
      );
      final centeredLabelRect = tester.getRect(topBarTitleFinder);
      final menuButtonRect = tester.getRect(find.byIcon(Icons.menu_rounded));
      expect(
        centeredLabelRect.left > menuButtonRect.right + 20,
        isTrue,
        reason: 'Selected label name must be centered in the top bar when search is inactive',
      );

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final midAnimationLabelRect = tester.getRect(topBarTitleFinder);
      expect(
        midAnimationLabelRect.left < centeredLabelRect.left &&
            midAnimationLabelRect.left > menuButtonRect.right,
        isTrue,
        reason: 'Selected label name must smoothly animate from the center toward the menu button',
      );

      await tester.pumpAndSettle();

      final searchingLabelRect = tester.getRect(topBarTitleFinder);
      final searchFieldRect = tester.getRect(find.byType(TextField));
      final closeSearchRect = tester.getRect(find.byIcon(Icons.close_rounded));
      expect(
        searchingLabelRect.left < midAnimationLabelRect.left,
        isTrue,
        reason: 'Completed search animation must position the label name next to the menu button',
      );
      expect(
        searchFieldRect.left >= searchingLabelRect.right - 1.0 &&
            searchFieldRect.right <= closeSearchRect.left + 1.0,
        isTrue,
        reason: 'Search field must appear between the shifted label name and the search/close button',
      );

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(
        tester.getRect(topBarTitleFinder).left,
        closeTo(centeredLabelRect.left, 0.5),
        reason: 'Closing search must smoothly return the selected label name to the center',
      );

      expect(
        find.text('Prepare quarterly report'),
        findsOneWidget,
        reason: 'Selecting Business label in drawer must show Business tasks',
      );
      expect(
        find.text('Water garden plants'),
        findsNothing,
        reason: 'Selecting Business label in drawer must filter out Home-only tasks',
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      await tester.tap(businessTileFinder);
      await tester.pumpAndSettle();

      expect(
        topBarTitleFinder,
        findsNothing,
        reason: 'Clearing the selected label filter must remove the label title from the top bar',
      );
      expect(
        find.text('Business'),
        findsNothing,
        reason:
            'Cleared label name must no longer be displayed as the top header',
      );
      expect(
        find.text('Water garden plants'),
        findsOneWidget,
        reason: 'Tapping the active label again in the drawer must clear the filter',
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      await tester.tap(editButtonFinder);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('edit_labels_screen')),
        findsOneWidget,
        reason: 'Clicking Edit at the top of the Labels section must open EditLabelsScreen',
      );
      expect(find.text('Edit labels'), findsOneWidget);
      final homeRowFinder = find.byKey(
        const ValueKey('edit_label_row_home00OkD2'),
      );
      final businessRowFinder = find.byKey(
        const ValueKey('edit_label_row_busin0OkD2'),
      );
      expect(
        tester.getTopLeft(businessRowFinder).dy <
            tester.getTopLeft(homeRowFinder).dy,
        isTrue,
        reason: 'Labels in EditLabelsScreen must be sorted alphabetically (Business before Home)',
      );
      expect(
        find.descendant(of: homeRowFinder, matching: find.text('2')),
        findsOneWidget,
        reason: 'EditLabelsScreen must keep the task count on Home label',
      );
      expect(
        find.descendant(of: businessRowFinder, matching: find.text('1')),
        findsOneWidget,
        reason: 'EditLabelsScreen must keep the task count on Business label',
      );

      await tester.enterText(
        find.byKey(const ValueKey('create_label_input')),
        'Camping',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('create_label_submit_button')),
      );
      await tester.pumpAndSettle();

      final campingLabel = container
          .read(taskNotifierProvider)
          .requireValue
          .labels
          .singleWhere((label) => label.name == 'Camping');
      expect(
        isValidLabelId(campingLabel.id),
        isTrue,
        reason: 'Created label must have a valid 10-character Base62 label ID',
      );
      final campingRowFinder = find.byKey(
        ValueKey('edit_label_row_${campingLabel.id}'),
      );
      expect(
        campingRowFinder,
        findsOneWidget,
        reason:
            'Creating a new label in EditLabelsScreen must add it to the list',
      );
      expect(
        tester.getTopLeft(businessRowFinder).dy <
                tester.getTopLeft(campingRowFinder).dy &&
            tester.getTopLeft(campingRowFinder).dy <
                tester.getTopLeft(homeRowFinder).dy,
        isTrue,
        reason: 'Newly created Camping label must be positioned alphabetically between Business and Home',
      );
      expect(
        find.byKey(ValueKey('rename_label_input_${campingLabel.id}')),
        findsNothing,
        reason: 'Inline rename field must not exist in the overview panel',
      );

      await tester.tap(
        find.byKey(ValueKey('edit_label_button_${campingLabel.id}')),
      );
      await tester.pumpAndSettle();

      final editLabelScreenFinder = find.byKey(
        const ValueKey('edit_label_screen'),
      );
      expect(
        editLabelScreenFinder,
        findsOneWidget,
        reason:
            'Clicking the edit button on a label row must open EditLabelScreen',
      );
      expect(
        find.byKey(const ValueKey('task_editor_condition_any_toggle')),
        findsNothing,
        reason: 'EditLabelScreen must not render task-only condition any reset toggles',
      );
      expect(
        find.byKey(const ValueKey('task_editor_condition_day_any_toggle')),
        findsNothing,
        reason:
            'EditLabelScreen must not render task-only day any reset toggles',
      );

      final titleInputFinder = find.byKey(
        const ValueKey('task_editor_title_input'),
      );
      final noteInputFinder = find.byKey(
        const ValueKey('task_editor_note_input'),
      );
      final colorInputFinder = find.byKey(
        const ValueKey('label_editor_color_input'),
      );
      final saveButtonFinder = find.byKey(
        const ValueKey('task_editor_save_button'),
      );

      await tester.enterText(titleInputFinder, '   ');
      await tester.pump();
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();
      expect(
        find.text('Please enter a label name.'),
        findsOneWidget,
        reason:
            'Empty label name in EditLabelScreen must show validation error',
      );

      await tester.enterText(titleInputFinder, '  home  ');
      await tester.pump();
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();
      expect(
        find.text('A label with this name already exists.'),
        findsOneWidget,
        reason: 'Duplicate label name in EditLabelScreen must show validation error',
      );

      await tester.enterText(titleInputFinder, 'Outdoor Camping');
      await tester.enterText(noteInputFinder, 'Weekend gear & tents');
      await tester.enterText(colorInputFinder, 'not-a-color');
      await tester.pump();
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a valid hex color (#RRGGBB).'),
        findsOneWidget,
        reason: 'Invalid hex color must show validation error',
      );

      await tester.tap(
        find.byKey(const ValueKey('label_editor_color_preset_#4CAF50')),
      );
      await tester.pump();

      final satChip = find.byKey(
        const ValueKey('task_editor_condition_day_sat'),
      );
      await tester.ensureVisible(satChip);
      await tester.tap(satChip);
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('task_editor_time_start_input')),
        '08:00',
      );
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_time_end_input')),
        '20:00',
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
        '250',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('task_editor_add_location_condition_button')),
      );
      await tester.pump();

      await tester.ensureVisible(saveButtonFinder);
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      expect(
        editLabelScreenFinder,
        findsNothing,
        reason: 'Saving valid label changes must close EditLabelScreen',
      );
      expect(
        find.text('Outdoor Camping'),
        findsOneWidget,
        reason:
            'Updated label name must be displayed in EditLabelsScreen overview',
      );
      expect(
        tester.getTopLeft(homeRowFinder).dy <
            tester.getTopLeft(campingRowFinder).dy,
        isTrue,
        reason: 'Renamed Outdoor Camping label must resort alphabetically after Home',
      );

      final updatedCamping = container
          .read(taskNotifierProvider)
          .requireValue
          .findLabel(campingLabel.id)!;
      expect(updatedCamping.name, equals('Outdoor Camping'));
      expect(updatedCamping.note, equals('Weekend gear & tents'));
      expect(updatedCamping.color, equals('#4CAF50'));
      expect(updatedCamping.conditions.length, equals(3));

      await tester.tap(
        find.byKey(ValueKey('delete_label_button_${campingLabel.id}')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Outdoor Camping'),
        findsNothing,
        reason: 'Quick delete button in EditLabelsScreen must remove the label immediately',
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      await tester.tap(createLabelTileFinder);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('edit_labels_screen')),
        findsOneWidget,
        reason: 'Clicking Create new label in the drawer must also open EditLabelsScreen',
      );
    },
  );
}
