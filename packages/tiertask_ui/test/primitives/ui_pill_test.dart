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
  group('UiPill', () {
    testWidgets('renders all variants and tones across presets', (
      tester,
    ) async {
      for (final variant in UiPillVariant.values) {
        for (final tone in UiPillTone.values) {
          await pumpUiWidget(
            tester,
            Center(
              child: UiPill(
                label: '${variant.name}_${tone.name}',
                variant: variant,
                tone: tone,
                colorDot: variant == UiPillVariant.tag
                    ? const Color(0xFF2196F3)
                    : null,
                icon: variant == UiPillVariant.meta
                    ? Icons.calendar_today_outlined
                    : null,
                onPressed: variant == UiPillVariant.selectable ? () {} : null,
                isSelected: variant == UiPillVariant.selectable,
              ),
            ),
          );
          expect(
            find.text('${variant.name}_${tone.name}'),
            findsOneWidget,
            reason:
                'Variant ${variant.name} tone ${tone.name} must render label',
          );
        }
      }
    });

    testWidgets(
      'supports splitChip navigation and removal, dashed vs direct addField, and UiSurfaceScope re-elevation',
      (tester) async {
        var navigated = false;
        var removed = false;
        final tokens = UiThemePresets.calm.light;

        await pumpUiWidget(
          tester,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              UiPill(
                label: 'Backend',
                variant: UiPillVariant.splitChip,
                colorDot: const Color(0xFF4CAF50),
                onPressed: () => navigated = true,
                onRemove: () => removed = true,
                removeTooltip: 'Remove Backend',
              ),
              UiPill(
                key: const ValueKey<String>('dashed_add'),
                label: '+ Note',
                variant: UiPillVariant.addField,
                onPressed: () {},
              ),
              UiPill(
                key: const ValueKey<String>('direct_add'),
                label: 'Priority',
                variant: UiPillVariant.addField,
                isDirect: true,
                onPressed: () {},
              ),
              UiSurfaceScope(
                level: UiSurfaceLevel.insetWell,
                child: UiPill(
                  key: const ValueKey<String>('inset_pill'),
                  label: 'Mon',
                  variant: UiPillVariant.selectable,
                  onPressed: () {},
                ),
              ),
            ],
          ),
          tokens: tokens,
        );

        await tester.tap(find.text('Backend'));
        await tester.pump();
        expect(navigated, isTrue);

        await tester.tap(find.byTooltip('Remove Backend'));
        await tester.pump();
        expect(removed, isTrue);

        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('dashed_add')),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('direct_add')),
            matching: find.byType(CustomPaint),
          ),
          findsNothing,
        );

        final insetBox = find.descendant(
          of: find.byKey(const ValueKey<String>('inset_pill')),
          matching: find.byWidgetPredicate((widget) {
            if (widget is! AnimatedContainer) {
              return false;
            }
            final decoration = widget.decoration;
            return decoration is BoxDecoration &&
                decoration.color == tokens.colors.panel;
          }),
        );
        expect(insetBox, findsOneWidget);
      },
    );
  });
}
