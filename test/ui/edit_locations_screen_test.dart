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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/location_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';

import 'test_helpers.dart';

class _FixedLocationNotifier extends LocationNotifier {
  _FixedLocationNotifier(this._fix);

  final LocationFix? _fix;

  @override
  LocationState build() => LocationState(
    status: _fix != null ? LocationStatus.found : LocationStatus.disabled,
    fix: _fix,
  );
}

void main() {
  testWidgets(
    'Side panel displays Locations section below Labels, opens EditLocationsScreen, permits duplicate location names, and supports EditLocationScreen with 6-decimal GPS rounding',
    (WidgetTester tester) async {
      const locationsTdf = '''
tdf 0.6.0

queue {
  modified 2026-11-01 08:30
  task 000001OkD2
}

location locHomeOk2 {
  name "Home Base"
  coordinates 52.52 13.405
  radius 100
  source "manual"
}
location locOffcOk2 {
  name "Alpha Office"
  coordinates 48.1351 11.582
  radius 200
  source "gps"
}
task 000001OkD2 {
  name "Check Office Router"
  created 2026-11-01 08:00
  condition {
    location locOffcOk2
  }
}
''';
      const fixedGpsFix = LocationFix(
        latitude: 50.978712345,
        longitude: 11.032898765,
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const WebDavConfig(language: AppLanguage.english),
            ),
          ),
          localFileRepositoryProvider.overrideWith(
            (ref) => FakeLocalFileRepository(
              config: const WebDavConfig(language: AppLanguage.english),
              initialTdf: locationsTdf,
            ),
          ),
          locationStateProvider.overrideWith(
            () => _FixedLocationNotifier(fixedGpsFix),
          ),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1, 12)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TierTaskApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      final editLocationsButtonFinder = find.byKey(
        const ValueKey('drawer_edit_locations_button'),
      );
      final createLocationTileFinder = find.byKey(
        const ValueKey('drawer_create_location_tile'),
      );
      final alphaLocationTileFinder = find.byKey(
        const ValueKey('drawer_location_tile_locOffcOk2'),
      );
      final homeLocationTileFinder = find.byKey(
        const ValueKey('drawer_location_tile_locHomeOk2'),
      );

      expect(
        find.text('Locations'),
        findsOneWidget,
        reason: 'Side panel must display the Locations section header',
      );
      expect(editLocationsButtonFinder, findsOneWidget);
      expect(createLocationTileFinder, findsOneWidget);
      expect(alphaLocationTileFinder, findsOneWidget);
      expect(homeLocationTileFinder, findsOneWidget);

      expect(
        tester.getTopLeft(alphaLocationTileFinder).dy <
            tester.getTopLeft(homeLocationTileFinder).dy,
        isTrue,
        reason: 'Drawer locations must be sorted alphabetically by name',
      );

      final officeBadge = tester.widget<Badge>(
        find.byKey(const ValueKey('drawer_location_badge_locOffcOk2')),
      );
      expect(
        (officeBadge.label as Text?)?.data,
        equals('1'),
        reason: 'Alpha Office must show open task count of 1',
      );

      await tester.tap(editLocationsButtonFinder);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('edit_locations_screen')),
        findsOneWidget,
        reason:
            'Clicking Edit in Locations header must open EditLocationsScreen',
      );

      final createInputFinder = find.byKey(
        const ValueKey('create_location_input'),
      );
      final createSubmitFinder = find.byKey(
        const ValueKey('create_location_submit_button'),
      );

      await tester.enterText(createInputFinder, 'Home Base');
      await tester.pump();
      await tester.tap(createSubmitFinder);
      await tester.pumpAndSettle();

      final boardAfterCreate = container
          .read(taskNotifierProvider)
          .requireValue;
      expect(
        boardAfterCreate.locations
            .where((loc) => loc.name == 'Home Base')
            .length,
        equals(2),
        reason: 'TDF 0.6.0 permits duplicate location names with distinct IDs',
      );

      final editOfficeButton = find.byKey(
        const ValueKey('edit_location_button_locOffcOk2'),
      );
      await tester.tap(editOfficeButton);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('edit_location_screen')),
        findsOneWidget,
        reason: 'Clicking edit on a location row must open EditLocationScreen',
      );

      await tester.tap(
        find.byKey(const ValueKey('location_editor_use_gps_button')),
      );
      await tester.pump();

      final latController = tester
          .widget<TextField>(
            find.byKey(const ValueKey('location_editor_lat_input')),
          )
          .controller;
      final lonController = tester
          .widget<TextField>(
            find.byKey(const ValueKey('location_editor_lon_input')),
          )
          .controller;
      expect(
        latController?.text,
        equals('50.978712'),
        reason: 'GPS button must round latitude to at most 6 decimal places',
      );
      expect(
        lonController?.text,
        equals('11.032899'),
        reason: 'GPS button must round longitude to at most 6 decimal places',
      );

      await tester.enterText(
        find.byKey(const ValueKey('location_editor_radius_input')),
        '350',
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('task_editor_save_button')));
      await tester.pumpAndSettle();

      final updatedOffice = container
          .read(taskNotifierProvider)
          .requireValue
          .findLocation('locOffcOk2')!;
      expect(updatedOffice.latitude, closeTo(50.978712, 1e-7));
      expect(updatedOffice.longitude, closeTo(11.032899, 1e-7));
      expect(updatedOffice.radius, equals(350));
    },
  );
}
