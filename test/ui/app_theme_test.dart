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
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/ui/app_theme.dart';

import 'test_helpers.dart';

void main() {
  const sampleTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 07:00:00
  task 000001OkD2
}

label work00OkD2 {
  name "Work"
}
task 000001OkD2 priority {
  name "Theme Test Task"
  created 2026-11-01 07:00
  queued 2026-11-01 07:00
  labels work00OkD2
}
''';

  test('AppThemePalette, AppThemeSet, Slate and Navy themes, and Material 3 ColorScheme container roles build complete ThemeData', () {
    expect(
      AppThemePalette.fromId(0),
      equals(AppThemePalette.slate),
      reason: 'fromId(0) must resolve to AppThemePalette.slate',
    );
    expect(
      AppThemePalette.fromId(1),
      equals(AppThemePalette.navy),
      reason: 'fromId(1) must resolve to AppThemePalette.navy',
    );
    expect(
      AppThemePalette.fromId(99),
      equals(AppThemePalette.slate),
      reason: 'fromId must default unknown values to AppThemePalette.slate',
    );
    expect(
      const WebDavConfig().themePalette,
      equals(AppThemePalette.slate),
      reason: 'WebDavConfig must default themePalette to AppThemePalette.slate',
    );

    const workspace = AppWorkspace(
      id: 'work',
      name: 'Work',
      config: WebDavConfig(themePalette: AppThemePalette.navy),
    );
    final roundTripped = AppWorkspace.fromBytes(workspace.toBytes());
    expect(
      roundTripped.config.themePalette,
      equals(AppThemePalette.navy),
      reason: 'AppWorkspace binary serialization must preserve themePalette',
    );

    expect(
      AppThemeSet.forPalette(AppThemePalette.slate),
      equals(AppThemeSet.slate),
      reason: 'AppThemeSet.forPalette must map slate to AppThemeSet.slate',
    );
    expect(
      AppThemeSet.forPalette(AppThemePalette.navy),
      equals(AppThemeSet.navy),
      reason: 'AppThemeSet.forPalette must map navy to AppThemeSet.navy',
    );

    const slateDark = AppTheme.slateDark;
    const slateLight = AppTheme.slateLight;
    const navyDark = AppTheme.navyDark;
    const navyLight = AppTheme.navyLight;

    expect(
      slateDark.canvasColor,
      equals(const Color(0xFF47545E)),
      reason: 'AppTheme.slateDark must use the extracted #47545E slate canvas color',
    );
    expect(
      slateDark.cardColor,
      equals(const Color(0xFF243037)),
      reason:
          'AppTheme.slateDark must use the extracted #243037 dark card surface',
    );
    expect(
      slateDark.elevatedSurfaceColor,
      equals(const Color(0xFF39434B)),
      reason: 'AppTheme.slateDark must use the extracted #39434B elevated surface color',
    );
    expect(
      slateDark.primaryAccent,
      equals(const Color(0xFF8AB4F8)),
      reason:
          'AppTheme.slateDark must use the M3 Tone-80 #8AB4F8 primary accent',
    );
    expect(
      slateDark.onPrimaryColor,
      equals(const Color(0xFF003258)),
      reason: 'AppTheme.slateDark must use dark M3 Tone-20 #003258 onPrimary for contrast',
    );
    expect(
      slateDark.primaryContainerColor,
      equals(const Color(0xFF004C6B)),
      reason:
          'AppTheme.slateDark must use the extracted #004C6B primaryContainer',
    );
    expect(
      slateDark.onPrimaryContainerColor,
      equals(const Color(0xFFCCE1F0)),
      reason: 'AppTheme.slateDark must use the extracted #CCE1F0 onPrimaryContainer',
    );
    expect(
      slateDark.secondaryAccent,
      equals(const Color(0xFF7EBAB1)),
      reason: 'AppTheme.slateDark must use the extracted #7EBAB1 secondary teal accent',
    );
    expect(
      navyDark.canvasColor,
      equals(const Color(0xFF344FA1)),
      reason: 'AppTheme.navyDark must preserve the classic #344FA1 navy canvas color',
    );
    expect(
      navyDark.cardColor,
      equals(const Color(0xFF071A52)),
      reason: 'AppTheme.navyDark must preserve the classic #071A52 card color',
    );
    expect(
      slateLight.brightness,
      equals(Brightness.light),
      reason: 'AppTheme.slateLight must declare Brightness.light',
    );
    expect(
      navyLight.brightness,
      equals(Brightness.light),
      reason: 'AppTheme.navyLight must declare Brightness.light',
    );

    final slateDarkThemeData = slateDark.toThemeData();
    final colorScheme = slateDarkThemeData.colorScheme;
    expect(
      colorScheme.primary,
      equals(slateDark.primaryAccent),
      reason: 'ColorScheme.primary must match AppTheme.primaryAccent',
    );
    expect(
      colorScheme.onPrimary,
      equals(slateDark.onPrimaryColor),
      reason: 'ColorScheme.onPrimary must match AppTheme.onPrimaryColor',
    );
    expect(
      colorScheme.primaryContainer,
      equals(slateDark.primaryContainerColor),
      reason: 'ColorScheme.primaryContainer must match AppTheme.primaryContainerColor',
    );
    expect(
      colorScheme.onPrimaryContainer,
      equals(slateDark.onPrimaryContainerColor),
      reason: 'ColorScheme.onPrimaryContainer must match AppTheme.onPrimaryContainerColor',
    );
    expect(
      colorScheme.secondary,
      equals(slateDark.secondaryAccent),
      reason: 'ColorScheme.secondary must match AppTheme.secondaryAccent',
    );
    expect(
      colorScheme.secondaryContainer,
      equals(slateDark.secondaryContainerColor),
      reason: 'ColorScheme.secondaryContainer must match AppTheme.secondaryContainerColor',
    );
    expect(
      colorScheme.onSecondaryContainer,
      equals(slateDark.onSecondaryContainerColor),
      reason: 'ColorScheme.onSecondaryContainer must match AppTheme.onSecondaryContainerColor',
    );
    expect(
      slateDarkThemeData.floatingActionButtonTheme.backgroundColor,
      equals(slateDark.primaryContainerColor),
      reason: 'M3 FAB theme must use primaryContainerColor',
    );
    expect(
      slateDarkThemeData.floatingActionButtonTheme.foregroundColor,
      equals(slateDark.onPrimaryContainerColor),
      reason: 'M3 FAB theme must use onPrimaryContainerColor',
    );
    expect(
      slateDarkThemeData.badgeTheme.backgroundColor,
      equals(slateDark.secondaryContainerColor),
      reason: 'M3 Badge theme must use secondaryContainerColor instead of error red',
    );
    expect(
      slateDarkThemeData.badgeTheme.textColor,
      equals(slateDark.onSecondaryContainerColor),
      reason: 'M3 Badge theme must use onSecondaryContainerColor',
    );
    final selectedSegmentBg = slateDarkThemeData
        .segmentedButtonTheme
        .style
        ?.backgroundColor
        ?.resolve(const <WidgetState>{WidgetState.selected});
    final selectedSegmentFg = slateDarkThemeData
        .segmentedButtonTheme
        .style
        ?.foregroundColor
        ?.resolve(const <WidgetState>{WidgetState.selected});
    expect(
      selectedSegmentBg,
      equals(slateDark.secondaryContainerColor),
      reason: 'Selected SegmentedButton segment must use M3 secondaryContainerColor',
    );
    expect(
      selectedSegmentFg,
      equals(slateDark.onSecondaryContainerColor),
      reason: 'Selected SegmentedButton segment must use M3 onSecondaryContainerColor',
    );

    final copied = slateDark.copyWith(
      primaryContainerColor: const Color(0xFF123456),
      secondaryContainerColor: const Color(0xFF654321),
    );
    expect(
      copied.primaryContainerColor,
      equals(const Color(0xFF123456)),
      reason: 'copyWith must update primaryContainerColor',
    );
    expect(
      copied.secondaryContainerColor,
      equals(const Color(0xFF654321)),
      reason: 'copyWith must update secondaryContainerColor',
    );

    final lerped = slateDark.lerp(slateLight, 0.5);
    expect(
      lerped.primaryContainerColor,
      equals(
        Color.lerp(
          slateDark.primaryContainerColor,
          slateLight.primaryContainerColor,
          0.5,
        ),
      ),
      reason: 'lerp must interpolate M3 container color tokens',
    );
  });

  testWidgets(
    'Switching between Slate and Navy palettes and Dark/Light modes updates M3 surfaces and container highlights across screens',
    (tester) async {
      const initialConfig = WebDavConfig(
        language: AppLanguage.english,
        themeMode: AppThemeMode.dark,
        themePalette: AppThemePalette.slate,
      );
      final settingsRepository = InMemorySettingsRepository(initialConfig);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepository),
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

      final slateDarkScaffold = tester.widget<Scaffold>(
        find.byType(Scaffold).first,
      );
      expect(
        slateDarkScaffold.backgroundColor,
        equals(AppTheme.slateDark.canvasColor),
        reason: 'HomeScreen Scaffold must default to AppTheme.slateDark.canvasColor in dark mode',
      );

      final addFab = tester.widget<FloatingActionButton>(
        find.byKey(const ValueKey('add_task_fab')),
      );
      expect(
        addFab.backgroundColor,
        equals(AppTheme.slateDark.primaryContainerColor),
        reason: 'Primary add FAB must use M3 primaryContainerColor (#004C6B)',
      );
      expect(
        addFab.foregroundColor,
        equals(AppTheme.slateDark.onPrimaryContainerColor),
        reason: 'Primary add FAB must use M3 onPrimaryContainerColor (#CCE1F0)',
      );

      await openSettingsFromMenu(tester);

      expect(
        find.text('Color Palette'),
        findsOneWidget,
        reason: 'SettingsScreen must display the Color Palette section',
      );
      expect(find.text('Slate'), findsOneWidget);
      expect(find.text('Navy'), findsOneWidget);

      await tester.tap(find.text('Navy'));
      await tester.pumpAndSettle();

      final savedConfig = await settingsRepository.loadConfig();
      expect(
        savedConfig.themePalette,
        equals(AppThemePalette.navy),
        reason: 'Selecting Navy in SettingsScreen must persist AppThemePalette.navy',
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      final navyDarkScaffold = tester.widget<Scaffold>(
        find.byType(Scaffold).first,
      );
      expect(
        navyDarkScaffold.backgroundColor,
        equals(AppTheme.navyDark.canvasColor),
        reason: 'HomeScreen Scaffold must switch to AppTheme.navyDark.canvasColor when Navy palette is selected',
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TierTaskApp)),
      );
      await container
          .read(webDavConfigProvider.notifier)
          .updateThemeMode(AppThemeMode.light);
      await tester.pumpAndSettle();

      final navyLightScaffold = tester.widget<Scaffold>(
        find.byType(Scaffold).first,
      );
      expect(
        navyLightScaffold.backgroundColor,
        equals(AppTheme.navyLight.canvasColor),
        reason: 'HomeScreen Scaffold must update to AppTheme.navyLight.canvasColor in light mode',
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

      final customTheme = AppTheme.slateDark.copyWith(
        canvasColor: const Color(0xFF1B2E1E),
        cardColor: const Color(0xFF0D1A10),
        elevatedSurfaceColor: const Color(0xFF243D29),
        primaryAccent: const Color(0xFF00E676),
        primaryContainerColor: const Color(0xFF004D25),
        onPrimaryContainerColor: const Color(0xFFB9F6CA),
        secondaryAccent: const Color(0xFF40C4FF),
        secondaryContainerColor: const Color(0xFF004D61),
        onSecondaryContainerColor: const Color(0xFFB3E5FC),
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

      final priorityChip = tester.widget<FilterChip>(
        find.byKey(const ValueKey('task_editor_priority_button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('task_editor_priority_button')),
      );
      await tester.pumpAndSettle();
      final selectedPriorityChip = tester.widget<FilterChip>(
        find.byKey(const ValueKey('task_editor_priority_button')),
      );
      expect(
        priorityChip.selected,
        isFalse,
        reason: 'Priority chip starts unselected in standard mode',
      );
      expect(
        selectedPriorityChip.selectedColor,
        equals(customTheme.primaryAccent.withValues(alpha: 0.22)),
        reason: 'TaskEditorChip must use M3 tonal container alpha highlight for selectedColor',
      );
    },
  );
}
