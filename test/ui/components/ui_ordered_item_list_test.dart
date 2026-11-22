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
import 'package:tiertask/ui/components/ui_ordered_item_list.dart';

import '../test_helpers.dart';

void main() {
  group('UiOrderedItemList', () {
    testWidgets(
      'renders header, boundary-disabled reorder buttons, editing highlight, and edit/delete callbacks',
      (tester) async {
        final items = <String>['Alpha', 'Beta', 'Gamma'];
        (int, int)? lastReorder;
        int? editedIndex;
        int? deletedIndex;

        await pumpUiWidget(
          tester,
          SizedBox(
            width: 480,
            child: UiOrderedItemList<String>(
              title: 'Subtasks',
              countLabel: '1 / 3',
              items: items,
              editingIndex: 1,
              itemKey: (item, index) => ValueKey<String>('item_$item'),
              itemBuilder: (context, item, index, isEditing) =>
                  Text(isEditing ? '$item (editing)' : item),
              onReorder: (oldIndex, newIndex) =>
                  lastReorder = (oldIndex, newIndex),
              moveUpTooltip: 'Move up',
              moveDownTooltip: 'Move down',
              onEdit: (_, index) => editedIndex = index,
              editTooltip: 'Edit item',
              onDelete: (_, index) => deletedIndex = index,
              deleteTooltip: 'Delete item',
              addBar: const Text('Add subtask bar'),
              footer: const Text('Auto-finish row'),
            ),
          ),
        );

        expect(find.text('Subtasks'), findsOneWidget);
        expect(find.text('1 / 3'), findsOneWidget);
        expect(find.text('Beta (editing)'), findsOneWidget);
        expect(find.text('Add subtask bar'), findsOneWidget);
        expect(find.text('Auto-finish row'), findsOneWidget);

        // Move up on index 0 is disabled; Move up on index 1 moves 1 -> 0.
        final moveUpButtons = find.byTooltip('Move up');
        expect(moveUpButtons, findsNWidgets(3));
        await tester.tap(moveUpButtons.first);
        await tester.pump();
        expect(lastReorder, isNull);

        await tester.tap(moveUpButtons.at(1));
        await tester.pump();
        expect(lastReorder, equals((1, 0)));

        // Move down on last index (2) is disabled.
        lastReorder = null;
        final moveDownButtons = find.byTooltip('Move down');
        await tester.tap(moveDownButtons.last);
        await tester.pump();
        expect(lastReorder, isNull);

        await tester.tap(find.byTooltip('Edit item').at(1));
        await tester.pump();
        expect(editedIndex, equals(1));

        await tester.tap(find.byTooltip('Delete item').at(2));
        await tester.pump();
        expect(deletedIndex, equals(2));
      },
    );

    testWidgets(
      'omits reorder arrows when onReorder is null and shows emptyText when list is empty',
      (tester) async {
        await pumpUiWidget(
          tester,
          UiOrderedItemList<String>(
            items: const <String>[],
            itemKey: (item, index) => ValueKey<String>('$item-$index'),
            itemBuilder: (_, item, _, _) => Text(item),
            emptyText: 'No history entries yet',
            moveUpTooltip: 'Move up',
            moveDownTooltip: 'Move down',
          ),
        );

        expect(find.text('No history entries yet'), findsOneWidget);
        expect(find.byTooltip('Move up'), findsNothing);
        expect(find.byTooltip('Move down'), findsNothing);
      },
    );

    testWidgets(
      'virtualizes large maxHeight lists lazily without shrinkWrap while keeping compact height for small lists',
      (tester) async {
        var largeBuiltCount = 0;
        final largeItems = <String>[
          for (var i = 0; i < 500; i++) 'History entry #$i',
        ];

        await pumpUiWidget(
          tester,
          SingleChildScrollView(
            child: SizedBox(
              width: 480.0,
              child: UiOrderedItemList<String>(
                items: largeItems,
                maxHeight: 200.0,
                itemKey: (item, index) => ValueKey<String>('large_$index'),
                itemBuilder: (_, item, _, _) {
                  largeBuiltCount++;
                  return Text(item);
                },
              ),
            ),
          ),
        );

        final largeListView = tester.widget<ListView>(find.byType(ListView));
        expect(
          largeListView.shrinkWrap,
          isFalse,
          reason: 'maxHeight list overflowing viewport must disable shrinkWrap for lazy virtualization',
        );
        expect(
          largeBuiltCount,
          lessThan(40),
          reason: '500-item bounded ordered list must lazily build only visible + cached rows',
        );

        await pumpUiWidget(
          tester,
          SingleChildScrollView(
            child: SizedBox(
              width: 480.0,
              child: UiOrderedItemList<String>(
                items: const <String>['One', 'Two'],
                maxHeight: 200.0,
                itemKey: (item, index) => ValueKey<String>('small_$index'),
                itemBuilder: (_, item, _, _) => Text(item),
              ),
            ),
          ),
        );

        expect(
          tester.getSize(find.byType(ListView)).height,
          lessThan(200.0),
          reason:
              'Small bounded ordered list must retain compact content height',
        );
      },
    );

    testWidgets(
      'applies explicit EdgeInsets.zero on internal ListView so OS MediaQuery padding never injects phantom gaps',
      (tester) async {
        tester.view.padding = const FakeViewPadding(top: 48.0, bottom: 24.0);
        tester.view.viewPadding = const FakeViewPadding(
          top: 48.0,
          bottom: 24.0,
        );
        addTearDown(() {
          tester.view.resetPadding();
          tester.view.resetViewPadding();
        });

        await pumpUiWidget(
          tester,
          SizedBox(
            width: 390.0,
            child: UiOrderedItemList<String>(
              items: const <String>['Alpha'],
              itemKey: (_, index) => ValueKey<String>('edge_$index'),
              itemBuilder: (_, item, _, _) => Text(item),
            ),
          ),
          surfaceSize: const Size(390.0, 844.0),
          wrapInScaffold: false,
        );

        final listView = tester.widget<ListView>(find.byType(ListView));
        expect(
          listView.padding,
          equals(EdgeInsets.zero),
          reason: 'UiOrderedItemList must set EdgeInsets.zero on internal ListView to avoid phantom MediaQuery padding',
        );
      },
    );

    testWidgets(
      'aligns headerTrailing flush with the right edge of the ordered list',
      (tester) async {
        await pumpUiWidget(
          tester,
          SizedBox(
            key: const ValueKey<String>('ordered_list_host'),
            width: 640.0,
            child: UiOrderedItemList<String>(
              title: 'Links',
              countLabel: '1 / 20',
              headerTrailing: const SizedBox(
                key: ValueKey<String>('ordered_header_trailing'),
                width: 30.0,
                height: 30.0,
              ),
              items: const <String>['Alpha'],
              itemKey: (_, index) => ValueKey<String>('hdr_$index'),
              itemBuilder: (_, item, _, _) => Text(item),
            ),
          ),
        );

        final hostRight = tester
            .getRect(find.byKey(const ValueKey<String>('ordered_list_host')))
            .right;
        final trailingRight = tester
            .getRect(
              find.byKey(const ValueKey<String>('ordered_header_trailing')),
            )
            .right;
        expect(
          trailingRight,
          closeTo(hostRight, 0.5),
          reason:
              'UiOrderedItemList headerTrailing must align flush to right edge',
        );
      },
    );
  });
}
