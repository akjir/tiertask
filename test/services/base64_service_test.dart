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
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/services/base64_service.dart';

void main() {
  const service = Base64Service();

  group('Base64Service RFC 4648 Vectors & Functional Round-Trips', () {
    test('encodes and decodes canonical RFC 4648 Section 10 test vectors', () {
      const vectors = <(String, String)>[
        ('', ''),
        ('f', 'Zg=='),
        ('fo', 'Zm8='),
        ('foo', 'Zm9v'),
        ('foob', 'Zm9vYg=='),
        ('fooba', 'Zm9vYmE='),
        ('foobar', 'Zm9vYmFy'),
      ];

      for (final (plain, expectedEncoded) in vectors) {
        final plainBytes = Uint8List.fromList(utf8.encode(plain));
        final encoded = service.encodeBytes(plainBytes);
        expect(
          encoded,
          equals(expectedEncoded),
          reason: 'RFC 4648 vector for "$plain" must match "$expectedEncoded"',
        );
        final decoded = service.decodeBytes(encoded);
        expect(
          decoded,
          equals(plainBytes),
          reason: 'Decoded bytes for "$encoded" must match "$plain"',
        );
      }
    });

    test('round-trips arbitrary binary byte arrays across all 256 byte values and modulo-3 lengths', () {
      for (final length in <int>[0, 1, 2, 3, 4, 5, 6, 63, 64, 65, 255, 256]) {
        final input = Uint8List.fromList(
          List<int>.generate(length, (i) => (i * 73 + 19) & 0xFF),
        );
        final encoded = service.encodeBytes(input);
        expect(
          encoded.length % 4,
          equals(0),
          reason: 'Encoded length for $length bytes must be a multiple of 4',
        );
        final decoded = service.decodeBytes(encoded);
        expect(
          decoded,
          equals(input),
          reason: 'Round-trip bytes for length $length must match input',
        );
      }
    });

    test('encodes binary workspace payloads without quotes or backslashes for GKeyFile compatibility', () {
      final workspaces = <AppWorkspace>[
        const AppWorkspace(
          id: 'tasks',
          name: 'Tasks ÄÖÜß',
          config: WebDavConfig(
            serverUrl: 'https://cloud.example.com',
            username: 'stefan',
            password: r'p"a\\s$w0rd!',
            filePath: 'tasks.tdf',
            localFilePath: 'tasks.tdf',
            storageMode: StorageMode.both,
            language: AppLanguage.german,
            themeMode: AppThemeMode.dark,
            themePalette: AppThemePalette.slate,
            showOpenTaskCount: true,
          ),
        ),
      ];
      final binaryPayload = AppWorkspace.encodePersistedState(
        workspaces,
        activeId: 'tasks',
      );

      final encoded = service.encodeBytes(binaryPayload);
      expect(encoded, isNotEmpty);
      expect(
        encoded.contains('"'),
        isFalse,
        reason: 'Base64 output must never contain double quotes',
      );
      expect(
        encoded.contains(r'\'),
        isFalse,
        reason: 'Base64 output must never contain backslashes',
      );
      final decodedBytes = service.decodeBytes(encoded);
      expect(
        decodedBytes,
        equals(binaryPayload),
        reason: 'Decoded workspace bytes must match the original payload',
      );
    });
  });

  group('Base64Service Security, Bounds & Error Exhaustiveness', () {
    test('enforces maxInputBytes boundary and pre-scan length checks on encodeBytes and decodeBytes', () {
      const boundedService = Base64Service(maxInputBytes: 6);

      final fiveBytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
      final sixBytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6]);
      final sevenBytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7]);

      expect(boundedService.encodeBytes(fiveBytes), hasLength(8));
      final exactEncoded = boundedService.encodeBytes(sixBytes);
      expect(exactEncoded, hasLength(8));
      expect(boundedService.decodeBytes(exactEncoded), equals(sixBytes));

      expect(
        () => boundedService.encodeBytes(sevenBytes),
        throwsA(
          isA<Base64Exception>().having(
            (error) => error.kind,
            'kind',
            Base64ErrorKind.inputTooLarge,
          ),
        ),
        reason: 'N+1 input bytes must be rejected before encoding',
      );

      final oversizedEncoded = service.encodeBytes(sevenBytes);
      expect(
        () => boundedService.decodeBytes(oversizedEncoded),
        throwsA(
          isA<Base64Exception>().having(
            (error) => error.kind,
            'kind',
            Base64ErrorKind.inputTooLarge,
          ),
        ),
        reason: 'Encoded payload decoding to N+1 bytes must be rejected',
      );

      for (final oversizedMalformed in <String>[
        'AAAAAAAAA',
        'AAAAAAAA====',
        '====AAAA====',
      ]) {
        expect(
          () => boundedService.decodeBytes(oversizedMalformed),
          throwsA(
            isA<Base64Exception>().having(
              (error) => error.kind,
              'kind',
              Base64ErrorKind.inputTooLarge,
            ),
          ),
          reason:
              'Oversized input "$oversizedMalformed" must fail with inputTooLarge before modulo-4 or padding checks',
        );
      }

      const zeroBoundedService = Base64Service(maxInputBytes: 0);
      expect(zeroBoundedService.encodeBytes(const <int>[]), isEmpty);
      expect(zeroBoundedService.decodeBytes(''), isEmpty);
      expect(
        () => zeroBoundedService.decodeBytes('===='),
        throwsA(
          isA<Base64Exception>().having(
            (error) => error.kind,
            'kind',
            Base64ErrorKind.inputTooLarge,
          ),
        ),
        reason: 'Non-empty encoded string when maxInputBytes is 0 must throw inputTooLarge before padding checks',
      );

      const negativeBoundedService = Base64Service(maxInputBytes: -1);
      expect(
        () => negativeBoundedService.encodeBytes(const <int>[]),
        throwsA(
          isA<Base64Exception>().having(
            (error) => error.kind,
            'kind',
            Base64ErrorKind.inputTooLarge,
          ),
        ),
        reason: 'Negative maxInputBytes must reject empty encodeBytes input with inputTooLarge',
      );
      expect(
        () => negativeBoundedService.decodeBytes(''),
        throwsA(
          isA<Base64Exception>().having(
            (error) => error.kind,
            'kind',
            Base64ErrorKind.inputTooLarge,
          ),
        ),
        reason: 'Negative maxInputBytes must reject empty decodeBytes input with inputTooLarge',
      );
    });

    test('rejects invalid lengths, out-of-alphabet characters, malformed padding, and non-canonical padding bits across all Base64ErrorKind variants', () {
      for (final invalidLengthInput in <String>[
        'A',
        'AB',
        'ABC',
        'ABCDE',
        'ABCDEF',
        'ABCDEFG',
      ]) {
        expect(
          () => service.decodeBytes(invalidLengthInput),
          throwsA(
            isA<Base64Exception>().having(
              (error) => error.kind,
              'kind',
              Base64ErrorKind.invalidLength,
            ),
          ),
          reason: 'Length ${invalidLengthInput.length} must be rejected',
        );
      }

      for (final invalidByte in <int>[-1, -255, 256, 1024]) {
        expect(
          () => service.encodeBytes(<int>[invalidByte]),
          throwsA(
            isA<Base64Exception>().having(
              (error) => error.kind,
              'kind',
              Base64ErrorKind.invalidCharacter,
            ),
          ),
          reason: 'Out-of-range byte $invalidByte must be rejected',
        );
      }

      for (final invalidCharacterInput in <String>[
        'Zm9\n',
        'Zm9\r',
        'Zm9 ',
        'Zm9\x00',
        'Zm9"',
        r'Zm9\',
        'Zm9-',
        'Zm9_',
        'Zm9ä',
        'Zm9\u0100',
      ]) {
        expect(
          () => service.decodeBytes(invalidCharacterInput),
          throwsA(
            isA<Base64Exception>().having(
              (error) => error.kind,
              'kind',
              Base64ErrorKind.invalidCharacter,
            ),
          ),
          reason: 'Out-of-alphabet input "$invalidCharacterInput" must fail',
        );
      }

      for (final invalidPaddingInput in <String>[
        '====',
        '=AAA',
        '==AA',
        '===A',
        'A=AA',
        'A==A',
        'AA=A',
        'Zg==Zg==',
        'Zm8=Zm9v',
      ]) {
        expect(
          () => service.decodeBytes(invalidPaddingInput),
          throwsA(
            isA<Base64Exception>().having(
              (error) => error.kind,
              'kind',
              Base64ErrorKind.invalidPadding,
            ),
          ),
          reason: 'Malformed padding "$invalidPaddingInput" must fail',
        );
      }

      for (final nonCanonicalInput in <String>[
        'Zh==',
        'Zi==',
        'Zr==',
        'Zm9=',
        'Zm+=',
        'Zm/=',
      ]) {
        expect(
          () => service.decodeBytes(nonCanonicalInput),
          throwsA(
            isA<Base64Exception>().having(
              (error) => error.kind,
              'kind',
              Base64ErrorKind.nonCanonicalPaddingBits,
            ),
          ),
          reason:
              'Non-zero trailing padding bits in "$nonCanonicalInput" must be rejected per RFC 4648 Section 3.5',
        );
      }

      for (final kind in Base64ErrorKind.values) {
        final exception = Base64Exception(kind, 'Error: ${kind.name}');
        expect(
          exception.toString(),
          contains(kind.name),
          reason: 'Base64Exception.toString() must format ${kind.name}',
        );
      }
    });
  });

  group('Base64Service Linear Throughput', () {
    test('encodes and decodes a 64 KiB payload in a single linear pass within budget', () {
      final payload = Uint8List.fromList(
        List<int>.generate(65536, (i) => i & 0xFF),
      );
      final stopwatch = Stopwatch()..start();
      final encoded = service.encodeBytes(payload);
      final decoded = service.decodeBytes(encoded);
      stopwatch.stop();

      expect(decoded, equals(payload));
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(250),
        reason: '64 KiB Base64 round-trip must complete in < 250 ms',
      );
    });
  });
}
