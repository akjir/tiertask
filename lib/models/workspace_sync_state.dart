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

import 'dart:convert' show Utf8Codec;
import 'dart:typed_data' show BytesBuilder, Uint8List;

import 'package:flutter/foundation.dart';

import 'task_item.dart';

/// Immutable per-workspace synchronization baseline, acknowledged generations, source digest, and pending deletion state.
@immutable
class WorkspaceSyncState {
  /// Creates a [WorkspaceSyncState].
  WorkspaceSyncState({
    this.lastSyncedLocalTdf,
    this.lastSyncedRemoteTdf,
    Map<String, DateTime> deletedLabelTimestamps = const {},
    Map<String, DateTime> deletedLocationTimestamps = const {},
    this.acknowledgedLocalGeneration = 0,
    this.acknowledgedRemoteGeneration = 0,
    this.localSourceDigest,
    this.remoteEtag,
    this.remoteLastModified,
  }) : deletedLabelTimestamps = Map<String, DateTime>.unmodifiable(
         <String, DateTime>{
           for (final entry in deletedLabelTimestamps.entries)
             entry.key: TaskItem.normalizeTimestamp(entry.value),
         },
       ),
       deletedLocationTimestamps = Map<String, DateTime>.unmodifiable(
         <String, DateTime>{
           for (final entry in deletedLocationTimestamps.entries)
             entry.key: TaskItem.normalizeTimestamp(entry.value),
         },
       );

  /// Creates an empty [WorkspaceSyncState] with default baselines and generations.
  const WorkspaceSyncState._empty()
    : lastSyncedLocalTdf = null,
      lastSyncedRemoteTdf = null,
      deletedLabelTimestamps = const <String, DateTime>{},
      deletedLocationTimestamps = const <String, DateTime>{},
      acknowledgedLocalGeneration = 0,
      acknowledgedRemoteGeneration = 0,
      localSourceDigest = null,
      remoteEtag = null,
      remoteLastModified = null;

  /// Reconstructs a [WorkspaceSyncState] from its compact `TTS\x01`, `TTS\x02`, or `TTS\x03` binary payload,
  /// returning [empty] if [bytes] is empty or malformed.
  factory WorkspaceSyncState.fromBytes(List<int> bytes) {
    if (bytes.length < 6 ||
        bytes[0] != 0x54 ||
        bytes[1] != 0x54 ||
        bytes[2] != 0x53) {
      return empty;
    }
    final version = bytes[3];
    if (version != _binaryVersionV1 &&
        version != _binaryVersionV2 &&
        version != _binaryVersionV3) {
      return empty;
    }
    final source = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    try {
      final (localTdf, afterLocal) = _readNullableString(source, 4);
      final (remoteTdf, afterRemote) = _readNullableString(source, afterLocal);
      final (deletedLabels, afterLabels) = _readDeletedEntityMap(
        source,
        afterRemote,
      );
      var cursor = afterLabels;
      var localGen = 0;
      var remoteGen = 0;
      if (version >= _binaryVersionV2) {
        if (cursor + 16 > source.length) return empty;
        localGen = _readInt64(source, cursor);
        remoteGen = _readInt64(source, cursor + 8);
        cursor += 16;
      }
      var deletedLocations = const <String, DateTime>{};
      String? localDigest;
      String? remoteEtag;
      String? remoteLastModified;
      if (version >= _binaryVersionV3) {
        (
          deletedLocations,
          localDigest,
          remoteEtag,
          remoteLastModified,
          cursor,
        ) = _readV3Payload(
          source,
          cursor,
        );
      }
      if (cursor != source.length) return empty;
      return WorkspaceSyncState(
        lastSyncedLocalTdf: localTdf,
        lastSyncedRemoteTdf: remoteTdf,
        deletedLabelTimestamps: deletedLabels,
        deletedLocationTimestamps: deletedLocations,
        acknowledgedLocalGeneration: localGen,
        acknowledgedRemoteGeneration: remoteGen,
        localSourceDigest: localDigest,
        remoteEtag: remoteEtag,
        remoteLastModified: remoteLastModified,
      );
    } on FormatException {
      return empty;
    }
  }

  /// Empty synchronization state with no baselines and no pending entity deletions.
  static const WorkspaceSyncState empty = WorkspaceSyncState._empty();

  /// Binary wire format version 1 identifier.
  static const int _binaryVersionV1 = 1;

  /// Binary wire format version 2 identifier.
  static const int _binaryVersionV2 = 2;

  /// Binary wire format version 3 identifier.
  static const int _binaryVersionV3 = 3;

  /// Strict UTF-8 codec that rejects malformed byte sequences.
  static const Utf8Codec _utf8Codec = Utf8Codec(allowMalformed: false);

  /// Last acknowledged `deleted.generation` for the local `.tdf` file.
  final int acknowledgedLocalGeneration;

  /// Last acknowledged `deleted.generation` for the remote WebDAV `.tdf` file.
  final int acknowledgedRemoteGeneration;

  /// UTC deletion timestamps (`T_del`) for labels deleted since the last full sync.
  final Map<String, DateTime> deletedLabelTimestamps;

  /// UTC deletion timestamps (`T_del`) for locations deleted since the last full sync.
  final Map<String, DateTime> deletedLocationTimestamps;

  /// Canonical `.tdf` snapshot from the last successful local file synchronization.
  final String? lastSyncedLocalTdf;

  /// Canonical `.tdf` snapshot from the last successful WebDAV synchronization.
  final String? lastSyncedRemoteTdf;

  /// SHA-256 hex digest of the local `.tdf` file from the last successful local publication.
  final String? localSourceDigest;

  /// Cached HTTP `ETag` validator header from the last successful WebDAV synchronization.
  final String? remoteEtag;

  /// Cached HTTP `Last-Modified` validator header from the last successful WebDAV synchronization.
  final String? remoteLastModified;

  /// Returns a copy of this [WorkspaceSyncState] with updated fields.
  WorkspaceSyncState copyWith({
    String? lastSyncedLocalTdf,
    bool clearLastSyncedLocalTdf = false,
    String? lastSyncedRemoteTdf,
    bool clearLastSyncedRemoteTdf = false,
    Map<String, DateTime>? deletedLabelTimestamps,
    Map<String, DateTime>? deletedLocationTimestamps,
    int? acknowledgedLocalGeneration,
    int? acknowledgedRemoteGeneration,
    String? localSourceDigest,
    bool clearLocalSourceDigest = false,
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
      deletedLabelTimestamps:
          deletedLabelTimestamps ?? this.deletedLabelTimestamps,
      deletedLocationTimestamps:
          deletedLocationTimestamps ?? this.deletedLocationTimestamps,
      acknowledgedLocalGeneration:
          acknowledgedLocalGeneration ?? this.acknowledgedLocalGeneration,
      acknowledgedRemoteGeneration:
          acknowledgedRemoteGeneration ?? this.acknowledgedRemoteGeneration,
      localSourceDigest: clearLocalSourceDigest
          ? null
          : (localSourceDigest ?? this.localSourceDigest),
      remoteEtag: clearRemoteEtag ? null : (remoteEtag ?? this.remoteEtag),
      remoteLastModified: clearRemoteLastModified
          ? null
          : (remoteLastModified ?? this.remoteLastModified),
    );
  }

  /// Encodes this [WorkspaceSyncState] into a compact `TTS\x03` binary [Uint8List].
  Uint8List toBytes() {
    final builder = BytesBuilder(copy: false)
      ..add(const <int>[0x54, 0x54, 0x53, _binaryVersionV3]);
    _writeNullableString(builder, lastSyncedLocalTdf);
    _writeNullableString(builder, lastSyncedRemoteTdf);
    _writeDeletedEntityMap(builder, deletedLabelTimestamps);
    _writeInt64(builder, acknowledgedLocalGeneration);
    _writeInt64(builder, acknowledgedRemoteGeneration);
    _writeDeletedEntityMap(builder, deletedLocationTimestamps);
    _writeNullableString(builder, localSourceDigest);
    if (remoteEtag != null || remoteLastModified != null) {
      _writeNullableString(builder, remoteEtag);
      _writeNullableString(builder, remoteLastModified);
    }
    return builder.toBytes();
  }

  /// Reads a 16-bit count-prefixed map of `(entityId, deletedAt)` entries from [source] at [offset].
  static (Map<String, DateTime>, int) _readDeletedEntityMap(
    Uint8List source,
    int offset,
  ) {
    if (offset + 2 > source.length) {
      throw const FormatException('Truncated deleted entity map count.');
    }
    final count = (source[offset] << 8) | source[offset + 1];
    var cursor = offset + 2;
    final deletedMap = <String, DateTime>{};
    for (var i = 0; i < count; i++) {
      final (entityId, dateVal, nextCursor) = _readDeletedLabelEntry(
        source,
        cursor,
      );
      deletedMap[entityId] = dateVal;
      cursor = nextCursor;
    }
    return (deletedMap, cursor);
  }

  /// Reads a single `(labelId, deletedAt, nextOffset)` entry from [source] at [offset].
  static (String, DateTime, int) _readDeletedLabelEntry(
    Uint8List source,
    int offset,
  ) {
    final (labelId, afterId) = _readNullableString(source, offset);
    if (labelId == null || labelId.isEmpty || afterId + 8 > source.length) {
      throw const FormatException('Invalid deleted label entry.');
    }
    final epochSeconds = _readInt64(source, afterId);
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      epochSeconds * 1000,
      isUtc: true,
    );
    return (labelId, TaskItem.normalizeTimestamp(timestamp), afterId + 8);
  }

  /// Reads a big-endian 64-bit integer from [source] at [offset].
  static int _readInt64(Uint8List source, int offset) {
    var value = 0;
    for (var i = 0; i < 8; i++) {
      value = (value << 8) | source[offset + i];
    }
    return value;
  }

  /// Reads a 32-bit length-prefixed nullable UTF-8 string from [source] at [offset].
  static (String?, int) _readNullableString(Uint8List source, int offset) {
    if (offset >= source.length) {
      throw const FormatException('Truncated string flag.');
    }
    final present = source[offset];
    if (present == 0) {
      return (null, offset + 1);
    }
    if (present != 1 || offset + 5 > source.length) {
      throw const FormatException('Invalid string header.');
    }
    final length =
        (source[offset + 1] << 24) |
        (source[offset + 2] << 16) |
        (source[offset + 3] << 8) |
        source[offset + 4];
    final start = offset + 5;
    final end = start + length;
    if (length < 0 || end > source.length) {
      throw const FormatException('Truncated string bytes.');
    }
    final decoded = _utf8Codec.decode(
      Uint8List.sublistView(source, start, end),
    );
    return (decoded, end);
  }

  /// Reads the `TTS\x03` location deletion map, local digest, and optional WebDAV HTTP validators from [source] at [offset].
  static (
    Map<String, DateTime> deletedLocations,
    String? localDigest,
    String? remoteEtag,
    String? remoteLastModified,
    int nextOffset,
  )
  _readV3Payload(Uint8List source, int offset) {
    final (locations, afterLocations) = _readDeletedEntityMap(source, offset);
    final (digest, afterDigest) = _readNullableString(source, afterLocations);
    if (afterDigest >= source.length) {
      return (locations, digest, null, null, afterDigest);
    }
    final (etag, afterEtag) = _readNullableString(source, afterDigest);
    final (lastModified, afterLastModified) = _readNullableString(
      source,
      afterEtag,
    );
    return (locations, digest, etag, lastModified, afterLastModified);
  }

  /// Appends a 16-bit count-prefixed map of `(entityId, deletedAt)` entries to [builder].
  static void _writeDeletedEntityMap(
    BytesBuilder builder,
    Map<String, DateTime> timestamps,
  ) {
    final entries = timestamps.entries.toList();
    final count = entries.length <= 0xFFFF ? entries.length : 0xFFFF;
    builder
      ..addByte((count >> 8) & 0xFF)
      ..addByte(count & 0xFF);
    for (var i = 0; i < count; i++) {
      _writeDeletedLabelEntry(builder, entries[i].key, entries[i].value);
    }
  }

  /// Appends a single `(labelId, deletedAt)` entry to [builder].
  static void _writeDeletedLabelEntry(
    BytesBuilder builder,
    String labelId,
    DateTime deletedAt,
  ) {
    _writeNullableString(builder, labelId);
    final epochSeconds =
        TaskItem.normalizeTimestamp(deletedAt).millisecondsSinceEpoch ~/ 1000;
    _writeInt64(builder, epochSeconds);
  }

  /// Appends a big-endian 64-bit integer [value] to [builder].
  static void _writeInt64(BytesBuilder builder, int value) {
    for (var shift = 56; shift >= 0; shift -= 8) {
      builder.addByte((value >> shift) & 0xFF);
    }
  }

  /// Appends a nullable UTF-8 [value] to [builder] with a 1-byte presence flag and 32-bit length.
  static void _writeNullableString(BytesBuilder builder, String? value) {
    if (value == null) {
      builder.addByte(0);
      return;
    }
    final encoded = _utf8Codec.encode(value);
    final len = encoded.length;
    builder
      ..addByte(1)
      ..addByte((len >> 24) & 0xFF)
      ..addByte((len >> 16) & 0xFF)
      ..addByte((len >> 8) & 0xFF)
      ..addByte(len & 0xFF)
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
        other.remoteEtag == remoteEtag &&
        other.remoteLastModified == remoteLastModified &&
        mapEquals(other.deletedLabelTimestamps, deletedLabelTimestamps) &&
        mapEquals(other.deletedLocationTimestamps, deletedLocationTimestamps);
  }

  @override
  int get hashCode => Object.hash(
    lastSyncedLocalTdf,
    lastSyncedRemoteTdf,
    acknowledgedLocalGeneration,
    acknowledgedRemoteGeneration,
    localSourceDigest,
    remoteEtag,
    remoteLastModified,
    Object.hashAllUnordered(
      deletedLabelTimestamps.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
    Object.hashAllUnordered(
      deletedLocationTimestamps.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
  );
}
