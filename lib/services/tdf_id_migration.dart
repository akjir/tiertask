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

import 'package:flutter/foundation.dart';

import '../models/tdf_metadata.dart';
import '../models/tdf_sync_metadata.dart';
import 'app_logger.dart';

/// Deterministic SHA-256 and Base62 identifier migration service per `TDF_SPEC.md` Section 10.4.
abstract final class TdfIdMigration {
  /// Maximum collision retry counter (`255`, giving `256` total attempts `0..255`).
  static const int maxCounter = 255;

  /// Base62 alphabet (`0-9`, `A-Z`, `a-z`) in ascending ASCII order.
  static const String _base62Alphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

  /// Base62 radix (`62`) as a [BigInt].
  static final BigInt _base62Radix = BigInt.from(62);

  /// Base62 modulus $62^{10} = 839299365868340224$.
  static final BigInt _modulus = BigInt.parse('839299365868340224');

  /// Standard FIPS 180-4 SHA-256 round constants.
  static const List<int> _sha256K = <int>[
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

  /// Assigns a unique 10-character Base62 ID for a legacy inline location [canonicalTuple] (`<lat>:<lon>:<radius>`), updating [usedIds].
  static String assignLocationId({
    required String canonicalTuple,
    required Set<String> usedIds,
  }) => _assignUniqueId(
    namespace: 'location',
    sourceId: canonicalTuple,
    usedIds: usedIds,
  );

  /// Builds a collision-free [TdfIdMigrationMap] for all non-canonical label and task IDs
  /// in a legacy document per `TDF_SPEC.md` Section 10.4.2.
  ///
  /// Throws [TdfContextException] (`MigrationIdentifierCollision`) if all 256 counters collide.
  static TdfIdMigrationMap buildMigrationMap({
    required Set<String> existingCanonicalIds,
    required Set<String> nonCanonicalLabelIds,
    required Set<String> nonCanonicalTaskIds,
  }) {
    final usedIds = <String>{...existingCanonicalIds};
    final sortedLabels = nonCanonicalLabelIds.toList()..sort();
    final sortedTasks = nonCanonicalTaskIds.toList()..sort();
    final labelMap = <String, String>{};
    final taskMap = <String, String>{};

    for (final sourceId in sortedLabels) {
      labelMap[sourceId] = _assignUniqueId(
        namespace: 'label',
        sourceId: sourceId,
        usedIds: usedIds,
      );
    }
    for (final sourceId in sortedTasks) {
      taskMap[sourceId] = _assignUniqueId(
        namespace: 'task',
        sourceId: sourceId,
        usedIds: usedIds,
      );
    }

    if (labelMap.isNotEmpty || taskMap.isNotEmpty) {
      AppLogger.info(
        LogTag.tdf,
        'Migrated non-canonical TDF IDs labels=${labelMap.length} tasks=${taskMap.length}',
      );
    }
    return TdfIdMigrationMap(labelIds: labelMap, taskIds: taskMap);
  }

  /// Derives the 10-character Base62 candidate ID for (`namespace`, `sourceId`, `counter`)
  /// per `TDF_SPEC.md` Section 10.4.1.
  static String deriveCandidateId({
    required String namespace,
    required String sourceId,
    required int counter,
  }) {
    final message = 'TDF-ID-MIGRATION-1\n$namespace\n$sourceId\n$counter';
    final digest = _sha256Bytes(utf8.encode(message));
    var hashValue = BigInt.zero;
    for (final byte in digest) {
      hashValue = (hashValue << 8) | BigInt.from(byte);
    }
    var value = hashValue % _modulus;
    final digits = List<int>.filled(tdfEntityIdLength, 0x30);
    for (var i = tdfEntityIdLength - 1; i >= 0; i--) {
      final remainder = (value % _base62Radix).toInt();
      value = value ~/ _base62Radix;
      digits[i] = _base62Alphabet.codeUnitAt(remainder);
    }
    return String.fromCharCodes(digits);
  }

  /// Computes the 64-character lowercase hexadecimal SHA-256 digest of [inputBytes] (`spec/TDF_SPEC_0.6.0.md` Section 6.7.2).
  static String sha256Hex(List<int> inputBytes) {
    const hexDigits = '0123456789abcdef';
    final digest = _sha256Bytes(inputBytes);
    final buffer = StringBuffer();
    for (final byte in digest) {
      buffer
        ..write(hexDigits[(byte >> 4) & 0x0F])
        ..write(hexDigits[byte & 0x0F]);
    }
    return buffer.toString();
  }

  /// Selects the first unused candidate ID across counters `0..255` and adds it to [usedIds].
  static String _assignUniqueId({
    required String namespace,
    required String sourceId,
    required Set<String> usedIds,
  }) {
    for (var counter = 0; counter <= maxCounter; counter++) {
      final candidate = deriveCandidateId(
        namespace: namespace,
        sourceId: sourceId,
        counter: counter,
      );
      if (usedIds.add(candidate)) {
        return candidate;
      }
    }
    AppLogger.error(
      LogTag.tdf,
      'MigrationIdentifierCollision namespace=$namespace sourceId=$sourceId',
    );
    throw TdfContextException(
      kind: TdfContextOutcomeKind.migrationIdentifierCollision,
      entityId: sourceId,
      message:
          'Exhausted counters 0..255 while migrating $namespace identifier "$sourceId".',
    );
  }

  /// Compresses one 64-byte SHA-256 block into [state] using scratch schedule [w].
  static void _compressSha256Block(
    ByteData view,
    int blockOffset,
    List<int> state,
    Uint32List w,
  ) {
    for (var i = 0; i < 16; i++) {
      w[i] = view.getUint32(blockOffset + i * 4);
    }
    for (var i = 16; i < 64; i++) {
      final s0 =
          _rotr32(w[i - 15], 7) ^ _rotr32(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      final s1 =
          _rotr32(w[i - 2], 17) ^ _rotr32(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF;
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
      final s1 = _rotr32(e, 6) ^ _rotr32(e, 11) ^ _rotr32(e, 25);
      final ch = (e & f) ^ ((~e & 0xFFFFFFFF) & g);
      final temp1 = (h + s1 + ch + _sha256K[i] + w[i]) & 0xFFFFFFFF;
      final s0 = _rotr32(a, 2) ^ _rotr32(a, 13) ^ _rotr32(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0 + maj) & 0xFFFFFFFF;

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

  /// Right-rotates a 32-bit unsigned integer [value] by [shift] bits.
  static int _rotr32(int value, int shift) {
    final masked = value & 0xFFFFFFFF;
    return ((masked >>> shift) | (masked << (32 - shift))) & 0xFFFFFFFF;
  }

  /// Computes the 32-byte FIPS 180-4 SHA-256 digest of [inputBytes].
  static Uint8List _sha256Bytes(List<int> inputBytes) {
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
    final w = Uint32List(64);
    for (var offset = 0; offset < paddedLength; offset += 64) {
      _compressSha256Block(view, offset, state, w);
    }

    final digest = Uint8List(32);
    final digestView = ByteData.sublistView(digest);
    for (var i = 0; i < 8; i++) {
      digestView.setUint32(i * 4, state[i]);
    }
    return digest;
  }
}

/// Immutable mapping of non-canonical label and task identifiers to 10-character Base62 IDs.
@immutable
class TdfIdMigrationMap {
  /// Creates a [TdfIdMigrationMap].
  TdfIdMigrationMap({
    required Map<String, String> labelIds,
    required Map<String, String> taskIds,
  }) : labelIds = Map<String, String>.unmodifiable(labelIds),
       taskIds = Map<String, String>.unmodifiable(taskIds);

  /// Mapping from non-canonical label IDs to canonical 10-character Base62 IDs.
  final Map<String, String> labelIds;

  /// Mapping from non-canonical task IDs to canonical 10-character Base62 IDs.
  final Map<String, String> taskIds;

  /// Resolves [rawLabelId] to its canonical 10-character Base62 ID.
  String resolveLabelId(String rawLabelId) =>
      labelIds[rawLabelId] ?? rawLabelId;

  /// Resolves [rawTaskId] to its canonical 10-character Base62 ID.
  String resolveTaskId(String rawTaskId) => taskIds[rawTaskId] ?? rawTaskId;
}
