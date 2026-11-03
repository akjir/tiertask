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

import 'test_helpers.dart';

void main() {
  testWidgets(
    'Landing page hides categories and locations when none exist and renders greeting, focus tasks, top-right search, and top-left menu',
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

      expect(
        find.byIcon(Icons.menu_rounded),
        findsOneWidget,
        reason: 'Top-left corner must display the menu button',
      );
      expect(
        find.byIcon(Icons.search_rounded),
        findsOneWidget,
        reason: 'Top-right corner must display the search button',
      );
      expect(
        find.byIcon(Icons.sync_rounded),
        findsNothing,
        reason: 'Floating sync button must be hidden when StorageMode.local is active',
      );
      expect(
        find.byIcon(Icons.settings_outlined),
        findsNothing,
        reason: 'Settings icon must reside inside the top-left menu, not on the landing page header',
      );

      expect(
        find.text("What's up!"),
        findsNothing,
        reason: 'Greeting must be removed from the landing page',
      );
      expect(
        find.byKey(const ValueKey('top_bar_title')),
        findsNothing,
        reason: 'Top bar must not display TierTask or any title when no label filter is selected',
      );
      expect(
        find.text('TierTask'),
        findsNothing,
        reason: 'TierTask must be omitted from the landing page header',
      );
      expect(
        find.textContaining('Olivia'),
        findsNothing,
        reason: 'Greeting must not contain the name Olivia',
      );
      expect(
        find.text('FOCUS TASKS'),
        findsOneWidget,
        reason: 'Focus tasks section must appear on the landing page',
      );
      expect(
        find.text('CATEGORIES'),
        findsNothing,
        reason:
            'Categories section must be hidden when no categories are defined',
      );
      expect(
        find.text('LOCATIONS'),
        findsNothing,
        reason:
            'Locations section must be hidden when no locations are defined',
      );
      expect(
        find.byKey(const ValueKey('accent_bar_category_business')),
        findsNothing,
        reason:
            'No category card accent bar must render when categories are empty',
      );
      expect(
        find.byKey(const ValueKey('accent_bar_location_home')),
        findsNothing,
        reason:
            'No location card accent bar must render when locations are empty',
      );

      final viewportWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final menuButtonRect = tester.getRect(find.byIcon(Icons.menu_rounded));
      final pageViewTop = tester.getTopLeft(find.byType(PageView)).dy;
      final focusFinder = find.text('FOCUS TASKS');
      final focusRect = tester.getRect(focusFinder);
      final focusText = tester.widget<Text>(focusFinder);

      expect(
        focusText.style?.fontSize,
        equals(15),
        reason: 'Focus tasks heading must use the enlarged 15px font size',
      );
      expect(
        focusText.textAlign,
        equals(TextAlign.center),
        reason: 'Focus tasks heading must be center-aligned',
      );
      expect(
        focusRect.center.dx,
        closeTo(viewportWidth / 2.0, 1.0),
        reason: 'Focus tasks heading must be horizontally centered on screen',
      );
      expect(
        focusRect.left > 24.0,
        isTrue,
        reason: 'Centered Focus tasks heading must not be left-aligned at the list padding edge',
      );
      expect(
        focusRect.top - pageViewTop >= 24.0,
        isTrue,
        reason: 'Spacing above Focus tasks heading to the top bar must be increased to at least 24px',
      );
      expect(
        menuButtonRect.bottom <= focusRect.top,
        isTrue,
        reason: 'Top bar must appear above Focus tasks',
      );

      expect(
        find.byKey(const ValueKey('bottom_nav_bar')),
        findsNothing,
        reason: 'Persistent bottom navigation bar must not be rendered',
      );
      expect(
        find.byKey(const ValueKey('quick_add_bar')),
        findsNothing,
        reason: 'QuickAddBar must be hidden until the add button is pressed',
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(
        find.byType(FloatingActionButton),
        findsNothing,
        reason: 'Add button must disappear when QuickAddBar opens',
      );
      expect(
        find.byKey(const ValueKey('quick_add_bar')),
        findsOneWidget,
        reason: 'Clicking the add button must show QuickAddBar at the bottom',
      );

      await tester.enterText(
        find.byKey(const ValueKey('quick_add_input')),
        'Daily meeting with team',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('quick_add_bar')),
        findsNothing,
        reason: 'Submitting a task must close QuickAddBar',
      );
      expect(
        find.byType(FloatingActionButton),
        findsOneWidget,
        reason: 'Closing QuickAddBar must restore the add button',
      );
      expect(
        find.text('Daily meeting with team'),
        findsOneWidget,
        reason: 'Added task must appear in the Focus tasks section on the landing page',
      );
      final firstTaskPillTop = tester
          .getTopLeft(
            find
                .ancestor(
                  of: find.text('Daily meeting with team'),
                  matching: find.byType(Material),
                )
                .first,
          )
          .dy;
      expect(
        firstTaskPillTop - focusRect.bottom,
        equals(36.0),
        reason: 'Spacing below Focus tasks heading to the first task pill must be 36px (1.5x of 24px)',
      );

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      final searchFieldRect = tester.getRect(find.byType(TextField));
      final closeSearchButtonRect = tester.getRect(
        find.byIcon(Icons.close_rounded),
      );

      expect(
        searchFieldRect.left >= menuButtonRect.right - 1.0,
        isTrue,
        reason: 'Search bar must appear to the right of the menu button when no label is selected',
      );
      expect(
        searchFieldRect.right <= closeSearchButtonRect.left + 1.0,
        isTrue,
        reason: 'Search bar must appear to the left of the search/close button',
      );

      await tester.enterText(find.byType(TextField), 'Nonexistent');
      await tester.pumpAndSettle();
      expect(
        find.text('Daily meeting with team'),
        findsNothing,
        reason: 'Search query must filter Focus tasks on the landing page',
      );

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(
        find.text('Daily meeting with team'),
        findsOneWidget,
        reason: 'Closing search must restore all Focus tasks',
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show TDF preview'));
      await tester.pumpAndSettle();

      expect(
        find.text('Raw TDF'),
        findsOneWidget,
        reason: 'English Raw TDF preview dialog must display Raw TDF without Single Source of Truth',
      );
      expect(
        find.textContaining('Single Source of Truth'),
        findsNothing,
        reason: 'English Raw TDF preview dialog must not mention Single Source of Truth',
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Landing page renders German labels, hides empty categories and locations, and exposes German Labels section without tiers in the top-left menu',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(
                const WebDavConfig(language: AppLanguage.german),
              ),
            ),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Was steht an!'), findsNothing);
      expect(find.byKey(const ValueKey('top_bar_title')), findsNothing);
      expect(find.textContaining('Olivia'), findsNothing);
      expect(find.text('FOKUSAUFGABEN'), findsOneWidget);
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

      expect(find.text('Bereit'), findsNothing);
      expect(find.text('Geplant'), findsNothing);
      expect(find.text('Blockiert'), findsNothing);
      expect(find.text('Irgendwann'), findsNothing);
      expect(find.text('Erledigt'), findsNothing);
      expect(find.text('Labels'), findsOneWidget);
      expect(find.text('Bearbeiten'), findsOneWidget);
      expect(find.text('Neues Label erstellen'), findsOneWidget);
      expect(find.text('Einstellungen'), findsOneWidget);

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
    'Sync button floats as a smaller button above the add button only when WebDAV or Both mode is active and hides when QuickAddBar opens',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(
                const WebDavConfig(
                  language: AppLanguage.english,
                  storageMode: StorageMode.local,
                ),
              ),
            ),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );

      await tester.pumpAndSettle();

      final syncFabFinder = find.byKey(const ValueKey('sync_fab'));
      final addFabFinder = find.byKey(const ValueKey('add_task_fab'));

      expect(
        syncFabFinder,
        findsNothing,
        reason: 'Local mode must not display the floating sync button',
      );
      expect(
        find.byIcon(Icons.sync_rounded),
        findsNothing,
        reason: 'Local mode must not display the sync icon anywhere on screen',
      );
      expect(
        addFabFinder,
        findsOneWidget,
        reason: 'Add task button must be visible when QuickAddBar is closed',
      );

      await openSettingsFromMenu(tester);
      await tester.ensureVisible(find.text('WebDAV'));
      await tester.tap(find.text('WebDAV'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(
        syncFabFinder,
        findsOneWidget,
        reason: 'WebDAV mode must display the floating sync button',
      );
      expect(
        find.byIcon(Icons.sync_rounded),
        findsOneWidget,
        reason:
            'WebDAV mode must display the sync icon inside the floating button',
      );

      final searchButtonRect = tester.getRect(
        find.byIcon(Icons.search_rounded),
      );
      final syncRect = tester.getRect(syncFabFinder);
      final addRect = tester.getRect(addFabFinder);

      expect(
        syncRect.top > searchButtonRect.bottom + 40.0,
        isTrue,
        reason: 'Sync button must no longer reside in the top bar',
      );
      expect(
        syncRect.width < addRect.width && syncRect.height < addRect.height,
        isTrue,
        reason: 'Sync button must be smaller than the add task button',
      );
      expect(
        syncRect.bottom <= addRect.top,
        isTrue,
        reason: 'Sync button must float above the add task button',
      );
      final syncMaterialRect = tester.getRect(
        find.descendant(of: syncFabFinder, matching: find.byType(Material)),
      );
      final addMaterialRect = tester.getRect(
        find.descendant(of: addFabFinder, matching: find.byType(Material)),
      );
      expect(
        syncRect.right,
        closeTo(addRect.right, 0.01),
        reason: 'Sync button must be right-aligned with the add task button at the same distance from the right screen edge',
      );
      expect(
        syncMaterialRect.right,
        closeTo(addMaterialRect.right, 0.01),
        reason: 'Visual circle of the sync button must have the exact same right-edge distance as the add task button',
      );
      expect(
        syncRect.left > addRect.left,
        isTrue,
        reason: 'Smaller right-aligned sync button must not be horizontally centered over the add task button',
      );

      await tester.tap(addFabFinder);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('quick_add_bar')),
        findsOneWidget,
        reason: 'Tapping the add button must open QuickAddBar',
      );
      expect(
        addFabFinder,
        findsNothing,
        reason: 'Add button must hide when transformed into QuickAddBar',
      );
      expect(
        syncFabFinder,
        findsNothing,
        reason: 'Sync button must also hide when Add button transforms into QuickAddBar',
      );
      expect(
        find.byIcon(Icons.sync_rounded),
        findsNothing,
        reason: 'Sync icon must not be visible while QuickAddBar is open',
      );

      await tester.tap(find.byKey(const ValueKey('quick_add_cancel_button')));
      await tester.pumpAndSettle();

      expect(
        syncFabFinder,
        findsOneWidget,
        reason: 'Closing QuickAddBar must restore the floating sync button',
      );
      expect(
        addFabFinder,
        findsOneWidget,
        reason: 'Closing QuickAddBar must restore the floating add button',
      );

      await openSettingsFromMenu(tester);
      await tester.ensureVisible(find.text('Both'));
      await tester.tap(find.text('Both'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(
        syncFabFinder,
        findsOneWidget,
        reason: 'Both mode must display the floating sync button above the add button',
      );
      final bothSyncRect = tester.getRect(syncFabFinder);
      final bothAddRect = tester.getRect(addFabFinder);
      expect(
        bothSyncRect.bottom <= bothAddRect.top &&
            bothSyncRect.width < bothAddRect.width &&
            (bothSyncRect.right - bothAddRect.right).abs() < 0.01,
        isTrue,
        reason: 'Both mode must keep the smaller sync button right-aligned above the add button',
      );
    },
  );

  testWidgets(
    'Navigation drawer opens secondary tier sheets for Ready, Planned, Blocked (including suspended), Someday, and Completed without a bottom navigation bar',
    (WidgetTester tester) async {
      const secondaryTiersTdf = '''
tdf 0.2.0

task f1 {
  name "Focus Task 1"
  created 2026-11-01 07:00
  queued 2026-11-01 07:00
}
task f2 {
  name "Focus Task 2"
  created 2026-11-01 07:05
  queued 2026-11-01 07:05
}
task f3 {
  name "Focus Task 3"
  created 2026-11-01 07:10
  queued 2026-11-01 07:10
}
task r1 {
  name "Ready Task 1"
  created 2026-11-01 07:15
  queued 2026-11-01 07:15
}
task r2 {
  name "Ready Task 2"
  created 2026-11-01 07:20
  queued 2026-11-01 07:20
}
task r3 {
  name "Ready Task 3"
  created 2026-11-01 07:25
  queued 2026-11-01 07:25
}
task r4 {
  name "Ready Task 4"
  created 2026-11-01 07:30
  queued 2026-11-01 07:30
}
task r5 {
  name "Ready Task 5"
  created 2026-11-01 07:35
  queued 2026-11-01 07:35
}
task p1 {
  name "Planned Backlog Task"
  created 2026-11-01 07:40
  queued 2026-11-01 07:40
}
task blk_dep {
  name "Blocked Prerequisite Task"
  created 2026-11-01 07:45
  queued 2026-11-01 07:45
  blocked f1
}
task blk_susp {
  name "Suspended Deferred Task"
  created 2026-11-01 07:50
  queued 2026-11-01 07:50
  suspended 2026-11-05 09:00
}
task smd1 {
  name "Someday Idea Task"
  created 2026-11-01 08:00
}
task cmp1 {
  name "Completed Archive Task"
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
                initialTdf: secondaryTiersTdf,
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
          .getTopLeft(find.byKey(const ValueKey('tier_pill_blocked_blk_dep')))
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
        find.byKey(const ValueKey('tier_pill_blocked_blk_dep')),
        findsOneWidget,
        reason: 'Blocked task must render as a dark-blue pill card matching Focus screen',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('edit_task_button_blk_dep')),
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
    'Task pills display identical primaryContainer squares with white circles across all tasks and downgrade via the > button per TDF_SPEC.md Section 6.3',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.2.0

task f1 priority {
  name "Focus 1"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
}
task f2 {
  name "Focus 2"
  created 2026-11-01 08:05
  queued 2026-11-01 08:05
}
task f3 {
  name "Focus 3"
  created 2026-11-01 08:10
  queued 2026-11-01 08:10
}
task r1 {
  name "Ready 1"
  created 2026-11-01 08:15
  queued 2026-11-01 08:15
}
task r2 {
  name "Ready 2"
  created 2026-11-01 08:20
  queued 2026-11-01 08:20
}
task r3 {
  name "Ready 3"
  created 2026-11-01 08:25
  queued 2026-11-01 08:25
}
task r4 {
  name "Ready 4"
  created 2026-11-01 08:30
  queued 2026-11-01 08:30
}
task r5 {
  name "Ready 5"
  created 2026-11-01 09:00:00
  queued 2026-11-01 09:00:00
}
task p1 {
  name "Planned 1"
  created 2026-11-01 09:00:01
  queued 2026-11-01 09:00:01
}
''';
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const WebDavConfig(language: AppLanguage.english),
            ),
          ),
          localFileRepositoryProvider.overrideWith(
            (ref) => FakeLocalFileRepository(
              config: const WebDavConfig(language: AppLanguage.english),
              initialTdf: seededTdf,
            ),
          ),
          clockProvider.overrideWithValue(
            () => DateTime.utc(2026, 11, 1, 12, 0),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();

      final theme = Theme.of(
        tester.element(find.byKey(const ValueKey('tier_pill_focus_f1'))),
      );
      for (final taskId in ['f1', 'f2', 'f3']) {
        final squareContainers = tester
            .widgetList<Container>(
              find.descendant(
                of: find.byKey(ValueKey('complete_task_button_$taskId')),
                matching: find.byType(Container),
              ),
            )
            .toList();
        final outerDecoration =
            squareContainers.first.decoration as BoxDecoration?;
        final innerDecoration =
            squareContainers.last.decoration as BoxDecoration?;
        expect(
          outerDecoration?.color,
          equals(theme.colorScheme.primaryContainer),
          reason:
              'Every task ($taskId) must display the identical M3 primaryContainer square without even/odd distinction',
        );
        expect(
          innerDecoration?.border?.top.color,
          equals(Colors.white),
          reason:
              'Every task ($taskId) must display a white circle inside the square',
        );
      }

      await tester.tap(find.byKey(const ValueKey('downgrade_task_button_f1')));
      await tester.pumpAndSettle();

      var board = container.read(taskNotifierProvider).value!;
      expect(
        board.focus.map((task) => task.id),
        equals(['f2', 'f3', 'r1']),
        reason: 'Downgrading f1 from Focus must advance r1 into Focus',
      );
      expect(
        board.ready.map((task) => task.id),
        equals(['r2', 'r3', 'r4', 'r5', 'f1']),
        reason: 'Downgraded Focus task f1 must land at the end of Ready (slot 8) ahead of Planned 1',
      );
      expect(
        board.planned.map((task) => task.id),
        equals(['p1']),
        reason: 'Colliding Planned task p1 must remain in Planned with shifted timestamp',
      );
      expect(
        board.findTask('f1')?.queuedAt,
        equals(DateTime.utc(2026, 11, 1, 9, 0, 1)),
      );
      expect(
        board.findTask('p1')?.queuedAt,
        equals(DateTime.utc(2026, 11, 1, 9, 0, 2)),
      );

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('downgrade_task_button_r2')));
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(
        board.ready.map((task) => task.id),
        equals(['r3', 'r4', 'r5', 'f1', 'p1']),
        reason: 'Downgrading r2 from Ready must pull p1 into Ready',
      );
      expect(
        board.planned.map((task) => task.id),
        equals(['r2']),
        reason: 'Downgraded Ready task r2 must move to the end of Planned',
      );

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('downgrade_task_button_r2')),
        findsOneWidget,
        reason: 'Planned task pill must display the downward arrow downgrade button',
      );
      await tester.tap(find.byKey(const ValueKey('downgrade_task_button_r2')));
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(
        board.planned,
        isEmpty,
        reason: 'Downgrading r2 from Planned must remove it from Planned',
      );
      expect(
        board.someday.map((task) => task.id),
        equals(['r2']),
        reason:
            'Downgraded Planned task r2 must move to Someday per Section 6.3',
      );
      expect(
        board.findTask('r2')?.queuedAt,
        isNull,
        reason: 'Downgraded Planned task r2 must omit queued per Section 6.3',
      );
      expect(
        board.findTask('r2')?.isPriority,
        isFalse,
        reason:
            'Downgraded Planned task r2 must remove priority per Section 6.3',
      );

      await tester.tap(
        find.byKey(const ValueKey('tier_indicator_item_someday')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('downgrade_task_button_r2')),
        findsNothing,
        reason: 'Someday task pill must not display a downgrade button',
      );
    },
  );
}
