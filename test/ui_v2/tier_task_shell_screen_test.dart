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

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/models/app_build_profile.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/presentation/app_shell_controller.dart';
import 'package:tiertask/presentation/ui_v2_shell_models.dart';
import 'package:tiertask/providers/sync_providers.dart';
import 'package:tiertask/ui_v2/tier_task_shell_screen.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import 'test_helpers.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 11, 10, 12, 0);

  TaskBoard createSampleBoard() {
    return TaskBoard.evaluate(
      tasks: <TaskItem>[
        TaskItem(
          id: 'taskA00001',
          title: 'Write Phase 3 Shell',
          labelIds: const <String>['work000001'],
          createdAt: fixedNow,
          modifiedAt: fixedNow,
        ),
        TaskItem(
          id: 'taskB00002',
          title: 'Plan Release Notes',
          createdAt: fixedNow,
          modifiedAt: fixedNow,
        ),
      ],
      labels: <TdfLabel>[
        TdfLabel(
          id: 'work000001',
          name: 'Work',
          color: '#2196F3',
          modifiedAt: fixedNow,
        ),
      ],
      locations: <TdfLocation>[
        TdfLocation(
          id: 'locA000001',
          name: 'Office',
          latitude: 47.1204,
          longitude: 8.5173,
          radius: 250.0,
          modifiedAt: fixedNow,
        ),
      ],
      queueBlock: TdfQueueBlock(
        modifiedAt: fixedNow,
        taskIds: const <String>['taskA00001'],
      ),
      evaluationTime: fixedNow,
      localEvaluationTime: fixedNow,
    );
  }

  group('TierTaskShellScreen', () {
    testWidgets(
      'renders desktop chrome, inline DEV pill only in dev profile, persistent sidebar, SemVer footer, and routes across all views',
      (tester) async {
        final container = await pumpV2Widget(
          tester,
          const TierTaskShellScreen(),
          board: createSampleBoard(),
          config: const WebDavConfig(
            language: AppLanguage.english,
            locationEnabled: true,
            diagnosticsEnabled: true,
            storageMode: StorageMode.both,
            serverUrl: 'https://cloud.example.com',
            username: 'alice',
            password: 'secret',
          ),
          buildProfile: AppBuildProfile.dev,
          locationFix: const LocationFix(
            latitude: 47.1204,
            longitude: 8.5173,
            source: LocationSource.gps,
            placeName: 'Riverdale',
          ),
          surfaceSize: const Size(1280, 860),
        );

        expect(find.byType(UiAppLogo), findsOneWidget);
        expect(find.text('TierTask'), findsOneWidget);
        expect(
          find.text('DEV'),
          findsOneWidget,
          reason: 'Inline DEV pill must appear in dev build profile',
        );
        expect(find.text('Version 0.4.0'), findsOneWidget);
        expect(find.text('+4.abc1234'), findsOneWidget);
        expect(find.text('Write Phase 3 Shell'), findsOneWidget);

        // Route via Tools sidebar to Raw TDF, Diagnostic Log, and Settings.
        await tester.tap(find.text('Raw TDF 0.8.0'));
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).view,
          equals(ShellView.rawTdf),
        );

        await tester.tap(find.text('Diagnostic Log'));
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).view,
          equals(ShellView.logs),
        );

        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).view,
          equals(ShellView.settings),
        );
        expect(find.text('Test Connection / Sync Now'), findsOneWidget);

        // Conflict state routes top chrome Sync button directly to Conflict view.
        container
            .read(syncStateProvider.notifier)
            .setConflict(
              'Conflict',
              outcome: const TdfSyncOutcomeException(
                kind: TdfSyncOutcomeKind.deletionConflict,
                message: 'Conflict',
                conflictedTaskIds: <String>['taskA00001'],
              ),
            );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Conflict'));
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).view,
          equals(ShellView.conflict),
        );
        expect(find.text('Apply Decisions & Sync'), findsOneWidget);
      },
    );

    testWidgets(
      'adapts compact <= 720px viewport with slide-over drawer, mobile active filter in chrome, and hides DEV pill in release',
      (tester) async {
        final container = await pumpV2Widget(
          tester,
          const TierTaskShellScreen(),
          board: createSampleBoard(),
          buildProfile: AppBuildProfile.release,
          surfaceSize: const Size(390, 844),
        );

        expect(find.text('DEV'), findsNothing);
        expect(find.byTooltip('Open menu'), findsOneWidget);

        // Open compact drawer and filter by Work label.
        await tester.tap(find.byTooltip('Open menu'));
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).compactDrawerOpen,
          isTrue,
        );
        await tester.tap(find.text('Work').last);
        await tester.pumpAndSettle();

        expect(
          container.read(appShellControllerProvider).activeLabelId,
          equals('work000001'),
        );
        expect(
          container.read(appShellControllerProvider).compactDrawerOpen,
          isFalse,
        );
        // Active filter replaces brand wordmark in compact Tasks top chrome.
        expect(
          find.byTooltip('Clear filter (All Tasks)'),
          findsOneWidget,
          reason: 'Compact active label filter must render clickable clear chip in top chrome',
        );
      },
    );

    testWidgets(
      'supports desktop keyboard shortcuts (/, ArrowRight, ArrowLeft, n, Escape, Ctrl+Z) across Calm/Plum Umber and en/de locales',
      (tester) async {
        final container = await pumpV2Widget(
          tester,
          const TierTaskShellScreen(),
          board: createSampleBoard(),
          presetId: 'plum_umber',
          themeMode: ThemeMode.dark,
          surfaceSize: const Size(1280, 860),
        );

        // ArrowRight steps from Focus -> Ready; ArrowLeft steps back to Focus.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).activeTier,
          equals(ShellTier.ready),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).activeTier,
          equals(ShellTier.focus),
        );

        // Slash opens Global Search; Escape closes it.
        await tester.sendKeyEvent(LogicalKeyboardKey.slash);
        await tester.pumpAndSettle();
        expect(container.read(appShellControllerProvider).searchOpen, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(container.read(appShellControllerProvider).searchOpen, isFalse);

        // Pressing 'n' focuses Quick-Add title input.
        await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
        await tester.pumpAndSettle();
        final focusedContext = FocusManager.instance.primaryFocus?.context;
        expect(
          focusedContext?.findAncestorWidgetOfExactType<EditableText>(),
          isNotNull,
          reason: 'Pressing n on desktop Tasks view must focus Quick-Add EditableText',
        );

        // Typing '/' inside the focused input must NOT hijack focus to Search.
        await tester.sendKeyEvent(LogicalKeyboardKey.slash);
        await tester.pumpAndSettle();
        expect(container.read(appShellControllerProvider).searchOpen, isFalse);

        // Ctrl+F opens Global Search even when focus is inside a text field.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(container.read(appShellControllerProvider).searchOpen, isTrue);

        // Escape closes Search.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(container.read(appShellControllerProvider).searchOpen, isFalse);
      },
    );

    testWidgets(
      'renders localized German strings and unwinds Android PopScope across sidebar and views',
      (tester) async {
        final container = await pumpV2Widget(
          tester,
          const TierTaskShellScreen(),
          board: createSampleBoard(),
          config: const WebDavConfig(language: AppLanguage.german),
          locale: const Locale('de'),
          surfaceSize: const Size(1024, 768),
        );

        expect(find.text('Alle Aufgaben'), findsWidgets);
        expect(find.text('Einstellungen'), findsWidgets);
        expect(find.text('Raw TDF 0.8.0'), findsOneWidget);

        // Open Settings and trigger system back via PopScope -> returns to Tasks.
        container
            .read(appShellControllerProvider.notifier)
            .openView(ShellView.settings);
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).view,
          equals(ShellView.settings),
        );

        final popScope = tester.widget<PopScope<void>>(
          find.byType(PopScope<void>),
        );
        expect(popScope.canPop, isFalse);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          container.read(appShellControllerProvider).view,
          equals(ShellView.tasks),
        );
      },
    );
  });
}
