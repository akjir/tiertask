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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/link_launcher_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/ui/edit_labels_screen.dart';
import 'package:tiertask/ui/widgets/task_editor_sections.dart';

import 'test_helpers.dart';

/// [FakeTaskNotifier] test double capturing the `links` argument forwarded to [updateLabel].
class _RecordingLabelTaskNotifier extends FakeTaskNotifier {
  /// Creates a [_RecordingLabelTaskNotifier].
  _RecordingLabelTaskNotifier([super.initialBoard]);

  /// Links passed to the most recent [updateLabel] invocation.
  List<TaskLink>? lastUpdatedLinks;

  @override
  Future<void> updateLabel(
    String labelId, {
    String? name,
    String? color,
    bool clearColor = false,
    String? note,
    bool clearNote = false,
    bool? isScoped,
    Iterable<TaskLink>? links,
    List<TaskCondition>? conditions,
    DateTime? currentDate,
  }) {
    lastUpdatedLinks = links?.toList();
    return super.updateLabel(
      labelId,
      name: name,
      color: color,
      clearColor: clearColor,
      note: note,
      clearNote: clearNote,
      isScoped: isScoped,
      links: links,
      conditions: conditions,
      currentDate: currentDate,
    );
  }
}

void main() {
  testWidgets(
    'Side panel removes tier items, displays Google Keep style Labels with Edit at top, task counts, label filtering, and Create new label opening EditLabelsScreen',
    (WidgetTester tester) async {
      const labelsTdf = '''
tdf 0.6.0

queue {
  modified 2026-11-01 08:30
  task 000001OkD2
  task 000002OkD2
}

location locCampOk2 {
  name "Campground"
  coordinates 50.9787 11.0328
  radius 250
  source "gps"
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
  labels busin0OkD2 home00OkD2
}
task 000002OkD2 {
  name "Water garden plants"
  created 2026-11-01 08:30
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
      expect(
        find.descendant(of: editButtonFinder, matching: find.text('Edit')),
        findsOneWidget,
      );

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

      final colorWheelButtonFinder = find.byKey(
        const ValueKey('label_editor_color_wheel_button'),
      );
      expect(
        colorWheelButtonFinder,
        findsOneWidget,
        reason:
            'Color wheel button must be rendered next to the label color input',
      );
      expect(
        tester.getRect(colorWheelButtonFinder).left >=
            tester.getRect(colorInputFinder).right,
        isTrue,
        reason: 'Color wheel button must be positioned directly to the right of the color input field',
      );

      await tester.tap(colorWheelButtonFinder);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('label_color_picker_dialog')),
        findsOneWidget,
        reason: 'Tapping color wheel button must open LabelColorPickerDialog',
      );
      final wheelFinder = find.byKey(
        const ValueKey('label_color_picker_wheel'),
      );
      final wheelRect = tester.getRect(wheelFinder);
      await tester.tapAt(Offset(wheelRect.left + 12, wheelRect.center.dy));
      await tester.pump();
      final pickedCustomHex = tester
          .widget<Text>(
            find.byKey(const ValueKey('label_color_picker_hex_text')),
          )
          .data!;
      await tester.tap(
        find.byKey(const ValueKey('label_color_picker_confirm_button')),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(colorInputFinder).controller?.text,
        equals(pickedCustomHex),
        reason: 'Confirming custom color wheel dialog must populate the label color input field',
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

      final scopedSwitchFinder = find.byKey(
        const ValueKey('label_editor_scoped_switch'),
      );
      await tester.ensureVisible(scopedSwitchFinder);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('label_editor_scoped_card')),
          matching: find.byIcon(Icons.visibility_off_outlined),
        ),
        findsOneWidget,
        reason: 'Scoped label card in EditLabelScreen must use the visibility_off_outlined icon',
      );
      await tester.tap(scopedSwitchFinder);
      await tester.pump();

      final locChipFinder = find.byKey(
        const ValueKey('task_editor_condition_location_locCampOk2'),
      );
      await tester.ensureVisible(locChipFinder);
      await tester.tap(locChipFinder);
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
      expect(updatedCamping.isScoped, isTrue);
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

  testWidgets(
    'EditLabelsScreen renders empty view, clears input, guards whitespace submit, and creates label on keyboard submit',
    (WidgetTester tester) async {
      final container = await pumpLeafWidget(
        tester,
        const EditLabelsScreen(),
        board: TaskBoard.empty(),
      );

      final emptyTextFinder = find.descendant(
        of: find.byType(Center),
        matching: find.byType(Text),
      );
      expect(
        emptyTextFinder,
        findsOneWidget,
        reason: 'Empty labels board must render the empty labels hint',
      );
      expect(
        tester.widget<Text>(emptyTextFinder).data,
        contains('label'),
        reason: 'Empty labels hint must describe the absence of labels',
      );

      final clearButtonFinder = find.byKey(
        const ValueKey('create_label_clear_button'),
      );
      final submitButtonFinder = find.byKey(
        const ValueKey('create_label_submit_button'),
      );
      final inputFinder = find.byKey(const ValueKey('create_label_input'));

      expect(
        tester.widget<IconButton>(clearButtonFinder).onPressed,
        isNull,
        reason: 'Clear button must be disabled when create input is empty',
      );
      expect(
        tester.widget<IconButton>(submitButtonFinder).onPressed,
        isNull,
        reason: 'Submit button must be disabled when create input is empty',
      );

      await tester.enterText(inputFinder, '   ');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        container.read(taskNotifierProvider).requireValue.labels,
        isEmpty,
        reason: 'Submitting whitespace-only input must not create a label',
      );

      await tester.enterText(inputFinder, 'DraftLabel');
      await tester.pump();
      expect(
        tester.widget<IconButton>(clearButtonFinder).onPressed,
        isNotNull,
        reason:
            'Clear button must be enabled when non-whitespace text is entered',
      );

      await tester.tap(clearButtonFinder);
      await tester.pump();
      expect(
        tester.widget<TextField>(inputFinder).controller?.text,
        isEmpty,
        reason: 'Tapping clear button must clear the create label input field',
      );
      expect(
        container.read(taskNotifierProvider).requireValue.labels,
        isEmpty,
        reason: 'Clearing the input must not create a label',
      );

      await tester.enterText(inputFinder, 'KeyboardLabel');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .labels
            .map((label) => label.name),
        equals(['KeyboardLabel']),
        reason: 'Submitting via keyboard action must create the new label',
      );
      expect(
        tester.widget<TextField>(inputFinder).controller?.text,
        isEmpty,
        reason:
            'Creating a label via keyboard submit must clear the input field',
      );
    },
  );

  testWidgets(
    'EditLabelScreen deselects active preset color, clears existing color and note on save, and handles dialog and screen cancel',
    (WidgetTester tester) async {
      const initialLabel = TdfLabel(
        id: 'home00OkD2',
        name: 'Home',
        color: '#4CAF50',
        note: 'Initial note',
      );
      final container = await pumpLeafWidget(
        tester,
        const EditLabelScreen(label: initialLabel),
        board: TaskBoard.empty().copyWith(labels: const [initialLabel]),
      );

      expect(
        find.ancestor(
          of: find.byType(LabelEditorColorCard),
          matching: find.byType(ValueListenableBuilder<TextEditingValue>),
        ),
        findsOneWidget,
        reason: 'LabelEditorColorCard must be scoped inside a ValueListenableBuilder on the color controller',
      );

      final colorInputFinder = find.byKey(
        const ValueKey('label_editor_color_input'),
      );
      final noteInputFinder = find.byKey(
        const ValueKey('task_editor_note_input'),
      );

      await tester.tap(
        find.byKey(const ValueKey('label_editor_color_wheel_button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('label_color_picker_dialog')),
        findsOneWidget,
        reason: 'Tapping color wheel button must open LabelColorPickerDialog',
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('label_color_picker_dialog')),
          matching: find.text('Cancel'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('label_color_picker_dialog')),
        findsNothing,
        reason: 'Cancelling LabelColorPickerDialog must close the dialog',
      );
      expect(
        tester.widget<TextField>(colorInputFinder).controller?.text,
        equals('#4CAF50'),
        reason:
            'Cancelling LabelColorPickerDialog must preserve the current color',
      );

      final greenPresetFinder = find.byKey(
        const ValueKey('label_editor_color_preset_#4CAF50'),
      );
      await tester.tap(greenPresetFinder);
      await tester.pump();
      expect(
        tester.widget<TextField>(colorInputFinder).controller?.text,
        isEmpty,
        reason:
            'Tapping an already-active preset color swatch must deselect it',
      );

      await tester.enterText(noteInputFinder, '   ');
      await tester.pump();

      final saveButtonFinder = find.byKey(
        const ValueKey('task_editor_save_button'),
      );
      await tester.ensureVisible(saveButtonFinder);
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      final clearedLabel = container
          .read(taskNotifierProvider)
          .requireValue
          .findLabel('home00OkD2')!;
      expect(
        clearedLabel.color,
        isNull,
        reason:
            'Saving with an empty color field must clear the existing color',
      );
      expect(
        clearedLabel.note,
        isNull,
        reason: 'Saving with a whitespace-only note field must clear the existing note',
      );
    },
  );

  testWidgets(
    'EditLabelScreen cancel button closes editor without persisting changes',
    (WidgetTester tester) async {
      const initialLabel = TdfLabel(
        id: 'home00OkD2',
        name: 'Home',
        color: '#4CAF50',
      );
      final container = await pumpLeafWidget(
        tester,
        const EditLabelScreen(label: initialLabel),
        board: TaskBoard.empty().copyWith(labels: const [initialLabel]),
      );

      await tester.enterText(
        find.byKey(const ValueKey('task_editor_title_input')),
        'Unsaved Home',
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('task_editor_cancel_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('edit_label_screen')),
        findsNothing,
        reason: 'Tapping cancel button must pop EditLabelScreen',
      );
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('home00OkD2')
            ?.name,
        equals('Home'),
        reason: 'Cancelling EditLabelScreen must not persist unsaved changes',
      );
    },
  );

  testWidgets(
    'EditLabelScreen preserves existing TdfLabel.links across edits and saves',
    (WidgetTester tester) async {
      const existingLinks = <TaskLink>[
        TaskLink(title: 'Architecture Doc', uri: 'https://example.com/arch'),
        TaskLink(title: 'Oncall Runbook', uri: 'https://example.com/runbook'),
      ];
      const initialLabel = TdfLabel(
        id: 'plat00OkD2',
        name: 'Platform',
        color: '#2196F3',
        note: 'Initial platform note',
        links: existingLinks,
      );
      final recordingNotifier = _RecordingLabelTaskNotifier(
        TaskBoard.empty().copyWith(labels: const [initialLabel]),
      );
      const config = WebDavConfig(language: AppLanguage.english);
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(config),
          ),
          localFileRepositoryProvider.overrideWith(
            (ref) => FakeLocalFileRepository(
              config: config,
              initialTdf: 'tdf 0.7.0\n',
            ),
          ),
          clockProvider.overrideWithValue(
            () => DateTime.utc(2026, 11, 1, 12, 0),
          ),
          taskNotifierProvider.overrideWith(() => recordingNotifier),
        ],
      );
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: EditLabelScreen(label: initialLabel),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('task_editor_title_input')),
        'Platform Core',
      );
      await tester.enterText(
        find.byKey(const ValueKey('task_editor_note_input')),
        'Updated platform note',
      );
      await tester.pump();

      final saveButtonFinder = find.byKey(
        const ValueKey('task_editor_save_button'),
      );
      await tester.ensureVisible(saveButtonFinder);
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      expect(
        recordingNotifier.lastUpdatedLinks,
        equals(existingLinks),
        reason: 'EditLabelScreen must explicitly pass existing TdfLabel.links to updateLabel',
      );
      final updatedLabel = container
          .read(taskNotifierProvider)
          .requireValue
          .findLabel('plat00OkD2');
      expect(updatedLabel?.name, equals('Platform Core'));
      expect(updatedLabel?.note, equals('Updated platform note'));
      expect(
        updatedLabel?.links,
        equals(existingLinks),
        reason: 'Saving an edited TdfLabel must preserve its existing links without dropping or resetting them',
      );
    },
  );

  testWidgets(
    'EditLabelScreen creates, edits in place, cancels, reorders, removes, launches, and logs label links without leaking PII',
    (WidgetTester tester) async {
      AppLogger.clear();
      AppLogger.setEnabled(
        true,
        persistToDisk: false,
        minimumLevel: LogLevel.info,
      );
      addTearDown(() {
        AppLogger.setEnabled(false, persistToDisk: false);
        AppLogger.clear();
      });

      const initialLabel = TdfLabel(
        id: 'hubLblOkD2',
        name: 'SecretProjectName',
        color: '#2196F3',
        note: 'ConfidentialRunbookNote',
        isScoped: true,
        links: <TaskLink>[
          TaskLink(title: 'FirstDocSecret', uri: 'https://example.com/first'),
        ],
      );
      final fakeLauncher = FakeLinkLauncherRepository();
      final container = await pumpLeafWidget(
        tester,
        const EditLabelScreen(label: initialLabel),
        board: TaskBoard.empty().copyWith(labels: const [initialLabel]),
        wrapInScaffold: false,
        linkLauncherRepository: fakeLauncher,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('task_editor_links_card')),
        findsOneWidget,
        reason: 'EditLabelScreen must render TaskEditorLinksSection',
      );

      final titleInput = find.byKey(const ValueKey('editor_link_title_input'));
      final uriInput = find.byKey(const ValueKey('editor_link_uri_input'));
      final addBtn = find.byKey(const ValueKey('editor_add_link_button'));

      // Add a second link via the + button.
      await tester.ensureVisible(addBtn);
      await tester.enterText(titleInput, '  SecondDocSecret  ');
      await tester.enterText(uriInput, '  mailto:team@example.com  ');
      await tester.pump();
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // Add a third link via keyboard Enter on the URI field.
      await tester.enterText(titleInput, 'ThirdDocSecret');
      await tester.enterText(uriInput, 'file:///home/user/runbook.md');
      await tester.pump();
      await tester.ensureVisible(uriInput);
      await tester.tap(uriInput);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('editor_link_item_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('editor_link_item_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('editor_link_item_2')), findsOneWidget);

      // Boundary move buttons must be disabled at 0 and N-1.
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('editor_move_link_up_0')),
            )
            .onPressed,
        isNull,
        reason: 'Move-up must be disabled on index 0',
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('editor_move_link_down_2')),
            )
            .onPressed,
        isNull,
        reason: 'Move-down must be disabled on last index',
      );

      // Start editing index 1, verify cancel button and check icon, then cancel.
      final editBtn1 = find.byKey(const ValueKey('editor_edit_link_1'));
      await tester.ensureVisible(editBtn1);
      await tester.tap(editBtn1);
      await tester.pumpAndSettle();

      expect(
        tester.widget<IconButton>(addBtn).tooltip,
        equals('Update link'),
        reason: 'Submit button tooltip must switch to Update link during edit',
      );
      final cancelEditBtn = find.byKey(
        const ValueKey('editor_cancel_edit_link_button'),
      );
      expect(cancelEditBtn, findsOneWidget);
      await tester.enterText(titleInput, 'DiscardedEdit');
      await tester.pump();
      await tester.tap(cancelEditBtn);
      await tester.pumpAndSettle();

      expect(cancelEditBtn, findsNothing);
      expect(find.text('SecondDocSecret'), findsOneWidget);

      // Start editing index 2 ('ThirdDocSecret'), move it up to index 1, then remove index 0 so active edit shifts to index 0!
      final editBtn2 = find.byKey(const ValueKey('editor_edit_link_2'));
      await tester.ensureVisible(editBtn2);
      await tester.tap(editBtn2);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('editor_move_link_up_2')),
      );
      await tester.tap(find.byKey(const ValueKey('editor_move_link_up_2')));
      await tester.pumpAndSettle();
      // Now order is: [FirstDocSecret (0), ThirdDocSecret (1, active edit), SecondDocSecret (2)].
      // Also test swapping from the adjacent item (move index 2 up onto index 1 -> active edit shifts to 2):
      await tester.ensureVisible(
        find.byKey(const ValueKey('editor_move_link_up_2')),
      );
      await tester.tap(find.byKey(const ValueKey('editor_move_link_up_2')));
      await tester.pumpAndSettle();
      // Order is: [FirstDocSecret (0), SecondDocSecret (1), ThirdDocSecret (2, active edit)].
      // Remove index 0 (before active edit) -> active edit shifts to index 1!
      final removeBtn0 = find.byKey(const ValueKey('editor_remove_link_0'));
      await tester.ensureVisible(removeBtn0);
      await tester.tap(removeBtn0);
      await tester.pumpAndSettle();

      // Confirm active edit (should update index 1: ThirdDocSecret -> UpdatedThirdSecret).
      await tester.ensureVisible(addBtn);
      await tester.enterText(titleInput, 'UpdatedThirdSecret');
      await tester.enterText(uriInput, 'https://example.com/third-updated');
      await tester.pump();
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      expect(find.text('SecondDocSecret'), findsOneWidget);
      expect(find.text('UpdatedThirdSecret'), findsOneWidget);

      // Start editing index 0, then remove index 0 itself -> cancels active edit cleanly without RangeError.
      final editBtn0 = find.byKey(const ValueKey('editor_edit_link_0'));
      await tester.ensureVisible(editBtn0);
      await tester.tap(editBtn0);
      await tester.pumpAndSettle();
      expect(cancelEditBtn, findsOneWidget);
      await tester.ensureVisible(removeBtn0);
      await tester.tap(removeBtn0);
      await tester.pumpAndSettle();
      expect(cancelEditBtn, findsNothing);
      expect(find.text('SecondDocSecret'), findsNothing);

      // Launch remaining link at index 0: first succeed, then fail with screen-local SnackBar.
      final openBtn0 = find.byKey(const ValueKey('editor_open_link_0'));
      await tester.ensureVisible(openBtn0);
      await tester.tap(openBtn0);
      await tester.pumpAndSettle();
      expect(
        fakeLauncher.launchedUris,
        equals(const <String>['https://example.com/third-updated']),
      );

      fakeLauncher.shouldThrow = true;
      await tester.ensureVisible(openBtn0);
      await tester.tap(openBtn0);
      await tester.pumpAndSettle();
      expect(
        find.text('Could not open link.'),
        findsOneWidget,
        reason: 'LinkLaunchException must show localized SnackBar inside EditLabelScreen',
      );
      ScaffoldMessenger.of(
        tester.element(find.byKey(const ValueKey('task_editor_save_button'))),
      ).clearSnackBars();
      await tester.pumpAndSettle();

      // Leave a valid pending draft in the inputs and tap Save -> auto-adds draft and persists!
      await tester.ensureVisible(titleInput);
      await tester.enterText(titleInput, 'AutoSavedDraftSecret');
      await tester.enterText(uriInput, 'https://example.com/draft-secret');
      await tester.pump();

      final saveButton = find.byKey(const ValueKey('task_editor_save_button'));
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      final savedLabel = container
          .read(taskNotifierProvider)
          .requireValue
          .findLabel('hubLblOkD2');
      expect(
        savedLabel?.links,
        equals(const <TaskLink>[
          TaskLink(
            title: 'UpdatedThirdSecret',
            uri: 'https://example.com/third-updated',
          ),
          TaskLink(
            title: 'AutoSavedDraftSecret',
            uri: 'https://example.com/draft-secret',
          ),
        ]),
        reason: 'Save must persist reordered/edited links plus valid pending draft in declaration order',
      );

      final uiSaveLine = AppLogger.lines.singleWhere(
        (line) => line.contains('ui.label_editor.save'),
      );
      expect(uiSaveLine, contains('id=hubLblOkD2'));
      expect(uiSaveLine, contains('links=2'));
      expect(uiSaveLine, contains('scoped=true'));
      expect(uiSaveLine, isNot(contains('SecretProjectName')));

      final logOutput = AppLogger.fullLogText;
      for (final secret in const <String>[
        'ConfidentialRunbookNote',
        'UpdatedThirdSecret',
        'AutoSavedDraftSecret',
        'https://example.com/draft-secret',
      ]) {
        expect(
          logOutput,
          isNot(contains(secret)),
          reason:
              'AppLogger must never log raw label notes, link titles, or URIs ($secret)',
        );
      }
    },
  );

  testWidgets(
    'EditLabelScreen enforces 20-link max bound, Unicode scalar limits, forbidden schemes, and cleared active-edit guard on Save',
    (WidgetTester tester) async {
      final nineteenLinks = <TaskLink>[
        for (var i = 1; i <= 19; i++)
          TaskLink(title: 'Link $i', uri: 'https://example.com/$i'),
      ];
      final initialLabel = TdfLabel(
        id: 'bndLblOkD2',
        name: 'Bounded Label',
        links: nineteenLinks,
      );
      final container = await pumpLeafWidget(
        tester,
        EditLabelScreen(label: initialLabel),
        board: TaskBoard.empty().copyWith(labels: [initialLabel]),
        wrapInScaffold: false,
      );
      await tester.pumpAndSettle();

      final titleInput = find.byKey(const ValueKey('editor_link_title_input'));
      final uriInput = find.byKey(const ValueKey('editor_link_uri_input'));
      final addBtn = find.byKey(const ValueKey('editor_add_link_button'));
      final saveBtn = find.byKey(const ValueKey('task_editor_save_button'));
      final errorFinder = find.byKey(const ValueKey('editor_link_error_text'));

      // Invalid schemes, control characters, and 501-scalar title must fail validation and block Save.
      for (final badCase in <({String title, String uri})>[
        (title: 'Missing scheme', uri: 'example.com/path'),
        (title: 'JS scheme', uri: 'javascript:alert(1)'),
        (title: 'VBS scheme', uri: 'vbscript:msgbox'),
        (title: 'Data scheme', uri: 'DaTa:text/html,1'),
        (title: '', uri: 'https://example.com/notitle'),
        (title: '\u{10400}' * 501, uri: 'https://example.com/501'),
        (
          title: '2049 URI',
          uri: 'https://example.com/${'\u{1F600}' * (2049 - 20)}',
        ),
      ]) {
        await tester.ensureVisible(addBtn);
        await tester.enterText(titleInput, badCase.title);
        await tester.enterText(uriInput, badCase.uri);
        await tester.pump();
        await tester.ensureVisible(saveBtn);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();
        expect(
          errorFinder,
          findsOneWidget,
          reason:
              'Invalid pending link (${badCase.uri}) must abort Save and show error',
        );
      }

      // 19 -> 20th link with 500 supplementary-plane scalars and 2048-scalar URI must succeed!
      final valid500Title = '\u{10400}' * 500;
      final valid2048Uri = 'https://example.com/${'\u{1F600}' * (2048 - 20)}';
      await tester.ensureVisible(addBtn);
      await tester.enterText(titleInput, valid500Title);
      await tester.enterText(uriInput, valid2048Uri);
      await tester.pump();
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      expect(errorFinder, findsNothing);
      expect(
        find.byKey(const ValueKey('editor_link_item_19')),
        findsOneWidget,
        reason: '20th link (index 19) must be added',
      );

      // At 20 links (when not editing), add button is disabled, and Enter / Save on a 21st draft fails with labelLinkErrorMaxExceeded.
      await tester.enterText(titleInput, 'Link 21');
      await tester.enterText(uriInput, 'https://example.com/21');
      await tester.pump();
      expect(
        tester.widget<IconButton>(addBtn).onPressed,
        isNull,
        reason: 'Add button must be disabled when 20 links already exist and not editing',
      );

      await tester.ensureVisible(uriInput);
      await tester.tap(uriInput);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.text('Maximum of 20 links per label reached.'),
        findsOneWidget,
        reason: 'Submitting 21st link via Enter must show max links error',
      );

      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();
      expect(
        find.text('Maximum of 20 links per label reached.'),
        findsOneWidget,
        reason: 'Clicking Save with a pending 21st link must abort Save and show max links error',
      );

      // Editing one of the 20 existing links in place MUST succeed!
      final editBtn0 = find.byKey(const ValueKey('editor_edit_link_0'));
      await tester.ensureVisible(editBtn0);
      await tester.tap(editBtn0);
      await tester.pumpAndSettle();

      // Clearing both fields while in active edit mode and tapping Save must block Save with linkErrorInvalid!
      await tester.enterText(titleInput, '');
      await tester.enterText(uriInput, '');
      await tester.pump();
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();
      expect(
        errorFinder,
        findsOneWidget,
        reason: 'Cleared active in-place edit must block Save instead of silently discarding the edit',
      );

      // Now enter valid updated values for index 0 at capacity (20 links) and Save!
      await tester.ensureVisible(addBtn);
      await tester.enterText(titleInput, 'Edited Link 1');
      await tester.enterText(uriInput, 'https://example.com/1-edited');
      await tester.pump();
      expect(
        tester.widget<IconButton>(addBtn).onPressed,
        isNotNull,
        reason: 'Update button must remain enabled during in-place edit even at 20 links',
      );
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      final saved = container
          .read(taskNotifierProvider)
          .requireValue
          .findLabel('bndLblOkD2');
      expect(saved?.links.length, equals(20));
      expect(
        saved?.links.first,
        equals(
          const TaskLink(
            title: 'Edited Link 1',
            uri: 'https://example.com/1-edited',
          ),
        ),
      );
      expect(
        saved?.links.last,
        equals(TaskLink(title: valid500Title, uri: valid2048Uri)),
      );
    },
  );
}
