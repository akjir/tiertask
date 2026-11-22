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
import 'package:tiertask/ui/components/ui_color_wheel.dart';

import '../test_helpers.dart';

void main() {
  group('UiColorWheel', () {
    test(
      'exposes exact 8 canonical presets and validates #RRGGBB hex strings',
      () {
        expect(UiColorWheel.canonicalPresets, hasLength(8));
        expect(
          UiColorWheel.canonicalPresets.map(UiColorWheel.formatHex).toList(),
          equals(const <String>[
            '#2196F3',
            '#4CAF50',
            '#FF9100',
            '#E91E63',
            '#9C27B0',
            '#00BCD4',
            '#EB06FF',
            '#00E5FF',
          ]),
        );

        expect(
          UiColorWheel.tryParseHex('#4caf50'),
          equals(const Color(0xFF4CAF50)),
        );
        expect(UiColorWheel.tryParseHex('#123'), isNull);
        expect(UiColorWheel.tryParseHex('4CAF50'), isNull);
        expect(UiColorWheel.tryParseHex('#GGGGGG'), isNull);

        final centerColor = UiColorWheel.hsvFromWheelOffset(
          const Offset(105, 105),
          const Size(210, 210),
          1.0,
        );
        expect(centerColor.saturation, closeTo(0.0, 0.01));

        final rightEdgeColor = UiColorWheel.hsvFromWheelOffset(
          const Offset(210, 105),
          const Size(210, 210),
          1.0,
        );
        expect(rightEdgeColor.hue, closeTo(0.0, 1.0));
        expect(rightEdgeColor.saturation, closeTo(1.0, 0.01));
      },
    );

    testWidgets(
      'supports preset chips, hex input validation, and HSV wheel modal interaction',
      (tester) async {
        var activeColor = const Color(0xFF2196F3);

        await pumpUiWidget(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                width: 480,
                child: UiColorWheel(
                  value: activeColor,
                  onChanged: (next) => setState(() => activeColor = next),
                  inputLabel: 'Label color',
                  customButtonLabel: 'Custom color',
                  modalTitle: 'Pick custom color',
                  brightnessLabel: 'Brightness',
                  cancelLabel: 'Cancel',
                  confirmLabel: 'Apply',
                  closeTooltip: 'Close picker',
                  invalidHexError: 'Enter a valid #RRGGBB color',
                ),
              );
            },
          ),
        );

        // Tap preset chip #4CAF50.
        await tester.tap(find.text('#4CAF50'));
        await tester.pump();
        expect(activeColor, equals(const Color(0xFF4CAF50)));

        // Invalid hex shows inline validation error without mutating activeColor.
        await tester.enterText(find.byType(TextField), '#ZZZZZZ');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(find.text('Enter a valid #RRGGBB color'), findsOneWidget);
        expect(activeColor, equals(const Color(0xFF4CAF50)));

        // Valid lowercase hex commits normalized uppercase color.
        await tester.enterText(find.byType(TextField), '#ff9100');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(activeColor, equals(const Color(0xFFFF9100)));

        // Open HSV wheel modal, tap canvas, adjust brightness slider, and confirm.
        await tester.tap(find.text('Custom color'));
        await tester.pumpAndSettle();
        expect(find.text('Pick custom color'), findsOneWidget);
        expect(find.text('Brightness'), findsOneWidget);

        final wheelFinder = find.byKey(
          const ValueKey<String>('ui_color_wheel_canvas'),
        );
        expect(wheelFinder, findsOneWidget);
        await tester.tapAt(
          tester.getTopLeft(wheelFinder) + const Offset(190, 105),
        );
        await tester.pump();

        final sliderFinder = find.byType(Slider);
        expect(sliderFinder, findsOneWidget);
        await tester.drag(sliderFinder, const Offset(-40, 0));
        await tester.pump();

        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(find.text('Pick custom color'), findsNothing);
        expect(activeColor, isNot(equals(const Color(0xFFFF9100))));
      },
    );
  });
}
