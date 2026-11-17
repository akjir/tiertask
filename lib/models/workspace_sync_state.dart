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
import 'dart:typed_data' show ByteData, BytesBuilder;

import 'package:flutter/foundation.dart';

import 'tdf_error.dart';

/// Immutable `TTS\x04` per-workspace synchronization baseline, acknowledged
/// generations, raw source digests, and HTTP conditional request validators.
@immutable
class WorkspaceSyncState {
  const WorkspaceSyncState._({
    this.lastSyncedLocalTdf,
    this.lastSyncedRemoteTdf,
    this.acknowledgedLocalGeneration,
    this.acknowledgedRemoteGeneration,
    this.localSourceDigest,
    this.remoteSourceDigest,
    this.remoteEtag,
    this.remoteLastModified,
  });

  /// Creates a validated [WorkspaceSyncState], atomically clearing any target
  /// whose canonical `tdf 0.8.0\n` baseline, acknowledged generation, or
  /// 64-character lowercase SHA-256 source digest is missing or invalid.
  factory WorkspaceSyncState({
    String? lastSyncedLocalTdf,
    String? lastSyncedRemoteTdf,
    int? acknowledgedLocalGeneration,
    int? acknowledgedRemoteGeneration,
    String? localSourceDigest,
    String? remoteSourceDigest,
    String? remoteEtag,
    String? remoteLastModified,
  }) {
    final validLocal = _isValidTargetBaseline(
      canonicalTdf: lastSyncedLocalTdf,
      acknowledgedGeneration: acknowledgedLocalGeneration,
      sourceDigest: localSourceDigest,
    );
    final validRemote = _isValidTargetBaseline(
      canonicalTdf: lastSyncedRemoteTdf,
      acknowledgedGeneration: acknowledgedRemoteGeneration,
      sourceDigest: remoteSourceDigest,
    );
    return WorkspaceSyncState._(
      lastSyncedLocalTdf: validLocal ? lastSyncedLocalTdf : null,
      lastSyncedRemoteTdf: validRemote ? lastSyncedRemoteTdf : null,
      acknowledgedLocalGeneration: validLocal
          ? acknowledgedLocalGeneration
          : null,
      acknowledgedRemoteGeneration: validRemote
          ? acknowledgedRemoteGeneration
          : null,
      localSourceDigest: validLocal ? localSourceDigest : null,
      remoteSourceDigest: validRemote ? remoteSourceDigest : null,
      remoteEtag: validRemote ? remoteEtag : null,
      remoteLastModified: validRemote ? remoteLastModified : null,
    );
  }

  /// Reconstructs a [WorkspaceSyncState] from its compact `TTS\x04` binary
  /// payload, returning [empty] if [bytes] is truncated, malformed, or uses any
  /// wire format version other than `4` (`TDF-MERGE-001`).
  factory WorkspaceSyncState.fromBytes(List<int> bytes) {
    if (!_hasValidHeader(bytes)) {
      return empty;
    }
    var offset = 4;
    final (localTdf, next1, ok1) = _readNullableString(bytes, offset);
    if (!ok1) return empty;
    offset = next1;

    final (remoteTdf, next2, ok2) = _readNullableString(bytes, offset);
    if (!ok2) return empty;
    offset = next2;

    final (localGeneration, next3, ok3) = _readNullableInt64(bytes, offset);
    if (!ok3) return empty;
    offset = next3;

    final (remoteGeneration, next4, ok4) = _readNullableInt64(bytes, offset);
    if (!ok4) return empty;
    offset = next4;

    final (localDigest, next5, ok5) = _readNullableString(bytes, offset);
    if (!ok5) return empty;
    offset = next5;

    final (remoteDigest, next6, ok6) = _readNullableString(bytes, offset);
    if (!ok6) return empty;
    offset = next6;

    final (etag, next7, ok7) = _readNullableString(bytes, offset);
    if (!ok7) return empty;
    offset = next7;

    final (lastModified, next8, ok8) = _readNullableString(bytes, offset);
    if (!ok8 || next8 != bytes.length) {
      return empty;
    }

    return WorkspaceSyncState(
      lastSyncedLocalTdf: localTdf,
      lastSyncedRemoteTdf: remoteTdf,
      acknowledgedLocalGeneration: localGeneration,
      acknowledgedRemoteGeneration: remoteGeneration,
      localSourceDigest: localDigest,
      remoteSourceDigest: remoteDigest,
      remoteEtag: etag,
      remoteLastModified: lastModified,
    );
  }

  /// Empty synchronization state with no baselines, generations, or validators.
  static const WorkspaceSyncState empty = WorkspaceSyncState._();

  static const String _canonicalHeaderPrefix = 'tdf 0.8.0\n';
  static const int _formatVersion = 0x04;
  static const int _magicByte0 = 0x54;
  static const int _magicByte1 = 0x54;
  static const int _magicByte2 = 0x53;
  static const int _maxStringByteLength = 16777216;
  static const int _sha256HexLength = 64;
  static const Utf8Codec _utf8Codec = Utf8Codec();

  /// Last acknowledged `deleted.generation` counter for the local `.tdf` file.
  final int? acknowledgedLocalGeneration;

  /// Last acknowledged `deleted.generation` counter for the remote WebDAV `.tdf` file.
  final int? acknowledgedRemoteGeneration;

  /// Canonical `tdf 0.8.0` baseline snapshot last synchronized with the local `.tdf` file.
  final String? lastSyncedLocalTdf;

  /// Canonical `tdf 0.8.0` baseline snapshot last synchronized with the remote WebDAV `.tdf` file.
  final String? lastSyncedRemoteTdf;

  /// Raw 64-character lowercase SHA-256 hex digest of the local `.tdf` byte stream.
  final String? localSourceDigest;

  /// HTTP `ETag` header observed on the last synchronized remote WebDAV `.tdf` response.
  final String? remoteEtag;

  /// HTTP `Last-Modified` header observed on the last synchronized remote WebDAV `.tdf` response.
  final String? remoteLastModified;

  /// Raw 64-character lowercase SHA-256 hex digest of the remote WebDAV `.tdf` byte stream.
  final String? remoteSourceDigest;

  /// Creates an updated [WorkspaceSyncState] preserving unspecified fields and
  /// enforcing atomic per-target validation.
  WorkspaceSyncState copyWith({
    String? lastSyncedLocalTdf,
    bool clearLastSyncedLocalTdf = false,
    String? lastSyncedRemoteTdf,
    bool clearLastSyncedRemoteTdf = false,
    int? acknowledgedLocalGeneration,
    bool clearAcknowledgedLocalGeneration = false,
    int? acknowledgedRemoteGeneration,
    bool clearAcknowledgedRemoteGeneration = false,
    String? localSourceDigest,
    bool clearLocalSourceDigest = false,
    String? remoteSourceDigest,
    bool clearRemoteSourceDigest = false,
    String? remoteEtag,
    bool clearRemoteEtag = false,
    String? remoteLastModified,
    bool clearRemoteLastModified = false,
  }) {
    return WorkspaceSyncState(
      lastSyncedLocalTdf: clearLastSyncedLocalTdf
          ? null
          : (lastSyncedLocalTdf ?? this.lastSyncedLocalTdf),
      lastSyncedRemoteTdf: clearLastSyncedRemoteTdf
          ? null
          : (lastSyncedRemoteTdf ?? this.lastSyncedRemoteTdf),
      acknowledgedLocalGeneration: clearAcknowledgedLocalGeneration
          ? null
          : (acknowledgedLocalGeneration ?? this.acknowledgedLocalGeneration),
      acknowledgedRemoteGeneration: clearAcknowledgedRemoteGeneration
          ? null
          : (acknowledgedRemoteGeneration ?? this.acknowledgedRemoteGeneration),
      localSourceDigest: clearLocalSourceDigest
          ? null
          : (localSourceDigest ?? this.localSourceDigest),
      remoteSourceDigest: clearRemoteSourceDigest
          ? null
          : (remoteSourceDigest ?? this.remoteSourceDigest),
      remoteEtag: clearRemoteEtag ? null : (remoteEtag ?? this.remoteEtag),
      remoteLastModified: clearRemoteLastModified
          ? null
          : (remoteLastModified ?? this.remoteLastModified),
    );
  }

  /// Serializes this [WorkspaceSyncState] into its compact `TTS\x04` binary wire representation.
  Uint8List toBytes() {
    final builder = BytesBuilder(copy: false)
      ..addByte(_magicByte0)
      ..addByte(_magicByte1)
      ..addByte(_magicByte2)
      ..addByte(_formatVersion);
    _writeNullableString(builder, lastSyncedLocalTdf);
    _writeNullableString(builder, lastSyncedRemoteTdf);
    _writeNullableInt64(builder, acknowledgedLocalGeneration);
    _writeNullableInt64(builder, acknowledgedRemoteGeneration);
    _writeNullableString(builder, localSourceDigest);
    _writeNullableString(builder, remoteSourceDigest);
    _writeNullableString(builder, remoteEtag);
    _writeNullableString(builder, remoteLastModified);
    return builder.toBytes();
  }

  /// Returns `true` when [bytes] starts with the 4-byte `TTS\x04` header.
  static bool _hasValidHeader(List<int> bytes) =>
      bytes.length >= 4 &&
      bytes[0] == _magicByte0 &&
      bytes[1] == _magicByte1 &&
      bytes[2] == _magicByte2 &&
      bytes[3] == _formatVersion;

  /// Returns `true` when [codeUnit] is a lowercase ASCII hexadecimal digit (`0-9`, `a-f`).
  static bool _isLowercaseHexCodeUnit(int codeUnit) =>
      (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x61 && codeUnit <= 0x66);

  /// Returns `true` when [digest] is a 64-character lowercase SHA-256 hex string.
  static bool _isValidSha256Hex(String? digest) {
    if (digest == null || digest.length != _sha256HexLength) {
      return false;
    }
    for (var i = 0; i < _sha256HexLength; i++) {
      if (!_isLowercaseHexCodeUnit(digest.codeUnitAt(i))) {
        return false;
      }
    }
    return true;
  }

  /// Returns `true` when a target's canonical baseline, generation, and SHA-256 digest are all present and valid.
  static bool _isValidTargetBaseline({
    required String? canonicalTdf,
    required int? acknowledgedGeneration,
    required String? sourceDigest,
  }) {
    if (canonicalTdf == null ||
        !canonicalTdf.startsWith(_canonicalHeaderPrefix)) {
      return false;
    }
    if (acknowledgedGeneration == null ||
        acknowledgedGeneration < 0 ||
        acknowledgedGeneration > maxTdfSyncGeneration) {
      return false;
    }
    return _isValidSha256Hex(sourceDigest);
  }

  /// Reads a 1-byte presence flag and optional big-endian signed 64-bit integer from [bytes] at [offset].
  static (int?, int, bool) _readNullableInt64(List<int> bytes, int offset) {
    if (offset >= bytes.length) {
      return (null, offset, false);
    }
    final presence = bytes[offset];
    if (presence == 0) {
      return (null, offset + 1, true);
    }
    if (presence != 1 || offset + 9 > bytes.length) {
      return (null, offset, false);
    }
    final slice = Uint8List.fromList(bytes.sublist(offset + 1, offset + 9));
    final value = ByteData.sublistView(slice).getInt64(0);
    return (value, offset + 9, true);
  }

  /// Reads a 1-byte presence flag and optional length-prefixed UTF-8 string from [bytes] at [offset].
  static (String?, int, bool) _readNullableString(List<int> bytes, int offset) {
    if (offset >= bytes.length) {
      return (null, offset, false);
    }
    final presence = bytes[offset];
    if (presence == 0) {
      return (null, offset + 1, true);
    }
    if (presence != 1 || offset + 5 > bytes.length) {
      return (null, offset, false);
    }
    final lengthSlice = Uint8List.fromList(
      bytes.sublist(offset + 1, offset + 5),
    );
    final byteLength = ByteData.sublistView(lengthSlice).getUint32(0);
    final endOffset = offset + 5 + byteLength;
    if (byteLength > _maxStringByteLength || endOffset > bytes.length) {
      return (null, offset, false);
    }
    try {
      final decoded = _utf8Codec.decode(bytes.sublist(offset + 5, endOffset));
      return (decoded, endOffset, true);
    } on FormatException {
      return (null, offset, false);
    }
  }

  /// Appends a nullable big-endian signed 64-bit integer [value] to [builder].
  static void _writeNullableInt64(BytesBuilder builder, int? value) {
    if (value == null) {
      builder.addByte(0);
      return;
    }
    final buffer = ByteData(8)..setInt64(0, value);
    builder
      ..addByte(1)
      ..add(buffer.buffer.asUint8List());
  }

  /// Appends a nullable length-prefixed UTF-8 [value] to [builder].
  static void _writeNullableString(BytesBuilder builder, String? value) {
    if (value == null) {
      builder.addByte(0);
      return;
    }
    final encoded = _utf8Codec.encode(value);
    final lengthBuffer = ByteData(4)..setUint32(0, encoded.length);
    builder
      ..addByte(1)
      ..add(lengthBuffer.buffer.asUint8List())
      ..add(encoded);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WorkspaceSyncState &&
        other.lastSyncedLocalTdf == lastSyncedLocalTdf &&
        other.lastSyncedRemoteTdf == lastSyncedRemoteTdf &&
        other.acknowledgedLocalGeneration == acknowledgedLocalGeneration &&
        other.acknowledgedRemoteGeneration == acknowledgedRemoteGeneration &&
        other.localSourceDigest == localSourceDigest &&
        other.remoteSourceDigest == remoteSourceDigest &&
        other.remoteEtag == remoteEtag &&
        other.remoteLastModified == remoteLastModified;
  }

  @override
  int get hashCode => Object.hash(
    lastSyncedLocalTdf,
    lastSyncedRemoteTdf,
    acknowledgedLocalGeneration,
    acknowledgedRemoteGeneration,
    localSourceDigest,
    remoteSourceDigest,
    remoteEtag,
    remoteLastModified,
  );
}
