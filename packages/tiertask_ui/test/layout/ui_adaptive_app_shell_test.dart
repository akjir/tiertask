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
import 'package:tiertask_ui/tiertask_ui.dart';

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
  });
}
