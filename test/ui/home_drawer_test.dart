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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/app_version_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';

import 'test_helpers.dart';

void main() {
  testWidgets(
    'Landing page renders German labels, hides empty categories and locations, and exposes German Labels section without tiers in the top-left menu',
    (WidgetTester tester) async {
      await _pumpDrawerApp(
        tester,
        config: const WebDavConfig(language: AppLanguage.german),
      );

      expect(
        find.text('Was steht an!'),
        findsNothing,
        reason: 'German legacy greeting must not be rendered',
      );
      expect(
        find.byKey(const ValueKey('top_bar_title')),
        findsNothing,
        reason: 'Top bar title must be hidden when no label filter is active',
      );
      expect(
        find.textContaining('Olivia'),
        findsNothing,
        reason: 'Legacy user name must not appear on landing page',
      );
      expect(
        find.text('FOKUSAUFGABEN'),
        findsOneWidget,
        reason: 'German Focus tasks heading must be displayed',
      );
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      expect(
        find.text('ALLE AUFGABEN'),
        findsOneWidget,
        reason: 'German search screen must display ALLE AUFGABEN',
      );
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(
        find.text('FOKUSAUFGABEN'),
        findsOneWidget,
        reason: 'Closing search must restore German Focus heading',
      );
      expect(
        find.text('KATEGORIEN'),
        findsNothing,
        reason: 'German categories heading must be hidden when none exist',
      );
      expect(
        find.text('ORTE'),
        findsNothing,
        reason: 'German locations heading must be hidden when none exist',
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      expect(
        find.text('Bereit'),
        findsNothing,
        reason: 'Drawer must not list Ready tier navigation item',
      );
      expect(
        find.text('Geplant'),
        findsNothing,
        reason: 'Drawer must not list Planned tier navigation item',
      );
      expect(
        find.text('Blockiert'),
        findsNothing,
        reason: 'Drawer must not list Blocked tier navigation item',
      );
      expect(
        find.text('Irgendwann'),
        findsNothing,
        reason: 'Drawer must not list Someday tier navigation item',
      );
      expect(
        find.text('Erledigt'),
        findsNothing,
        reason: 'Drawer must not list Completed tier navigation item',
      );
      expect(
        find.text('Labels'),
        findsOneWidget,
        reason: 'Drawer must display the German Labels section header',
      );
      expect(
        find.text('Orte'),
        findsOneWidget,
        reason: 'Drawer must display the German Locations section header',
      );
      expect(
        find.text('Bearbeiten'),
        findsNWidgets(2),
        reason: 'Drawer must display the German Edit actions for Labels and Locations',
      );
      expect(
        find.text('Neues Label erstellen'),
        findsOneWidget,
        reason: 'Drawer must display the German Create new label action',
      );
      expect(
        find.text('Neuen Ort erstellen'),
        findsOneWidget,
        reason: 'Drawer must display the German Create new location action',
      );
      expect(
        find.text('Einstellungen'),
        findsOneWidget,
        reason: 'Drawer must display the German Settings action',
      );

      await tester.tap(find.text('TDF-Vorschau anzeigen'));
      await tester.pumpAndSettle();

      expect(
        find.text('Raw TDF'),
        findsOneWidget,
        reason: 'Raw TDF preview dialog must display Raw TDF without Single Source of Truth',
      );
      expect(
        find.textContaining('Single Source of Truth'),
        findsNothing,
        reason:
            'Raw TDF preview dialog must not mention Single Source of Truth',
      );
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Navigation drawer opens secondary tier sheets for Ready, Planned, Blocked (including suspended), Someday, and Completed without a bottom navigation bar',
    (WidgetTester tester) async {
      const secondaryTiersTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 07:50:00
  task f10000OkD2
  task f20000OkD2
  task f30000OkD2
  task r10000OkD2
  task r20000OkD2
  task r30000OkD2
  task r40000OkD2
  task r50000OkD2
  task p10000OkD2
  task blkdepOkD2
  task blksusOkD2
}

task f10000OkD2 {
  name "Focus Task 1"
  created 2026-11-01 07:00
  queued 2026-11-01 07:00
}
task f20000OkD2 {
  name "Focus Task 2"
  created 2026-11-01 07:05
  queued 2026-11-01 07:05
}
task f30000OkD2 {
  name "Focus Task 3"
  created 2026-11-01 07:10
  queued 2026-11-01 07:10
}
task r10000OkD2 {
  name "Ready Task 1"
  created 2026-11-01 07:15
  queued 2026-11-01 07:15
}
task r20000OkD2 {
  name "Ready Task 2"
  created 2026-11-01 07:20
  queued 2026-11-01 07:20
}
task r30000OkD2 {
  name "Ready Task 3"
  created 2026-11-01 07:25
  queued 2026-11-01 07:25
}
task r40000OkD2 {
  name "Ready Task 4"
  created 2026-11-01 07:30
  queued 2026-11-01 07:30
}
task r50000OkD2 {
  name "Ready Task 5"
  created 2026-11-01 07:35
  queued 2026-11-01 07:35
}
task p10000OkD2 {
  name "Planned Backlog Task"
  created 2026-11-01 07:40
  queued 2026-11-01 07:40
}
task blkdepOkD2 {
  name "Blocked Prerequisite Task"
  created 2026-11-01 07:45
  queued 2026-11-01 07:45
  blocked f10000OkD2
}
task blksusOkD2 {
  name "Suspended Deferred Task"
  created 2026-11-01 07:50
  queued 2026-11-01 07:50
  suspended 2026-11-05 09:00
}
task smd100OkD2 {
  name "Someday Idea Task"
  created 2026-11-01 08:00
}
task cmp100OkD2 {
  name "Completed Archive Task"
  created 2026-10-28 08:00
  queued 2026-10-28 08:00
  finished 2026-10-29 10:00
  completions 1
}
''';

      await _pumpDrawerApp(
        tester,
        initialTdf: secondaryTiersTdf,
        clock: DateTime.utc(2026, 11, 1, 12, 0),
      );

      expect(
        find.byKey(const ValueKey('bottom_nav_bar')),
        findsNothing,
        reason: 'Bottom navigation bar must be removed',
      );
      expect(
        find.byType(FloatingActionButton),
        findsOneWidget,
        reason: 'Only the add button must be displayed at the bottom',
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.text('Blocked'),
        ),
        findsNothing,
        reason: 'Navigation drawer must not contain the Blocked tier item',
      );
      await tester.tapAt(const Offset(500, 300));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('tier_indicator_item_blocked')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text("What's up!"),
        findsNothing,
        reason: 'Blocked tier panel must not display the legacy greeting',
      );
      expect(
        find.byKey(const ValueKey('top_bar_title')),
        findsNothing,
        reason: 'Top header must not display a title when no label is selected on Blocked',
      );
      final blockedHeadingFinder = find.text('BLOCKED TASKS');
      expect(
        blockedHeadingFinder,
        findsOneWidget,
        reason: 'Blocked tier panel must display the uppercase section heading',
      );
      final blockedHeadingText = tester.widget<Text>(blockedHeadingFinder);
      final blockedHeadingRect = tester.getRect(blockedHeadingFinder);
      final blockedPillTop = tester
          .getTopLeft(
            find.byKey(const ValueKey('tier_pill_blocked_blkdepOkD2')),
          )
          .dy;
      final viewportWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(
        blockedHeadingText.style?.fontSize,
        equals(15),
        reason: 'Blocked tasks heading must use the enlarged 15px font size',
      );
      expect(
        blockedHeadingRect.center.dx,
        closeTo(viewportWidth / 2.0, 1.0),
        reason: 'Blocked tasks heading must be horizontally centered on screen',
      );
      expect(
        blockedPillTop - blockedHeadingRect.bottom,
        equals(36.0),
        reason: 'Spacing below Blocked tasks heading to the first task pill must be 36px (1.5x of 24px)',
      );
      expect(
        find.text('Blocked Prerequisite Task'),
        findsOneWidget,
        reason:
            'Blocked tier panel must display tasks blocked by prerequisites',
      );
      expect(
        find.text('Suspended Deferred Task'),
        findsOneWidget,
        reason: 'Blocked tier panel must also display suspended tasks',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_icon_blocked')),
        findsOneWidget,
        reason: 'Selecting Blocked from the tier indicator must jump to the Blocked pane',
      );
      expect(
        find.byKey(const ValueKey('tier_pill_blocked_blkdepOkD2')),
        findsOneWidget,
        reason: 'Blocked task must render as a dark-blue pill card matching Focus screen',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('edit_task_button_blkdepOkD2')),
          matching: find.byIcon(Icons.more_vert_rounded),
        ),
        findsOneWidget,
        reason: 'Task entries must render the three-dots edit button',
      );
      expect(
        find.byType(Checkbox),
        findsNothing,
        reason: 'Task entries must not render the legacy Checkbox widget',
      );
    },
  );

  testWidgets(
    'Navigation drawer displays version and build metadata anchored at the bottom of the sidepanel',
    (WidgetTester tester) async {
      await _pumpDrawerApp(tester, version: 'v0.1.0+55.e64e6a5.dev');
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      final drawerFinder = find.byType(Drawer);
      final versionFooterFinder = find.byKey(
        const ValueKey('drawer_version_footer'),
      );
      final versionTextFinder = find.byKey(
        const ValueKey('drawer_version_text'),
      );
      final settingsTileFinder = find.descendant(
        of: drawerFinder,
        matching: find.text('Settings'),
      );

      expect(
        versionFooterFinder,
        findsOneWidget,
        reason: 'Sidepanel must render the bottom version footer container',
      );
      expect(
        versionTextFinder,
        findsOneWidget,
        reason: 'Sidepanel must render the version text widget',
      );
      expect(
        find.descendant(
          of: versionFooterFinder,
          matching: find.text('Version 0.1.0+55.e64e6a5.dev'),
        ),
        findsOneWidget,
        reason:
            'Sidepanel footer must display Version 0.1.0+<count>.<hash>[.dev]',
      );

      final versionTextWidget = tester.widget<Text>(versionTextFinder);
      final rootSpan = versionTextWidget.textSpan;
      expect(
        rootSpan,
        isA<TextSpan>(),
        reason: 'Version footer must use Text.rich with a root TextSpan',
      );
      if (rootSpan case final TextSpan span) {
        final children = span.children ?? const <InlineSpan>[];
        expect(
          children.length,
          equals(2),
          reason: 'Version text must split into Version 0.1.0 and the +build suffix',
        );
        if (children case [
          final TextSpan versionSpan,
          final TextSpan buildSpan,
        ]) {
          expect(versionSpan.text, equals('Version 0.1.0'));
          expect(buildSpan.text, equals('+55.e64e6a5.dev'));
          final versionColor = versionSpan.style?.color;
          final buildColor = buildSpan.style?.color;
          expect(versionColor, isNotNull);
          expect(buildColor, isNotNull);
          if (versionColor != null && buildColor != null) {
            expect(
              buildColor.computeLuminance() < versionColor.computeLuminance(),
              isTrue,
              reason: 'Build metadata starting from + must be rendered darker than Version 0.1.0',
            );
          }
        }
      }

      final drawerRect = tester.getRect(drawerFinder);
      final settingsRect = tester.getRect(settingsTileFinder);
      final footerRect = tester.getRect(versionFooterFinder);

      expect(
        footerRect.top >= settingsRect.bottom,
        isTrue,
        reason: 'Version footer must be positioned below the Settings action',
      );
      expect(
        drawerRect.bottom - footerRect.bottom <= 24.0,
        isTrue,
        reason: 'Version footer must be anchored at the bottom edge of the sidepanel',
      );
    },
  );

  testWidgets(
    'Navigation drawer displays a task-style scoped indicator directly next to the task count badge only for scoped labels',
    (WidgetTester tester) async {
      const scopedLabelsTdf = '''
tdf 0.6.0

queue {
  modified 2026-11-01 08:10:00
  task tskScpOkD2
  task tskRegOkD2
}

label scp000OkD2 scoped {
  name "Focused Project"
}

label reg000OkD2 {
  name "General"
}

task tskScpOkD2 {
  name "Scoped Task"
  created 2026-11-01 08:00
  labels scp000OkD2
}

task tskRegOkD2 {
  name "Regular Task"
  created 2026-11-01 08:05
  labels reg000OkD2
}
''';

      await _pumpDrawerApp(
        tester,
        initialTdf: scopedLabelsTdf,
        clock: DateTime.utc(2026, 11, 1, 12, 0),
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      final scopedIndicatorFinder = find.byKey(
        const ValueKey('drawer_label_scoped_indicator_scp000OkD2'),
      );
      final regularIndicatorFinder = find.byKey(
        const ValueKey('drawer_label_scoped_indicator_reg000OkD2'),
      );
      final scopedBadgeFinder = find.byKey(
        const ValueKey('drawer_label_badge_scp000OkD2'),
      );
      final regularBadgeFinder = find.byKey(
        const ValueKey('drawer_label_badge_reg000OkD2'),
      );

      expect(
        scopedIndicatorFinder,
        findsOneWidget,
        reason: 'Scoped label in drawer must display the scoped indicator icon',
      );
      expect(
        regularIndicatorFinder,
        findsNothing,
        reason: 'Unscoped label in drawer must not display the scoped indicator icon',
      );
      expect(
        scopedBadgeFinder,
        findsOneWidget,
        reason:
            'Scoped label in drawer must still display its task count badge',
      );
      expect(
        regularBadgeFinder,
        findsOneWidget,
        reason: 'Unscoped label in drawer must display its task count badge',
      );

      final tileContext = tester.element(
        find.byKey(const ValueKey('drawer_label_tile_scp000OkD2')),
      );
      final expectedColor = Theme.of(tileContext).colorScheme.onSurfaceVariant
          .withValues(alpha: 0.55);

      final scopedIcon = tester.widget<Icon>(scopedIndicatorFinder);
      expect(
        scopedIcon.icon,
        equals(Icons.visibility_off_outlined),
        reason:
            'Scoped label indicator must use the visibility_off_outlined icon',
      );
      expect(
        scopedIcon.size,
        equals(16),
        reason: 'Scoped label indicator must match the 16px passive task indicator size',
      );
      expect(
        scopedIcon.color,
        equals(expectedColor),
        reason: 'Scoped label indicator must match the dimmed passive task indicator color',
      );

      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: scopedIndicatorFinder,
          matching: find.byType(Tooltip),
        ),
      );
      expect(
        tooltip.message,
        equals('Scoped Label'),
        reason: 'Scoped label indicator must expose the localized Scoped Label tooltip',
      );

      final labelTitleRight = tester
          .getTopRight(find.text('Focused Project'))
          .dx;
      final indicatorLeft = tester.getTopLeft(scopedIndicatorFinder).dx;
      final indicatorRight = tester.getTopRight(scopedIndicatorFinder).dx;
      final badgeLeft = tester.getTopLeft(scopedBadgeFinder).dx;

      expect(
        indicatorLeft >= labelTitleRight,
        isTrue,
        reason: 'Scoped indicator must be positioned to the right of the label name',
      );
      expect(
        indicatorRight <= badgeLeft,
        isTrue,
        reason: 'Scoped indicator must be positioned directly to the left of the task count badge',
      );
    },
  );
}

/// Pumps [TierTaskApp] with optional [config], [initialTdf], [version], and [clock] overrides.
Future<void> _pumpDrawerApp(
  WidgetTester tester, {
  WebDavConfig config = const WebDavConfig(language: AppLanguage.english),
  String? initialTdf,
  String? version,
  DateTime? clock,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (version != null)
          appVersionRepositoryProvider.overrideWithValue(
            FakeAppVersionRepository(version: version),
          ),
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(config),
        ),
        if (initialTdf != null)
          localFileRepositoryProvider.overrideWith(
            (ref) =>
                FakeLocalFileRepository(config: config, initialTdf: initialTdf),
          ),
        clockProvider.overrideWithValue(
          () => clock ?? DateTime.utc(2026, 11, 1),
        ),
      ],
      child: const TierTaskApp(),
    ),
  );
  await tester.pumpAndSettle();
}
