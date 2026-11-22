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

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/ui/layout/ui_adaptive_app_shell.dart';
import 'package:tiertask/ui/primitives/ui_banner.dart';
import 'package:tiertask/ui/primitives/ui_button.dart';

import '../test_helpers.dart';

void main() {
  group('UiAdaptiveAppShell', () {
    testWidgets(
      'renders persistent 244px sidebar above 720px and below-chrome drawer at or below 720px',
      (tester) async {
        const breakpointCases = <(double, bool)>[
          (390.0, true),
          (720.0, true),
          (721.0, false),
          (820.0, false),
          (821.0, false),
          (1280.0, false),
        ];

        for (final (width, expectCompact) in breakpointCases) {
          var drawerOpen = false;
          await pumpUiWidget(
            tester,
            StatefulBuilder(
              builder: (context, setState) {
                return UiAdaptiveAppShell(
                  brand: const Text('TierTask'),
                  workspaceTrigger: const Text('Personal'),
                  trailingActions: const <Widget>[Text('Sync')],
                  sidebarHeader: const Text('Compact Workspace Card'),
                  sidebarBody: const Text('Sidebar Nav'),
                  sidebarFooter: const Text('Version 0.4.0'),
                  body: const Text('Main Pane'),
                  isDrawerOpen: drawerOpen,
                  onToggleDrawer: () =>
                      setState(() => drawerOpen = !drawerOpen),
                  menuOpenTooltip: 'Open menu',
                  menuCloseTooltip: 'Close menu',
                );
              },
            ),
            surfaceSize: Size(width, 800),
            wrapInScaffold: false,
          );

          if (expectCompact) {
            expect(
              find.byTooltip('Open menu'),
              findsOneWidget,
              reason: 'Compact width $width must display menu toggle button',
            );
            expect(
              find.text('Personal'),
              findsNothing,
              reason: 'Compact width $width must hide desktop workspace pill',
            );
            expect(
              find.text('Sidebar Nav'),
              findsNothing,
              reason: 'Compact width $width hides drawer when closed',
            );

            // Open drawer and verify top chrome menu toggle remains uncovered and clickable.
            await tester.tap(find.byTooltip('Open menu'));
            await tester.pumpAndSettle();
            expect(
              find.text('Sidebar Nav'),
              findsOneWidget,
              reason: 'Compact width $width shows drawer content when open',
            );
            expect(
              find.text('Compact Workspace Card'),
              findsOneWidget,
              reason: 'Compact width $width shows sidebarHeader inside drawer',
            );

            // Verify drawer anchors strictly below the 62px top chrome bar.
            final menuTop = tester.getTopLeft(find.byTooltip('Close menu')).dy;
            expect(menuTop, lessThan(62.0));
            await tester.tap(find.byTooltip('Close menu'));
            await tester.pumpAndSettle();
            expect(
              find.text('Sidebar Nav'),
              findsNothing,
              reason:
                  'Top chrome close toggle remains clickable over open drawer',
            );
          } else {
            expect(
              find.byTooltip('Open menu'),
              findsNothing,
              reason: 'Width $width must hide compact menu toggle',
            );
            expect(
              find.text('Personal'),
              findsOneWidget,
              reason: 'Width $width must display desktop workspace pill',
            );
            expect(
              find.text('Sidebar Nav'),
              findsOneWidget,
              reason: 'Width $width must render persistent left sidebar',
            );
            expect(
              find.text('Compact Workspace Card'),
              findsNothing,
              reason: 'Width $width hides compact-only sidebarHeader',
            );
          }
        }
      },
    );

    testWidgets(
      'collapses compact chrome siblings during search and swaps brand for mobileActiveFilter',
      (tester) async {
        await pumpUiWidget(
          tester,
          const UiAdaptiveAppShell(
            brand: Text('TierTask'),
            mobileActiveFilter: Text('Active Label: Work'),
            searchWidget: Text('Search Box'),
            trailingActions: <Widget>[Text('Sync')],
            isSearchOpen: false,
            sidebarBody: SizedBox.shrink(),
            body: Text('Body'),
            menuOpenTooltip: 'Open menu',
            menuCloseTooltip: 'Close menu',
          ),
          surfaceSize: const Size(390, 800),
          wrapInScaffold: false,
        );
        expect(find.text('Active Label: Work'), findsOneWidget);
        expect(find.text('TierTask'), findsNothing);

        await pumpUiWidget(
          tester,
          const UiAdaptiveAppShell(
            brand: Text('TierTask'),
            mobileActiveFilter: Text('Active Label: Work'),
            searchWidget: Text('Full Width Search'),
            trailingActions: <Widget>[Text('Sync')],
            isSearchOpen: true,
            sidebarBody: SizedBox.shrink(),
            body: Text('Body'),
            menuOpenTooltip: 'Open menu',
            menuCloseTooltip: 'Close menu',
          ),
          surfaceSize: const Size(390, 800),
          wrapInScaffold: false,
        );
        expect(find.text('Full Width Search'), findsOneWidget);
        expect(find.text('Sync'), findsNothing);
        expect(find.text('Active Label: Work'), findsNothing);
        expect(find.byTooltip('Open menu'), findsNothing);
      },
    );

    testWidgets(
      'decouples floatingNotice above pinned bottomDock, supports lazy SliverList body, and preserves sidebar scroll',
      (tester) async {
        final sidebarController = ScrollController();
        addTearDown(sidebarController.dispose);

        await pumpUiWidget(
          tester,
          UiAdaptiveAppShell(
            brand: const Text('TierTask'),
            sidebarScrollController: sidebarController,
            sidebarBody: Column(
              children: <Widget>[
                for (var i = 0; i < 40; i++)
                  SizedBox(height: 36, child: Text('Sidebar item $i')),
              ],
            ),
            body: CustomScrollView(
              slivers: <Widget>[
                SliverList.builder(
                  itemCount: 30,
                  itemBuilder: (context, index) => SizedBox(
                    key: ValueKey<String>('lazy_row_$index'),
                    height: 48,
                    child: Text('Task $index'),
                  ),
                ),
              ],
            ),
            floatingNotice: const UiBanner(
              key: ValueKey<String>('floating_toast'),
              variant: UiBannerVariant.toast,
              message: 'Completed task',
            ),
            bottomDock: const SizedBox(
              key: ValueKey<String>('pinned_dock'),
              height: 52,
              child: Text('Quick Add Dock'),
            ),
          ),
          surfaceSize: const Size(1280, 700),
          wrapInScaffold: false,
        );

        final toastBottom = tester
            .getBottomLeft(find.byKey(const ValueKey<String>('floating_toast')))
            .dy;
        final dockTop = tester
            .getTopLeft(find.byKey(const ValueKey<String>('pinned_dock')))
            .dy;
        expect(
          toastBottom,
          lessThanOrEqualTo(dockTop),
          reason: 'Floating notice must sit strictly above pinned bottomDock',
        );

        sidebarController.jumpTo(120.0);
        await tester.pump();
        expect(sidebarController.offset, equals(120.0));
        expect(find.text('Task 0'), findsOneWidget);
      },
    );

    testWidgets(
      'places buildBadge after workspaceTrigger on desktop and beside brand on compact',
      (tester) async {
        // Desktop (> 720px): Brand -> Workspace -> Build Badge.
        for (final width in const <double>[721.0, 820.0, 821.0, 1280.0]) {
          await pumpUiWidget(
            tester,
            const UiAdaptiveAppShell(
              brand: Text('TierTask'),
              workspaceTrigger: Text('Work'),
              buildBadge: Text('DEV'),
              trailingActions: <Widget>[Text('Synced')],
              sidebarBody: SizedBox.shrink(),
              body: Text('Main'),
            ),
            surfaceSize: Size(width, 800),
            wrapInScaffold: false,
          );

          final brandRight = tester.getTopRight(find.text('TierTask')).dx;
          final workspaceRect = tester.getRect(find.text('Work'));
          final badgeRect = tester.getRect(find.text('DEV'));
          expect(
            workspaceRect.left - brandRight,
            greaterThanOrEqualTo(18.0),
            reason:
                'Width $width must maintain 18px chrome gap between brand and workspace pill',
          );
          expect(
            badgeRect.left,
            greaterThan(workspaceRect.right),
            reason:
                'Width $width must place buildBadge strictly to the right of workspaceTrigger',
          );
        }

        // Compact (<= 720px): hidden workspaceTrigger, buildBadge beside brand when no active filter.
        for (final width in const <double>[390.0, 720.0]) {
          await pumpUiWidget(
            tester,
            const UiAdaptiveAppShell(
              brand: Text('TierTask'),
              workspaceTrigger: Text('Work'),
              buildBadge: Text('DEV'),
              trailingActions: <Widget>[Text('Synced')],
              sidebarBody: SizedBox.shrink(),
              body: Text('Main'),
              menuOpenTooltip: 'Open menu',
              menuCloseTooltip: 'Close menu',
            ),
            surfaceSize: Size(width, 800),
            wrapInScaffold: false,
          );
          expect(
            find.text('Work'),
            findsNothing,
            reason: 'Compact width $width hides desktop workspaceTrigger',
          );
          expect(
            find.text('DEV'),
            findsOneWidget,
            reason: 'Compact width $width displays buildBadge beside brand',
          );
          expect(
            tester.getTopLeft(find.text('DEV')).dx,
            greaterThan(tester.getTopRight(find.text('TierTask')).dx),
            reason: 'Compact width $width places buildBadge to right of brand',
          );
        }

        // Compact with mobileActiveFilter hides buildBadge along with brand.
        await pumpUiWidget(
          tester,
          const UiAdaptiveAppShell(
            brand: Text('TierTask'),
            mobileActiveFilter: Text('Filter: Work'),
            workspaceTrigger: Text('Work'),
            buildBadge: Text('DEV'),
            sidebarBody: SizedBox.shrink(),
            body: Text('Main'),
            menuOpenTooltip: 'Open menu',
            menuCloseTooltip: 'Close menu',
          ),
          surfaceSize: const Size(390, 800),
          wrapInScaffold: false,
        );
        expect(find.text('Filter: Work'), findsOneWidget);
        expect(find.text('DEV'), findsNothing);
      },
    );

    testWidgets(
      'supports desktop chrome drag and double-tap on empty chrome area without delaying interactive buttons',
      (tester) async {
        var dragCount = 0;
        var doubleTapCount = 0;
        var syncTapCount = 0;
        var closeTapCount = 0;

        await pumpUiWidget(
          tester,
          UiAdaptiveAppShell(
            brand: const Text('TierTask'),
            workspaceTrigger: const Text('Work'),
            trailingActions: <Widget>[
              UiButton(
                key: const ValueKey<String>('test_sync_button'),
                label: 'Synced',
                variant: UiButtonVariant.secondary,
                density: UiButtonDensity.chrome,
                onPressed: () => syncTapCount++,
              ),
              UiButton(
                key: const ValueKey<String>('test_close_button'),
                leadingIcon: Icons.close_rounded,
                variant: UiButtonVariant.icon,
                density: UiButtonDensity.standard,
                isDangerHover: true,
                tooltip: 'Close TierTask',
                onPressed: () => closeTapCount++,
              ),
            ],
            onChromeDragStart: () => dragCount++,
            onChromeDoubleTap: () => doubleTapCount++,
            sidebarBody: const SizedBox.shrink(),
            body: const Text('Main'),
          ),
          surfaceSize: const Size(1280, 800),
          wrapInScaffold: false,
        );

        final dragRegionFinder = find.byKey(
          const ValueKey<String>('ui_top_chrome_drag_region'),
        );
        expect(dragRegionFinder, findsOneWidget);

        // Single-tapping interactive buttons fires immediately without waiting for double-tap timeout.
        await tester.tap(
          find.byKey(const ValueKey<String>('test_sync_button')),
        );
        await tester.pump();
        expect(
          syncTapCount,
          equals(1),
          reason: 'Sync button tap must fire immediately on single pump',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('test_close_button')),
        );
        await tester.pump();
        expect(
          closeTapCount,
          equals(1),
          reason: 'Close button tap must fire immediately on single pump',
        );
        expect(dragCount, equals(0));
        expect(doubleTapCount, equals(0));

        // Dragging empty top-bar spacer starts native window move.
        const emptyChromeCenter = Offset(640, 31);
        await tester.dragFrom(emptyChromeCenter, const Offset(40, 12));
        await tester.pumpAndSettle();
        expect(
          dragCount,
          equals(1),
          reason:
              'Dragging empty top chrome space must invoke onChromeDragStart',
        );
        expect(doubleTapCount, equals(0));

        // Double-tapping empty top-bar spacer toggles maximize/restore.
        await tester.tapAt(emptyChromeCenter);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(emptyChromeCenter);
        await tester.pumpAndSettle();
        expect(
          doubleTapCount,
          equals(1),
          reason: 'Double-tapping empty top chrome space must invoke onChromeDoubleTap',
        );

        // Omitting desktop callbacks omits the drag region completely (e.g. Android).
        await pumpUiWidget(
          tester,
          const UiAdaptiveAppShell(
            brand: Text('TierTask'),
            sidebarBody: SizedBox.shrink(),
            body: Text('Main'),
          ),
          surfaceSize: const Size(1280, 800),
          wrapInScaffold: false,
        );
        expect(
          dragRegionFinder,
          findsNothing,
          reason: 'Top chrome drag region must not mount when drag/double-tap callbacks are absent',
        );
      },
    );

    testWidgets(
      'scrolls sidebarFooter inside sidebar when content overflows and aligns it to the bottom when content fits',
      (tester) async {
        const cases = <(String, Size, bool)>[
          ('desktop persistent sidebar', Size(1280, 500), false),
          ('compact slide-over drawer', Size(390, 500), true),
        ];

        for (final (label, size, isCompact) in cases) {
          final overflowingController = ScrollController();
          addTearDown(overflowingController.dispose);

          await pumpUiWidget(
            tester,
            UiAdaptiveAppShell(
              brand: const Text('TierTask'),
              sidebarHeader: const Text('Compact Workspace'),
              sidebarScrollController: overflowingController,
              isDrawerOpen: isCompact,
              sidebarBody: Column(
                children: <Widget>[
                  for (var i = 0; i < 24; i++)
                    SizedBox(height: 36.0, child: Text('Nav item $i')),
                ],
              ),
              sidebarFooter: const Text(
                'Version 0.4.0',
                key: ValueKey<String>('test_sidebar_footer'),
              ),
              body: const Text('Main'),
            ),
            surfaceSize: size,
            wrapInScaffold: false,
          );

          final footerFinder = find.byKey(
            const ValueKey<String>('test_sidebar_footer'),
          );
          final initialFooterTop = tester.getTopLeft(footerFinder).dy;
          expect(
            overflowingController.position.maxScrollExtent,
            greaterThan(0.0),
            reason: '$label with 24 nav items must scroll vertically',
          );
          expect(
            initialFooterTop,
            greaterThan(size.height),
            reason:
                '$label sidebarFooter must not be sticky above overflowing content at scroll offset 0',
          );

          final maxExtent = overflowingController.position.maxScrollExtent;
          overflowingController.jumpTo(maxExtent);
          await tester.pump();

          final scrolledFooterRect = tester.getRect(footerFinder);
          expect(
            initialFooterTop - scrolledFooterRect.top,
            closeTo(maxExtent, 0.5),
            reason: '$label sidebarFooter must move with sidebar scroll offset',
          );
          expect(
            scrolledFooterRect.bottom,
            closeTo(size.height - 14.0, 0.5),
            reason:
                '$label sidebarFooter must rest on the 14px bottom scroll padding at max scroll',
          );

          // Short content: footer aligns to the bottom (CSS margin-top: auto) without scrolling.
          final fittingController = ScrollController();
          addTearDown(fittingController.dispose);

          await pumpUiWidget(
            tester,
            UiAdaptiveAppShell(
              brand: const Text('TierTask'),
              sidebarHeader: const Text('Compact Workspace'),
              sidebarScrollController: fittingController,
              isDrawerOpen: isCompact,
              sidebarBody: const SizedBox(height: 80.0, child: Text('Short')),
              sidebarFooter: const Text(
                'Version 0.4.0',
                key: ValueKey<String>('test_sidebar_footer'),
              ),
              body: const Text('Main'),
            ),
            surfaceSize: size,
            wrapInScaffold: false,
          );

          expect(
            fittingController.position.maxScrollExtent,
            equals(0.0),
            reason: '$label with short content must not overflow vertically',
          );
          expect(
            tester.getRect(footerFinder).bottom,
            closeTo(size.height - 14.0, 0.5),
            reason:
                '$label with short content must push sidebarFooter to the bottom (margin-top: auto)',
          );

          // Omitting sidebarFooter keeps top content anchored at the top padding.
          await pumpUiWidget(
            tester,
            UiAdaptiveAppShell(
              brand: const Text('TierTask'),
              isDrawerOpen: isCompact,
              sidebarBody: const SizedBox(
                key: ValueKey<String>('test_sidebar_top_only'),
                height: 40.0,
                child: Text('Top Only'),
              ),
              body: const Text('Main'),
            ),
            surfaceSize: size,
            wrapInScaffold: false,
          );
          expect(
            tester
                .getTopLeft(
                  find.byKey(const ValueKey<String>('test_sidebar_top_only')),
                )
                .dy,
            closeTo(76.0, 1.0),
            reason:
                '$label without sidebarFooter must keep sidebarBody aligned at top padding below 62px chrome',
          );
        }
      },
    );
  });
}
