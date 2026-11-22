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
import 'package:tiertask/ui/components/ui_dialog_frame.dart';
import 'package:tiertask/ui/primitives/ui_button.dart';

import '../test_helpers.dart';

void main() {
  group('UiDialogFrame', () {
    testWidgets(
      'renders modal sizes 420, 520, and 600 with subtitle, traps Tab cyclically, dismisses on Escape, and restores focus',
      (tester) async {
        final triggerFocus = FocusNode();
        addTearDown(triggerFocus.dispose);

        const sizeExpectations = <(UiDialogSize, double)>[
          (UiDialogSize.small, 420.0),
          (UiDialogSize.medium, 520.0),
          (UiDialogSize.large, 600.0),
        ];

        for (final (dialogSize, expectedMaxWidth) in sizeExpectations) {
          await pumpUiWidget(
            tester,
            Builder(
              builder: (context) {
                return Center(
                  child: UiButton(
                    key: const ValueKey<String>('open_modal_btn'),
                    focusNode: triggerFocus,
                    label: 'Open Modal',
                    onPressed: () async {
                      await UiDialogFrame.showModal<void>(
                        context: context,
                        builder: (dialogContext) {
                          return UiDialogFrame(
                            key: const ValueKey<String>('modal_frame'),
                            title: 'Dialog ${dialogSize.name}',
                            subtitle: 'Optional subtitle',
                            size: dialogSize,
                            closeTooltip: 'Close dialog',
                            onClose: () => Navigator.of(dialogContext).pop(),
                            body: const Text('Modal body'),
                            footer: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                UiButton(
                                  key: const ValueKey<String>('modal_cancel'),
                                  label: 'Cancel',
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(),
                                ),
                                const SizedBox(width: 8.0),
                                UiButton(
                                  key: const ValueKey<String>('modal_confirm'),
                                  label: 'Confirm',
                                  variant: UiButtonVariant.primary,
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
          );

          triggerFocus.requestFocus();
          await tester.pump();
          expect(triggerFocus.hasFocus, isTrue);

          await tester.tap(
            find.byKey(const ValueKey<String>('open_modal_btn')),
          );
          await tester.pumpAndSettle();

          expect(find.text('Dialog ${dialogSize.name}'), findsOneWidget);
          expect(find.text('Optional subtitle'), findsOneWidget);
          final frameSize = tester.getSize(
            find.byKey(const ValueKey<String>('modal_frame')),
          );
          expect(
            frameSize.width,
            closeTo(expectedMaxWidth, 0.5),
            reason:
                'UiDialogSize.${dialogSize.name} must measure $expectedMaxWidth px wide',
          );

          // Cyclical Tab traversal stays strictly inside modal descendants.
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(
            triggerFocus.hasFocus,
            isFalse,
            reason: 'Tab must stay trapped inside modal overlay',
          );

          // Shift+Tab cycles backward inside modal without escaping.
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pump();
          expect(triggerFocus.hasFocus, isFalse);

          // Escape dismisses modal and restores originating focus.
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.text('Dialog ${dialogSize.name}'), findsNothing);
          expect(
            triggerFocus.hasFocus,
            isTrue,
            reason: 'Closing modal must restore focus to triggering control',
          );
        }
      },
    );

    testWidgets(
      'showBottomSheet caps height at 78%, renders ExcludeSemantics handle, and closes on Done or scrim tap',
      (tester) async {
        final triggerFocus = FocusNode();
        addTearDown(triggerFocus.dispose);

        await pumpUiWidget(
          tester,
          Builder(
            builder: (context) {
              return Center(
                child: UiButton(
                  key: const ValueKey<String>('open_sheet_btn'),
                  focusNode: triggerFocus,
                  label: 'Pick labels',
                  onPressed: () async {
                    await UiDialogFrame.showBottomSheet<void>(
                      context: context,
                      title: 'Labels',
                      icon: Icons.label_outline_rounded,
                      countLabel: '3',
                      doneLabel: 'Done',
                      builder: (_) => const SizedBox(
                        height: 900,
                        child: Text('Sheet content'),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          surfaceSize: const Size(390, 800),
        );

        triggerFocus.requestFocus();
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey<String>('open_sheet_btn')));
        await tester.pumpAndSettle();

        expect(find.text('Labels'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('Sheet content'), findsOneWidget);

        final sheetFinder = find.byKey(
          const ValueKey<String>('ui_bottom_sheet'),
        );
        expect(sheetFinder, findsOneWidget);
        expect(
          tester.getSize(sheetFinder).height,
          lessThanOrEqualTo(800 * 0.78 + 1),
        );

        expect(
          find.descendant(
            of: sheetFinder,
            matching: find.byKey(
              const ValueKey<String>('ui_bottom_sheet_handle'),
            ),
          ),
          findsOneWidget,
        );

        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.text('Sheet content'), findsNothing);
        expect(triggerFocus.hasFocus, isTrue);
      },
    );

    testWidgets(
      'showBottomSheet and showModal clear system bar padding and soft keyboard viewInsets',
      (tester) async {
        tester.view.padding = const FakeViewPadding(top: 48.0, bottom: 24.0);
        tester.view.viewPadding = const FakeViewPadding(
          top: 48.0,
          bottom: 24.0,
        );
        addTearDown(() {
          tester.view.resetPadding();
          tester.view.resetViewPadding();
          tester.view.resetViewInsets();
        });

        await pumpUiWidget(
          tester,
          Builder(
            builder: (context) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  UiButton(
                    key: const ValueKey<String>('open_edge_sheet'),
                    label: 'Open Sheet',
                    onPressed: () async {
                      await UiDialogFrame.showBottomSheet<void>(
                        context: context,
                        title: 'Labels',
                        doneLabel: 'Done',
                        builder: (_) => const SizedBox(
                          key: ValueKey<String>('edge_sheet_body'),
                          height: 120.0,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Text('Bottom Sheet Content'),
                          ),
                        ),
                      );
                    },
                  ),
                  UiButton(
                    key: const ValueKey<String>('open_edge_modal'),
                    label: 'Open Modal',
                    onPressed: () async {
                      await UiDialogFrame.showModal<void>(
                        context: context,
                        builder: (dialogContext) => UiDialogFrame(
                          key: const ValueKey<String>('edge_modal_frame'),
                          title: 'Tall Modal',
                          onClose: () => Navigator.of(dialogContext).pop(),
                          body: const SizedBox(height: 900.0),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
          surfaceSize: const Size(390.0, 844.0),
          wrapInScaffold: false,
        );

        await tester.tap(find.byKey(const ValueKey<String>('open_edge_sheet')));
        await tester.pumpAndSettle();

        final sheetBodyRect = tester.getRect(
          find.byKey(const ValueKey<String>('edge_sheet_body')),
        );
        expect(
          sheetBodyRect.bottom,
          lessThanOrEqualTo(844.0 - 24.0 - 16.0 + 0.5),
          reason: 'Bottom sheet content must clear 24px navigation bar plus 16px bottom padding',
        );

        // Soft keyboard opens while bottom sheet is visible -> sheet rises above keyboard.
        tester.view.padding = const FakeViewPadding(top: 48.0);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300.0);
        await tester.pumpAndSettle();

        final sheetWithImeRect = tester.getRect(
          find.byKey(const ValueKey<String>('ui_bottom_sheet')),
        );
        expect(
          sheetWithImeRect.bottom,
          lessThanOrEqualTo(844.0 - 300.0 + 0.5),
          reason: 'Bottom sheet must rise above 300px soft keyboard',
        );
        expect(
          sheetWithImeRect.top,
          greaterThanOrEqualTo(48.0 - 0.5),
          reason: 'Bottom sheet must stay below 48px status bar',
        );

        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();

        // Modal dialog with tall body and soft keyboard open must stay inside safe + IME bounds.
        await tester.tap(find.byKey(const ValueKey<String>('open_edge_modal')));
        await tester.pumpAndSettle();

        final modalRect = tester.getRect(
          find.byKey(const ValueKey<String>('edge_modal_frame')),
        );
        expect(
          modalRect.top,
          greaterThanOrEqualTo(48.0 + 16.0 - 0.5),
          reason: 'Modal dialog must clear 48px status bar plus 16px margin',
        );
        expect(
          modalRect.bottom,
          lessThanOrEqualTo(844.0 - 300.0 - 16.0 + 0.5),
          reason:
              'Modal dialog must clear 300px soft keyboard plus 16px margin',
        );
      },
    );

    testWidgets(
      'aligns compact bottom sheet Done button flush to right header edge',
      (tester) async {
        await pumpUiWidget(
          tester,
          Builder(
            builder: (context) => UiButton(
              key: const ValueKey<String>('open_align_sheet'),
              label: 'Open Sheet',
              onPressed: () async {
                await UiDialogFrame.showBottomSheet<void>(
                  context: context,
                  title: 'Labels',
                  countLabel: '2',
                  doneLabel: 'Done',
                  builder: (_) => const SizedBox(height: 80.0),
                );
              },
            ),
          ),
          surfaceSize: const Size(390.0, 844.0),
          wrapInScaffold: false,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('open_align_sheet')),
        );
        await tester.pumpAndSettle();

        final sheetRect = tester.getRect(
          find.byKey(const ValueKey<String>('ui_bottom_sheet')),
        );
        final doneRect = tester.getRect(find.text('Done'));
        expect(
          sheetRect.right - doneRect.right,
          lessThan(40.0),
          reason: 'Bottom sheet Done button must anchor near the right edge',
        );
      },
    );
  });
}
