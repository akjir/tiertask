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

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/floating_notice_providers.dart';
import 'package:tiertask/providers/location_providers.dart';
import 'package:tiertask/providers/shell_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/location_repository.dart';
import 'package:tiertask/ui/primitives/ui_button.dart';
import 'package:tiertask/ui/primitives/ui_field.dart';
import 'package:tiertask/ui/views/locations_view.dart';

import 'test_helpers.dart';

class _DelayedAddLocationTaskNotifier extends FakeTaskNotifier {
  _DelayedAddLocationTaskNotifier(super.initialBoard, this.completer);

  final Completer<void> completer;
  int addLocationCallCount = 0;

  @override
  Future<void> addLocation(
    String name, {
    required double latitude,
    required double longitude,
    required double radiusMeters,
    String source = 'manual',
    String? id,
    String? note,
    DateTime? currentDate,
  }) async {
    addLocationCallCount++;
    await completer.future;
    await super.addLocation(
      name,
      id: id,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      source: source,
      note: note,
      currentDate: currentDate,
    );
  }
}

void main() {
  String? lastCopiedText;

  setUp(() {
    lastCopiedText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final arguments = call.arguments;
            if (arguments is Map<Object?, Object?>) {
              final text = arguments['text'];
              if (text is String) {
                lastCopiedText = text;
              }
            }
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('LocationsView', () {
    testWidgets(
      'renders empty state, header count, inline quick-create composer, and hides back button without returnContext',
      (tester) async {
        await pumpLeafWidget(tester, const Scaffold(body: LocationsView()));

        expect(find.text('Locations'), findsOneWidget);
        expect(
          find.text('Reusable locations for task and label GPS conditions.'),
          findsOneWidget,
        );
        expect(find.text('0'), findsOneWidget);
        expect(find.text('No locations created yet.'), findsOneWidget);
        expect(find.text('Quick-create a new location...'), findsOneWidget);
        expect(find.widgetWithText(UiButton, 'Add'), findsOneWidget);
        expect(find.text('Open as draft'), findsOneWidget);
        expect(find.text('Back to tasks'), findsNothing);
        expect(find.text('Back to search'), findsNothing);
      },
    );

    testWidgets(
      'quick-create validates empty name, seeds active GPS fix, persists location, clears input, and auto-expands new card',
      (tester) async {
        final container = await pumpLeafWidget(
          tester,
          const Scaffold(body: LocationsView()),
          config: const WebDavConfig(
            language: AppLanguage.english,
            locationEnabled: true,
          ),
          locationFix: const LocationFix(
            latitude: 50.9787123,
            longitude: 11.0328456,
            placeName: 'Erfurt',
            source: LocationSource.gps,
          ),
        );
        // Prime foreground GPS fix as TierTaskShellScreen does when mounted in the full shell.
        container.read(locationStateProvider);
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(UiButton, 'Add'));
        await tester.pumpAndSettle();

        expect(
          container.read(floatingNoticeProvider)?.message,
          equals('Please enter a location name.'),
        );
        expect(
          container.read(taskNotifierProvider).asData?.value.locations,
          isEmpty,
        );

        final composerInput = find.descendant(
          of: find.byKey(
            const ValueKey<String>('locations_quick_create_composer'),
          ),
          matching: find.byType(TextField),
        );
        await tester.enterText(composerInput, 'Erfurt Office');
        await tester.tap(find.widgetWithText(UiButton, 'Add'));
        await tester.pumpAndSettle();

        final locations =
            container.read(taskNotifierProvider).asData?.value.locations ??
            const <TdfLocation>[];
        expect(locations, hasLength(1));
        final createdLocation = locations.first;
        expect(createdLocation.name, equals('Erfurt Office'));
        expect(createdLocation.latitude, closeTo(50.978712, 0.000001));
        expect(createdLocation.longitude, closeTo(11.032846, 0.000001));
        expect(createdLocation.radius, equals(200.0));

        final shellState = container.read(shellProvider);
        expect(
          shellState.expandedEntity,
          equals(EntityRef(kind: EntityKind.location, id: createdLocation.id)),
        );
        expect(
          container.read(floatingNoticeProvider)?.message,
          equals('Location saved.'),
        );
        expect(find.text('No locations created yet.'), findsNothing);
        expect(find.text('50.978712, 11.032846'), findsOneWidget);
        expect(find.text('Radius: 200m'), findsOneWidget);

        final inputField = tester.widget<TextField>(composerInput);
        expect(inputField.controller?.text, isEmpty);
      },
    );

    testWidgets(
      'uncommitted draft card replaces quick-create bar in place, seeds GPS, validates, and commits',
      (tester) async {
        final container = await pumpLeafWidget(
          tester,
          const Scaffold(body: LocationsView()),
          config: const WebDavConfig(
            language: AppLanguage.english,
            locationEnabled: true,
          ),
          locationFix: const LocationFix(
            latitude: 47.1204,
            longitude: 8.5173,
            placeName: 'Zug',
            source: LocationSource.gps,
          ),
        );
        // Prime foreground GPS fix as TierTaskShellScreen does when mounted in the full shell.
        container.read(locationStateProvider);
        await tester.pumpAndSettle();

        final composerInput = find.descendant(
          of: find.byKey(
            const ValueKey<String>('locations_quick_create_composer'),
          ),
          matching: find.byType(TextField),
        );
        await tester.enterText(composerInput, 'Depot North');
        await tester.tap(find.text('Open as draft'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('locations_quick_create_composer')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('location_draft_card')),
          findsOneWidget,
        );
        expect(find.text('New Location (Draft)'), findsOneWidget);
        expect(find.text('No locations created yet.'), findsNothing);

        final draftNameField = tester.widget<UiField>(
          find.byKey(const ValueKey<String>('location_draft_name_field')),
        );
        expect(draftNameField.controller?.text, equals('Depot North'));
        expect(draftNameField.autofocus, isTrue);

        final draftLatitudeField = tester.widget<UiField>(
          find.byKey(const ValueKey<String>('location_draft_latitude_field')),
        );
        final draftLongitudeField = tester.widget<UiField>(
          find.byKey(const ValueKey<String>('location_draft_longitude_field')),
        );
        expect(draftLatitudeField.controller?.text, equals('47.1204'));
        expect(draftLongitudeField.controller?.text, equals('8.5173'));

        await tester.tap(
          find.byKey(const ValueKey<String>('location_draft_cancel_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('location_draft_card')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('locations_quick_create_composer')),
          findsOneWidget,
        );
        expect(
          container.read(taskNotifierProvider).asData?.value.locations,
          isEmpty,
        );

        await tester.enterText(composerInput, 'Depot North');
        await tester.tap(find.text('Open as draft'));
        await tester.pumpAndSettle();

        final draftRadiusInput = find.descendant(
          of: find.byKey(const ValueKey<String>('location_draft_radius_field')),
          matching: find.byType(TextField),
        );
        await tester.enterText(draftRadiusInput, 'invalid');
        final createButton = find.byKey(
          const ValueKey<String>('location_draft_create_button'),
        );
        await tester.ensureVisible(createButton);
        await tester.pumpAndSettle();
        await tester.tap(createButton);
        await tester.pumpAndSettle();

        expect(
          find.text('Enter a valid radius between 0.01m and 100km.'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('location_draft_card')),
          findsOneWidget,
        );

        await tester.enterText(draftRadiusInput, '1,5km');
        final draftNoteInput = find.descendant(
          of: find.byKey(const ValueKey<String>('location_draft_note_field')),
          matching: find.byType(TextField),
        );
        await tester.enterText(draftNoteInput, 'Rear gate code 42');
        await tester.ensureVisible(createButton);
        await tester.pumpAndSettle();
        await tester.tap(createButton);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('location_draft_card')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('locations_quick_create_composer')),
          findsOneWidget,
        );
        final locations =
            container.read(taskNotifierProvider).asData?.value.locations ??
            const <TdfLocation>[];
        expect(locations, hasLength(1));
        final createdLocation = locations.first;
        expect(createdLocation.name, equals('Depot North'));
        expect(createdLocation.radius, equals(1500.0));
        expect(createdLocation.note, equals('Rear gate code 42'));
        expect(
          container.read(shellProvider).expandedEntity,
          equals(EntityRef(kind: EntityKind.location, id: createdLocation.id)),
        );
        expect(find.text('Rear gate code 42'), findsOneWidget);
        expect(find.text('Radius: 1.5km'), findsOneWidget);
      },
    );

    testWidgets(
      'enforces collapsed metadata strip, single-expand accordion, copy ID, and inline name/note editing',
      (tester) async {
        const office = TdfLocation(
          id: 'loc_office',
          name: 'Alpha Office',
          latitude: 50.9787,
          longitude: 11.0328,
          radius: 250.0,
          source: 'Domplatz 1, Erfurt',
          note: 'Side entrance',
        );
        const home = TdfLocation(
          id: 'loc_home',
          name: 'Beta Home',
          latitude: 48.1351,
          longitude: 11.5820,
          radius: 100.0,
        );
        final taskAtOffice = TaskItem(
          id: 't_1',
          title: 'Sign parcel',
          conditions: <TaskCondition>[
            LocationTaskCondition.fromIds(const <String>['loc_office']),
          ],
        );
        final board = TaskBoard(
          blocked: <TaskItem>[taskAtOffice],
          locations: const <TdfLocation>[office, home],
        );

        final container = await pumpLeafWidget(
          tester,
          const Scaffold(body: LocationsView()),
          board: board,
        );

        expect(find.text('Address'), findsOneWidget);
        expect(find.text('50.9787, 11.0328 · 250m'), findsOneWidget);
        expect(find.text('1 open'), findsOneWidget);
        expect(find.text('Note'), findsOneWidget);
        expect(find.text('GPS Coordinates'), findsOneWidget);
        expect(find.text('48.1351, 11.5820 · 100m'), findsOneWidget);
        expect(find.text('0 open'), findsOneWidget);

        await tester.tap(find.text('Alpha Office'));
        await tester.pumpAndSettle();

        expect(find.text('ID: loc_office'), findsOneWidget);
        expect(find.text('Domplatz 1, Erfurt'), findsOneWidget);
        expect(find.text('Side entrance'), findsOneWidget);
        expect(find.text('+ Note'), findsNothing);
        expect(
          find.byKey(
            const ValueKey<String>('location_edit_name_button_loc_office'),
          ),
          findsOneWidget,
        );

        await tester.tap(find.byTooltip('Copy'));
        await tester.pumpAndSettle();
        expect(lastCopiedText, equals('loc_office'));
        expect(
          container.read(floatingNoticeProvider)?.message,
          equals('Location ID copied to clipboard.'),
        );

        await tester.tap(
          find.byKey(
            const ValueKey<String>('location_edit_name_button_loc_office'),
          ),
        );
        await tester.pumpAndSettle();
        final nameInput = find.descendant(
          of: find.byKey(
            const ValueKey<String>('location_name_editor_loc_office'),
          ),
          matching: find.byType(TextField),
        );
        await tester.enterText(nameInput, '   ');
        await tester.tap(
          find.byKey(const ValueKey<String>('location_name_save_loc_office')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Please enter a location name.'), findsOneWidget);

        await tester.enterText(nameInput, 'Alpha HQ');
        await tester.tap(
          find.byKey(const ValueKey<String>('location_name_save_loc_office')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Alpha HQ'), findsOneWidget);
        expect(
          container
              .read(taskNotifierProvider)
              .asData
              ?.value
              .findLocation('loc_office')
              ?.name,
          equals('Alpha HQ'),
        );

        await tester.tap(find.text('Beta Home'));
        await tester.pumpAndSettle();
        expect(find.text('ID: loc_office'), findsNothing);
        expect(find.text('ID: loc_home'), findsOneWidget);
        expect(find.text('+ Note'), findsOneWidget);

        await tester.tap(find.text('+ Note'));
        await tester.pumpAndSettle();
        final noteInput = find.descendant(
          of: find.byKey(
            const ValueKey<String>('location_note_section_loc_home'),
          ),
          matching: find.byType(TextField),
        );
        await tester.enterText(noteInput, 'Quiet study room');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(find.text('Quiet study room'), findsOneWidget);
        expect(find.text('+ Note'), findsNothing);
        expect(
          container
              .read(taskNotifierProvider)
              .asData
              ?.value
              .findLocation('loc_home')
              ?.note,
          equals('Quiet study room'),
        );

        final noteEditButton = find.descendant(
          of: find.byKey(
            const ValueKey<String>('location_note_section_loc_home'),
          ),
          matching: find.byTooltip('Edit'),
        );
        await tester.tap(noteEditButton);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();

        expect(find.text('Quiet study room'), findsNothing);
        expect(find.text('+ Note'), findsOneWidget);

        await tester.tap(find.text('Beta Home'));
        await tester.pumpAndSettle();
        expect(find.text('ID: loc_home'), findsNothing);
      },
    );

    testWidgets(
      'enforces Use Current GPS vs Resolve mutual gating, read-only lat/lon opacity, and Plus Code resolution',
      (tester) async {
        const location = TdfLocation(
          id: 'loc_1',
          name: 'Workshop',
          latitude: 10.0,
          longitude: 20.0,
          radius: 150.0,
        );
        final container = await pumpLeafWidget(
          tester,
          const Scaffold(body: LocationsView()),
          board: TaskBoard(locations: const <TdfLocation>[location]),
          config: const WebDavConfig(
            language: AppLanguage.english,
            locationEnabled: true,
          ),
          locationFix: const LocationFix(
            latitude: 52.520008,
            longitude: 13.404954,
            placeName: 'Berlin',
            source: LocationSource.gps,
          ),
        );

        await tester.tap(find.text('Workshop'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey<String>('location_edit_coords_button_loc_1'),
          ),
        );
        await tester.pumpAndSettle();

        final useGpsFinder = find.byKey(
          const ValueKey<String>('location_coords_loc_1_use_gps_button'),
        );
        final resolveFinder = find.byKey(
          const ValueKey<String>('location_coords_loc_1_resolve_button'),
        );
        final latitudeFieldFinder = find.byKey(
          const ValueKey<String>('location_coords_loc_1_latitude_field'),
        );
        final longitudeFieldFinder = find.byKey(
          const ValueKey<String>('location_coords_loc_1_longitude_field'),
        );

        expect(tester.widget<UiButton>(useGpsFinder).onPressed, isNotNull);
        expect(tester.widget<UiButton>(resolveFinder).onPressed, isNull);
        expect(tester.widget<UiField>(latitudeFieldFinder).readOnly, isFalse);
        expect(tester.widget<UiField>(longitudeFieldFinder).readOnly, isFalse);

        await tester.tap(useGpsFinder);
        await tester.pumpAndSettle();
        expect(
          tester.widget<UiField>(latitudeFieldFinder).controller?.text,
          equals('52.520008'),
        );
        expect(
          tester.widget<UiField>(longitudeFieldFinder).controller?.text,
          equals('13.404954'),
        );
        expect(
          container.read(floatingNoticeProvider)?.message,
          equals('Current GPS position applied.'),
        );

        await tester.tap(find.text('Google Plus Code'));
        await tester.pumpAndSettle();

        expect(tester.widget<UiButton>(useGpsFinder).onPressed, isNull);
        expect(tester.widget<UiButton>(resolveFinder).onPressed, isNotNull);
        expect(tester.widget<UiField>(latitudeFieldFinder).readOnly, isTrue);
        expect(tester.widget<UiField>(longitudeFieldFinder).readOnly, isTrue);

        final latitudeOpacity = tester.widget<Opacity>(
          find
              .descendant(
                of: latitudeFieldFinder,
                matching: find.byType(Opacity),
              )
              .first,
        );
        expect(latitudeOpacity.opacity, equals(0.72));

        final sourceInput = find.descendant(
          of: find.byKey(
            const ValueKey<String>('location_coords_loc_1_source_field'),
          ),
          matching: find.byType(TextField),
        );
        await tester.enterText(sourceInput, '9F2PXXH7+F4');
        await tester.tap(resolveFinder);
        await tester.pumpAndSettle();

        expect(
          container.read(floatingNoticeProvider)?.message,
          equals('Source resolved to coordinates.'),
        );
        final resolvedLatitudeText =
            tester.widget<UiField>(latitudeFieldFinder).controller?.text ?? '';
        final resolvedLongitudeText =
            tester.widget<UiField>(longitudeFieldFinder).controller?.text ?? '';
        expect(
          double.tryParse(resolvedLatitudeText),
          closeTo(50.978688, 0.001),
        );
        expect(
          double.tryParse(resolvedLongitudeText),
          closeTo(14.962813, 0.001),
        );

        final radiusInput = find.descendant(
          of: find.byKey(
            const ValueKey<String>('location_coords_loc_1_radius_field'),
          ),
          matching: find.byType(TextField),
        );
        await tester.enterText(radiusInput, '300m');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        final updated = container
            .read(taskNotifierProvider)
            .asData
            ?.value
            .findLocation('loc_1');
        expect(updated?.source, equals('9F2PXXH7+F4'));
        expect(updated?.radius, equals(300.0));
        expect(updated?.latitude, closeTo(50.978688, 0.001));
        expect(updated?.longitude, closeTo(14.962813, 0.001));
      },
    );

    testWidgets(
      'opens geocoding candidates modal on ambiguous address and applies selected candidate',
      (tester) async {
        final locationRepository = FakeLocationRepository()
          ..searchResults = const <GeocodingCandidate>[
            GeocodingCandidate(
              displayName: 'Berlin, Germany',
              latitude: 52.520008,
              longitude: 13.404954,
            ),
            GeocodingCandidate(
              displayName: 'Berlin, New Hampshire, USA',
              latitude: 44.468669,
              longitude: -71.185077,
            ),
          ];
        const location = TdfLocation(
          id: 'loc_city',
          name: 'City Hub',
          latitude: 0.0,
          longitude: 0.0,
          radius: 200.0,
        );

        final container = await pumpLeafWidget(
          tester,
          const Scaffold(body: LocationsView()),
          board: TaskBoard(locations: const <TdfLocation>[location]),
          locationRepository: locationRepository,
        );

        await tester.tap(find.text('City Hub'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey<String>('location_edit_coords_button_loc_city'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Address'));
        await tester.pumpAndSettle();

        final sourceInput = find.descendant(
          of: find.byKey(
            const ValueKey<String>('location_coords_loc_city_source_field'),
          ),
          matching: find.byType(TextField),
        );
        await tester.enterText(sourceInput, 'Berlin');
        await tester.tap(
          find.byKey(
            const ValueKey<String>('location_coords_loc_city_resolve_button'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('geocoding_candidates_modal')),
          findsOneWidget,
        );
        expect(find.text('Berlin, Germany'), findsOneWidget);
        expect(find.text('Berlin, New Hampshire, USA'), findsOneWidget);

        await tester.tap(find.text('Berlin, New Hampshire, USA'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('geocoding_candidates_modal')),
          findsNothing,
        );
        expect(
          container.read(floatingNoticeProvider)?.message,
          equals('Source resolved to coordinates.'),
        );

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        final updated = container
            .read(taskNotifierProvider)
            .asData
            ?.value
            .findLocation('loc_city');
        expect(updated?.source, equals('Berlin, New Hampshire, USA'));
        expect(updated?.latitude, closeTo(44.468669, 0.000001));
        expect(updated?.longitude, closeTo(-71.185077, 0.000001));
      },
    );

    testWidgets(
      'supports disambiguated geocoding resolution inside Location Draft Card',
      (tester) async {
        final locationRepository = FakeLocationRepository()
          ..searchResults = const <GeocodingCandidate>[
            GeocodingCandidate(
              displayName: 'Paris, France',
              latitude: 48.856614,
              longitude: 2.352222,
            ),
            GeocodingCandidate(
              displayName: 'Paris, Texas, USA',
              latitude: 33.660939,
              longitude: -95.555513,
            ),
          ];

        final container = await pumpLeafWidget(
          tester,
          const Scaffold(body: LocationsView()),
          locationRepository: locationRepository,
        );

        await tester.tap(find.text('Open as draft'));
        await tester.pumpAndSettle();

        final draftNameInput = find.descendant(
          of: find.byKey(const ValueKey<String>('location_draft_name_field')),
          matching: find.byType(TextField),
        );
        await tester.enterText(draftNameInput, 'Paris Studio');

        await tester.tap(find.text('Address'));
        await tester.pumpAndSettle();

        final draftSourceInput = find.descendant(
          of: find.byKey(const ValueKey<String>('location_draft_source_field')),
          matching: find.byType(TextField),
        );
        await tester.enterText(draftSourceInput, 'Paris');
        await tester.tap(
          find.byKey(const ValueKey<String>('location_draft_resolve_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('geocoding_candidates_modal')),
          findsOneWidget,
        );
        await tester.tap(find.text('Paris, France'));
        await tester.pumpAndSettle();

        final createButton = find.byKey(
          const ValueKey<String>('location_draft_create_button'),
        );
        await tester.ensureVisible(createButton);
        await tester.pumpAndSettle();
        await tester.tap(createButton);
        await tester.pumpAndSettle();

        final locations =
            container.read(taskNotifierProvider).asData?.value.locations ??
            const <TdfLocation>[];
        expect(locations, hasLength(1));
        expect(locations.first.name, equals('Paris Studio'));
        expect(locations.first.source, equals('Paris, France'));
        expect(locations.first.latitude, closeTo(48.856614, 0.000001));
        expect(locations.first.longitude, closeTo(2.352222, 0.000001));
      },
    );

    testWidgets('supports inline delete confirmation Keep and Yes, delete', (
      tester,
    ) async {
      const location = TdfLocation(
        id: 'loc_del',
        name: 'Temporary Site',
        latitude: 51.0,
        longitude: 10.0,
        radius: 150.0,
      );
      final container = await pumpLeafWidget(
        tester,
        const Scaffold(body: LocationsView()),
        board: TaskBoard(locations: const <TdfLocation>[location]),
      );

      await tester.tap(find.text('Temporary Site'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete location'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this location?'), findsOneWidget);

      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this location?'), findsNothing);
      expect(
        container.read(taskNotifierProvider).asData?.value.locations,
        hasLength(1),
      );

      await tester.tap(find.byTooltip('Delete location'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, delete'));
      await tester.pumpAndSettle();

      expect(
        container.read(taskNotifierProvider).asData?.value.locations,
        isEmpty,
      );
      expect(container.read(shellProvider).expandedEntity, isNull);
      expect(
        container.read(floatingNoticeProvider)?.message,
        equals('Location deleted.'),
      );
    });

    testWidgets(
      'preserves returnContext back navigation to Tasks and Global Search and clears reveal request',
      (tester) async {
        const location = TdfLocation(
          id: 'loc_nav',
          name: 'Archive Vault',
          latitude: 49.0,
          longitude: 8.4,
          radius: 120.0,
        );
        final task = TaskItem(id: 'task_1', title: 'Review files');
        const label = TdfLabel(id: 'lbl_1', name: 'Ops');
        final board = TaskBoard(
          focus: <TaskItem>[task],
          labels: const <TdfLabel>[label],
          locations: const <TdfLocation>[location],
        );

        final container = await pumpLeafWidget(
          tester,
          const Scaffold(body: LocationsView()),
          board: board,
        );

        final shellNotifier = container.read(shellProvider.notifier);
        shellNotifier.selectTier(TaskTier.ready);
        shellNotifier.selectLabelFilter('lbl_1');
        shellNotifier.expandEntity(
          const EntityRef(kind: EntityKind.task, id: 'task_1'),
          reveal: false,
        );
        shellNotifier.openEntityInManager(
          const EntityRef(kind: EntityKind.location, id: 'loc_nav'),
          preserveReturnContext: true,
        );
        await tester.pumpAndSettle();

        expect(find.text('Back to tasks'), findsOneWidget);
        expect(find.text('ID: loc_nav'), findsOneWidget);
        expect(container.read(shellProvider).revealEntityRequest, isNull);

        await tester.tap(find.text('Back to tasks'));
        await tester.pumpAndSettle();

        final restoredTasksState = container.read(shellProvider);
        expect(restoredTasksState.view, equals(ShellView.tasks));
        expect(restoredTasksState.activeTier, equals(TaskTier.ready));
        expect(restoredTasksState.activeLabelId, equals('lbl_1'));
        expect(
          restoredTasksState.expandedEntity,
          equals(const EntityRef(kind: EntityKind.task, id: 'task_1')),
        );
        expect(restoredTasksState.returnContext, isNull);

        shellNotifier.openSearch();
        container.read(searchQueryProvider.notifier).setQuery('files');
        shellNotifier.openEntityInManager(
          const EntityRef(kind: EntityKind.location, id: 'loc_nav'),
          preserveReturnContext: true,
        );
        await tester.pumpAndSettle();

        expect(find.text('Back to search'), findsOneWidget);
        await tester.tap(find.text('Back to search'));
        await tester.pumpAndSettle();

        final restoredSearchState = container.read(shellProvider);
        expect(restoredSearchState.view, equals(ShellView.tasks));
        expect(restoredSearchState.searchOpen, isTrue);
        expect(container.read(searchQueryProvider), equals('files'));
      },
    );

    testWidgets(
      'renders cleanly on compact 390px viewport and guards mid-flight location creation',
      (tester) async {
        final completer = Completer<void>();
        late _DelayedAddLocationTaskNotifier spyNotifier;

        final container = await pumpLeafWidget(
          tester,
          const Scaffold(body: LocationsView()),
          surfaceSize: const Size(390, 844),
          taskNotifierFactory: () {
            spyNotifier = _DelayedAddLocationTaskNotifier(
              TaskBoard.empty(),
              completer,
            );
            return spyNotifier;
          },
        );

        final composerInput = find.descendant(
          of: find.byKey(
            const ValueKey<String>('locations_quick_create_composer'),
          ),
          matching: find.byType(TextField),
        );
        expect(
          composerInput,
          findsOneWidget,
          reason:
              'Quick-Create must remain inline (non-collapsible) on compact',
        );

        await tester.enterText(composerInput, 'Compact Site');
        await tester.tap(find.widgetWithText(UiButton, 'Add'));
        await tester.pump();

        expect(spyNotifier.addLocationCallCount, equals(1));

        await tester.tap(find.widgetWithText(UiButton, 'Add'));
        await tester.pump();
        expect(
          spyNotifier.addLocationCallCount,
          equals(1),
          reason: 'Mid-flight busy state must block duplicate creation',
        );

        completer.complete();
        await tester.pumpAndSettle();

        expect(
          container.read(taskNotifierProvider).asData?.value.locations,
          hasLength(1),
        );

        await tester.tap(find.text('Open as draft'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('location_draft_card')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
