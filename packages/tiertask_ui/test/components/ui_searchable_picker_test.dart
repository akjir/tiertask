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
import 'package:tiertask_ui/tiertask_ui.dart';

import '../test_helpers.dart';

void main() {
  group('UiSearchablePicker', () {
    testWidgets(
      'supports multi-select, conditional scope pills, inline create, disabled cycle rows, arrow/Enter navigation, and two-step Escape',
      (tester) async {
        final selectedIds = <String>{'work'};
        var activeScope = 'all';
        var createdName = '';
        var closed = false;
        var infoOptionId = '';
        final scrollController = ScrollController();
        addTearDown(scrollController.dispose);

        final allOptions = <UiPickerOption<String>>[
          const UiPickerOption<String>(
            id: 'work',
            value: 'work',
            label: 'Work',
            colorDot: Color(0xFF2196F3),
            badgeLabel: 'Scoped Queue',
            countLabel: '3',
            hasInfoAction: true,
          ),
          const UiPickerOption<String>(
            id: 'home',
            value: 'home',
            label: 'Home',
            colorDot: Color(0xFF4CAF50),
            countLabel: '1',
          ),
          const UiPickerOption<String>(
            id: 'cycle',
            value: 'cycle',
            label: 'Blocked loop',
            enabled: false,
            disabledHint: 'Cycle prevented',
          ),
        ];

        await pumpUiWidget(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                width: 420,
                child: UiSearchablePicker<String>(
                  options: allOptions,
                  selectedIds: selectedIds,
                  scrollController: scrollController,
                  scopeFilters: const <UiPickerScopeFilter>[
                    UiPickerScopeFilter(id: 'all', label: 'All'),
                    UiPickerScopeFilter(id: 'scoped', label: 'Scoped'),
                    UiPickerScopeFilter(id: 'global', label: 'Global'),
                  ],
                  activeScopeId: activeScope,
                  onScopeChanged: (id) => setState(() => activeScope = id),
                  searchPlaceholder: 'Search labels',
                  searchClearTooltip: 'Clear search',
                  infoTooltip: 'Open label hub',
                  removeChipTooltip: (option) => 'Remove ${option.label}',
                  emptyText: 'No matching labels',
                  inlineCreateLabel: (query) => 'Create & assign "$query"',
                  onInlineCreate: (query) =>
                      setState(() => createdName = query),
                  onOptionInfo: (option) => infoOptionId = option.id,
                  onRequestClose: () => closed = true,
                  autoFocusSearch: true,
                  onToggleOption: (option) {
                    setState(() {
                      if (!selectedIds.remove(option.id)) {
                        selectedIds.add(option.id);
                      }
                    });
                  },
                ),
              );
            },
          ),
        );

        // Scope filter pills appear when >= 2 scopes exist.
        expect(find.text('All'), findsOneWidget);
        expect(find.text('Scoped'), findsOneWidget);
        expect(find.text('Global'), findsOneWidget);
        expect(find.text('Cycle prevented'), findsOneWidget);

        // Info action triggers callback.
        await tester.tap(find.byTooltip('Open label hub'));
        await tester.pump();
        expect(infoOptionId, equals('work'));

        // Keyboard ArrowDown -> Enter toggles 'Home' (index 1).
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(selectedIds, contains('home'));

        // Typing unique query exposes inline create row; Enter creates.
        await tester.enterText(find.byType(TextField), 'Urgent');
        await tester.pump();
        expect(find.text('Create & assign "Urgent"'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(createdName, equals('Urgent'));

        // First Escape clears query without closing; second Escape calls onRequestClose.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(closed, isFalse);
        expect(find.text('Create & assign "Urgent"'), findsNothing);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(closed, isTrue);
      },
    );

    testWidgets(
      'supports single-select, hides scope pills when < 2, hides chips when showSelectedChips is false, and disables autofocus in compact sheet mode',
      (tester) async {
        var selectedId = 'a';
        await pumpUiWidget(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                width: 360,
                height: 400,
                child: UiSearchablePicker<String>(
                  selectionMode: UiPickerSelectionMode.single,
                  showSelectedChips: false,
                  autoFocusSearch: true,
                  isCompactSheet: true,
                  scopeFilters: const <UiPickerScopeFilter>[
                    UiPickerScopeFilter(id: 'only', label: 'Only One'),
                  ],
                  options: const <UiPickerOption<String>>[
                    UiPickerOption<String>(
                      id: 'a',
                      value: 'a',
                      label: 'tasks.tdf',
                      isMonospace: true,
                    ),
                    UiPickerOption<String>(
                      id: 'b',
                      value: 'b',
                      label: 'work.tdf',
                      isMonospace: true,
                    ),
                  ],
                  selectedIds: <String>{selectedId},
                  emptyText: 'No files',
                  onToggleOption: (option) =>
                      setState(() => selectedId = option.id),
                ),
              );
            },
          ),
          surfaceSize: const Size(390, 800),
        );

        expect(find.text('Only One'), findsNothing);

        // Compact bottom sheet mode MUST NOT auto-focus search input.
        final searchField = tester.widget<TextField>(find.byType(TextField));
        expect(searchField.autofocus, isFalse);
        expect(
          FocusManager.instance.primaryFocus?.context?.widget,
          isNot(isA<EditableText>()),
        );

        await tester.tap(find.text('work.tdf'));
        await tester.pump();
        expect(selectedId, equals('b'));
      },
    );

    testWidgets(
      'honors custom searchMaxLength for inline creation length bounds',
      (tester) async {
        var created = '';
        await pumpUiWidget(
          tester,
          SizedBox(
            width: 420,
            child: UiSearchablePicker<String>(
              options: const <UiPickerOption<String>>[],
              selectedIds: const <String>{},
              searchMaxLength: 500,
              emptyText: 'No matching labels',
              inlineCreateLabel: (query) => 'Create "$query"',
              onInlineCreate: (query) => created = query,
              onToggleOption: (_) {},
            ),
          ),
        );

        final validLong = 'a' * 200;
        await tester.enterText(find.byType(TextField), validLong);
        await tester.pump();
        expect(
          find.text('Create "$validLong"'),
          findsOneWidget,
          reason: 'Inline creation must allow queries above 120 when searchMaxLength is 500',
        );
        await tester.tap(find.text('Create "$validLong"'));
        await tester.pump();
        expect(created, equals(validLong));

        final atLimit = 'b' * 500;
        await tester.enterText(find.byType(TextField), atLimit);
        await tester.pump();
        expect(
          find.text('Create "$atLimit"'),
          findsOneWidget,
          reason: 'Inline creation must allow queries at exact searchMaxLength',
        );
      },
    );
  });
}
