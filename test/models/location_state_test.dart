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
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/webdav_config.dart';

void main() {
  group('LocationFix & LocationState Domain Models', () {
    test('formats WGS-84 coordinates, evaluates 100-meter Haversine displacement threshold, and preserves value equality', () {
      const erfurtFix = LocationFix(
        latitude: 50.9787,
        longitude: 11.0328,
        placeName: 'Erfurt',
        source: LocationSource.gps,
      );
      const nearbyFix = LocationFix(
        latitude: 50.9790,
        longitude: 11.0330,
        placeName: 'Erfurt Center',
      );
      const distantFix = LocationFix(
        latitude: 52.5200,
        longitude: 13.4050,
        placeName: 'Berlin',
      );
      const placeOnlyFix = LocationFix(placeName: 'Munich');

      expect(
        erfurtFix.hasCoordinates,
        isTrue,
        reason: 'Fix with latitude and longitude must report hasCoordinates',
      );
      expect(
        erfurtFix.formattedCoordinates,
        equals('50.97870, 11.03280'),
        reason: 'formattedCoordinates must format to 5 decimal places',
      );
      expect(
        placeOnlyFix.hasCoordinates,
        isFalse,
        reason: 'Fix without coordinates must report hasCoordinates false',
      );
      expect(
        placeOnlyFix.formattedCoordinates,
        isNull,
        reason: 'Fix without coordinates must return null formattedCoordinates',
      );

      expect(
        erfurtFix.isWithinDisplacementThreshold(erfurtFix, 0.0),
        isTrue,
        reason: 'Identical coordinates must be within 0.0m threshold boundary',
      );
      expect(
        erfurtFix.isWithinDisplacementThreshold(nearbyFix, 100.0),
        isTrue,
        reason: 'Points ~36m apart must be within 100m threshold',
      );
      expect(
        erfurtFix.isWithinDisplacementThreshold(distantFix, 100.0),
        isFalse,
        reason: 'Points >200km apart must exceed 100m threshold',
      );
      expect(
        erfurtFix.isWithinDisplacementThreshold(placeOnlyFix, 100.0),
        isFalse,
        reason: 'Comparison with missing target coordinates must return false',
      );
      expect(
        placeOnlyFix.isWithinDisplacementThreshold(erfurtFix, 100.0),
        isFalse,
        reason:
            'Comparison with missing receiver coordinates must return false',
      );

      final updatedFix = erfurtFix.copyWith(placeName: 'Erfurt, Germany');
      expect(
        updatedFix.placeName,
        equals('Erfurt, Germany'),
        reason: 'copyWith must update placeName while keeping coordinates',
      );
      expect(
        updatedFix.latitude,
        equals(50.9787),
        reason: 'copyWith must preserve latitude',
      );
      expect(
        updatedFix.source,
        equals(LocationSource.gps),
        reason: 'copyWith must preserve LocationSource',
      );
      for (final source in LocationSource.values) {
        final withSource = erfurtFix.copyWith(source: source);
        expect(
          withSource.source,
          equals(source),
          reason: 'copyWith must update source to ${source.name}',
        );
      }
      expect(
        erfurtFix,
        equals(
          const LocationFix(
            latitude: 50.9787,
            longitude: 11.0328,
            placeName: 'Erfurt',
            source: LocationSource.gps,
          ),
        ),
        reason: 'Identical LocationFix instances must be equal',
      );
      expect(
        erfurtFix.hashCode,
        equals(
          const LocationFix(
            latitude: 50.9787,
            longitude: 11.0328,
            placeName: 'Erfurt',
            source: LocationSource.gps,
          ).hashCode,
        ),
        reason: 'Identical LocationFix instances must share hashCode',
      );
      expect(
        erfurtFix.toString(),
        contains('Erfurt'),
        reason: 'LocationFix.toString must include placeName',
      );
    });

    test('enforces resume refresh cooldown boundaries across all LocationStatus variants', () {
      final baseTime = DateTime.utc(2026, 11, 3, 12, 0, 0);
      const minInterval = Duration(minutes: 5);
      const fix = LocationFix(
        latitude: 50.9787,
        longitude: 11.0328,
        placeName: 'Erfurt',
      );

      const disabledState = LocationState.disabled();
      const searchingState = LocationState.searching();
      final unavailableState = LocationState.unavailable(updatedAt: baseTime);
      const foundWithoutTimestamp = LocationState(
        status: LocationStatus.found,
        fix: fix,
      );
      final foundState = LocationState.found(fix: fix, updatedAt: baseTime);

      expect(
        disabledState.shouldRefreshOnResume(
          baseTime.add(const Duration(minutes: 10)),
          minInterval,
        ),
        isFalse,
        reason: 'Disabled state must never refresh on resume',
      );
      expect(
        searchingState.shouldRefreshOnResume(
          baseTime.add(const Duration(minutes: 10)),
          minInterval,
        ),
        isFalse,
        reason: 'Searching state is already in flight and must not re-trigger',
      );
      expect(
        unavailableState.shouldRefreshOnResume(
          baseTime.add(const Duration(seconds: 10)),
          minInterval,
        ),
        isTrue,
        reason: 'Unavailable state must retry immediately on app resume',
      );
      expect(
        foundWithoutTimestamp.shouldRefreshOnResume(baseTime, minInterval),
        isTrue,
        reason: 'Found state without updatedAt timestamp must refresh',
      );
      expect(
        foundState.shouldRefreshOnResume(
          baseTime.add(const Duration(minutes: 4, seconds: 59)),
          minInterval,
        ),
        isFalse,
        reason: 'Found state at 4m 59s (< 5m cooldown) must not refresh',
      );
      expect(
        foundState.shouldRefreshOnResume(
          baseTime.add(const Duration(minutes: 5)),
          minInterval,
        ),
        isTrue,
        reason: 'Found state at exact 5m 00s cooldown boundary must refresh',
      );
      expect(
        foundState.shouldRefreshOnResume(
          baseTime.add(const Duration(minutes: 5, seconds: 1)),
          minInterval,
        ),
        isTrue,
        reason: 'Found state at 5m 01s (> 5m cooldown) must refresh',
      );

      final copied = foundState.copyWith(status: LocationStatus.searching);
      expect(
        copied.status,
        equals(LocationStatus.searching),
        reason: 'copyWith must update status',
      );
      expect(
        copied.fix,
        equals(fix),
        reason: 'copyWith must preserve existing fix when not cleared',
      );
      final cleared = foundState.copyWith(
        status: LocationStatus.unavailable,
        clearFix: true,
      );
      expect(
        cleared.fix,
        isNull,
        reason: 'copyWith(clearFix: true) must clear fix',
      );
      expect(
        foundState.hashCode,
        equals(LocationState.found(fix: fix, updatedAt: baseTime).hashCode),
        reason: 'Equal LocationState instances must have matching hashCode',
      );
      expect(
        foundState.toString(),
        contains('found'),
        reason: 'LocationState.toString must include status name',
      );
    });
  });

  group('WebDavConfig.locationEnabled & TTW\\x01 Binary Persistence', () {
    test('defaults locationEnabled to false and round-trips locationEnabled in TTW\\x01 binary workspace records', () {
      const defaultConfig = WebDavConfig();
      expect(
        defaultConfig.locationEnabled,
        isFalse,
        reason: 'locationEnabled must default to false',
      );

      final enabledConfig = defaultConfig.copyWith(
        locationEnabled: true,
        timeZoneMode: AppTimeZoneMode.manual,
        manualTimeZoneOffsetMinutes: 60,
      );
      expect(
        enabledConfig.locationEnabled,
        isTrue,
        reason: 'copyWith(locationEnabled: true) must enable location',
      );
      expect(
        enabledConfig,
        isNot(equals(defaultConfig)),
        reason: 'Toggling locationEnabled must change WebDavConfig equality',
      );

      final workspaceEnabled = AppWorkspace.defaultWorkspace.copyWith(
        config: enabledConfig,
      );
      final encodedEnabled = workspaceEnabled.toBytes();
      expect(
        encodedEnabled.length,
        equals(51),
        reason: 'Encoding locationEnabled in tzWord bit 14 must keep 51-byte record size',
      );

      final decodedEnabled = AppWorkspace.fromBytes(encodedEnabled);
      expect(
        decodedEnabled,
        equals(workspaceEnabled),
        reason:
            'Decoded workspace must equal original with locationEnabled: true',
      );
      expect(
        decodedEnabled.config.locationEnabled,
        isTrue,
        reason: 'Decoded config must preserve locationEnabled: true',
      );
      expect(
        decodedEnabled.config.timeZoneMode,
        equals(AppTimeZoneMode.manual),
        reason: 'Decoded config must preserve timeZoneMode alongside bit 14',
      );
      expect(
        decodedEnabled.config.manualTimeZoneOffsetMinutes,
        equals(60),
        reason: 'Decoded config must preserve manualTimeZoneOffsetMinutes',
      );

      final encodedDefault = AppWorkspace.defaultWorkspace.toBytes();
      final decodedDefault = AppWorkspace.fromBytes(encodedDefault);
      expect(
        decodedDefault.config.locationEnabled,
        isFalse,
        reason: 'Default binary record must decode locationEnabled: false',
      );
    });
  });

  group('LocationSourceType & GeocodingCandidate Domain Models', () {
    test('defines exhaustive LocationSourceType values and formats GeocodingCandidate coordinates to at most 6 decimal places', () {
      expect(
        LocationSourceType.values,
        equals(const <LocationSourceType>[
          LocationSourceType.gps,
          LocationSourceType.address,
          LocationSourceType.plusCode,
        ]),
        reason: 'LocationSourceType must define gps, address, and plusCode',
      );

      const candidate1 = GeocodingCandidate(
        displayName: 'Willy-Brandt-Platz 1, 99084 Erfurt, Germany',
        latitude: 50.97256789,
        longitude: 11.03781234,
      );
      const candidate1Duplicate = GeocodingCandidate(
        displayName: 'Willy-Brandt-Platz 1, 99084 Erfurt, Germany',
        latitude: 50.97256789,
        longitude: 11.03781234,
      );
      const candidate2 = GeocodingCandidate(
        displayName: 'Alexanderplatz, 10178 Berlin, Germany',
        latitude: 52.52,
        longitude: 13.405,
      );

      expect(
        candidate1.formattedCoordinates,
        equals('50.972568, 11.037812'),
        reason: 'formattedCoordinates must round to at most 6 decimal places matching TdfLocation.formatRoundedDouble',
      );
      expect(
        candidate2.formattedCoordinates,
        equals('52.52, 13.405'),
        reason: 'formattedCoordinates must strip trailing zeros after rounding to 6 decimals',
      );
      expect(
        candidate1,
        equals(candidate1Duplicate),
        reason: 'Identical GeocodingCandidate instances must be equal',
      );
      expect(
        candidate1.hashCode,
        equals(candidate1Duplicate.hashCode),
        reason: 'Identical GeocodingCandidate instances must share hashCode',
      );
      expect(
        candidate1,
        isNot(equals(candidate2)),
        reason: 'Distinct GeocodingCandidate instances must not be equal',
      );
      expect(
        candidate1.toString(),
        contains('Willy-Brandt-Platz 1'),
        reason: 'GeocodingCandidate.toString must include displayName',
      );
    });
  });
}
