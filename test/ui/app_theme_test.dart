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
import 'package:tiertask/ui/app_theme.dart';

import 'test_helpers.dart';

void main() {
  const sampleTdf = '''
tdf 0.2.0

task t1 {
  name "Theme Test Task"
  created 2026-11-01 07:00
  queued 2026-11-01 07:00
  priority
  label "work"
}
''';

  test('AppTheme.dark and AppTheme.light build complete Material 3 ThemeData and support copyWith and lerp', () {
    const dark = AppTheme.dark;
    const light = AppTheme.light;

    expect(
      dark.brightness,
      equals(Brightness.dark),
      reason: 'AppTheme.dark must declare Brightness.dark',
    );
    expect(
      light.brightness,
      equals(Brightness.light),
      reason: 'AppTheme.light must declare Brightness.light',
    );
    expect(
      dark.canvasColor,
      equals(const Color(0xFF344FA1)),
      reason: 'AppTheme.dark must preserve the signature navy canvas color',
    );
    expect(
      dark.cardColor,
      equals(const Color(0xFF071A52)),
      reason: 'AppTheme.dark must preserve the signature dark pill color',
    );
    expect(
      light.canvasColor,
      isNot(equals(dark.canvasColor)),
      reason: 'AppTheme.light must provide a distinct light canvas surface',
    );

    final darkThemeData = dark.toThemeData();
    final lightThemeData = light.toThemeData();

    expect(
      darkThemeData.scaffoldBackgroundColor,
      equals(dark.canvasColor),
      reason: 'ThemeData scaffoldBackgroundColor must match AppTheme canvas',
    );
    expect(
      darkThemeData.cardColor,
      equals(dark.cardColor),
      reason: 'ThemeData cardColor must match AppTheme cardColor',
    );
    expect(
      darkThemeData.colorScheme.primary,
      equals(dark.primaryAccent),
      reason: 'ColorScheme.primary must match AppTheme.primaryAccent',
    );
    expect(
      darkThemeData.colorScheme.secondary,
      equals(dark.secondaryAccent),
      reason: 'ColorScheme.secondary must match AppTheme.secondaryAccent',
    );
    expect(
      darkThemeData.colorScheme.tertiary,
      equals(dark.tertiaryAccent),
      reason: 'ColorScheme.tertiary must match AppTheme.tertiaryAccent',
    );
    expect(
      darkThemeData.textTheme.titleSmall?.fontSize,
      equals(15),
      reason: 'Section header text style titleSmall must use fontSize 15',
    );
    expect(
      darkThemeData.extension<AppTheme>(),
      equals(dark),
      reason: 'ThemeData must register AppTheme as a ThemeExtension',
    );
    expect(
      lightThemeData.extension<AppTheme>(),
      equals(light),
      reason: 'Light ThemeData must register AppTheme.light as extension',
    );

    final copied = dark.copyWith(canvasColor: const Color(0xFF112233));
    expect(
      copied.canvasColor,
      equals(const Color(0xFF112233)),
      reason: 'copyWith must override specified color fields',
    );
    expect(
      copied.primaryAccent,
      equals(dark.primaryAccent),
      reason: 'copyWith must preserve unmodified color fields',
    );

    final lerped = dark.lerp(light, 0.5);
    expect(
      lerped.canvasColor,
      equals(Color.lerp(dark.canvasColor, light.canvasColor, 0.5)),
      reason: 'lerp must interpolate all AppTheme colors',
    );
  });

  testWidgets(
    'Switching between Dark and Light modes updates colors across HomeScreen, QuickAddBar, and TierPageIndicator',
    (tester) async {
      const initialConfig = WebDavConfig(
        language: AppLanguage.english,
        themeMode: AppThemeMode.dark,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(initialConfig),
            ),
            localFileRepositoryProvider.overrideWith(
              (ref) => FakeLocalFileRepository(
                config: initialConfig,
                initialTdf: sampleTdf,
              ),
            ),
            clockProvider.overrideWithValue(
              () => DateTime.utc(2026, 11, 1, 12, 0),
            ),
          ],
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();

      final darkScaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(
        darkScaffold.backgroundColor,
        equals(AppTheme.dark.canvasColor),
        reason: 'HomeScreen Scaffold must use AppTheme.dark.canvasColor in dark mode',
      );

      final darkReadyDot = tester.widget<Container>(
        find.byKey(const ValueKey('tier_indicator_dot_ready')),
      );
      final darkDotDecoration = darkReadyDot.decoration as BoxDecoration?;
      expect(
        darkDotDecoration?.color,
        equals(AppTheme.dark.indicatorInactiveDotColor),
        reason: 'TierPageIndicator dots must use AppTheme.dark in dark mode',
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TierTaskApp)),
      );
      await container
          .read(webDavConfigProvider.notifier)
          .updateConfig(
            const WebDavConfig(
              language: AppLanguage.english,
              themeMode: AppThemeMode.light,
            ),
          );
      await tester.pumpAndSettle();

      final lightScaffold = tester.widget<Scaffold>(
        find.byType(Scaffold).first,
      );
      expect(
        lightScaffold.backgroundColor,
        equals(AppTheme.light.canvasColor),
        reason: 'HomeScreen Scaffold must update to AppTheme.light.canvasColor in light mode',
      );

      final lightReadyDot = tester.widget<Container>(
        find.byKey(const ValueKey('tier_indicator_dot_ready')),
      );
      final lightDotDecoration = lightReadyDot.decoration as BoxDecoration?;
      expect(
        lightDotDecoration?.color,
        equals(AppTheme.light.indicatorInactiveDotColor),
        reason: 'TierPageIndicator dots must update to AppTheme.light in light mode',
      );
    },
  );

  testWidgets(
    'Swapping AppTheme at runtime via appThemeProvider updates all UI screens and widgets dynamically',
    (tester) async {
      const initialConfig = WebDavConfig(
        language: AppLanguage.english,
        themeMode: AppThemeMode.dark,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(initialConfig),
            ),
            localFileRepositoryProvider.overrideWith(
              (ref) => FakeLocalFileRepository(
                config: initialConfig,
                initialTdf: sampleTdf,
              ),
            ),
            clockProvider.overrideWithValue(
              () => DateTime.utc(2026, 11, 1, 12, 0),
            ),
          ],
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();

      final customTheme = AppTheme.dark.copyWith(
        canvasColor: const Color(0xFF1B2E1E),
        cardColor: const Color(0xFF0D1A10),
        elevatedSurfaceColor: const Color(0xFF243D29),
        primaryAccent: const Color(0xFF00E676),
        secondaryAccent: const Color(0xFF40C4FF),
        tertiaryAccent: const Color(0xFFFFD740),
        warningAccent: const Color(0xFFFF6E40),
        primaryTextColor: const Color(0xFFF1F8E9),
        mutedTextColor: const Color(0xFFA5D6A7),
        indicatorActiveIconColor: const Color(0xFF00E676),
        indicatorInactiveDotColor: const Color(0x8AA5D6A7),
        indicatorIntermediateColor: const Color(0xC5C8E6C9),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TierTaskApp)),
      );
      container.read(appThemeProvider.notifier).setTheme(customTheme);
      await tester.pumpAndSettle();

      final homeScaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(
        homeScaffold.backgroundColor,
        equals(customTheme.canvasColor),
        reason: 'HomeScreen Scaffold must immediately reflect the runtime-swapped AppTheme canvasColor',
      );

      final activeIndicatorIcon = tester.widget<Icon>(
        find.byKey(const ValueKey('tier_indicator_icon_focus')),
      );
      expect(
        activeIndicatorIcon.color,
        equals(customTheme.indicatorActiveIconColor),
        reason: 'TierPageIndicator active icon must reflect the runtime-swapped AppTheme',
      );

      await tester.tap(find.byKey(const ValueKey('add_task_fab')));
      await tester.pumpAndSettle();

      final priorityIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('quick_add_priority_button')),
          matching: find.byType(Icon),
        ),
      );
      expect(
        priorityIcon.color,
        equals(customTheme.mutedTextColor),
        reason: 'QuickAddBar unselected icons must reflect the runtime-swapped AppTheme mutedTextColor',
      );

      await tester.tap(find.byKey(const ValueKey('quick_add_advanced_button')));
      await tester.pumpAndSettle();

      final editTaskScaffold = tester.widget<Scaffold>(
        find.byKey(const ValueKey('edit_task_screen')),
      );
      expect(
        editTaskScaffold.backgroundColor,
        equals(customTheme.canvasColor),
        reason: 'EditTaskScreen Scaffold must reflect the runtime-swapped AppTheme canvasColor',
      );
    },
  );
}
