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

    testWidgets(
      'meta variant uses 6px tag radius and transparent resting borders for neutral, soft, and accent tones across presets',
      (tester) async {
        final presets = <({String name, UiThemeTokens tokens})>[
          (name: 'calm-light', tokens: UiThemePresets.calm.light),
          (name: 'calm-dark', tokens: UiThemePresets.calm.dark),
          (name: 'plum-light', tokens: UiThemePresets.plumUmber.light),
          (name: 'plum-dark', tokens: UiThemePresets.plumUmber.dark),
        ];

        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        addTearDown(gesture.removePointer);

        for (final entry in presets) {
          final presetName = entry.name;
          final tokens = entry.tokens;
          final colors = tokens.colors;
          final expectedBorders = <UiPillTone, Color>{
            UiPillTone.neutral: Colors.transparent,
            UiPillTone.soft: Colors.transparent,
            UiPillTone.accent: Colors.transparent,
            UiPillTone.warning: colors.warningBorder,
            UiPillTone.danger: colors.dangerBorder,
            UiPillTone.success: colors.successBorder,
          };

          await pumpUiWidget(
            tester,
            Center(
              child: Wrap(
                spacing: 6.0,
                children: <Widget>[
                  for (final tone in UiPillTone.values)
                    UiPill(
                      key: ValueKey<String>('meta_${tone.name}'),
                      label: tone.name,
                      variant: UiPillVariant.meta,
                      tone: tone,
                      onPressed: () {},
                    ),
                  UiPill(
                    key: const ValueKey<String>('tag_resting'),
                    label: 'Label',
                    variant: UiPillVariant.tag,
                    colorDot: const Color(0xFF4CAF50),
                    onPressed: () {},
                  ),
                  const UiPill(
                    key: ValueKey<String>('badge_accent'),
                    label: 'Badge',
                    variant: UiPillVariant.badge,
                    tone: UiPillTone.accent,
                  ),
                ],
              ),
            ),
            tokens: tokens,
          );
          await tester.pumpAndSettle();

          for (final tone in UiPillTone.values) {
            final box = _readPillDecoration(
              tester,
              find.byKey(ValueKey<String>('meta_${tone.name}')),
            );
            expect(
              box.borderRadius,
              equals(BorderRadius.circular(tokens.radii.tag)),
              reason:
                  'Meta pill ${tone.name} must use 6px tag corner radius ($presetName)',
            );
            expect(
              _readBorderTopColor(box),
              equals(expectedBorders[tone]),
              reason:
                  'Meta pill ${tone.name} resting border mismatch ($presetName)',
            );
          }

          final tagBox = _readPillDecoration(
            tester,
            find.byKey(const ValueKey<String>('tag_resting')),
          );
          expect(
            tagBox.borderRadius,
            equals(BorderRadius.circular(tokens.radii.tag)),
            reason: 'Tag chip must keep 6px tag radius',
          );
          expect(
            _readBorderTopColor(tagBox),
            equals(colors.line),
            reason: 'Tag chip must keep 1px line resting border',
          );

          final badgeBox = _readPillDecoration(
            tester,
            find.byKey(const ValueKey<String>('badge_accent')),
          );
          expect(
            badgeBox.borderRadius,
            equals(BorderRadius.circular(tokens.radii.pill)),
            reason: 'Status badge must keep full pill radius',
          );
          expect(
            _readBorderTopColor(badgeBox),
            equals(colors.accent),
            reason: 'Accent status badge must keep accent border',
          );

          // Interactive neutral meta pill reveals accent border and ink foreground on hover.
          final neutralFinder = find.byKey(
            const ValueKey<String>('meta_neutral'),
          );
          await gesture.moveTo(tester.getCenter(neutralFinder));
          await tester.pumpAndSettle();

          final hoveredBox = _readPillDecoration(tester, neutralFinder);
          expect(
            _readBorderTopColor(hoveredBox),
            equals(colors.accent),
            reason:
                'Hovered interactive neutral meta pill must show accent border',
          );
          expect(
            hoveredBox.color,
            equals(colors.bg),
            reason: 'Hovered interactive neutral meta pill must retain resting fill',
          );
          final hoveredText = tester.widget<Text>(
            find.descendant(of: neutralFinder, matching: find.byType(Text)),
          );
          expect(
            hoveredText.style?.color,
            equals(colors.ink),
            reason: 'Hovered interactive neutral meta pill must use ink text',
          );

          await gesture.moveTo(Offset.zero);
          await tester.pumpAndSettle();
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
              width: 180.0,
              child: UiPill(
                key: const ValueKey<String>('tight_focus_pill'),
                label: 'Ops',
                variant: UiPillVariant.tag,
                focusNode: focusNode,
                onPressed: () {},
              ),
            ),
          ),
        );

        final containerFinder = find.descendant(
          of: find.byKey(const ValueKey<String>('tight_focus_pill')),
          matching: find.byType(AnimatedContainer),
        );
        final elementBefore = tester.element(containerFinder);
        expect(tester.getSize(containerFinder).width, closeTo(180.0, 0.1));

        focusNode.requestFocus();
        await tester.pump();
        await tester.pump();

        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('tight_focus_pill')),
            matching: find.byType(Positioned),
          ),
          findsOneWidget,
          reason: 'Focus ring must be visible under alwaysTraditional',
        );
        expect(
          tester.element(containerFinder),
          same(elementBefore),
          reason: 'Focus ring toggle must not remount pill AnimatedContainer',
        );
        expect(
          tester.getSize(containerFinder).width,
          closeTo(180.0, 0.1),
          reason: 'Focused pill in tight parent must keep full 180px width inside focus ring',
        );
      },
    );
  });
}

/// Extracts the [BoxDecoration] rendered by the [AnimatedContainer] inside [pillFinder].
BoxDecoration _readPillDecoration(WidgetTester tester, Finder pillFinder) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(of: pillFinder, matching: find.byType(AnimatedContainer)),
  );
  if (container.decoration case final BoxDecoration box) {
    return box;
  }
  fail('Expected BoxDecoration on AnimatedContainer');
}

/// Extracts the top border color from [box].
Color _readBorderTopColor(BoxDecoration box) {
  if (box.border case final Border border) {
    return border.top.color;
  }
  fail('Expected Border on BoxDecoration');
}
