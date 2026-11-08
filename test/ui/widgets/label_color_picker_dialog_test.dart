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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/ui/widgets/label_color_picker_dialog.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'LabelColorPickerDialog initializes from valid or fallback hex, updates color on wheel tap/drag and brightness slider, and returns canonical #RRGGBB on confirm or null on cancel',
    (WidgetTester tester) async {
      String? dialogResult = 'UNSET';

      await pumpLeafWidget(
        tester,
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const ValueKey('open_picker_btn'),
              onPressed: () async {
                dialogResult = await showLabelColorPickerDialog(
                  context,
                  initialHex: '#4CAF50',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open_picker_btn')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('label_color_picker_dialog')),
        findsOneWidget,
        reason: 'Dialog must be visible when opened',
      );
      expect(
        find.text('Choose Custom Color'),
        findsOneWidget,
        reason: 'Dialog title must render localized heading',
      );
      expect(
        find.byKey(const ValueKey('label_color_picker_preview')),
        findsOneWidget,
        reason: 'Live color preview swatch must be rendered',
      );
      final hexTextFinder = find.byKey(
        const ValueKey('label_color_picker_hex_text'),
      );
      expect(hexTextFinder, findsOneWidget);
      expect(
        tester.widget<Text>(hexTextFinder).data,
        equals('#4CAF50'),
        reason: 'Initial valid hex color must be displayed in uppercase',
      );

      final wheelFinder = find.byKey(
        const ValueKey('label_color_picker_wheel'),
      );
      expect(
        wheelFinder,
        findsOneWidget,
        reason: 'Interactive color wheel must be rendered',
      );

      final wheelRect = tester.getRect(wheelFinder);
      await tester.tapAt(Offset(wheelRect.right - 10, wheelRect.center.dy));
      await tester.pump();

      final afterRightTapHex = tester.widget<Text>(hexTextFinder).data!;
      expect(
        TdfColor.isStrictHexColor(afterRightTapHex),
        isTrue,
        reason:
            'Tapping right edge of wheel must produce a valid #RRGGBB string',
      );
      expect(
        afterRightTapHex,
        isNot(equals('#4CAF50')),
        reason: 'Tapping a different point on the color wheel must change the selected color',
      );

      await tester.dragFrom(
        wheelRect.center,
        Offset(0, -wheelRect.height * 0.4),
      );
      await tester.pump();

      final afterDragHex = tester.widget<Text>(hexTextFinder).data!;
      expect(
        afterDragHex,
        isNot(equals(afterRightTapHex)),
        reason: 'Dragging across the color wheel must update the hue and saturation',
      );

      final sliderFinder = find.byKey(
        const ValueKey('label_color_picker_value_slider'),
      );
      expect(
        sliderFinder,
        findsOneWidget,
        reason: 'Brightness slider must be rendered below the color wheel',
      );
      await tester.drag(sliderFinder, const Offset(-80, 0));
      await tester.pump();

      final afterSliderHex = tester.widget<Text>(hexTextFinder).data!;
      expect(
        afterSliderHex,
        isNot(equals(afterDragHex)),
        reason: 'Adjusting brightness slider must darken the selected color',
      );

      await tester.tap(
        find.byKey(const ValueKey('label_color_picker_confirm_button')),
      );
      await tester.pumpAndSettle();

      expect(
        dialogResult,
        equals(afterSliderHex),
        reason: 'Confirming dialog must return the selected canonical #RRGGBB string',
      );
    },
  );

  testWidgets(
    'LabelColorPickerDialog falls back to default color when initialHex is empty or invalid and returns null when canceled',
    (WidgetTester tester) async {
      String? dialogResult = 'UNSET';

      await pumpLeafWidget(
        tester,
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const ValueKey('open_invalid_picker_btn'),
              onPressed: () async {
                dialogResult = await showLabelColorPickerDialog(
                  context,
                  initialHex: 'not-a-hex',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open_invalid_picker_btn')));
      await tester.pumpAndSettle();

      final hexTextFinder = find.byKey(
        const ValueKey('label_color_picker_hex_text'),
      );
      expect(
        tester.widget<Text>(hexTextFinder).data,
        equals('#2196F3'),
        reason: 'Invalid initialHex must fall back to default #2196F3',
      );

      await tester.tap(
        find.byKey(const ValueKey('label_color_picker_cancel_button')),
      );
      await tester.pumpAndSettle();

      expect(dialogResult, isNull, reason: 'Canceling dialog must return null');
    },
  );
}
