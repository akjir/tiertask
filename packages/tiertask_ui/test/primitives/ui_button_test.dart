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
  });
}
