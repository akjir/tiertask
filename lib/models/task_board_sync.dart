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

import 'task_board.dart';
import 'task_item.dart';
import 'tdf_metadata.dart';

/// Stateless entity-level synchronization and Last-Write-Wins (LWW) merge engine
/// for [TaskBoard] documents per `TDF_SPEC.md` Section 6.7.
@immutable
class TaskBoardSync {
  const TaskBoardSync._();

  /// Merges [primary] and [secondary] entity-by-entity (`label` and `task` blocks)
  /// using [baseline] and [deletedLabelTimestamps], and evaluates the 6-tier pipeline at [evaluationTime].
  static TaskBoard merge({
    required TaskBoard primary,
    required TaskBoard secondary,
    TaskBoard? baseline,
    Map<String, DateTime> deletedLabelTimestamps = const {},
    required DateTime evaluationTime,
    DateTime? localEvaluationTime,
  }) {
    final now = TaskItem.normalizeTimestamp(evaluationTime);
    final mergedLabels = _mergeLabels(
      primaryLabels: primary.labels,
      secondaryLabels: secondary.labels,
      baselineLabels: baseline?.labels,
      deletedLabelTimestamps: deletedLabelTimestamps,
      now: now,
    );
    final validLabelIds = <String>{for (final label in mergedLabels) label.id};

    final (
      resolvedPrimaryTasks,
      resolvedSecondaryTasks,
    ) = _resolveTaskIdCollisions(
      primaryTasks: primary.allTasks,
      secondaryTasks: secondary.allTasks,
      now: now,
    );

    final rawMergedTasks = _mergeTasks(
      primaryTasks: resolvedPrimaryTasks,
      secondaryTasks: resolvedSecondaryTasks,
      baselineTasks: baseline?.allTasks,
      now: now,
    );

    final sanitizedTasks = _sanitizeMergedTasks(
      tasks: rawMergedTasks,
      validLabelIds: validLabelIds,
    );

    return TaskBoard.evaluate(
      tasks: sanitizedTasks,
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
      labels: mergedLabels,
      pruneExpiredCompleted: true,
    );
  }

  /// Ensures every [TdfLabel] and [TaskItem] in [board] carries an explicit UTC `modifiedAt`
  /// timestamp and evaluates the 6-tier pipeline at [evaluationTime].
  static TaskBoard stampAndNormalize(
    TaskBoard board, {
    required DateTime evaluationTime,
    DateTime? localEvaluationTime,
  }) {
    final now = TaskItem.normalizeTimestamp(evaluationTime);
    final stampedLabels = <TdfLabel>[
      for (final label in board.labels)
        label.modifiedAt != null
            ? label
            : label.copyWith(modifiedAt: label.effectiveModifiedAt),
    ];
    final stampedTasks = <TaskItem>[
      for (final task in board.allTasks)
        task.modifiedAt != null
            ? task
            : task.copyWith(modifiedAt: task.effectiveModifiedAt),
    ];
    return TaskBoard.evaluate(
      tasks: stampedTasks,
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
      labels: stampedLabels,
      pruneExpiredCompleted: true,
    );
  }

  /// Collects all unique entity keys in declaration order across [first] and [second].
  static List<String> _collectOrderedKeys(
    Iterable<String> first,
    Iterable<String> second,
  ) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final id in first) {
      if (seen.add(id)) {
        ordered.add(id);
      }
    }
    for (final id in second) {
      if (seen.add(id)) {
        ordered.add(id);
      }
    }
    return ordered;
  }

  /// Allocates the next unused sequential `tNNN` task ID not present in [usedIds].
  static String _nextFreeTaskId(Set<String> usedIds) {
    var number = usedIds.length + 1;
    while (true) {
      final candidate = 't${number.toString().padLeft(3, '0')}';
      if (usedIds.add(candidate)) {
        return candidate;
      }
      number++;
    }
  }

  /// Merges `label` blocks across [primaryLabels] and [secondaryLabels] using [baselineLabels] and [deletedLabelTimestamps].
  static List<TdfLabel> _mergeLabels({
    required List<TdfLabel> primaryLabels,
    required List<TdfLabel> secondaryLabels,
    required List<TdfLabel>? baselineLabels,
    required Map<String, DateTime> deletedLabelTimestamps,
    required DateTime now,
  }) {
    final primaryMap = <String, TdfLabel>{
      for (final label in primaryLabels) label.id: label,
    };
    final secondaryMap = <String, TdfLabel>{
      for (final label in secondaryLabels) label.id: label,
    };
    final baselineMap = baselineLabels != null
        ? <String, TdfLabel>{
            for (final label in baselineLabels) label.id: label,
          }
        : null;
    final orderedIds = _collectOrderedKeys(primaryMap.keys, secondaryMap.keys);
    final merged = <TdfLabel>[];

    for (final id in orderedIds) {
      final resolved = _resolveSingleLabel(
        id: id,
        primaryLabel: primaryMap[id],
        secondaryLabel: secondaryMap[id],
        baselineLabel: baselineMap?[id],
        hasBaseline: baselineMap != null,
        deletedAt: deletedLabelTimestamps[id],
        now: now,
      );
      if (resolved != null) {
        merged.add(resolved);
      }
    }
    return merged;
  }

  /// Merges `task` blocks across [primaryTasks] and [secondaryTasks] using [baselineTasks].
  static List<TaskItem> _mergeTasks({
    required List<TaskItem> primaryTasks,
    required List<TaskItem> secondaryTasks,
    required List<TaskItem>? baselineTasks,
    required DateTime now,
  }) {
    final primaryMap = <String, TaskItem>{
      for (final task in primaryTasks) task.id: task,
    };
    final secondaryMap = <String, TaskItem>{
      for (final task in secondaryTasks) task.id: task,
    };
    final baselineMap = baselineTasks != null
        ? <String, TaskItem>{for (final task in baselineTasks) task.id: task}
        : null;
    final orderedIds = _collectOrderedKeys(primaryMap.keys, secondaryMap.keys);
    final merged = <TaskItem>[];

    for (final id in orderedIds) {
      final resolved = _resolveSingleTask(
        primaryTask: primaryMap[id],
        secondaryTask: secondaryMap[id],
        baselineTask: baselineMap?[id],
        now: now,
      );
      if (resolved != null) {
        merged.add(resolved);
      }
    }
    return merged;
  }

  /// Resolves a single colliding task ID between [primaryTasks] and [secondaryTasks].
  static void _reassignCollidingTask({
    required String collidingId,
    required Map<String, int> primaryIndexById,
    required Map<String, int> secondaryIndexById,
    required List<TaskItem> nextPrimary,
    required List<TaskItem> nextSecondary,
    required Set<String> usedIds,
    required DateTime now,
  }) {
    final pIndex = primaryIndexById[collidingId];
    final sIndex = secondaryIndexById[collidingId];
    if (pIndex == null || sIndex == null) {
      return;
    }
    final pTask = nextPrimary[pIndex];
    final sTask = nextSecondary[sIndex];
    final pCreated = TaskItem.normalizeTimestamp(pTask.createdAt);
    final sCreated = TaskItem.normalizeTimestamp(sTask.createdAt);
    final sameTitle =
        pTask.title.trim().toLowerCase() == sTask.title.trim().toLowerCase();
    if (pCreated == sCreated || sameTitle) {
      return;
    }

    final newId = _nextFreeTaskId(usedIds);
    if (sCreated.isBefore(pCreated)) {
      nextPrimary[pIndex] = pTask.copyWith(
        id: newId,
        modifiedAt: TaskItem.nextModifiedTimestamp(
          now,
          pTask.effectiveModifiedAt,
        ),
      );
      _rewriteBlockedReferences(
        tasks: nextPrimary,
        oldId: collidingId,
        newId: newId,
        minCreatedAt: pCreated,
        now: now,
      );
      return;
    }

    nextSecondary[sIndex] = sTask.copyWith(
      id: newId,
      modifiedAt: TaskItem.nextModifiedTimestamp(
        now,
        sTask.effectiveModifiedAt,
      ),
    );
    _rewriteBlockedReferences(
      tasks: nextSecondary,
      oldId: collidingId,
      newId: newId,
      minCreatedAt: sCreated,
      now: now,
    );
  }

  /// Resolves a single label entity across primary, secondary, baseline, and deletion state.
  static TdfLabel? _resolveSingleLabel({
    required String id,
    required TdfLabel? primaryLabel,
    required TdfLabel? secondaryLabel,
    required TdfLabel? baselineLabel,
    required bool hasBaseline,
    required DateTime? deletedAt,
    required DateTime now,
  }) {
    if (primaryLabel != null && secondaryLabel != null) {
      final pMod = primaryLabel.effectiveModifiedAt;
      final sMod = secondaryLabel.effectiveModifiedAt;
      if (pMod.isAfter(sMod)) {
        return primaryLabel.copyWith(modifiedAt: pMod);
      }
      if (sMod.isAfter(pMod)) {
        return secondaryLabel.copyWith(modifiedAt: sMod);
      }
      if (primaryLabel == secondaryLabel) {
        return primaryLabel.copyWith(modifiedAt: pMod);
      }
      return secondaryLabel.copyWith(
        modifiedAt: TaskItem.nextModifiedTimestamp(now, sMod),
      );
    }

    if (primaryLabel != null) {
      final pMod = primaryLabel.effectiveModifiedAt;
      if (deletedAt != null && !pMod.isAfter(deletedAt)) {
        return null;
      }
      if (baselineLabel != null &&
          !pMod.isAfter(baselineLabel.effectiveModifiedAt)) {
        return null;
      }
      return primaryLabel.copyWith(modifiedAt: pMod);
    }

    if (secondaryLabel == null) {
      return null;
    }
    if (secondaryLabel.modifiedAt == null &&
        (!hasBaseline || baselineLabel == null)) {
      return secondaryLabel.copyWith(modifiedAt: now);
    }
    final sMod = secondaryLabel.effectiveModifiedAt;
    if (deletedAt != null && !sMod.isAfter(deletedAt)) {
      return null;
    }
    if (baselineLabel != null &&
        !sMod.isAfter(baselineLabel.effectiveModifiedAt)) {
      return null;
    }
    return secondaryLabel.copyWith(
      modifiedAt: secondaryLabel.modifiedAt ?? sMod,
    );
  }

  /// Resolves a single task entity across primary, secondary, and baseline boards.
  static TaskItem? _resolveSingleTask({
    required TaskItem? primaryTask,
    required TaskItem? secondaryTask,
    required TaskItem? baselineTask,
    required DateTime now,
  }) {
    if (primaryTask != null && secondaryTask != null) {
      final pMod = primaryTask.effectiveModifiedAt;
      final sMod = secondaryTask.effectiveModifiedAt;
      if (pMod.isAfter(sMod)) {
        return primaryTask.copyWith(modifiedAt: pMod);
      }
      if (sMod.isAfter(pMod)) {
        return secondaryTask.copyWith(modifiedAt: sMod);
      }
      if (_tasksContentEqual(primaryTask, secondaryTask)) {
        return primaryTask.copyWith(modifiedAt: pMod);
      }
      return secondaryTask.copyWith(
        modifiedAt: TaskItem.nextModifiedTimestamp(now, sMod),
      );
    }

    if (primaryTask != null) {
      final pMod = primaryTask.effectiveModifiedAt;
      if (baselineTask != null &&
          !pMod.isAfter(baselineTask.effectiveModifiedAt)) {
        return null;
      }
      return primaryTask.copyWith(modifiedAt: pMod);
    }

    if (secondaryTask == null) {
      return null;
    }
    final sMod = secondaryTask.effectiveModifiedAt;
    if (baselineTask != null &&
        !sMod.isAfter(baselineTask.effectiveModifiedAt)) {
      return null;
    }
    return secondaryTask.copyWith(modifiedAt: sMod);
  }

  /// Detects offline sequential task ID collisions and reassigns the later-created task,
  /// updating intra-board `blocked` references on the same side.
  static (List<TaskItem>, List<TaskItem>) _resolveTaskIdCollisions({
    required List<TaskItem> primaryTasks,
    required List<TaskItem> secondaryTasks,
    required DateTime now,
  }) {
    final nextPrimary = List<TaskItem>.from(primaryTasks);
    final nextSecondary = List<TaskItem>.from(secondaryTasks);
    final primaryIndexById = <String, int>{
      for (var i = 0; i < nextPrimary.length; i++) nextPrimary[i].id: i,
    };
    final secondaryIndexById = <String, int>{
      for (var i = 0; i < nextSecondary.length; i++) nextSecondary[i].id: i,
    };
    final usedIds = <String>{
      ...primaryIndexById.keys,
      ...secondaryIndexById.keys,
    };

    for (final collidingId in secondaryIndexById.keys) {
      _reassignCollidingTask(
        collidingId: collidingId,
        primaryIndexById: primaryIndexById,
        secondaryIndexById: secondaryIndexById,
        nextPrimary: nextPrimary,
        nextSecondary: nextSecondary,
        usedIds: usedIds,
        now: now,
      );
    }
    return (nextPrimary, nextSecondary);
  }

  /// Rewrites `blockedByTaskIds` references from [oldId] to [newId] for tasks in [tasks]
  /// created on or after [minCreatedAt].
  static void _rewriteBlockedReferences({
    required List<TaskItem> tasks,
    required String oldId,
    required String newId,
    required DateTime minCreatedAt,
    required DateTime now,
  }) {
    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      final taskCreated = TaskItem.normalizeTimestamp(task.createdAt);
      if (taskCreated.isBefore(minCreatedAt) ||
          !task.blockedByTaskIds.contains(oldId)) {
        continue;
      }
      final updatedBlockers = <String>[
        for (final blockerId in task.blockedByTaskIds)
          blockerId == oldId ? newId : blockerId,
      ];
      tasks[i] = task.copyWith(
        blockedByTaskIds: updatedBlockers,
        modifiedAt: TaskItem.nextModifiedTimestamp(
          now,
          task.effectiveModifiedAt,
        ),
      );
    }
  }

  /// Strips unknown label references and self-referential blockers from merged [tasks].
  static List<TaskItem> _sanitizeMergedTasks({
    required List<TaskItem> tasks,
    required Set<String> validLabelIds,
  }) {
    final validTaskIds = <String>{for (final task in tasks) task.id};
    return <TaskItem>[
      for (final task in tasks)
        _sanitizeSingleMergedTask(
          task: task,
          validLabelIds: validLabelIds,
          validTaskIds: validTaskIds,
        ),
    ];
  }

  /// Sanitizes `labelIds` and `blockedByTaskIds` on a single merged [task].
  static TaskItem _sanitizeSingleMergedTask({
    required TaskItem task,
    required Set<String> validLabelIds,
    required Set<String> validTaskIds,
  }) {
    final cleanLabels = <String>[
      for (final labelId in task.labelIds)
        if (validLabelIds.contains(labelId)) labelId,
    ];
    final cleanBlockers = <String>[
      for (final blockerId in task.blockedByTaskIds)
        if (blockerId != task.id && validTaskIds.contains(blockerId)) blockerId,
    ];
    if (cleanLabels.length == task.labelIds.length &&
        cleanBlockers.length == task.blockedByTaskIds.length) {
      return task;
    }
    return task.copyWith(
      labelIds: cleanLabels,
      blockedByTaskIds: cleanBlockers,
    );
  }

  /// Compares two [TaskItem] instances for semantic content equality (ignoring `modifiedAt`).
  static bool _tasksContentEqual(TaskItem first, TaskItem second) {
    return first.copyWith(clearModifiedAt: true) ==
        second.copyWith(clearModifiedAt: true);
  }
}

/// Immutable per-workspace synchronization baseline and label deletion state.
@immutable
class WorkspaceSyncState {
  /// Creates a [WorkspaceSyncState].
  WorkspaceSyncState({
    this.lastSyncedLocalTdf,
    this.lastSyncedRemoteTdf,
    Map<String, DateTime> deletedLabelTimestamps = const {},
  }) : deletedLabelTimestamps = Map<String, DateTime>.unmodifiable(
         <String, DateTime>{
           for (final entry in deletedLabelTimestamps.entries)
             entry.key: TaskItem.normalizeTimestamp(entry.value),
         },
       );

  const WorkspaceSyncState._empty()
    : lastSyncedLocalTdf = null,
      lastSyncedRemoteTdf = null,
      deletedLabelTimestamps = const <String, DateTime>{};

  /// Reconstructs a [WorkspaceSyncState] from its compact `TTS\x01` binary payload,
  /// returning [empty] if [bytes] is empty or malformed.
  factory WorkspaceSyncState.fromBytes(List<int> bytes) {
    if (bytes.length < 6 ||
        bytes[0] != 0x54 ||
        bytes[1] != 0x54 ||
        bytes[2] != 0x53 ||
        bytes[3] != _binaryVersion) {
      return empty;
    }
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
      if (cursor != source.length) {
        return empty;
      }
      return WorkspaceSyncState(
        lastSyncedLocalTdf: localTdf,
        lastSyncedRemoteTdf: remoteTdf,
        deletedLabelTimestamps: deletedMap,
      );
    } on FormatException {
      return empty;
    }
  }

  /// Empty synchronization state with no baselines and no pending label deletions.
  static const WorkspaceSyncState empty = WorkspaceSyncState._empty();

  static const int _binaryVersion = 1;
  static const Utf8Codec _utf8Codec = Utf8Codec(allowMalformed: false);

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
    );
  }

  /// Encodes this [WorkspaceSyncState] into a compact `TTS\x01` binary [Uint8List].
  Uint8List toBytes() {
    final builder = BytesBuilder(copy: false)
      ..add(const <int>[0x54, 0x54, 0x53, _binaryVersion]);
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
    var epochSeconds = 0;
    for (var i = 0; i < 8; i++) {
      epochSeconds = (epochSeconds << 8) | source[afterId + i];
    }
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      epochSeconds * 1000,
      isUtc: true,
    );
    return (labelId, TaskItem.normalizeTimestamp(timestamp), afterId + 8);
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
    for (var shift = 56; shift >= 0; shift -= 8) {
      builder.addByte((epochSeconds >> shift) & 0xFF);
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
        mapEquals(other.deletedLabelTimestamps, deletedLabelTimestamps);
  }

  @override
  int get hashCode => Object.hash(
    lastSyncedLocalTdf,
    lastSyncedRemoteTdf,
    Object.hashAllUnordered(
      deletedLabelTimestamps.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
  );
}
