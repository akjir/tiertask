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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/ui/widgets/app_logo.dart';

void main() {
  testWidgets(
    'AppLogo renders vector custom paint at default and custom dimensions',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AppLogo(),
                AppLogo(key: ValueKey('custom_size_logo'), size: 64),
              ],
            ),
          ),
        ),
      );

      final defaultLogoFinder = find.byKey(const ValueKey('app_logo'));
      final customLogoFinder = find.byKey(const ValueKey('custom_size_logo'));

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
      expect(
        tester.getSize(customLogoFinder),
        equals(const Size(64, 64)),
        reason: 'Custom AppLogo size must match the requested 64x64 dimension',
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
    },
  );

  testWidgets(
    'Navigation drawer header displays AppLogo next to the TierTask title',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(
                const WebDavConfig(language: AppLanguage.english),
              ),
            ),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu_rounded));
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
