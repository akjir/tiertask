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
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'Clicking the add button replaces it with the inline QuickAddBar containing input, Priority, Someday, Labels, Advanced, and Cancel buttons',
    (WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const WebDavConfig(language: AppLanguage.english),
            ),
          ),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
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

      expect(
        find.byKey(const ValueKey('bottom_nav_bar')),
        findsNothing,
        reason: 'Old bottom navigation bar must be removed',
      );
      expect(
        find.byType(FloatingActionButton),
        findsOneWidget,
        reason: 'Only the circular add button must be visible initially',
      );
      expect(
        find.byKey(const ValueKey('quick_add_bar')),
        findsNothing,
        reason: 'QuickAddBar must be hidden initially',
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(
        find.byType(FloatingActionButton),
        findsNothing,
        reason: 'Add button must disappear when clicked',
      );

      final barFinder = find.byKey(const ValueKey('quick_add_bar'));
      final inputFinder = find.byKey(const ValueKey('quick_add_input'));
      final priorityFinder = find.byKey(
        const ValueKey('quick_add_priority_button'),
      );
      final somedayFinder = find.byKey(
        const ValueKey('quick_add_someday_button'),
      );
      final labelsFinder = find.byKey(
        const ValueKey('quick_add_labels_button'),
      );
      final advancedFinder = find.byKey(
        const ValueKey('quick_add_advanced_button'),
      );
      final cancelFinder = find.byKey(
        const ValueKey('quick_add_cancel_button'),
      );

      expect(barFinder, findsOneWidget);
      expect(inputFinder, findsOneWidget);
      expect(priorityFinder, findsOneWidget);
      expect(somedayFinder, findsOneWidget);
      expect(labelsFinder, findsOneWidget);
      expect(advancedFinder, findsOneWidget);
      expect(cancelFinder, findsOneWidget);

      final inputDx = tester.getTopLeft(inputFinder).dx;
      final priorityDx = tester.getTopLeft(priorityFinder).dx;
      final somedayDx = tester.getTopLeft(somedayFinder).dx;
      final labelsDx = tester.getTopLeft(labelsFinder).dx;
      final advancedDx = tester.getTopLeft(advancedFinder).dx;
      final cancelDx = tester.getTopLeft(cancelFinder).dx;

      expect(
        inputDx < priorityDx &&
            priorityDx < somedayDx &&
            somedayDx < labelsDx &&
            labelsDx < advancedDx &&
            advancedDx < cancelDx,
        isTrue,
        reason: 'QuickAddBar items must be ordered left-to-right: input, priority, someday, labels, advanced, cancel',
      );

      final barTheme = Theme.of(tester.element(barFinder));
      final priorityIconFinder = find.descendant(
        of: priorityFinder,
        matching: find.byType(Icon),
      );
      final somedayIconFinder = find.descendant(
        of: somedayFinder,
        matching: find.byType(Icon),
      );
      expect(
        tester.widget<Icon>(priorityIconFinder).color,
        equals(barTheme.colorScheme.onSurfaceVariant),
        reason: 'Priority icon must be muted when unselected',
      );
      expect(
        tester.widget<Icon>(somedayIconFinder).color,
        equals(barTheme.colorScheme.onSurfaceVariant),
        reason: 'Someday icon must be muted when unselected',
      );

      await tester.tap(priorityFinder);
      await tester.pump();
      expect(
        tester.widget<Icon>(priorityIconFinder).color,
        equals(barTheme.colorScheme.primary),
        reason: 'Tapping Priority must highlight the Priority button',
      );
      expect(
        tester.widget<Icon>(somedayIconFinder).color,
        equals(barTheme.colorScheme.onSurfaceVariant),
        reason: 'Someday must remain unselected when Priority is active',
      );

      await tester.tap(somedayFinder);
      await tester.pump();
      expect(
        tester.widget<Icon>(somedayIconFinder).color,
        equals(barTheme.colorScheme.secondary),
        reason: 'Tapping Someday must highlight the Someday button',
      );
      expect(
        tester.widget<Icon>(priorityIconFinder).color,
        equals(barTheme.colorScheme.onSurfaceVariant),
        reason: 'Enabling Someday must automatically turn off Priority',
      );

      await tester.tap(advancedFinder);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('edit_task_screen')),
        findsOneWidget,
        reason: 'Advanced button must open the shared EditTaskScreen panel in extended creation mode',
      );
      await tester.tap(find.byKey(const ValueKey('task_editor_cancel_button')));
      await tester.pumpAndSettle();
      expect(
        barFinder,
        findsOneWidget,
        reason: 'QuickAddBar must remain open after cancelling EditTaskScreen',
      );

      await tester.enterText(inputFinder, 'Draft to cancel');
      await tester.pump();
      await tester.tap(cancelFinder);
      await tester.pumpAndSettle();

      expect(
        barFinder,
        findsNothing,
        reason: 'Tapping Cancel must close QuickAddBar',
      );
      expect(
        find.byType(FloatingActionButton),
        findsOneWidget,
        reason: 'Tapping Cancel must restore the add button',
      );
      expect(
        container.read(taskNotifierProvider).value!.focus,
        isEmpty,
        reason: 'Cancelling must not add a task',
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(somedayFinder);
      await tester.pump();
      await tester.enterText(inputFinder, 'Future idea');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('quick_add_submit_button')));
      await tester.pumpAndSettle();

      expect(
        barFinder,
        findsNothing,
        reason: 'Submitting a task must close QuickAddBar',
      );
      expect(
        find.byType(FloatingActionButton),
        findsOneWidget,
        reason: 'Submitting a task must restore the add button',
      );

      final boardAfterSomeday = container.read(taskNotifierProvider).value!;
      expect(
        boardAfterSomeday.someday.map((task) => task.title),
        equals(['Future idea']),
        reason: 'Submitting with Someday active must add task to Someday tier',
      );
      expect(boardAfterSomeday.focus, isEmpty);
    },
  );

  testWidgets(
    'QuickAddBar Labels button expands upward menu to select multiple labels',
    (WidgetTester tester) async {
      const seededLabelsTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 00:00:00
}

label home00OkD2 {
  name "Home"
  color "#00E5FF"
}
label officeOkD2 {
  name "Office"
  color "#FF9100"
}
label cit000OkD2 {
  name "IT"
  color "#2196F3"
}
label cops00OkD2 {
  name "Operations"
  color "#EB06FF"
}
label chr000OkD2 {
  name "HR"
  color "#4CAF50"
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
              initialTdf: seededLabelsTdf,
            ),
          ),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
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

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final barFinder = find.byKey(const ValueKey('quick_add_bar'));
      final indicatorFinder = find.byKey(const ValueKey('tier_page_indicator'));
      final labelsButton = find.byKey(
        const ValueKey('quick_add_labels_button'),
      );
      final labelsMenu = find.byKey(const ValueKey('quick_add_labels_menu'));
      final indicatorRectBefore = tester.getRect(indicatorFinder);
      final barRectBefore = tester.getRect(barFinder);

      expect(
        labelsMenu,
        findsNothing,
        reason: 'Labels upward menu must be closed initially',
      );

      await tester.tap(labelsButton);
      await tester.pumpAndSettle();

      expect(
        labelsMenu,
        findsOneWidget,
        reason: 'Tapping Labels button must expand the labels menu upward',
      );
      expect(
        tester.getRect(indicatorFinder),
        equals(indicatorRectBefore),
        reason:
            'Opening the Labels popup must not push TierPageIndicator upward',
      );
      expect(
        tester.getRect(barFinder),
        equals(barRectBefore),
        reason: 'Opening the Labels popup must not shift QuickAddBar',
      );
      expect(
        tester.getBottomLeft(labelsMenu).dy <=
            tester.getTopLeft(barFinder).dy + 4.0,
        isTrue,
        reason: 'Labels menu must expand upward above QuickAddBar',
      );
      expect(
        tester.widget<Material>(labelsMenu).clipBehavior,
        equals(Clip.antiAlias),
        reason: 'Labels menu Material must clip ink highlights to its rounded border',
      );

      final labelHomeOption = find.byKey(
        const ValueKey('quick_add_label_home00OkD2'),
      );
      final labelOfficeOption = find.byKey(
        const ValueKey('quick_add_label_officeOkD2'),
      );
      final labelItOption = find.byKey(
        const ValueKey('quick_add_label_cit000OkD2'),
      );
      final labelOpsOption = find.byKey(
        const ValueKey('quick_add_label_cops00OkD2'),
      );
      final labelHrOption = find.byKey(
        const ValueKey('quick_add_label_chr000OkD2'),
      );
      expect(labelHomeOption, findsOneWidget);
      expect(labelOfficeOption, findsOneWidget);
      expect(labelItOption, findsOneWidget);
      expect(labelOpsOption, findsOneWidget);
      expect(labelHrOption, findsOneWidget);

      final labelItInkWell = tester.widget<InkWell>(
        find.descendant(of: labelItOption, matching: find.byType(InkWell)),
      );
      expect(
        labelItInkWell.borderRadius,
        isNotNull,
        reason: 'Label option InkWell must define a borderRadius so press/focus highlight does not overlap rounded corners',
      );

      await tester.tap(labelItOption);
      await tester.pump();
      await tester.tap(labelOpsOption);
      await tester.pump();
      await tester.tap(labelHomeOption);
      await tester.pump();

      await tester.tap(find.text('FOCUS TASKS'));
      await tester.pumpAndSettle();
      expect(
        labelsMenu,
        findsNothing,
        reason: 'Tapping outside the Labels menu must close it',
      );

      await tester.enterText(
        find.byKey(const ValueKey('quick_add_input')),
        'Audit hybrid network',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('quick_add_submit_button')));
      await tester.pumpAndSettle();

      final board = container.read(taskNotifierProvider).value!;
      expect(board.focus.length, equals(1));
      final createdTask = board.focus.single;
      expect(createdTask.title, equals('Audit hybrid network'));
      expect(
        createdTask.labelIds,
        equals(['home00OkD2', 'cit000OkD2', 'cops00OkD2']),
        reason: 'Created task must store all selected labels in board declaration order',
      );
    },
  );

  testWidgets(
    'QuickAddBar stacks input above action buttons at Pixel 9 Pro width and when window width drops below threshold',
    (WidgetTester tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Pixel 9 Pro physical resolution (1280x2856) at 3.0x density (426.67x952 dp).
      tester.view.physicalSize = const Size(1280, 2856);
      tester.view.devicePixelRatio = 3.0;

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const WebDavConfig(language: AppLanguage.english),
            ),
          ),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
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

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final inputFinder = find.byKey(const ValueKey('quick_add_input'));
      final priorityFinder = find.byKey(
        const ValueKey('quick_add_priority_button'),
      );
      final somedayFinder = find.byKey(
        const ValueKey('quick_add_someday_button'),
      );
      final labelsFinder = find.byKey(
        const ValueKey('quick_add_labels_button'),
      );
      final advancedFinder = find.byKey(
        const ValueKey('quick_add_advanced_button'),
      );
      final cancelFinder = find.byKey(
        const ValueKey('quick_add_cancel_button'),
      );

      expect(
        tester.getBottomLeft(inputFinder).dy <=
            tester.getTopLeft(priorityFinder).dy,
        isTrue,
        reason: 'At Pixel 9 Pro viewport width, input must be positioned above the action buttons',
      );
      expect(
        tester.getTopLeft(priorityFinder).dx <
                tester.getTopLeft(somedayFinder).dx &&
            tester.getTopLeft(somedayFinder).dx <
                tester.getTopLeft(labelsFinder).dx &&
            tester.getTopLeft(labelsFinder).dx <
                tester.getTopLeft(advancedFinder).dx &&
            tester.getTopLeft(advancedFinder).dx <
                tester.getTopLeft(cancelFinder).dx,
        isTrue,
        reason: 'Action buttons must remain ordered left-to-right on the bottom row',
      );

      // Resize to a wide desktop window (1280x720 at 1.0x): input must sit beside buttons.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 720);
      await tester.pumpAndSettle();

      expect(
        tester.getTopRight(inputFinder).dx <=
            tester.getTopLeft(priorityFinder).dx,
        isTrue,
        reason: 'In a wide desktop window, input must sit to the left of the action buttons',
      );
      expect(
        (tester.getCenter(inputFinder).dy - tester.getCenter(priorityFinder).dy)
            .abs(),
        lessThan(8.0),
        reason: 'In a wide desktop window, input and buttons must share the same row',
      );

      // Narrow the desktop window below the Pixel 9 Pro width threshold (320x720): input must stack above buttons.
      tester.view.physicalSize = const Size(320, 720);
      await tester.pumpAndSettle();

      expect(
        tester.getBottomLeft(inputFinder).dy <=
            tester.getTopLeft(priorityFinder).dy,
        isTrue,
        reason: 'When window width drops below the Pixel 9 Pro threshold, input must automatically stack above the buttons',
      );
    },
  );
}
