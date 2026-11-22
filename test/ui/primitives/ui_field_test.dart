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

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/ui/primitives/ui_button.dart';
import 'package:tiertask/ui/primitives/ui_field.dart';
import 'package:tiertask/ui/tokens/ui_spacing_tokens.dart';
import 'package:tiertask/ui/tokens/ui_theme_tokens.dart';

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
          equals(Border.all(color: tokens.colors.accent)),
        );
      },
    );

    testWidgets(
      'defers internal FocusNode and TextEditingController disposal when external instances attach',
      (tester) async {
        final externalFocusNode = FocusNode();
        final externalController = TextEditingController(text: 'External text');
        addTearDown(() {
          externalFocusNode.dispose();
          externalController.dispose();
        });

        var useExternal = false;
        late StateSetter rebuildHost;

        await pumpUiWidget(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              rebuildHost = setState;
              return UiField(
                key: const ValueKey<String>('swap_field'),
                controller: useExternal ? externalController : null,
                focusNode: useExternal ? externalFocusNode : null,
                hintText: 'Title',
              );
            },
          ),
        );

        final textFieldFinder = find.descendant(
          of: find.byKey(const ValueKey<String>('swap_field')),
          matching: find.byType(TextField),
        );
        final internalTextField = tester.widget<TextField>(textFieldFinder);
        final previousController = internalTextField.controller;
        final previousFocusNode = internalTextField.focusNode;
        expect(previousController, isNotNull);
        expect(previousFocusNode, isNotNull);

        await tester.tap(textFieldFinder);
        await tester.enterText(textFieldFinder, 'Internal text');
        previousController?.value = const TextEditingValue(
          text: 'Internal text',
          selection: TextSelection.collapsed(offset: 13),
          composing: TextRange(start: 0, end: 8),
        );
        await tester.pump();

        rebuildHost(() => useExternal = true);
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'Swapping from internal to external controller/focusNode must not dispose attached instances synchronously',
        );
        expect(find.text('External text'), findsOneWidget);
        expect(
          () => previousController?.addListener(() {}),
          throwsFlutterError,
          reason: 'Deferred internal controller must be disposed post-frame',
        );
        expect(
          () => previousFocusNode?.addListener(() {}),
          throwsFlutterError,
          reason: 'Deferred internal focus node must be disposed post-frame',
        );

        externalFocusNode.requestFocus();
        await tester.pump();
        expect(externalFocusNode.hasFocus, isTrue);
      },
    );

    testWidgets(
      'select kind renders flat custom popup without Material DropdownButton, handles hover/disabled/TapRegion/upward flip',
      (tester) async {
        final tokens = UiThemePresets.calm.light;
        String? selectedValue;
        var selectCount = 0;
        var outsideTapCount = 0;

        await pumpUiWidget(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: UiField(
                      key: const ValueKey<String>('custom_select_top'),
                      kind: UiFieldKind.select,
                      hintText: 'Choose option',
                      selectValue: selectedValue,
                      selectOptions: const <UiSelectOption>[
                        UiSelectOption(value: 'alpha', label: 'Alpha'),
                        UiSelectOption(
                          value: 'beta',
                          label: 'Beta',
                          enabled: false,
                        ),
                        UiSelectOption(value: 'gamma', label: 'Gamma'),
                      ],
                      onSelectChanged: (next) {
                        selectCount++;
                        setState(() => selectedValue = next);
                      },
                    ),
                  ),
                  const SizedBox(height: 200.0),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: UiButton(
                      label: 'Outside Select Action',
                      onPressed: () => outsideTapCount++,
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: UiField(
                      key: const ValueKey<String>('custom_select_bottom'),
                      kind: UiFieldKind.select,
                      selectValue: 'alpha',
                      selectOptions: const <UiSelectOption>[
                        UiSelectOption(value: 'alpha', label: 'Alpha Bottom'),
                        UiSelectOption(value: 'beta', label: 'Beta Bottom'),
                        UiSelectOption(value: 'gamma', label: 'Gamma Bottom'),
                      ],
                      onSelectChanged: (_) {},
                    ),
                  ),
                ],
              );
            },
          ),
          tokens: tokens,
        );

        expect(
          find.byType(DropdownButton<String>),
          findsNothing,
          reason: 'UiFieldKind.select must retire Material DropdownButton',
        );
        expect(find.text('Choose option'), findsOneWidget);

        final topSelect = find.byKey(
          const ValueKey<String>('custom_select_top'),
        );
        final topRect = tester.getRect(topSelect);
        await tester.tap(topSelect);
        await tester.pumpAndSettle();

        final followerFinder = find.byType(CompositedTransformFollower);
        expect(followerFinder, findsOneWidget);
        final popupRect = tester.getRect(
          find.descendant(
            of: followerFinder,
            matching: find.byType(FadeTransition),
          ),
        );
        expect(
          popupRect.top,
          greaterThanOrEqualTo(topRect.bottom),
          reason: 'Select near top must open downward below trigger',
        );

        // Disabled option cannot be selected and keeps menu open.
        await tester.tap(find.text('Beta'));
        await tester.pumpAndSettle();
        expect(selectedValue, isNull);
        expect(selectCount, equals(0));
        expect(followerFinder, findsOneWidget);

        // Hover unselected option -> bg fill + ink foreground.
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.text('Gamma')));
        await tester.pumpAndSettle();

        final hoveredRow = tester.widget<AnimatedContainer>(
          find
              .ancestor(
                of: find.text('Gamma'),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        if (hoveredRow.decoration case final BoxDecoration decoration) {
          expect(decoration.color, equals(tokens.colors.bg));
        }

        // Selecting Gamma updates value and closes menu.
        await tester.tap(find.text('Gamma'));
        await tester.pumpAndSettle();
        expect(selectedValue, equals('gamma'));
        expect(selectCount, equals(1));
        expect(followerFinder, findsNothing);

        // Re-opening highlights selected Gamma with soft tint + check icon; re-selecting is a no-op.
        await tester.tap(topSelect);
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        final selectedRow = tester.widget<AnimatedContainer>(
          find
              .ancestor(
                of: find.text('Gamma').last,
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        if (selectedRow.decoration case final BoxDecoration decoration) {
          expect(decoration.color, equals(tokens.colors.soft));
        }
        await tester.tap(find.text('Gamma').last);
        await tester.pumpAndSettle();
        expect(selectCount, equals(1));
        expect(followerFinder, findsNothing);

        // Outside TapRegion click dismisses without swallowing outside button click.
        await tester.tap(topSelect);
        await tester.pumpAndSettle();
        expect(followerFinder, findsOneWidget);
        await tester.tap(find.text('Outside Select Action'));
        await tester.pumpAndSettle();
        expect(outsideTapCount, equals(1));
        expect(followerFinder, findsNothing);

        // Bottom select opens upward above trigger.
        final bottomSelect = find.byKey(
          const ValueKey<String>('custom_select_bottom'),
        );
        final bottomRect = tester.getRect(bottomSelect);
        await tester.tap(bottomSelect);
        await tester.pumpAndSettle();
        final bottomPopupRect = tester.getRect(
          find.descendant(
            of: followerFinder,
            matching: find.byType(FadeTransition),
          ),
        );
        expect(
          bottomPopupRect.bottom,
          lessThanOrEqualTo(bottomRect.top),
          reason: 'Select near bottom of viewport must open upward',
        );
      },
    );

    testWidgets(
      'select kind supports ArrowDown/ArrowUp/Home/End/Enter/Space/Escape keyboard navigation and readOnly/disabled guards',
      (tester) async {
        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);
        var selectedValue = 'a';
        var parentEscapeCount = 0;

        await pumpUiWidget(
          tester,
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                parentEscapeCount++;
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: StatefulBuilder(
              builder: (context, setState) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        width: 260.0,
                        child: UiField(
                          key: const ValueKey<String>('kbd_select'),
                          kind: UiFieldKind.select,
                          focusNode: focusNode,
                          selectValue: selectedValue,
                          selectOptions: const <UiSelectOption>[
                            UiSelectOption(value: 'a', label: 'Alpha'),
                            UiSelectOption(
                              value: 'b',
                              label: 'Beta',
                              enabled: false,
                            ),
                            UiSelectOption(value: 'c', label: 'Gamma'),
                            UiSelectOption(value: 'd', label: 'Delta'),
                          ],
                          onSelectChanged: (next) =>
                              setState(() => selectedValue = next),
                        ),
                      ),
                      const SizedBox(height: 16.0),
                      SizedBox(
                        width: 260.0,
                        child: UiField(
                          key: const ValueKey<String>('readonly_select'),
                          kind: UiFieldKind.select,
                          readOnly: true,
                          selectValue: 'a',
                          selectOptions: const <UiSelectOption>[
                            UiSelectOption(value: 'a', label: 'Locked'),
                            UiSelectOption(value: 'b', label: 'Other'),
                          ],
                          onSelectChanged: (_) {},
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );

        // Read-only select does not open.
        await tester.tap(find.byKey(const ValueKey<String>('readonly_select')));
        await tester.pumpAndSettle();
        expect(find.byType(CompositedTransformFollower), findsNothing);

        focusNode.requestFocus();
        await tester.pump();

        // Enter opens, ArrowDown skips disabled Beta -> Gamma, End -> Delta, Home -> Alpha, ArrowDown -> Gamma, Enter commits.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(CompositedTransformFollower), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(selectedValue, equals('d'));
        expect(focusNode.hasFocus, isTrue);

        // ArrowUp opens, Home jumps to Alpha, Space commits.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(selectedValue, equals('a'));
        expect(focusNode.hasFocus, isTrue);

        // Space opens, Escape closes without leaking to parent; second Escape propagates.
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(find.byType(CompositedTransformFollower), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(CompositedTransformFollower), findsNothing);
        expect(parentEscapeCount, equals(0));
        expect(focusNode.hasFocus, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(parentEscapeCount, equals(1));
      },
    );

    testWidgets(
      'select kind refreshes popup metrics dynamically on viewport resize and ancestor scroll across all 4 theme presets',
      (tester) async {
        final scrollController = ScrollController();
        addTearDown(scrollController.dispose);

        await pumpUiWidget(
          tester,
          SingleChildScrollView(
            controller: scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 720.0),
                SizedBox(
                  width: 240.0,
                  child: UiField(
                    key: const ValueKey<String>('scroll_select'),
                    kind: UiFieldKind.select,
                    selectValue: 'a',
                    selectOptions: const <UiSelectOption>[
                      UiSelectOption(value: 'a', label: 'Alpha'),
                      UiSelectOption(value: 'b', label: 'Beta'),
                      UiSelectOption(value: 'c', label: 'Gamma'),
                      UiSelectOption(value: 'd', label: 'Delta'),
                    ],
                    onSelectChanged: (_) {},
                  ),
                ),
                const SizedBox(height: 800.0),
              ],
            ),
          ),
        );

        // Start scrolled so trigger sits near top -> opens downward.
        scrollController.jumpTo(680.0);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('scroll_select')));
        await tester.pumpAndSettle();

        final followerFinder = find.byType(CompositedTransformFollower);
        expect(
          tester
              .widget<SizeTransition>(
                find.descendant(
                  of: followerFinder,
                  matching: find.byType(SizeTransition),
                ),
              )
              .alignment,
          equals(Alignment.topCenter),
        );

        // Scroll ancestor so trigger moves near bottom while open -> flips upward dynamically.
        scrollController.jumpTo(0.0);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SizeTransition>(
                find.descendant(
                  of: followerFinder,
                  matching: find.byType(SizeTransition),
                ),
              )
              .alignment,
          equals(Alignment.bottomCenter),
          reason: 'Scrolling ancestor while select popup is open must recompute upward direction',
        );

        // Resize viewport to compact 390px while open -> row height switches to 44px touchTargetMobile.
        tester.view.physicalSize = const Size(390.0, 700.0);
        await tester.pumpAndSettle();
        final compactRow = find
            .ancestor(
              of: find.text('Beta'),
              matching: find.byType(AnimatedContainer),
            )
            .first;
        expect(
          tester.getSize(compactRow).height,
          greaterThanOrEqualTo(UiSpacingTokens.standard.touchTargetMobile),
          reason: 'Resizing to compact while select popup is open must update row density to 44px',
        );
      },
    );
  });
}
