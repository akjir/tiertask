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
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/location_providers.dart';
import 'package:tiertask/providers/location_source_resolver.dart';
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

void main() {
  group('LocationSourceResolver pure parsing and validation', () {
    test(
      'classifies source, formats GPS coordinates, and validates WGS-84 bounds',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final resolver = container.read(locationSourceResolverProvider);

        expect(resolver.classifySource(null), equals(LocationSourceType.gps));
        expect(
          resolver.classifySource('9F4MG9X5+XX'),
          equals(LocationSourceType.plusCode),
        );
        expect(
          resolver.classifySource('Berlin, Germany'),
          equals(LocationSourceType.address),
        );
        expect(resolver.formatGpsCoordinate(52.520008123), equals('52.520008'));

        expect(resolver.isValidCoordinates(90.0, 180.0), isTrue);
        expect(resolver.isValidCoordinates(-90.0, -180.0), isTrue);
        expect(resolver.isValidCoordinates(90.01, 0.0), isFalse);
        expect(resolver.isValidCoordinates(-90.01, 0.0), isFalse);
        expect(resolver.isValidCoordinates(0.0, -180.01), isFalse);
        expect(resolver.isValidCoordinates(0.0, 180.01), isFalse);
        expect(resolver.isValidCoordinates(double.nan, 0.0), isFalse);
        expect(resolver.isValidCoordinates(double.infinity, 0.0), isFalse);
        expect(
          resolver.isValidCoordinates(0.0, double.negativeInfinity),
          isFalse,
        );
      },
    );

    test('supports value equality, hashCode, and unmodifiable candidates across result variants', () {
      const candidateA = GeocodingCandidate(
        displayName: 'Berlin, Germany',
        latitude: 52.52,
        longitude: 13.405,
      );
      const candidateB = GeocodingCandidate(
        displayName: 'Munich, Germany',
        latitude: 48.1351,
        longitude: 11.582,
      );

      final mutableCandidates = <GeocodingCandidate>[candidateA];
      final disambiguationA = LocationSourceNeedsDisambiguation(
        candidates: mutableCandidates,
        sourceType: LocationSourceType.plusCode,
        shortPlusCode: 'G9X5+XX',
        localityQuery: 'Berlin',
      );
      final disambiguationB = LocationSourceNeedsDisambiguation(
        candidates: const <GeocodingCandidate>[candidateA],
        sourceType: LocationSourceType.plusCode,
        shortPlusCode: 'G9X5+XX',
        localityQuery: 'Berlin',
      );
      mutableCandidates.add(candidateB);
      expect(disambiguationA.candidates.length, equals(1));
      expect(
        () => disambiguationA.candidates.add(candidateB),
        throwsUnsupportedError,
      );
      expect(disambiguationA, equals(disambiguationB));
      expect(disambiguationA.hashCode, equals(disambiguationB.hashCode));

      const errorA = LocationSourceResolutionError('not found');
      const errorB = LocationSourceResolutionError('not found');
      expect(errorA, equals(errorB));
      expect(errorA.hashCode, equals(errorB.hashCode));

      const resolvedA = LocationSourceResolved(
        latitude: 52.52,
        longitude: 13.405,
        normalizedSource: 'Berlin, Germany',
        sourceType: LocationSourceType.address,
      );
      const resolvedB = LocationSourceResolved(
        latitude: 52.52,
        longitude: 13.405,
        normalizedSource: 'Berlin, Germany',
        sourceType: LocationSourceType.address,
      );
      expect(resolvedA, equals(resolvedB));
      expect(resolvedA.hashCode, equals(resolvedB.hashCode));
      expect(
        const LocationSourceNotNeeded(),
        isA<LocationSourceResolutionResult>(),
      );
    });
  });

  group('LocationSourceResolver.resolveSource and disambiguation', () {
    test('handles gps, full Plus Code, short Plus Code, address geocoding, and maxInputLength bounds', () async {
      final fakeRepository = FakeLocationRepository();
      final container = ProviderContainer(
        overrides: [
          locationRepositoryProvider.overrideWithValue(fakeRepository),
          appLocaleProvider.overrideWithValue(const Locale('en')),
        ],
      );
      addTearDown(container.dispose);
      final resolver = container.read(locationSourceResolverProvider);

      // GPS mode requires no source resolution.
      expect(
        await resolver.resolveSource(
          sourceType: LocationSourceType.gps,
          rawSource: 'ignored',
        ),
        isA<LocationSourceNotNeeded>(),
      );

      // Empty/whitespace and maxInputLength + 1 rejected upfront without calling geocoder.
      expect(
        await resolver.resolveSource(
          sourceType: LocationSourceType.address,
          rawSource: '   ',
        ),
        isA<LocationSourceResolutionError>(),
      );
      final overLimit = await resolver.resolveSource(
        sourceType: LocationSourceType.address,
        rawSource: 'a' * (PlusCodeService.maxInputLength + 1),
      );
      expect(overLimit, isA<LocationSourceResolutionError>());
      expect(fakeRepository.searchCallCount, equals(0));

      // Full Plus Code resolves offline without calling geocoder.
      final fullPlus = await resolver.resolveSource(
        sourceType: LocationSourceType.plusCode,
        rawSource: '9F4MG9X5+XX Berlin',
      );
      if (fullPlus case LocationSourceResolved(
        :final sourceType,
        :final normalizedSource,
      )) {
        expect(sourceType, equals(LocationSourceType.plusCode));
        expect(normalizedSource, equals('9F4MG9X5+XX Berlin'));
      } else {
        fail('Expected LocationSourceResolved for full Plus Code');
      }
      expect(fakeRepository.searchCallCount, equals(0));

      // Invalid Plus Code returns localized error.
      expect(
        await resolver.resolveSource(
          sourceType: LocationSourceType.plusCode,
          rawSource: 'INVALID',
        ),
        isA<LocationSourceResolutionError>(),
      );

      // Address: 0 candidates -> error.
      fakeRepository.searchResults = const <GeocodingCandidate>[];
      expect(
        await resolver.resolveSource(
          sourceType: LocationSourceType.address,
          rawSource: 'Nowhere',
        ),
        isA<LocationSourceResolutionError>(),
      );

      // Address: 1 candidate -> resolved.
      fakeRepository.searchResults = const <GeocodingCandidate>[
        GeocodingCandidate(
          displayName: 'Berlin, Germany',
          latitude: 52.52,
          longitude: 13.405,
        ),
      ];
      final singleAddress = await resolver.resolveSource(
        sourceType: LocationSourceType.address,
        rawSource: 'Berlin',
      );
      if (singleAddress case LocationSourceResolved(:final normalizedSource)) {
        expect(normalizedSource, equals('Berlin, Germany'));
      } else {
        fail('Expected LocationSourceResolved for single address match');
      }

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
      fakeRepository.searchResults = multiCandidates;
      final multiAddress = await resolver.resolveSource(
        sourceType: LocationSourceType.address,
        rawSource: 'Springfield',
      );
      if (multiAddress case LocationSourceNeedsDisambiguation(
        :final candidates,
      )) {
        expect(candidates.length, equals(2));
      } else {
        fail('Expected LocationSourceNeedsDisambiguation for multi address');
      }

      final appliedAddress = resolver.applyDisambiguatedCandidate(
        candidate: multiCandidates[1],
        sourceType: LocationSourceType.address,
      );
      if (appliedAddress case LocationSourceResolved(:final normalizedSource)) {
        expect(normalizedSource, equals('Springfield, OR'));
      } else {
        fail('Expected LocationSourceResolved after address disambiguation');
      }

      expect(
        resolver.applyDisambiguatedCandidate(
          candidate: multiCandidates[0],
          sourceType: LocationSourceType.gps,
        ),
        isA<LocationSourceNotNeeded>(),
      );

      // Short Plus Code: 0 candidates -> error.
      fakeRepository.searchResults = const <GeocodingCandidate>[];
      expect(
        await resolver.resolveSource(
          sourceType: LocationSourceType.plusCode,
          rawSource: 'G9X5+XX Nowhere',
        ),
        isA<LocationSourceResolutionError>(),
      );

      // Short Plus Code: 1 candidate resolves directly; multi candidates need disambiguation.
      fakeRepository.searchResults = const <GeocodingCandidate>[
        GeocodingCandidate(
          displayName: 'Berlin, Germany',
          latitude: 52.52,
          longitude: 13.405,
        ),
      ];
      final shortSingle = await resolver.resolveSource(
        sourceType: LocationSourceType.plusCode,
        rawSource: 'G9X5+XX Berlin',
      );
      if (shortSingle case LocationSourceResolved(:final normalizedSource)) {
        expect(normalizedSource, equals('G9X5+XX Berlin'));
      } else {
        fail('Expected LocationSourceResolved for single short Plus Code');
      }

      fakeRepository.searchResults = multiCandidates;
      final shortMulti = await resolver.resolveSource(
        sourceType: LocationSourceType.plusCode,
        rawSource: 'G9X5+XX Springfield',
      );
      if (shortMulti case LocationSourceNeedsDisambiguation(
        :final shortPlusCode,
        :final localityQuery,
      )) {
        final appliedShort = resolver.applyDisambiguatedCandidate(
          candidate: multiCandidates[0],
          sourceType: LocationSourceType.plusCode,
          shortPlusCode: shortPlusCode,
          localityQuery: localityQuery,
        );
        expect(appliedShort, isA<LocationSourceResolved>());
      } else {
        fail(
          'Expected LocationSourceNeedsDisambiguation for multi short Plus Code',
        );
      }

      // Invalid shortPlusCode in applyDisambiguatedCandidate returns error.
      expect(
        resolver.applyDisambiguatedCandidate(
          candidate: multiCandidates[0],
          sourceType: LocationSourceType.plusCode,
          shortPlusCode: 'INVALID',
          localityQuery: 'Springfield',
        ),
        isA<LocationSourceResolutionError>(),
      );
    });
  });

  group('LocationSourceResolver GPS lookup', () {
    test(
      'refreshes GPS fix when missing and returns resolved coordinates',
      () async {
        final locationNotifier = _RecordingLocationNotifier(
          const LocationState(status: LocationStatus.unavailable),
          refreshedFix: const LocationFix(
            latitude: 52.5200089,
            longitude: 13.4049541,
          ),
        );
        final container = ProviderContainer(
          overrides: [
            locationStateProvider.overrideWith(() => locationNotifier),
          ],
        );
        addTearDown(container.dispose);

        final resolver = container.read(locationSourceResolverProvider);

        final coordinates = await resolver.resolveCurrentGpsPosition();
        expect(locationNotifier.refreshCalls, equals(1));
        expect(coordinates?.latitude, closeTo(52.5200089, 1e-7));
        expect(coordinates?.longitude, closeTo(13.4049541, 1e-7));
      },
    );

    test('reuses cached GPS fix without refreshing and returns null when unavailable', () async {
      final cachedNotifier = _RecordingLocationNotifier(
        const LocationState(
          status: LocationStatus.found,
          fix: LocationFix(latitude: 48.1351, longitude: 11.582),
        ),
      );
      final cachedContainer = ProviderContainer(
        overrides: [locationStateProvider.overrideWith(() => cachedNotifier)],
      );
      addTearDown(cachedContainer.dispose);

      final cachedCoordinates = await cachedContainer
          .read(locationSourceResolverProvider)
          .resolveCurrentGpsPosition();
      expect(cachedNotifier.refreshCalls, equals(0));
      expect(cachedCoordinates?.latitude, closeTo(48.1351, 1e-7));
      expect(cachedCoordinates?.longitude, closeTo(11.582, 1e-7));

      final missingNotifier = _RecordingLocationNotifier(
        const LocationState(status: LocationStatus.unavailable),
      );
      final missingContainer = ProviderContainer(
        overrides: [locationStateProvider.overrideWith(() => missingNotifier)],
      );
      addTearDown(missingContainer.dispose);

      final missingCoordinates = await missingContainer
          .read(locationSourceResolverProvider)
          .resolveCurrentGpsPosition();
      expect(missingNotifier.refreshCalls, equals(1));
      expect(missingCoordinates, isNull);
    });
  });
}
