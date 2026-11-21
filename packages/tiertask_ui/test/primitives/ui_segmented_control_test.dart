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
import 'package:tiertask_ui/tiertask_ui.dart';

import '../test_helpers.dart';

/// Standard three-option segments reused across horizontal and vertical tests.
const List<UiSegment<String>> _placementSegments = <UiSegment<String>>[
  UiSegment<String>(value: 'queue', label: 'Queue'),
  UiSegment<String>(value: 'priority', label: 'Priority'),
  UiSegment<String>(value: 'someday', label: 'Someday'),
];

void main() {
  group('UiSegmentedControl horizontal mode', () {
    testWidgets(
      'selects segments on tap and steps with ArrowRight and ArrowLeft keys',
      (tester) async {
        var selected = 'queue';

        await pumpUiWidget(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              return Center(
                child: SizedBox(
                  width: 360,
                  child: UiSegmentedControl<String>(
                    value: selected,
                    segments: _placementSegments,
                    onChanged: (next) => setState(() => selected = next),
                  ),
                ),
              );
            },
          ),
        );

        final control = tester.widget<UiSegmentedControl<String>>(
          find.byType(UiSegmentedControl<String>),
        );
        expect(control.mode, equals(UiSegmentedControlMode.horizontal));
        expect(find.text('Queue'), findsOneWidget);
        expect(find.text('Priority'), findsOneWidget);
        expect(find.text('Someday'), findsOneWidget);

        await tester.tap(find.text('Priority'));
        await tester.pump();
        expect(selected, equals('priority'));

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(selected, equals('someday'));

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(selected, equals('priority'));
      },
    );

    testWidgets('skips disabled segments and respects control disabled state', (
      tester,
    ) async {
      var selected = 'a';
      await pumpUiWidget(
        tester,
        Center(
          child: SizedBox(
            width: 300,
            child: UiSegmentedControl<String>(
              value: selected,
              segments: const <UiSegment<String>>[
                UiSegment<String>(value: 'a', label: 'Alpha'),
                UiSegment<String>(value: 'b', label: 'Beta', enabled: false),
                UiSegment<String>(value: 'c', label: 'Gamma'),
              ],
              onChanged: (next) => selected = next,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Beta'));
      await tester.pump();
      expect(selected, equals('a'));
    });
  });

  group('UiSegmentedControl vertical combobox mode', () {
    testWidgets(
      'shows only selected segment while closed and animates open downward near top of viewport',
      (tester) async {
        var selected = 'queue';
        const segments = <UiSegment<String>>[
          UiSegment<String>(
            value: 'queue',
            label: 'Queue',
            icon: Icons.format_list_numbered_rounded,
          ),
          UiSegment<String>(
            value: 'priority',
            label: 'Priority',
            icon: Icons.bolt_rounded,
          ),
          UiSegment<String>(
            value: 'someday',
            label: 'Someday',
            icon: Icons.lightbulb_outline_rounded,
          ),
        ];

        await pumpUiWidget(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              return Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: UiSegmentedControl<String>(
                    mode: UiSegmentedControlMode.vertical,
                    value: selected,
                    segments: segments,
                    onChanged: (next) => setState(() => selected = next),
                  ),
                ),
              );
            },
          ),
        );

        final triggerFinder = find.byType(UiSegmentedControl<String>);
        expect(find.text('Queue'), findsOneWidget);
        expect(find.text('Priority'), findsNothing);
        expect(find.text('Someday'), findsNothing);
        expect(find.byIcon(Icons.format_list_numbered_rounded), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
        expect(
          tester.getSize(triggerFinder).height,
          greaterThanOrEqualTo(UiSpacingTokens.standard.touchTarget),
        );

        final triggerRect = tester.getRect(triggerFinder);
        await tester.tap(triggerFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));

        // Mid-animation frame must show partial opacity and partial expansion.
        final followerFinder = find.byType(CompositedTransformFollower);
        expect(followerFinder, findsOneWidget);
        final fadeMid = tester.widget<FadeTransition>(
          find.descendant(
            of: followerFinder,
            matching: find.byType(FadeTransition),
          ),
        );
        final sizeMid = tester.widget<SizeTransition>(
          find.descendant(
            of: followerFinder,
            matching: find.byType(SizeTransition),
          ),
        );
        expect(fadeMid.opacity.value, greaterThan(0.0));
        expect(fadeMid.opacity.value, lessThan(1.0));
        expect(sizeMid.sizeFactor.value, greaterThan(0.0));
        expect(sizeMid.sizeFactor.value, lessThan(1.0));
        expect(sizeMid.alignment, equals(Alignment.topCenter));

        await tester.pumpAndSettle();

        final popupSurfaceFinder = find.descendant(
          of: followerFinder,
          matching: find.byType(FadeTransition),
        );
        final popupRect = tester.getRect(popupSurfaceFinder);
        expect(
          popupRect.top,
          greaterThanOrEqualTo(triggerRect.bottom),
          reason:
              'Near top of viewport, popup must open downward below trigger',
        );
        expect(
          popupRect.width,
          greaterThanOrEqualTo(triggerRect.width),
          reason: 'Popup width must be at least the trigger width',
        );
        expect(find.text('Priority'), findsOneWidget);
        expect(find.text('Someday'), findsOneWidget);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);

        // Hover unselected option row -> bg fill + ink text; selected row -> soft fill + accent bold text.
        final tokens = UiThemePresets.calm.light;
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.text('Priority')));
        await tester.pumpAndSettle();

        final hoveredRow = tester.widget<AnimatedContainer>(
          find
              .ancestor(
                of: find.text('Priority'),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        if (hoveredRow.decoration case final BoxDecoration decoration) {
          expect(decoration.color, equals(tokens.colors.bg));
        }
        final hoveredText = tester.widget<Text>(find.text('Priority'));
        expect(hoveredText.style?.color, equals(tokens.colors.ink));

        final selectedRow = tester.widget<AnimatedContainer>(
          find
              .ancestor(
                of: find.text('Queue').last,
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        if (selectedRow.decoration case final BoxDecoration decoration) {
          expect(decoration.color, equals(tokens.colors.soft));
        }
        final selectedText = tester.widget<Text>(find.text('Queue').last);
        expect(selectedText.style?.color, equals(tokens.colors.accent));
        expect(selectedText.style?.fontWeight, equals(FontWeight.w600));

        // Selecting an option invokes callback, animates closed, and updates trigger.
        await tester.tap(find.text('Priority'));
        await tester.pump();
        expect(selected, equals('priority'));

        await tester.pump(const Duration(milliseconds: 80));
        expect(
          followerFinder,
          findsOneWidget,
          reason: 'Popup must remain mounted while reverse collapse animates',
        );

        await tester.pumpAndSettle();
        expect(followerFinder, findsNothing);
        expect(find.text('Priority'), findsOneWidget);
        expect(find.text('Queue'), findsNothing);
        expect(find.text('Someday'), findsNothing);
      },
    );

    testWidgets(
      'opens upward when placed near bottom of viewport such as a bottom dock',
      (tester) async {
        var selected = 'queue';

        await pumpUiWidget(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              return Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: UiSegmentedControl<String>(
                    mode: UiSegmentedControlMode.vertical,
                    value: selected,
                    segments: _placementSegments,
                    onChanged: (next) => setState(() => selected = next),
                  ),
                ),
              );
            },
          ),
        );

        final triggerFinder = find.byType(UiSegmentedControl<String>);
        final triggerRect = tester.getRect(triggerFinder);

        await tester.tap(triggerFinder);
        await tester.pumpAndSettle();

        final followerFinder = find.byType(CompositedTransformFollower);
        expect(followerFinder, findsOneWidget);
        final sizeTransition = tester.widget<SizeTransition>(
          find.descendant(
            of: followerFinder,
            matching: find.byType(SizeTransition),
          ),
        );
        expect(sizeTransition.alignment, equals(Alignment.bottomCenter));

        final popupSurfaceFinder = find.descendant(
          of: followerFinder,
          matching: find.byType(FadeTransition),
        );
        final popupRect = tester.getRect(popupSurfaceFinder);
        expect(
          popupRect.bottom,
          lessThanOrEqualTo(triggerRect.top),
          reason:
              'Near bottom of viewport, popup must open upward above trigger',
        );

        await tester.tap(find.text('Someday'));
        await tester.pumpAndSettle();
        expect(selected, equals('someday'));
        expect(followerFinder, findsNothing);
      },
    );

    testWidgets('respects disabled segment rows and disabled control state', (
      tester,
    ) async {
      var selected = 'a';
      var changedCount = 0;

      await pumpUiWidget(
        tester,
        Center(
          child: UiSegmentedControl<String>(
            mode: UiSegmentedControlMode.vertical,
            value: selected,
            segments: const <UiSegment<String>>[
              UiSegment<String>(value: 'a', label: 'Alpha'),
              UiSegment<String>(value: 'b', label: 'Beta', enabled: false),
              UiSegment<String>(value: 'c', label: 'Gamma'),
            ],
            onChanged: (next) {
              changedCount++;
              selected = next;
            },
          ),
        ),
      );

      await tester.tap(find.byType(UiSegmentedControl<String>));
      await tester.pumpAndSettle();

      final betaOpacity = tester.widget<Opacity>(
        find.ancestor(of: find.text('Beta'), matching: find.byType(Opacity)),
      );
      expect(
        betaOpacity.opacity,
        equals(UiFocusTokens.standard.disabledOpacity),
      );

      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      expect(selected, equals('a'));
      expect(changedCount, equals(0));
      expect(
        find.byType(CompositedTransformFollower),
        findsOneWidget,
        reason: 'Tapping a disabled option must not select or close the menu',
      );

      // Disabled entire control renders at disabledOpacity and cannot open.
      await pumpUiWidget(
        tester,
        const Center(
          child: UiSegmentedControl<String>(
            mode: UiSegmentedControlMode.vertical,
            value: 'a',
            enabled: false,
            segments: <UiSegment<String>>[
              UiSegment<String>(value: 'a', label: 'Alpha'),
              UiSegment<String>(value: 'b', label: 'Beta'),
            ],
            onChanged: null,
          ),
        ),
      );

      final disabledOpacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.byIcon(Icons.keyboard_arrow_down_rounded),
          matching: find.byType(Opacity),
        ),
      );
      expect(
        disabledOpacity.opacity,
        equals(UiFocusTokens.standard.disabledOpacity),
      );

      await tester.tap(find.byType(UiSegmentedControl<String>));
      await tester.pumpAndSettle();
      expect(find.byType(CompositedTransformFollower), findsNothing);
    });

    testWidgets(
      'dismisses via TapRegion outside tap without swallowing clicks on outside controls',
      (tester) async {
        var outsideTapped = 0;

        await pumpUiWidget(
          tester,
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              UiSegmentedControl<String>(
                mode: UiSegmentedControlMode.vertical,
                value: 'queue',
                segments: _placementSegments,
                onChanged: (_) {},
              ),
              const SizedBox(height: 200.0),
              UiButton(
                label: 'Outside Action',
                onPressed: () => outsideTapped++,
              ),
            ],
          ),
        );

        await tester.tap(find.byType(UiSegmentedControl<String>));
        await tester.pumpAndSettle();
        expect(find.byType(CompositedTransformFollower), findsOneWidget);

        await tester.tap(find.text('Outside Action'));
        await tester.pumpAndSettle();

        expect(
          outsideTapped,
          equals(1),
          reason: 'Outside TapRegion dismissal must not swallow outside clicks',
        );
        expect(find.byType(CompositedTransformFollower), findsNothing);
      },
    );

    testWidgets(
      'supports keyboard open, ArrowDown/ArrowUp skipping disabled options, Enter/Space selection, Escape without leaking, and focus restoration',
      (tester) async {
        var selected = 'a';
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
                  child: UiSegmentedControl<String>(
                    mode: UiSegmentedControlMode.vertical,
                    value: selected,
                    segments: const <UiSegment<String>>[
                      UiSegment<String>(value: 'a', label: 'Alpha'),
                      UiSegment<String>(
                        value: 'b',
                        label: 'Beta',
                        enabled: false,
                      ),
                      UiSegment<String>(value: 'c', label: 'Gamma'),
                    ],
                    onChanged: (next) => setState(() => selected = next),
                  ),
                );
              },
            ),
          ),
        );

        // Move keyboard focus onto the vertical trigger via Tab.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();

        final triggerFocus = FocusManager.instance.primaryFocus;
        expect(triggerFocus, isNotNull);

        // Open with Enter, move down (skipping disabled Beta to Gamma), verify inset accent highlight border, select with Enter.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(CompositedTransformFollower), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        final gammaContainer = tester.widget<AnimatedContainer>(
          find
              .ancestor(
                of: find.text('Gamma'),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        final gammaDecoration = gammaContainer.decoration;
        expect(gammaDecoration, isA<BoxDecoration>());
        if (gammaDecoration case final BoxDecoration decoration) {
          expect(
            decoration.border?.top.color,
            equals(UiThemePresets.calm.light.colors.accent),
            reason: 'Keyboard-highlighted option must paint 1px inset accent border',
          );
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(selected, equals('c'));
        expect(find.byType(CompositedTransformFollower), findsNothing);
        expect(
          FocusManager.instance.primaryFocus,
          equals(triggerFocus),
          reason: 'Selecting via Enter must restore focus to trigger',
        );

        // Open with ArrowUp, step up to Alpha, select with Space.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(find.byType(CompositedTransformFollower), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();

        expect(selected, equals('a'));
        expect(find.byType(CompositedTransformFollower), findsNothing);
        expect(FocusManager.instance.primaryFocus, equals(triggerFocus));

        // Open with Space, press Escape -> closes menu without leaking Escape to parent.
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(find.byType(CompositedTransformFollower), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(CompositedTransformFollower), findsNothing);
        expect(
          parentEscapeCount,
          equals(0),
          reason:
              'Escape while menu is open must not leak to outer Escape handler',
        );
        expect(FocusManager.instance.primaryFocus, equals(triggerFocus));

        // Pressing Escape while closed propagates cleanly to parent.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(parentEscapeCount, equals(1));
      },
    );

    testWidgets(
      're-elevates trigger fill inside UiSurfaceScope.insetWell and sizes cleanly in unbounded rows and tight widths',
      (tester) async {
        final tokens = UiThemePresets.calm.light;
        await pumpUiWidget(
          tester,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  UiSegmentedControl<String>(
                    key: const ValueKey<String>('panel_trigger'),
                    mode: UiSegmentedControlMode.vertical,
                    value: 'queue',
                    segments: _placementSegments,
                    onChanged: (_) {},
                  ),
                ],
              ),
              UiSurfaceScope(
                level: UiSurfaceLevel.insetWell,
                child: SizedBox(
                  width: 300.0,
                  child: UiSegmentedControl<String>(
                    key: const ValueKey<String>('inset_trigger'),
                    mode: UiSegmentedControlMode.vertical,
                    value: 'queue',
                    segments: _placementSegments,
                    onChanged: (_) {},
                  ),
                ),
              ),
            ],
          ),
          tokens: tokens,
        );

        expect(tester.takeException(), isNull);

        BoxDecoration? findTriggerDecoration(Key key) {
          final containers = tester.widgetList<AnimatedContainer>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(AnimatedContainer),
            ),
          );
          for (final container in containers) {
            if (container.decoration case final BoxDecoration decoration) {
              return decoration;
            }
          }
          return null;
        }

        expect(
          findTriggerDecoration(const ValueKey<String>('panel_trigger'))?.color,
          equals(tokens.colors.bg),
        );
        expect(
          findTriggerDecoration(const ValueKey<String>('inset_trigger'))?.color,
          equals(tokens.colors.panel),
        );
        expect(
          tester
              .getSize(find.byKey(const ValueKey<String>('panel_trigger')))
              .width,
          lessThan(200.0),
          reason:
              'Unconstrained trigger in Row must size intrinsically to content',
        );
        expect(
          tester
              .getSize(find.byKey(const ValueKey<String>('inset_trigger')))
              .width,
          equals(1280.0),
          reason: 'Stretched Column trigger must fill available width cleanly',
        );
      },
    );

    testWidgets(
      'renders cleanly across all 4 theme presets, compact vs desktop option heights, and disposes safely while open',
      (tester) async {
        final presets = <UiThemeTokens>[
          UiThemePresets.calm.light,
          UiThemePresets.calm.dark,
          UiThemePresets.plumUmber.light,
          UiThemePresets.plumUmber.dark,
        ];

        for (var presetIndex = 0; presetIndex < presets.length; presetIndex++) {
          final tokens = presets[presetIndex];
          for (final width in <double>[390.0, 1280.0]) {
            await pumpUiWidget(
              tester,
              Center(
                child: UiSegmentedControl<String>(
                  key: ValueKey<String>('preset_${presetIndex}_$width'),
                  mode: UiSegmentedControlMode.vertical,
                  value: 'queue',
                  segments: _placementSegments,
                  onChanged: (_) {},
                ),
              ),
              tokens: tokens,
              surfaceSize: Size(width, 800.0),
            );

            await tester.tap(find.byType(UiSegmentedControl<String>));
            await tester.pumpAndSettle();

            final expectedMinRowHeight = width <= 720.0
                ? UiSpacingTokens.standard.touchTargetMobile
                : UiSpacingTokens.standard.chromeControlHeight;
            final optionRowFinder = find.ancestor(
              of: find.text('Priority'),
              matching: find.byType(AnimatedContainer),
            );
            expect(
              tester.getSize(optionRowFinder.first).height,
              greaterThanOrEqualTo(expectedMinRowHeight),
              reason:
                  'Option row height must match density at width=$width (${tokens.brightness})',
            );
            expect(tester.takeException(), isNull);
          }
        }

        // Verify narrow 390px viewport with longer German labels fits without overflow.
        await pumpUiWidget(
          tester,
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: UiSegmentedControl<String>(
                key: const ValueKey<String>('german_compact_vertical'),
                mode: UiSegmentedControlMode.vertical,
                value: 'queue',
                segments: const <UiSegment<String>>[
                  UiSegment<String>(value: 'queue', label: 'Warteschlange'),
                  UiSegment<String>(value: 'priority', label: 'Priorität'),
                  UiSegment<String>(value: 'someday', label: 'Irgendwann'),
                ],
                onChanged: (_) {},
              ),
            ),
          ),
          surfaceSize: const Size(390.0, 800.0),
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('german_compact_vertical')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Priorität'), findsOneWidget);
        expect(find.text('Irgendwann'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Unmount while popup is mid-open animation -> zero ticker/overlay exceptions.
        await pumpUiWidget(
          tester,
          Center(
            child: UiSegmentedControl<String>(
              mode: UiSegmentedControlMode.vertical,
              value: 'queue',
              segments: _placementSegments,
              onChanged: (_) {},
            ),
          ),
        );
        await tester.tap(find.byType(UiSegmentedControl<String>));
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'preserves full slot width and element stability under FocusHighlightStrategy.alwaysTraditional in horizontal and vertical modes',
      (tester) async {
        final previousStrategy = FocusManager.instance.highlightStrategy;
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        addTearDown(() {
          FocusManager.instance.highlightStrategy = previousStrategy;
        });

        var horizontalValue = 'queue';
        var horizontalChanges = 0;
        var verticalValue = 'queue';
        final verticalFocusNode = FocusNode();
        addTearDown(verticalFocusNode.dispose);

        await pumpUiWidget(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: 252.0,
                    child: UiSegmentedControl<String>(
                      key: const ValueKey<String>('focused_horizontal_control'),
                      value: horizontalValue,
                      segments: _placementSegments,
                      onChanged: (next) {
                        horizontalChanges += 1;
                        setState(() => horizontalValue = next);
                      },
                    ),
                  ),
                  const SizedBox(height: 24.0),
                  SizedBox(
                    width: 252.0,
                    child: Focus(
                      focusNode: verticalFocusNode,
                      skipTraversal: true,
                      child: UiSegmentedControl<String>(
                        key: const ValueKey<String>('focused_vertical_control'),
                        mode: UiSegmentedControlMode.vertical,
                        value: verticalValue,
                        segments: _placementSegments,
                        onChanged: (next) {
                          setState(() => verticalValue = next);
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );

        final horizontalControlFinder = find.byKey(
          const ValueKey<String>('focused_horizontal_control'),
        );
        final queueTabFinder = find.descendant(
          of: horizontalControlFinder,
          matching: find.ancestor(
            of: find.text('Queue'),
            matching: find.byType(AnimatedContainer),
          ),
        );
        final queueExpandedFinder = find.descendant(
          of: horizontalControlFinder,
          matching: find.ancestor(
            of: find.text('Queue'),
            matching: find.byType(Expanded),
          ),
        );
        final queueElementBefore = tester.element(queueTabFinder);
        final expectedSlotWidth = tester.getSize(queueExpandedFinder).width;

        // Tapping Queue focuses it on desktop traditional highlight mode; inner tab must fill slot width.
        await tester.tap(
          find.descendant(
            of: horizontalControlFinder,
            matching: find.text('Queue'),
          ),
        );
        await tester.pump();
        expect(
          tester.element(queueTabFinder),
          same(queueElementBefore),
          reason: 'Toggling focus ring must not unmount and remount AnimatedContainer',
        );
        expect(
          tester.getSize(queueTabFinder).width,
          closeTo(expectedSlotWidth, 0.1),
          reason: 'Focused horizontal segment must retain full Expanded slot width inside focus ring',
        );

        // Switching to Priority fires onChanged strictly once across 250ms of 16ms ticks and retains full slot width.
        horizontalChanges = 0;
        await tester.tap(
          find.descendant(
            of: horizontalControlFinder,
            matching: find.text('Priority'),
          ),
        );
        for (var i = 0; i < 16; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            horizontalChanges,
            equals(1),
            reason: 'onChanged must fire strictly once without oscillation',
          );
          expect(horizontalValue, equals('priority'));
        }
        final priorityTabFinder = find.descendant(
          of: horizontalControlFinder,
          matching: find.ancestor(
            of: find.text('Priority'),
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(
          tester.getSize(priorityTabFinder).width,
          closeTo(expectedSlotWidth, 0.1),
          reason: 'Focused Priority segment must retain full Expanded slot width inside focus ring',
        );

        // Vertical trigger inside tight 252px SizedBox keeps full 252px width when focused.
        final verticalControlFinder = find.byKey(
          const ValueKey<String>('focused_vertical_control'),
        );
        final verticalTriggerContainer = find.ancestor(
          of: find.descendant(
            of: verticalControlFinder,
            matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
          ),
          matching: find.byType(AnimatedContainer),
        );
        final verticalElementBefore = tester.element(verticalTriggerContainer);
        await tester.tap(verticalControlFinder);
        await tester.pump();
        expect(
          tester.element(verticalTriggerContainer),
          same(verticalElementBefore),
          reason: 'Focusing vertical trigger must not reparent its GlobalKey AnimatedContainer',
        );
        expect(
          tester.getSize(verticalTriggerContainer).width,
          closeTo(252.0, 0.1),
          reason: 'Focused vertical trigger must keep full tight 252px width inside focus ring',
        );
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'toggling enabled preserves horizontal and vertical elements without double-dimming and suppresses no-op re-selection',
      (tester) async {
        var horizontalValue = 'queue';
        var verticalValue = 'queue';
        var horizontalEnabled = true;
        var verticalEnabled = true;
        var horizontalChanges = 0;
        var verticalChanges = 0;
        late StateSetter rebuildHost;

        await pumpUiWidget(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              rebuildHost = setState;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: 360.0,
                    child: UiSegmentedControl<String>(
                      key: const ValueKey<String>('toggle_horizontal_control'),
                      value: horizontalValue,
                      enabled: horizontalEnabled,
                      segments: const <UiSegment<String>>[
                        UiSegment<String>(value: 'queue', label: 'Queue'),
                        UiSegment<String>(value: 'priority', label: 'Priority'),
                        UiSegment<String>(
                          value: 'someday',
                          label: 'Someday',
                          enabled: false,
                        ),
                      ],
                      onChanged: (next) {
                        horizontalChanges++;
                        setState(() => horizontalValue = next);
                      },
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  SizedBox(
                    width: 240.0,
                    child: UiSegmentedControl<String>(
                      key: const ValueKey<String>('toggle_vertical_control'),
                      mode: UiSegmentedControlMode.vertical,
                      value: verticalValue,
                      enabled: verticalEnabled,
                      segments: _placementSegments,
                      onChanged: (next) {
                        verticalChanges++;
                        setState(() => verticalValue = next);
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );

        final horizontalControl = find.byKey(
          const ValueKey<String>('toggle_horizontal_control'),
        );
        final verticalControl = find.byKey(
          const ValueKey<String>('toggle_vertical_control'),
        );
        final queueTabContainer = find.descendant(
          of: horizontalControl,
          matching: find.ancestor(
            of: find.text('Queue'),
            matching: find.byType(AnimatedContainer),
          ),
        );
        final somedayTabContainer = find.descendant(
          of: horizontalControl,
          matching: find.ancestor(
            of: find.text('Someday'),
            matching: find.byType(AnimatedContainer),
          ),
        );
        final verticalTriggerContainer = find.descendant(
          of: verticalControl,
          matching: find.byType(AnimatedContainer),
        );

        final queueElementBefore = tester.element(queueTabContainer);
        final somedayElementBefore = tester.element(somedayTabContainer);
        final verticalElementBefore = tester.element(verticalTriggerContainer);

        // Tapping the already-selected horizontal segment must not emit a redundant onChanged.
        await tester.tap(
          find.descendant(of: horizontalControl, matching: find.text('Queue')),
        );
        await tester.pump();
        expect(
          horizontalChanges,
          equals(0),
          reason: 'Re-tapping the already-selected horizontal segment must be a no-op',
        );

        // Tapping the already-selected vertical option closes the menu without firing onChanged.
        await tester.tap(verticalControl);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(CompositedTransformFollower),
            matching: find.text('Queue'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          verticalChanges,
          equals(0),
          reason: 'Re-selecting the already-selected vertical option must be a no-op',
        );

        // Compute effective product of Opacity ancestors inside horizontal control.
        double effectiveOpacity(Element target) {
          var product = 1.0;
          target.visitAncestorElements((ancestor) {
            if (ancestor.widget case final Opacity opacityWidget) {
              product *= opacityWidget.opacity;
            }
            return ancestor.widget is! UiSegmentedControl;
          });
          return product;
        }

        expect(
          effectiveOpacity(queueElementBefore),
          closeTo(1.0, 0.001),
          reason:
              'Enabled segment inside enabled control must have opacity 1.0',
        );
        expect(
          effectiveOpacity(somedayElementBefore),
          closeTo(UiFocusTokens.standard.disabledOpacity, 0.001),
          reason: 'Individually disabled segment must render at disabledOpacity once',
        );

        // Disable both controls: elements must NOT unmount/remount and opacity must NOT double-dim.
        rebuildHost(() {
          horizontalEnabled = false;
          verticalEnabled = false;
        });
        await tester.pump();

        expect(
          tester.element(queueTabContainer),
          same(queueElementBefore),
          reason: 'Disabling horizontal control must not unmount/remount tab AnimatedContainer',
        );
        expect(
          tester.element(somedayTabContainer),
          same(somedayElementBefore),
          reason: 'Disabling horizontal control must not unmount/remount disabled segment',
        );
        expect(
          tester.element(verticalTriggerContainer),
          same(verticalElementBefore),
          reason: 'Disabling vertical control must not unmount/remount trigger AnimatedContainer',
        );
        expect(
          effectiveOpacity(tester.element(queueTabContainer)),
          closeTo(UiFocusTokens.standard.disabledOpacity, 0.001),
          reason: 'Disabled horizontal control must apply disabledOpacity once (0.48, not 0.23)',
        );
        expect(
          effectiveOpacity(tester.element(somedayTabContainer)),
          closeTo(UiFocusTokens.standard.disabledOpacity, 0.001),
          reason: 'Disabled segment inside disabled horizontal control must not double-dim',
        );

        // Re-enable both controls: elements must remain identical.
        rebuildHost(() {
          horizontalEnabled = true;
          verticalEnabled = true;
        });
        await tester.pump();

        expect(
          tester.element(queueTabContainer),
          same(queueElementBefore),
          reason: 'Re-enabling horizontal control must preserve tab AnimatedContainer element',
        );
        expect(
          tester.element(verticalTriggerContainer),
          same(verticalElementBefore),
          reason: 'Re-enabling vertical control must preserve trigger AnimatedContainer element',
        );
      },
    );
  });
}
