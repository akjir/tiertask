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
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/board_providers.dart';
import 'package:tiertask/providers/floating_notice_providers.dart';
import 'package:tiertask/providers/shell_providers.dart';
import 'package:tiertask/providers/sync_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/window_control_repository.dart';
import 'package:tiertask/ui/layout/ui_adaptive_app_shell.dart';
import 'package:tiertask/ui/layout/ui_sidebar_section.dart';
import 'package:tiertask/ui/primitives/ui_app_logo.dart';
import 'package:tiertask/ui/primitives/ui_button.dart';
import 'package:tiertask/ui/tier_task_shell_screen.dart';
import 'package:tiertask/ui/tokens/ui_theme_tokens.dart';

import 'test_helpers.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 11, 10, 12);

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
        final container = await pumpLeafWidget(
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

        // Route via Tools sidebar to TDF Source, Diagnostic Log, and Settings.
        await tester.tap(find.text('TDF Source'));
        await tester.pumpAndSettle();
        expect(container.read(shellProvider).view, equals(ShellView.rawTdf));

        await tester.tap(find.text('Diagnostic Log'));
        await tester.pumpAndSettle();
        expect(container.read(shellProvider).view, equals(ShellView.logs));

        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        expect(container.read(shellProvider).view, equals(ShellView.settings));
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
        expect(container.read(shellProvider).view, equals(ShellView.conflict));
        expect(find.text('Apply Decisions & Sync'), findsOneWidget);
      },
    );

    testWidgets(
      'adapts compact <= 720px viewport with slide-over drawer, mobile active filter in chrome, and hides DEV pill in release',
      (tester) async {
        final container = await pumpLeafWidget(
          tester,
          const TierTaskShellScreen(),
          board: createSampleBoard(),
          surfaceSize: const Size(390, 844),
        );

        expect(find.text('DEV'), findsNothing);
        expect(find.byTooltip('Open menu'), findsOneWidget);

        // Open compact drawer and filter by Work label.
        await tester.tap(find.byTooltip('Open menu'));
        await tester.pumpAndSettle();
        expect(container.read(shellProvider).compactDrawerOpen, isTrue);
        await tester.tap(find.text('Work').last);
        await tester.pumpAndSettle();

        expect(
          container.read(shellProvider).activeLabelId,
          equals('work000001'),
        );
        expect(container.read(shellProvider).compactDrawerOpen, isFalse);
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
        final container = await pumpLeafWidget(
          tester,
          const TierTaskShellScreen(),
          board: createSampleBoard(),
          presetId: 'plum_umber',
          themeMode: ThemeMode.dark,
        );

        // ArrowRight steps from Focus -> Ready; ArrowLeft steps back to Focus.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(
          container.read(shellProvider).activeTier,
          equals(TaskTier.ready),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(
          container.read(shellProvider).activeTier,
          equals(TaskTier.focus),
        );

        // Slash opens Global Search; Escape closes it.
        await tester.sendKeyEvent(LogicalKeyboardKey.slash);
        await tester.pumpAndSettle();
        expect(container.read(shellProvider).searchOpen, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(container.read(shellProvider).searchOpen, isFalse);

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
        expect(container.read(shellProvider).searchOpen, isFalse);

        // Ctrl+F opens Global Search even when focus is inside a text field.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(container.read(shellProvider).searchOpen, isTrue);

        // Escape closes Search.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(container.read(shellProvider).searchOpen, isFalse);
      },
    );

    testWidgets(
      'renders localized German strings and unwinds Android PopScope across sidebar and views',
      (tester) async {
        final container = await pumpLeafWidget(
          tester,
          const TierTaskShellScreen(),
          board: createSampleBoard(),
          config: const WebDavConfig(language: AppLanguage.german),
          locale: const Locale('de'),
          surfaceSize: const Size(1024, 768),
        );

        expect(find.text('Alle Aufgaben'), findsWidgets);
        expect(find.text('Einstellungen'), findsWidgets);
        expect(find.text('TDF-Quelltext'), findsOneWidget);

        await tester.tap(find.text('TDF-Quelltext'));
        await tester.pumpAndSettle();
        expect(container.read(shellProvider).view, equals(ShellView.rawTdf));
        expect(
          find.text('TDF-Quelltext'),
          findsNWidgets(2),
          reason: 'German TDF-Quelltext must appear in both the sidebar and page title',
        );

        // Open Settings and trigger system back via PopScope -> returns to Tasks.
        container.read(shellProvider.notifier).openView(ShellView.settings);
        await tester.pumpAndSettle();
        expect(container.read(shellProvider).view, equals(ShellView.settings));

        final popScope = tester.widget<PopScope<void>>(
          find.byType(PopScope<void>),
        );
        expect(popScope.canPop, isFalse);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(container.read(shellProvider).view, equals(ShellView.tasks));
      },
    );

    testWidgets(
      'matches prototype top chrome styling: DEV badge after workspace pill, bg chrome pills, workspaces/chevron icons, and accent GPS icon',
      (tester) async {
        await pumpLeafWidget(
          tester,
          const TierTaskShellScreen(),
          board: createSampleBoard(),
          config: const WebDavConfig(
            language: AppLanguage.english,
            locationEnabled: true,
            storageMode: StorageMode.both,
            serverUrl: 'https://cloud.example.com',
            username: 'alice',
            password: 'secret',
          ),
          buildProfile: AppBuildProfile.dev,
          themeMode: ThemeMode.dark,
          locationFix: const LocationFix(
            latitude: 47.1204,
            longitude: 8.5173,
            source: LocationSource.gps,
            placeName: 'Riverdale',
          ),
        );

        final tokens = UiThemePresets.calm.dark;
        final brandRect = tester.getRect(
          find.byKey(const ValueKey<String>('chrome_brand_button')),
        );
        final workspaceFinder = find.byKey(
          const ValueKey<String>('chrome_workspace_button'),
        );
        final workspaceRect = tester.getRect(workspaceFinder);
        final devRect = tester.getRect(
          find.byKey(const ValueKey<String>('chrome_dev_pill')),
        );

        expect(
          workspaceRect.left,
          greaterThan(brandRect.right),
          reason: 'Workspace selector must sit to the right of TierTask brand',
        );
        expect(
          devRect.left,
          greaterThan(workspaceRect.right),
          reason: 'DEV pill must sit immediately after workspace selector',
        );

        final workspaceButton = tester.widget<UiButton>(workspaceFinder);
        expect(
          workspaceButton.leadingIcon,
          equals(Icons.grid_view_outlined),
          reason: 'Workspace pill must use 2x2 grid workspaces icon',
        );
        expect(
          workspaceButton.trailingIcon,
          equals(Icons.unfold_more_rounded),
          reason: 'Workspace pill must use up-down double chevron icon',
        );
        final workspaceContainer = tester.widget<AnimatedContainer>(
          find.descendant(
            of: workspaceFinder,
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(
          (workspaceContainer.decoration as BoxDecoration?)?.color,
          equals(tokens.colors.bg),
          reason: 'Workspace pill must fill with bg token against panel chrome',
        );

        final syncFinder = find.byKey(
          const ValueKey<String>('chrome_sync_button'),
        );
        final syncButton = tester.widget<UiButton>(syncFinder);
        expect(
          syncButton.tone,
          equals(UiButtonTone.muted),
          reason: 'Synced chrome pill must use muted foreground tone',
        );
        final syncContainer = tester.widget<AnimatedContainer>(
          find.descendant(
            of: syncFinder,
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(
          (syncContainer.decoration as BoxDecoration?)?.color,
          equals(tokens.colors.bg),
          reason: 'Synced chrome pill must fill with bg token',
        );
        final syncText = tester.widget<Text>(find.text('Synced'));
        expect(syncText.style?.color, equals(tokens.colors.muted));

        final locationFinder = find.byKey(
          const ValueKey<String>('chrome_location_button'),
        );
        final locationButton = tester.widget<UiButton>(locationFinder);
        expect(
          locationButton.density,
          equals(UiButtonDensity.standard),
          reason: 'Chrome location icon button must use 40px standard density',
        );
        expect(
          locationButton.tone,
          equals(UiButtonTone.accent),
          reason: 'Found GPS status must tint chrome location button accent',
        );
        final locationIcon = tester.widget<Icon>(
          find.descendant(of: locationFinder, matching: find.byType(Icon)),
        );
        expect(locationIcon.size, equals(tokens.spacing.iconMd));
        expect(locationIcon.color, equals(tokens.colors.accent));

        final searchFinder = find.byKey(
          const ValueKey<String>('chrome_search_open_button'),
        );
        final searchButton = tester.widget<UiButton>(searchFinder);
        expect(searchButton.density, equals(UiButtonDensity.standard));
        final searchIcon = tester.widget<Icon>(
          find.descendant(of: searchFinder, matching: find.byType(Icon)),
        );
        expect(searchIcon.size, equals(tokens.spacing.iconMd));
      },
    );

    testWidgets(
      'preserves compact chrome sync bordered pill, compact DEV placement, and drawer workspace icons',
      (tester) async {
        await pumpLeafWidget(
          tester,
          const TierTaskShellScreen(),
          board: createSampleBoard(),
          config: const WebDavConfig(
            language: AppLanguage.english,
            locationEnabled: true,
            storageMode: StorageMode.both,
            serverUrl: 'https://cloud.example.com',
            username: 'alice',
            password: 'secret',
          ),
          buildProfile: AppBuildProfile.dev,
          themeMode: ThemeMode.dark,
          surfaceSize: const Size(390, 844),
        );

        final tokens = UiThemePresets.calm.dark;
        expect(
          find.byKey(const ValueKey<String>('chrome_dev_pill')),
          findsOneWidget,
        );
        final syncFinder = find.byKey(
          const ValueKey<String>('chrome_sync_button'),
        );
        final syncButton = tester.widget<UiButton>(syncFinder);
        expect(syncButton.variant, equals(UiButtonVariant.secondary));
        expect(syncButton.label, isNull);
        final syncContainer = tester.widget<AnimatedContainer>(
          find.descendant(
            of: syncFinder,
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(
          (syncContainer.decoration as BoxDecoration?)?.color,
          equals(tokens.colors.bg),
        );

        // Open compact drawer and check drawer workspace card icons.
        await tester.tap(find.byTooltip('Open menu'));
        await tester.pumpAndSettle();
        final drawerWorkspace = tester.widget<UiButton>(
          find.byKey(const ValueKey<String>('drawer_workspace_button')),
        );
        expect(drawerWorkspace.leadingIcon, equals(Icons.grid_view_outlined));
        expect(drawerWorkspace.trailingIcon, equals(Icons.unfold_more_rounded));
      },
    );

    testWidgets(
      'shows desktop close button beside sync and handles chrome drag/maximize on desktop, while omitting both on Android',
      (tester) async {
        final fakeWindowControls = FakeWindowControlRepository();

        // Desktop expanded and compact widths both show close button beside sync.
        for (final size in const <Size>[Size(1280, 860), Size(390, 844)]) {
          await pumpLeafWidget(
            tester,
            const TierTaskShellScreen(),
            board: createSampleBoard(),
            config: const WebDavConfig(
              language: AppLanguage.english,
              storageMode: StorageMode.both,
              serverUrl: 'https://cloud.example.com',
              username: 'alice',
              password: 'secret',
            ),
            windowControlRepository: fakeWindowControls,
            surfaceSize: size,
          );

          final syncFinder = find.byKey(
            const ValueKey<String>('chrome_sync_button'),
          );
          final closeFinder = find.byKey(
            const ValueKey<String>('chrome_close_window_button'),
          );
          expect(
            closeFinder,
            findsOneWidget,
            reason:
                'Desktop size $size must show the window close button in top chrome',
          );
          expect(
            tester.getTopLeft(closeFinder).dx,
            greaterThan(tester.getTopRight(syncFinder).dx),
            reason:
                'Desktop size $size must place window close button strictly to the right of sync button',
          );
          final closeButton = tester.widget<UiButton>(closeFinder);
          expect(closeButton.variant, equals(UiButtonVariant.icon));
          expect(closeButton.density, equals(UiButtonDensity.standard));
          expect(closeButton.leadingIcon, equals(Icons.close_rounded));
          expect(closeButton.isDangerHover, isTrue);
          expect(closeButton.tooltip, equals('Close TierTask'));
        }

        // Desktop interactions: tap close, drag empty chrome, double-tap empty chrome.
        await pumpLeafWidget(
          tester,
          const TierTaskShellScreen(),
          board: createSampleBoard(),
          config: const WebDavConfig(language: AppLanguage.german),
          locale: const Locale('de'),
          windowControlRepository: fakeWindowControls,
        );
        expect(
          find.byTooltip('TierTask schließen'),
          findsOneWidget,
          reason: 'German locale must localize desktop close button tooltip',
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('chrome_close_window_button')),
        );
        await tester.pump();
        expect(fakeWindowControls.closeWindowCount, equals(1));

        const emptyChromeCenter = Offset(640, 31);
        await tester.dragFrom(emptyChromeCenter, const Offset(36, 10));
        await tester.pumpAndSettle();
        expect(fakeWindowControls.startDraggingCount, equals(1));

        await tester.tapAt(emptyChromeCenter);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(emptyChromeCenter);
        await tester.pumpAndSettle();
        expect(fakeWindowControls.toggleMaximizeCount, equals(1));

        // Android hides close button and chrome drag region at both phone and tablet sizes.
        for (final size in const <Size>[Size(390, 844), Size(1280, 860)]) {
          await pumpLeafWidget(
            tester,
            const TierTaskShellScreen(),
            board: createSampleBoard(),
            supportsDesktopWindowControls: false,
            windowControlRepository: fakeWindowControls,
            surfaceSize: size,
          );
          expect(
            find.byKey(const ValueKey<String>('chrome_close_window_button')),
            findsNothing,
            reason:
                'Android size $size must omit the desktop window close button',
          );
          expect(
            find.byKey(const ValueKey<String>('ui_top_chrome_drag_region')),
            findsNothing,
            reason: 'Android size $size must omit desktop chrome drag gestures',
          );
        }
      },
    );

    testWidgets(
      'omits sidebar WebDAV sync button across all storage modes and scrolls version footer inside sidebar',
      (tester) async {
        final boardWithManyLabels = TaskBoard.evaluate(
          tasks: const <TaskItem>[],
          labels: <TdfLabel>[
            for (var i = 0; i < 16; i++)
              TdfLabel(
                id: 'lbl${i.toString().padLeft(7, '0')}',
                name: 'Label ${i.toString().padLeft(2, '0')}',
                modifiedAt: fixedNow,
              ),
          ],
          queueBlock: TdfQueueBlock(modifiedAt: fixedNow),
          evaluationTime: fixedNow,
          localEvaluationTime: fixedNow,
        );

        for (final mode in StorageMode.values) {
          for (final isCompact in const <bool>[false, true]) {
            final size = isCompact
                ? const Size(390, 560)
                : const Size(1280, 560);
            await pumpLeafWidget(
              tester,
              const TierTaskShellScreen(),
              board: boardWithManyLabels,
              config: WebDavConfig(
                language: AppLanguage.english,
                diagnosticsEnabled: true,
                storageMode: mode,
                serverUrl: 'https://cloud.example.com',
                username: 'alice',
                password: 'secret',
              ),
              surfaceSize: size,
            );

            if (isCompact) {
              await tester.tap(find.byTooltip('Open menu'));
              await tester.pumpAndSettle();
            }

            expect(
              find.byKey(const ValueKey<String>('tool_sync_webdav')),
              findsNothing,
              reason:
                  'StorageMode.$mode (compact=$isCompact) must not render a sync button in the sidebar',
            );
            expect(
              find.text('Synchronize with WebDAV'),
              findsNothing,
              reason:
                  'StorageMode.$mode (compact=$isCompact) must omit sidebar WebDAV sync label',
            );
            expect(
              find.byKey(const ValueKey<String>('chrome_sync_button')),
              findsOneWidget,
              reason:
                  'StorageMode.$mode (compact=$isCompact) keeps top chrome Sync button',
            );
            expect(
              find.byKey(const ValueKey<String>('tool_diagnostic_log')),
              findsOneWidget,
              reason:
                  'StorageMode.$mode (compact=$isCompact) keeps Diagnostic Log tool row',
            );
            expect(
              find.byKey(const ValueKey<String>('tool_raw_tdf')),
              findsOneWidget,
              reason:
                  'StorageMode.$mode (compact=$isCompact) keeps Raw TDF tool row',
            );
            expect(
              find.byKey(const ValueKey<String>('tool_settings')),
              findsOneWidget,
              reason:
                  'StorageMode.$mode (compact=$isCompact) keeps Settings tool row',
            );

            final versionFinder = find.text('Version 0.4.0');
            expect(
              tester.getTopLeft(versionFinder).dy,
              greaterThan(size.height),
              reason:
                  'StorageMode.$mode (compact=$isCompact) version footer must not be sticky when sidebar overflows',
            );
            await tester.ensureVisible(versionFinder);
            await tester.pumpAndSettle();
            expect(
              tester.getRect(versionFinder).bottom,
              lessThanOrEqualTo(size.height),
              reason:
                  'StorageMode.$mode (compact=$isCompact) version footer must scroll into view',
            );
          }
        }
      },
    );

    testWidgets(
      'isolates root shell from boundary timer and floating notices, scopes sync status rebuilds, and skips collapsed sidebar items',
      (tester) async {
        final scopedLabel = TdfLabel(
          id: 'scoped0001',
          name: 'Scoped Project',
          color: '#E91E63',
          isScoped: true,
          modifiedAt: fixedNow,
        );
        final workLabel = TdfLabel(
          id: 'work000001',
          name: 'Work',
          color: '#2196F3',
          modifiedAt: fixedNow,
        );
        final board = TaskBoard.evaluate(
          tasks: <TaskItem>[
            TaskItem(
              id: 'taskA00001',
              title: 'Open Focus Task',
              labelIds: const <String>['work000001'],
              createdAt: fixedNow,
              modifiedAt: fixedNow,
            ),
            TaskItem(
              id: 'taskS00002',
              title: 'Scoped Open Task',
              labelIds: const <String>['scoped0001'],
              createdAt: fixedNow,
              modifiedAt: fixedNow,
            ),
            TaskItem(
              id: 'taskDone03',
              title: 'Finished Task',
              isCompleted: true,
              completedAt: fixedNow,
              createdAt: fixedNow,
              modifiedAt: fixedNow,
            ),
          ],
          labels: <TdfLabel>[workLabel, scopedLabel],
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
            taskIds: const <String>['taskA00001', 'taskS00002'],
          ),
          evaluationTime: fixedNow,
          localEvaluationTime: fixedNow,
        );

        final container = await pumpLeafWidget(
          tester,
          const TierTaskShellScreen(),
          board: board,
          config: const WebDavConfig(
            language: AppLanguage.english,
            storageMode: StorageMode.both,
            serverUrl: 'https://cloud.example.com',
            username: 'alice',
            password: 'secret',
          ),
          nowUtc: fixedNow,
        );

        final boundaryNotifierBefore = container.read(
          boardBoundaryTimerProvider.notifier,
        );
        await tester.pump();
        expect(
          identical(
            container.read(boardBoundaryTimerProvider.notifier),
            boundaryNotifierBefore,
          ),
          isTrue,
          reason: 'Root shell must keep autoDispose boardBoundaryTimerProvider alive across frames',
        );

        // 1. Floating notice show/hide must not rebuild UiAdaptiveAppShell.
        final adaptiveShellBefore = tester.widget<UiAdaptiveAppShell>(
          find.byType(UiAdaptiveAppShell),
        );
        container
            .read(floatingNoticeProvider.notifier)
            .showNotice('Task archived.');
        await tester.pump();
        expect(find.text('Task archived.'), findsOneWidget);
        final adaptiveShellAfterShow = tester.widget<UiAdaptiveAppShell>(
          find.byType(UiAdaptiveAppShell),
        );
        expect(
          identical(adaptiveShellAfterShow, adaptiveShellBefore),
          isTrue,
          reason:
              'Showing a floating notice must not rebuild UiAdaptiveAppShell',
        );

        container.read(floatingNoticeProvider.notifier).dismiss();
        await tester.pump();
        expect(find.text('Task archived.'), findsNothing);
        final adaptiveShellAfterDismiss = tester.widget<UiAdaptiveAppShell>(
          find.byType(UiAdaptiveAppShell),
        );
        expect(
          identical(adaptiveShellAfterDismiss, adaptiveShellBefore),
          isTrue,
          reason: 'Dismissing a floating notice must not rebuild UiAdaptiveAppShell',
        );

        // 2. Boundary timer state changes must not rebuild TierTaskShellScreen root.
        final popScopeBefore = tester.widget<PopScope<void>>(
          find.byType(PopScope<void>),
        );
        await container
            .read(taskNotifierProvider.notifier)
            .addTask(
              'Scheduled deadline task',
              dueAt: fixedNow.add(const Duration(hours: 2)),
            );
        await tester.pump();
        final popScopeAfter = tester.widget<PopScope<void>>(
          find.byType(PopScope<void>),
        );
        expect(
          identical(popScopeAfter, popScopeBefore),
          isTrue,
          reason:
              'Updating boardBoundaryTimerProvider must not rebuild root shell',
        );

        // 3. Unchanged sync status with a new lastSyncedAt must not rebuild _ChromeSyncButton.
        final syncButtonBefore = tester.widget<UiButton>(
          find.byKey(const ValueKey<String>('chrome_sync_button')),
        );
        container
            .read(syncStateProvider.notifier)
            .setSuccess(fixedNow.add(const Duration(minutes: 5)));
        await tester.pump();
        final syncButtonAfter = tester.widget<UiButton>(
          find.byKey(const ValueKey<String>('chrome_sync_button')),
        );
        expect(
          identical(syncButtonAfter, syncButtonBefore),
          isTrue,
          reason: 'Updating lastSyncedAt without changing SyncStatusKind must not rebuild chrome sync button',
        );

        // 4. All Tasks count matches global open tasks in O(1) (Focus..Someday: 2 open tasks, excluding scoped and completed).
        final allTasksRow = find.byKey(
          const ValueKey<String>('label_all_tasks'),
        );
        expect(
          find.descendant(of: allTasksRow, matching: find.text('2')),
          findsOneWidget,
          reason: 'All Tasks sidebar count must equal global open tasks across Focus..Someday',
        );

        // 5. Collapsing Labels and Locations skips allocating sidebar nav items while preserving collapsed summaries.
        final shellNotifier = container.read(shellProvider.notifier);
        shellNotifier.selectLabelFilter('work000001');
        shellNotifier.toggleSidebarLabelsCollapsed();
        shellNotifier.toggleSidebarLocationsCollapsed();
        await tester.pump();

        final sidebarSections = tester
            .widgetList<UiSidebarSection>(find.byType(UiSidebarSection))
            .toList(growable: false);
        final labelsSection = sidebarSections.firstWhere(
          (section) => section.title == 'Labels',
        );
        final locationsSection = sidebarSections.firstWhere(
          (section) => section.title == 'Locations',
        );
        expect(
          labelsSection.items,
          isEmpty,
          reason:
              'Collapsed Labels sidebar section must not allocate nav items',
        );
        expect(
          labelsSection.collapsedCountLabel,
          equals('2'),
          reason: 'Collapsed Labels section must preserve label count summary',
        );
        expect(
          labelsSection.collapsedActiveColorDot,
          equals(const Color(0xFF2196F3)),
          reason:
              'Collapsed Labels section must preserve active label color dot',
        );
        expect(
          locationsSection.items,
          isEmpty,
          reason:
              'Collapsed Locations sidebar section must not allocate nav items',
        );
        expect(
          locationsSection.collapsedCountLabel,
          equals('1'),
          reason: 'Collapsed Locations section must preserve location count summary',
        );
      },
    );

    testWidgets(
      'brand button and compact active-filter button avoid raw Material InkWell and support hover, keyboard focus ring, and tap',
      (tester) async {
        final previousStrategy = FocusManager.instance.highlightStrategy;
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        addTearDown(() {
          FocusManager.instance.highlightStrategy = previousStrategy;
        });

        final board = TaskBoard.evaluate(
          tasks: const <TaskItem>[],
          labels: const <TdfLabel>[
            TdfLabel(id: 'work000001', name: 'Work', color: '#2196F3'),
          ],
        );

        final container = await pumpLeafWidget(
          tester,
          const TierTaskShellScreen(),
          board: board,
        );

        final brandFinder = find.byKey(
          const ValueKey<String>('chrome_brand_button'),
        );
        expect(brandFinder, findsOneWidget);
        expect(
          find.descendant(of: brandFinder, matching: find.byType(InkWell)),
          findsNothing,
          reason: 'Shell brand button must not use raw Material InkWell',
        );

        // Navigate away and verify brand button returns to Tasks view on tap.
        container.read(shellProvider.notifier).openView(ShellView.settings);
        await tester.pumpAndSettle();
        await tester.tap(brandFinder);
        await tester.pumpAndSettle();
        expect(container.read(shellProvider).view, equals(ShellView.tasks));

        // Switch to compact viewport with active label filter and inspect mobile_active_filter_button.
        await tester.binding.setSurfaceSize(const Size(390, 844));
        container.read(shellProvider.notifier).selectLabelFilter('work000001');
        await tester.pumpAndSettle();

        final mobileFilterFinder = find.byKey(
          const ValueKey<String>('mobile_active_filter_button'),
        );
        expect(mobileFilterFinder, findsOneWidget);
        expect(
          find.descendant(
            of: mobileFilterFinder,
            matching: find.byType(InkWell),
          ),
          findsNothing,
          reason:
              'Mobile active-filter button must not use raw Material InkWell',
        );
        expect(
          find.descendant(
            of: mobileFilterFinder,
            matching: find.byType(FocusableActionDetector),
          ),
          findsOneWidget,
        );

        await tester.tap(mobileFilterFinder);
        await tester.pumpAndSettle();
        expect(container.read(shellProvider).activeLabelId, isNull);
      },
    );
  });
}
