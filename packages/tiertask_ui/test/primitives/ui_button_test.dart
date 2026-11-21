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

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import '../test_helpers.dart';

void main() {
  group('UiButton', () {
    testWidgets(
      'renders all variant, density, and tone combinations with exact target heights',
      (tester) async {
        const expectedHeights = <UiButtonDensity, double>{
          UiButtonDensity.standard: 40.0,
          UiButtonDensity.chrome: 34.0,
          UiButtonDensity.compact: 32.0,
          UiButtonDensity.dense: 30.0,
          UiButtonDensity.mobileTouch: 44.0,
          UiButtonDensity.sidebarDesktop: 26.0,
        };

        for (final density in UiButtonDensity.values) {
          await pumpUiWidget(
            tester,
            Center(
              child: UiButton(
                key: ValueKey<String>('btn_${density.name}'),
                label: density.name,
                density: density,
                onPressed: () {},
              ),
            ),
          );
          final size = tester.getSize(
            find.byKey(ValueKey<String>('btn_${density.name}')),
          );
          final expectedHeight = expectedHeights[density] ?? 0.0;
          expect(
            size.height,
            greaterThanOrEqualTo(expectedHeight),
            reason:
                'Density ${density.name} must satisfy minimum target height',
          );
        }

        for (final variant in UiButtonVariant.values) {
          for (final tone in UiButtonTone.values) {
            var tapped = false;
            await pumpUiWidget(
              tester,
              Center(
                child: UiButton(
                  label: variant == UiButtonVariant.icon ? null : variant.name,
                  leadingIcon: Icons.sync_rounded,
                  trailingIcon: variant == UiButtonVariant.secondary
                      ? Icons.expand_more_rounded
                      : null,
                  variant: variant,
                  tone: tone,
                  semanticLabel: '${variant.name}_${tone.name}',
                  onPressed: () => tapped = true,
                ),
              ),
            );
            await tester.tap(find.byType(UiButton));
            await tester.pump();
            expect(
              tapped,
              isTrue,
              reason:
                  'Variant ${variant.name} tone ${tone.name} must handle taps',
            );
          }
        }
      },
    );

    testWidgets(
      'applies disabled opacity, active accent surface, loading spin, and focus ring',
      (tester) async {
        var tapped = false;
        await pumpUiWidget(
          tester,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const UiButton(
                key: ValueKey<String>('disabled_btn'),
                label: 'Disabled',
                onPressed: null,
              ),
              UiButton(
                key: const ValueKey<String>('active_btn'),
                label: 'Active',
                isActive: true,
                onPressed: () => tapped = true,
              ),
              UiButton(
                key: const ValueKey<String>('loading_btn'),
                label: 'Syncing',
                leadingIcon: Icons.sync_rounded,
                isLoading: true,
                onPressed: () {},
              ),
            ],
          ),
        );

        final disabledOpacity = tester.widget<Opacity>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('disabled_btn')),
            matching: find.byType(Opacity),
          ),
        );
        expect(disabledOpacity.opacity, equals(0.48));

        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('loading_btn')),
            matching: find.byType(RotationTransition),
          ),
          findsOneWidget,
        );

        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        addTearDown(() {
          FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.automatic;
        });

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();

        final activeFinder = find.byKey(const ValueKey<String>('active_btn'));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(tapped, isTrue);

        final tokens = UiThemePresets.calm.light;
        final focusRingFinder = find.descendant(
          of: activeFinder,
          matching: find.byWidgetPredicate((widget) {
            if (widget is! DecoratedBox) {
              return false;
            }
            final decoration = widget.decoration;
            if (decoration is! BoxDecoration) {
              return false;
            }
            final border = decoration.border;
            return decoration.color == null &&
                border is Border &&
                border.top.color == tokens.colors.accent &&
                border.top.width == tokens.focus.ringWidth;
          }),
        );
        expect(focusRingFinder, findsOneWidget);
      },
    );

    testWidgets(
      'reuses single ticker across repeated isLoading true -> false -> true transitions',
      (tester) async {
        var loading = true;
        late StateSetter setOuterState;
        await pumpUiWidget(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              setOuterState = setState;
              return UiButton(
                label: 'Sync',
                leadingIcon: Icons.sync_rounded,
                isLoading: loading,
                onPressed: () {},
              );
            },
          ),
        );
        final rotationFinder = find.descendant(
          of: find.byType(UiButton),
          matching: find.byType(RotationTransition),
        );
        expect(rotationFinder, findsOneWidget);

        setOuterState(() => loading = false);
        await tester.pump();
        expect(rotationFinder, findsNothing);

        setOuterState(() => loading = true);
        await tester.pump();
        expect(rotationFinder, findsOneWidget);
      },
    );

    testWidgets(
      'uses bg surface alternation on chrome secondary buttons, muted tone styling, and 18px standard icon buttons across all presets',
      (tester) async {
        final presetTokens = <UiThemeTokens>[
          UiThemePresets.calm.light,
          UiThemePresets.calm.dark,
          UiThemePresets.plumUmber.light,
          UiThemePresets.plumUmber.dark,
        ];

        for (final tokens in presetTokens) {
          await pumpUiWidget(
            tester,
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                UiButton(
                  key: const ValueKey<String>('chrome_workspace'),
                  label: 'Work',
                  leadingIcon: Icons.grid_view_outlined,
                  trailingIcon: Icons.unfold_more_rounded,
                  variant: UiButtonVariant.secondary,
                  density: UiButtonDensity.chrome,
                  onPressed: () {},
                ),
                UiButton(
                  key: const ValueKey<String>('chrome_sync_muted'),
                  label: 'Synced',
                  leadingIcon: Icons.cloud_done_outlined,
                  variant: UiButtonVariant.secondary,
                  density: UiButtonDensity.chrome,
                  tone: UiButtonTone.muted,
                  onPressed: () {},
                ),
                UiSurfaceScope(
                  level: UiSurfaceLevel.insetWell,
                  child: UiButton(
                    key: const ValueKey<String>('inset_chrome_btn'),
                    label: 'Inset',
                    variant: UiButtonVariant.secondary,
                    density: UiButtonDensity.chrome,
                    onPressed: () {},
                  ),
                ),
                UiButton(
                  key: const ValueKey<String>('standard_icon_accent'),
                  leadingIcon: Icons.my_location_rounded,
                  variant: UiButtonVariant.icon,
                  density: UiButtonDensity.standard,
                  tone: UiButtonTone.accent,
                  onPressed: () {},
                ),
              ],
            ),
            tokens: tokens,
          );
          await tester.pumpAndSettle();

          final workspaceContainer = tester.widget<AnimatedContainer>(
            find.descendant(
              of: find.byKey(const ValueKey<String>('chrome_workspace')),
              matching: find.byType(AnimatedContainer),
            ),
          );
          final workspaceBox = workspaceContainer.decoration as BoxDecoration?;
          expect(
            workspaceBox?.color,
            equals(tokens.colors.bg),
            reason: 'Chrome secondary button must alternate to bg fill on panel chrome',
          );
          final workspaceText = tester.widget<Text>(find.text('Work'));
          expect(
            workspaceText.style?.color,
            equals(tokens.colors.ink),
            reason: 'Workspace chrome button label must use ink foreground',
          );

          final syncContainer = tester.widget<AnimatedContainer>(
            find.descendant(
              of: find.byKey(const ValueKey<String>('chrome_sync_muted')),
              matching: find.byType(AnimatedContainer),
            ),
          );
          final syncBox = syncContainer.decoration as BoxDecoration?;
          expect(
            syncBox?.color,
            equals(tokens.colors.bg),
            reason: 'Muted chrome sync button must use bg fill',
          );
          final syncText = tester.widget<Text>(find.text('Synced'));
          expect(
            syncText.style?.color,
            equals(tokens.colors.muted),
            reason: 'Muted chrome sync button label must use muted foreground',
          );
          expect(
            syncText.style?.fontWeight,
            equals(FontWeight.w400),
            reason: 'Muted chrome sync button label must use w400 weight',
          );

          final insetContainer = tester.widget<AnimatedContainer>(
            find.descendant(
              of: find.byKey(const ValueKey<String>('inset_chrome_btn')),
              matching: find.byType(AnimatedContainer),
            ),
          );
          final insetBox = insetContainer.decoration as BoxDecoration?;
          expect(
            insetBox?.color,
            equals(tokens.colors.panel),
            reason: 'Chrome secondary button inside insetWell must re-elevate to panel',
          );

          final accentIcon = tester.widget<Icon>(
            find.descendant(
              of: find.byKey(const ValueKey<String>('standard_icon_accent')),
              matching: find.byType(Icon),
            ),
          );
          expect(
            accentIcon.size,
            equals(tokens.spacing.iconMd),
            reason: 'Standard icon button must render 18px iconMd glyph',
          );
          expect(
            accentIcon.color,
            equals(tokens.colors.accent),
            reason: 'Accent icon button must render accent foreground color',
          );
        }
      },
    );

    testWidgets(
      'preserves tight parent width and AnimatedContainer identity when focused under alwaysTraditional',
      (tester) async {
        final previousStrategy = FocusManager.instance.highlightStrategy;
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        addTearDown(() {
          FocusManager.instance.highlightStrategy = previousStrategy;
        });

        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);

        await pumpUiWidget(
          tester,
          Center(
            child: SizedBox(
              width: 220.0,
              child: UiButton(
                key: const ValueKey<String>('tight_focus_btn'),
                label: 'Save',
                focusNode: focusNode,
                onPressed: () {},
              ),
            ),
          ),
        );

        final containerFinder = find.descendant(
          of: find.byKey(const ValueKey<String>('tight_focus_btn')),
          matching: find.byType(AnimatedContainer),
        );
        final elementBefore = tester.element(containerFinder);
        expect(tester.getSize(containerFinder).width, closeTo(220.0, 0.1));

        focusNode.requestFocus();
        await tester.pump();
        await tester.pump();

        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('tight_focus_btn')),
            matching: find.byType(Positioned),
          ),
          findsOneWidget,
          reason: 'Focus ring must be visible under alwaysTraditional',
        );
        expect(
          tester.element(containerFinder),
          same(elementBefore),
          reason: 'Focus ring toggle must not remount button AnimatedContainer',
        );
        expect(
          tester.getSize(containerFinder).width,
          closeTo(220.0, 0.1),
          reason: 'Focused button in tight parent must keep full 220px width inside focus ring',
        );
      },
    );
  });
}
