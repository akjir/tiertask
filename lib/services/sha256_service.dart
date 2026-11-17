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

import 'dart:typed_data';

/// Pure Dart FIPS 180-4 SHA-256 cryptographic digest service (`TDF-SER-005`, `TDF-MERGE-001`, `TDF-PUB-002`).
abstract final class Sha256Service {
  /// Lowercase hexadecimal digit table (`0-9`, `a-f`).
  static const String _hexDigits = '0123456789abcdef';

  /// Standard FIPS 180-4 SHA-256 32-bit round constants.
  static const List<int> _roundConstants = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  /// Computes the 32-byte FIPS 180-4 SHA-256 binary digest of [inputBytes].
  static Uint8List hashBytes(List<int> inputBytes) {
    final bitLength = inputBytes.length * 8;
    final paddedLength = ((inputBytes.length + 9 + 63) ~/ 64) * 64;
    final padded = Uint8List(paddedLength);
    padded.setRange(0, inputBytes.length, inputBytes);
    padded[inputBytes.length] = 0x80;

    final view = ByteData.sublistView(padded);
    view.setUint32(paddedLength - 8, (bitLength ~/ 0x100000000) & 0xFFFFFFFF);
    view.setUint32(paddedLength - 4, bitLength & 0xFFFFFFFF);

    final state = <int>[
      0x6a09e667,
      0xbb67ae85,
      0x3c6ef372,
      0xa54ff53a,
      0x510e527f,
      0x9b05688c,
      0x1f83d9ab,
      0x5be0cd19,
    ];
    final schedule = Uint32List(64);
    for (var offset = 0; offset < paddedLength; offset += 64) {
      _compressBlock(view, offset, state, schedule);
    }

    final digest = Uint8List(32);
    final digestView = ByteData.sublistView(digest);
    for (var i = 0; i < 8; i++) {
      digestView.setUint32(i * 4, state[i]);
    }
    return digest;
  }

  /// Computes the 64-character lowercase hexadecimal SHA-256 digest of [inputBytes].
  static String hashHex(List<int> inputBytes) {
    final digest = hashBytes(inputBytes);
    final codeUnits = Uint8List(64);
    for (var i = 0; i < 32; i++) {
      final byte = digest[i];
      codeUnits[i * 2] = _hexDigits.codeUnitAt((byte >> 4) & 0x0F);
      codeUnits[i * 2 + 1] = _hexDigits.codeUnitAt(byte & 0x0F);
    }
    return String.fromCharCodes(codeUnits);
  }

  /// Compresses one 64-byte SHA-256 block into [state] using message [schedule].
  static void _compressBlock(
    ByteData view,
    int blockOffset,
    List<int> state,
    Uint32List schedule,
  ) {
    for (var i = 0; i < 16; i++) {
      schedule[i] = view.getUint32(blockOffset + i * 4);
    }
    for (var i = 16; i < 64; i++) {
      final prev15 = schedule[i - 15];
      final prev2 = schedule[i - 2];
      final sigma0 = _rotr32(prev15, 7) ^ _rotr32(prev15, 18) ^ (prev15 >>> 3);
      final sigma1 = _rotr32(prev2, 17) ^ _rotr32(prev2, 19) ^ (prev2 >>> 10);
      schedule[i] =
          (schedule[i - 16] + sigma0 + schedule[i - 7] + sigma1) & 0xFFFFFFFF;
    }

    var a = state[0];
    var b = state[1];
    var c = state[2];
    var d = state[3];
    var e = state[4];
    var f = state[5];
    var g = state[6];
    var h = state[7];

    for (var i = 0; i < 64; i++) {
      final sum1 = _rotr32(e, 6) ^ _rotr32(e, 11) ^ _rotr32(e, 25);
      final choice = (e & f) ^ ((~e & 0xFFFFFFFF) & g);
      final temp1 =
          (h + sum1 + choice + _roundConstants[i] + schedule[i]) & 0xFFFFFFFF;
      final sum0 = _rotr32(a, 2) ^ _rotr32(a, 13) ^ _rotr32(a, 22);
      final majority = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (sum0 + majority) & 0xFFFFFFFF;

      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xFFFFFFFF;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xFFFFFFFF;
    }

    state[0] = (state[0] + a) & 0xFFFFFFFF;
    state[1] = (state[1] + b) & 0xFFFFFFFF;
    state[2] = (state[2] + c) & 0xFFFFFFFF;
    state[3] = (state[3] + d) & 0xFFFFFFFF;
    state[4] = (state[4] + e) & 0xFFFFFFFF;
    state[5] = (state[5] + f) & 0xFFFFFFFF;
    state[6] = (state[6] + g) & 0xFFFFFFFF;
    state[7] = (state[7] + h) & 0xFFFFFFFF;
  }

  /// Right-rotates an unsigned 32-bit integer [value] by [shift] bits.
  static int _rotr32(int value, int shift) {
    final masked = value & 0xFFFFFFFF;
    return ((masked >>> shift) | (masked << (32 - shift))) & 0xFFFFFFFF;
  }
}
