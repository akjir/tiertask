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
import 'package:tiertask_ui_example/main.dart';

void main() {
  group('TierTaskUiGalleryApp', () {
    testWidgets(
      'switches presets, color modes, DEV pill, and simulated viewports with zero overflow',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(1440, 960);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const TierTaskUiGalleryApp());
        await tester.pump();

        expect(find.text('TierTask'), findsOneWidget);
        expect(find.text('17 / 17 WCAG AA'), findsOneWidget);

        // Toggle Plum Umber preset and Dark mode.
        await tester.tap(find.text('Plum Umber'));
        await tester.pump();
        await tester.tap(find.text('Dark'));
        await tester.pump();
        expect(find.text('17 / 17 WCAG AA'), findsOneWidget);

        // Toggle DEV build pill on.
        await tester.tap(find.text('DEV pill'));
        await tester.pump();
        expect(find.text('DEV'), findsOneWidget);

        // Switch simulated viewports: Medium 760 and Compact 390.
        await tester.tap(find.text('Medium 760'));
        await tester.pump();
        await tester.tap(find.text('Compact 390'));
        await tester.pump();

        // Compact viewport displays drawer menu trigger and + New task trigger.
        expect(find.byTooltip('Open navigation menu'), findsOneWidget);
        expect(find.text('+ New task'), findsOneWidget);

        // Switch back to Desktop 1280 and exercise Primitives, Layouts, and Composites.
        await tester.tap(find.text('Desktop 1280'));
        await tester.pump();

        await tester.tap(find.text('Primitives'));
        await tester.pump();
        expect(find.text('Unified expandable entity card'), findsOneWidget);
        await tester.tap(find.text('Compact 390'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Desktop 1280'));
        await tester.pump();

        await tester.tap(find.text('Layouts'));
        await tester.pump();
        expect(find.text('Adaptive Layouts'), findsOneWidget);
        await tester.tap(find.text('Medium 760'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Desktop 1280'));
        await tester.pump();

        await tester.tap(find.text('Composites'));
        await tester.pump();
        expect(find.text('Open Modal'), findsOneWidget);
        expect(find.text('Open Bottom Sheet'), findsOneWidget);

        // Verify Modal opens and closes cleanly.
        await tester.tap(find.text('Open Modal'));
        await tester.pumpAndSettle();
        expect(find.text('Sample Dialog'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.text('Sample Dialog'), findsNothing);

        // Verify Bottom Sheet opens and closes cleanly.
        await tester.tap(find.text('Open Bottom Sheet'));
        await tester.pumpAndSettle();
        expect(find.text('Done'), findsOneWidget);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });
}
