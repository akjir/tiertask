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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/link_launcher_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'Tapping a task pill with subtasks animates subtasks downward, shifts subsequent tasks down, toggles subtasks on and off, and collapses on second tap',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 08:05:00
  task 000001OkD2
  task 000002OkD2
}

task 000001OkD2 {
  name "Deploy release candidate"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
  subtasks {
    step false "Prepare backup"
    step false "Verify checksum"
  }
}
task 000002OkD2 {
  name "Update status page"
  created 2026-11-01 08:05
  queued 2026-11-01 08:05
}
''';
      final container = await _pumpSeededApp(tester, seededTdf);

      final step0Finder = _byKey('subtask_step_000001OkD2_0');
      final step1Finder = _byKey('subtask_step_000001OkD2_1');
      final secondTaskPillFinder = _byKey('tier_pill_focus_000002OkD2');

      _expectNone(step0Finder, 'Subtasks must be collapsed initially');
      expect(step1Finder, findsNothing);

      final initialSecondTaskTop = tester.getTopLeft(secondTaskPillFinder).dy;

      await tester.tap(find.text('Deploy release candidate'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));

      final midAnimationSecondTaskTop = tester
          .getTopLeft(secondTaskPillFinder)
          .dy;
      _expectTrue(
        midAnimationSecondTaskTop > initialSecondTaskTop,
        'Downward expansion animation must progressively shift the following task pill downward',
      );

      await tester.pumpAndSettle();

      final expandedSecondTaskTop = tester.getTopLeft(secondTaskPillFinder).dy;
      _expectTrue(
        expandedSecondTaskTop > midAnimationSecondTaskTop,
        'Completed expansion must shift the following task pill to its full offset below the subtasks',
      );
      _expectOne(step0Finder, 'First subtask must be visible when expanded');
      _expectOne(step1Finder, 'Second subtask must be visible when expanded');
      expect(find.text('Prepare backup'), findsOneWidget);
      expect(find.text('Verify checksum'), findsOneWidget);

      await tester.tap(step0Finder);
      await tester.pumpAndSettle();

      var board = container.read(taskNotifierProvider).value!;
      _expectTrue(
        board.findTask('000001OkD2')!.subtasks[0].isCompleted,
        'Tapping an unchecked subtask must mark it as completed',
      );
      expect(
        board.findTask('000001OkD2')!.subtasks[1].isCompleted,
        isFalse,
        reason: 'Other subtasks must remain unchanged',
      );
      _expectOne(
        _byKey('subtasks_task_indicator_000001OkD2'),
        'Subtasks indicator icon must remain visible when a subtask is checked',
      );

      await tester.tap(step1Finder);
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      _expectTrue(
        board
            .findTask('000001OkD2')!
            .subtasks
            .every((step) => step.isCompleted),
        'Tapping the second subtask must mark all subtasks completed',
      );
      _expectOne(
        _byKey('subtasks_task_indicator_000001OkD2'),
        'Subtasks indicator icon must remain visible when all subtasks are checked',
      );

      await tester.tap(step0Finder);
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(
        board.findTask('000001OkD2')!.subtasks[0].isCompleted,
        isFalse,
        reason: 'Tapping a checked subtask again must uncheck it',
      );

      await tester.tap(find.text('Deploy release candidate'));
      await tester.pumpAndSettle();

      _expectNone(
        step0Finder,
        'Tapping the same task again must collapse its subtasks',
      );
      expect(step1Finder, findsNothing);
      expect(
        tester.getTopLeft(secondTaskPillFinder).dy,
        closeTo(initialSecondTaskTop, 0.01),
        reason: 'Collapsing subtasks must shift subsequent tasks back to their initial position',
      );

      await tester.tap(_byKey('complete_task_button_000001OkD2'));
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(
        board.completed.map((task) => task.id),
        equals(['000001OkD2']),
        reason: 'Completing 000001OkD2 must move it to Completed',
      );
      _expectTrue(
        board
            .findTask('000001OkD2')!
            .subtasks
            .every((step) => step.isCompleted),
        'Completing a task with subtasks must mark all subtasks as completed',
      );

      await tester.tap(_byKey('tier_indicator_item_completed'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Deploy release candidate'));
      await tester.pumpAndSettle();

      _expectOne(
        step0Finder,
        'Completed task must still allow viewing its subtasks',
      );
      await tester.tap(step0Finder);
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      _expectTrue(
        board
            .findTask('000001OkD2')!
            .subtasks
            .every((step) => step.isCompleted),
        'Tapping a subtask of a completed task must not unlock or uncheck the subtask',
      );

      await tester.tap(_byKey('complete_task_button_000001OkD2'));
      await tester.pumpAndSettle();

      board = container.read(taskNotifierProvider).value!;
      expect(
        board.completed,
        isEmpty,
        reason: 'Tapping the completion button in Completed must restore 000001OkD2',
      );
      _expectTrue(
        board
            .findTask('000001OkD2')!
            .subtasks
            .every((step) => !step.isCompleted),
        'Reopening a completed task must reopen all of its subtasks',
      );
    },
  );

  testWidgets(
    'Checking all expanded subtasks on a task with subtasks auto-finish completes the task automatically and differentiates subtask indicator icons and hover tooltips',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 08:05:00
  task auto00OkD2
  task manualOkD2
}

task auto00OkD2 priority {
  name "Auto Finish Checklist Task"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
  repeat 1 weeks
  subtasks auto-finish {
    step false "Final verification step"
    step false "Second step"
  }
}
task manualOkD2 {
  name "Manual Subtasks Task"
  created 2026-11-01 08:05
  queued 2026-11-01 08:05
  subtasks {
    step false "Manual step"
  }
}
''';
      final container = await _pumpSeededApp(tester, seededTdf);

      final autoSubtasksIcon = tester.widget<Icon>(
        _byKey('subtasks_task_indicator_auto00OkD2'),
      );
      final manualSubtasksIcon = tester.widget<Icon>(
        _byKey('subtasks_task_indicator_manualOkD2'),
      );

      expect(
        manualSubtasksIcon.icon,
        equals(Icons.checklist_rounded),
        reason: 'Standard subtasks indicator without auto-finish must use checklist_rounded',
      );
      expect(
        autoSubtasksIcon.icon,
        equals(Icons.fact_check_outlined),
        reason: 'Auto-finish subtasks indicator must use fact_check_outlined to distinguish tasks closed by subtasks',
      );
      expect(
        autoSubtasksIcon.icon,
        isNot(equals(manualSubtasksIcon.icon)),
        reason: 'Subtasks with and without auto-finish must display distinct indicator icons',
      );

      _expectTooltip(tester, 'priority_task_indicator_auto00OkD2', 'Priority');
      _expectTooltip(
        tester,
        'repeat_task_indicator_auto00OkD2',
        'Repeating task',
      );
      _expectTooltip(
        tester,
        'subtasks_task_indicator_auto00OkD2',
        'Subtasks (auto-finish)',
      );
      _expectTooltip(tester, 'subtasks_task_indicator_manualOkD2', 'Subtasks');

      final mouseGesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouseGesture.addPointer(location: Offset.zero);
      addTearDown(mouseGesture.removePointer);

      await mouseGesture.moveTo(
        tester.getCenter(_byKey('repeat_task_indicator_auto00OkD2')),
      );
      await tester.pumpAndSettle();
      _expectOne(
        find.text('Repeating task'),
        'Hovering the mouse over the repeat indicator must display its tooltip',
      );

      await container
          .read(webDavConfigProvider.notifier)
          .updateLanguage(AppLanguage.german);
      await tester.pumpAndSettle();

      _expectTooltip(tester, 'priority_task_indicator_auto00OkD2', 'Priorität');
      _expectTooltip(
        tester,
        'repeat_task_indicator_auto00OkD2',
        'Wiederkehrende Aufgabe',
      );
      _expectTooltip(
        tester,
        'subtasks_task_indicator_auto00OkD2',
        'Unteraufgaben (automatisch abschließen)',
      );
      _expectTooltip(
        tester,
        'subtasks_task_indicator_manualOkD2',
        'Unteraufgaben',
      );

      final firstTaskFinder = _byKey('tier_pill_focus_auto00OkD2');
      final secondTaskFinder = _byKey('tier_pill_focus_manualOkD2');
      final initialFirstTaskTop = tester.getTopLeft(firstTaskFinder).dy;
      final collapsedSecondTaskTop = tester.getTopLeft(secondTaskFinder).dy;

      await tester.tap(find.text('Auto Finish Checklist Task'));
      await tester.pumpAndSettle();

      final expandedSecondTaskTop = tester.getTopLeft(secondTaskFinder).dy;
      expect(expandedSecondTaskTop > collapsedSecondTaskTop, isTrue);

      await tester.tap(_byKey('subtask_step_auto00OkD2_0'));
      await tester.pumpAndSettle();

      await tester.tap(_byKey('subtask_step_auto00OkD2_1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));

      final midSubgroupCollapseTop = tester.getTopLeft(secondTaskFinder).dy;
      _expectTrue(
        midSubgroupCollapseTop < expandedSecondTaskTop &&
            midSubgroupCollapseTop > collapsedSecondTaskTop,
        'Stage 1 of subtask auto-finish must collapse the subtask subgroup first while shifting lower tasks upward',
      );
      _expectOne(
        _byKey('subtask_step_auto00OkD2_1'),
        'Subtask rows must still be visible while the subgroup is collapsing during Stage 1',
      );

      await tester.pump(const Duration(milliseconds: 110));

      _expectNone(
        _byKey('subtask_step_auto00OkD2_0'),
        'Subtask subgroup must be completely closed before Stage 2 task removal starts',
      );
      _expectOne(
        firstTaskFinder,
        'Parent task pill must still be present when Stage 2 task removal begins',
      );
      expect(
        tester.getTopLeft(secondTaskFinder).dy,
        closeTo(collapsedSecondTaskTop, 0.5),
        reason: 'Lower task must reach the collapsed-subgroup offset right as Stage 1 finishes',
      );

      await tester.pump(const Duration(milliseconds: 130));

      final midRemovalSecondTaskTop = tester.getTopLeft(secondTaskFinder).dy;
      _expectTrue(
        midRemovalSecondTaskTop < collapsedSecondTaskTop &&
            midRemovalSecondTaskTop > initialFirstTaskTop,
        'Stage 2 task removal animation must progressively slide lower tasks upward into the removed task slot',
      );

      await tester.pumpAndSettle();

      final board = container.read(taskNotifierProvider).value!;
      expect(
        board.focus.map((task) => task.id),
        equals(['manualOkD2']),
        reason: 'Auto-finished recurring task must leave Focus and reschedule into Blocked when all steps are done',
      );
      expect(
        board.blocked.map((task) => task.id),
        equals(['auto00OkD2']),
        reason: 'Auto-finished recurring task must move to Blocked',
      );
      expect(
        tester.getTopLeft(secondTaskFinder).dy,
        closeTo(initialFirstTaskTop, 0.01),
        reason: 'After task removal completes, the lower task must rest at the exact top position of the removed task',
      );
    },
  );

  testWidgets(
    'Task pill displays passive link indicator, expands link rows on tap, launches URIs via LinkLauncherRepository, and shows SnackBar on launch failure',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 08:00:00
  task lnk001OkD2
}

task lnk001OkD2 {
  name "Review architecture docs"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
  link "Architecture Spec" "https://example.com/arch"
  link "Issue Tracker" "https://example.com/issues/10"
}
''';
      final fakeLauncher = FakeLinkLauncherRepository();
      await _pumpSeededApp(tester, seededTdf, linkLauncher: fakeLauncher);

      final linksIndicatorFinder = _byKey('links_task_indicator_lnk001OkD2');
      _expectOne(
        linksIndicatorFinder,
        'Task with links must display the passive link indicator icon',
      );
      final linksIcon = tester.widget<Icon>(linksIndicatorFinder);
      expect(linksIcon.icon, equals(Icons.link_rounded));

      final link0Finder = _byKey('task_link_lnk001OkD2_0');
      final link1Finder = _byKey('task_link_lnk001OkD2_1');
      _expectNone(link0Finder, 'Task links must be collapsed initially');

      await tester.tap(find.text('Review architecture docs'));
      await tester.pumpAndSettle();

      expect(link0Finder, findsOneWidget);
      expect(link1Finder, findsOneWidget);
      expect(find.text('Architecture Spec'), findsOneWidget);
      expect(find.text('Issue Tracker'), findsOneWidget);

      await tester.tap(link0Finder);
      await tester.pumpAndSettle();
      expect(
        fakeLauncher.launchedUris,
        equals(['https://example.com/arch']),
        reason:
            'Tapping a link row must launch its URI via LinkLauncherRepository',
      );

      fakeLauncher.shouldThrow = true;
      await tester.tap(link1Finder);
      await tester.pumpAndSettle();
      _expectOne(
        find.text('Could not open link.'),
        'Failed link launch must display a localized error SnackBar',
      );
    },
  );

  testWidgets(
    'Task pill displays passive note indicator, expands note-only tasks, and renders expanded note above links and subtasks with leading icon',
    (WidgetTester tester) async {
      const seededTdf = '''
tdf 0.5.0

queue {
  modified 2026-11-01 08:10:00
  task all001OkD2
  task not001OkD2
  task plain1OkD2
}

task not001OkD2 {
  name "Note Only Task"
  note "Standalone note content"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
}
task all001OkD2 priority {
  name "Full Details Task"
  note "Top level task note"
  created 2026-11-01 08:05
  queued 2026-11-01 08:05
  repeat 1 days
  link "Design Doc" "https://example.com/design"
  subtasks {
    step false "First checklist item"
  }
}
task plain1OkD2 {
  name "No Note Task"
  created 2026-11-01 08:10
  queued 2026-11-01 08:10
}
''';
      await _pumpSeededApp(tester, seededTdf);

      final noteOnlyIndicatorFinder = _byKey('note_task_indicator_not001OkD2');
      final fullNoteIndicatorFinder = _byKey('note_task_indicator_all001OkD2');
      final plainNoteIndicatorFinder = _byKey('note_task_indicator_plain1OkD2');

      _expectOne(
        noteOnlyIndicatorFinder,
        'Task with note must display the passive note indicator icon',
      );
      _expectOne(
        fullNoteIndicatorFinder,
        'Task with note, links, and subtasks must display the passive note indicator icon',
      );
      _expectNone(
        plainNoteIndicatorFinder,
        'Task without a note must not display the note indicator icon',
      );

      final noteIndicatorIcon = tester.widget<Icon>(noteOnlyIndicatorFinder);
      expect(noteIndicatorIcon.icon, equals(Icons.notes_rounded));
      _expectTooltip(tester, 'note_task_indicator_not001OkD2', 'Note');

      final priorityLeft = tester
          .getTopLeft(_byKey('priority_task_indicator_all001OkD2'))
          .dx;
      final repeatLeft = tester
          .getTopLeft(_byKey('repeat_task_indicator_all001OkD2'))
          .dx;
      final noteLeft = tester.getTopLeft(fullNoteIndicatorFinder).dx;
      final linksLeft = tester
          .getTopLeft(_byKey('links_task_indicator_all001OkD2'))
          .dx;
      final subtasksLeft = tester
          .getTopLeft(_byKey('subtasks_task_indicator_all001OkD2'))
          .dx;

      _expectTrue(
        priorityLeft < repeatLeft &&
            repeatLeft < noteLeft &&
            noteLeft < linksLeft &&
            linksLeft < subtasksLeft,
        'Passive indicators must be ordered Priority, Repeat, Note, Links, then Subtasks',
      );

      final noteOnlyRowFinder = _byKey('task_note_not001OkD2');
      _expectNone(noteOnlyRowFinder, 'Note row must be collapsed initially');

      await tester.tap(find.text('Note Only Task'));
      await tester.pumpAndSettle();

      _expectOne(
        noteOnlyRowFinder,
        'Tapping a note-only task pill must expand its note row',
      );
      expect(find.text('Standalone note content'), findsOneWidget);
      _expectOne(
        find.descendant(
          of: noteOnlyRowFinder,
          matching: find.byIcon(Icons.notes_rounded),
        ),
        'Expanded note row must display a leading note icon',
      );

      await tester.tap(find.text('Note Only Task'));
      await tester.pumpAndSettle();
      _expectNone(
        noteOnlyRowFinder,
        'Tapping an expanded note-only task pill must collapse it',
      );

      final fullNoteRowFinder = _byKey('task_note_all001OkD2');
      final fullLinkRowFinder = _byKey('task_link_all001OkD2_0');
      final fullSubtaskRowFinder = _byKey('subtask_step_all001OkD2_0');

      await tester.tap(find.text('Full Details Task'));
      await tester.pumpAndSettle();

      expect(fullNoteRowFinder, findsOneWidget);
      expect(fullLinkRowFinder, findsOneWidget);
      expect(fullSubtaskRowFinder, findsOneWidget);

      final noteTop = tester.getTopLeft(fullNoteRowFinder).dy;
      final linkTop = tester.getTopLeft(fullLinkRowFinder).dy;
      final subtaskTop = tester.getTopLeft(fullSubtaskRowFinder).dy;

      _expectTrue(
        noteTop < linkTop,
        'Expanded note row must always be rendered above links',
      );
      _expectTrue(
        linkTop < subtaskTop,
        'Expanded links must always be rendered above subtasks',
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

/// Asserts that the [Tooltip.message] wrapping [key] equals [expected].
void _expectTooltip(WidgetTester tester, String key, String expected) {
  final tooltip = tester.widget<Tooltip>(
    find.ancestor(of: _byKey(key), matching: find.byType(Tooltip)),
  );
  expect(tooltip.message, equals(expected));
}

/// Asserts that [actual] is `true` with [reason].
void _expectTrue(bool actual, String reason) =>
    expect(actual, isTrue, reason: reason);

/// Pumps [TierTaskApp] seeded with [seededTdf] and optional [linkLauncher] at `2026-11-01 12:00` UTC.
Future<ProviderContainer> _pumpSeededApp(
  WidgetTester tester,
  String seededTdf, {
  LinkLauncherRepository? linkLauncher,
}) async {
  const config = WebDavConfig(language: AppLanguage.english);
  final container = ProviderContainer(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(
        InMemorySettingsRepository(config),
      ),
      localFileRepositoryProvider.overrideWith(
        (ref) => FakeLocalFileRepository(config: config, initialTdf: seededTdf),
      ),
      if (linkLauncher != null)
        linkLauncherRepositoryProvider.overrideWithValue(linkLauncher),
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
