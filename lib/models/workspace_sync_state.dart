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

/// Immutable per-workspace synchronization baseline, acknowledged generations, and label deletion state.
@immutable
class WorkspaceSyncState {
  /// Creates a [WorkspaceSyncState].
  WorkspaceSyncState({
    this.lastSyncedLocalTdf,
    this.lastSyncedRemoteTdf,
    Map<String, DateTime> deletedLabelTimestamps = const {},
    this.acknowledgedLocalGeneration = 0,
    this.acknowledgedRemoteGeneration = 0,
  }) : deletedLabelTimestamps = Map<String, DateTime>.unmodifiable(
         <String, DateTime>{
           for (final entry in deletedLabelTimestamps.entries)
             entry.key: TaskItem.normalizeTimestamp(entry.value),
         },
       );

  /// Creates an empty [WorkspaceSyncState] with default baselines and generations.
  const WorkspaceSyncState._empty()
    : lastSyncedLocalTdf = null,
      lastSyncedRemoteTdf = null,
      deletedLabelTimestamps = const <String, DateTime>{},
      acknowledgedLocalGeneration = 0,
      acknowledgedRemoteGeneration = 0;

  /// Reconstructs a [WorkspaceSyncState] from its compact `TTS\x01` or `TTS\x02` binary payload,
  /// returning [empty] if [bytes] is empty or malformed.
  factory WorkspaceSyncState.fromBytes(List<int> bytes) {
    if (bytes.length < 6 ||
        bytes[0] != 0x54 ||
        bytes[1] != 0x54 ||
        bytes[2] != 0x53 ||
        (bytes[3] != _binaryVersionV1 && bytes[3] != _binaryVersionV2)) {
      return empty;
    }
    final version = bytes[3];
    final source = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    try {
      final (localTdf, afterLocal) = _readNullableString(source, 4);
      final (remoteTdf, afterRemote) = _readNullableString(source, afterLocal);
      if (afterRemote + 2 > source.length) {
        return empty;
      }
      final count = (source[afterRemote] << 8) | source[afterRemote + 1];
      var cursor = afterRemote + 2;
      final deletedMap = <String, DateTime>{};
      for (var i = 0; i < count; i++) {
        final (labelId, dateVal, nextCursor) = _readDeletedLabelEntry(
          source,
          cursor,
        );
        deletedMap[labelId] = dateVal;
        cursor = nextCursor;
      }
      var localGen = 0;
      var remoteGen = 0;
      if (version == _binaryVersionV2) {
        if (cursor + 16 != source.length) {
          return empty;
        }
        localGen = _readInt64(source, cursor);
        remoteGen = _readInt64(source, cursor + 8);
        cursor += 16;
      }
      if (cursor != source.length) {
        return empty;
      }
      return WorkspaceSyncState(
        lastSyncedLocalTdf: localTdf,
        lastSyncedRemoteTdf: remoteTdf,
        deletedLabelTimestamps: deletedMap,
        acknowledgedLocalGeneration: localGen,
        acknowledgedRemoteGeneration: remoteGen,
      );
    } on FormatException {
      return empty;
    }
  }

  /// Empty synchronization state with no baselines and no pending label deletions.
  static const WorkspaceSyncState empty = WorkspaceSyncState._empty();

  /// Binary wire format version 1 identifier.
  static const int _binaryVersionV1 = 1;

  /// Binary wire format version 2 identifier.
  static const int _binaryVersionV2 = 2;

  /// Strict UTF-8 codec that rejects malformed byte sequences.
  static const Utf8Codec _utf8Codec = Utf8Codec(allowMalformed: false);

  /// Last acknowledged `deleted.generation` for the local `.tdf` file.
  final int acknowledgedLocalGeneration;

  /// Last acknowledged `deleted.generation` for the remote WebDAV `.tdf` file.
  final int acknowledgedRemoteGeneration;

  /// UTC deletion timestamps (`T_del`) for labels deleted since the last full sync.
  final Map<String, DateTime> deletedLabelTimestamps;

  /// Canonical `.tdf` snapshot from the last successful local file synchronization.
  final String? lastSyncedLocalTdf;

  /// Canonical `.tdf` snapshot from the last successful WebDAV synchronization.
  final String? lastSyncedRemoteTdf;

  /// Returns a copy of this [WorkspaceSyncState] with updated fields.
  WorkspaceSyncState copyWith({
    String? lastSyncedLocalTdf,
    bool clearLastSyncedLocalTdf = false,
    String? lastSyncedRemoteTdf,
    bool clearLastSyncedRemoteTdf = false,
    Map<String, DateTime>? deletedLabelTimestamps,
    int? acknowledgedLocalGeneration,
    int? acknowledgedRemoteGeneration,
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
      acknowledgedLocalGeneration:
          acknowledgedLocalGeneration ?? this.acknowledgedLocalGeneration,
      acknowledgedRemoteGeneration:
          acknowledgedRemoteGeneration ?? this.acknowledgedRemoteGeneration,
    );
  }

  /// Encodes this [WorkspaceSyncState] into a compact `TTS\x02` binary [Uint8List].
  Uint8List toBytes() {
    final builder = BytesBuilder(copy: false)
      ..add(const <int>[0x54, 0x54, 0x53, _binaryVersionV2]);
    _writeNullableString(builder, lastSyncedLocalTdf);
    _writeNullableString(builder, lastSyncedRemoteTdf);

    final entries = deletedLabelTimestamps.entries.toList();
    final count = entries.length <= 0xFFFF ? entries.length : 0xFFFF;
    builder
      ..addByte((count >> 8) & 0xFF)
      ..addByte(count & 0xFF);
    for (var i = 0; i < count; i++) {
      _writeDeletedLabelEntry(builder, entries[i].key, entries[i].value);
    }
    _writeInt64(builder, acknowledgedLocalGeneration);
    _writeInt64(builder, acknowledgedRemoteGeneration);
    return builder.toBytes();
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
        mapEquals(other.deletedLabelTimestamps, deletedLabelTimestamps);
  }

  @override
  int get hashCode => Object.hash(
    lastSyncedLocalTdf,
    lastSyncedRemoteTdf,
    acknowledgedLocalGeneration,
    acknowledgedRemoteGeneration,
    Object.hashAllUnordered(
      deletedLabelTimestamps.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
  );
}
