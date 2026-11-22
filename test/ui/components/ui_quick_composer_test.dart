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
import 'package:tiertask/ui/components/ui_quick_composer.dart';
import 'package:tiertask/ui/primitives/ui_button.dart';
import 'package:tiertask/ui/tokens/ui_spacing_tokens.dart';

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
                    placeholder: 'New task...',
                    submitLabel: 'Add',
                    expandDraftLabel: 'Open as draft',
                    modeWidget: const Text('Mode: Queue'),
                    modeHint: 'Append at the end of the active queue.',
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

        // Placement hint sits outside and strictly below the bordered composer card.
        final cardFinder = find.descendant(
          of: find.byKey(const ValueKey<String>('desktop_composer')),
          matching: find.byKey(
            const ValueKey<String>('ui_quick_composer_card'),
          ),
        );
        expect(cardFinder, findsOneWidget);
        final cardBottom = tester.getBottomLeft(cardFinder).dy;
        final hintTop = tester
            .getTopLeft(find.text('Append at the end of the active queue.'))
            .dy;
        expect(
          hintTop,
          greaterThanOrEqualTo(cardBottom),
          reason: 'modeHint must render outside and below the bordered card',
        );

        // Submit button uses 40px standard primary density with leading + icon.
        final submitButtonFinder = find.ancestor(
          of: find.text('Add'),
          matching: find.byType(UiButton),
        );
        final submitButton = tester.widget<UiButton>(submitButtonFinder);
        expect(submitButton.variant, equals(UiButtonVariant.primary));
        expect(submitButton.density, equals(UiButtonDensity.standard));
        expect(submitButton.leadingIcon, equals(Icons.add_rounded));
        expect(
          tester.getSize(submitButtonFinder).height,
          greaterThanOrEqualTo(UiSpacingTokens.standard.touchTarget),
        );

        // Open as draft renders as a borderless text button with icon in footer row.
        final draftButtonFinder = find.ancestor(
          of: find.text('Open as draft'),
          matching: find.byType(UiButton),
        );
        final draftButton = tester.widget<UiButton>(draftButtonFinder);
        expect(draftButton.variant, equals(UiButtonVariant.text));
        expect(draftButton.leadingIcon, equals(Icons.tune_rounded));
        expect(
          tester.getTopLeft(draftButtonFinder).dy,
          greaterThan(tester.getBottomLeft(submitButtonFinder).dy),
          reason: 'Open as draft must sit in the footer row below the top input row when draftChips is provided',
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

        await tester.tap(find.text('Add'));
        await tester.pump();
        expect(submitted, isTrue);

        await tester.tap(find.text('Open as draft'));
        await tester.pump();
        expect(draftOpened, isTrue);
      },
    );

    testWidgets(
      'supports stackModeWidget inside card while keeping modeHint below card and inline quick-create single row',
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
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              UiQuickComposer(
                key: const ValueKey<String>('inline_quick_create'),
                controller: labelController,
                placeholder: 'New label name',
                maxLength: 120,
                submitLabel: 'Add',
                expandDraftLabel: 'Open as draft',
                isCollapsibleOnCompact: false,
                onSubmit: () {},
                onExpandDraft: () {},
              ),
              const SizedBox(height: 16.0),
              UiQuickComposer(
                key: const ValueKey<String>('stacked_desktop_composer'),
                controller: taskController,
                placeholder: 'New task...',
                submitLabel: 'Add',
                expandDraftLabel: 'Open as draft',
                modeWidget: const Text('Segmented Mode'),
                stackModeWidget: true,
                modeHint: 'Append at the end of the active queue.',
                draftChips: const Text('+ Labels'),
                onSubmit: () {},
                onExpandDraft: () {},
              ),
            ],
          ),
          surfaceSize: const Size(760, 720),
        );

        final inlineDraftFinder = find.descendant(
          of: find.byKey(const ValueKey<String>('inline_quick_create')),
          matching: find.ancestor(
            of: find.text('Open as draft'),
            matching: find.byType(UiButton),
          ),
        );
        expect(
          tester.widget<UiButton>(inlineDraftFinder).variant,
          equals(UiButtonVariant.text),
          reason:
              'Inline quick-create Open as draft uses borderless text style',
        );

        final stackedCardFinder = find.descendant(
          of: find.byKey(const ValueKey<String>('stacked_desktop_composer')),
          matching: find.byKey(
            const ValueKey<String>('ui_quick_composer_card'),
          ),
        );
        final cardRect = tester.getRect(stackedCardFinder);
        final modeRect = tester.getRect(find.text('Segmented Mode'));
        final labelsRect = tester.getRect(find.text('+ Labels'));
        final hintRect = tester.getRect(
          find.text('Append at the end of the active queue.'),
        );

        expect(
          modeRect.bottom,
          lessThanOrEqualTo(cardRect.bottom),
          reason: 'Stacked modeWidget stays inside the bordered card',
        );
        expect(
          modeRect.bottom,
          lessThanOrEqualTo(labelsRect.top),
          reason: 'Stacked modeWidget appears above the footer labels row',
        );
        expect(
          hintRect.top,
          greaterThanOrEqualTo(cardRect.bottom),
          reason: 'modeHint renders outside and below the bordered card',
        );
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
                submitLabel: 'Add',
                expandDraftLabel: 'Open as draft',
                isCollapsibleOnCompact: false,
                onSubmit: () {},
              ),
              const Spacer(),
              UiQuickComposer(
                key: const ValueKey<String>('compact_task_composer'),
                controller: taskController,
                placeholder: 'New task...',
                submitLabel: 'Add',
                compactTriggerLabel: '+ New task',
                compactCloseTooltip: 'Close composer',
                modeHint: 'Append at the end of the active queue.',
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
        expect(find.text('New task...'), findsNothing);
        expect(
          find.text('Append at the end of the active queue.'),
          findsNothing,
        );

        await tester.tap(find.text('+ New task'));
        await tester.pumpAndSettle();
        expect(find.text('New task...'), findsOneWidget);
        final compactCardFinder = find.descendant(
          of: find.byKey(const ValueKey<String>('compact_task_composer')),
          matching: find.byKey(
            const ValueKey<String>('ui_quick_composer_card'),
          ),
        );
        expect(
          tester
              .getTopLeft(find.text('Append at the end of the active queue.'))
              .dy,
          greaterThanOrEqualTo(tester.getBottomLeft(compactCardFinder).dy),
          reason:
              'Compact expanded composer must render modeHint below the card',
        );

        await tester.tap(find.byTooltip('Close composer'));
        await tester.pumpAndSettle();
        expect(find.text('+ New task'), findsOneWidget);
        expect(find.text('New task...'), findsNothing);
      },
    );

    testWidgets(
      'defers internal FocusNode disposal when external focusNode attaches after mount',
      (tester) async {
        final controller = TextEditingController();
        final externalFocusNode = FocusNode();
        addTearDown(() {
          controller.dispose();
          externalFocusNode.dispose();
        });

        var useExternalFocus = false;
        late StateSetter rebuildHost;

        await pumpUiWidget(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              rebuildHost = setState;
              return UiQuickComposer(
                controller: controller,
                focusNode: useExternalFocus ? externalFocusNode : null,
                placeholder: 'New task...',
                submitLabel: 'Add',
                onSubmit: () {},
              );
            },
          ),
          surfaceSize: const Size(1024, 800),
        );

        await tester.tap(find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'Draft title');
        await tester.pump();

        rebuildHost(() => useExternalFocus = true);
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'Attaching an external FocusNode must defer disposal of the previous internal FocusNode',
        );
        externalFocusNode.requestFocus();
        await tester.pump();
        expect(externalFocusNode.hasFocus, isTrue);
      },
    );

    testWidgets(
      'guards OverlayPortalController on compact collapsed mount and across desktop-compact resizes',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(() {
          controller.dispose();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        var popoverOpen = true;
        late StateSetter rebuildHost;

        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(390, 800);

        await pumpUiWidget(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              rebuildHost = setState;
              return Align(
                alignment: Alignment.bottomCenter,
                child: UiQuickComposer(
                  controller: controller,
                  placeholder: 'New task...',
                  submitLabel: 'Add',
                  compactTriggerLabel: '+ New task',
                  isPopoverOpen: popoverOpen,
                  popoverContent: const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Text('Popover Picker Body'),
                  ),
                  onSubmit: () {},
                ),
              );
            },
          ),
          surfaceSize: const Size(390, 800),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'Mounting compact collapsed with isPopoverOpen=true must not call show() on unmounted OverlayPortal',
        );
        expect(find.text('+ New task'), findsOneWidget);
        expect(find.text('Popover Picker Body'), findsNothing);

        // Resize to desktop while popover remains open: OverlayPortal mounts and shows popover.
        tester.view.physicalSize = const Size(1280, 800);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('Popover Picker Body'),
          findsOneWidget,
          reason: 'Resizing from compact collapsed to desktop with isPopoverOpen=true must show popover',
        );

        // Resize back to compact collapsed: OverlayPortal unmounts cleanly without assertion.
        tester.view.physicalSize = const Size(390, 800);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('+ New task'), findsOneWidget);
        expect(find.text('Popover Picker Body'), findsNothing);

        // Resize back to desktop again while popover remains open: OverlayPortal re-syncs cleanly.
        tester.view.physicalSize = const Size(1280, 800);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('Popover Picker Body'),
          findsOneWidget,
          reason: 'Resizing desktop -> compact collapsed -> desktop with isPopoverOpen=true must re-show popover cleanly',
        );

        // Return to compact collapsed and close popover while unmounted.
        tester.view.physicalSize = const Size(390, 800);
        await tester.pumpAndSettle();
        rebuildHost(() => popoverOpen = false);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
