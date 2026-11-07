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
    var geoIpRequests = 0;
    var wifiGeolocateRequests = 0;
    var responseStatusCode = HttpStatus.ok;
    var wifiStatusCode = HttpStatus.ok;
    var reverseGeocodeResponseBody =
        '{"address":{"city":"Erfurt","country":"Germany"}}';
    var geoIpResponseBody =
        '{"latitude":"50.9787","longitude":"11.0328","city":"Erfurt","country":"Germany"}';
    var wifiGeolocateResponseBody =
        '{"location":{"lat":50.9787,"lng":11.0328},"accuracy":35.0}';
    Map<String, Object?>? channelResponse;

    setUp(() async {
      HttpOverrides.global = null;
      reverseGeocodeRequests = 0;
      geoIpRequests = 0;
      wifiGeolocateRequests = 0;
      responseStatusCode = HttpStatus.ok;
      wifiStatusCode = HttpStatus.ok;
      reverseGeocodeResponseBody =
          '{"address":{"city":"Erfurt","country":"Germany"}}';
      geoIpResponseBody = '{"latitude":"50.9787","longitude":"11.0328","city":"Erfurt","country":"Germany"}';
      wifiGeolocateResponseBody =
          '{"location":{"lat":50.9787,"lng":11.0328},"accuracy":35.0}';
      channelResponse = <String, Object?>{'status': 'unavailable'};

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
        } else if (request.uri.path == '/geoip') {
          request.response.statusCode = responseStatusCode;
          geoIpRequests++;
          request.response.write(geoIpResponseBody);
        } else if (request.uri.path == '/wifi') {
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
      final failedFix = await repository.determineLocation(forceRefresh: true);
      expect(failedFix, isNull);
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
  });

  group('FakeLocationRepository', () {
    test(
      'records callCount, lastForceRefresh, and returns currentFix',
      () async {
        const initialFix = LocationFix(
          latitude: 50.9787,
          longitude: 11.0328,
          placeName: 'Erfurt, Germany',
        );
        final fake = FakeLocationRepository(initialFix: initialFix);
        expect(fake.callCount, equals(0));
        expect(fake.lastForceRefresh, isFalse);

        final result1 = await fake.determineLocation();
        expect(result1, equals(initialFix));
        expect(fake.callCount, equals(1));
        expect(fake.lastForceRefresh, isFalse);

        fake.currentFix = null;
        final result2 = await fake.determineLocation(forceRefresh: true);
        expect(result2, isNull);
        expect(fake.callCount, equals(2));
        expect(fake.lastForceRefresh, isTrue);
      },
    );
  });
}
