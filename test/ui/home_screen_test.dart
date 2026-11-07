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
import 'package:tiertask/repositories/app_version_repository.dart';
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

      expect(
        find.text('ALL TASKS'),
        findsOneWidget,
        reason:
            'Opening search must display ALL TASKS where FOCUS TASKS was shown',
      );
      expect(
        find.text('FOCUS TASKS'),
        findsNothing,
        reason: 'FOCUS TASKS heading must be replaced by ALL TASKS in search',
      );

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
        reason: 'Search query must filter tasks on the All Tasks search screen',
      );

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(
        find.text('FOCUS TASKS'),
        findsOneWidget,
        reason: 'Closing search must restore the FOCUS TASKS heading',
      );
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
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      expect(
        find.text('ALLE AUFGABEN'),
        findsOneWidget,
        reason: 'German search screen must display ALLE AUFGABEN',
      );
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
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
    'Task pills display identical primaryContainer squares with white circles across all tasks and downgrade via the > button per TDF_SPEC.md Section 6.3',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 09:00:01
  task f10000OkD2
  task f20000OkD2
  task f30000OkD2
  task r10000OkD2
  task r20000OkD2
  task r30000OkD2
  task r40000OkD2
  task r50000OkD2
  task p10000OkD2
}

task f10000OkD2 priority {
  name "Focus 1"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
}
task f20000OkD2 {
  name "Focus 2"
  created 2026-11-01 08:05
  queued 2026-11-01 08:05
}
task f30000OkD2 {
  name "Focus 3"
  created 2026-11-01 08:10
  queued 2026-11-01 08:10
}
task r10000OkD2 {
  name "Ready 1"
  created 2026-11-01 08:15
  queued 2026-11-01 08:15
}
task r20000OkD2 {
  name "Ready 2"
  created 2026-11-01 08:20
  queued 2026-11-01 08:20
}
task r30000OkD2 {
  name "Ready 3"
  created 2026-11-01 08:25
  queued 2026-11-01 08:25
}
task r40000OkD2 {
  name "Ready 4"
  created 2026-11-01 08:30
  queued 2026-11-01 08:30
}
task r50000OkD2 {
  name "Ready 5"
  created 2026-11-01 09:00:00
  queued 2026-11-01 09:00:00
}
task p10000OkD2 {
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
        tester.element(
          find.byKey(const ValueKey('tier_pill_focus_f10000OkD2')),
        ),
      );
      for (final taskId in ['f10000OkD2', 'f20000OkD2', 'f30000OkD2']) {
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

      await tester.tap(
        find.byKey(const ValueKey('downgrade_task_button_f10000OkD2')),
      );
      await tester.pumpAndSettle();

      var board = container.read(taskNotifierProvider).value!;
      expect(
        board.focus.map((task) => task.id),
        equals(['f20000OkD2', 'f30000OkD2', 'r10000OkD2']),
        reason: 'Downgrading f1 from Focus must advance r1 into Focus',
      );
      expect(
        board.ready.map((task) => task.id),
        equals([
          'r20000OkD2',
          'r30000OkD2',
          'r40000OkD2',
          'r50000OkD2',
          'f10000OkD2',
        ]),
        reason: 'Downgraded Focus task f1 must land at the end of Ready (slot 8) ahead of Planned 1',
      );
      expect(
        board.planned.map((task) => task.id),
        equals(['p10000OkD2']),
        reason: 'Colliding Planned task p1 must remain in Planned',
      );
      expect(
        board.queueBlock.taskIds.indexOf('f10000OkD2'),
        equals(board.queueBlock.taskIds.indexOf('r50000OkD2') + 1),
      );

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('downgrade_task_button_r20000OkD2')),
      );
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(
        board.ready.map((task) => task.id),
        equals([
          'r30000OkD2',
          'r40000OkD2',
          'r50000OkD2',
          'f10000OkD2',
          'p10000OkD2',
        ]),
        reason: 'Downgrading r2 from Ready must pull p1 into Ready',
      );
      expect(
        board.planned.map((task) => task.id),
        equals(['r20000OkD2']),
        reason: 'Downgraded Ready task r2 must move to the end of Planned',
      );

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('downgrade_task_button_r20000OkD2')),
        findsOneWidget,
        reason: 'Planned task pill must display the downward arrow downgrade button',
      );
      await tester.tap(
        find.byKey(const ValueKey('downgrade_task_button_r20000OkD2')),
      );
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(
        board.planned,
        isEmpty,
        reason: 'Downgrading r2 from Planned must remove it from Planned',
      );
      expect(
        board.someday.map((task) => task.id),
        equals(['r20000OkD2']),
        reason:
            'Downgraded Planned task r2 must move to Someday per Section 6.3',
      );
      expect(
        board.queueTaskIds.contains('r20000OkD2'),
        isFalse,
        reason: 'Downgraded Planned task r2 must be removed from queue per Section 6.3',
      );
      expect(
        board.findTask('r20000OkD2')?.isPriority,
        isFalse,
        reason:
            'Downgraded Planned task r2 must remove priority per Section 6.3',
      );

      await tester.tap(
        find.byKey(const ValueKey('tier_indicator_item_someday')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('downgrade_task_button_r20000OkD2')),
        findsNothing,
        reason: 'Someday task pill must not display a downgrade button',
      );
    },
  );

  testWidgets(
    'Search view displays ALL TASKS, orders all tasks from Focus through Completed, applies active label filter, and restores the previous tier screen on close',
    (WidgetTester tester) async {
      const searchTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 07:45:00
  task f10000OkD2
  task f20000OkD2
  task f30000OkD2
  task r10000OkD2
  task r20000OkD2
  task r30000OkD2
  task r40000OkD2
  task r50000OkD2
  task p10000OkD2
  task b10000OkD2
}

label work00OkD2 {
  name "Work"
}
label home00OkD2 {
  name "Home"
}
task f10000OkD2 {
  name "Alpha Focus Match"
  created 2026-11-01 07:00
  queued 2026-11-01 07:00
  labels work00OkD2
}
task f20000OkD2 {
  name "Focus Two"
  created 2026-11-01 07:05
  queued 2026-11-01 07:05
  labels home00OkD2
}
task f30000OkD2 {
  name "Focus Three"
  created 2026-11-01 07:10
  queued 2026-11-01 07:10
  labels home00OkD2
}
task r10000OkD2 {
  name "Bravo Ready Match"
  created 2026-11-01 07:15
  queued 2026-11-01 07:15
  labels work00OkD2
}
task r20000OkD2 {
  name "Ready Two"
  created 2026-11-01 07:20
  queued 2026-11-01 07:20
  labels home00OkD2
}
task r30000OkD2 {
  name "Ready Three"
  created 2026-11-01 07:25
  queued 2026-11-01 07:25
  labels home00OkD2
}
task r40000OkD2 {
  name "Ready Four"
  created 2026-11-01 07:30
  queued 2026-11-01 07:30
  labels home00OkD2
}
task r50000OkD2 {
  name "Ready Five"
  created 2026-11-01 07:35
  queued 2026-11-01 07:35
  labels home00OkD2
}
task p10000OkD2 {
  name "Charlie Planned Match"
  created 2026-11-01 07:40
  queued 2026-11-01 07:40
  labels work00OkD2
}
task b10000OkD2 {
  name "Delta Blocked Match"
  created 2026-11-01 07:45
  queued 2026-11-01 07:45
  suspended 2026-11-05 09:00
  labels home00OkD2
}
task s10000OkD2 {
  name "Echo Someday Match"
  created 2026-11-01 07:50
  labels work00OkD2
}
task c10000OkD2 {
  name "Foxtrot Completed Match"
  created 2026-10-28 08:00
  queued 2026-10-28 08:00
  finished 2026-10-29 10:00
  completions 1
  labels work00OkD2
}
task c20000OkD2 {
  name "Home Completed Only"
  created 2026-10-28 09:00
  queued 2026-10-28 09:00
  finished 2026-10-29 11:00
  completions 1
  labels home00OkD2
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
                initialTdf: searchTdf,
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

      await tester.tap(
        find.byKey(const ValueKey('tier_indicator_item_blocked')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('BLOCKED TASKS'),
        findsOneWidget,
        reason: 'Must navigate to Blocked screen before opening search',
      );

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      expect(
        find.text('ALL TASKS'),
        findsOneWidget,
        reason: 'Search screen must display ALL TASKS as section heading',
      );
      expect(
        find.text('BLOCKED TASKS'),
        findsNothing,
        reason: 'Previous tier heading must be replaced while searching',
      );

      await tester.enterText(find.byType(TextField), 'Match');
      await tester.pumpAndSettle();

      final focusY = tester.getTopLeft(find.text('Alpha Focus Match')).dy;
      final readyY = tester.getTopLeft(find.text('Bravo Ready Match')).dy;
      final plannedY = tester.getTopLeft(find.text('Charlie Planned Match')).dy;
      final blockedY = tester.getTopLeft(find.text('Delta Blocked Match')).dy;
      final somedayY = tester.getTopLeft(find.text('Echo Someday Match')).dy;
      final completedY = tester
          .getTopLeft(find.text('Foxtrot Completed Match'))
          .dy;

      expect(
        focusY < readyY &&
            readyY < plannedY &&
            plannedY < blockedY &&
            blockedY < somedayY &&
            somedayY < completedY,
        isTrue,
        reason: 'Filtered tasks in search view must be ordered: Focus, Ready, Planned, Blocked, Someday, Completed',
      );
      expect(
        find.text('Focus Two'),
        findsNothing,
        reason: 'Non-matching tasks must be filtered out',
      );

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(
        find.text('BLOCKED TASKS'),
        findsOneWidget,
        reason: 'Closing search must return to the previous Blocked screen',
      );
      expect(
        find.text('Delta Blocked Match'),
        findsOneWidget,
        reason:
            'Blocked task must be visible after returning to Blocked screen',
      );
      expect(
        find.text('ALL TASKS'),
        findsNothing,
        reason: 'ALL TASKS heading must disappear when search closes',
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('drawer_label_tile_work00OkD2')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('tier_indicator_item_planned')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('PLANNED TASKS'),
        findsOneWidget,
        reason:
            'Must be on Planned screen before opening label-filtered search',
      );

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      expect(
        find.text('ALL TASKS'),
        findsOneWidget,
        reason: 'Label-filtered search must still display ALL TASKS heading',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('top_bar_title')),
          matching: find.text('Work'),
        ),
        findsOneWidget,
        reason: 'Selected Work label title must remain visible in the top bar',
      );
      expect(
        find.text('Alpha Focus Match'),
        findsOneWidget,
        reason: 'Work label task in Focus must appear in search',
      );
      expect(
        find.text('Bravo Ready Match'),
        findsOneWidget,
        reason: 'Work label task in Ready/Focus context must appear in search',
      );
      expect(
        find.text('Charlie Planned Match'),
        findsOneWidget,
        reason:
            'Work label task in Planned/Focus context must appear in search',
      );
      expect(
        find.text('Echo Someday Match'),
        findsOneWidget,
        reason: 'Work label task in Someday must appear in search',
      );
      expect(
        find.text('Foxtrot Completed Match'),
        findsOneWidget,
        reason: 'Completed task with Work label must appear in search',
      );
      expect(
        find.text('Focus Two'),
        findsNothing,
        reason:
            'Home-only open task must be excluded when Work label is active',
      );
      expect(
        find.text('Delta Blocked Match'),
        findsNothing,
        reason:
            'Home-only blocked task must be excluded when Work label is active',
      );
      expect(
        find.text('Home Completed Only'),
        findsNothing,
        reason: 'Home-only completed task must be excluded when Work label is active',
      );

      final workAlphaY = tester.getTopLeft(find.text('Alpha Focus Match')).dy;
      final workBravoY = tester.getTopLeft(find.text('Bravo Ready Match')).dy;
      final workCharlieY = tester
          .getTopLeft(find.text('Charlie Planned Match'))
          .dy;
      final workEchoY = tester.getTopLeft(find.text('Echo Someday Match')).dy;
      final workFoxtrotY = tester
          .getTopLeft(find.text('Foxtrot Completed Match'))
          .dy;

      expect(
        workAlphaY < workBravoY &&
            workBravoY < workCharlieY &&
            workCharlieY < workEchoY &&
            workEchoY < workFoxtrotY,
        isTrue,
        reason: 'Label-filtered search tasks must maintain tier order through Completed',
      );

      await tester.enterText(find.byType(TextField), 'Foxtrot');
      await tester.pumpAndSettle();
      expect(
        find.text('Foxtrot Completed Match'),
        findsOneWidget,
        reason:
            'Search query must match completed tasks within the active label',
      );
      expect(
        find.text('Alpha Focus Match'),
        findsNothing,
        reason: 'Non-matching tasks in the active label must be filtered out',
      );

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(
        find.text('PLANNED TASKS'),
        findsOneWidget,
        reason: 'Closing search must return to the Planned screen',
      );
    },
  );

  testWidgets(
    'Navigation drawer displays version and build metadata anchored at the bottom of the sidepanel',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appVersionRepositoryProvider.overrideWithValue(
              const FakeAppVersionRepository(version: 'v0.1.0+55.e64e6a5.dev'),
            ),
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
}
