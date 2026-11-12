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

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';

import 'test_helpers.dart';

/// [FakeWebDavRepository] subclass that counts remote fetch invocations.
class _CountingFakeWebDavRepository extends FakeWebDavRepository {
  /// Creates a [_CountingFakeWebDavRepository].
  _CountingFakeWebDavRepository({
    required super.config,
    required super.remoteStore,
    required this.onFetch,
  }) : super(shouldFail: () => false);

  /// Callback invoked on every [fetchTdf] call.
  final VoidCallback onFetch;

  @override
  Future<String> fetchTdf() async {
    onFetch();
    return super.fetchTdf();
  }
}

void main() {
  testWidgets(
    'Landing page hides categories and locations when none exist and renders greeting, focus tasks, top-right search, and top-left menu',
    (WidgetTester tester) async {
      await _pumpHomeApp(tester);

      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.byIcon(Icons.sync_rounded), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.text("What's up!"), findsNothing);
      expect(find.byKey(const ValueKey('top_bar_title')), findsNothing);
      expect(find.text('TierTask'), findsNothing);
      expect(find.textContaining('Olivia'), findsNothing);
      expect(find.text('FOCUS TASKS'), findsOneWidget);
      expect(find.text('CATEGORIES'), findsNothing);
      expect(find.text('LOCATIONS'), findsNothing);
      expect(
        find.byKey(const ValueKey('accent_bar_category_business')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('accent_bar_location_home')),
        findsNothing,
      );

      final viewportWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final menuButtonRect = tester.getRect(find.byIcon(Icons.menu_rounded));
      final pageViewTop = tester.getTopLeft(find.byType(PageView)).dy;
      final focusFinder = find.text('FOCUS TASKS');
      final focusRect = tester.getRect(focusFinder);
      final focusText = tester.widget<Text>(focusFinder);

      expect(focusText.style?.fontSize, equals(15));
      expect(focusText.textAlign, equals(TextAlign.center));
      expect(focusRect.center.dx, closeTo(viewportWidth / 2.0, 1.0));
      expect(focusRect.left > 24.0, isTrue);
      expect(focusRect.top - pageViewTop >= 24.0, isTrue);
      expect(menuButtonRect.bottom <= focusRect.top, isTrue);
      expect(find.byKey(const ValueKey('bottom_nav_bar')), findsNothing);
      expect(find.byKey(const ValueKey('quick_add_bar')), findsNothing);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byKey(const ValueKey('quick_add_bar')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('quick_add_input')),
        'Daily meeting with team',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('quick_add_bar')), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Daily meeting with team'), findsOneWidget);
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
      expect(firstTaskPillTop - focusRect.bottom, equals(36.0));

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      expect(find.text('ALL TASKS'), findsOneWidget);
      expect(find.text('FOCUS TASKS'), findsNothing);

      final searchFieldRect = tester.getRect(find.byType(TextField));
      final closeSearchButtonRect = tester.getRect(
        find.byIcon(Icons.close_rounded),
      );
      expect(searchFieldRect.left >= menuButtonRect.right - 1.0, isTrue);
      expect(searchFieldRect.right <= closeSearchButtonRect.left + 1.0, isTrue);

      await tester.enterText(find.byType(TextField), 'Nonexistent');
      await tester.pumpAndSettle();
      expect(find.text('Daily meeting with team'), findsNothing);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('FOCUS TASKS'), findsOneWidget);
      expect(find.text('Daily meeting with team'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show TDF preview'));
      await tester.pumpAndSettle();

      expect(find.text('Raw TDF'), findsOneWidget);
      expect(find.textContaining('Single Source of Truth'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Sync button floats as a smaller button above the add button only when WebDAV or Both mode is active and hides when QuickAddBar opens',
    (WidgetTester tester) async {
      await _pumpHomeApp(tester);

      final syncFabFinder = find.byKey(const ValueKey('sync_fab'));
      final addFabFinder = find.byKey(const ValueKey('add_task_fab'));

      expect(syncFabFinder, findsNothing);
      expect(find.byIcon(Icons.sync_rounded), findsNothing);
      expect(addFabFinder, findsOneWidget);

      await _selectStorageModeAndReturn(tester, 'WebDAV');

      expect(syncFabFinder, findsOneWidget);
      expect(find.byIcon(Icons.sync_rounded), findsOneWidget);

      final searchButtonRect = tester.getRect(
        find.byIcon(Icons.search_rounded),
      );
      final syncRect = tester.getRect(syncFabFinder);
      final addRect = tester.getRect(addFabFinder);

      expect(syncRect.top > searchButtonRect.bottom + 40.0, isTrue);
      expect(
        syncRect.width < addRect.width && syncRect.height < addRect.height,
        isTrue,
      );
      expect(syncRect.bottom <= addRect.top, isTrue);
      final syncMaterialRect = tester.getRect(
        find.descendant(of: syncFabFinder, matching: find.byType(Material)),
      );
      final addMaterialRect = tester.getRect(
        find.descendant(of: addFabFinder, matching: find.byType(Material)),
      );
      expect(syncRect.right, closeTo(addRect.right, 0.01));
      expect(syncMaterialRect.right, closeTo(addMaterialRect.right, 0.01));
      expect(syncRect.left > addRect.left, isTrue);

      await tester.tap(addFabFinder);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('quick_add_bar')), findsOneWidget);
      expect(addFabFinder, findsNothing);
      expect(syncFabFinder, findsNothing);
      expect(find.byIcon(Icons.sync_rounded), findsNothing);

      await tester.tap(find.byKey(const ValueKey('quick_add_cancel_button')));
      await tester.pumpAndSettle();

      expect(syncFabFinder, findsOneWidget);
      expect(addFabFinder, findsOneWidget);

      await _selectStorageModeAndReturn(tester, 'Both');

      expect(syncFabFinder, findsOneWidget);
      final bothSyncRect = tester.getRect(syncFabFinder);
      final bothAddRect = tester.getRect(addFabFinder);
      expect(
        bothSyncRect.bottom <= bothAddRect.top &&
            bothSyncRect.width < bothAddRect.width &&
            (bothSyncRect.right - bothAddRect.right).abs() < 0.01,
        isTrue,
      );
    },
  );

  testWidgets(
    'Task pills display identical primaryContainer squares with white circles across all tasks and downgrade via the > button per TDF_SPEC.md Section 6.3',
    (WidgetTester tester) async {
      final seededTdf = [
        _tdfHeader(
          '09:00:01',
          'f10000OkD2 f20000OkD2 f30000OkD2 r10000OkD2 r20000OkD2 r30000OkD2 r40000OkD2 r50000OkD2 p10000OkD2',
        ),
        _tdfTask('f10000OkD2', 'Focus 1', '08:00', priority: true),
        _tdfTask('f20000OkD2', 'Focus 2', '08:05'),
        _tdfTask('f30000OkD2', 'Focus 3', '08:10'),
        _tdfTask('r10000OkD2', 'Ready 1', '08:15'),
        _tdfTask('r20000OkD2', 'Ready 2', '08:20'),
        _tdfTask('r30000OkD2', 'Ready 3', '08:25'),
        _tdfTask('r40000OkD2', 'Ready 4', '08:30'),
        _tdfTask('r50000OkD2', 'Ready 5', '09:00:00'),
        _tdfTask('p10000OkD2', 'Planned 1', '09:00:01'),
      ].join('\n');

      final container = await _pumpHomeAppWithContainer(
        tester,
        initialTdf: seededTdf,
      );

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
        );
        expect(innerDecoration?.border?.top.color, equals(Colors.white));
      }

      await tester.tap(
        find.byKey(const ValueKey('downgrade_task_button_f10000OkD2')),
      );
      await tester.pumpAndSettle();

      var board = container.read(taskNotifierProvider).value!;
      expect(
        board.focus.map((task) => task.id),
        equals(['f20000OkD2', 'f30000OkD2', 'r10000OkD2']),
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
      );
      expect(board.planned.map((task) => task.id), equals(['p10000OkD2']));
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
      );
      expect(board.planned.map((task) => task.id), equals(['r20000OkD2']));

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('downgrade_task_button_r20000OkD2')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('downgrade_task_button_r20000OkD2')),
      );
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(board.planned, isEmpty);
      expect(board.someday.map((task) => task.id), equals(['r20000OkD2']));
      expect(board.queueTaskIds.contains('r20000OkD2'), isFalse);
      expect(board.findTask('r20000OkD2')?.isPriority, isFalse);

      await tester.tap(
        find.byKey(const ValueKey('tier_indicator_item_someday')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('downgrade_task_button_r20000OkD2')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Search view displays ALL TASKS, orders all tasks from Focus through Completed, applies active label filter, and restores the previous tier screen on close',
    (WidgetTester tester) async {
      final searchTdf = [
        _tdfHeader(
          '07:45:00',
          'f10000OkD2 f20000OkD2 f30000OkD2 r10000OkD2 r20000OkD2 r30000OkD2 r40000OkD2 r50000OkD2 p10000OkD2 b10000OkD2',
        ),
        'label work00OkD2 {\n  name "Work"\n}',
        'label home00OkD2 {\n  name "Home"\n}',
        _tdfTask(
          'f10000OkD2',
          'Alpha Focus Match',
          '07:00',
          label: 'work00OkD2',
        ),
        _tdfTask('f20000OkD2', 'Focus Two', '07:05', label: 'home00OkD2'),
        _tdfTask('f30000OkD2', 'Focus Three', '07:10', label: 'home00OkD2'),
        _tdfTask(
          'r10000OkD2',
          'Bravo Ready Match',
          '07:15',
          label: 'work00OkD2',
        ),
        _tdfTask('r20000OkD2', 'Ready Two', '07:20', label: 'home00OkD2'),
        _tdfTask('r30000OkD2', 'Ready Three', '07:25', label: 'home00OkD2'),
        _tdfTask('r40000OkD2', 'Ready Four', '07:30', label: 'home00OkD2'),
        _tdfTask('r50000OkD2', 'Ready Five', '07:35', label: 'home00OkD2'),
        _tdfTask(
          'p10000OkD2',
          'Charlie Planned Match',
          '07:40',
          label: 'work00OkD2',
        ),
        _tdfTask(
          'b10000OkD2',
          'Delta Blocked Match',
          '07:45',
          label: 'home00OkD2',
          extra: '  suspended 2026-11-05 09:00\n',
        ),
        'task s10000OkD2 {\n  name "Echo Someday Match"\n  created 2026-11-01 07:50\n  labels work00OkD2\n}',
        'task c10000OkD2 {\n  name "Foxtrot Completed Match"\n  created 2026-10-28 08:00\n  queued 2026-10-28 08:00\n  finished 2026-10-29 10:00\n  completions 1\n  labels work00OkD2\n}',
        'task c20000OkD2 {\n  name "Home Completed Only"\n  created 2026-10-28 09:00\n  queued 2026-10-28 09:00\n  finished 2026-10-29 11:00\n  completions 1\n  labels home00OkD2\n}',
      ].join('\n');

      await _pumpHomeApp(tester, initialTdf: searchTdf);

      await tester.tap(
        find.byKey(const ValueKey('tier_indicator_item_blocked')),
      );
      await tester.pumpAndSettle();
      expect(find.text('BLOCKED TASKS'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      expect(find.text('ALL TASKS'), findsOneWidget);
      expect(find.text('BLOCKED TASKS'), findsNothing);

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
      );
      expect(find.text('Focus Two'), findsNothing);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('BLOCKED TASKS'), findsOneWidget);
      expect(find.text('Delta Blocked Match'), findsOneWidget);
      expect(find.text('ALL TASKS'), findsNothing);

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
      expect(find.text('PLANNED TASKS'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      expect(find.text('ALL TASKS'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('top_bar_title')),
          matching: find.text('Work'),
        ),
        findsOneWidget,
      );
      expect(find.text('Alpha Focus Match'), findsOneWidget);
      expect(find.text('Bravo Ready Match'), findsOneWidget);
      expect(find.text('Charlie Planned Match'), findsOneWidget);
      expect(find.text('Echo Someday Match'), findsOneWidget);
      expect(find.text('Foxtrot Completed Match'), findsOneWidget);
      expect(find.text('Focus Two'), findsNothing);
      expect(find.text('Delta Blocked Match'), findsNothing);
      expect(find.text('Home Completed Only'), findsNothing);

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
      );

      await tester.enterText(find.byType(TextField), 'Foxtrot');
      await tester.pumpAndSettle();
      expect(find.text('Foxtrot Completed Match'), findsOneWidget);
      expect(find.text('Alpha Focus Match'), findsNothing);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('PLANNED TASKS'), findsOneWidget);
    },
  );

  testWidgets(
    'HomeScreen displays localized unsupported TDF version update hint once without repeated remote fetch retries',
    (WidgetTester tester) async {
      var remoteFetchCount = 0;
      const webDavConfig = WebDavConfig(
        storageMode: StorageMode.webdav,
        language: AppLanguage.german,
        serverUrl: 'https://cloud.example.com/dav/',
        username: 'alice',
        password: 'secret',
        filePath: 'tasks.tdf',
      );
      final remoteStore = <String, String>{
        webDavConfig.resolveEndpointUri()!.path: 'tdf 0.7.0\n',
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(webDavConfig),
            ),
            webDavRepositoryProvider.overrideWith(
              (ref) => _CountingFakeWebDavRepository(
                config: webDavConfig,
                remoteStore: remoteStore,
                onFetch: () => remoteFetchCount++,
              ),
            ),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );

      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));

      expect(remoteFetchCount, equals(1));
      expect(
        find.text(
          'Die Remote-Datei verwendet die nicht unterstützte Dateiversion 0.7.0. Bitte aktualisieren Sie TierTask auf eine neuere Version.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'HomeScreen shows localized floating Undo SnackBar for complete, auto-finish subtask, and downgrade without obstructing TierPageIndicator',
    (WidgetTester tester) async {
      const initialTdf = '''
tdf 0.6.0

queue {
    modified 2026-11-01 08:00:00
    task 000001OkD2
    task 000002OkD2
}

task 000001OkD2 priority {
    name "Focus Alpha"
    created 2026-11-01 08:00
}

task 000002OkD2 priority {
    name "Auto Subtask Beta"
    created 2026-11-01 08:05
    subtasks auto-finish {
        step false "Final Checklist Step"
    }
}
''';
      final container = await _pumpHomeAppWithContainer(
        tester,
        initialTdf: initialTdf,
      );

      await tester.tap(
        find.byKey(const ValueKey('complete_task_button_000001OkD2')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Completed "Focus Alpha".'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('tier_indicator_item_completed')),
      );
      await tester.pumpAndSettle();
      expect(find.text('COMPLETED TASKS'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(
        container
            .read(taskNotifierProvider)
            .requireValue
            .findTask('000001OkD2')!
            .isCompleted,
        isFalse,
      );

      await tester.tap(find.byKey(const ValueKey('tier_indicator_item_focus')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('downgrade_task_button_000001OkD2')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Downgraded "Focus Alpha".'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('add_task_fab')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auto Subtask Beta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Final Checklist Step'));
      await tester.pumpAndSettle();
      expect(find.text('Completed "Auto Subtask Beta".'), findsOneWidget);
      expect(find.text('Downgraded "Focus Alpha".'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('tier_indicator_item_ready')));
      await tester.pumpAndSettle();
      expect(find.text('READY TASKS'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      final restoredBeta = container
          .read(taskNotifierProvider)
          .requireValue
          .findTask('000002OkD2')!;
      expect(restoredBeta.isCompleted, isFalse);
      expect(restoredBeta.subtasks.single.isCompleted, isFalse);
    },
  );

  testWidgets(
    'Desktop Ctrl+Z reverses stacked actions on Linux and Windows even after SnackBar dismissal and respects Android, modifier, route, and EditableText guards',
    (WidgetTester tester) async {
      const initialTdf = '''
tdf 0.6.0

queue {
    modified 2026-11-01 08:00:00
    task 000001OkD2
    task 000002OkD2
}

task 000001OkD2 priority {
    name "Shortcut Task One"
    created 2026-11-01 08:00
}

task 000002OkD2 priority {
    name "Shortcut Task Two"
    created 2026-11-01 08:05
}
''';
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        final container = await _pumpHomeAppWithContainer(
          tester,
          initialTdf: initialTdf,
        );

        await tester.tap(
          find.byKey(const ValueKey('complete_task_button_000001OkD2')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('downgrade_task_button_000002OkD2')),
        );
        await tester.pumpAndSettle();
        expect(container.read(taskUndoStateProvider).stackDepth, equals(2));

        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);

        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        await _sendCtrlZ(tester);
        expect(
          container.read(taskUndoStateProvider).stackDepth,
          equals(2),
          reason: 'Ctrl+Z must not fire on Android',
        );

        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        await _sendCtrlZ(tester, withShift: true);
        await _sendCtrlZRepeat(tester);
        expect(
          container.read(taskUndoStateProvider).stackDepth,
          equals(2),
          reason: 'Ctrl+Shift+Z and KeyRepeatEvent must not trigger undo',
        );

        await tester.tap(find.byKey(const ValueKey('add_task_fab')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('quick_add_input')));
        await tester.pump();
        await _sendCtrlZ(tester);
        expect(
          container.read(taskUndoStateProvider).stackDepth,
          equals(2),
          reason: 'Ctrl+Z must not hijack focused QuickAddBar input',
        );
        await tester.tap(find.byKey(const ValueKey('quick_add_cancel_button')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('top_bar_search_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(TextField).first);
        await tester.pump();
        await _sendCtrlZ(tester);
        expect(
          container.read(taskUndoStateProvider).stackDepth,
          equals(2),
          reason: 'Ctrl+Z must not hijack focused search TextField',
        );
        await tester.tap(find.byKey(const ValueKey('top_bar_search_button')));
        await tester.pumpAndSettle();

        await openSettingsFromMenu(tester);
        await _sendCtrlZ(tester);
        expect(
          container.read(taskUndoStateProvider).stackDepth,
          equals(2),
          reason: 'Ctrl+Z must not fire while a pushed route is on top',
        );
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();

        await _sendCtrlZ(tester);
        expect(container.read(taskUndoStateProvider).stackDepth, equals(1));
        expect(
          container
              .read(taskNotifierProvider)
              .requireValue
              .findTask('000002OkD2')!
              .isPriority,
          isTrue,
        );

        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        await _sendCtrlZ(tester);
        expect(container.read(taskUndoStateProvider).stackDepth, equals(0));
        expect(
          container
              .read(taskNotifierProvider)
              .requireValue
              .findTask('000001OkD2')!
              .isCompleted,
          isFalse,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'TierTaskApp and pumpLeafWidget resolve standalone material_ui MaterialLocalizations in English and German',
    (WidgetTester tester) async {
      await _pumpHomeApp(
        tester,
        config: const WebDavConfig(language: AppLanguage.english),
      );
      final enContext = tester.element(find.byType(Scaffold));
      expect(
        MaterialLocalizations.of(enContext).cancelButtonLabel,
        equals('Cancel'),
        reason: 'English TierTaskApp must provide standalone material_ui MaterialLocalizations',
      );

      await _pumpHomeApp(
        tester,
        config: const WebDavConfig(language: AppLanguage.german),
      );
      final deContext = tester.element(find.byType(Scaffold));
      expect(
        MaterialLocalizations.of(deContext).cancelButtonLabel,
        equals('Abbrechen'),
        reason: 'German TierTaskApp must register material_ui GlobalMaterialLocalizations',
      );
      expect(
        MaterialLocalizations.of(deContext).firstDayOfWeekIndex,
        equals(1),
        reason: 'German Material calendar week must start on Monday',
      );

      await pumpLeafWidget(
        tester,
        const SizedBox(key: ValueKey<String>('leaf_probe')),
        locale: const Locale('de'),
      );
      final leafDeContext = tester.element(
        find.byKey(const ValueKey<String>('leaf_probe')),
      );
      expect(
        MaterialLocalizations.of(leafDeContext).cancelButtonLabel,
        equals('Abbrechen'),
        reason: 'German pumpLeafWidget must register material_ui GlobalMaterialLocalizations',
      );
    },
  );
}

/// Pumps [TierTaskApp] with optional [config] and [initialTdf] overrides.
Future<void> _pumpHomeApp(
  WidgetTester tester, {
  WebDavConfig config = const WebDavConfig(language: AppLanguage.english),
  String? initialTdf,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(config),
        ),
        if (initialTdf != null)
          localFileRepositoryProvider.overrideWith(
            (ref) =>
                FakeLocalFileRepository(config: config, initialTdf: initialTdf),
          ),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1, 12, 0)),
      ],
      child: const TierTaskApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Pumps [TierTaskApp] inside an [UncontrolledProviderScope] and returns the [ProviderContainer].
Future<ProviderContainer> _pumpHomeAppWithContainer(
  WidgetTester tester, {
  required String initialTdf,
}) async {
  const config = WebDavConfig(language: AppLanguage.english);
  final container = ProviderContainer(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(
        InMemorySettingsRepository(config),
      ),
      localFileRepositoryProvider.overrideWith(
        (ref) =>
            FakeLocalFileRepository(config: config, initialTdf: initialTdf),
      ),
      clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1, 12, 0)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const TierTaskApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Opens Settings from the drawer, selects [modeLabel], and navigates back.
Future<void> _selectStorageModeAndReturn(
  WidgetTester tester,
  String modeLabel,
) async {
  await openSettingsFromMenu(tester);
  await tester.ensureVisible(find.text(modeLabel));
  await tester.tap(find.text(modeLabel));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
}

/// Dispatches a `Ctrl+Z` (or `Ctrl+Shift+Z`) hardware key-down and key-up sequence.
Future<void> _sendCtrlZ(WidgetTester tester, {bool withShift = false}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (withShift) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
  if (withShift) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

/// Dispatches only a `KeyRepeatEvent` for `Z` while `Ctrl` is held down.
Future<void> _sendCtrlZRepeat(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await simulateKeyRepeatEvent(
    LogicalKeyboardKey.keyZ,
    physicalKey: PhysicalKeyboardKey.keyZ,
  );
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

/// Builds a `.tdf` document header and queue block for [spaceSeparatedIds].
String _tdfHeader(String modifiedTime, String spaceSeparatedIds) {
  final entries = spaceSeparatedIds
      .split(' ')
      .map((id) => '  task $id')
      .join('\n');
  return 'tdf 0.5.0\n\nqueue {\n  modified 2026-11-01 $modifiedTime\n$entries\n}';
}

/// Builds a queued `.tdf` task block string for test fixtures.
String _tdfTask(
  String id,
  String name,
  String time, {
  bool priority = false,
  String? label,
  String extra = '',
}) {
  final header = priority ? 'task $id priority {' : 'task $id {';
  final labelLine = label != null ? '  labels $label\n' : '';
  return '$header\n  name "$name"\n  created 2026-11-01 $time\n  queued 2026-11-01 $time\n$extra$labelLine}';
}
