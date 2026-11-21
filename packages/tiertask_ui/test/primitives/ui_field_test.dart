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

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import '../test_helpers.dart';

void main() {
  group('UiField', () {
    testWidgets(
      'renders every UiFieldKind with surface re-elevation inside insetWell',
      (tester) async {
        final textController = TextEditingController(text: 'Initial');
        final searchController = TextEditingController(text: 'Query');
        final passwordController = TextEditingController(text: 'secret');
        addTearDown(() {
          textController.dispose();
          searchController.dispose();
          passwordController.dispose();
        });

        var selectedValue = 'focus';
        var dateTapped = false;
        var cleared = false;
        final tokens = UiThemePresets.calm.light;

        await pumpUiWidget(
          tester,
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                UiField(
                  key: const ValueKey<String>('field_text'),
                  kind: UiFieldKind.text,
                  label: 'Title',
                  controller: textController,
                  helperText: 'Helper note',
                  errorText: 'Required field',
                  showClearButton: true,
                  clearTooltip: 'Clear title',
                  onClear: () => cleared = true,
                ),
                const UiField(
                  key: ValueKey<String>('field_multiline'),
                  kind: UiFieldKind.multiline,
                  label: 'Notes',
                  hintText: 'Write details',
                ),
                UiField(
                  key: const ValueKey<String>('field_password'),
                  kind: UiFieldKind.password,
                  label: 'Password',
                  controller: passwordController,
                  showPasswordTooltip: 'Show password',
                  hidePasswordTooltip: 'Hide password',
                ),
                StatefulBuilder(
                  builder: (context, setState) {
                    return UiField(
                      key: const ValueKey<String>('field_select'),
                      kind: UiFieldKind.select,
                      label: 'Tier',
                      height: 44.0,
                      borderRadius: tokens.radii.tierSelect,
                      selectValue: selectedValue,
                      selectOptions: const <UiSelectOption>[
                        UiSelectOption(value: 'focus', label: 'Focus · 2'),
                        UiSelectOption(value: 'ready', label: 'Ready · 4'),
                      ],
                      onSelectChanged: (next) =>
                          setState(() => selectedValue = next),
                    );
                  },
                ),
                UiField(
                  key: const ValueKey<String>('field_datetime'),
                  kind: UiFieldKind.dateTime,
                  label: 'Due date',
                  displayValue: '2026-11-22 09:00',
                  onTap: () => dateTapped = true,
                ),
                UiField(
                  key: const ValueKey<String>('field_search'),
                  kind: UiFieldKind.search,
                  controller: searchController,
                  hintText: 'Search tasks',
                  clearTooltip: 'Clear search',
                ),
                const UiSurfaceScope(
                  level: UiSurfaceLevel.insetWell,
                  child: UiField(
                    key: ValueKey<String>('field_readonly'),
                    kind: UiFieldKind.readOnlyDisplay,
                    label: 'Resolved endpoint',
                    displayValue: 'https://cloud.example.com/tasks.tdf',
                    readOnly: true,
                  ),
                ),
              ],
            ),
          ),
          tokens: tokens,
        );

        expect(find.text('Helper note'), findsOneWidget);
        expect(find.text('Required field'), findsOneWidget);

        // Clear button clears text field and triggers callback.
        await tester.tap(find.byTooltip('Clear title'));
        await tester.pump();
        expect(textController.text, isEmpty);
        expect(cleared, isTrue);

        // Password toggle switches obscureText.
        final passwordFieldBefore = tester.widget<TextField>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('field_password')),
            matching: find.byType(TextField),
          ),
        );
        expect(passwordFieldBefore.obscureText, isTrue);
        await tester.tap(find.byTooltip('Show password'));
        await tester.pump();
        final passwordFieldAfter = tester.widget<TextField>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('field_password')),
            matching: find.byType(TextField),
          ),
        );
        expect(passwordFieldAfter.obscureText, isFalse);

        // Date/time field handles tap.
        await tester.tap(find.text('2026-11-22 09:00'));
        await tester.pump();
        expect(dateTapped, isTrue);

        // Search clear button clears query.
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pump();
        expect(searchController.text, isEmpty);

        // Readonly inside insetWell has 0.72 opacity and re-elevated panel fill.
        final readonlyOpacity = tester.widget<Opacity>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('field_readonly')),
            matching: find.byType(Opacity),
          ),
        );
        expect(readonlyOpacity.opacity, equals(0.72));

        final insetDecorated = find.descendant(
          of: find.byKey(const ValueKey<String>('field_readonly')),
          matching: find.byWidgetPredicate((widget) {
            if (widget is! AnimatedContainer) {
              return false;
            }
            final decoration = widget.decoration;
            return decoration is BoxDecoration &&
                decoration.color == tokens.colors.panel;
          }),
        );
        expect(insetDecorated, findsOneWidget);
      },
    );

    testWidgets(
      'switches container border to accent on focus without outer ring',
      (tester) async {
        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);
        final tokens = UiThemePresets.calm.light;

        await pumpUiWidget(
          tester,
          UiField(
            key: const ValueKey<String>('focus_search'),
            kind: UiFieldKind.search,
            focusNode: focusNode,
            hintText: 'Filter',
          ),
          tokens: tokens,
        );

        focusNode.requestFocus();
        await tester.pumpAndSettle();

        final container = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('focus_search')),
            matching: find.byType(AnimatedContainer),
          ),
        );
        final decoration = container.decoration as BoxDecoration?;
        expect(
          decoration?.border,
          equals(Border.all(color: tokens.colors.accent, width: 1.0)),
        );
      },
    );
  });
}
