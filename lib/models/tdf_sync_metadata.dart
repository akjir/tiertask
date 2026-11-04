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

import 'package:flutter/foundation.dart';

import 'tdf_metadata.dart';

/// Scheduling, import, and identifier migration outcome categories defined in `TDF_SPEC.md` Sections 8.2 and 10.4.
enum TdfContextOutcomeKind {
  /// A local calendar operation lacks a configured time zone or its applicable transition rules.
  timeZoneContextRequired,

  /// A historical timestamp conversion requires an explicit source time zone that was not provided.
  importContextRequired,

  /// All 256 deterministic SHA-256 Base62 migration counters collided for a non-canonical identifier.
  migrationIdentifierCollision,
}

/// Resolution choice for a `DeletionConflict` synchronization outcome per `TDF_SPEC.md` Section 6.8.2.
enum TdfDeletionResolution {
  /// Confirms deletion of the conflicted entity and advances its deletion timestamp past the live edit.
  delete,

  /// Restores the conflicted entity, removes its deletion record, and advances its `modified` timestamp past the deletion.
  undelete,
}

/// Synchronization and recovery outcome categories defined in `TDF_SPEC.md` Section 8.1.
enum TdfSyncOutcomeKind {
  /// Unacknowledged history expiry (`generation > acknowledgedGeneration` or missing acknowledgment) requires user recovery.
  recoveryRequired,

  /// One side deleted an entity while the other side modified it at or after the deletion timestamp.
  deletionConflict,

  /// Incoming shared document has a `deleted.generation` lower than the acknowledged generation.
  syncGenerationRollback,
}

/// Typed exception representing a `TDF_SPEC.md` Section 8.2 or 10.4 context/migration outcome.
@immutable
class TdfContextException implements Exception {
  /// Creates a [TdfContextException].
  const TdfContextException({
    required this.kind,
    required this.message,
    this.entityId,
    this.line,
  });

  /// Optional affected task or label identifier.
  final String? entityId;

  /// Specific context outcome category.
  final TdfContextOutcomeKind kind;

  /// Optional 1-based source line number where the context error occurred.
  final int? line;

  /// Factual diagnostic description of the context outcome.
  final String message;

  @override
  String toString() => 'TdfContextException(${kind.name}): $message';
}

/// Immutable root `deleted` block storing the deletion history generation and active deletion records per `TDF_SPEC.md` Section 4.4.
@immutable
class TdfDeletedBlock {
  /// Creates a [TdfDeletedBlock] with sorted, unmodifiable task and label deletion records.
  TdfDeletedBlock({
    this.generation = 0,
    Iterable<TdfDeletedTaskRecord> tasks = const <TdfDeletedTaskRecord>[],
    Iterable<TdfDeletedLabelRecord> labels = const <TdfDeletedLabelRecord>[],
  }) : assert(
         generation >= 0 && generation <= maxGeneration,
         'generation must be within 0..$maxGeneration',
       ),
       tasks = List<TdfDeletedTaskRecord>.unmodifiable(_sortTaskRecords(tasks)),
       labels = List<TdfDeletedLabelRecord>.unmodifiable(
         _sortLabelRecords(labels),
       );

  /// Empty default `deleted` block (`generation = 0`, no records).
  static final TdfDeletedBlock empty = TdfDeletedBlock();

  /// Maximum allowed `deleted` records (`task` + `label` combined) per `TDF_SPEC.md` Section 3.3.
  static const int maxDeletedRecords = 4096;

  /// Maximum allowed `generation` value (`2^53 - 1`) per `TDF_SPEC.md` Section 4.4.
  static const int maxGeneration = 9007199254740991;

  /// Monotonically increasing deletion history generation (`0..9007199254740991`).
  final int generation;

  /// Deleted label records sorted by ascending ASCII `labelId`.
  final List<TdfDeletedLabelRecord> labels;

  /// Deleted task records sorted by ascending ASCII `taskId`.
  final List<TdfDeletedTaskRecord> tasks;

  /// Whether this block can be omitted during canonical serialization (`generation == 0` and no records).
  bool get isDefaultEmpty => generation == 0 && tasks.isEmpty && labels.isEmpty;

  /// Total number of task and label deletion records in this block.
  int get totalRecords => tasks.length + labels.length;

  /// Returns a copy of this [TdfDeletedBlock] with updated fields.
  TdfDeletedBlock copyWith({
    int? generation,
    Iterable<TdfDeletedTaskRecord>? tasks,
    Iterable<TdfDeletedLabelRecord>? labels,
  }) {
    return TdfDeletedBlock(
      generation: generation ?? this.generation,
      tasks: tasks ?? this.tasks,
      labels: labels ?? this.labels,
    );
  }

  /// Looks up the deletion record for [labelId], or returns `null` if absent.
  TdfDeletedLabelRecord? findLabelRecord(String labelId) {
    for (final record in labels) {
      if (record.labelId == labelId) {
        return record;
      }
    }
    return null;
  }

  /// Looks up the deletion record for [taskId], or returns `null` if absent.
  TdfDeletedTaskRecord? findTaskRecord(String taskId) {
    for (final record in tasks) {
      if (record.taskId == taskId) {
        return record;
      }
    }
    return null;
  }

  /// Sorts label deletion records by ascending ASCII `labelId`, keeping the latest deletion per ID.
  static List<TdfDeletedLabelRecord> _sortLabelRecords(
    Iterable<TdfDeletedLabelRecord> records,
  ) {
    final byId = <String, TdfDeletedLabelRecord>{};
    for (final record in records) {
      final existing = byId[record.labelId];
      if (existing == null || record.deletedAt.isAfter(existing.deletedAt)) {
        byId[record.labelId] = record;
      }
    }
    final sorted = byId.values.toList()
      ..sort((left, right) => left.labelId.compareTo(right.labelId));
    return sorted;
  }

  /// Sorts task deletion records by ascending ASCII `taskId`, keeping the latest deletion timestamp and greatest completion checkpoint per ID.
  static List<TdfDeletedTaskRecord> _sortTaskRecords(
    Iterable<TdfDeletedTaskRecord> records,
  ) {
    final byId = <String, TdfDeletedTaskRecord>{};
    for (final record in records) {
      final existing = byId[record.taskId];
      byId[record.taskId] = existing == null
          ? record
          : existing.mergeWith(record);
    }
    final sorted = byId.values.toList()
      ..sort((left, right) => left.taskId.compareTo(right.taskId));
    return sorted;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TdfDeletedBlock &&
        other.generation == generation &&
        listEquals(other.tasks, tasks) &&
        listEquals(other.labels, labels);
  }

  @override
  int get hashCode =>
      Object.hash(generation, Object.hashAll(tasks), Object.hashAll(labels));
}

/// Immutable deletion record for a label (`label <label-id> <timestamp>`) inside a `deleted` block.
@immutable
class TdfDeletedLabelRecord {
  /// Creates a [TdfDeletedLabelRecord].
  const TdfDeletedLabelRecord({required this.labelId, required this.deletedAt});

  /// UTC deletion timestamp.
  final DateTime deletedAt;

  /// Canonical 10-character Base62 label identifier.
  final String labelId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TdfDeletedLabelRecord &&
        other.labelId == labelId &&
        other.deletedAt == deletedAt;
  }

  @override
  int get hashCode => Object.hash(labelId, deletedAt);
}

/// Immutable deletion record for a task (`task <task-id> <timestamp> [<completion-count>]`) inside a `deleted` block.
@immutable
class TdfDeletedTaskRecord {
  /// Creates a [TdfDeletedTaskRecord].
  const TdfDeletedTaskRecord({
    required this.taskId,
    required this.deletedAt,
    this.completionsCheckpoint = 0,
  }) : assert(
         completionsCheckpoint >= 0 &&
             completionsCheckpoint <= TdfTaskDependency.maxCompletions,
         'completionsCheckpoint must be within 0..${TdfTaskDependency.maxCompletions}',
       );

  /// Highest known cumulative completion count (`0..999,999,999`) at or before deletion.
  final int completionsCheckpoint;

  /// UTC deletion timestamp.
  final DateTime deletedAt;

  /// Canonical 10-character Base62 task identifier.
  final String taskId;

  /// Merges two deletion records for the same [taskId], keeping the later [deletedAt] and greater [completionsCheckpoint].
  TdfDeletedTaskRecord mergeWith(TdfDeletedTaskRecord other) {
    final laterDeletedAt = other.deletedAt.isAfter(deletedAt)
        ? other.deletedAt
        : deletedAt;
    final maxCheckpoint = other.completionsCheckpoint > completionsCheckpoint
        ? other.completionsCheckpoint
        : completionsCheckpoint;
    return TdfDeletedTaskRecord(
      taskId: taskId,
      deletedAt: laterDeletedAt,
      completionsCheckpoint: maxCheckpoint,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TdfDeletedTaskRecord &&
        other.taskId == taskId &&
        other.deletedAt == deletedAt &&
        other.completionsCheckpoint == completionsCheckpoint;
  }

  @override
  int get hashCode => Object.hash(taskId, deletedAt, completionsCheckpoint);
}

/// Immutable root `queue` block storing the shared queue modification timestamp and ordered scheduled open task IDs per `TDF_SPEC.md` Section 4.5.
@immutable
class TdfQueueBlock {
  /// Creates a [TdfQueueBlock].
  TdfQueueBlock({
    DateTime? modifiedAt,
    Iterable<String> taskIds = const <String>[],
  }) : modifiedAt = modifiedAt ?? epochModifiedAt,
       taskIds = List<String>.unmodifiable(taskIds);

  /// Default epoch timestamp (`1970-01-01 00:00:00` UTC) for an omitted or initial empty `queue` block.
  static final DateTime epochModifiedAt = DateTime.utc(1970, 1, 1, 0, 0, 0);

  /// Empty default `queue` block at the Unix epoch (`1970-01-01 00:00:00` UTC).
  static final TdfQueueBlock empty = TdfQueueBlock();

  /// Maximum allowed `task` entries inside a `queue` block per `TDF_SPEC.md` Section 3.3.
  static const int maxQueueEntries = 4096;

  /// UTC timestamp of the last shared queue order modification.
  final DateTime modifiedAt;

  /// Ordered list of scheduled open task IDs.
  final List<String> taskIds;

  /// Whether this block is in its default omitted state (`taskIds.isEmpty` and `modifiedAt == 1970-01-01 00:00:00` UTC).
  bool get isDefaultEmpty => taskIds.isEmpty && modifiedAt == epochModifiedAt;

  /// Returns a copy of this [TdfQueueBlock] with updated fields.
  TdfQueueBlock copyWith({DateTime? modifiedAt, Iterable<String>? taskIds}) {
    return TdfQueueBlock(
      modifiedAt: modifiedAt ?? this.modifiedAt,
      taskIds: taskIds ?? this.taskIds,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TdfQueueBlock &&
        other.modifiedAt == modifiedAt &&
        listEquals(other.taskIds, taskIds);
  }

  @override
  int get hashCode => Object.hash(modifiedAt, Object.hashAll(taskIds));
}

/// Typed exception representing a `TDF_SPEC.md` Section 8.1 synchronization or recovery outcome.
@immutable
class TdfSyncOutcomeException implements Exception {
  /// Creates a [TdfSyncOutcomeException].
  const TdfSyncOutcomeException({
    required this.kind,
    required this.message,
    this.conflictedTaskIds = const <String>[],
    this.conflictedLabelIds = const <String>[],
    this.ambiguousTaskIds = const <String>[],
    this.ambiguousLabelIds = const <String>[],
  });

  /// Local-only label IDs requiring explicit user recovery when deletion history expired.
  final List<String> ambiguousLabelIds;

  /// Local-only task IDs requiring explicit user recovery when deletion history expired.
  final List<String> ambiguousTaskIds;

  /// Label IDs involved in a deletion vs. edit conflict.
  final List<String> conflictedLabelIds;

  /// Task IDs involved in a deletion vs. edit conflict.
  final List<String> conflictedTaskIds;

  /// Specific synchronization outcome category.
  final TdfSyncOutcomeKind kind;

  /// Factual diagnostic description of the synchronization outcome.
  final String message;

  @override
  String toString() => 'TdfSyncOutcomeException(${kind.name}): $message';
}

/// Immutable prerequisite dependency token (`<task-id>[:<required-completion>]`) per `TDF_SPEC.md` Section 4.1 and 6.9.
@immutable
class TdfTaskDependency {
  /// Creates a [TdfTaskDependency].
  const TdfTaskDependency({required this.taskId, this.requiredCompletion = 1})
    : assert(
        requiredCompletion >= 1 && requiredCompletion <= maxCompletions,
        'requiredCompletion must be within 1..$maxCompletions',
      );

  /// Maximum allowed cumulative completion count or required completion threshold (`9,007,199,254,740,991`) per `TDF_SPEC.md` Section 7.
  static const int maxCompletions = 9007199254740991;

  /// Minimum completion counter value (`1..999,999,999`) required on [taskId] to satisfy this dependency.
  final int requiredCompletion;

  /// Canonical 10-character Base62 identifier of the prerequisite task.
  final String taskId;

  /// Formats this dependency in canonical TDF 0.5.0 form (`<task-id>` when [requiredCompletion] is `1`, else `<task-id>:<n>`).
  String formatCanonical() {
    if (requiredCompletion <= 1) {
      return taskId;
    }
    return '$taskId:$requiredCompletion';
  }

  /// Converts a list of bare task IDs into normalized [TdfTaskDependency] items with `requiredCompletion = 1`.
  static List<TdfTaskDependency> fromTaskIds(Iterable<String> taskIds) {
    final result = <TdfTaskDependency>[];
    final seen = <String>{};
    for (final id in taskIds) {
      if (seen.add(id)) {
        result.add(TdfTaskDependency(taskId: id));
      }
    }
    return List<TdfTaskDependency>.unmodifiable(result);
  }

  /// Deduplicates [dependencies] by retaining the greatest [requiredCompletion] for each [taskId]
  /// and sorting entries in ascending ASCII [taskId] order per `TDF_SPEC.md` Section 4.1 and 7.1.
  static List<TdfTaskDependency> normalizeList(
    Iterable<TdfTaskDependency> dependencies,
  ) {
    final byTaskId = <String, int>{};
    for (final dependency in dependencies) {
      final existing = byTaskId[dependency.taskId];
      if (existing == null || dependency.requiredCompletion > existing) {
        byTaskId[dependency.taskId] = dependency.requiredCompletion;
      }
    }
    final sortedIds = byTaskId.keys.toList()..sort();
    return List<TdfTaskDependency>.unmodifiable(<TdfTaskDependency>[
      for (final id in sortedIds)
        TdfTaskDependency(taskId: id, requiredCompletion: byTaskId[id] ?? 1),
    ]);
  }

  /// Parses a `<task-id>[:<required-completion>]` token, or returns `null` if invalid.
  static TdfTaskDependency? tryParse(
    String rawToken, {
    bool requireCanonicalId = true,
  }) {
    if (rawToken.isEmpty) {
      return null;
    }
    final colonIndex = rawToken.indexOf(':');
    if (colonIndex < 0) {
      if (requireCanonicalId && !isValidTaskId(rawToken)) {
        return null;
      }
      return TdfTaskDependency(taskId: rawToken);
    }
    final idPart = rawToken.substring(0, colonIndex);
    final countPart = rawToken.substring(colonIndex + 1);
    if (idPart.isEmpty || countPart.isEmpty || countPart.contains(':')) {
      return null;
    }
    if (requireCanonicalId && !isValidTaskId(idPart)) {
      return null;
    }
    if (!_isAsciiDigits(countPart)) {
      return null;
    }
    final parsedCount = int.tryParse(countPart);
    if (parsedCount == null ||
        parsedCount < 1 ||
        parsedCount > maxCompletions) {
      return null;
    }
    return TdfTaskDependency(taskId: idPart, requiredCompletion: parsedCount);
  }

  /// Checks whether [value] consists exclusively of ASCII decimal digits (`0-9`).
  static bool _isAsciiDigits(String value) {
    if (value.isEmpty) {
      return false;
    }
    for (var i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      if (code < 0x30 || code > 0x39) {
        return false;
      }
    }
    return true;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TdfTaskDependency &&
        other.taskId == taskId &&
        other.requiredCompletion == requiredCompletion;
  }

  @override
  int get hashCode => Object.hash(taskId, requiredCompletion);
}
