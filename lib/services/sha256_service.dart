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

  /// Standard FIPS 180-4 SHA-256 32-bit round constants stored in an unboxed [Uint32List].
  static final Uint32List _roundConstants = Uint32List.fromList(const <int>[
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
  ]);

  /// Computes the 32-byte FIPS 180-4 SHA-256 binary digest of [inputBytes] without allocating a full padded copy.
  static Uint8List hashBytes(List<int> inputBytes) {
    final state = Uint32List(8)
      ..[0] = 0x6a09e667
      ..[1] = 0xbb67ae85
      ..[2] = 0x3c6ef372
      ..[3] = 0xa54ff53a
      ..[4] = 0x510e527f
      ..[5] = 0x9b05688c
      ..[6] = 0x1f83d9ab
      ..[7] = 0x5be0cd19;
    final schedule = Uint32List(64);
    final fullBlocksBytes = inputBytes.length & ~63;
    _compressFullInputBlocks(inputBytes, fullBlocksBytes, state, schedule);
    _compressTailBlocks(inputBytes, fullBlocksBytes, state, schedule);

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
    Uint32List state,
    Uint32List schedule,
  ) {
    for (var i = 0; i < 16; i++) {
      schedule[i] = view.getUint32(blockOffset + i * 4);
    }
    for (var i = 16; i < 64; i++) {
      final prev15 = schedule[i - 15];
      final prev2 = schedule[i - 2];
      final sigma0 =
          (((prev15 >>> 7) | (prev15 << 25)) ^
              ((prev15 >>> 18) | (prev15 << 14)) ^
              (prev15 >>> 3)) &
          0xFFFFFFFF;
      final sigma1 =
          (((prev2 >>> 17) | (prev2 << 15)) ^
              ((prev2 >>> 19) | (prev2 << 13)) ^
              (prev2 >>> 10)) &
          0xFFFFFFFF;
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
      final sum1 =
          (((e >>> 6) | (e << 26)) ^
              ((e >>> 11) | (e << 21)) ^
              ((e >>> 25) | (e << 7))) &
          0xFFFFFFFF;
      final choice = (e & f) ^ ((~e) & g);
      final temp1 =
          (h + sum1 + choice + _roundConstants[i] + schedule[i]) & 0xFFFFFFFF;
      final sum0 =
          (((a >>> 2) | (a << 30)) ^
              ((a >>> 13) | (a << 19)) ^
              ((a >>> 22) | (a << 10))) &
          0xFFFFFFFF;
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

  /// Streams all full 64-byte blocks from [inputBytes] up to [fullBlocksBytes] into [state].
  static void _compressFullInputBlocks(
    List<int> inputBytes,
    int fullBlocksBytes,
    Uint32List state,
    Uint32List schedule,
  ) {
    if (fullBlocksBytes == 0) {
      return;
    }
    if (inputBytes is Uint8List) {
      final view = ByteData.sublistView(inputBytes);
      for (var offset = 0; offset < fullBlocksBytes; offset += 64) {
        _compressBlock(view, offset, state, schedule);
      }
      return;
    }
    final scratch = Uint8List(64);
    final scratchView = ByteData.sublistView(scratch);
    for (var offset = 0; offset < fullBlocksBytes; offset += 64) {
      scratch.setRange(0, 64, inputBytes, offset);
      _compressBlock(scratchView, 0, state, schedule);
    }
  }

  /// Pads and compresses the remaining trailing bytes of [inputBytes] starting at [fullBlocksBytes] using a 128-byte tail buffer.
  static void _compressTailBlocks(
    List<int> inputBytes,
    int fullBlocksBytes,
    Uint32List state,
    Uint32List schedule,
  ) {
    final remaining = inputBytes.length - fullBlocksBytes;
    final tailLength = remaining < 56 ? 64 : 128;
    final tail = Uint8List(128);
    if (remaining > 0) {
      tail.setRange(0, remaining, inputBytes, fullBlocksBytes);
    }
    tail[remaining] = 0x80;
    final bitLength = inputBytes.length * 8;
    final tailView = ByteData.sublistView(tail);
    tailView.setUint32(tailLength - 8, (bitLength ~/ 0x100000000) & 0xFFFFFFFF);
    tailView.setUint32(tailLength - 4, bitLength & 0xFFFFFFFF);
    for (var offset = 0; offset < tailLength; offset += 64) {
      _compressBlock(tailView, offset, state, schedule);
    }
  }
}
