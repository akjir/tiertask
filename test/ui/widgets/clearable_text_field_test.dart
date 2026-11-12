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
import 'package:tiertask/main.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/ui/widgets/clearable_text_field.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'ClearableTextField shows right-side clear button only when focused, clears text on click, invokes callbacks, and composes with suffixIcon',
    (WidgetTester tester) async {
      final controller = TextEditingController(text: 'tasks.tdf');
      final otherFocusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(otherFocusNode.dispose);

      String? lastChanged;
      var clearedCount = 0;

      await pumpLeafWidget(
        tester,
        Column(
          children: [
            ClearableTextField(
              fieldKey: const ValueKey('sample_field'),
              clearButtonKey: const ValueKey('sample_clear_button'),
              controller: controller,
              onChanged: (value) => lastChanged = value,
              onCleared: () => clearedCount++,
              decoration: const InputDecoration(
                labelText: 'Sample',
                suffixIcon: Icon(
                  Icons.visibility_outlined,
                  key: ValueKey('trailing_icon'),
                ),
              ),
            ),
            TextField(
              key: const ValueKey('other_field'),
              focusNode: otherFocusNode,
            ),
          ],
        ),
      );

      final fieldFinder = find.byKey(const ValueKey('sample_field'));
      final clearButtonFinder = find.byKey(
        const ValueKey('sample_clear_button'),
      );
      final trailingIconFinder = find.byKey(const ValueKey('trailing_icon'));

      expect(
        clearButtonFinder,
        findsNothing,
        reason: 'Unfocused ClearableTextField must not show the clear button',
      );
      expect(
        trailingIconFinder,
        findsOneWidget,
        reason: 'Existing suffixIcon must remain visible when unfocused',
      );

      await tester.tap(fieldFinder);
      await tester.pump();

      expect(
        clearButtonFinder,
        findsOneWidget,
        reason: 'Focused ClearableTextField must show the clear button on the right side',
      );
      expect(
        trailingIconFinder,
        findsOneWidget,
        reason: 'Existing suffixIcon must remain visible alongside the clear button',
      );
      expect(
        tester.getTopLeft(clearButtonFinder).dx >
            tester.getTopLeft(fieldFinder).dx,
        isTrue,
        reason:
            'Clear button must be positioned on the right side of the field',
      );

      await tester.tap(clearButtonFinder);
      await tester.pump();

      expect(
        controller.text,
        isEmpty,
        reason: 'Clicking the clear button must empty the controller text',
      );
      expect(
        lastChanged,
        equals(''),
        reason: 'Clearing the text must notify onChanged with an empty string',
      );
      expect(
        clearedCount,
        equals(1),
        reason: 'Clearing the text must invoke onCleared',
      );
      expect(
        clearButtonFinder,
        findsOneWidget,
        reason: 'Field must remain focused after clicking the clear button',
      );

      otherFocusNode.requestFocus();
      await tester.pump();

      expect(
        clearButtonFinder,
        findsNothing,
        reason: 'Losing focus must hide the clear button',
      );
    },
  );

  testWidgets(
    'ClearableTextField scopes rebuilds to clear-button visibility transitions, swaps controllers in didUpdateWidget, enforces visibility guards, and supports TextField and TextFormField modes',
    (WidgetTester tester) async {
      final firstController = TextEditingController();
      final secondController = TextEditingController();
      addTearDown(firstController.dispose);
      addTearDown(secondController.dispose);

      var suffixBuildCount = 0;
      var activeController = firstController;
      var isEnabled = true;
      var isReadOnly = false;
      var showClearWhenUnfocused = false;
      var useFormField = false;
      FormFieldValidator<String>? validator;
      final formKey = GlobalKey<FormState>();

      late StateSetter updateHost;

      await pumpLeafWidget(
        tester,
        StatefulBuilder(
          builder: (context, setHostState) {
            updateHost = setHostState;
            return Form(
              key: formKey,
              child: ClearableTextField(
                fieldKey: const ValueKey('scoped_field'),
                clearButtonKey: const ValueKey('scoped_clear_button'),
                controller: activeController,
                enabled: isEnabled,
                readOnly: isReadOnly,
                showClearWhenUnfocused: showClearWhenUnfocused,
                useFormField: useFormField,
                validator: validator,
                decoration: InputDecoration(
                  labelText: 'Scoped',
                  suffixIcon: Builder(
                    builder: (context) {
                      suffixBuildCount++;
                      return const Icon(
                        Icons.info_outline,
                        key: ValueKey('scoped_suffix_icon'),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      );

      final fieldFinder = find.byKey(const ValueKey('scoped_field'));
      final clearButtonFinder = find.byKey(
        const ValueKey('scoped_clear_button'),
      );

      expect(
        find.byType(TextFormField),
        findsNothing,
        reason: 'Default mode must render a plain TextField',
      );
      expect(
        find.byType(TextField),
        findsOneWidget,
        reason: 'Default mode must mount a TextField widget',
      );
      expect(
        clearButtonFinder,
        findsNothing,
        reason: 'Clear button must be hidden initially when unfocused',
      );
      expect(
        suffixBuildCount,
        equals(1),
        reason: 'Custom suffixIcon Builder must build once on initial mount',
      );

      await tester.tap(fieldFinder);
      await tester.pump();

      expect(
        clearButtonFinder,
        findsOneWidget,
        reason: 'Focusing the field must transition clear button to visible',
      );
      expect(
        suffixBuildCount,
        equals(2),
        reason: 'Custom suffixIcon Builder must rebuild when clear-button visibility transitions',
      );

      final clearButtonBeforeTyping = tester.widget<IconButton>(
        clearButtonFinder,
      );

      await tester.enterText(fieldFinder, 'a');
      await tester.pump();
      await tester.enterText(fieldFinder, 'ab');
      await tester.pump();
      await tester.enterText(fieldFinder, 'abc');
      await tester.pump();

      expect(
        suffixBuildCount,
        equals(2),
        reason: 'Typing characters while focused must not rebuild custom suffixIcon when clear-button visibility is unchanged',
      );
      expect(
        tester.widget<IconButton>(clearButtonFinder),
        same(clearButtonBeforeTyping),
        reason: 'Typing characters while focused must not trigger redundant ClearableTextField setState rebuilds when clear-button visibility is unchanged',
      );

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      expect(
        clearButtonFinder,
        findsNothing,
        reason: 'Unfocusing with showClearWhenUnfocused false must hide the clear button',
      );
      expect(
        suffixBuildCount,
        equals(3),
        reason: 'Hiding the clear button must transition suffix slot back to the bare suffixIcon',
      );

      firstController.clear();
      updateHost(() {
        showClearWhenUnfocused = true;
      });
      await tester.pump();

      expect(
        clearButtonFinder,
        findsNothing,
        reason: 'showClearWhenUnfocused must not show clear button when unfocused text is empty',
      );

      firstController.text = 'a';
      await tester.pump();

      expect(
        clearButtonFinder,
        findsOneWidget,
        reason: 'showClearWhenUnfocused must show clear button when unfocused text becomes non-empty',
      );
      final unfocusedClearButton = tester.widget<IconButton>(clearButtonFinder);

      firstController.text = 'ab';
      await tester.pump();
      firstController.text = 'abc';
      await tester.pump();

      expect(
        tester.widget<IconButton>(clearButtonFinder),
        same(unfocusedClearButton),
        reason: 'Subsequent non-empty edits while unfocused must not rebuild ClearableTextField when visibility stays true',
      );

      updateHost(() {
        isReadOnly = true;
      });
      await tester.pump();

      expect(
        clearButtonFinder,
        findsNothing,
        reason: 'readOnly true must hide the clear button',
      );

      updateHost(() {
        isReadOnly = false;
        isEnabled = false;
      });
      await tester.pump();

      expect(
        clearButtonFinder,
        findsNothing,
        reason: 'enabled false must hide the clear button',
      );

      updateHost(() {
        isEnabled = true;
        activeController = secondController;
      });
      await tester.pump();

      expect(
        clearButtonFinder,
        findsNothing,
        reason: 'Swapping to an empty second controller while unfocused must hide the clear button',
      );

      firstController.text = 'mutated old controller';
      await tester.pump();

      expect(
        clearButtonFinder,
        findsNothing,
        reason: 'Old controller listener must be detached in didUpdateWidget so mutations do not affect visibility',
      );

      secondController.text = 'new controller text';
      await tester.pump();

      expect(
        clearButtonFinder,
        findsOneWidget,
        reason: 'New controller listener must be attached in didUpdateWidget so non-empty text shows the clear button',
      );

      updateHost(() {
        useFormField = true;
      });
      await tester.pump();

      expect(
        find.byType(TextFormField),
        findsOneWidget,
        reason: 'useFormField true must render a TextFormField',
      );

      updateHost(() {
        useFormField = false;
        validator = (value) =>
            (value == null || value.isEmpty) ? 'Required' : null;
      });
      await tester.pump();

      expect(
        find.byType(TextFormField),
        findsOneWidget,
        reason: 'Non-null validator must render a TextFormField',
      );

      secondController.clear();
      await tester.pump();
      expect(
        formKey.currentState?.validate(),
        isFalse,
        reason: 'TextFormField mode must wire the validator into the enclosing Form',
      );
    },
  );

  testWidgets(
    'SettingsScreen text fields display right-side clear button when focused and clear text on click',
    (WidgetTester tester) async {
      const config = WebDavConfig(
        language: AppLanguage.english,
        storageMode: StorageMode.both,
        localFilePath: 'tasks.tdf',
        serverUrl: 'https://cloud.example.com',
        username: 'example-user',
        password: 'secret-password',
        filePath: 'remote.tdf',
      );
      final settingsRepository = InMemorySettingsRepository(config);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepository),
            localFileRepositoryProvider.overrideWithValue(
              FakeLocalFileRepository(
                config: config,
                initialTdf:
                    'tdf 0.5.0\n\nqueue {\n  modified 2026-11-01 00:00:00\n}\n',
              ),
            ),
            webDavRepositoryProvider.overrideWithValue(
              FakeWebDavRepository(config: config, shouldFail: () => false),
            ),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();

      await openSettingsFromMenu(tester);

      final renameButton = find.byKey(
        const ValueKey('settings_rename_local_button'),
      );
      await tester.ensureVisible(renameButton);
      await tester.pumpAndSettle();
      await tester.tap(renameButton);
      await tester.pumpAndSettle();

      final renameInput = find.byKey(const ValueKey('rename_local_tdf_input'));
      await tester.tap(renameInput);
      await tester.pumpAndSettle();
      final renameClearBtn = find.byKey(
        const ValueKey('rename_local_tdf_input_clear_button'),
      );
      expect(
        renameClearBtn,
        findsOneWidget,
        reason: 'Focused RenameLocalTdfDialog field must show a clear button on the right',
      );
      await tester.tap(renameClearBtn);
      await tester.pump();
      expect(
        tester.widget<TextField>(renameInput).controller?.text,
        isEmpty,
        reason: 'Clicking clear in RenameLocalTdfDialog must delete its text',
      );
      await tester.tap(
        find.byKey(const ValueKey('rename_local_tdf_cancel_button')),
      );
      await tester.pumpAndSettle();

      for (final label in [
        'WebDAV Server URL',
        'Username',
        'App Password / Password',
        'TDF File Name / Path',
      ]) {
        final fieldFinder = find.widgetWithText(TextFormField, label);
        await tester.ensureVisible(fieldFinder);
        await tester.pumpAndSettle();
        await tester.tap(fieldFinder);
        await tester.pumpAndSettle();

        final clearBtn = find.descendant(
          of: fieldFinder,
          matching: find.byIcon(Icons.close_rounded),
        );
        expect(
          clearBtn,
          findsOneWidget,
          reason: 'Focused $label field must show a clear button on the right',
        );
        await tester.tap(clearBtn);
        await tester.pump();
        expect(
          tester.widget<TextFormField>(fieldFinder).controller?.text,
          isEmpty,
          reason: 'Clicking clear on $label must delete its text',
        );
      }
    },
  );

  testWidgets(
    'QuickAddBar, EditTaskScreen, TaskEditorConditionsSection, and EditLabelsScreen text fields show clear button when focused and clear text on click',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 08:00:00
  task 000001OkD2
}

label officeOkD2 {
  name "Office"
}
task 000001OkD2 {
  name "First Task"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
}
''';
      await tester.pumpWidget(
        ProviderScope(
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
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('add_task_fab')));
      await tester.pumpAndSettle();

      final quickAddInput = find.byKey(const ValueKey('quick_add_input'));
      await tester.enterText(quickAddInput, 'Draft task');
      await tester.pump();

      final quickAddClearBtn = find.descendant(
        of: quickAddInput,
        matching: find.byIcon(Icons.close_rounded),
      );
      expect(
        quickAddClearBtn,
        findsOneWidget,
        reason: 'Focused QuickAddBar input must display a clear button',
      );
      await tester.tap(quickAddClearBtn);
      await tester.pump();
      expect(
        tester.widget<TextField>(quickAddInput).controller?.text,
        isEmpty,
        reason:
            'Clicking clear in QuickAddBar input must delete the draft text',
      );

      await tester.tap(find.byKey(const ValueKey('quick_add_advanced_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('task_editor_repeat_button')));
      await tester.pump();

      for (final fieldKey in const [
        ValueKey('task_editor_title_input'),
        ValueKey('task_editor_note_input'),
        ValueKey('task_editor_repeat_count_input'),
        ValueKey('task_editor_subtask_input'),
        ValueKey('task_editor_blocked_search_input'),
        ValueKey('task_editor_time_start_input'),
        ValueKey('task_editor_time_end_input'),
      ]) {
        final fieldFinder = find.byKey(fieldKey);
        await tester.ensureVisible(fieldFinder);
        await tester.pumpAndSettle();
        await tester.tap(fieldFinder);
        await tester.pumpAndSettle();
        await tester.enterText(fieldFinder, 'sample');
        await tester.pumpAndSettle();

        final clearBtn = find.descendant(
          of: fieldFinder,
          matching: find.byIcon(Icons.close_rounded),
        );
        expect(
          clearBtn,
          findsOneWidget,
          reason: 'Focused $fieldKey must display a clear button on the right',
        );
        await tester.tap(clearBtn);
        await tester.pump();
        expect(
          tester.widget<TextField>(fieldFinder).controller?.text,
          isEmpty,
          reason: 'Clicking clear on $fieldKey must delete its text',
        );
      }

      await tester.ensureVisible(
        find.byKey(const ValueKey('task_editor_cancel_button')),
      );
      await tester.tap(find.byKey(const ValueKey('task_editor_cancel_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick_add_cancel_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('drawer_edit_labels_button')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('edit_label_button_officeOkD2')),
      );
      await tester.pumpAndSettle();

      final labelNameInput = find.byKey(
        const ValueKey('task_editor_title_input'),
      );
      final labelNameClearBtn = find.descendant(
        of: labelNameInput,
        matching: find.byIcon(Icons.close_rounded),
      );
      expect(
        labelNameClearBtn,
        findsOneWidget,
        reason: 'Focused label name input in EditLabelScreen must display a clear button',
      );
      await tester.tap(labelNameClearBtn);
      await tester.pump();
      expect(
        tester.widget<TextField>(labelNameInput).controller?.text,
        isEmpty,
        reason: 'Clicking clear on label name input in EditLabelScreen must delete its text',
      );

      final labelColorInput = find.byKey(
        const ValueKey('label_editor_color_input'),
      );
      await tester.tap(labelColorInput);
      await tester.pump();
      final labelColorClearBtn = find.descendant(
        of: labelColorInput,
        matching: find.byIcon(Icons.close_rounded),
      );
      expect(
        labelColorClearBtn,
        findsOneWidget,
        reason: 'Focused label color input in EditLabelScreen must display a clear button',
      );
      await tester.tap(labelColorClearBtn);
      await tester.pump();
      expect(
        tester.widget<TextField>(labelColorInput).controller?.text,
        isEmpty,
        reason: 'Clicking clear on label color input in EditLabelScreen must delete its text',
      );
    },
  );
}
