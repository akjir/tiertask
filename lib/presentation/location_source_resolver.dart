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

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/location_state.dart';
import '../models/tdf_location.dart';
import '../providers/config_providers.dart';
import '../providers/location_providers.dart';
import '../services/plus_code_service.dart';

/// Provides [LocationSourceResolver] for Plus Code decoding, forward geocoding, and foreground GPS lookup.
final locationSourceResolverProvider = Provider<LocationSourceResolver>(
  LocationSourceResolver.new,
);

/// Sealed result returned by [LocationSourceResolver.resolveSource] and [LocationSourceResolver.applyDisambiguatedCandidate].
sealed class LocationSourceResolutionResult {
  /// Creates a [LocationSourceResolutionResult].
  const LocationSourceResolutionResult();
}

/// Result returned when forward geocoding yields multiple [GeocodingCandidate] choices requiring user selection.
@immutable
final class LocationSourceNeedsDisambiguation
    extends LocationSourceResolutionResult {
  /// Creates a [LocationSourceNeedsDisambiguation] carrying an unmodifiable [candidates] list.
  LocationSourceNeedsDisambiguation({
    required Iterable<GeocodingCandidate> candidates,
    required this.sourceType,
    this.shortPlusCode,
    this.localityQuery,
  }) : candidates = List<GeocodingCandidate>.unmodifiable(candidates);

  /// Ranked geocoding candidates to present to the user.
  final List<GeocodingCandidate> candidates;

  /// Locality query accompanying a short Plus Code, or `null` for address mode.
  final String? localityQuery;

  /// Short Plus Code awaiting reference-coordinate recovery, or `null` for address mode.
  final String? shortPlusCode;

  /// Active [LocationSourceType] being resolved.
  final LocationSourceType sourceType;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationSourceNeedsDisambiguation &&
        other.sourceType == sourceType &&
        other.shortPlusCode == shortPlusCode &&
        other.localityQuery == localityQuery &&
        listEquals(other.candidates, candidates);
  }

  @override
  int get hashCode => Object.hash(
    sourceType,
    shortPlusCode,
    localityQuery,
    Object.hashAll(candidates),
  );
}

/// Result returned when `LocationSourceType.gps` requires no external source lookup.
@immutable
final class LocationSourceNotNeeded extends LocationSourceResolutionResult {
  /// Creates a [LocationSourceNotNeeded] result.
  const LocationSourceNotNeeded();
}

/// Result returned when source input is invalid, exceeds bounds, or yields zero matches.
@immutable
final class LocationSourceResolutionError
    extends LocationSourceResolutionResult {
  /// Creates a [LocationSourceResolutionError] with [localizedMessage].
  const LocationSourceResolutionError(this.localizedMessage);

  /// Localized inline validation message for the coordinate/source card.
  final String localizedMessage;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationSourceResolutionError &&
        other.localizedMessage == localizedMessage;
  }

  @override
  int get hashCode => localizedMessage.hashCode;
}

/// Result returned when a source input resolves into WGS-84 coordinates and a normalized source string.
@immutable
final class LocationSourceResolved extends LocationSourceResolutionResult {
  /// Creates a [LocationSourceResolved] result.
  const LocationSourceResolved({
    required this.latitude,
    required this.longitude,
    required this.normalizedSource,
    required this.sourceType,
  });

  /// Resolved WGS-84 latitude in decimal degrees.
  final double latitude;

  /// Resolved WGS-84 longitude in decimal degrees.
  final double longitude;

  /// Canonical source label persisted alongside the coordinates.
  final String normalizedSource;

  /// Source mode under which coordinates were resolved.
  final LocationSourceType sourceType;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationSourceResolved &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.normalizedSource == normalizedSource &&
        other.sourceType == sourceType;
  }

  @override
  int get hashCode =>
      Object.hash(latitude, longitude, normalizedSource, sourceType);
}

/// Presentation resolver owning Plus Code decoding, forward geocoding, and foreground GPS position lookup.
class LocationSourceResolver {
  /// Creates a [LocationSourceResolver] backed by [_ref].
  const LocationSourceResolver(this._ref);

  final Ref _ref;

  /// Applies a user-selected [GeocodingCandidate] for address or short Plus Code resolution.
  LocationSourceResolutionResult applyDisambiguatedCandidate({
    required GeocodingCandidate candidate,
    required LocationSourceType sourceType,
    String? shortPlusCode,
    String? localityQuery,
    Locale? locale,
  }) {
    return switch (sourceType) {
      LocationSourceType.gps => const LocationSourceNotNeeded(),
      LocationSourceType.address => LocationSourceResolved(
        latitude: candidate.latitude,
        longitude: candidate.longitude,
        normalizedSource: candidate.displayName,
        sourceType: LocationSourceType.address,
      ),
      LocationSourceType.plusCode => _recoverShortPlusCode(
        shortCode: shortPlusCode ?? '',
        localityQuery: localityQuery ?? '',
        reference: candidate,
        localizations: lookupAppLocalizations(
          locale ?? _ref.read(appLocaleProvider),
        ),
      ),
    };
  }

  /// Classifies a persisted location [rawSource] into its [LocationSourceType].
  LocationSourceType classifySource(String? rawSource) =>
      PlusCodeService.classifySource(rawSource);

  /// Rounds [value] to at most 6 decimal places and formats it canonically.
  String formatGpsCoordinate(double value) =>
      TdfLocation.formatRoundedDouble(value, 6);

  /// Checks whether [latitude] and [longitude] are finite WGS-84 coordinates.
  bool isValidCoordinates(double latitude, double longitude) =>
      !latitude.isNaN &&
      !latitude.isInfinite &&
      latitude >= -90.0 &&
      latitude <= 90.0 &&
      !longitude.isNaN &&
      !longitude.isInfinite &&
      longitude >= -180.0 &&
      longitude <= 180.0;

  /// Reads the current GPS coordinates, triggering [LocationNotifier.refreshLocation] when absent.
  Future<({double latitude, double longitude})?>
  resolveCurrentGpsPosition() async {
    var fix = _ref.read(locationStateProvider).fix;
    if (fix == null || !fix.hasCoordinates) {
      await _ref.read(locationStateProvider.notifier).refreshLocation();
      fix = _ref.read(locationStateProvider).fix;
    }
    if ((fix?.latitude, fix?.longitude) case (
      final latitude?,
      final longitude?,
    )) {
      return (latitude: latitude, longitude: longitude);
    }
    return null;
  }

  /// Resolves [rawSource] according to [sourceType], enforcing [PlusCodeService.maxInputLength] upfront.
  Future<LocationSourceResolutionResult> resolveSource({
    required LocationSourceType sourceType,
    required String rawSource,
    Locale? locale,
  }) async {
    if (sourceType == LocationSourceType.gps) {
      return const LocationSourceNotNeeded();
    }
    final localizations = lookupAppLocalizations(
      locale ?? _ref.read(appLocaleProvider),
    );
    final trimmedSource = rawSource.trim();
    if (trimmedSource.isEmpty ||
        trimmedSource.length > PlusCodeService.maxInputLength) {
      return LocationSourceResolutionError(
        sourceType == LocationSourceType.plusCode
            ? localizations.locationResolveErrorInvalidPlusCode
            : localizations.locationResolveErrorNotFound,
      );
    }
    return switch (sourceType) {
      LocationSourceType.gps => const LocationSourceNotNeeded(),
      LocationSourceType.address => _resolveAddress(
        trimmedSource,
        localizations,
      ),
      LocationSourceType.plusCode => _resolvePlusCode(
        trimmedSource,
        localizations,
      ),
    };
  }

  /// Decodes a full Plus Code offline and formats its canonical source text.
  LocationSourceResolutionResult _decodeFullPlusCode(
    String fullCode,
    String? localitySuffix,
    AppLocalizations localizations,
  ) {
    final area = PlusCodeService.decode(fullCode);
    if (area == null) {
      return LocationSourceResolutionError(
        localizations.locationResolveErrorInvalidPlusCode,
      );
    }
    final formattedSource = PlusCodeService.truncateToMaxTextLength(
      localitySuffix == null || localitySuffix.isEmpty
          ? fullCode
          : '$fullCode $localitySuffix',
    );
    return LocationSourceResolved(
      latitude: area.latitudeCenter,
      longitude: area.longitudeCenter,
      normalizedSource: formattedSource,
      sourceType: LocationSourceType.plusCode,
    );
  }

  /// Recovers and decodes a short Plus Code using [reference] coordinates.
  LocationSourceResolutionResult _recoverShortPlusCode({
    required String shortCode,
    required String localityQuery,
    required GeocodingCandidate reference,
    required AppLocalizations localizations,
  }) {
    final fullCode = PlusCodeService.recoverNearest(
      shortCode,
      reference.latitude,
      reference.longitude,
    );
    final area = fullCode == null ? null : PlusCodeService.decode(fullCode);
    if (area == null) {
      return LocationSourceResolutionError(
        localizations.locationResolveErrorInvalidPlusCode,
      );
    }
    final formattedSource = PlusCodeService.truncateToMaxTextLength(
      '$shortCode $localityQuery',
    );
    return LocationSourceResolved(
      latitude: area.latitudeCenter,
      longitude: area.longitudeCenter,
      normalizedSource: formattedSource,
      sourceType: LocationSourceType.plusCode,
    );
  }

  /// Resolves an address query via forward geocoding.
  Future<LocationSourceResolutionResult> _resolveAddress(
    String trimmedSource,
    AppLocalizations localizations,
  ) async {
    final candidates = await _ref
        .read(locationRepositoryProvider)
        .searchLocations(trimmedSource);
    if (candidates.isEmpty) {
      return LocationSourceResolutionError(
        localizations.locationResolveErrorNotFound,
      );
    }
    if (candidates.length == 1) {
      final match = candidates.first;
      return LocationSourceResolved(
        latitude: match.latitude,
        longitude: match.longitude,
        normalizedSource: match.displayName,
        sourceType: LocationSourceType.address,
      );
    }
    return LocationSourceNeedsDisambiguation(
      candidates: candidates,
      sourceType: LocationSourceType.address,
    );
  }

  /// Parses and resolves a full or short Google Plus Code.
  Future<LocationSourceResolutionResult> _resolvePlusCode(
    String trimmedSource,
    AppLocalizations localizations,
  ) async {
    return switch (PlusCodeService.parseInput(trimmedSource)) {
      InvalidPlusCodeInput() => LocationSourceResolutionError(
        localizations.locationResolveErrorInvalidPlusCode,
      ),
      FullPlusCodeInput(:final fullCode, :final localitySuffix) =>
        _decodeFullPlusCode(fullCode, localitySuffix, localizations),
      ShortPlusCodeInput(:final localityQuery, :final shortCode) =>
        _resolveShortPlusCode(
          shortCode: shortCode,
          localityQuery: localityQuery,
          localizations: localizations,
        ),
    };
  }

  /// Geocodes [localityQuery] for a short Plus Code and recovers coordinates or returns disambiguation choices.
  Future<LocationSourceResolutionResult> _resolveShortPlusCode({
    required String shortCode,
    required String localityQuery,
    required AppLocalizations localizations,
  }) async {
    final candidates = await _ref
        .read(locationRepositoryProvider)
        .searchLocations(localityQuery);
    if (candidates.isEmpty) {
      return LocationSourceResolutionError(
        localizations.locationResolveErrorNotFound,
      );
    }
    if (candidates.length == 1) {
      return _recoverShortPlusCode(
        shortCode: shortCode,
        localityQuery: localityQuery,
        reference: candidates.first,
        localizations: localizations,
      );
    }
    return LocationSourceNeedsDisambiguation(
      candidates: candidates,
      sourceType: LocationSourceType.plusCode,
      shortPlusCode: shortCode,
      localityQuery: localityQuery,
    );
  }
}
