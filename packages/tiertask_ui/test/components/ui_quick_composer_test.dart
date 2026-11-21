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
  group('UiQuickComposer', () {
    testWidgets(
      'anchors desktop popover upward and dismisses on outside tap without swallowing target button clicks',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        var popoverOpen = true;
        var outsideTapped = false;
        var submitted = false;
        var draftOpened = false;

        await pumpUiWidget(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: <Widget>[
                  Align(
                    alignment: Alignment.topLeft,
                    child: UiButton(
                      key: const ValueKey<String>('outside_target_btn'),
                      label: 'Outside Target',
                      onPressed: () => outsideTapped = true,
                    ),
                  ),
                  const Spacer(),
                  UiQuickComposer(
                    key: const ValueKey<String>('desktop_composer'),
                    controller: controller,
                    placeholder: 'Add a task',
                    submitLabel: '+ Add',
                    expandDraftLabel: 'Open as draft',
                    modeWidget: const Text('Mode: Queue'),
                    modeHint: 'Added to Ready or Focus',
                    draftChips: const Text('Draft chips'),
                    isPopoverOpen: popoverOpen,
                    popoverContent: const SizedBox(
                      key: ValueKey<String>('composer_popover_body'),
                      height: 120,
                      child: Text('Popover Picker'),
                    ),
                    onDismissPopover: () => setState(() => popoverOpen = false),
                    onSubmit: () => submitted = true,
                    onExpandDraft: () => draftOpened = true,
                  ),
                ],
              );
            },
          ),
          surfaceSize: const Size(1280, 720),
        );

        expect(find.text('Popover Picker'), findsOneWidget);
        final popoverBottom = tester
            .getBottomLeft(
              find.byKey(const ValueKey<String>('composer_popover_body')),
            )
            .dy;
        final composerTop = tester
            .getTopLeft(find.byKey(const ValueKey<String>('desktop_composer')))
            .dy;
        expect(
          popoverBottom,
          lessThanOrEqualTo(composerTop),
          reason: 'Desktop popover must anchor upward above the composer',
        );

        // Single outside tap both dismisses popover AND fires outside button click.
        await tester.tap(
          find.byKey(const ValueKey<String>('outside_target_btn')),
        );
        await tester.pumpAndSettle();
        expect(popoverOpen, isFalse);
        expect(
          outsideTapped,
          isTrue,
          reason: 'TapRegion outside tap must not swallow target button taps',
        );

        await tester.tap(find.text('+ Add'));
        await tester.pump();
        expect(submitted, isTrue);

        await tester.tap(find.text('Open as draft'));
        await tester.pump();
        expect(draftOpened, isTrue);
      },
    );

    testWidgets(
      'collapses to + New task on compact when collapsible and stays inline when isCollapsibleOnCompact is false',
      (tester) async {
        final taskController = TextEditingController();
        final labelController = TextEditingController();
        addTearDown(() {
          taskController.dispose();
          labelController.dispose();
        });

        await pumpUiWidget(
          tester,
          Column(
            children: <Widget>[
              UiQuickComposer(
                controller: labelController,
                placeholder: 'New label name',
                maxLength: 120,
                submitLabel: '+ Add',
                expandDraftLabel: 'Open as draft',
                isCollapsibleOnCompact: false,
                onSubmit: () {},
              ),
              const Spacer(),
              UiQuickComposer(
                controller: taskController,
                placeholder: 'Add a task',
                submitLabel: '+ Add',
                compactTriggerLabel: '+ New task',
                compactCloseTooltip: 'Close composer',
                isCollapsibleOnCompact: true,
                onSubmit: () {},
              ),
            ],
          ),
          surfaceSize: const Size(390, 800),
        );

        // Inline Labels quick-create stays visible immediately on compact.
        expect(find.text('New label name'), findsOneWidget);

        // Collapsible task composer starts collapsed behind + New task.
        expect(find.text('+ New task'), findsOneWidget);
        expect(find.text('Add a task'), findsNothing);

        await tester.tap(find.text('+ New task'));
        await tester.pumpAndSettle();
        expect(find.text('Add a task'), findsOneWidget);

        await tester.tap(find.byTooltip('Close composer'));
        await tester.pumpAndSettle();
        expect(find.text('+ New task'), findsOneWidget);
        expect(find.text('Add a task'), findsNothing);
      },
    );
  });
}
