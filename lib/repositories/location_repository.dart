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
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/services.dart';

import '../models/location_state.dart';
import '../services/app_logger.dart';
import '../services/plus_code_service.dart';

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

  /// Query string passed to the most recent [searchLocations] call.
  String? lastSearchQuery;

  /// Total number of [searchLocations] invocations.
  int searchCallCount = 0;

  /// Configured [GeocodingCandidate] list returned by [searchLocations].
  List<GeocodingCandidate> searchResults = const <GeocodingCandidate>[];

  @override
  Future<LocationFix?> determineLocation({bool forceRefresh = false}) async {
    callCount++;
    lastForceRefresh = forceRefresh;
    return currentFix;
  }

  @override
  Future<List<GeocodingCandidate>> searchLocations(String query) async {
    searchCallCount++;
    lastSearchQuery = query;
    return searchResults;
  }
}

/// Contract for resolving the user's current foreground location and place name.
abstract interface class LocationRepository {
  /// Resolves the current [LocationFix], or returns `null` when unavailable.
  Future<LocationFix?> determineLocation({bool forceRefresh = false});

  /// Searches forward-geocoding candidates matching [query] (at most 5 results).
  Future<List<GeocodingCandidate>> searchLocations(String query);
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
    this.minSearchInterval = defaultMinSearchInterval,
    Uri Function(double latitude, double longitude)? reverseGeocodeUriBuilder,
    Uri Function(String query)? searchGeocodeUriBuilder,
    Uri? wifiGeolocateUri,
  }) : _channel = channel ?? locationChannel,
       _clientFactory = clientFactory ?? HttpClient.new,
       _clock = clock ?? DateTime.now,
       _fallbackGeoIpUri = fallbackGeoIpUri ?? defaultFallbackGeoIpUri,
       _geoIpUri = geoIpUri ?? defaultGeoIpUri,
       _reverseGeocodeUriBuilder =
           reverseGeocodeUriBuilder ?? _defaultReverseGeocodeUri,
       _searchGeocodeUriBuilder =
           searchGeocodeUriBuilder ?? _defaultSearchGeocodeUri,
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

  /// Default minimum interval between outbound Nominatim search requests (1 req/s).
  static const Duration defaultMinSearchInterval = Duration(seconds: 1);

  /// Default HTTPS Wi-Fi BSSID positioning endpoint (MLS / Ichnaea v1 protocol).
  static final Uri defaultWifiGeolocateUri = Uri.parse(
    'https://api.beacondb.net/v1/geolocate',
  );

  /// Time-to-live for cached desktop GeoIP fallback results.
  static const Duration geoIpCacheTtl = Duration(minutes: 30);

  /// Negative backoff duration suppressing repeated GeoIP fetches after both endpoints fail.
  static const Duration geoIpFailureBackoff = Duration(minutes: 5);

  /// Native platform channel for foreground location queries.
  static const MethodChannel locationChannel = MethodChannel(
    'de.akjir.tiertask/location',
  );

  /// Maximum number of forward-geocoding candidates returned by [searchLocations].
  static const int maxGeocodingCandidates = 5;

  /// Maximum allowed character length for a forward-geocoding search query.
  static const int maxSearchQueryLength = 500;

  /// Maximum number of Wi-Fi access points included in a positioning lookup.
  static const int maxWifiAccessPoints = 20;

  /// Maximum horizontal accuracy radius in meters accepted for a Wi-Fi BSSID fix.
  static const double maxWifiPositioningAccuracyMeters = 2000.0;

  /// Minimum Haversine distance in meters required before querying the reverse geocoder again.
  static const double minReverseGeocodeDisplacementMeters = 100.0;

  /// Timeout applied to native platform channel invocations.
  static const Duration nativeChannelTimeout = Duration(seconds: 12);

  /// User-Agent header sent with Nominatim, Wi-Fi MLS, and GeoIP requests.
  static const String userAgentHeader =
      'TierTask/0.5.0 (+https://github.com/akjir/tiertask)';

  /// Time-to-live for cached Wi-Fi BSSID MLS positioning results.
  static const Duration wifiCacheTtl = Duration(minutes: 15);

  static const int _maxDrainBytes = 65536;
  static const int _maxRedirects = 5;

  /// Timeout applied to outbound HTTP connections and responses.
  final Duration connectionTimeout;

  /// Maximum allowed HTTP response size in bytes.
  final int maxResponseBytes;

  /// Minimum interval enforced between consecutive Nominatim `/search` and `/reverse` HTTP calls.
  final Duration minSearchInterval;

  DateTime? _cachedGeoIpAt;
  LocationFix? _cachedGeoIpFix;
  DateTime? _cachedWifiAt;
  String? _cachedWifiBssidKey;
  LocationFix? _cachedWifiFix;
  final MethodChannel _channel;
  HttpClient? _client;
  final HttpClient Function() _clientFactory;
  final DateTime Function() _clock;
  final Uri _fallbackGeoIpUri;
  DateTime? _geoIpFailedAt;
  final Uri _geoIpUri;
  LocationFix? _lastGeocodedFix;
  DateTime? _lastNominatimRequestAt;
  Future<void> _nominatimQueue = Future<void>.value();
  final Uri Function(double latitude, double longitude)
  _reverseGeocodeUriBuilder;
  final Uri Function(String query) _searchGeocodeUriBuilder;
  final Uri _wifiGeolocateUri;

  /// Closes the pooled [HttpClient] and releases underlying socket connections.
  void close({bool force = false}) {
    final active = _client;
    _client = null;
    active?.close(force: force);
  }

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
    if (await _resolveWifiAccessPointsFix(nativeMap, forceRefresh: forceRefresh)
        case final wifiFix?) {
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

  @override
  Future<List<GeocodingCandidate>> searchLocations(String query) async {
    if (query.length > maxSearchQueryLength) {
      return const <GeocodingCandidate>[];
    }
    final normalizedQuery = PlusCodeService.normalizeSingleLineText(query);
    if (normalizedQuery.isEmpty) {
      return const <GeocodingCandidate>[];
    }
    return _runRateLimitedNominatim<List<GeocodingCandidate>>(() async {
      final stopwatch = Stopwatch()..start();
      final uri = _searchGeocodeUriBuilder(normalizedQuery);
      final jsonList = await _fetchJsonList(uri);
      final candidates = _parseSearchCandidates(jsonList);
      AppLogger.event(
        LogLevel.info,
        LogTag.storage,
        'location.search',
        fields: <String, Object?>{
          'results': candidates.length,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      return candidates;
    });
  }

  /// Returns the lazily initialized pooled [HttpClient] configured with [connectionTimeout].
  HttpClient _acquireClient() {
    if (_client case final existing?) {
      return existing;
    }
    final created = _clientFactory()..connectionTimeout = connectionTimeout;
    _client = created;
    return created;
  }

  /// Builds a deterministic cache key from the sorted lowercase BSSIDs in [accessPoints].
  static String _buildWifiBssidCacheKey(
    List<Map<String, Object?>> accessPoints,
  ) {
    final macAddresses = <String>[
      for (final entry in accessPoints)
        if (entry['macAddress'] case final String mac) mac.toLowerCase(),
    ]..sort();
    return macAddresses.join(',');
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

  /// Builds the default OpenStreetMap Nominatim forward-geocoding search URI for [query].
  static Uri _defaultSearchGeocodeUri(String query) {
    return Uri.https('nominatim.openstreetmap.org', '/search', <String, String>{
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '$maxGeocodingCandidates',
      'q': query,
    });
  }

  /// Drains up to [_maxDrainBytes] from [response] within [deadline] so keep-alive sockets return cleanly to the pool.
  Future<void> _drainResponseSafely(
    HttpClientResponse response,
    DateTime deadline,
    HttpClient client,
  ) async {
    if (response.contentLength > _maxDrainBytes) {
      _resetPooledClient(client);
      return;
    }
    final iterator = StreamIterator<List<int>>(response);
    var completedNormally = false;
    var drainedBytes = 0;
    try {
      while (await iterator.moveNext().timeout(_remainingTimeout(deadline))) {
        drainedBytes += iterator.current.length;
        if (drainedBytes > _maxDrainBytes) {
          _resetPooledClient(client);
          return;
        }
      }
      completedNormally = true;
    } finally {
      if (!completedNormally) {
        unawaited(iterator.cancel());
      }
    }
  }

  /// Waits for [previous] in the Nominatim FIFO queue, enforces [minSearchInterval], and runs [action].
  Future<T> _executeQueuedNominatim<T>(
    Future<void> previous,
    Completer<void> gate,
    Future<T> Function() action,
  ) async {
    await previous;
    try {
      await _waitForNominatimRateLimit();
      _lastNominatimRequestAt = _clock();
      return await action();
    } finally {
      gate.complete();
    }
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
      if (sanitized.length >= maxWifiAccessPoints) {
        break;
      }
      if (_sanitizeWifiAccessPointEntry(item) case final entry?) {
        sanitized.add(entry);
      }
    }
    return sanitized;
  }

  /// Performs a bounded HTTP GET to [uri] with explicit redirect validation and returns the decoded JSON value, or `null` on error.
  Future<Object?> _fetchDecodedJson(Uri uri) async {
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      return null;
    }
    final deadline = DateTime.now().add(connectionTimeout);
    final client = _acquireClient();
    var currentUri = uri;
    try {
      for (var hop = 0; hop <= _maxRedirects; hop++) {
        final request = await client
            .getUrl(currentUri)
            .timeout(_remainingTimeout(deadline));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, userAgentHeader);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close().timeout(
          _remainingTimeout(deadline),
        );
        if (_isRedirectStatus(response.statusCode)) {
          await _drainResponseSafely(response, deadline, client);
          if (hop == _maxRedirects) {
            return null;
          }
          final nextUri = _resolveRedirectUri(
            currentUri: currentUri,
            locationHeader: response.headers.value(HttpHeaders.locationHeader),
          );
          if (nextUri == null) {
            return null;
          }
          currentUri = nextUri;
          continue;
        }
        if (response.statusCode != HttpStatus.ok) {
          await _drainResponseSafely(response, deadline, client);
          return null;
        }
        final body = await _readBoundedUtf8Body(
          response,
          deadline: deadline,
          client: client,
        );
        if (body == null) {
          return null;
        }
        return jsonDecode(body);
      }
      return null;
    } on TimeoutException {
      _resetPooledClient(client);
      AppLogger.warn(LogTag.storage, 'HTTP GET JSON fetch timed out');
      return null;
    } on Object {
      AppLogger.warn(LogTag.storage, 'HTTP GET JSON fetch failed');
      return null;
    }
  }

  /// Performs a bounded HTTP GET to [uri] and decodes a JSON array list, or returns `null` on error.
  Future<List<Object?>?> _fetchJsonList(Uri uri) async {
    final decoded = await _fetchDecodedJson(uri);
    if (decoded is List<Object?>) {
      return decoded;
    }
    return null;
  }

  /// Performs a bounded HTTP GET to [uri] and decodes a JSON object map, or returns `null` on error.
  Future<Map<String, Object?>?> _fetchJsonMap(Uri uri) async {
    final decoded = await _fetchDecodedJson(uri);
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    return null;
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

  /// Returns `true` when [statusCode] is an HTTP redirect status (`301`, `302`, `303`, `307`, `308`).
  static bool _isRedirectStatus(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;

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

  /// Parses a single Nominatim search JSON object into a [GeocodingCandidate], or returns `null` when invalid.
  static GeocodingCandidate? _parseSearchCandidateEntry(Object? rawItem) {
    if (rawItem is! Map<Object?, Object?>) {
      return null;
    }
    final latitude = _parseCoordinate(
      rawItem['lat'] ?? rawItem['latitude'],
      maxMagnitude: 90.0,
    );
    final longitude = _parseCoordinate(
      rawItem['lon'] ?? rawItem['longitude'],
      maxMagnitude: 180.0,
    );
    if (latitude == null || longitude == null) {
      return null;
    }
    final rawName = rawItem['display_name'] ?? rawItem['name'];
    if (rawName is! String) {
      return null;
    }
    final displayName = PlusCodeService.normalizeSingleLineText(rawName);
    if (displayName.isEmpty) {
      return null;
    }
    return GeocodingCandidate(
      displayName: displayName,
      latitude: latitude,
      longitude: longitude,
    );
  }

  /// Extracts up to [maxGeocodingCandidates] sanitized [GeocodingCandidate] items from [jsonList].
  static List<GeocodingCandidate> _parseSearchCandidates(
    List<Object?>? jsonList,
  ) {
    if (jsonList == null || jsonList.isEmpty) {
      return const <GeocodingCandidate>[];
    }
    final candidates = <GeocodingCandidate>[];
    for (final rawItem in jsonList) {
      if (candidates.length >= maxGeocodingCandidates) {
        break;
      }
      if (_parseSearchCandidateEntry(rawItem) case final candidate?) {
        candidates.add(candidate);
      }
    }
    return List<GeocodingCandidate>.unmodifiable(candidates);
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

  /// Performs a bounded HTTP POST of [payload] to [uri] with explicit `Content-Length` and decodes a JSON object map, or returns `null` on error.
  Future<Map<String, Object?>?> _postJsonMap(
    Uri uri,
    Map<String, Object?> payload,
  ) async {
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      return null;
    }
    final deadline = DateTime.now().add(connectionTimeout);
    final client = _acquireClient();
    try {
      final request = await client
          .postUrl(uri)
          .timeout(_remainingTimeout(deadline));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, userAgentHeader);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final bytes = utf8.encode(jsonEncode(payload));
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(
        _remainingTimeout(deadline),
      );
      if (response.statusCode != HttpStatus.ok) {
        await _drainResponseSafely(response, deadline, client);
        AppLogger.event(
          LogLevel.warn,
          LogTag.storage,
          'location.post_failed',
          fields: <String, Object?>{'status': response.statusCode},
        );
        return null;
      }
      final body = await _readBoundedUtf8Body(
        response,
        deadline: deadline,
        client: client,
      );
      if (body == null) {
        AppLogger.event(
          LogLevel.warn,
          LogTag.storage,
          'location.post_failed',
          fields: const <String, Object?>{'reason': 'oversized_response'},
        );
        return null;
      }
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      return null;
    } on TimeoutException {
      _resetPooledClient(client);
      AppLogger.event(
        LogLevel.warn,
        LogTag.storage,
        'location.post_failed',
        fields: const <String, Object?>{'reason': 'timeout'},
      );
      return null;
    } on Object {
      AppLogger.event(
        LogLevel.warn,
        LogTag.storage,
        'location.post_failed',
        fields: const <String, Object?>{'reason': 'request_error'},
      );
      return null;
    }
  }

  /// Reads at most [maxResponseBytes] from [response] within [deadline] using [BytesBuilder] and decodes UTF-8 text.
  Future<String?> _readBoundedUtf8Body(
    HttpClientResponse response, {
    required DateTime deadline,
    required HttpClient client,
  }) async {
    if (response.contentLength > maxResponseBytes) {
      _resetPooledClient(client);
      return null;
    }
    final iterator = StreamIterator<List<int>>(response);
    final builder = BytesBuilder(copy: false);
    var completedNormally = false;
    try {
      while (await iterator.moveNext().timeout(_remainingTimeout(deadline))) {
        final chunk = iterator.current;
        if (builder.length + chunk.length > maxResponseBytes) {
          _resetPooledClient(client);
          return null;
        }
        builder.add(chunk);
      }
      completedNormally = true;
      return utf8.decode(builder.takeBytes(), allowMalformed: true);
    } finally {
      if (!completedNormally) {
        unawaited(iterator.cancel());
      }
    }
  }

  /// Computes remaining wall-clock budget before [deadline], throwing [TimeoutException] when exhausted.
  Duration _remainingTimeout(DateTime deadline) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw TimeoutException(
        'Location HTTP request deadline exceeded',
        connectionTimeout,
      );
    }
    return remaining;
  }

  /// Force-closes [client] and clears [_client] so subsequent calls create a fresh connection pool.
  void _resetPooledClient(HttpClient client) {
    if (identical(_client, client)) {
      _client = null;
    }
    client.close(force: true);
  }

  /// Resolves a desktop GeoIP fallback [LocationFix] respecting the 30-minute [geoIpCacheTtl] and 5-minute [geoIpFailureBackoff].
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
      if (_geoIpFailedAt case final failedAt?) {
        if (now.difference(failedAt) < geoIpFailureBackoff) {
          return null;
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
      _geoIpFailedAt = null;
    } else {
      _geoIpFailedAt = now;
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

  /// Resolves or reuses a cached place name for [nativeFix] using the 100-meter displacement threshold and unified Nominatim rate limit.
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
      final placeName = await _runRateLimitedNominatim<String?>(() async {
        final stopwatch = Stopwatch()..start();
        final uri = _reverseGeocodeUriBuilder(latitude, longitude);
        final jsonMap = await _fetchJsonMap(uri);
        final resolvedName = _parseReverseGeocodePlaceName(jsonMap);
        AppLogger.event(
          LogLevel.info,
          LogTag.storage,
          'location.geocode',
          fields: <String, Object?>{
            'results': resolvedName != null ? 1 : 0,
            'elapsed_ms': stopwatch.elapsedMilliseconds,
          },
        );
        return resolvedName;
      });
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

  /// Resolves and validates a redirect [locationHeader] relative to [currentUri], returning `null` on HTTPS-to-HTTP downgrade or malformed URI.
  Uri? _resolveRedirectUri({
    required Uri currentUri,
    required String? locationHeader,
  }) {
    final trimmed = locationHeader?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    final Uri nextUri;
    try {
      nextUri = currentUri.resolve(trimmed);
    } on FormatException {
      return null;
    }
    final scheme = nextUri.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') ||
        nextUri.host.isEmpty ||
        nextUri.userInfo.isNotEmpty) {
      return null;
    }
    if (currentUri.scheme.toLowerCase() == 'https' && scheme != 'https') {
      AppLogger.event(
        LogLevel.warn,
        LogTag.storage,
        'location.redirect_blocked',
        fields: const <String, Object?>{'reason': 'cleartext_downgrade'},
      );
      return null;
    }
    return nextUri;
  }

  /// Resolves a street-level [LocationFix] from visible Wi-Fi BSSIDs reported in [nativeMap], caching results by sorted BSSID set for [wifiCacheTtl].
  Future<LocationFix?> _resolveWifiAccessPointsFix(
    Map<String, Object?>? nativeMap, {
    required bool forceRefresh,
  }) async {
    if (nativeMap == null) {
      return null;
    }
    final accessPoints = _extractWifiAccessPoints(
      nativeMap['wifiAccessPoints'],
    );
    if (accessPoints.length < 2) {
      return null;
    }
    final now = _clock();
    final bssidKey = _buildWifiBssidCacheKey(accessPoints);
    if (!forceRefresh) {
      if ((_cachedWifiFix, _cachedWifiAt) case (
        final cachedFix?,
        final cachedAt?,
      )) {
        if (_cachedWifiBssidKey == bssidKey &&
            now.difference(cachedAt) < wifiCacheTtl) {
          return cachedFix;
        }
      }
    }
    final responseMap = await _postJsonMap(_wifiGeolocateUri, <String, Object?>{
      'considerIp': false,
      'wifiAccessPoints': accessPoints,
    });
    final resolved = _parseWifiGeolocateFix(responseMap);
    if (resolved != null) {
      _cachedWifiBssidKey = bssidKey;
      _cachedWifiFix = resolved;
      _cachedWifiAt = now;
    }
    return resolved;
  }

  /// Enqueues [action] onto the unified Nominatim FIFO queue enforcing [minSearchInterval] across `/search` and `/reverse`.
  Future<T> _runRateLimitedNominatim<T>(Future<T> Function() action) {
    final previous = _nominatimQueue;
    final gate = Completer<void>();
    _nominatimQueue = gate.future;
    return _executeQueuedNominatim<T>(previous, gate, action);
  }

  /// Sanitizes a single raw Wi-Fi access point [item] into a map with `macAddress` and optional integer `signalStrength`, or returns `null` when invalid.
  static Map<String, Object?>? _sanitizeWifiAccessPointEntry(Object? item) {
    if (item is! Map<Object?, Object?>) {
      return null;
    }
    final mac = item['macAddress'];
    if (mac is! String || mac.trim().isEmpty) {
      return null;
    }
    final entry = <String, Object?>{'macAddress': mac.trim()};
    if (item['signalStrength'] case final num strength) {
      entry['signalStrength'] = strength.toInt();
    }
    return entry;
  }

  /// Waits for any remaining [minSearchInterval] cooldown since [_lastNominatimRequestAt].
  Future<void> _waitForNominatimRateLimit() async {
    if (minSearchInterval <= Duration.zero) {
      return;
    }
    if (_lastNominatimRequestAt case final lastAt?) {
      final elapsed = _clock().difference(lastAt);
      if (elapsed < minSearchInterval) {
        await Future<void>.delayed(minSearchInterval - elapsed);
      }
    }
  }
}
