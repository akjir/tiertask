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
  });
}
