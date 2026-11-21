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
  group('UiToggleRow', () {
    testWidgets('toggles value across full row and respects disabled state', (
      tester,
    ) async {
      var checked = false;
      var disabledChanged = false;

      await pumpUiWidget(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                UiToggleRow(
                  key: const ValueKey<String>('toggle_active'),
                  label: 'Watch local file',
                  description: 'Reload external edits automatically',
                  value: checked,
                  onChanged: (next) => setState(() => checked = next),
                ),
                UiToggleRow(
                  key: const ValueKey<String>('toggle_disabled'),
                  label: 'Auto-finish',
                  value: true,
                  isDense: true,
                  enabled: false,
                  onChanged: (_) => disabledChanged = true,
                ),
              ],
            );
          },
        ),
      );

      expect(find.text('Watch local file'), findsOneWidget);
      expect(find.text('Reload external edits automatically'), findsOneWidget);

      final activeSize = tester.getSize(
        find.byKey(const ValueKey<String>('toggle_active')),
      );
      expect(activeSize.height, greaterThanOrEqualTo(40.0));

      await tester.tap(find.text('Reload external edits automatically'));
      await tester.pump();
      expect(checked, isTrue);

      await tester.tap(find.text('Auto-finish'));
      await tester.pump();
      expect(disabledChanged, isFalse);

      final disabledOpacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('toggle_disabled')),
          matching: find.byType(Opacity),
        ),
      );
      expect(disabledOpacity.opacity, equals(0.48));
    });
  });
}
