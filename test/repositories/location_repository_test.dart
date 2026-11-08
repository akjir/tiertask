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

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/repositories/location_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlatformLocationRepository', () {
    late HttpServer server;
    late Uri baseUri;
    var reverseGeocodeRequests = 0;
    var searchGeocodeRequests = 0;
    var geoIpRequests = 0;
    var fallbackGeoIpRequests = 0;
    var wifiGeolocateRequests = 0;
    var responseStatusCode = HttpStatus.ok;
    var fallbackGeoIpStatusCode = HttpStatus.ok;
    var searchStatusCode = HttpStatus.ok;
    var wifiStatusCode = HttpStatus.ok;
    var reverseGeocodeResponseBody =
        '{"address":{"city":"Erfurt","country":"Germany"}}';
    var searchGeocodeResponseBody = '[]';
    var geoIpResponseBody =
        '{"latitude":"50.9787","longitude":"11.0328","city":"Erfurt","country":"Germany"}';
    var fallbackGeoIpResponseBody =
        '{"latitude":"50.9848","longitude":"11.3299","city":"Weimar","country":"Germany"}';
    var wifiGeolocateResponseBody =
        '{"location":{"lat":50.9787,"lng":11.0328},"accuracy":35.0}';
    Map<String, Object?>? channelResponse;
    String? lastSearchQueryParam;
    String? lastWifiRequestBody;

    setUp(() async {
      HttpOverrides.global = null;
      reverseGeocodeRequests = 0;
      searchGeocodeRequests = 0;
      geoIpRequests = 0;
      fallbackGeoIpRequests = 0;
      wifiGeolocateRequests = 0;
      responseStatusCode = HttpStatus.ok;
      fallbackGeoIpStatusCode = HttpStatus.ok;
      searchStatusCode = HttpStatus.ok;
      wifiStatusCode = HttpStatus.ok;
      reverseGeocodeResponseBody =
          '{"address":{"city":"Erfurt","country":"Germany"}}';
      searchGeocodeResponseBody = '[]';
      geoIpResponseBody = '{"latitude":"50.9787","longitude":"11.0328","city":"Erfurt","country":"Germany"}';
      fallbackGeoIpResponseBody = '{"latitude":"50.9848","longitude":"11.3299","city":"Weimar","country":"Germany"}';
      wifiGeolocateResponseBody =
          '{"location":{"lat":50.9787,"lng":11.0328},"accuracy":35.0}';
      channelResponse = <String, Object?>{'status': 'unavailable'};
      lastSearchQueryParam = null;
      lastWifiRequestBody = null;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            PlatformLocationRepository.locationChannel,
            (call) async {
              if (call.method == 'getLocation') {
                return channelResponse;
              }
              return null;
            },
          );

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUri = Uri.parse('http://${server.address.host}:${server.port}');
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/reverse') {
          request.response.statusCode = responseStatusCode;
          reverseGeocodeRequests++;
          request.response.write(reverseGeocodeResponseBody);
        } else if (request.uri.path == '/search') {
          request.response.statusCode = searchStatusCode;
          searchGeocodeRequests++;
          lastSearchQueryParam = request.uri.queryParameters['q'];
          request.response.write(searchGeocodeResponseBody);
        } else if (request.uri.path == '/geoip') {
          request.response.statusCode = responseStatusCode;
          geoIpRequests++;
          request.response.write(geoIpResponseBody);
        } else if (request.uri.path == '/geoip-fallback') {
          request.response.statusCode = fallbackGeoIpStatusCode;
          fallbackGeoIpRequests++;
          request.response.write(fallbackGeoIpResponseBody);
        } else if (request.uri.path == '/wifi') {
          lastWifiRequestBody = await utf8.decoder.bind(request).join();
          request.response.statusCode = wifiStatusCode;
          wifiGeolocateRequests++;
          request.response.write(wifiGeolocateResponseBody);
        }
        await request.response.close();
      });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            PlatformLocationRepository.locationChannel,
            null,
          );
      await server.close(force: true);
    });

    test('returns native channel fix directly without HTTP calls when OS provides placeName and coordinates', () async {
      channelResponse = <String, Object?>{
        'status': 'found',
        'latitude': 50.9787,
        'longitude': 11.0328,
        'placeName': 'Erfurt, Germany',
        'source': 'gps',
      };
      final repository = PlatformLocationRepository(
        reverseGeocodeUriBuilder: (latitude, longitude) =>
            baseUri.replace(path: '/reverse'),
        geoIpUri: baseUri.replace(path: '/geoip'),
      );

      final fix = await repository.determineLocation();
      expect(
        fix,
        equals(
          const LocationFix(
            latitude: 50.9787,
            longitude: 11.0328,
            placeName: 'Erfurt, Germany',
            source: LocationSource.gps,
          ),
        ),
        reason: 'Native fix with placeName must be returned directly.',
      );
      expect(
        reverseGeocodeRequests,
        equals(0),
        reason: 'No reverse geocoding HTTP request should occur.',
      );
      expect(
        geoIpRequests,
        equals(0),
        reason: 'No GeoIP HTTP request should occur.',
      );
    });

    test('resolves placeName via reverse geocoding and reuses cached placeName within 100 meters', () async {
      channelResponse = <String, Object?>{
        'status': 'found',
        'latitude': 50.9787,
        'longitude': 11.0328,
      };
      final repository = PlatformLocationRepository(
        reverseGeocodeUriBuilder: (latitude, longitude) => baseUri.replace(
          path: '/reverse',
          queryParameters: <String, String>{
            'lat': '$latitude',
            'lon': '$longitude',
          },
        ),
        geoIpUri: baseUri.replace(path: '/geoip'),
      );

      final firstFix = await repository.determineLocation();
      expect(
        firstFix,
        equals(
          const LocationFix(
            latitude: 50.9787,
            longitude: 11.0328,
            placeName: 'Erfurt, Germany',
            source: LocationSource.system,
          ),
        ),
      );
      expect(
        reverseGeocodeRequests,
        equals(1),
        reason: 'Initial un-named coordinate fix must query reverse geocoder.',
      );

      channelResponse = <String, Object?>{
        'status': 'found',
        'latitude': 50.9789,
        'longitude': 11.0330,
      };
      final jitterFix = await repository.determineLocation();
      expect(
        jitterFix,
        equals(
          const LocationFix(
            latitude: 50.9789,
            longitude: 11.0330,
            placeName: 'Erfurt, Germany',
            source: LocationSource.system,
          ),
        ),
        reason: 'Sub-100m movement must reuse cached placeName with updated coordinates.',
      );
      expect(
        reverseGeocodeRequests,
        equals(1),
        reason:
            'Sub-100m movement must not trigger an additional HTTP request.',
      );

      reverseGeocodeResponseBody =
          '{"address":{"town":"Weimar","country":"Germany"}}';
      channelResponse = <String, Object?>{
        'status': 'found',
        'latitude': 50.9795,
        'longitude': 11.3235,
      };
      final distantFix = await repository.determineLocation();
      expect(
        distantFix,
        equals(
          const LocationFix(
            latitude: 50.9795,
            longitude: 11.3235,
            placeName: 'Weimar, Germany',
            source: LocationSource.system,
          ),
        ),
      );
      expect(
        reverseGeocodeRequests,
        equals(2),
        reason:
            'Movement >= 100m must query reverse geocoder for new place name.',
      );
    });

    test('falls back to GeoIP when native channel is unavailable and caches GeoIP result for 30 minutes', () async {
      var now = DateTime.utc(2026, 3, 29, 12, 0);
      channelResponse = <String, Object?>{'status': 'unavailable'};
      final repository = PlatformLocationRepository(
        clock: () => now,
        reverseGeocodeUriBuilder: (latitude, longitude) =>
            baseUri.replace(path: '/reverse'),
        geoIpUri: baseUri.replace(path: '/geoip'),
      );

      final firstFix = await repository.determineLocation();
      expect(
        firstFix,
        equals(
          const LocationFix(
            latitude: 50.9787,
            longitude: 11.0328,
            placeName: 'Erfurt, Germany',
            source: LocationSource.internet,
          ),
        ),
      );
      expect(geoIpRequests, equals(1));

      now = now.add(const Duration(minutes: 29));
      final cachedFix = await repository.determineLocation();
      expect(cachedFix, equals(firstFix));
      expect(
        geoIpRequests,
        equals(1),
        reason:
            'GeoIP response within 30-minute TTL must be served from cache.',
      );

      now = now.add(const Duration(minutes: 1));
      geoIpResponseBody = '{"latitude":51.3397,"longitude":12.3731,"city":"Leipzig","country_name":"Germany"}';
      final refreshedFix = await repository.determineLocation();
      expect(
        refreshedFix,
        equals(
          const LocationFix(
            latitude: 51.3397,
            longitude: 12.3731,
            placeName: 'Leipzig, Germany',
            source: LocationSource.internet,
          ),
        ),
      );
      expect(geoIpRequests, equals(2));

      geoIpResponseBody = '{"latitude":52.5200,"longitude":13.4050,"city":"Berlin","country":"Germany"}';
      final forcedFix = await repository.determineLocation(forceRefresh: true);
      expect(
        forcedFix,
        equals(
          const LocationFix(
            latitude: 52.5200,
            longitude: 13.4050,
            placeName: 'Berlin, Germany',
            source: LocationSource.internet,
          ),
        ),
      );
      expect(geoIpRequests, equals(3));
    });

    test('enforces maxResponseBytes bound and preserves native coordinates when reverse geocoding fails', () async {
      channelResponse = <String, Object?>{
        'status': 'found',
        'latitude': 48.1351,
        'longitude': 11.5820,
      };
      reverseGeocodeResponseBody = jsonEncode(<String, String>{
        'display_name': 'A' * 1024,
      });
      final repository = PlatformLocationRepository(
        maxResponseBytes: 128,
        reverseGeocodeUriBuilder: (latitude, longitude) =>
            baseUri.replace(path: '/reverse'),
        geoIpUri: baseUri.replace(path: '/geoip'),
        fallbackGeoIpUri: baseUri.replace(path: '/geoip-fallback'),
      );

      final fix = await repository.determineLocation();
      expect(
        fix,
        equals(
          const LocationFix(
            latitude: 48.1351,
            longitude: 11.5820,
            source: LocationSource.system,
          ),
        ),
        reason: 'Oversized geocoder response must be rejected while preserving native coordinates.',
      );

      channelResponse = <String, Object?>{'status': 'unavailable'};
      responseStatusCode = HttpStatus.internalServerError;
      fallbackGeoIpStatusCode = HttpStatus.internalServerError;
      final failedFix = await repository.determineLocation(forceRefresh: true);
      expect(
        failedFix,
        isNull,
        reason: 'When both primary and loopback fallback GeoIP endpoints fail, determineLocation must return null.',
      );
      expect(geoIpRequests, equals(1));
      expect(fallbackGeoIpRequests, equals(1));
    });

    test('recovers via secondary fallbackGeoIpUri when primary geoIpUri returns an HTTP error', () async {
      channelResponse = <String, Object?>{'status': 'unavailable'};
      responseStatusCode = HttpStatus.serviceUnavailable;
      fallbackGeoIpStatusCode = HttpStatus.ok;
      final repository = PlatformLocationRepository(
        reverseGeocodeUriBuilder: (latitude, longitude) =>
            baseUri.replace(path: '/reverse'),
        geoIpUri: baseUri.replace(path: '/geoip'),
        fallbackGeoIpUri: baseUri.replace(path: '/geoip-fallback'),
      );

      final fix = await repository.determineLocation();
      expect(
        fix,
        equals(
          const LocationFix(
            latitude: 50.9848,
            longitude: 11.3299,
            placeName: 'Weimar, Germany',
            source: LocationSource.internet,
          ),
        ),
        reason: 'Secondary fallbackGeoIpUri must recover when primary geoIpUri fails.',
      );
      expect(
        geoIpRequests,
        equals(1),
        reason: 'Primary GeoIP endpoint must be queried first.',
      );
      expect(
        fallbackGeoIpRequests,
        equals(1),
        reason: 'Fallback GeoIP endpoint must be queried when primary fails.',
      );
    });

    test('resolves high-accuracy Wi-Fi BSSID positioning before falling back to GeoIP', () async {
      channelResponse = <String, Object?>{
        'status': 'unavailable',
        'wifiAccessPoints': <Map<String, Object?>>[
          <String, Object?>{
            'macAddress': 'aa:bb:cc:dd:ee:01',
            'signalStrength': -58,
          },
          <String, Object?>{
            'macAddress': 'aa:bb:cc:dd:ee:02',
            'signalStrength': -67,
          },
        ],
      };
      final repository = PlatformLocationRepository(
        reverseGeocodeUriBuilder: (latitude, longitude) =>
            baseUri.replace(path: '/reverse'),
        geoIpUri: baseUri.replace(path: '/geoip'),
        fallbackGeoIpUri: baseUri.replace(path: '/geoip'),
        wifiGeolocateUri: baseUri.replace(path: '/wifi'),
      );

      final wifiFix = await repository.determineLocation();
      expect(
        wifiFix,
        equals(
          const LocationFix(
            latitude: 50.9787,
            longitude: 11.0328,
            placeName: 'Erfurt, Germany',
            source: LocationSource.system,
          ),
        ),
        reason: 'Wi-Fi BSSID positioning must resolve street-level coordinates with system source.',
      );
      expect(wifiGeolocateRequests, equals(1));
      expect(
        geoIpRequests,
        equals(0),
        reason: 'Successful Wi-Fi BSSID lookup must not fall back to GeoIP.',
      );

      wifiStatusCode = HttpStatus.notFound;
      final fallbackFix = await repository.determineLocation(
        forceRefresh: true,
      );
      expect(
        fallbackFix,
        equals(
          const LocationFix(
            latitude: 50.9787,
            longitude: 11.0328,
            placeName: 'Erfurt, Germany',
            source: LocationSource.internet,
          ),
        ),
      );
      expect(wifiGeolocateRequests, equals(2));
      expect(geoIpRequests, equals(1));
    });

    test('caps Wi-Fi BSSID scan at maxWifiAccessPoints (20), skips blank or non-string BSSIDs, and preserves optional signalStrength integers', () async {
      expect(
        PlatformLocationRepository.maxWifiAccessPoints,
        equals(20),
        reason: 'maxWifiAccessPoints bound must be 20.',
      );
      final rawAccessPoints = <Object?>[
        'not-a-map',
        <String, Object?>{'macAddress': '   ', 'signalStrength': -40},
        <String, Object?>{'macAddress': 12345, 'signalStrength': -42},
        <String, Object?>{'signalStrength': -45},
        for (var i = 1; i <= 25; i++)
          <String, Object?>{
            'macAddress':
                '  aa:bb:cc:dd:ee:${i.toRadixString(16).padLeft(2, '0')}  ',
            if (i.isOdd) 'signalStrength': -50.7 - i,
            if (i.isEven && i <= 4) 'signalStrength': 'invalid',
          },
      ];
      channelResponse = <String, Object?>{
        'status': 'unavailable',
        'wifiAccessPoints': rawAccessPoints,
      };
      final repository = PlatformLocationRepository(
        reverseGeocodeUriBuilder: (latitude, longitude) =>
            baseUri.replace(path: '/reverse'),
        geoIpUri: baseUri.replace(path: '/geoip'),
        fallbackGeoIpUri: baseUri.replace(path: '/geoip-fallback'),
        wifiGeolocateUri: baseUri.replace(path: '/wifi'),
      );

      final wifiFix = await repository.determineLocation();
      expect(wifiFix, isNotNull);
      expect(wifiGeolocateRequests, equals(1));
      expect(lastWifiRequestBody, isNotNull);

      final Object? decodedPayload = jsonDecode(lastWifiRequestBody ?? '{}');
      expect(decodedPayload, isA<Map<String, Object?>>());
      final payloadMap = decodedPayload is Map<String, Object?>
          ? decodedPayload
          : const <String, Object?>{};
      final Object? rawSentPoints = payloadMap['wifiAccessPoints'];
      expect(rawSentPoints, isA<List<Object?>>());
      final sentPoints = rawSentPoints is List<Object?>
          ? rawSentPoints
          : const <Object?>[];

      expect(
        sentPoints.length,
        equals(PlatformLocationRepository.maxWifiAccessPoints),
        reason: 'Sanitized Wi-Fi access points must be capped at 20 entries.',
      );
      for (var i = 0; i < sentPoints.length; i++) {
        final index = i + 1;
        final expectedMac =
            'aa:bb:cc:dd:ee:${index.toRadixString(16).padLeft(2, '0')}';
        final expectedEntry = <String, Object?>{
          'macAddress': expectedMac,
          if (index.isOdd) 'signalStrength': (-50.7 - index).toInt(),
        };
        expect(
          sentPoints[i],
          equals(expectedEntry),
          reason:
              'Entry at index $i must have trimmed macAddress and optional integer signalStrength.',
        );
      }
    });

    test('enforces maxWifiPositioningAccuracyMeters boundary (2000.0 accepted vs 2000.1 rejected)', () async {
      channelResponse = <String, Object?>{
        'status': 'unavailable',
        'wifiAccessPoints': <Map<String, Object?>>[
          <String, Object?>{'macAddress': 'aa:bb:cc:dd:ee:01'},
          <String, Object?>{'macAddress': 'aa:bb:cc:dd:ee:02'},
        ],
      };
      responseStatusCode = HttpStatus.internalServerError;
      fallbackGeoIpStatusCode = HttpStatus.internalServerError;
      final repository = PlatformLocationRepository(
        reverseGeocodeUriBuilder: (latitude, longitude) =>
            baseUri.replace(path: '/reverse'),
        geoIpUri: baseUri.replace(path: '/geoip'),
        fallbackGeoIpUri: baseUri.replace(path: '/geoip-fallback'),
        wifiGeolocateUri: baseUri.replace(path: '/wifi'),
      );

      final cases =
          <({double accuracy, LocationFix? expectedFix, String label})>[
            (
              accuracy:
                  PlatformLocationRepository.maxWifiPositioningAccuracyMeters,
              expectedFix: const LocationFix(
                latitude: 50.9787,
                longitude: 11.0328,
                source: LocationSource.system,
              ),
              label: '2000.0m exact boundary must be accepted',
            ),
            (
              accuracy: 2000.1,
              expectedFix: null,
              label: '2000.1m exceeding boundary must be rejected',
            ),
          ];

      for (final testCase in cases) {
        wifiGeolocateResponseBody = jsonEncode(<String, Object?>{
          'location': <String, double>{'lat': 50.9787, 'lng': 11.0328},
          'accuracy': testCase.accuracy,
        });
        final result = await repository.determineLocation(forceRefresh: true);
        expect(result, equals(testCase.expectedFix), reason: testCase.label);
      }
    });

    test('searchLocations parses candidates, normalizes display_name to single-line <= 500 runes, caps at 5 results, and enforces query bounds and rate limits', () async {
      final overlongEmojiTail = '🏛️' * 520;
      searchGeocodeResponseBody = jsonEncode(<Map<String, Object?>>[
        <String, Object?>{
          'lat': '50.9725678',
          'lon': '11.0378123',
          'display_name': '  Willy-Brandt-Platz 1,\r\n\t 99084   Erfurt  ',
        },
        <String, Object?>{
          'lat': 50.9780,
          'lon': 11.0290,
          'name': 'Domplatz\nErfurt $overlongEmojiTail',
        },
        <String, Object?>{
          'lat': '50.9800',
          'lon': '11.0300',
          'display_name': ' \r\n\t ',
        },
        <String, Object?>{
          'lat': '50.9810',
          'lon': '11.0310',
          'display_name': 'Candidate 3, Erfurt',
        },
        <String, Object?>{
          'lat': '50.9820',
          'lon': '11.0320',
          'display_name': 'Candidate 4, Erfurt',
        },
        <String, Object?>{
          'lat': '50.9830',
          'lon': '11.0330',
          'display_name': 'Candidate 5, Erfurt',
        },
        <String, Object?>{
          'lat': '50.9840',
          'lon': '11.0340',
          'display_name': 'Candidate 6 (must be capped)',
        },
      ]);

      final repository = PlatformLocationRepository(
        minSearchInterval: Duration.zero,
        searchGeocodeUriBuilder: (query) => baseUri.replace(
          path: '/search',
          queryParameters: <String, String>{'q': query},
        ),
      );

      expect(
        await repository.searchLocations('   '),
        isEmpty,
        reason: 'Empty or whitespace query must return empty list without HTTP calls',
      );
      expect(
        await repository.searchLocations('A' * 501),
        isEmpty,
        reason: 'Query exceeding maxSearchQueryLength (500) must be rejected without HTTP calls',
      );
      expect(searchGeocodeRequests, equals(0));

      final results = await repository.searchLocations(
        '  Willy-Brandt-Platz 1,\nErfurt  ',
      );
      expect(searchGeocodeRequests, equals(1));
      expect(
        lastSearchQueryParam,
        equals('Willy-Brandt-Platz 1, Erfurt'),
        reason: 'Search query must be single-line normalized before sending',
      );
      expect(
        results.length,
        equals(5),
        reason: 'searchLocations must skip empty display_name and cap at 5 candidates',
      );
      expect(
        results[0],
        equals(
          const GeocodingCandidate(
            displayName: 'Willy-Brandt-Platz 1, 99084 Erfurt',
            latitude: 50.9725678,
            longitude: 11.0378123,
          ),
        ),
        reason: 'First candidate must have normalized single-line displayName',
      );
      expect(
        results[1].displayName.runes.length,
        equals(500),
        reason: 'Second candidate displayName must be truncated to 500 Unicode scalar values',
      );
      expect(
        results[1].displayName.contains('\n'),
        isFalse,
        reason: 'Sanitized displayName must never contain newlines',
      );

      searchStatusCode = HttpStatus.internalServerError;
      expect(
        await repository.searchLocations('Erfurt'),
        isEmpty,
        reason: 'HTTP 500 on search endpoint must return empty list',
      );
    });
  });

  group('FakeLocationRepository', () {
    test('records callCount, lastForceRefresh, searchCallCount, lastSearchQuery, and returns configured results', () async {
      const initialFix = LocationFix(
        latitude: 50.9787,
        longitude: 11.0328,
        placeName: 'Erfurt, Germany',
      );
      final fake = FakeLocationRepository(initialFix: initialFix);
      expect(fake.callCount, equals(0));
      expect(fake.lastForceRefresh, isFalse);
      expect(fake.searchCallCount, equals(0));
      expect(fake.lastSearchQuery, isNull);

      final result1 = await fake.determineLocation();
      expect(result1, equals(initialFix));
      expect(fake.callCount, equals(1));
      expect(fake.lastForceRefresh, isFalse);

      fake.currentFix = null;
      final result2 = await fake.determineLocation(forceRefresh: true);
      expect(result2, isNull);
      expect(fake.callCount, equals(2));
      expect(fake.lastForceRefresh, isTrue);

      const candidate = GeocodingCandidate(
        displayName: 'Bahnhofstraße 1, 99084 Erfurt',
        latitude: 50.9735,
        longitude: 11.0365,
      );
      fake.searchResults = const <GeocodingCandidate>[candidate];
      final searchMatches = await fake.searchLocations('Bahnhofstraße 1');
      expect(searchMatches, equals(const <GeocodingCandidate>[candidate]));
      expect(fake.searchCallCount, equals(1));
      expect(fake.lastSearchQuery, equals('Bahnhofstraße 1'));
    });
  });
}
