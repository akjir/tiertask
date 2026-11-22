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
import 'package:tiertask/ui/primitives/ui_banner.dart';
import 'package:tiertask/ui/primitives/ui_button.dart';

import '../test_helpers.dart';

void main() {
  group('UiBanner', () {
    testWidgets('renders every UiBannerVariant and UiBannerTone cleanly', (
      tester,
    ) async {
      for (final variant in UiBannerVariant.values) {
        for (final tone in UiBannerTone.values) {
          await pumpUiWidget(
            tester,
            Center(
              child: UiBanner(
                variant: variant,
                tone: tone,
                title: 'Title ${variant.name}',
                message: 'Message ${variant.name} ${tone.name}',
                sublines: variant == UiBannerVariant.status
                    ? const <String>['Detail line']
                    : const <String>[],
                actionLabel: variant == UiBannerVariant.toast ? 'Undo' : null,
                onAction: variant == UiBannerVariant.toast ? () {} : null,
                kbdHint: variant == UiBannerVariant.toast ? 'Ctrl+Z' : null,
                cancelLabel: variant == UiBannerVariant.inlineConfirm
                    ? 'Keep'
                    : null,
                onCancel: variant == UiBannerVariant.inlineConfirm
                    ? () {}
                    : null,
                confirmLabel: variant == UiBannerVariant.inlineConfirm
                    ? 'Delete'
                    : null,
                onConfirm: variant == UiBannerVariant.inlineConfirm
                    ? () {}
                    : null,
                detailsChild: variant == UiBannerVariant.fullError
                    ? const Text('Local target failed')
                    : null,
              ),
            ),
          );
          expect(
            find.text('Message ${variant.name} ${tone.name}'),
            findsOneWidget,
            reason:
                'Variant ${variant.name} tone ${tone.name} must render message',
          );
        }
      }
    });

    testWidgets(
      'toast enforces maxWidth 620, hides kbdHint on compact, and wires action/dismiss callbacks',
      (tester) async {
        var undone = false;
        var dismissed = false;

        Widget buildToast() {
          return Center(
            child: UiBanner(
              key: const ValueKey<String>('undo_toast'),
              variant: UiBannerVariant.toast,
              tone: UiBannerTone.neutral,
              message: 'Completed task',
              actionLabel: 'Undo',
              onAction: () => undone = true,
              kbdHint: 'Ctrl+Z',
              onDismiss: () => dismissed = true,
              dismissTooltip: 'Close notice',
            ),
          );
        }

        await pumpUiWidget(
          tester,
          buildToast(),
          surfaceSize: const Size(1280, 800),
        );
        expect(find.text('Ctrl+Z'), findsOneWidget);
        expect(
          tester
              .getSize(find.byKey(const ValueKey<String>('undo_toast')))
              .width,
          lessThanOrEqualTo(620.0),
        );

        await tester.tap(find.text('Undo'));
        await tester.pump();
        expect(undone, isTrue);

        await tester.tap(find.byTooltip('Close notice'));
        await tester.pump();
        expect(dismissed, isTrue);

        await pumpUiWidget(
          tester,
          buildToast(),
          surfaceSize: const Size(390, 800),
        );
        expect(find.text('Ctrl+Z'), findsNothing);
      },
    );

    testWidgets(
      'inlineConfirm triggers cancel and confirm callbacks and status supports multiple actions',
      (tester) async {
        var kept = false;
        var deleted = false;
        var retried = false;
        var openedSettings = false;

        await pumpUiWidget(
          tester,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              UiBanner(
                variant: UiBannerVariant.inlineConfirm,
                message: 'Delete this task?',
                cancelLabel: 'Keep',
                onCancel: () => kept = true,
                confirmLabel: 'Yes, delete',
                onConfirm: () => deleted = true,
              ),
              UiBanner(
                variant: UiBannerVariant.status,
                tone: UiBannerTone.danger,
                message: 'Sync failed',
                actions: <Widget>[
                  UiButton(
                    label: 'Retry',
                    density: UiButtonDensity.compact,
                    onPressed: () => retried = true,
                  ),
                  UiButton(
                    label: 'Settings',
                    density: UiButtonDensity.compact,
                    onPressed: () => openedSettings = true,
                  ),
                ],
              ),
            ],
          ),
        );

        await tester.tap(find.text('Keep'));
        await tester.pump();
        expect(kept, isTrue);

        await tester.tap(find.text('Yes, delete'));
        await tester.pump();
        expect(deleted, isTrue);

        await tester.tap(find.text('Retry'));
        await tester.pump();
        expect(retried, isTrue);

        await tester.tap(find.text('Settings'));
        await tester.pump();
        expect(openedSettings, isTrue);
      },
    );
  });
}
