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

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/ui/app_theme.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'Bottom tier indicator renders above QuickAddBar when add button is pressed, updates active icon when sliding across tiers, and jumps to target pane via wave wheel on long-press drag',
    (WidgetTester tester) async {
      const allTiersTdf = '''
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
  task blk100OkD2
  task susp10OkD2
}

task f10000OkD2 {
  name "Focus Pane Task"
  created 2026-11-01 07:00
  queued 2026-11-01 07:00
}
task f20000OkD2 {
  name "Focus Pane Task 2"
  created 2026-11-01 07:05
  queued 2026-11-01 07:05
}
task f30000OkD2 {
  name "Focus Pane Task 3"
  created 2026-11-01 07:10
  queued 2026-11-01 07:10
}
task r10000OkD2 {
  name "Ready Pane Task"
  created 2026-11-01 07:15
  queued 2026-11-01 07:15
}
task r20000OkD2 {
  name "Ready Pane Task 2"
  created 2026-11-01 07:20
  queued 2026-11-01 07:20
}
task r30000OkD2 {
  name "Ready Pane Task 3"
  created 2026-11-01 07:25
  queued 2026-11-01 07:25
}
task r40000OkD2 {
  name "Ready Pane Task 4"
  created 2026-11-01 07:30
  queued 2026-11-01 07:30
}
task r50000OkD2 {
  name "Ready Pane Task 5"
  created 2026-11-01 07:35
  queued 2026-11-01 07:35
}
task p10000OkD2 {
  name "Planned Pane Task"
  created 2026-11-01 07:40
  queued 2026-11-01 07:40
}
task blk100OkD2 {
  name "Blocked Pane Task"
  created 2026-11-01 07:45
  queued 2026-11-01 07:45
  blocked f10000OkD2
}
task susp10OkD2 {
  name "Suspended Pane Task"
  created 2026-11-01 07:50
  queued 2026-11-01 07:50
  suspended 2026-11-05 09:00
}
task smd100OkD2 {
  name "Someday Pane Task"
  created 2026-11-01 08:00
}
task cmp100OkD2 {
  name "Completed Pane Task"
  created 2026-10-28 08:00
  queued 2026-10-28 08:00
  finished 2026-10-29 10:00
  completions 1
}
''';

      await _pumpAllTiersApp(tester, allTiersTdf);

      final indicatorFinder = _byKey('tier_page_indicator');
      _expectOne(
        indicatorFinder,
        'Bottom tier indicator must be rendered at the bottom edge',
      );

      final focusItem = _byKey('tier_indicator_item_focus');
      final readyItem = _byKey('tier_indicator_item_ready');
      final plannedItem = _byKey('tier_indicator_item_planned');
      final blockedItem = _byKey('tier_indicator_item_blocked');
      final somedayItem = _byKey('tier_indicator_item_someday');
      final completedItem = _byKey('tier_indicator_item_completed');

      expect(focusItem, findsOneWidget);
      expect(readyItem, findsOneWidget);
      expect(plannedItem, findsOneWidget);
      expect(blockedItem, findsOneWidget);
      expect(somedayItem, findsOneWidget);
      expect(completedItem, findsOneWidget);

      final focusDx = tester.getCenter(focusItem).dx;
      final readyDx = tester.getCenter(readyItem).dx;
      final plannedDx = tester.getCenter(plannedItem).dx;
      final blockedDx = tester.getCenter(blockedItem).dx;
      final somedayDx = tester.getCenter(somedayItem).dx;
      final completedDx = tester.getCenter(completedItem).dx;

      expect(
        focusDx < readyDx &&
            readyDx < plannedDx &&
            plannedDx < blockedDx &&
            blockedDx < somedayDx &&
            somedayDx < completedDx,
        isTrue,
        reason: 'Tier indicator items must be ordered left-to-right: Focus, Ready, Planned, Blocked, Someday, Completed',
      );

      _expectOne(
        _byKey('tier_indicator_icon_focus'),
        'Active Focus tier must render an icon instead of a dot',
      );
      _expectNone(
        _byKey('tier_indicator_dot_focus'),
        'Active Focus tier must not render a dot',
      );
      for (final inactiveName in [
        'ready',
        'planned',
        'blocked',
        'someday',
        'completed',
      ]) {
        _expectOne(
          _byKey('tier_indicator_dot_$inactiveName'),
          'Inactive tier $inactiveName must render a dot',
        );
        _expectNone(
          _byKey('tier_indicator_icon_$inactiveName'),
          'Inactive tier $inactiveName must not render an icon',
        );
      }

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final quickAddBarFinder = _byKey('quick_add_bar');
      expect(quickAddBarFinder, findsOneWidget);
      _expectOne(
        indicatorFinder,
        'Tier indicator must remain visible when QuickAddBar is open',
      );
      expect(
        tester.getBottomLeft(indicatorFinder).dy <=
            tester.getTopLeft(quickAddBarFinder).dy + 1.0,
        isTrue,
        reason: 'Tier indicator must be positioned above QuickAddBar when the add button is pressed',
      );

      await tester.tap(_byKey('quick_add_cancel_button'));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      _expectNone(
        find.text("What's up!"),
        'Ready pane must not display the legacy greeting',
      );
      _expectNone(
        _byKey('top_bar_title'),
        'Top header must not display a title on the Ready pane when no label is selected',
      );
      final readyHeadingFinder = find.text('READY TASKS');
      _expectOne(
        readyHeadingFinder,
        'Ready pane must display the uppercase section label matching the Focus screen',
      );
      final readyHeadingText = tester.widget<Text>(readyHeadingFinder);
      final readyHeadingRect = tester.getRect(readyHeadingFinder);
      final readyPillTop = tester
          .getTopLeft(_byKey('tier_pill_ready_r10000OkD2'))
          .dy;
      final viewportWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(
        readyHeadingText.style?.fontSize,
        equals(15),
        reason: 'Ready tasks heading must use the enlarged 15px font size',
      );
      expect(
        readyHeadingRect.center.dx,
        closeTo(viewportWidth / 2.0, 1.0),
        reason: 'Ready tasks heading must be horizontally centered on screen',
      );
      expect(
        readyPillTop - readyHeadingRect.bottom >= 24.0,
        isTrue,
        reason: 'Spacing below Ready tasks heading to the first task pill must be at least 24px',
      );
      _expectOne(
        find.text('Ready Pane Task'),
        'Sliding right-to-left from Focus must display Ready tier pane',
      );
      _expectOne(
        _byKey('tier_pill_ready_r10000OkD2'),
        'Ready task must render as a pill card matching the Focus screen',
      );
      _expectOne(
        find.descendant(
          of: _byKey('edit_task_button_r10000OkD2'),
          matching: find.byIcon(Icons.more_vert_rounded),
        ),
        'Ready task pill must display the three-dots edit button',
      );
      _expectOne(
        _byKey('downgrade_task_button_r10000OkD2'),
        'Ready task pill must display the > downgrade button',
      );
      _expectOne(
        _byKey('tier_indicator_icon_ready'),
        'Sliding to Ready must display the Ready icon in the indicator',
      );
      _expectOne(
        _byKey('tier_indicator_dot_focus'),
        'Focus must become a dot after sliding to Ready',
      );

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      _expectOne(
        find.text('PLANNED TASKS'),
        'Planned pane must display the uppercase section label matching the Focus screen',
      );
      _expectOne(
        find.text('Planned Pane Task'),
        'Sliding again must display Planned tier pane',
      );
      _expectOne(
        _byKey('tier_pill_planned_p10000OkD2'),
        'Planned task must render as a pill card matching the Focus screen',
      );
      _expectOne(
        _byKey('downgrade_task_button_p10000OkD2'),
        'Planned task pill must display the > downgrade button',
      );
      _expectOne(
        find.byIcon(Icons.chevron_right_rounded),
        'Planned pane must render the > downgrade icon for Planned tasks',
      );
      _expectOne(
        _byKey('tier_indicator_icon_planned'),
        'Planned tier must display its icon when active',
      );

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      _expectOne(
        find.text('BLOCKED TASKS'),
        'Blocked pane must display the uppercase section label matching the Focus screen',
      );
      _expectOne(
        find.text('Blocked Pane Task'),
        'Sliding to Blocked pane must show blocked tasks',
      );
      _expectOne(
        find.text('Suspended Pane Task'),
        'Blocked pane must also show suspended tasks',
      );
      _expectOne(
        _byKey('tier_pill_blocked_blk100OkD2'),
        'Blocked task must render as a pill card matching the Focus screen',
      );
      _expectNone(
        find.byIcon(Icons.arrow_upward_rounded),
        'Blocked task pill must not display the legacy promote arrow button',
      );
      _expectNone(
        _byKey('downgrade_task_button_blk100OkD2'),
        'Blocked task pill must not display a downgrade button',
      );
      _expectNone(
        find.byIcon(Icons.chevron_right_rounded),
        'Blocked pane must not render any > downgrade icons',
      );
      _expectOne(
        _byKey('tier_indicator_icon_blocked'),
        'Blocked tier must display its icon when active',
      );

      final gesture = await tester.startGesture(tester.getCenter(blockedItem));
      await tester.pump(const Duration(milliseconds: 600));

      final waveLabelFinder = _byKey('tier_indicator_wave_label');
      _expectOne(
        waveLabelFinder,
        'Holding the indicator must display the tier name above the wave',
      );
      _expectNone(
        _byKey('tier_indicator_wave_arc'),
        'Connecting line and dark-blue bottom wave background must not be rendered',
      );
      final waveLabelContainer = tester.widget<Container>(waveLabelFinder);
      final waveLabelDecoration =
          waveLabelContainer.decoration as BoxDecoration?;
      expect(
        waveLabelDecoration?.border,
        isNull,
        reason: 'Overlay tier name label must not have a border',
      );
      _expectOne(
        find.descendant(of: waveLabelFinder, matching: find.text('Blocked')),
        'Wave label must initially show Blocked while holding over Blocked',
      );

      final focusDotFinder = _byKey('tier_indicator_dot_focus');
      final readyDotFinder = _byKey('tier_indicator_dot_ready');
      final plannedDotFinder = _byKey('tier_indicator_dot_planned');
      final somedayDotFinder = _byKey('tier_indicator_dot_someday');
      final completedDotFinder = _byKey('tier_indicator_dot_completed');

      final focusDotSize = tester.getSize(focusDotFinder);
      final readyDotSize = tester.getSize(readyDotFinder);
      final plannedDotSize = tester.getSize(plannedDotFinder);
      final somedayDotSize = tester.getSize(somedayDotFinder);
      final completedDotSize = tester.getSize(completedDotFinder);
      expect(
        plannedDotSize.width,
        closeTo(focusDotSize.width * 1.5, 0.01),
        reason: 'Left neighbor dot (Planned) adjacent to active Blocked tier must be 1.5x base dot size during wave effect',
      );
      expect(
        somedayDotSize.width,
        closeTo(focusDotSize.width * 1.5, 0.01),
        reason: 'Right neighbor dot (Someday) adjacent to active Blocked tier must be 1.5x base dot size during wave effect',
      );
      expect(
        readyDotSize.width,
        closeTo(focusDotSize.width, 0.01),
        reason: 'Non-adjacent dots must keep the base dot size',
      );
      expect(
        completedDotSize.width,
        closeTo(focusDotSize.width, 0.01),
        reason: 'Non-adjacent dots must keep the base dot size',
      );

      final activeAppTheme = AppTheme.of(tester.element(indicatorFinder));
      final plannedDotDecoration =
          tester.widget<Container>(plannedDotFinder).decoration
              as BoxDecoration?;
      final focusDotDecoration =
          tester.widget<Container>(focusDotFinder).decoration as BoxDecoration?;
      expect(
        plannedDotDecoration?.color,
        equals(activeAppTheme.indicatorIntermediateColor),
        reason: 'Larger adjacent wave dots must use the intermediate color between inactive dot and active icon',
      );
      expect(
        focusDotDecoration?.color,
        equals(activeAppTheme.indicatorInactiveDotColor),
        reason: 'Non-adjacent dots must use the standard inactive dot color',
      );

      final blockedWaveDy = tester.getCenter(blockedItem).dy;
      final focusWaveDy = tester.getCenter(focusItem).dy;
      expect(
        blockedWaveDy < focusWaveDy,
        isTrue,
        reason: 'Held tier item in the wave crest must be lifted higher (smaller dy) than distant items',
      );

      final completedTarget = tester.getCenter(completedItem);
      await gesture.moveTo(completedTarget);
      await tester.pump();

      _expectOne(
        find.descendant(of: waveLabelFinder, matching: find.text('Completed')),
        'Dragging the held indicator to Completed must update the wave label to Completed',
      );
      final somedayNeighborSize = tester.getSize(
        _byKey('tier_indicator_dot_someday'),
      );
      final blockedNonNeighborSize = tester.getSize(
        _byKey('tier_indicator_dot_blocked'),
      );
      expect(
        somedayNeighborSize.width,
        closeTo(blockedNonNeighborSize.width * 1.5, 0.01),
        reason: 'Adjacent neighbor dot (Someday) next to Completed must be 1.5x base size',
      );
      final completedWaveDy = tester.getCenter(completedItem).dy;
      final readyWaveDy = tester.getCenter(readyItem).dy;
      expect(
        completedWaveDy < readyWaveDy,
        isTrue,
        reason: 'Moving the wave to Completed must lift the Completed item higher than distant items',
      );

      await gesture.up();
      await tester.pumpAndSettle();

      _expectNone(
        waveLabelFinder,
        'Releasing the indicator must hide the wave label',
      );
      _expectOne(
        find.text('COMPLETED TASKS'),
        'Completed pane must display the uppercase section label matching the Focus screen',
      );
      _expectOne(
        find.text('Completed Pane Task'),
        'Releasing the indicator on Completed must jump directly to the Completed pane',
      );
      _expectOne(
        _byKey('tier_pill_completed_cmp100OkD2'),
        'Completed task must render as a pill card matching the Focus screen',
      );
      _expectOne(
        find.descendant(
          of: _byKey('edit_task_button_cmp100OkD2'),
          matching: find.byIcon(Icons.more_vert_rounded),
        ),
        'Completed task pill must render the three-dots edit button',
      );
      _expectNone(
        _byKey('downgrade_task_button_cmp100OkD2'),
        'Completed task pill must not display a downgrade button',
      );
      _expectNone(
        find.byIcon(Icons.chevron_right_rounded),
        'Completed pane must not render any > downgrade icons',
      );
      _expectOne(
        _byKey('tier_indicator_icon_completed'),
        'Completed tier must display its icon after jumping to Completed',
      );

      final mouseGesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouseGesture.addPointer(location: Offset.zero);
      addTearDown(mouseGesture.removePointer);

      await mouseGesture.moveTo(tester.getCenter(somedayItem));
      await tester.pumpAndSettle();

      expect(
        tester.getCenter(somedayItem).dy,
        closeTo(tester.getCenter(focusItem).dy, 0.1),
        reason: 'Desktop mouse-over must keep indicator items flat without vertical wave displacement',
      );
      final hoveredSomedayIconFinder = _byKey('tier_indicator_icon_someday');
      _expectOne(
        hoveredSomedayIconFinder,
        'Desktop mouse-over on an inactive indicator must display its icon instead of a dot',
      );
      _expectNone(
        _byKey('tier_indicator_dot_someday'),
        'Desktop mouse-over on an inactive indicator must replace the dot with the icon',
      );
      final hoveredSomedayIcon = tester.widget<Icon>(hoveredSomedayIconFinder);
      final activeCompletedIcon = tester.widget<Icon>(
        _byKey('tier_indicator_icon_completed'),
      );
      expect(
        hoveredSomedayIcon.color,
        equals(activeAppTheme.indicatorIntermediateColor),
        reason: 'Hovered indicator icon must be rendered in the color between the active icon color and inactive dot color',
      );
      expect(
        activeCompletedIcon.color,
        equals(activeAppTheme.indicatorActiveIconColor),
        reason: 'Active indicator icon must keep the active icon color',
      );
      _expectOne(
        find.descendant(of: indicatorFinder, matching: find.text('Someday')),
        'Desktop mouse-over must display the hovered tier name without wave animation',
      );

      await tester.tap(somedayItem);
      await tester.pumpAndSettle();

      _expectOne(
        find.text('SOMEDAY TASKS'),
        'Someday pane must display the uppercase section label matching the Focus screen',
      );
      _expectOne(
        find.text('Someday Pane Task'),
        'Clicking a tier indicator item on desktop must jump to that tier pane',
      );
      _expectOne(
        _byKey('tier_pill_someday_smd100OkD2'),
        'Someday task must render as a pill card matching the Focus screen',
      );
      _expectNone(
        _byKey('downgrade_task_button_smd100OkD2'),
        'Someday task pill must not display a downgrade button',
      );
      _expectNone(
        find.byIcon(Icons.chevron_right_rounded),
        'Someday pane must not render any > downgrade icons',
      );
      _expectOne(
        _byKey('tier_indicator_icon_someday'),
        'Someday tier must display its icon after selecting Someday',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      _expectOne(
        find.text('Blocked Pane Task'),
        'Pressing Left Arrow on desktop must navigate to the previous tier pane (Blocked)',
      );
      _expectOne(
        _byKey('tier_indicator_icon_blocked'),
        'Active indicator icon must update to Blocked after Left Arrow',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      _expectOne(
        find.text('Someday Pane Task'),
        'Pressing Right Arrow on desktop must navigate to the next tier pane (Someday)',
      );
      _expectOne(
        _byKey('tier_indicator_icon_someday'),
        'Active indicator icon must update to Someday after Right Arrow',
      );
    },
  );
}

/// Finds a widget by its string [ValueKey].
Finder _byKey(String key) => find.byKey(ValueKey(key));

/// Asserts that [finder] matches zero widgets with [reason].
void _expectNone(Finder finder, String reason) =>
    expect(finder, findsNothing, reason: reason);

/// Asserts that [finder] matches exactly one widget with [reason].
void _expectOne(Finder finder, String reason) =>
    expect(finder, findsOneWidget, reason: reason);

/// Pumps [TierTaskApp] seeded with [seededTdf] across all six task tiers at `2026-11-01 12:00` UTC.
Future<void> _pumpAllTiersApp(WidgetTester tester, String seededTdf) async {
  const config = WebDavConfig(language: AppLanguage.english);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(config),
        ),
        localFileRepositoryProvider.overrideWith(
          (ref) =>
              FakeLocalFileRepository(config: config, initialTdf: seededTdf),
        ),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1, 12, 0)),
      ],
      child: const TierTaskApp(),
    ),
  );
  await tester.pumpAndSettle();
}
