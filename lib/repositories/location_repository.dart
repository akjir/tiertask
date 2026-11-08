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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/location_state.dart';
import '../services/app_logger.dart';

/// In-memory [LocationRepository] implementation for deterministic unit and widget tests.
class FakeLocationRepository implements LocationRepository {
  /// Creates a [FakeLocationRepository] returning [initialFix].
  FakeLocationRepository({LocationFix? initialFix}) : currentFix = initialFix;

  /// Total number of [determineLocation] invocations.
  int callCount = 0;

  /// Current [LocationFix] returned by [determineLocation].
  LocationFix? currentFix;

  /// Value of `forceRefresh` passed to the most recent [determineLocation] call.
  bool lastForceRefresh = false;

  @override
  Future<LocationFix?> determineLocation({bool forceRefresh = false}) async {
    callCount++;
    lastForceRefresh = forceRefresh;
    return currentFix;
  }
}

/// Contract for resolving the user's current foreground location and place name.
abstract interface class LocationRepository {
  /// Resolves the current [LocationFix], or returns `null` when unavailable.
  Future<LocationFix?> determineLocation({bool forceRefresh = false});
}

/// Platform-backed [LocationRepository] combining the native OS location channel with bounded geocoding and GeoIP fallback.
class PlatformLocationRepository implements LocationRepository {
  /// Creates a [PlatformLocationRepository] with optional test overrides.
  PlatformLocationRepository({
    MethodChannel? channel,
    HttpClient Function()? clientFactory,
    DateTime Function()? clock,
    this.connectionTimeout = defaultConnectionTimeout,
    Uri? fallbackGeoIpUri,
    Uri? geoIpUri,
    this.maxResponseBytes = defaultMaxResponseBytes,
    Uri Function(double latitude, double longitude)? reverseGeocodeUriBuilder,
    Uri? wifiGeolocateUri,
  }) : _channel = channel ?? locationChannel,
       _clientFactory = clientFactory ?? HttpClient.new,
       _clock = clock ?? DateTime.now,
       _fallbackGeoIpUri = fallbackGeoIpUri ?? defaultFallbackGeoIpUri,
       _geoIpUri = geoIpUri ?? defaultGeoIpUri,
       _reverseGeocodeUriBuilder =
           reverseGeocodeUriBuilder ?? _defaultReverseGeocodeUri,
       _wifiGeolocateUri = wifiGeolocateUri ?? defaultWifiGeolocateUri;

  /// Default timeout for HTTP reverse-geocoding and GeoIP requests.
  static const Duration defaultConnectionTimeout = Duration(seconds: 8);

  /// Secondary HTTPS GeoIP fallback endpoint when the primary endpoint is unreachable.
  static final Uri defaultFallbackGeoIpUri = Uri.parse(
    'https://get.geojs.io/v1/ip/geo.json',
  );

  /// Primary HTTPS GeoIP fallback endpoint for desktop environments without location hardware.
  static final Uri defaultGeoIpUri = Uri.parse(
    'https://geolocation-db.com/json/',
  );

  /// Default maximum allowed HTTP response body size in bytes (64 KiB).
  static const int defaultMaxResponseBytes = 65536;

  /// Default HTTPS Wi-Fi BSSID positioning endpoint (MLS / Ichnaea v1 protocol).
  static final Uri defaultWifiGeolocateUri = Uri.parse(
    'https://api.beacondb.net/v1/geolocate',
  );

  /// Time-to-live for cached desktop GeoIP fallback results.
  static const Duration geoIpCacheTtl = Duration(minutes: 30);

  /// Native platform channel for foreground location queries.
  static const MethodChannel locationChannel = MethodChannel(
    'de.akjir.tiertask/location',
  );

  /// Maximum horizontal accuracy radius in meters accepted for a Wi-Fi BSSID fix.
  static const double maxWifiPositioningAccuracyMeters = 2000.0;

  /// Minimum Haversine distance in meters required before querying the reverse geocoder again.
  static const double minReverseGeocodeDisplacementMeters = 100.0;

  /// Timeout applied to native platform channel invocations.
  static const Duration nativeChannelTimeout = Duration(seconds: 12);

  /// User-Agent header sent with Nominatim and GeoIP requests.
  static const String userAgentHeader = 'TierTask/1.0';

  /// Timeout applied to outbound HTTP connections and responses.
  final Duration connectionTimeout;

  /// Maximum allowed HTTP response size in bytes.
  final int maxResponseBytes;

  DateTime? _cachedGeoIpAt;
  LocationFix? _cachedGeoIpFix;
  final MethodChannel _channel;
  final HttpClient Function() _clientFactory;
  final DateTime Function() _clock;
  final Uri _fallbackGeoIpUri;
  final Uri _geoIpUri;
  LocationFix? _lastGeocodedFix;
  final Uri Function(double latitude, double longitude)
  _reverseGeocodeUriBuilder;
  final Uri _wifiGeolocateUri;

  @override
  Future<LocationFix?> determineLocation({bool forceRefresh = false}) async {
    final stopwatch = Stopwatch()..start();
    final nativeMap = await _invokeNativeChannel();
    if (_extractNativeFix(nativeMap) case final nativeFix?) {
      final resolved = await _resolvePlaceNameForNativeFix(nativeFix);
      AppLogger.event(
        LogLevel.info,
        LogTag.storage,
        'location.lookup',
        fields: <String, Object?>{
          'source': 'channel',
          'has_coords': resolved.hasCoordinates,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      return resolved;
    }
    if (await _resolveWifiAccessPointsFix(nativeMap) case final wifiFix?) {
      final resolved = await _resolvePlaceNameForNativeFix(wifiFix);
      AppLogger.event(
        LogLevel.info,
        LogTag.storage,
        'location.lookup',
        fields: <String, Object?>{
          'source': 'wifi_mls',
          'has_coords': resolved.hasCoordinates,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      return resolved;
    }
    final geoIpFix = await _resolveGeoIpFallback(forceRefresh: forceRefresh);
    AppLogger.event(
      geoIpFix != null ? LogLevel.info : LogLevel.warn,
      LogTag.storage,
      'location.lookup',
      fields: <String, Object?>{
        'source': 'geoip',
        'has_coords': geoIpFix?.hasCoordinates ?? false,
        'elapsed_ms': stopwatch.elapsedMilliseconds,
      },
    );
    return geoIpFix;
  }

  /// Builds the default OpenStreetMap Nominatim reverse-geocoding URI for [latitude] and [longitude].
  static Uri _defaultReverseGeocodeUri(double latitude, double longitude) {
    return Uri.https(
      'nominatim.openstreetmap.org',
      '/reverse',
      <String, String>{
        'format': 'jsonv2',
        'lat': latitude.toStringAsFixed(5),
        'lon': longitude.toStringAsFixed(5),
        'zoom': '10',
      },
    );
  }

  /// Extracts a [LocationFix] from the native channel map when status is `'found'` and coordinates are valid.
  LocationFix? _extractNativeFix(Map<String, Object?>? map) {
    if (map == null || map['status'] != 'found') {
      return null;
    }
    final latitude = _parseCoordinate(map['latitude'], maxMagnitude: 90.0);
    final longitude = _parseCoordinate(map['longitude'], maxMagnitude: 180.0);
    if (latitude == null || longitude == null) {
      return null;
    }
    final rawPlace = map['placeName'];
    final placeName = rawPlace is String && rawPlace.trim().isNotEmpty
        ? rawPlace.trim()
        : null;
    final source = _parseNativeSource(map['source']);
    return LocationFix(
      latitude: latitude,
      longitude: longitude,
      placeName: placeName,
      source: source,
    );
  }

  /// Extracts a sanitized list of Wi-Fi access point maps (`macAddress` and optional `signalStrength`) from [rawList].
  static List<Map<String, Object?>> _extractWifiAccessPoints(Object? rawList) {
    if (rawList is! List<Object?>) {
      return const <Map<String, Object?>>[];
    }
    final sanitized = <Map<String, Object?>>[];
    for (final item in rawList) {
      if (sanitized.length >= 20) {
        break;
      }
      if (item is Map<Object?, Object?>) {
        final mac = item['macAddress'];
        if (mac is String && mac.trim().isNotEmpty) {
          final entry = <String, Object?>{'macAddress': mac.trim()};
          if (item['signalStrength'] case final num strength) {
            entry['signalStrength'] = strength.toInt();
          }
          sanitized.add(entry);
        }
      }
    }
    return sanitized;
  }

  /// Performs a bounded HTTP GET to [uri] and decodes a JSON object map, or returns `null` on error.
  Future<Map<String, Object?>?> _fetchJsonMap(Uri uri) async {
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      return null;
    }
    final client = _clientFactory();
    client.connectionTimeout = connectionTimeout;
    try {
      final request = await client.getUrl(uri).timeout(connectionTimeout);
      request.headers.set(HttpHeaders.userAgentHeader, userAgentHeader);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(connectionTimeout);
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }
      final body = await _readBoundedUtf8Body(response);
      if (body == null) {
        return null;
      }
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      return null;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Returns the first non-empty trimmed string value among [keys] in [map].
  static String? _firstNonEmptyString(
    Map<String, Object?> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  /// Invokes the native platform channel and returns the result map, or `null` if unavailable.
  Future<Map<String, Object?>?> _invokeNativeChannel() async {
    try {
      return await _channel
          .invokeMapMethod<String, Object?>('getLocation')
          .timeout(nativeChannelTimeout);
    } on Object {
      return null;
    }
  }

  /// Joins [locality] and [country] into a human-readable place label.
  static String? _joinPlaceParts(String? locality, String? country) {
    if (locality != null && country != null && locality != country) {
      return '$locality, $country';
    }
    return locality ?? country;
  }

  /// Parses a finite coordinate from [rawValue] bounded by [maxMagnitude].
  static double? _parseCoordinate(
    Object? rawValue, {
    required double maxMagnitude,
  }) {
    final double? numeric = switch (rawValue) {
      final num number => number.toDouble(),
      final String text => double.tryParse(text.trim()),
      _ => null,
    };
    if (numeric == null || !numeric.isFinite || numeric.abs() > maxMagnitude) {
      return null;
    }
    return numeric;
  }

  /// Extracts a [LocationFix] from a GeoIP JSON payload.
  static LocationFix? _parseGeoIpFix(Map<String, Object?>? jsonMap) {
    if (jsonMap == null) {
      return null;
    }
    final latitude = _parseCoordinate(
      jsonMap['latitude'] ?? jsonMap['lat'],
      maxMagnitude: 90.0,
    );
    final longitude = _parseCoordinate(
      jsonMap['longitude'] ?? jsonMap['lon'],
      maxMagnitude: 180.0,
    );
    final locality = _firstNonEmptyString(jsonMap, const <String>[
      'city',
      'region',
      'region_name',
    ]);
    final country = _firstNonEmptyString(jsonMap, const <String>[
      'country',
      'country_name',
    ]);
    final placeName = _joinPlaceParts(locality, country);
    if (latitude == null && longitude == null && placeName == null) {
      return null;
    }
    return LocationFix(
      latitude: latitude,
      longitude: longitude,
      placeName: placeName,
      source: LocationSource.internet,
    );
  }

  /// Parses the native platform channel `source` string into a [LocationSource].
  static LocationSource _parseNativeSource(Object? rawSource) {
    if (rawSource is String) {
      return switch (rawSource.trim().toLowerCase()) {
        'gps' => LocationSource.gps,
        'internet' => LocationSource.internet,
        _ => LocationSource.system,
      };
    }
    return LocationSource.system;
  }

  /// Extracts a concise place name from a Nominatim reverse-geocoding JSON payload.
  static String? _parseReverseGeocodePlaceName(Map<String, Object?>? jsonMap) {
    if (jsonMap == null) {
      return null;
    }
    final address = jsonMap['address'];
    if (address is Map<String, Object?>) {
      final locality = _firstNonEmptyString(address, const <String>[
        'city',
        'town',
        'village',
        'municipality',
        'county',
        'state',
      ]);
      final country = _firstNonEmptyString(address, const <String>['country']);
      if (_joinPlaceParts(locality, country) case final combined?) {
        return combined;
      }
    }
    return _firstNonEmptyString(jsonMap, const <String>[
      'name',
      'display_name',
    ]);
  }

  /// Extracts a [LocationFix] from an MLS / BeaconDB `/v1/geolocate` JSON payload.
  static LocationFix? _parseWifiGeolocateFix(Map<String, Object?>? jsonMap) {
    if (jsonMap == null) {
      return null;
    }
    final accuracy = _parseCoordinate(
      jsonMap['accuracy'],
      maxMagnitude: 100000.0,
    );
    if (accuracy != null && accuracy > maxWifiPositioningAccuracyMeters) {
      return null;
    }
    final location = jsonMap['location'];
    if (location is! Map<String, Object?>) {
      return null;
    }
    final latitude = _parseCoordinate(location['lat'], maxMagnitude: 90.0);
    final longitude = _parseCoordinate(location['lng'], maxMagnitude: 180.0);
    if (latitude == null || longitude == null) {
      return null;
    }
    return LocationFix(
      latitude: latitude,
      longitude: longitude,
      source: LocationSource.system,
    );
  }

  /// Performs a bounded HTTP POST of [payload] to [uri] and decodes a JSON object map, or returns `null` on error.
  Future<Map<String, Object?>?> _postJsonMap(
    Uri uri,
    Map<String, Object?> payload,
  ) async {
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      return null;
    }
    final client = _clientFactory();
    client.connectionTimeout = connectionTimeout;
    try {
      final request = await client.postUrl(uri).timeout(connectionTimeout);
      request.headers.set(HttpHeaders.userAgentHeader, userAgentHeader);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close().timeout(connectionTimeout);
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }
      final body = await _readBoundedUtf8Body(response);
      if (body == null) {
        return null;
      }
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      return null;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Reads at most [maxResponseBytes] from [response] and decodes UTF-8 text.
  Future<String?> _readBoundedUtf8Body(HttpClientResponse response) async {
    if (response.contentLength > maxResponseBytes) {
      return null;
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(connectionTimeout)) {
      if (bytes.length + chunk.length > maxResponseBytes) {
        return null;
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Resolves a desktop GeoIP fallback [LocationFix] respecting the 30-minute [geoIpCacheTtl].
  Future<LocationFix?> _resolveGeoIpFallback({
    required bool forceRefresh,
  }) async {
    final now = _clock();
    if (!forceRefresh) {
      if ((_cachedGeoIpFix, _cachedGeoIpAt) case (
        final cachedFix?,
        final cachedAt?,
      )) {
        if (now.difference(cachedAt) < geoIpCacheTtl) {
          return cachedFix;
        }
      }
    }
    final stopwatch = Stopwatch()..start();
    final jsonMap = await _fetchJsonMap(_geoIpUri);
    var resolved = _parseGeoIpFix(jsonMap);
    if (resolved == null && _fallbackGeoIpUri != _geoIpUri) {
      final fallbackMap = await _fetchJsonMap(_fallbackGeoIpUri);
      resolved = _parseGeoIpFix(fallbackMap);
    }
    if (resolved != null) {
      _cachedGeoIpFix = resolved;
      _cachedGeoIpAt = now;
    }
    AppLogger.event(
      resolved != null ? LogLevel.info : LogLevel.warn,
      LogTag.storage,
      'location.geoip',
      fields: <String, Object?>{
        'has_coords': resolved?.hasCoordinates ?? false,
        'elapsed_ms': stopwatch.elapsedMilliseconds,
      },
    );
    return resolved;
  }

  /// Resolves or reuses a cached place name for [nativeFix] using the 100-meter displacement threshold.
  Future<LocationFix> _resolvePlaceNameForNativeFix(
    LocationFix nativeFix,
  ) async {
    if (nativeFix.placeName != null) {
      _lastGeocodedFix = nativeFix;
      return nativeFix;
    }
    if (_lastGeocodedFix case final cached?) {
      if (cached.placeName != null &&
          nativeFix.isWithinDisplacementThreshold(
            cached,
            minReverseGeocodeDisplacementMeters,
          )) {
        return LocationFix(
          latitude: nativeFix.latitude,
          longitude: nativeFix.longitude,
          placeName: cached.placeName,
          source: nativeFix.source,
        );
      }
    }
    if ((nativeFix.latitude, nativeFix.longitude) case (
      final latitude?,
      final longitude?,
    )) {
      final stopwatch = Stopwatch()..start();
      final uri = _reverseGeocodeUriBuilder(latitude, longitude);
      final jsonMap = await _fetchJsonMap(uri);
      final placeName = _parseReverseGeocodePlaceName(jsonMap);
      AppLogger.event(
        LogLevel.info,
        LogTag.storage,
        'location.geocode',
        fields: <String, Object?>{
          'results': placeName != null ? 1 : 0,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      if (placeName != null) {
        final enriched = LocationFix(
          latitude: latitude,
          longitude: longitude,
          placeName: placeName,
          source: nativeFix.source,
        );
        _lastGeocodedFix = enriched;
        return enriched;
      }
    }
    return nativeFix;
  }

  /// Resolves a street-level [LocationFix] from visible Wi-Fi BSSIDs reported in [nativeMap], or `null` if unavailable.
  Future<LocationFix?> _resolveWifiAccessPointsFix(
    Map<String, Object?>? nativeMap,
  ) async {
    if (nativeMap == null) {
      return null;
    }
    final accessPoints = _extractWifiAccessPoints(
      nativeMap['wifiAccessPoints'],
    );
    if (accessPoints.length < 2) {
      return null;
    }
    final responseMap = await _postJsonMap(_wifiGeolocateUri, <String, Object?>{
      'considerIp': false,
      'wifiAccessPoints': accessPoints,
    });
    return _parseWifiGeolocateFix(responseMap);
  }
}
