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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/location_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/location_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/ui/edit_locations_screen.dart';

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
            .where((location) => location.name == 'Home Base')
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

      final latitudeController = tester
          .widget<TextField>(
            find.byKey(const ValueKey('location_editor_lat_input')),
          )
          .controller;
      final longitudeController = tester
          .widget<TextField>(
            find.byKey(const ValueKey('location_editor_lon_input')),
          )
          .controller;
      expect(
        latitudeController?.text,
        equals('50.978712'),
        reason: 'GPS button must round latitude to at most 6 decimal places',
      );
      expect(
        longitudeController?.text,
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
      expect(
        updatedOffice.source,
        isNull,
        reason:
            'Saving in GPS mode must omit redundant gps/manual source token',
      );
    },
  );

  testWidgets(
    'EditLocationScreen governs field editability by source type, decodes full and short Plus Codes, and disambiguates multiple address candidates',
    (WidgetTester tester) async {
      final fakeLocationRepository = FakeLocationRepository();
      const initialLocation = TdfLocation(
        id: 'locTestOk1',
        name: 'Erfurt Station',
        latitude: 50.0,
        longitude: 11.0,
        radius: 150,
      );

      final container = await pumpLeafWidget(
        tester,
        const EditLocationScreen(location: initialLocation),
        board: TaskBoard(locations: const <TdfLocation>[initialLocation]),
        wrapInScaffold: false,
        locationRepository: fakeLocationRepository,
      );

      final sourceInputFinder = find.byKey(
        const ValueKey('location_editor_source_input'),
      );
      final latitudeInputFinder = find.byKey(
        const ValueKey('location_editor_lat_input'),
      );
      final longitudeInputFinder = find.byKey(
        const ValueKey('location_editor_lon_input'),
      );
      final dropdownFinder = find.byKey(
        const ValueKey('location_editor_source_type_dropdown'),
      );

      expect(
        tester.widget<TextField>(sourceInputFinder).enabled,
        isFalse,
        reason:
            'Source input must be disabled when GPS Coordinates is selected',
      );
      expect(
        tester.widget<TextField>(latitudeInputFinder).readOnly,
        isFalse,
        reason:
            'Latitude input must be editable when GPS Coordinates is selected',
      );
      expect(
        tester.widget<TextField>(longitudeInputFinder).readOnly,
        isFalse,
        reason:
            'Longitude input must be editable when GPS Coordinates is selected',
      );

      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Google Plus Code').last);
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(sourceInputFinder).enabled,
        isTrue,
        reason: 'Source input must be enabled in Google Plus Code mode',
      );
      expect(
        tester.widget<TextField>(latitudeInputFinder).readOnly,
        isTrue,
        reason: 'Latitude input must be readOnly in Google Plus Code mode',
      );
      expect(
        tester.widget<TextField>(longitudeInputFinder).readOnly,
        isTrue,
        reason: 'Longitude input must be readOnly in Google Plus Code mode',
      );

      await tester.enterText(sourceInputFinder, 'INVALID_CODE');
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('location_editor_resolve_button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Enter a valid Plus Code (e.g. 9F2PXXH7+F4 or XXH7+F4 Erfurt).',
        ),
        findsOneWidget,
        reason: 'Invalid Plus Code must display validation error',
      );

      await tester.enterText(sourceInputFinder, '9F2HX2HM+F4 Erfurt');
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('location_editor_resolve_button')),
      );
      await tester.pumpAndSettle();

      expect(
        fakeLocationRepository.searchCallCount,
        equals(0),
        reason: 'Full Plus Code resolution must be 100% offline with zero network calls',
      );
      expect(
        tester.widget<TextField>(latitudeInputFinder).controller?.text,
        equals('50.978688'),
        reason:
            'Resolved full Plus Code latitude must be rounded to 6 decimals',
      );
      expect(
        tester.widget<TextField>(longitudeInputFinder).controller?.text,
        equals('11.032813'),
        reason:
            'Resolved full Plus Code longitude must be rounded to 6 decimals',
      );
      expect(
        tester.widget<TextField>(sourceInputFinder).controller?.text,
        equals('9F2HX2HM+F4 Erfurt'),
        reason:
            'Full Plus Code resolution must preserve optional locality suffix',
      );

      fakeLocationRepository.searchResults = const <GeocodingCandidate>[
        GeocodingCandidate(
          displayName: 'Erfurt, Thuringia, Germany',
          latitude: 50.9787,
          longitude: 11.0328,
        ),
      ];
      await tester.enterText(sourceInputFinder, 'X2HM+F4 Erfurt');
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('location_editor_resolve_button')),
      );
      await tester.pumpAndSettle();

      expect(
        fakeLocationRepository.searchCallCount,
        equals(1),
        reason: 'Short Plus Code must query geocoder for reference locality',
      );
      expect(fakeLocationRepository.lastSearchQuery, equals('Erfurt'));
      expect(
        tester.widget<TextField>(sourceInputFinder).controller?.text,
        equals('X2HM+F4 Erfurt'),
        reason: 'Short Plus Code resolution must preserve concise shortCode + localityQuery',
      );
      expect(
        tester.widget<TextField>(latitudeInputFinder).controller?.text,
        equals('50.978688'),
      );
      expect(
        tester.widget<TextField>(longitudeInputFinder).controller?.text,
        equals('11.032813'),
      );

      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Address').last);
      await tester.pumpAndSettle();

      fakeLocationRepository.searchResults = const <GeocodingCandidate>[
        GeocodingCandidate(
          displayName: 'Willy-Brandt-Platz 1, 99084 Erfurt, Germany',
          latitude: 50.972568,
          longitude: 11.037812,
        ),
        GeocodingCandidate(
          displayName: 'Willy-Brandt-Platz 1, 04109 Leipzig, Germany',
          latitude: 51.345123,
          longitude: 12.381456,
        ),
      ];
      await tester.enterText(sourceInputFinder, 'Willy-Brandt-Platz 1');
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('location_editor_resolve_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('location_candidate_dialog')),
        findsOneWidget,
        reason:
            'Multiple geocoding matches must open candidate selection dialog',
      );

      await tester.tap(find.byKey(const ValueKey('location_candidate_item_1')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(latitudeInputFinder).controller?.text,
        equals('51.345123'),
        reason: 'Selecting second candidate must populate its latitude',
      );
      expect(
        tester.widget<TextField>(longitudeInputFinder).controller?.text,
        equals('12.381456'),
        reason: 'Selecting second candidate must populate its longitude',
      );
      expect(
        tester.widget<TextField>(sourceInputFinder).controller?.text,
        equals('Willy-Brandt-Platz 1, 04109 Leipzig, Germany'),
        reason: 'Selecting second candidate must populate its normalized displayName',
      );

      fakeLocationRepository.searchResults = const <GeocodingCandidate>[
        GeocodingCandidate(
          displayName: 'Bahnhofstraße 1, 99084 Erfurt, Germany',
          latitude: 50.973512,
          longitude: 11.036543,
        ),
      ];
      await tester.enterText(sourceInputFinder, 'Bahnhofstraße 1, Erfurt');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('task_editor_save_button')));
      await tester.pumpAndSettle();

      final savedLocation = container
          .read(taskNotifierProvider)
          .requireValue
          .findLocation('locTestOk1')!;
      expect(
        savedLocation.source,
        equals('Bahnhofstraße 1, 99084 Erfurt, Germany'),
        reason: 'Clicking Save with an edited unresolved address must auto-resolve before saving',
      );
      expect(savedLocation.latitude, closeTo(50.973512, 1e-7));
      expect(savedLocation.longitude, closeTo(11.036543, 1e-7));
    },
  );

  testWidgets(
    'EditLocationsScreen and EditLocationScreen validate empty state, create clear, delete, source switching to GPS, name and coordinate errors, and radius bounds',
    (WidgetTester tester) async {
      final container = await pumpLeafWidget(
        tester,
        const EditLocationsScreen(),
        board: TaskBoard.empty(),
        wrapInScaffold: false,
      );

      final localizations = AppLocalizations.of(
        tester.element(find.byKey(const ValueKey('edit_locations_screen'))),
      );

      expect(
        find.text(localizations.emptyLocationsHint),
        findsOneWidget,
        reason: 'Empty locations board must render _EmptyLocationsView',
      );

      final createInputFinder = find.byKey(
        const ValueKey('create_location_input'),
      );
      final createClearFinder = find.byKey(
        const ValueKey('create_location_clear_button'),
      );
      final createSubmitFinder = find.byKey(
        const ValueKey('create_location_submit_button'),
      );

      await tester.enterText(createInputFinder, 'Draft Location');
      await tester.pump();
      await tester.tap(createClearFinder);
      await tester.pump();

      expect(
        tester.widget<TextField>(createInputFinder).controller?.text,
        isEmpty,
        reason: 'Tapping create_location_clear_button must clear create input',
      );

      await tester.enterText(createInputFinder, 'Test Spot');
      await tester.pump();
      await tester.tap(createSubmitFinder);
      await tester.pumpAndSettle();

      expect(
        find.text(localizations.emptyLocationsHint),
        findsNothing,
        reason: 'Empty state must disappear once a location exists',
      );

      final locationId = container
          .read(taskNotifierProvider)
          .requireValue
          .locations
          .single
          .id;

      await tester.tap(
        find.byKey(ValueKey('edit_location_button_$locationId')),
      );
      await tester.pumpAndSettle();

      final dropdownFinder = find.byKey(
        const ValueKey('location_editor_source_type_dropdown'),
      );
      final sourceInputFinder = find.byKey(
        const ValueKey('location_editor_source_input'),
      );
      final latitudeInputFinder = find.byKey(
        const ValueKey('location_editor_lat_input'),
      );
      final radiusInputFinder = find.byKey(
        const ValueKey('location_editor_radius_input'),
      );
      final saveButtonFinder = find.byKey(
        const ValueKey('task_editor_save_button'),
      );

      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Google Plus Code').last);
      await tester.pumpAndSettle();

      await tester.enterText(sourceInputFinder, '9F2HX2HM+F4');
      await tester.pump();

      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('GPS Coordinates').last);
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(sourceInputFinder).controller?.text,
        isEmpty,
        reason: 'Switching source type back to GPS must clear source input',
      );
      expect(
        tester.widget<TextField>(sourceInputFinder).enabled,
        isFalse,
        reason: 'Source input must be disabled after switching back to GPS',
      );
      expect(
        tester.widget<TextField>(latitudeInputFinder).readOnly,
        isFalse,
        reason: 'Latitude input must be editable after switching back to GPS',
      );

      final nameInputFinder = find.byKey(
        const ValueKey('task_editor_title_input'),
      );
      await tester.enterText(nameInputFinder, '   ');
      await tester.pump();
      await tester.tap(saveButtonFinder);
      await tester.pump();

      expect(
        find.text(localizations.locationNameErrorEmpty),
        findsOneWidget,
        reason: 'Saving with empty name must show locationNameErrorEmpty',
      );

      await tester.enterText(nameInputFinder, 'Test Spot');
      await tester.pump();
      expect(
        find.text(localizations.locationNameErrorEmpty),
        findsNothing,
        reason: 'Editing name must clear locationNameErrorEmpty',
      );

      await tester.enterText(latitudeInputFinder, '95.0');
      await tester.pump();
      await tester.tap(saveButtonFinder);
      await tester.pump();

      expect(
        find.text(localizations.locationCoordinatesErrorInvalid),
        findsOneWidget,
        reason:
            'Out-of-range latitude must show locationCoordinatesErrorInvalid',
      );

      await tester.enterText(latitudeInputFinder, '50.0');
      await tester.pump();
      expect(
        find.text(localizations.locationCoordinatesErrorInvalid),
        findsNothing,
        reason:
            'Editing coordinates must clear locationCoordinatesErrorInvalid',
      );

      await tester.enterText(radiusInputFinder, '0.004');
      await tester.pump();
      await tester.tap(saveButtonFinder);
      await tester.pump();

      expect(
        find.text(localizations.locationRadiusErrorInvalid),
        findsOneWidget,
        reason: 'Sub-centimeter radius 0.004 that rounds to 0 must be rejected with locationRadiusErrorInvalid',
      );

      await tester.enterText(radiusInputFinder, '100001');
      await tester.pump();
      await tester.tap(saveButtonFinder);
      await tester.pump();

      expect(
        find.text(localizations.locationRadiusErrorInvalid),
        findsOneWidget,
        reason:
            'Radius > 100000m must be rejected with locationRadiusErrorInvalid',
      );

      const acceptedRadii = <(String, double)>[
        ('0.01', 0.01),
        ('150m', 150.0),
        ('0.5km', 500.0),
        ('100000', 100000.0),
      ];
      for (final (radiusInput, expectedMeters) in acceptedRadii) {
        if (find
            .byKey(const ValueKey('edit_location_screen'))
            .evaluate()
            .isEmpty) {
          await tester.tap(
            find.byKey(ValueKey('edit_location_button_$locationId')),
          );
          await tester.pumpAndSettle();
        }
        await tester.enterText(radiusInputFinder, radiusInput);
        await tester.pump();
        await tester.tap(saveButtonFinder);
        await tester.pumpAndSettle();

        final updated = container
            .read(taskNotifierProvider)
            .requireValue
            .findLocation(locationId)!;
        expect(
          updated.radius,
          closeTo(expectedMeters, 1e-6),
          reason:
              'Radius input $radiusInput must be accepted as $expectedMeters m',
        );
      }

      await tester.tap(
        find.byKey(ValueKey('delete_location_button_$locationId')),
      );
      await tester.pumpAndSettle();

      expect(
        container.read(taskNotifierProvider).requireValue.locations,
        isEmpty,
        reason: 'Tapping delete_location_button must remove the location',
      );
      expect(
        find.text(localizations.emptyLocationsHint),
        findsOneWidget,
        reason: 'Deleting the last location must restore _EmptyLocationsView',
      );
    },
  );
}
