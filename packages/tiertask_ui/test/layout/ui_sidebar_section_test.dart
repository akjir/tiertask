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
  group('UiSidebarSection', () {
    testWidgets('renders static group with split and single-button nav rows', (
      tester,
    ) async {
      var primaryTapped = false;
      var trailingTapped = false;

      await pumpUiWidget(
        tester,
        SizedBox(
          width: 244,
          child: UiSidebarSection(
            title: 'Tasks',
            items: <UiSidebarNavItem>[
              UiSidebarNavItem(
                id: 'focus',
                label: 'Focus',
                icon: Icons.bolt_outlined,
                countLabel: '2',
                isSelected: true,
                onTap: () => primaryTapped = true,
              ),
              UiSidebarNavItem(
                id: 'office',
                label: 'Office',
                subtitle: 'Scoped Queue',
                colorDot: const Color(0xFF2196F3),
                countLabel: '4',
                onTap: () {},
                trailingIcon: Icons.info_outline_rounded,
                trailingTooltip: 'Label details',
                onTrailingTap: () => trailingTapped = true,
              ),
              const UiSidebarNavItem(
                id: 'home_loc',
                label: 'Home',
                icon: Icons.location_on_outlined,
                countLabel: '1',
                trailingHintIcon: Icons.info_outline_rounded,
              ),
            ],
          ),
        ),
      );

      expect(find.text('TASKS'), findsOneWidget);
      expect(find.text('Focus'), findsOneWidget);
      expect(find.text('Scoped Queue'), findsOneWidget);

      await tester.tap(find.text('Focus'));
      await tester.pump();
      expect(primaryTapped, isTrue);

      await tester.tap(find.byTooltip('Label details'));
      await tester.pump();
      expect(trailingTapped, isTrue);
    });

    testWidgets(
      'handles collapsible header counts, auto-expand on filter toggle, filter empty state, clear-on-collapse, and responsive action button size',
      (tester) async {
        var collapsed = true;
        var filterOpen = false;
        var query = '';
        var manageTapped = false;

        Widget buildHarness() {
          return StatefulBuilder(
            builder: (context, setState) {
              final allItems = <UiSidebarNavItem>[
                const UiSidebarNavItem(id: 'work', label: 'Work'),
                const UiSidebarNavItem(id: 'home', label: 'Home'),
              ];
              final filtered = query.isEmpty
                  ? allItems
                  : allItems
                        .where(
                          (item) => item.label.toLowerCase().contains(
                            query.toLowerCase(),
                          ),
                        )
                        .toList();
              return SizedBox(
                width: 244,
                child: UiSidebarSection(
                  title: 'Labels',
                  isCollapsible: true,
                  isCollapsed: collapsed,
                  onToggleCollapse: () =>
                      setState(() => collapsed = !collapsed),
                  collapsedCountLabel: '2',
                  collapsedActiveColorDot: const Color(0xFF4CAF50),
                  isFilterable: true,
                  isFilterOpen: filterOpen,
                  onToggleFilter: () =>
                      setState(() => filterOpen = !filterOpen),
                  filterQuery: query,
                  onFilterChanged: (next) => setState(() => query = next),
                  filterPlaceholder: 'Filter labels',
                  filterClearTooltip: 'Clear filter',
                  filterEmptyText: 'No matching labels',
                  onManage: () => manageTapped = true,
                  filterTooltip: 'Filter labels',
                  manageTooltip: 'Manage labels',
                  collapseTooltip: 'Collapse labels',
                  expandTooltip: 'Expand labels',
                  items: filtered,
                ),
              );
            },
          );
        }

        // Desktop: collapsed shows count + dot, header buttons are 26px.
        await pumpUiWidget(
          tester,
          buildHarness(),
          surfaceSize: const Size(1280, 800),
        );
        expect(find.text('2'), findsOneWidget);
        expect(find.text('Work'), findsNothing);
        expect(
          tester.getSize(find.byTooltip('Filter labels')).height,
          equals(26.0),
        );

        // Toggling Filter while collapsed auto-expands and opens filter field.
        await tester.tap(find.byTooltip('Filter labels'));
        await tester.pumpAndSettle();
        expect(collapsed, isFalse);
        expect(filterOpen, isTrue);
        expect(find.text('Work'), findsOneWidget);

        // Non-matching query displays filterEmptyText.
        await tester.enterText(find.byType(TextField), 'zzzz');
        await tester.pump();
        expect(find.text('No matching labels'), findsOneWidget);

        // Collapsing clears query and closes filter.
        await tester.tap(find.byTooltip('Collapse labels'));
        await tester.pumpAndSettle();
        expect(collapsed, isTrue);
        expect(filterOpen, isFalse);
        expect(query, isEmpty);

        // Manage callback fires.
        await tester.tap(find.byTooltip('Manage labels'));
        await tester.pump();
        expect(manageTapped, isTrue);

        // Compact viewport enlarges header icon buttons to 34px.
        await pumpUiWidget(
          tester,
          buildHarness(),
          surfaceSize: const Size(390, 800),
        );
        expect(
          tester.getSize(find.byTooltip('Filter labels')).height,
          equals(34.0),
        );
      },
    );
  });
}
