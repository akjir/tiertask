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
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/ui/widgets/tier_page_indicator.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'Bottom tier indicator renders above QuickAddBar when add button is pressed, updates active icon when sliding across tiers, and jumps to target pane via wave wheel on long-press drag',
    (WidgetTester tester) async {
      const allTiersTdf = '''
tdf 0.2.0

task f1 {
  name "Focus Pane Task"
  created 2026-11-01 07:00
  queued 2026-11-01 07:00
}
task f2 {
  name "Focus Pane Task 2"
  created 2026-11-01 07:05
  queued 2026-11-01 07:05
}
task f3 {
  name "Focus Pane Task 3"
  created 2026-11-01 07:10
  queued 2026-11-01 07:10
}
task r1 {
  name "Ready Pane Task"
  created 2026-11-01 07:15
  queued 2026-11-01 07:15
}
task r2 {
  name "Ready Pane Task 2"
  created 2026-11-01 07:20
  queued 2026-11-01 07:20
}
task r3 {
  name "Ready Pane Task 3"
  created 2026-11-01 07:25
  queued 2026-11-01 07:25
}
task r4 {
  name "Ready Pane Task 4"
  created 2026-11-01 07:30
  queued 2026-11-01 07:30
}
task r5 {
  name "Ready Pane Task 5"
  created 2026-11-01 07:35
  queued 2026-11-01 07:35
}
task p1 {
  name "Planned Pane Task"
  created 2026-11-01 07:40
  queued 2026-11-01 07:40
}
task blk1 {
  name "Blocked Pane Task"
  created 2026-11-01 07:45
  queued 2026-11-01 07:45
  blocked f1
}
task susp1 {
  name "Suspended Pane Task"
  created 2026-11-01 07:50
  queued 2026-11-01 07:50
  suspended 2026-11-05 09:00
}
task smd1 {
  name "Someday Pane Task"
  created 2026-11-01 08:00
}
task cmp1 {
  name "Completed Pane Task"
  created 2026-10-28 08:00
  queued 2026-10-28 08:00
  finished 2026-10-29 10:00
}
''';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(
                const WebDavConfig(language: AppLanguage.english),
              ),
            ),
            localFileRepositoryProvider.overrideWith(
              (ref) => FakeLocalFileRepository(
                config: const WebDavConfig(language: AppLanguage.english),
                initialTdf: allTiersTdf,
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

      final indicatorFinder = find.byKey(const ValueKey('tier_page_indicator'));
      expect(
        indicatorFinder,
        findsOneWidget,
        reason: 'Bottom tier indicator must be rendered at the bottom edge',
      );

      final focusItem = find.byKey(const ValueKey('tier_indicator_item_focus'));
      final readyItem = find.byKey(const ValueKey('tier_indicator_item_ready'));
      final plannedItem = find.byKey(
        const ValueKey('tier_indicator_item_planned'),
      );
      final blockedItem = find.byKey(
        const ValueKey('tier_indicator_item_blocked'),
      );
      final somedayItem = find.byKey(
        const ValueKey('tier_indicator_item_someday'),
      );
      final completedItem = find.byKey(
        const ValueKey('tier_indicator_item_completed'),
      );

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

      expect(
        find.byKey(const ValueKey('tier_indicator_icon_focus')),
        findsOneWidget,
        reason: 'Active Focus tier must render an icon instead of a dot',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_dot_focus')),
        findsNothing,
        reason: 'Active Focus tier must not render a dot',
      );
      for (final inactiveName in [
        'ready',
        'planned',
        'blocked',
        'someday',
        'completed',
      ]) {
        expect(
          find.byKey(ValueKey('tier_indicator_dot_$inactiveName')),
          findsOneWidget,
          reason: 'Inactive tier $inactiveName must render a dot',
        );
        expect(
          find.byKey(ValueKey('tier_indicator_icon_$inactiveName')),
          findsNothing,
          reason: 'Inactive tier $inactiveName must not render an icon',
        );
      }

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final quickAddBarFinder = find.byKey(const ValueKey('quick_add_bar'));
      expect(quickAddBarFinder, findsOneWidget);
      expect(
        indicatorFinder,
        findsOneWidget,
        reason: 'Tier indicator must remain visible when QuickAddBar is open',
      );
      expect(
        tester.getBottomLeft(indicatorFinder).dy <=
            tester.getTopLeft(quickAddBarFinder).dy + 1.0,
        isTrue,
        reason: 'Tier indicator must be positioned above QuickAddBar when the add button is pressed',
      );

      await tester.tap(find.byKey(const ValueKey('quick_add_cancel_button')));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(
        find.text("What's up!"),
        findsNothing,
        reason: 'Ready pane must not display the legacy greeting',
      );
      expect(
        find.byKey(const ValueKey('top_bar_title')),
        findsNothing,
        reason: 'Top header must not display a title on the Ready pane when no label is selected',
      );
      expect(
        find.text('READY TASKS'),
        findsOneWidget,
        reason: 'Ready pane must display the uppercase section label matching the Focus screen',
      );
      expect(
        find.text('Ready Pane Task'),
        findsOneWidget,
        reason: 'Sliding right-to-left from Focus must display Ready tier pane',
      );
      expect(
        find.byKey(const ValueKey('tier_pill_ready_r1')),
        findsOneWidget,
        reason:
            'Ready task must render as a pill card matching the Focus screen',
      );
      expect(
        find.byIcon(Icons.more_vert_rounded),
        findsNothing,
        reason: 'Ready task pill must not display the legacy overflow menu',
      );
      expect(
        find.byKey(const ValueKey('downgrade_task_button_r1')),
        findsOneWidget,
        reason: 'Ready task pill must display the downgrade arrow button to the left of the gap',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_icon_ready')),
        findsOneWidget,
        reason: 'Sliding to Ready must display the Ready icon in the indicator',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_dot_focus')),
        findsOneWidget,
        reason: 'Focus must become a dot after sliding to Ready',
      );

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(
        find.text('PLANNED TASKS'),
        findsOneWidget,
        reason: 'Planned pane must display the uppercase section label matching the Focus screen',
      );
      expect(
        find.text('Planned Pane Task'),
        findsOneWidget,
        reason: 'Sliding again must display Planned tier pane',
      );
      expect(
        find.byKey(const ValueKey('tier_pill_planned_p1')),
        findsOneWidget,
        reason:
            'Planned task must render as a pill card matching the Focus screen',
      );
      expect(
        find.byKey(const ValueKey('downgrade_task_button_p1')),
        findsOneWidget,
        reason: 'Planned task pill must display the downgrade arrow button to the left of the gap',
      );
      expect(
        find.byIcon(Icons.arrow_downward_rounded),
        findsOneWidget,
        reason: 'Planned pane must render the downgrade arrow icon for Planned tasks',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_icon_planned')),
        findsOneWidget,
        reason: 'Planned tier must display its icon when active',
      );

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(
        find.text('BLOCKED TASKS'),
        findsOneWidget,
        reason: 'Blocked pane must display the uppercase section label matching the Focus screen',
      );
      expect(
        find.text('Blocked Pane Task'),
        findsOneWidget,
        reason: 'Sliding to Blocked pane must show blocked tasks',
      );
      expect(
        find.text('Suspended Pane Task'),
        findsOneWidget,
        reason: 'Blocked pane must also show suspended tasks',
      );
      expect(
        find.byKey(const ValueKey('tier_pill_blocked_blk1')),
        findsOneWidget,
        reason:
            'Blocked task must render as a pill card matching the Focus screen',
      );
      expect(
        find.byIcon(Icons.arrow_upward_rounded),
        findsNothing,
        reason: 'Blocked task pill must not display the legacy promote arrow button',
      );
      expect(
        find.byKey(const ValueKey('downgrade_task_button_blk1')),
        findsNothing,
        reason: 'Blocked task pill must not display a downgrade arrow button',
      );
      expect(
        find.byIcon(Icons.arrow_downward_rounded),
        findsNothing,
        reason: 'Blocked pane must not render any downgrade arrow icons',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_icon_blocked')),
        findsOneWidget,
        reason: 'Blocked tier must display its icon when active',
      );

      final gesture = await tester.startGesture(tester.getCenter(blockedItem));
      await tester.pump(const Duration(milliseconds: 600));

      final waveLabelFinder = find.byKey(
        const ValueKey('tier_indicator_wave_label'),
      );
      expect(
        waveLabelFinder,
        findsOneWidget,
        reason:
            'Holding the indicator must display the tier name above the wave',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_wave_arc')),
        findsNothing,
        reason: 'Connecting line and dark-blue bottom wave background must not be rendered',
      );
      final waveLabelContainer = tester.widget<Container>(waveLabelFinder);
      final waveLabelDecoration =
          waveLabelContainer.decoration as BoxDecoration?;
      expect(
        waveLabelDecoration?.border,
        isNull,
        reason: 'Overlay tier name label must not have a border',
      );
      expect(
        find.descendant(of: waveLabelFinder, matching: find.text('Blocked')),
        findsOneWidget,
        reason:
            'Wave label must initially show Blocked while holding over Blocked',
      );

      final focusDotFinder = find.byKey(
        const ValueKey('tier_indicator_dot_focus'),
      );
      final readyDotFinder = find.byKey(
        const ValueKey('tier_indicator_dot_ready'),
      );
      final plannedDotFinder = find.byKey(
        const ValueKey('tier_indicator_dot_planned'),
      );
      final somedayDotFinder = find.byKey(
        const ValueKey('tier_indicator_dot_someday'),
      );
      final completedDotFinder = find.byKey(
        const ValueKey('tier_indicator_dot_completed'),
      );

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

      final plannedDotDecoration =
          tester.widget<Container>(plannedDotFinder).decoration
              as BoxDecoration?;
      final focusDotDecoration =
          tester.widget<Container>(focusDotFinder).decoration as BoxDecoration?;
      expect(
        plannedDotDecoration?.color,
        equals(TierPageIndicator.intermediateColor),
        reason: 'Larger adjacent wave dots must use the intermediate color between inactive dot and active icon',
      );
      expect(
        focusDotDecoration?.color,
        equals(TierPageIndicator.inactiveDotColor),
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

      expect(
        find.descendant(of: waveLabelFinder, matching: find.text('Completed')),
        findsOneWidget,
        reason: 'Dragging the held indicator to Completed must update the wave label to Completed',
      );
      final somedayNeighborSize = tester.getSize(
        find.byKey(const ValueKey('tier_indicator_dot_someday')),
      );
      final blockedNonNeighborSize = tester.getSize(
        find.byKey(const ValueKey('tier_indicator_dot_blocked')),
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

      expect(
        waveLabelFinder,
        findsNothing,
        reason: 'Releasing the indicator must hide the wave label',
      );
      expect(
        find.text('COMPLETED TASKS'),
        findsOneWidget,
        reason: 'Completed pane must display the uppercase section label matching the Focus screen',
      );
      expect(
        find.text('Completed Pane Task'),
        findsOneWidget,
        reason: 'Releasing the indicator on Completed must jump directly to the Completed pane',
      );
      expect(
        find.byKey(const ValueKey('tier_pill_completed_cmp1')),
        findsOneWidget,
        reason: 'Completed task must render as a pill card matching the Focus screen',
      );
      expect(
        find.byIcon(Icons.more_vert_rounded),
        findsNothing,
        reason: 'Completed task pill must not render the legacy overflow menu or Move to button',
      );
      expect(
        find.byKey(const ValueKey('downgrade_task_button_cmp1')),
        findsNothing,
        reason: 'Completed task pill must not display a downgrade arrow button',
      );
      expect(
        find.byIcon(Icons.arrow_downward_rounded),
        findsNothing,
        reason: 'Completed pane must not render any downgrade arrow icons',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_icon_completed')),
        findsOneWidget,
        reason:
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
      final hoveredSomedayIconFinder = find.byKey(
        const ValueKey('tier_indicator_icon_someday'),
      );
      expect(
        hoveredSomedayIconFinder,
        findsOneWidget,
        reason: 'Desktop mouse-over on an inactive indicator must display its icon instead of a dot',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_dot_someday')),
        findsNothing,
        reason: 'Desktop mouse-over on an inactive indicator must replace the dot with the icon',
      );
      final hoveredSomedayIcon = tester.widget<Icon>(hoveredSomedayIconFinder);
      final activeCompletedIcon = tester.widget<Icon>(
        find.byKey(const ValueKey('tier_indicator_icon_completed')),
      );
      expect(
        hoveredSomedayIcon.color,
        equals(TierPageIndicator.intermediateColor),
        reason: 'Hovered indicator icon must be rendered in the color between the active icon color and inactive dot color',
      );
      expect(
        activeCompletedIcon.color,
        equals(TierPageIndicator.activeIconColor),
        reason: 'Active indicator icon must keep the active icon color',
      );
      expect(
        find.descendant(of: indicatorFinder, matching: find.text('Someday')),
        findsOneWidget,
        reason: 'Desktop mouse-over must display the hovered tier name without wave animation',
      );

      await tester.tap(somedayItem);
      await tester.pumpAndSettle();

      expect(
        find.text('SOMEDAY TASKS'),
        findsOneWidget,
        reason: 'Someday pane must display the uppercase section label matching the Focus screen',
      );
      expect(
        find.text('Someday Pane Task'),
        findsOneWidget,
        reason: 'Clicking a tier indicator item on desktop must jump to that tier pane',
      );
      expect(
        find.byKey(const ValueKey('tier_pill_someday_smd1')),
        findsOneWidget,
        reason:
            'Someday task must render as a pill card matching the Focus screen',
      );
      expect(
        find.byKey(const ValueKey('downgrade_task_button_smd1')),
        findsNothing,
        reason: 'Someday task pill must not display a downgrade arrow button',
      );
      expect(
        find.byIcon(Icons.arrow_downward_rounded),
        findsNothing,
        reason: 'Someday pane must not render any downgrade arrow icons',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_icon_someday')),
        findsOneWidget,
        reason: 'Someday tier must display its icon after selecting Someday',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(
        find.text('Blocked Pane Task'),
        findsOneWidget,
        reason: 'Pressing Left Arrow on desktop must navigate to the previous tier pane (Blocked)',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_icon_blocked')),
        findsOneWidget,
        reason: 'Active indicator icon must update to Blocked after Left Arrow',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(
        find.text('Someday Pane Task'),
        findsOneWidget,
        reason: 'Pressing Right Arrow on desktop must navigate to the next tier pane (Someday)',
      );
      expect(
        find.byKey(const ValueKey('tier_indicator_icon_someday')),
        findsOneWidget,
        reason:
            'Active indicator icon must update to Someday after Right Arrow',
      );
    },
  );
}
