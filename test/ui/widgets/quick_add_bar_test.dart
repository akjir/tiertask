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
        equals(const Color(0xFF9BA8E5)),
        reason: 'Priority icon must be muted when unselected',
      );
      expect(
        tester.widget<Icon>(somedayIconFinder).color,
        equals(const Color(0xFF9BA8E5)),
        reason: 'Someday icon must be muted when unselected',
      );

      await tester.tap(priorityFinder);
      await tester.pump();
      expect(
        tester.widget<Icon>(priorityIconFinder).color,
        equals(const Color(0xFFEB06FF)),
        reason: 'Tapping Priority must highlight the Priority button',
      );
      expect(
        tester.widget<Icon>(somedayIconFinder).color,
        equals(const Color(0xFF9BA8E5)),
        reason: 'Someday must remain unselected when Priority is active',
      );

      await tester.tap(somedayFinder);
      await tester.pump();
      expect(
        tester.widget<Icon>(somedayIconFinder).color,
        equals(const Color(0xFF2196F3)),
        reason: 'Tapping Someday must highlight the Someday button',
      );
      expect(
        tester.widget<Icon>(priorityIconFinder).color,
        equals(const Color(0xFF9BA8E5)),
        reason: 'Enabling Someday must automatically turn off Priority',
      );

      await tester.tap(advancedFinder);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('task_editor_dialog')),
        findsOneWidget,
        reason: 'Advanced button must open the shared TaskEditorDialog in extended creation mode',
      );
      await tester.tap(find.byKey(const ValueKey('task_editor_cancel_button')));
      await tester.pumpAndSettle();
      expect(
        barFinder,
        findsOneWidget,
        reason:
            'QuickAddBar must remain open after cancelling TaskEditorDialog',
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
tdf 0.2.0

label home {
  name "Home"
  color "#00E5FF"
}
label office {
  name "Office"
  color "#FF9100"
}
label c_it {
  name "IT"
  color "#2196F3"
}
label c_ops {
  name "Operations"
  color "#EB06FF"
}
label c_hr {
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
      final labelsButton = find.byKey(
        const ValueKey('quick_add_labels_button'),
      );
      final labelsMenu = find.byKey(const ValueKey('quick_add_labels_menu'));

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
        const ValueKey('quick_add_label_home'),
      );
      final labelOfficeOption = find.byKey(
        const ValueKey('quick_add_label_office'),
      );
      final labelItOption = find.byKey(const ValueKey('quick_add_label_c_it'));
      final labelOpsOption = find.byKey(
        const ValueKey('quick_add_label_c_ops'),
      );
      final labelHrOption = find.byKey(const ValueKey('quick_add_label_c_hr'));
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

      await tester.tap(find.text("What's up!"));
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
        equals(['home', 'c_it', 'c_ops']),
        reason: 'Created task must store all selected labels in board declaration order',
      );
    },
  );
}
