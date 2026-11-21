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

import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/presentation/location_editor_controller.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/location_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/location_repository.dart';
import 'package:tiertask/services/plus_code_service.dart';

class _RecordingLocationNotifier extends LocationNotifier {
  _RecordingLocationNotifier(this._initialState, {this.refreshedFix});

  final LocationState _initialState;
  final LocationFix? refreshedFix;
  int refreshCalls = 0;

  @override
  LocationState build() => _initialState;

  @override
  Future<void> refreshLocation() async {
    refreshCalls++;
    if (refreshedFix case final fix?) {
      state = LocationState(
        status: LocationStatus.found,
        fix: fix,
        updatedAt: DateTime.utc(2026, 11, 21),
      );
    }
  }
}

class _RecordingTaskNotifier extends TaskNotifier {
  final List<String> addedNames = <String>[];
  double? lastAddedLatitude;
  double? lastAddedLongitude;
  double? lastAddedRadius;
  String? lastUpdatedId;
  String? lastUpdatedName;
  String? lastUpdatedSource;
  bool? lastClearSource;
  String? lastUpdatedNote;
  bool? lastClearNote;
  final List<String> deletedIds = <String>[];

  @override
  Future<TaskBoard> build() async => TaskBoard.empty();

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
    addedNames.add(name);
    lastAddedLatitude = latitude;
    lastAddedLongitude = longitude;
    lastAddedRadius = radiusMeters;
  }

  @override
  Future<void> deleteLocation(
    String locationId, {
    DateTime? currentDate,
  }) async {
    deletedIds.add(locationId);
  }

  @override
  Future<void> updateLocation(
    String locationId, {
    String? name,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    String? source,
    bool clearSource = false,
    String? note,
    bool clearNote = false,
    DateTime? currentDate,
  }) async {
    lastUpdatedId = locationId;
    lastUpdatedName = name;
    lastUpdatedSource = source;
    lastClearSource = clearSource;
    lastUpdatedNote = note;
    lastClearNote = clearNote;
  }
}

void main() {
  group('LocationEditorController pure parsing and validation', () {
    test(
      'classifies source, validates coordinates/radius, and parses m/km radii',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final controller = container.read(locationEditorControllerProvider);

        expect(controller.classifySource(null), equals(LocationSourceType.gps));
        expect(
          controller.classifySource('9F4MG9X5+XX'),
          equals(LocationSourceType.plusCode),
        );
        expect(
          controller.classifySource('Berlin, Germany'),
          equals(LocationSourceType.address),
        );
        expect(
          controller.formatGpsCoordinate(52.520008123),
          equals('52.520008'),
        );

        expect(controller.isValidCoordinates(90.0, 180.0), isTrue);
        expect(controller.isValidCoordinates(-90.0, -180.0), isTrue);
        expect(controller.isValidCoordinates(90.01, 0.0), isFalse);
        expect(controller.isValidCoordinates(0.0, -180.01), isFalse);
        expect(controller.isValidCoordinates(double.nan, 0.0), isFalse);

        expect(controller.parseRadiusInput('150'), equals(150.0));
        expect(controller.parseRadiusInput('150m'), equals(150.0));
        expect(controller.parseRadiusInput('0.5km'), equals(500.0));
        expect(controller.parseRadiusInput('100km'), equals(100000.0));
        expect(controller.parseRadiusInput('0'), isNull);
        expect(controller.parseRadiusInput('-5'), isNull);
        expect(controller.parseRadiusInput('100001'), isNull);
        expect(controller.parseRadiusInput('NaN'), isNull);
        expect(controller.parseRadiusInput(''), isNull);
      },
    );

    test('validateDraft covers all LocationValidationErrorKind branches and valid output', () {
      final container = ProviderContainer(
        overrides: [appLocaleProvider.overrideWithValue(const Locale('en'))],
      );
      addTearDown(container.dispose);
      final controller = container.read(locationEditorControllerProvider);
      final en = lookupAppLocalizations(const Locale('en'));

      final emptyName = controller.validateDraft(
        rawName: '   ',
        rawLatitude: '52.52',
        rawLongitude: '13.405',
        rawRadius: '100',
        sourceType: LocationSourceType.gps,
        rawSource: '',
        rawNote: '',
      );
      expect(emptyName.isValid, isFalse);
      expect(
        emptyName.errorKind,
        equals(LocationValidationErrorKind.emptyName),
      );
      expect(emptyName.errorMessage, equals(en.locationNameErrorEmpty));

      final badCoords = controller.validateDraft(
        rawName: 'Office',
        rawLatitude: '95.0',
        rawLongitude: '13.405',
        rawRadius: '100',
        sourceType: LocationSourceType.gps,
        rawSource: '',
        rawNote: '',
      );
      expect(
        badCoords.errorKind,
        equals(LocationValidationErrorKind.invalidCoordinates),
      );
      expect(
        badCoords.errorMessage,
        equals(en.locationCoordinatesErrorInvalid),
      );

      final badRadius = controller.validateDraft(
        rawName: 'Office',
        rawLatitude: '52.52',
        rawLongitude: '13.405',
        rawRadius: '0',
        sourceType: LocationSourceType.gps,
        rawSource: '',
        rawNote: '',
      );
      expect(
        badRadius.errorKind,
        equals(LocationValidationErrorKind.invalidRadius),
      );
      expect(badRadius.errorMessage, equals(en.locationRadiusErrorInvalid));

      final valid = controller.validateDraft(
        rawName: '  Office  ',
        rawLatitude: '52.52',
        rawLongitude: '13.405',
        rawRadius: '0.25km',
        sourceType: LocationSourceType.address,
        rawSource: '  Berlin  ',
        rawNote: '  Desk 4  ',
      );
      expect(valid.isValid, isTrue);
      expect(
        valid.draft,
        equals(
          const ValidatedLocationDraft(
            name: 'Office',
            latitude: 52.52,
            longitude: 13.405,
            radiusMeters: 250.0,
            source: 'Berlin',
            note: 'Desk 4',
          ),
        ),
      );
    });
  });

  group('LocationEditorController.resolveSource and disambiguation', () {
    test('handles gps, full Plus Code, short Plus Code, address geocoding, and maxInputLength bounds', () async {
      final fakeRepo = FakeLocationRepository();
      final container = ProviderContainer(
        overrides: [
          locationRepositoryProvider.overrideWithValue(fakeRepo),
          appLocaleProvider.overrideWithValue(const Locale('en')),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(locationEditorControllerProvider);

      // GPS mode requires no source resolution.
      expect(
        await controller.resolveSource(
          sourceType: LocationSourceType.gps,
          rawSource: 'ignored',
        ),
        isA<LocationSourceNotNeeded>(),
      );

      // maxInputLength + 1 rejected upfront without calling geocoder.
      final overLimit = await controller.resolveSource(
        sourceType: LocationSourceType.address,
        rawSource: 'a' * (PlusCodeService.maxInputLength + 1),
      );
      expect(overLimit, isA<LocationSourceResolutionError>());
      expect(fakeRepo.searchCallCount, equals(0));

      // Full Plus Code resolves offline without calling geocoder.
      final fullPlus = await controller.resolveSource(
        sourceType: LocationSourceType.plusCode,
        rawSource: '9F4MG9X5+XX Berlin',
      );
      expect(fullPlus, isA<LocationSourceResolved>());
      final resolvedFull = fullPlus as LocationSourceResolved;
      expect(resolvedFull.sourceType, equals(LocationSourceType.plusCode));
      expect(resolvedFull.normalizedSource, equals('9F4MG9X5+XX Berlin'));
      expect(fakeRepo.searchCallCount, equals(0));

      // Invalid Plus Code returns localized error.
      expect(
        await controller.resolveSource(
          sourceType: LocationSourceType.plusCode,
          rawSource: 'INVALID',
        ),
        isA<LocationSourceResolutionError>(),
      );

      // Address: 0 candidates -> error.
      fakeRepo.searchResults = const <GeocodingCandidate>[];
      expect(
        await controller.resolveSource(
          sourceType: LocationSourceType.address,
          rawSource: 'Nowhere',
        ),
        isA<LocationSourceResolutionError>(),
      );

      // Address: 1 candidate -> resolved.
      fakeRepo.searchResults = const <GeocodingCandidate>[
        GeocodingCandidate(
          displayName: 'Berlin, Germany',
          latitude: 52.52,
          longitude: 13.405,
        ),
      ];
      final singleAddr = await controller.resolveSource(
        sourceType: LocationSourceType.address,
        rawSource: 'Berlin',
      );
      expect(singleAddr, isA<LocationSourceResolved>());
      expect(
        (singleAddr as LocationSourceResolved).normalizedSource,
        equals('Berlin, Germany'),
      );

      // Address: N candidates -> disambiguation + applyDisambiguatedCandidate.
      const multiCandidates = <GeocodingCandidate>[
        GeocodingCandidate(
          displayName: 'Springfield, IL',
          latitude: 39.7817,
          longitude: -89.6501,
        ),
        GeocodingCandidate(
          displayName: 'Springfield, OR',
          latitude: 44.0462,
          longitude: -123.0220,
        ),
      ];
      fakeRepo.searchResults = multiCandidates;
      final multiAddr = await controller.resolveSource(
        sourceType: LocationSourceType.address,
        rawSource: 'Springfield',
      );
      expect(multiAddr, isA<LocationSourceNeedsDisambiguation>());
      final disambig = multiAddr as LocationSourceNeedsDisambiguation;
      expect(disambig.candidates.length, equals(2));

      final appliedAddr = controller.applyDisambiguatedCandidate(
        candidate: multiCandidates[1],
        sourceType: LocationSourceType.address,
      );
      expect(appliedAddr, isA<LocationSourceResolved>());
      expect(
        (appliedAddr as LocationSourceResolved).normalizedSource,
        equals('Springfield, OR'),
      );

      // Short Plus Code: 1 candidate resolves directly; multi candidates need disambiguation.
      fakeRepo.searchResults = const <GeocodingCandidate>[
        GeocodingCandidate(
          displayName: 'Berlin, Germany',
          latitude: 52.52,
          longitude: 13.405,
        ),
      ];
      final shortSingle = await controller.resolveSource(
        sourceType: LocationSourceType.plusCode,
        rawSource: 'G9X5+XX Berlin',
      );
      expect(shortSingle, isA<LocationSourceResolved>());
      expect(
        (shortSingle as LocationSourceResolved).normalizedSource,
        equals('G9X5+XX Berlin'),
      );

      fakeRepo.searchResults = multiCandidates;
      final shortMulti = await controller.resolveSource(
        sourceType: LocationSourceType.plusCode,
        rawSource: 'G9X5+XX Springfield',
      );
      expect(shortMulti, isA<LocationSourceNeedsDisambiguation>());
      final shortDisambig = shortMulti as LocationSourceNeedsDisambiguation;
      final appliedShort = controller.applyDisambiguatedCandidate(
        candidate: multiCandidates[0],
        sourceType: LocationSourceType.plusCode,
        shortPlusCode: shortDisambig.shortPlusCode,
        localityQuery: shortDisambig.localityQuery,
      );
      expect(appliedShort, isA<LocationSourceResolved>());
    });
  });

  group('LocationEditorController GPS lookup and CRUD', () {
    test(
      'refreshes GPS fix when missing and creates/updates/deletes locations',
      () async {
        final locationNotifier = _RecordingLocationNotifier(
          const LocationState(status: LocationStatus.unavailable),
          refreshedFix: const LocationFix(
            latitude: 52.5200089,
            longitude: 13.4049541,
          ),
        );
        final taskNotifier = _RecordingTaskNotifier();
        final container = ProviderContainer(
          overrides: [
            locationStateProvider.overrideWith(() => locationNotifier),
            taskNotifierProvider.overrideWith(() => taskNotifier),
          ],
        );
        addTearDown(container.dispose);
        await container.read(taskNotifierProvider.future);

        final controller = container.read(locationEditorControllerProvider);

        final coords = await controller.resolveCurrentGpsPosition();
        expect(locationNotifier.refreshCalls, equals(1));
        expect(coords?.latitude, closeTo(52.5200089, 1e-7));
        expect(coords?.longitude, closeTo(13.4049541, 1e-7));

        // Whitespace-only names are ignored.
        await controller.createLocationFromCurrentFix('   ');
        expect(taskNotifier.addedNames, isEmpty);

        // Rounds coordinates to 6 decimals and defaults radius to 100.0.
        await controller.createLocationFromCurrentFix('  Home  ');
        expect(taskNotifier.addedNames, equals(['Home']));
        expect(taskNotifier.lastAddedLatitude, equals(52.520009));
        expect(taskNotifier.lastAddedLongitude, equals(13.404954));
        expect(taskNotifier.lastAddedRadius, equals(100.0));

        await controller.saveLocation(
          locationId: 'loc-1',
          draft: const ValidatedLocationDraft(
            name: 'Home HQ',
            latitude: 52.52,
            longitude: 13.405,
            radiusMeters: 150.0,
            source: null,
            note: null,
          ),
        );
        expect(taskNotifier.lastUpdatedId, equals('loc-1'));
        expect(taskNotifier.lastUpdatedName, equals('Home HQ'));
        expect(taskNotifier.lastClearSource, isTrue);
        expect(taskNotifier.lastClearNote, isTrue);

        await controller.deleteLocation('loc-1');
        expect(taskNotifier.deletedIds, equals(['loc-1']));
      },
    );
  });
}
