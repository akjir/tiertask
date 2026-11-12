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
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/ui/widgets/app_logo.dart';
import 'package:tiertask/ui/widgets/home_drawer.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'AppLogo renders vector custom paint at default and custom dimensions',
    (WidgetTester tester) async {
      await pumpLeafWidget(tester, const AppLogo());

      final defaultLogoFinder = find.byKey(const ValueKey('app_logo'));

      expect(
        defaultLogoFinder,
        findsOneWidget,
        reason: 'Default AppLogo must use the canonical app_logo key',
      );
      expect(
        tester.getSize(defaultLogoFinder),
        equals(const Size(32, 32)),
        reason: 'Default AppLogo size must be 32x32 logical pixels',
      );

      final customPaintFinder = find.descendant(
        of: defaultLogoFinder,
        matching: find.byType(CustomPaint),
      );
      expect(
        customPaintFinder,
        findsOneWidget,
        reason: 'AppLogo must render its motif using a CustomPaint canvas',
      );
      final customPaint = tester.widget<CustomPaint>(customPaintFinder);
      expect(
        customPaint.painter,
        isNotNull,
        reason: 'AppLogo CustomPaint must attach a non-null foreground painter',
      );
      expect(
        customPaint.painter?.shouldRepaint(customPaint.painter!),
        isFalse,
        reason: 'Stateless vector logo painter must not repaint unnecessarily',
      );

      await pumpLeafWidget(
        tester,
        const AppLogo(key: ValueKey('custom_size_logo'), size: 64),
      );
      final customLogoFinder = find.byKey(const ValueKey('custom_size_logo'));
      expect(
        tester.getSize(customLogoFinder),
        equals(const Size(64, 64)),
        reason: 'Custom AppLogo size must match the requested 64x64 dimension',
      );
    },
  );

  testWidgets(
    'Navigation drawer header displays AppLogo next to the TierTask title',
    (WidgetTester tester) async {
      await pumpLeafWidget(
        tester,
        HomeDrawer(
          activeLabelId: null,
          activeWorkspace: AppWorkspace.defaultWorkspace,
          board: TaskBoard.empty(),
          onManageWorkspaces: () {},
          onOpenEditLabels: (_) {},
          onOpenSettings: () {},
          onSelectLabel: (_) {},
          onSyncRemote: () {},
        ),
      );
      await tester.pumpAndSettle();

      final drawerFinder = find.byType(Drawer);
      final logoFinder = find.descendant(
        of: drawerFinder,
        matching: find.byType(AppLogo),
      );
      final titleFinder = find.descendant(
        of: drawerFinder,
        matching: find.text('TierTask'),
      );

      expect(
        logoFinder,
        findsOneWidget,
        reason: 'Navigation drawer header must render the AppLogo widget',
      );
      expect(
        titleFinder,
        findsOneWidget,
        reason: 'Navigation drawer header must render the TierTask title',
      );

      final logoRect = tester.getRect(logoFinder);
      final titleRect = tester.getRect(titleFinder);

      expect(
        logoRect.right <= titleRect.left,
        isTrue,
        reason: 'AppLogo must be positioned to the left of the TierTask title',
      );
      expect(
        (logoRect.center.dy - titleRect.center.dy).abs() <= 8.0,
        isTrue,
        reason: 'AppLogo and TierTask title must be vertically aligned',
      );
    },
  );
}
