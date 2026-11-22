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
import 'package:tiertask/services/sha256_service.dart';

void main() {
  group('Sha256Service FIPS 180-4 & TDF 0.8.0 Digest Vectors', () {
    test('computes exact FIPS 180-4 SHA-256 digests across empty, single-block, two-block, and 1MB inputs', () {
      expect(
        Sha256Service.hashHex(const <int>[]),
        equals(
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        ),
        reason: 'FIPS 180-4 empty message digest',
      );
      final emptyBytes = Sha256Service.hashBytes(const <int>[]);
      expect(emptyBytes, isA<Uint8List>());
      expect(emptyBytes.length, equals(32));
      expect(emptyBytes.first, equals(0xe3));
      expect(emptyBytes.last, equals(0x55));

      expect(
        Sha256Service.hashHex(utf8.encode('abc')),
        equals(
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        ),
        reason: 'FIPS 180-4 single-block "abc" digest',
      );

      expect(
        Sha256Service.hashHex(
          utf8.encode(
            'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
          ),
        ),
        equals(
          '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
        ),
        reason: 'FIPS 180-4 448-bit two-block padding boundary digest',
      );

      // Exact 55-byte vs 56-byte padding boundary:
      final bytes55 = List<int>.filled(55, 0x61);
      final bytes56 = List<int>.filled(56, 0x61);
      expect(Sha256Service.hashHex(bytes55).length, equals(64));
      expect(Sha256Service.hashHex(bytes56).length, equals(64));
      expect(
        Sha256Service.hashHex(bytes55),
        isNot(equals(Sha256Service.hashHex(bytes56))),
      );

      // Million 'a's NIST vector:
      final millionA = Uint8List(1000000)..fillRange(0, 1000000, 0x61);
      expect(
        Sha256Service.hashHex(millionA),
        equals(
          'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
        ),
      );
    });

    test('matches TDF 0.8.0 Section 7.5 Vector 1 and Vector 2 canonical SHA-256 digests', () {
      expect(
        Sha256Service.hashHex(utf8.encode('tdf 0.8.0\n')),
        equals(
          '7904b7a8e8cd221287ac91710477af38bbb7beb14dea75e2c827dfa2bfd2097a',
        ),
        reason: 'TDF-SER-005 Vector 1 (10 UTF-8 bytes)',
      );

      const vector2 =
          'tdf 0.8.0\n\ntask AAAAAAAAAA {\n    name    "A"\n    created 2026-11-16 00:00\n}\n';
      expect(utf8.encode(vector2).length, equals(76));
      expect(
        Sha256Service.hashHex(utf8.encode(vector2)),
        equals(
          '3211d46b392b7b1efbf53cf07a0c0c6131f987a4b17dba9a733b9971108f7090',
        ),
        reason: 'TDF-SER-005 Vector 2 (76 UTF-8 bytes)',
      );
    });

    test('matches exact streaming block boundaries for both Uint8List and non-typed List<int> inputs', () {
      const boundaryVectors = <({int length, String expectedHex})>[
        (
          length: 55,
          expectedHex: '9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318',
        ),
        (
          length: 56,
          expectedHex: 'b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a',
        ),
        (
          length: 63,
          expectedHex: '7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34',
        ),
        (
          length: 64,
          expectedHex: 'ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb',
        ),
        (
          length: 65,
          expectedHex: '635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0',
        ),
        (
          length: 119,
          expectedHex: '31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb',
        ),
        (
          length: 120,
          expectedHex: '2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c',
        ),
        (
          length: 127,
          expectedHex: 'c57e9278af78fa3cab38667bef4ce29d783787a2f731d4e12200270f0c32320a',
        ),
        (
          length: 128,
          expectedHex: '6836cf13bac400e9105071cd6af47084dfacad4e5e302c94bfed24e013afb73e',
        ),
        (
          length: 129,
          expectedHex: 'c12cb024a2e5551cca0e08fce8f1c5e314555cc3fef6329ee994a3db752166ae',
        ),
      ];
      for (final vector in boundaryVectors) {
        final typedInput = Uint8List(vector.length)
          ..fillRange(0, vector.length, 0x61);
        final listInput = List<int>.filled(vector.length, 0x61);
        final typedDigest = Sha256Service.hashHex(typedInput);
        final listDigest = Sha256Service.hashHex(listInput);
        expect(
          typedDigest,
          equals(listDigest),
          reason:
              'Uint8List and List<int> must hash identically at length ${vector.length}',
        );
        expect(
          typedDigest,
          equals(vector.expectedHex),
          reason:
              'SHA-256 streaming digest mismatch at ${vector.length} "a" bytes',
        );
      }
    });
  });
}
