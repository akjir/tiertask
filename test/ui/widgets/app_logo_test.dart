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

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/ui/app_theme.dart';
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
      final painter = customPaint.painter;
      expect(
        painter,
        isNotNull,
        reason: 'AppLogo CustomPaint must attach a non-null foreground painter',
      );
      if (painter != null) {
        expect(
          painter.shouldRepaint(painter),
          isFalse,
          reason: 'Vector logo painter must not repaint for identical theme',
        );
      }

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
    'AppLogo paints three stepped accent bars on transparent canvas and repaints on accent change',
    (WidgetTester tester) async {
      await pumpLeafWidget(
        tester,
        Theme(
          data: AppTheme.slateLight.toThemeData(),
          child: const AppLogo(size: 22),
        ),
      );
      final lightPainter = tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byKey(const ValueKey('app_logo')),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter;
      expect(
        lightPainter,
        isNotNull,
        reason: 'AppLogo must provide a CustomPainter under slateLight',
      );

      await pumpLeafWidget(
        tester,
        Theme(
          data: AppTheme.slateDark.toThemeData(),
          child: const AppLogo(size: 22),
        ),
      );
      final darkPainter = tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byKey(const ValueKey('app_logo')),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter;
      expect(
        darkPainter,
        isNotNull,
        reason: 'AppLogo must provide a CustomPainter under slateDark',
      );
      if (lightPainter == null || darkPainter == null) {
        return;
      }

      expect(
        lightPainter.shouldRepaint(darkPainter),
        isTrue,
        reason: 'AppLogo painter must repaint when theme accent changes',
      );

      final pixels = await tester.runAsync(
        () => _rasterizePainter(lightPainter, 22, 22),
      );
      expect(
        pixels,
        isNotNull,
        reason: 'Rasterizing AppLogo painter must produce RGBA pixel bytes',
      );
      if (pixels == null) {
        return;
      }

      expect(
        _rgbaAt(pixels, 22, 0, 0).alpha,
        equals(0),
        reason: 'Corner pixel must remain transparent with no squircle tile',
      );
      expect(
        _rgbaAt(pixels, 22, 11, 1).alpha,
        equals(0),
        reason: 'Top margin above bar 1 must remain transparent with no tile',
      );
      expect(
        _rgbaAt(pixels, 22, 19, 18).alpha,
        equals(0),
        reason:
            'Bottom-right area must remain transparent with no checkmark badge',
      );

      final topBar = _rgbaAt(pixels, 22, 11, 4);
      expect(
        topBar,
        equals((red: 0, green: 100, blue: 139, alpha: 255)),
        reason: 'Top bar must paint full-opacity slateLight primaryAccent (#00648B)',
      );

      final middleBar = _rgbaAt(pixels, 22, 8, 11);
      expect(
        middleBar.alpha,
        closeTo((0.72 * 255).round(), 2),
        reason: 'Middle bar must paint at 0.72 opacity',
      );
      expect(
        _rgbaAt(pixels, 22, 20, 11).alpha,
        equals(0),
        reason: 'Middle bar must end at 75% width',
      );

      final bottomBar = _rgbaAt(pixels, 22, 5, 18);
      expect(
        bottomBar.alpha,
        closeTo((0.42 * 255).round(), 2),
        reason: 'Bottom bar must paint at 0.42 opacity',
      );
      expect(
        _rgbaAt(pixels, 22, 14, 18).alpha,
        equals(0),
        reason: 'Bottom bar must end at 50% width',
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

Future<Uint8List> _rasterizePainter(
  CustomPainter painter,
  int width,
  int height,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, Size(width.toDouble(), height.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return byteData?.buffer.asUint8List() ?? Uint8List(0);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

({int alpha, int blue, int green, int red}) _rgbaAt(
  Uint8List pixels,
  int width,
  int column,
  int row,
) {
  final offset = (row * width + column) * 4;
  return (
    red: pixels[offset],
    green: pixels[offset + 1],
    blue: pixels[offset + 2],
    alpha: pixels[offset + 3],
  );
}
