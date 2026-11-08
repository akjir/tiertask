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
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/services/plus_code_service.dart';

void main() {
  group('PlusCodeService', () {
    test(
      'classifies TdfLocation.source strings into gps, plusCode, and address',
      () {
        expect(
          PlusCodeService.classifySource(null),
          equals(LocationSourceType.gps),
          reason: 'Null source must classify as gps',
        );
        expect(
          PlusCodeService.classifySource(''),
          equals(LocationSourceType.gps),
          reason: 'Empty source must classify as gps',
        );
        expect(
          PlusCodeService.classifySource('   '),
          equals(LocationSourceType.gps),
          reason: 'Whitespace source must classify as gps',
        );
        expect(
          PlusCodeService.classifySource('gps'),
          equals(LocationSourceType.gps),
          reason: 'Legacy gps token must classify as gps',
        );
        expect(
          PlusCodeService.classifySource('  GPS '),
          equals(LocationSourceType.gps),
          reason: 'Case-insensitive GPS token must classify as gps',
        );
        expect(
          PlusCodeService.classifySource('manual'),
          equals(LocationSourceType.gps),
          reason: 'Legacy manual token must classify as gps',
        );
        expect(
          PlusCodeService.classifySource('MANUAL'),
          equals(LocationSourceType.gps),
          reason: 'Case-insensitive MANUAL token must classify as gps',
        );
        expect(
          PlusCodeService.classifySource('9F2PXXH7+F4'),
          equals(LocationSourceType.plusCode),
          reason: 'Full Plus Code must classify as plusCode',
        );
        expect(
          PlusCodeService.classifySource('9F2PXXH7+F4 Erfurt'),
          equals(LocationSourceType.plusCode),
          reason:
              'Full Plus Code with locality suffix must classify as plusCode',
        );
        expect(
          PlusCodeService.classifySource('XXH7+F4 Erfurt'),
          equals(LocationSourceType.plusCode),
          reason: 'Short Plus Code with locality must classify as plusCode',
        );
        expect(
          PlusCodeService.classifySource('Erfurt, XXH7+F4'),
          equals(LocationSourceType.plusCode),
          reason:
              'Locality followed by short Plus Code must classify as plusCode',
        );
        expect(
          PlusCodeService.classifySource('Bahnhofstraße 1, 99084 Erfurt'),
          equals(LocationSourceType.address),
          reason: 'Street address must classify as address',
        );
        expect(
          PlusCodeService.classifySource('XXH7+F4'),
          equals(LocationSourceType.address),
          reason: 'Short Plus Code without locality cannot be resolved as Plus Code and classifies as address',
        );
        expect(
          PlusCodeService.classifySource('${' ' * 495}9F2PXXH7+F4'),
          equals(LocationSourceType.address),
          reason: 'Oversized source exceeding maxInputLength before trimming must classify as address',
        );
        expect(
          PlusCodeService.classifySource('${' ' * 500}gps'),
          equals(LocationSourceType.address),
          reason: 'Oversized padded gps token exceeding maxInputLength must be rejected before trimming',
        );
      },
    );

    test('parses full, short, and invalid Plus Code inputs and preserves optional localitySuffix', () {
      final fullOnly = PlusCodeService.parseInput('  9f2pxxh7+f4  ');
      expect(
        fullOnly,
        equals(const FullPlusCodeInput(fullCode: '9F2PXXH7+F4')),
        reason: 'Lowercase full Plus Code must normalize to uppercase without localitySuffix',
      );
      expect(
        fullOnly.hashCode,
        equals(const FullPlusCodeInput(fullCode: '9F2PXXH7+F4').hashCode),
      );
      expect(fullOnly.toString(), contains('9F2PXXH7+F4'));

      final fullWithLocalityAfter = PlusCodeService.parseInput(
        '9F2PXXH7+F4 Erfurt, Germany',
      );
      expect(
        fullWithLocalityAfter,
        equals(
          const FullPlusCodeInput(
            fullCode: '9F2PXXH7+F4',
            localitySuffix: 'Erfurt, Germany',
          ),
        ),
        reason: 'Full Plus Code with trailing locality must preserve localitySuffix',
      );

      final fullWithLocalityBefore = PlusCodeService.parseInput(
        'Erfurt, 9F2PXXH7+F4',
      );
      expect(
        fullWithLocalityBefore,
        equals(
          const FullPlusCodeInput(
            fullCode: '9F2PXXH7+F4',
            localitySuffix: 'Erfurt',
          ),
        ),
        reason: 'Full Plus Code with leading locality must preserve cleaned localitySuffix',
      );

      final shortAfter = PlusCodeService.parseInput('xxh7+f4 Erfurt, Germany');
      expect(
        shortAfter,
        equals(
          const ShortPlusCodeInput(
            localityQuery: 'Erfurt, Germany',
            shortCode: 'XXH7+F4',
          ),
        ),
        reason: '4-digit prefix short code with trailing locality must parse as ShortPlusCodeInput',
      );
      expect(
        shortAfter.hashCode,
        equals(
          const ShortPlusCodeInput(
            localityQuery: 'Erfurt, Germany',
            shortCode: 'XXH7+F4',
          ).hashCode,
        ),
      );
      expect(shortAfter.toString(), contains('XXH7+F4'));

      final short6PrefixBefore = PlusCodeService.parseInput(
        'Erfurt, 2PXXH7+F4',
      );
      expect(
        short6PrefixBefore,
        equals(
          const ShortPlusCodeInput(
            localityQuery: 'Erfurt',
            shortCode: '2PXXH7+F4',
          ),
        ),
        reason: '6-digit prefix short code with leading locality must parse as ShortPlusCodeInput',
      );

      for (final invalid in <String>[
        '',
        '   ',
        'Bahnhofstraße 1, 99084 Erfurt',
        'XXH7+F4',
        'H7+F4 Erfurt',
        '9F2PXXH7++F4',
        '9F2PXXH7+',
        '9F2PXXH7+F0',
        '9F2PXXH7+FA',
        '9F2PXXH7+F1',
        '9F2P00H7+F4',
        '9F2PXXH7+F42345678',
        'A' * 501,
      ]) {
        final parsed = PlusCodeService.parseInput(invalid);
        expect(
          parsed,
          equals(const InvalidPlusCodeInput()),
          reason: 'Input "$invalid" must be rejected as InvalidPlusCodeInput',
        );
      }
      expect(
        const InvalidPlusCodeInput().hashCode,
        equals(const InvalidPlusCodeInput().hashCode),
      );
      expect(
        const InvalidPlusCodeInput().toString(),
        contains('InvalidPlusCodeInput'),
      );
    });

    test('decodes and encodes standard Open Location Code vectors and grid refinement codes', () {
      final erfurtArea = PlusCodeService.decode('9F2HX2HM+F4');
      expect(erfurtArea, isNotNull);
      expect(erfurtArea?.latitudeLo, closeTo(50.978625, 1e-6));
      expect(erfurtArea?.latitudeHi, closeTo(50.978750, 1e-6));
      expect(erfurtArea?.longitudeLo, closeTo(11.032750, 1e-6));
      expect(erfurtArea?.longitudeHi, closeTo(11.032875, 1e-6));
      expect(erfurtArea?.latitudeCenter, closeTo(50.9786875, 1e-7));
      expect(erfurtArea?.longitudeCenter, closeTo(11.0328125, 1e-7));
      expect(
        erfurtArea,
        equals(PlusCodeService.decode('9f2hx2hm+f4')),
        reason: 'Decoding must be case-insensitive and value-equal',
      );
      expect(
        erfurtArea.hashCode,
        equals(PlusCodeService.decode('9f2hx2hm+f4').hashCode),
      );
      expect(erfurtArea.toString(), contains('PlusCodeArea'));

      final specExampleArea = PlusCodeService.decode('9F2PXXH7+F4');
      expect(specExampleArea, isNotNull);
      expect(specExampleArea?.latitudeCenter, closeTo(50.9786875, 1e-7));
      expect(specExampleArea?.longitudeCenter, closeTo(14.9628125, 1e-7));

      final zurichArea = PlusCodeService.decode('8FVC9G8F+6W');
      expect(zurichArea, isNotNull);
      expect(zurichArea?.latitudeCenter, closeTo(47.3655625, 1e-6));
      expect(zurichArea?.longitudeCenter, closeTo(8.5248125, 1e-6));

      final mountainViewArea = PlusCodeService.decode('849VCWC8+R9');
      expect(mountainViewArea, isNotNull);
      expect(mountainViewArea?.latitudeCenter, closeTo(37.4220625, 1e-6));
      expect(mountainViewArea?.longitudeCenter, closeTo(-122.0840625, 1e-6));

      final paddedArea = PlusCodeService.decode('9F2H0000+');
      expect(paddedArea, isNotNull);
      expect(paddedArea?.latitudeLo, closeTo(50.0, 1e-6));
      expect(paddedArea?.latitudeHi, closeTo(51.0, 1e-6));
      expect(paddedArea?.longitudeLo, closeTo(11.0, 1e-6));
      expect(paddedArea?.longitudeHi, closeTo(12.0, 1e-6));

      final refinedArea = PlusCodeService.decode('9F2HX2HM+F42');
      expect(refinedArea, isNotNull);
      expect(
        refinedArea!.latitudeHi - refinedArea.latitudeLo,
        closeTo(0.000125 / 5.0, 1e-9),
        reason: '11-digit code must refine latitude by 1/5 of a 10-digit cell',
      );
      expect(
        refinedArea.longitudeHi - refinedArea.longitudeLo,
        closeTo(0.000125 / 4.0, 1e-9),
        reason: '11-digit code must refine longitude by 1/4 of a 10-digit cell',
      );

      final encodedErfurt = PlusCodeService.encode(50.9786875, 11.0328125);
      expect(
        encodedErfurt,
        equals('9F2HX2HM+F4'),
        reason: 'Encoding center of 9F2HX2HM+F4 must produce 9F2HX2HM+F4',
      );

      final encoded11 = PlusCodeService.encode(
        50.97863,
        11.03276,
        codeLength: 11,
      );
      expect(
        encoded11,
        equals('9F2HX2HM+F42'),
        reason: '11-digit encoding of bottom-left subcell must end with 2',
      );

      final encodedPadded = PlusCodeService.encode(50.5, 11.5, codeLength: 4);
      expect(
        encodedPadded,
        equals('9F2H0000+'),
        reason: '4-digit encoding must pad remaining 4 prefix positions with 0',
      );

      expect(PlusCodeService.decode('X2HM+F4'), isNull);
      expect(
        PlusCodeService.decode('${' ' * 490}9F2HX2HM+F4'),
        isNull,
        reason: 'Oversized fullCode exceeding maxInputLength before trimming must return null',
      );
    });

    test('normalizes odd pair codeLength < 10 to valid even pair lengths in encode', () {
      final expectedLengths = <int, int>{3: 2, 5: 4, 7: 6, 9: 8};
      for (final entry in expectedLengths.entries) {
        final oddLength = entry.key;
        final evenLength = entry.value;
        final encodedOdd = PlusCodeService.encode(
          50.9786875,
          11.0328125,
          codeLength: oddLength,
        );
        final encodedEven = PlusCodeService.encode(
          50.9786875,
          11.0328125,
          codeLength: evenLength,
        );
        expect(
          encodedOdd,
          equals(encodedEven),
          reason:
              'Odd pair codeLength $oddLength must normalize to even pair codeLength $evenLength',
        );
        expect(
          PlusCodeService.isFullCode(encodedOdd),
          isTrue,
          reason:
              'Encoded result for odd codeLength $oddLength must be a valid full Plus Code',
        );
        expect(
          PlusCodeService.decode(encodedOdd),
          isNotNull,
          reason:
              'Encoded result for odd codeLength $oddLength must be decodable',
        );
      }
    });

    test('handles non-finite coordinates, extreme finite longitudes, and polar latitudes in encode and recoverNearest', () {
      final zeroCode = PlusCodeService.encode(0.0, 0.0);
      for (final nonFinite in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          PlusCodeService.encode(nonFinite, 0.0),
          equals(zeroCode),
          reason: 'Non-finite latitude $nonFinite must fall back to 0.0',
        );
        expect(
          PlusCodeService.encode(0.0, nonFinite),
          equals(zeroCode),
          reason: 'Non-finite longitude $nonFinite must fall back to 0.0',
        );
        expect(
          PlusCodeService.recoverNearest('XXH7+F4', nonFinite, 11.0),
          isNull,
          reason:
              'Non-finite referenceLatitude $nonFinite must return null in recoverNearest',
        );
        expect(
          PlusCodeService.recoverNearest('XXH7+F4', 50.0, nonFinite),
          isNull,
          reason:
              'Non-finite referenceLongitude $nonFinite must return null in recoverNearest',
        );
      }

      for (final extremeLongitude in <double>[
        1e20,
        -1e20,
        180.0,
        -180.0,
        540.0,
        -540.0,
      ]) {
        final encoded = PlusCodeService.encode(50.0, extremeLongitude);
        expect(
          PlusCodeService.isFullCode(encoded),
          isTrue,
          reason:
              'Extreme finite longitude $extremeLongitude must encode to a valid full Plus Code in O(1)',
        );
        final recovered = PlusCodeService.recoverNearest(
          'X2HM+F4',
          50.9787,
          extremeLongitude,
        );
        expect(
          recovered,
          isNotNull,
          reason:
              'Extreme finite referenceLongitude $extremeLongitude must recover without hanging',
        );
      }

      expect(
        PlusCodeService.encode(0.0, 180.0),
        equals(PlusCodeService.encode(0.0, -180.0)),
        reason: 'Longitude 180.0 must wrap to -180.0',
      );
      expect(
        PlusCodeService.encode(0.0, 540.0),
        equals(PlusCodeService.encode(0.0, -180.0)),
        reason: 'Longitude 540.0 must wrap to -180.0',
      );
      expect(
        PlusCodeService.encode(0.0, -540.0),
        equals(PlusCodeService.encode(0.0, -180.0)),
        reason: 'Longitude -540.0 must wrap to -180.0',
      );

      final northPole10 = PlusCodeService.encode(90.0, 0.0, codeLength: 10);
      expect(
        PlusCodeService.decode(northPole10)?.latitudeHi,
        closeTo(90.0, 1e-6),
        reason: 'North Pole 10-digit code must be inside northernmost cell',
      );
      final northPole11 = PlusCodeService.encode(90.0, 0.0, codeLength: 11);
      expect(
        PlusCodeService.decode(northPole11)?.latitudeHi,
        closeTo(90.0, 1e-6),
        reason: 'North Pole 11-digit code must be inside northernmost subcell',
      );
      final southPole10 = PlusCodeService.encode(-90.0, 0.0, codeLength: 10);
      expect(
        PlusCodeService.decode(southPole10)?.latitudeLo,
        closeTo(-90.0, 1e-6),
        reason: 'South Pole 10-digit code must start at -90.0',
      );
    });

    test('recovers full Open Location Codes from short codes and reference coordinates across cell boundaries', () {
      expect(
        PlusCodeService.recoverNearest('X2HM+F4', 50.9787, 11.0328),
        equals('9F2HX2HM+F4'),
        reason: '4-digit short code near Erfurt must recover 9F2HX2HM+F4',
      );
      expect(
        PlusCodeService.recoverNearest('2HX2HM+F4', 50.9787, 11.0328),
        equals('9F2HX2HM+F4'),
        reason: '6-digit short code near Erfurt must recover 9F2HX2HM+F4',
      );
      expect(
        PlusCodeService.recoverNearest('9G8F+6W', 47.3655, 8.5248),
        equals('8FVC9G8F+6W'),
        reason: 'Short code near Zurich must recover 8FVC9G8F+6W',
      );
      expect(
        PlusCodeService.recoverNearest('X2HM+F4', 51.05, 11.0328),
        equals('9F2HX2HM+F4'),
        reason: 'Reference latitude slightly north of 51.0° must still recover nearest 50.9787° cell',
      );
      expect(
        PlusCodeService.recoverNearest('2222+22', 50.95, 11.0328),
        equals('9F3H2222+22'),
        reason: 'Short code at bottom of northern cell when reference is at top of southern cell must shift north',
      );

      final sydneyFull = PlusCodeService.encode(-33.8688, 151.2093);
      final sydneyShort = sydneyFull.substring(4);
      expect(
        PlusCodeService.recoverNearest(sydneyShort, -33.86, 151.20),
        equals(sydneyFull),
        reason:
            'Southern/Eastern hemisphere short code must recover accurately',
      );

      final saoPauloFull = PlusCodeService.encode(-23.5505, -46.6333);
      final saoPauloShort = saoPauloFull.substring(4);
      expect(
        PlusCodeService.recoverNearest(saoPauloShort, -23.55, -46.63),
        equals(saoPauloFull),
        reason:
            'Southern/Western hemisphere short code must recover accurately',
      );

      expect(
        PlusCodeService.recoverNearest('9F2PXXH7+F4', 50.9787, 11.0328),
        equals('9F2PXXH7+F4'),
        reason: 'Full code passed to recoverNearest must return uppercase full code',
      );
      expect(
        PlusCodeService.recoverNearest('INVALID', 50.0, 11.0),
        isNull,
        reason: 'Invalid code must return null',
      );
      expect(
        PlusCodeService.recoverNearest('XXH7+F4', double.nan, 11.0),
        isNull,
        reason: 'NaN reference latitude must return null',
      );
      expect(
        PlusCodeService.recoverNearest('${' ' * 495}XXH7+F4', 50.9787, 11.0328),
        isNull,
        reason: 'Oversized shortCode exceeding maxInputLength before trimming must return null',
      );
    });

    test('normalizes single-line text, strips C0/C1 control characters and lone surrogates, and truncates at 500 Unicode scalar values', () {
      const messy = '  Bahnhofstraße 1,\r\n\t 99084   Erfurt \n ';
      expect(
        PlusCodeService.normalizeSingleLineText(messy),
        equals('Bahnhofstraße 1, 99084 Erfurt'),
        reason: 'CR, LF, and TAB must be replaced with spaces and collapsed',
      );

      const withControlsAndSurrogates =
          'Erf\u0000urt\u0007 \u001BMain\u007F-\u0085Taunus\u009F \uD800\u{1D11E}\uDC00';
      expect(
        PlusCodeService.normalizeSingleLineText(withControlsAndSurrogates),
        equals('Erfurt Main-Taunus \u{1D11E}'),
        reason: 'C0/C1 control characters and lone surrogates must be stripped while preserving supplementary characters',
      );
      expect(
        PlusCodeService.truncateToMaxTextLength(withControlsAndSurrogates),
        equals('Erfurt Main-Taunus \u{1D11E}'),
        reason: 'truncateToMaxTextLength must strip C0/C1 controls and lone surrogates while preserving valid non-BMP characters',
      );

      final astralText = '\u{1F30D}' * 505;
      final truncated = PlusCodeService.truncateToMaxTextLength(astralText);
      expect(
        truncated.runes.length,
        equals(maxTdfTextLength),
        reason: 'Truncated text must contain at most 500 Unicode scalar values',
      );
      expect(
        truncated.length,
        equals(maxTdfTextLength * 2),
        reason:
            'Astral surrogate pairs must remain intact without lone surrogates',
      );
    });

    test('enforces value equality and inequality across PlusCodeInput variants and PlusCodeArea', () {
      const fullA = FullPlusCodeInput(
        fullCode: '9F2PXXH7+F4',
        localitySuffix: 'Erfurt',
      );
      const fullSame = FullPlusCodeInput(
        fullCode: '9F2PXXH7+F4',
        localitySuffix: 'Erfurt',
      );
      const fullDifferentCode = FullPlusCodeInput(
        fullCode: '8FVC9G8F+6W',
        localitySuffix: 'Erfurt',
      );
      const fullDifferentLocality = FullPlusCodeInput(
        fullCode: '9F2PXXH7+F4',
        localitySuffix: 'Weimar',
      );
      expect(fullA, equals(fullSame));
      expect(fullA.hashCode, equals(fullSame.hashCode));
      expect(fullA, isNot(equals(fullDifferentCode)));
      expect(fullA, isNot(equals(fullDifferentLocality)));

      const shortA = ShortPlusCodeInput(
        localityQuery: 'Erfurt',
        shortCode: 'XXH7+F4',
      );
      const shortSame = ShortPlusCodeInput(
        localityQuery: 'Erfurt',
        shortCode: 'XXH7+F4',
      );
      const shortDifferentCode = ShortPlusCodeInput(
        localityQuery: 'Erfurt',
        shortCode: '9G8F+6W',
      );
      const shortDifferentLocality = ShortPlusCodeInput(
        localityQuery: 'Weimar',
        shortCode: 'XXH7+F4',
      );
      expect(shortA, equals(shortSame));
      expect(shortA.hashCode, equals(shortSame.hashCode));
      expect(shortA, isNot(equals(shortDifferentCode)));
      expect(shortA, isNot(equals(shortDifferentLocality)));

      const invalidA = InvalidPlusCodeInput();
      const invalidB = InvalidPlusCodeInput();
      expect(invalidA, equals(invalidB));
      expect(invalidA.hashCode, equals(invalidB.hashCode));
      expect(invalidA, isNot(equals(fullA)));
      expect(invalidA, isNot(equals(shortA)));

      const areaA = PlusCodeArea(
        latitudeLo: 50.0,
        latitudeHi: 51.0,
        longitudeLo: 11.0,
        longitudeHi: 12.0,
      );
      const areaSame = PlusCodeArea(
        latitudeLo: 50.0,
        latitudeHi: 51.0,
        longitudeLo: 11.0,
        longitudeHi: 12.0,
      );
      const areaDifferentLatitudeLow = PlusCodeArea(
        latitudeLo: 49.0,
        latitudeHi: 51.0,
        longitudeLo: 11.0,
        longitudeHi: 12.0,
      );
      const areaDifferentLatitudeHigh = PlusCodeArea(
        latitudeLo: 50.0,
        latitudeHi: 52.0,
        longitudeLo: 11.0,
        longitudeHi: 12.0,
      );
      const areaDifferentLongitudeLow = PlusCodeArea(
        latitudeLo: 50.0,
        latitudeHi: 51.0,
        longitudeLo: 10.0,
        longitudeHi: 12.0,
      );
      const areaDifferentLongitudeHigh = PlusCodeArea(
        latitudeLo: 50.0,
        latitudeHi: 51.0,
        longitudeLo: 11.0,
        longitudeHi: 13.0,
      );
      expect(areaA, equals(areaSame));
      expect(areaA.hashCode, equals(areaSame.hashCode));
      expect(areaA, isNot(equals(areaDifferentLatitudeLow)));
      expect(areaA, isNot(equals(areaDifferentLatitudeHigh)));
      expect(areaA, isNot(equals(areaDifferentLongitudeLow)));
      expect(areaA, isNot(equals(areaDifferentLongitudeHigh)));
    });
  });
}
