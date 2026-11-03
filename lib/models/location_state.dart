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

import 'package:flutter/foundation.dart';

import 'tdf_metadata.dart';

/// Immutable representation of a resolved geographical location fix.
@immutable
class LocationFix {
  /// Creates a [LocationFix] with optional WGS-84 coordinates, [placeName], and [source].
  const LocationFix({
    this.latitude,
    this.longitude,
    this.placeName,
    this.source,
  });

  /// WGS-84 latitude in decimal degrees (`-90.0..90.0`), or `null` when unavailable.
  final double? latitude;

  /// WGS-84 longitude in decimal degrees (`-180.0..180.0`), or `null` when unavailable.
  final double? longitude;

  /// Human-readable locality, city, or region name, or `null` when unavailable.
  final String? placeName;

  /// Origin of the location fix (`gps`, `system`, or `internet`), or `null` when unspecified.
  final LocationSource? source;

  /// Formats [latitude] and [longitude] to 5 decimal places, or returns `null` when missing.
  String? get formattedCoordinates {
    final lat = latitude;
    final lon = longitude;
    if (lat == null || lon == null) {
      return null;
    }
    return '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
  }

  /// Whether both [latitude] and [longitude] are present.
  bool get hasCoordinates => latitude != null && longitude != null;

  /// Returns a copy of this [LocationFix] with updated fields.
  LocationFix copyWith({
    double? latitude,
    double? longitude,
    String? placeName,
    LocationSource? source,
  }) {
    return LocationFix(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      placeName: placeName ?? this.placeName,
      source: source ?? this.source,
    );
  }

  /// Returns `true` when both this fix and [other] have coordinates within [thresholdMeters].
  bool isWithinDisplacementThreshold(
    LocationFix other,
    double thresholdMeters,
  ) {
    final lat1 = latitude;
    final lon1 = longitude;
    final lat2 = other.latitude;
    final lon2 = other.longitude;
    if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) {
      return false;
    }
    final distance = LocationTaskCondition.haversineDistanceMeters(
      lat1,
      lon1,
      lat2,
      lon2,
    );
    return distance <= thresholdMeters;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationFix &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.placeName == placeName &&
        other.source == source;
  }

  @override
  int get hashCode => Object.hash(latitude, longitude, placeName, source);

  @override
  String toString() =>
      'LocationFix(placeName: $placeName, coordinates: $formattedCoordinates, source: ${source?.name})';
}

/// Origin from which a [LocationFix] was determined.
enum LocationSource {
  /// Hardware GPS or GNSS satellite receiver.
  gps,

  /// Operating system or network location service (Wi-Fi, cell, GeoClue2, or Windows Location API).
  system,

  /// IP-based GeoIP lookup over the internet.
  internet,
}

/// Immutable state snapshot of the foreground location determination service.
@immutable
class LocationState {
  /// Creates a [LocationState] with [status], optional [fix], and optional [updatedAt].
  const LocationState({required this.status, this.fix, this.updatedAt});

  /// Creates a [LocationState] representing a disabled location service.
  const LocationState.disabled()
    : status = LocationStatus.disabled,
      fix = null,
      updatedAt = null;

  /// Creates a [LocationState] representing a successful [fix] at [updatedAt].
  const LocationState.found({required LocationFix this.fix, this.updatedAt})
    : status = LocationStatus.found;

  /// Creates a [LocationState] representing an in-flight location lookup.
  const LocationState.searching({this.fix, this.updatedAt})
    : status = LocationStatus.searching;

  /// Creates a [LocationState] when no location information could be determined.
  const LocationState.unavailable({this.updatedAt})
    : status = LocationStatus.unavailable,
      fix = null;

  /// Resolved geographical location fix when [status] is [LocationStatus.found] (or preserved during refresh).
  final LocationFix? fix;

  /// Current operational status of location determination.
  final LocationStatus status;

  /// UTC timestamp when the most recent location check completed.
  final DateTime? updatedAt;

  /// Returns a copy of this [LocationState] with updated fields.
  LocationState copyWith({
    LocationStatus? status,
    LocationFix? fix,
    bool clearFix = false,
    DateTime? updatedAt,
  }) {
    return LocationState(
      status: status ?? this.status,
      fix: clearFix ? null : (fix ?? this.fix),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Evaluates whether returning the application to the foreground at [now] should trigger a refresh.
  bool shouldRefreshOnResume(DateTime now, Duration minInterval) {
    return switch (status) {
      LocationStatus.disabled => false,
      LocationStatus.searching => false,
      LocationStatus.unavailable => true,
      LocationStatus.found =>
        updatedAt == null ||
            now.difference(updatedAt ?? now).compareTo(minInterval) >= 0,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationState &&
        other.status == status &&
        other.fix == fix &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(status, fix, updatedAt);

  @override
  String toString() =>
      'LocationState(status: ${status.name}, fix: $fix, updatedAt: $updatedAt)';
}

/// Operational status of foreground location determination.
enum LocationStatus {
  /// Location determination is turned off in settings.
  disabled,

  /// Location determination is active and currently acquiring a fix.
  searching,

  /// Location determination is active and a place or coordinate fix is available.
  found,

  /// Location determination is active, but no location information could be obtained.
  unavailable,
}
