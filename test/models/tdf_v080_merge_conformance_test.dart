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
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_board_evaluator.dart';
import 'package:tiertask/models/task_board_sync.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_payload_comparison.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';

const String _mergeVectorsPath = 'spec/conformance/v0.8.0/merge/vectors.json';

const String _timezoneVectorsPath =
    'spec/conformance/v0.8.0/timezone/vectors.json';

/// Executes the normative TDF 0.8.0 timezone and synchronization conformance suites.
void main() {
  group('TDF 0.8.0 Timezone, Calendar, Priority, and Lifecycle Conformance', () {
    test(
      'executes all local-to-UTC point conversion and missing-context vectors',
      () {
        final suite = _loadJsonSuite(_timezoneVectorsPath);
        expect(
          suite['version'],
          equals(tdfSupportedVersion),
          reason: 'timezone/vectors.json must target TDF 0.8.0',
        );
        final vectors = _requireMapList(suite, 'pointConversionVectors');
        expect(
          vectors.length,
          greaterThanOrEqualTo(12),
          reason: 'Must cover all 7 Berlin vectors, New York DST, and error',
        );
        for (final vector in vectors) {
          _runPointConversionVector(vector);
        }
      },
    );

    test(
      'executes cross-zone UTC deferral expiry and cleanup conformance vectors',
      () {
        final suite = _loadJsonSuite(_timezoneVectorsPath);
        final vectors = _requireMapList(suite, 'crossZoneDeferralVectors');
        expect(
          vectors,
          isNotEmpty,
          reason: 'crossZoneDeferralVectors must not be empty',
        );
        for (final vector in vectors) {
          _runCrossZoneDeferralVector(vector);
        }
      },
    );

    test('executes Mode 2 due.anchor recurrence, month-end clamping, interval edit, and spring-gap vectors', () {
      final suite = _loadJsonSuite(_timezoneVectorsPath);
      final vectors = _requireMapList(suite, 'mode2RecurrenceVectors');
      expect(
        vectors.length,
        greaterThanOrEqualTo(7),
        reason: 'Must cover tz_01 through tz_07 Mode 2 anchor vectors',
      );
      for (final vector in vectors) {
        _runMode2RecurrenceVector(vector);
      }
    });

    test('executes W_due (86400s, 0s, absent) effective priority and scoped exclusion vectors', () {
      expect(
        defaultDueLeadSeconds,
        equals(86400),
        reason: 'Normative DEFAULT_DUE_LEAD_SECONDS must equal 86400s',
      );
      final suite = _loadJsonSuite(_timezoneVectorsPath);
      final vectors = _requireMapList(suite, 'dueLeadPriorityVectors');
      expect(
        vectors.length,
        greaterThanOrEqualTo(4),
        reason: 'Must cover 86400s, activeLabelId, 0s, and absent W_due',
      );
      for (final vector in vectors) {
        _runDueLeadPriorityVector(vector);
      }
    });

    test('executes downgradeTask (Case A, Case B, Ready, Planned, no-op) and restoreTask vectors', () {
      final suite = _loadJsonSuite(_timezoneVectorsPath);
      final downgradeVectors = _requireMapList(suite, 'downgradeVectors');
      final restoreVectors = _requireMapList(suite, 'restoreVectors');
      expect(
        downgradeVectors.length,
        greaterThanOrEqualTo(6),
        reason: 'Must cover Case A, Case B, Ready->Planned->Someday, no-op',
      );
      expect(
        restoreVectors.length,
        greaterThanOrEqualTo(3),
        reason: 'Must cover restoreTask to Someday, Planned, and Focus',
      );
      for (final vector in downgradeVectors) {
        _runDowngradeVector(vector);
      }
      for (final vector in restoreVectors) {
        _runRestoreVector(vector);
      }
    });
  });

  group('TDF 0.8.0 Synchronization, Stage Fairness, Cascade, and Recovery Conformance', () {
    test('executes all three-way, baseline-free, occurrence, cascade, conflict, retention, and generation vectors symmetrically', () {
      final suite = _loadJsonSuite(_mergeVectorsPath);
      expect(
        suite['version'],
        equals(tdfSupportedVersion),
        reason: 'merge/vectors.json must target TDF 0.8.0',
      );
      final vectors = _requireMapList(suite, 'mergeVectors');
      expect(
        vectors.length,
        greaterThanOrEqualTo(35),
        reason: 'mergeVectors must cover all Appendix A.2.3 merge rules',
      );
      for (final vector in vectors) {
        _runMergeVector(vector);
      }
    });

    test('executes multi-stage deferred-then-final and local Step 3 contention retry vectors', () {
      final suite = _loadJsonSuite(_mergeVectorsPath);
      final vectors = _requireMapList(suite, 'multiStageVectors');
      expect(
        vectors.length,
        greaterThanOrEqualTo(2),
        reason: 'Must cover multi-stage fairness and Step 3 local retry',
      );
      for (final vector in vectors) {
        _runMultiStageVector(vector);
      }
    });

    test(
      'executes RecoveryRequired discard and recoverAsNew ID-rewriting vectors',
      () {
        final suite = _loadJsonSuite(_mergeVectorsPath);
        final vectors = _requireMapList(suite, 'recoveryResolutionVectors');
        expect(
          vectors,
          isNotEmpty,
          reason: 'recoveryResolutionVectors must not be empty',
        );
        for (final vector in vectors) {
          _runRecoveryResolutionVector(vector);
        }
      },
    );
  });
}

/// Verifies that [board] matches every expected collection and block in [expected].
void _assertBoardMatchesExpected(
  TaskBoard board,
  Map<String, Object?> expected, {
  required String contextLabel,
}) {
  if (expected['tasks'] is List<Object?>) {
    final expectedTasks = _parseTaskList(_requireMapList(expected, 'tasks'));
    expect(
      board.allTasks.length,
      equals(expectedTasks.length),
      reason: '$contextLabel: live task count',
    );
    for (final expectedTask in expectedTasks) {
      _assertSingleExpectedTask(board, expectedTask, contextLabel);
    }
  }
  if (expected['labels'] is List<Object?>) {
    final expectedLabels = _parseLabelList(_requireMapList(expected, 'labels'));
    expect(
      board.labels.length,
      equals(expectedLabels.length),
      reason: '$contextLabel: live label count',
    );
    for (final expectedLabel in expectedLabels) {
      _assertLabelMatchesExpected(board, expectedLabel, contextLabel);
    }
  }
  if (expected['locations'] is List<Object?>) {
    final expectedLocations = _parseLocationList(
      _requireMapList(expected, 'locations'),
    );
    expect(
      board.locations.length,
      equals(expectedLocations.length),
      reason: '$contextLabel: live location count',
    );
    for (final expectedLocation in expectedLocations) {
      _assertLocationMatchesExpected(board, expectedLocation, contextLabel);
    }
  }
  if (expected['deleted'] case final Map<String, Object?> deletedMap) {
    _assertDeletedMatchesExpected(
      board.deletedBlock,
      _parseDeletedBlock(deletedMap),
      contextLabel,
    );
  }
  if (expected['queue'] case final Map<String, Object?> queueMap) {
    _assertQueueMatchesExpected(board.queueBlock, queueMap, contextLabel);
  }
  if (expected['tiers'] case final Map<String, Object?> tiersMap) {
    _assertTierIdsMatch(board, tiersMap, contextLabel);
  }
}

/// Verifies that [actual] matches [expected] `deleted` block generation and records.
void _assertDeletedMatchesExpected(
  TdfDeletedBlock actual,
  TdfDeletedBlock expected,
  String contextLabel,
) {
  expect(
    actual.generation,
    equals(expected.generation),
    reason: '$contextLabel: deleted.generation',
  );
  expect(
    actual.tasks,
    equals(expected.tasks),
    reason: '$contextLabel: deleted.tasks',
  );
  expect(
    actual.labels,
    equals(expected.labels),
    reason: '$contextLabel: deleted.labels',
  );
  expect(
    actual.locations,
    equals(expected.locations),
    reason: '$contextLabel: deleted.locations',
  );
}

/// Verifies that [board] contains [expectedLabel] with matching attributes.
void _assertLabelMatchesExpected(
  TaskBoard board,
  TdfLabel expectedLabel,
  String contextLabel,
) {
  final actual = board.findLabel(expectedLabel.id);
  expect(
    actual,
    isNotNull,
    reason: '$contextLabel: missing expected label ${expectedLabel.id}',
  );
  if (actual == null) {
    return;
  }
  expect(
    actual,
    equals(expectedLabel),
    reason: '$contextLabel: label ${expectedLabel.id} mismatch',
  );
}

/// Verifies that [board] contains [expectedLocation] with matching attributes.
void _assertLocationMatchesExpected(
  TaskBoard board,
  TdfLocation expectedLocation,
  String contextLabel,
) {
  final actual = board.findLocation(expectedLocation.id);
  expect(
    actual,
    isNotNull,
    reason: '$contextLabel: missing expected location ${expectedLocation.id}',
  );
  if (actual == null) {
    return;
  }
  expect(
    actual,
    equals(expectedLocation),
    reason: '$contextLabel: location ${expectedLocation.id} mismatch',
  );
}

/// Verifies that [actual] matches the expected `queue` task IDs and optional `modified` timestamp.
void _assertQueueMatchesExpected(
  TdfQueueBlock actual,
  Map<String, Object?> expectedQueueMap,
  String contextLabel,
) {
  final expectedIds = _parseStringList(expectedQueueMap['taskIds']);
  expect(
    actual.taskIds,
    equals(expectedIds),
    reason: '$contextLabel: queue.taskIds',
  );
  if (expectedQueueMap.containsKey('modified')) {
    final rawModified = expectedQueueMap['modified'];
    final expectedModified = rawModified is String
        ? _parseUtcTimestamp(rawModified)
        : TdfQueueBlock.epochModifiedAt;
    expect(
      actual.modifiedAt,
      equals(expectedModified),
      reason: '$contextLabel: queue.modifiedAt',
    );
  }
}

/// Looks up [expectedTask] in [board] and asserts full TDF 0.8.0 field equality.
void _assertSingleExpectedTask(
  TaskBoard board,
  TaskItem expectedTask,
  String contextLabel,
) {
  final actual = board.findTask(expectedTask.id);
  expect(
    actual,
    isNotNull,
    reason: '$contextLabel: missing expected task ${expectedTask.id}',
  );
  if (actual == null) {
    return;
  }
  _assertTaskMatchesExpected(
    actual,
    expectedTask,
    contextLabel: '$contextLabel [${expectedTask.id}]',
  );
}

/// Executes [action] and asserts that it throws a [TdfSyncOutcomeException] matching [expectedOutcome].
void _assertSyncOutcomeMatches(
  TaskBoard Function() action,
  Map<String, Object?> expectedOutcome, {
  required String contextLabel,
}) {
  final kindName = _requireString(expectedOutcome, 'kind');
  final expectedKind = TdfSyncOutcomeKind.values.byName(kindName);
  TdfSyncOutcomeException? caught;
  try {
    action();
  } on TdfSyncOutcomeException catch (exception) {
    caught = exception;
  }
  expect(
    caught,
    isNotNull,
    reason: '$contextLabel: expected TdfSyncOutcomeException($kindName)',
  );
  if (caught == null) {
    return;
  }
  expect(
    caught.kind,
    equals(expectedKind),
    reason: '$contextLabel: outcome kind',
  );
  if (expectedOutcome['conflictedTaskIds'] != null) {
    expect(
      caught.conflictedTaskIds,
      unorderedEquals(_parseStringList(expectedOutcome['conflictedTaskIds'])),
      reason: '$contextLabel: conflictedTaskIds',
    );
  }
  if (expectedOutcome['conflictedLabelIds'] != null) {
    expect(
      caught.conflictedLabelIds,
      unorderedEquals(_parseStringList(expectedOutcome['conflictedLabelIds'])),
      reason: '$contextLabel: conflictedLabelIds',
    );
  }
  if (expectedOutcome['conflictedLocationIds'] != null) {
    expect(
      caught.conflictedLocationIds,
      unorderedEquals(
        _parseStringList(expectedOutcome['conflictedLocationIds']),
      ),
      reason: '$contextLabel: conflictedLocationIds',
    );
  }
  if (expectedOutcome['ambiguousTaskIds'] != null) {
    expect(
      caught.ambiguousTaskIds,
      unorderedEquals(_parseStringList(expectedOutcome['ambiguousTaskIds'])),
      reason: '$contextLabel: ambiguousTaskIds',
    );
  }
  if (expectedOutcome['ambiguousLabelIds'] != null) {
    expect(
      caught.ambiguousLabelIds,
      unorderedEquals(_parseStringList(expectedOutcome['ambiguousLabelIds'])),
      reason: '$contextLabel: ambiguousLabelIds',
    );
  }
  if (expectedOutcome['ambiguousLocationIds'] != null) {
    expect(
      caught.ambiguousLocationIds,
      unorderedEquals(
        _parseStringList(expectedOutcome['ambiguousLocationIds']),
      ),
      reason: '$contextLabel: ambiguousLocationIds',
    );
  }
}

/// Asserts that [actual] and [expected] match across all TDF 0.8.0 task fields including `dueAnchor`.
void _assertTaskMatchesExpected(
  TaskItem actual,
  TaskItem expected, {
  required String contextLabel,
}) {
  expect(actual.title, equals(expected.title), reason: '$contextLabel title');
  expect(actual.note, equals(expected.note), reason: '$contextLabel note');
  expect(
    actual.modifiedAt,
    equals(expected.modifiedAt),
    reason: '$contextLabel modifiedAt',
  );
  expect(
    actual.completions,
    equals(expected.completions),
    reason: '$contextLabel completions',
  );
  expect(
    actual.isCompleted,
    equals(expected.isCompleted),
    reason: '$contextLabel isCompleted',
  );
  expect(
    actual.completedAt,
    equals(expected.completedAt),
    reason: '$contextLabel completedAt',
  );
  expect(
    actual.isPriority,
    equals(expected.isPriority),
    reason: '$contextLabel isPriority',
  );
  expect(
    actual.labelIds,
    equals(expected.labelIds),
    reason: '$contextLabel labelIds',
  );
  expect(
    actual.isSuspendedForever,
    equals(expected.isSuspendedForever),
    reason: '$contextLabel isSuspendedForever',
  );
  expect(
    actual.suspendedAt,
    equals(expected.suspendedAt),
    reason: '$contextLabel suspendedAt',
  );
  expect(
    actual.suspendedNote,
    equals(expected.suspendedNote),
    reason: '$contextLabel suspendedNote',
  );
  expect(actual.dueAt, equals(expected.dueAt), reason: '$contextLabel dueAt');
  expect(
    actual.dueAnchor,
    equals(expected.dueAnchor),
    reason: '$contextLabel dueAnchor',
  );
  expect(
    actual.isDuePassive,
    equals(expected.isDuePassive),
    reason: '$contextLabel isDuePassive',
  );
  expect(
    actual.dueNote,
    equals(expected.dueNote),
    reason: '$contextLabel dueNote',
  );
  expect(
    actual.origin,
    equals(expected.origin),
    reason: '$contextLabel origin',
  );
  expect(actual.links, equals(expected.links), reason: '$contextLabel links');
  expect(
    actual.history,
    equals(expected.history),
    reason: '$contextLabel history',
  );
  expect(
    actual.repeatRule,
    equals(expected.repeatRule),
    reason: '$contextLabel repeatRule',
  );
  expect(
    actual.dependencies,
    equals(expected.dependencies),
    reason: '$contextLabel dependencies',
  );
  expect(
    actual.conditions,
    equals(expected.conditions),
    reason: '$contextLabel conditions',
  );
  expect(
    actual.subtasksAutoFinish,
    equals(expected.subtasksAutoFinish),
    reason: '$contextLabel subtasksAutoFinish',
  );
  expect(
    actual.subtasks,
    equals(expected.subtasks),
    reason: '$contextLabel subtasks',
  );
}

/// Asserts that derived 6-tier task ID lists on [board] match [tiersMap].
void _assertTierIdsMatch(
  TaskBoard board,
  Map<String, Object?> tiersMap,
  String contextLabel,
) {
  if (tiersMap['focus'] != null) {
    expect(
      board.focus.map((task) => task.id).toList(),
      equals(_parseStringList(tiersMap['focus'])),
      reason: '$contextLabel: focus tier IDs',
    );
  }
  if (tiersMap['ready'] != null) {
    expect(
      board.ready.map((task) => task.id).toList(),
      equals(_parseStringList(tiersMap['ready'])),
      reason: '$contextLabel: ready tier IDs',
    );
  }
  if (tiersMap['planned'] != null) {
    expect(
      board.planned.map((task) => task.id).toList(),
      equals(_parseStringList(tiersMap['planned'])),
      reason: '$contextLabel: planned tier IDs',
    );
  }
  if (tiersMap['blocked'] != null) {
    expect(
      board.blocked.map((task) => task.id).toList(),
      equals(_parseStringList(tiersMap['blocked'])),
      reason: '$contextLabel: blocked tier IDs',
    );
  }
  if (tiersMap['someday'] != null) {
    expect(
      board.someday.map((task) => task.id).toList(),
      equals(_parseStringList(tiersMap['someday'])),
      reason: '$contextLabel: someday tier IDs',
    );
  }
  if (tiersMap['completed'] != null) {
    expect(
      board.completed.map((task) => task.id).toList(),
      equals(_parseStringList(tiersMap['completed'])),
      reason: '$contextLabel: completed tier IDs',
    );
  }
}

/// Verifies `TdfPayloadComparison` total-order antisymmetry across shared entities in [leftBoard] and [rightBoard].
void _assertVersionComparisonAntisymmetry(
  TaskBoard leftBoard,
  TaskBoard rightBoard,
  String vectorId,
) {
  for (final leftTask in leftBoard.allTasks) {
    if (rightBoard.findTask(leftTask.id) case final rightTask?) {
      final forward = TdfPayloadComparison.compareTaskVersions(
        leftTask,
        rightTask,
      );
      final reverse = TdfPayloadComparison.compareTaskVersions(
        rightTask,
        leftTask,
      );
      expect(
        forward.sign,
        equals(-reverse.sign),
        reason: '$vectorId: compareTaskVersions antisymmetry (${leftTask.id})',
      );
    }
  }
  for (final leftLabel in leftBoard.labels) {
    if (rightBoard.findLabel(leftLabel.id) case final rightLabel?) {
      final forward = TdfPayloadComparison.compareLabelVersions(
        leftLabel,
        rightLabel,
      );
      final reverse = TdfPayloadComparison.compareLabelVersions(
        rightLabel,
        leftLabel,
      );
      expect(
        forward.sign,
        equals(-reverse.sign),
        reason:
            '$vectorId: compareLabelVersions antisymmetry (${leftLabel.id})',
      );
    }
  }
  for (final leftLocation in leftBoard.locations) {
    if (rightBoard.findLocation(leftLocation.id) case final rightLocation?) {
      final forward = TdfPayloadComparison.compareLocationVersions(
        leftLocation,
        rightLocation,
      );
      final reverse = TdfPayloadComparison.compareLocationVersions(
        rightLocation,
        leftLocation,
      );
      expect(
        forward.sign,
        equals(-reverse.sign),
        reason:
            '$vectorId: compareLocationVersions antisymmetry (${leftLocation.id})',
      );
    }
  }
}

/// Parses optional bound `TDF-DEL-003` decisions using [entityKey] and [signatureForEntity].
Map<String, TdfBoundDeletionDecision> _buildBoundDecisions(
  Object? rawDecisions, {
  required String entityKey,
  required String Function(Map<String, Object?> entityMap) signatureForEntity,
}) {
  if (rawDecisions is! Map<String, Object?>) {
    return const <String, TdfBoundDeletionDecision>{};
  }
  final result = <String, TdfBoundDeletionDecision>{};
  for (final entry in rawDecisions.entries) {
    final decisionMap = _requireMap(<String, Object?>{'v': entry.value}, 'v');
    final resolution = TdfDeletionResolution.values.byName(
      _requireString(decisionMap, 'resolution'),
    );
    final liveModifiedAt = decisionMap['expectedLiveModified'] is String
        ? _parseUtcTimestamp(
            _requireString(decisionMap, 'expectedLiveModified'),
          )
        : null;
    final deletionAt = decisionMap['expectedDeletionAt'] is String
        ? _parseUtcTimestamp(_requireString(decisionMap, 'expectedDeletionAt'))
        : null;
    final signature = decisionMap[entityKey] is Map<String, Object?>
        ? signatureForEntity(_requireMap(decisionMap, entityKey))
        : null;
    result[entry.key] = TdfBoundDeletionDecision(
      resolution: resolution,
      expectedLiveModifiedAt: liveModifiedAt,
      expectedDeletionAt: deletionAt,
      expectedLivePayloadSignature: signature,
    );
  }
  return result;
}

/// Parses optional bound `label` deletion-conflict decisions using `TdfPayloadComparison.labelPayloadSignature`.
Map<String, TdfBoundDeletionDecision> _buildBoundLabelDecisions(
  Object? rawDecisions,
) => _buildBoundDecisions(
  rawDecisions,
  entityKey: 'expectedLiveLabel',
  signatureForEntity: (entityMap) =>
      TdfPayloadComparison.labelPayloadSignature(_parseLabel(entityMap)),
);

/// Parses optional bound `location` deletion-conflict decisions using `TdfPayloadComparison.locationPayloadSignature`.
Map<String, TdfBoundDeletionDecision> _buildBoundLocationDecisions(
  Object? rawDecisions,
) => _buildBoundDecisions(
  rawDecisions,
  entityKey: 'expectedLiveLocation',
  signatureForEntity: (entityMap) =>
      TdfPayloadComparison.locationPayloadSignature(_parseLocation(entityMap)),
);

/// Parses optional bound `task` deletion-conflict decisions using `TdfPayloadComparison.taskPayloadSignature`.
Map<String, TdfBoundDeletionDecision> _buildBoundTaskDecisions(
  Object? rawDecisions,
) => _buildBoundDecisions(
  rawDecisions,
  entityKey: 'expectedLiveTask',
  signatureForEntity: (entityMap) =>
      TdfPayloadComparison.taskPayloadSignature(_parseTask(entityMap)),
);

/// Parses a `Map<String, TdfDeletionResolution>` from [rawMap].
Map<String, TdfDeletionResolution> _buildDeletionResolutionMap(Object? rawMap) {
  if (rawMap is! Map<String, Object?>) {
    return const <String, TdfDeletionResolution>{};
  }
  final result = <String, TdfDeletionResolution>{};
  for (final entry in rawMap.entries) {
    if (entry.value case final String rawName) {
      result[entry.key] = TdfDeletionResolution.values.byName(rawName);
    }
  }
  return result;
}

/// Parses a `Map<String, TdfRecoveryResolution>` from [rawMap].
Map<String, TdfRecoveryResolution> _buildRecoveryResolutionMap(Object? rawMap) {
  if (rawMap is! Map<String, Object?>) {
    return const <String, TdfRecoveryResolution>{};
  }
  final result = <String, TdfRecoveryResolution>{};
  for (final entry in rawMap.entries) {
    if (entry.value case final String rawName) {
      result[entry.key] = TdfRecoveryResolution.values.byName(rawName);
    }
  }
  return result;
}

/// Executes `TaskBoardSync.merge` with options decoded from [vector].
TaskBoard _executeMergeCall({
  required Map<String, Object?> vector,
  required TaskBoard primary,
  required TaskBoard secondary,
  required TaskBoard? baseline,
  required DateTime evaluationTime,
  required TdfTimeZoneContext? timeZone,
  required TdfCleanupMode cleanupMode,
}) {
  final acknowledgedGeneration = vector['acknowledgedGeneration'] is int
      ? _requireInt(vector, 'acknowledgedGeneration')
      : null;
  final requireAcknowledged = vector['requireAcknowledgedGeneration'] is bool
      ? _requireBool(vector, 'requireAcknowledgedGeneration')
      : false;
  final pruneDeleted = vector['pruneExpiredDeleted'] is bool
      ? _requireBool(vector, 'pruneExpiredDeleted')
      : true;
  final pruneCompleted = vector['pruneExpiredCompleted'] is bool
      ? _requireBool(vector, 'pruneExpiredCompleted')
      : true;

  return TaskBoardSync.merge(
    primary: primary,
    secondary: secondary,
    baseline: baseline,
    acknowledgedGeneration: acknowledgedGeneration,
    requireAcknowledgedGeneration: requireAcknowledged,
    taskConflictResolutions: _buildDeletionResolutionMap(
      vector['taskConflictResolutions'],
    ),
    labelConflictResolutions: _buildDeletionResolutionMap(
      vector['labelConflictResolutions'],
    ),
    locationConflictResolutions: _buildDeletionResolutionMap(
      vector['locationConflictResolutions'],
    ),
    boundTaskConflictDecisions: _buildBoundTaskDecisions(
      vector['boundTaskConflictDecisions'],
    ),
    boundLabelConflictDecisions: _buildBoundLabelDecisions(
      vector['boundLabelConflictDecisions'],
    ),
    boundLocationConflictDecisions: _buildBoundLocationDecisions(
      vector['boundLocationConflictDecisions'],
    ),
    taskRecoveryResolutions: _buildRecoveryResolutionMap(
      vector['taskRecoveryResolutions'],
    ),
    labelRecoveryResolutions: _buildRecoveryResolutionMap(
      vector['labelRecoveryResolutions'],
    ),
    locationRecoveryResolutions: _buildRecoveryResolutionMap(
      vector['locationRecoveryResolutions'],
    ),
    evaluationTime: evaluationTime,
    timeZone: timeZone,
    cleanupMode: cleanupMode,
    pruneExpiredDeleted: pruneDeleted,
    pruneExpiredCompleted: pruneCompleted,
  );
}

/// Reads and decodes a JSON conformance fixture file from [relativePath].
Map<String, Object?> _loadJsonSuite(String relativePath) {
  final file = File(relativePath);
  expect(
    file.existsSync(),
    isTrue,
    reason: 'Missing conformance fixture suite at $relativePath',
  );
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded case final Map<String, Object?> root) {
    return root;
  }
  throw StateError('Expected top-level JSON object in $relativePath.');
}

/// Constructs an immutable [TaskBoard] snapshot from [map] evaluated at [evaluationTime].
TaskBoard _parseBoard(
  Map<String, Object?> map,
  DateTime evaluationTime, {
  TdfTimeZoneContext? timeZone,
  Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
  String? activeLabelId,
}) {
  final tasks = map['tasks'] is List<Object?>
      ? _parseTaskList(_requireMapList(map, 'tasks'))
      : const <TaskItem>[];
  final labels = map['labels'] is List<Object?>
      ? _parseLabelList(_requireMapList(map, 'labels'))
      : const <TdfLabel>[];
  final locations = map['locations'] is List<Object?>
      ? _parseLocationList(_requireMapList(map, 'locations'))
      : const <TdfLocation>[];
  final deletedBlock = map['deleted'] is Map<String, Object?>
      ? _parseDeletedBlock(_requireMap(map, 'deleted'))
      : TdfDeletedBlock.empty;
  final queueBlock = map['queue'] is Map<String, Object?>
      ? _parseQueueBlock(_requireMap(map, 'queue'))
      : TdfQueueBlock.empty;

  return TaskBoard.evaluate(
    tasks: tasks,
    labels: labels,
    locations: locations,
    deletedBlock: deletedBlock,
    queueBlock: queueBlock,
    evaluationTime: evaluationTime,
    timeZone: timeZone,
    dueLeadWindow: dueLeadWindow,
    activeLabelId: activeLabelId,
  );
}

/// Parses a single [TaskCondition] from [map].
TaskCondition _parseCondition(Map<String, Object?> map) {
  final kind = _requireString(map, 'kind');
  return switch (kind) {
    'globalAny' => const GlobalResetTaskCondition(),
    'groupAny' => GroupResetTaskCondition(
      targetGroup: ConditionGroup.values.byName(_requireString(map, 'group')),
    ),
    'day' =>
      DayTaskCondition.tryFromTokens(_parseStringList(map['days'])) ??
          (throw StateError('Invalid day condition in vector: $map')),
    'time' =>
      TimeWindowTaskCondition.tryParse(
            _requireString(map, 'start'),
            _requireString(map, 'end'),
          ) ??
          (throw StateError('Invalid time condition in vector: $map')),
    'location' => LocationTaskCondition.fromIds(
      _parseStringList(map['locationIds']),
    ),
    _ => throw StateError('Unsupported condition kind: $kind'),
  };
}

/// Parses an ordered list of [TaskCondition] rules from [rawConditions].
List<TaskCondition> _parseConditionList(Object? rawConditions) {
  if (rawConditions is! List<Object?>) {
    return const <TaskCondition>[];
  }
  final result = <TaskCondition>[];
  for (final element in rawConditions) {
    if (element case final Map<String, Object?> conditionMap) {
      result.add(_parseCondition(conditionMap));
    }
  }
  return result;
}

/// Parses a [TdfDeletedBlock] from [map].
TdfDeletedBlock _parseDeletedBlock(Map<String, Object?> map) {
  final generation = map['generation'] is int
      ? _requireInt(map, 'generation')
      : 0;
  final tasks = map['tasks'] is List<Object?>
      ? _parseDeletedTasks(_requireMapList(map, 'tasks'))
      : const <TdfDeletedTaskRecord>[];
  final labels = map['labels'] is List<Object?>
      ? _parseDeletedLabels(_requireMapList(map, 'labels'))
      : const <TdfDeletedLabelRecord>[];
  final locations = map['locations'] is List<Object?>
      ? _parseDeletedLocations(_requireMapList(map, 'locations'))
      : const <TdfDeletedLocationRecord>[];
  return TdfDeletedBlock(
    generation: generation,
    tasks: tasks,
    labels: labels,
    locations: locations,
  );
}

/// Parses [TdfDeletedLabelRecord] items from [items].
List<TdfDeletedLabelRecord> _parseDeletedLabels(
  List<Map<String, Object?>> items,
) {
  return <TdfDeletedLabelRecord>[
    for (final item in items)
      TdfDeletedLabelRecord(
        labelId: _requireString(item, 'id'),
        deletedAt: _parseUtcTimestamp(_requireString(item, 'deletedAt')),
      ),
  ];
}

/// Parses [TdfDeletedLocationRecord] items from [items].
List<TdfDeletedLocationRecord> _parseDeletedLocations(
  List<Map<String, Object?>> items,
) {
  return <TdfDeletedLocationRecord>[
    for (final item in items)
      TdfDeletedLocationRecord(
        locationId: _requireString(item, 'id'),
        deletedAt: _parseUtcTimestamp(_requireString(item, 'deletedAt')),
      ),
  ];
}

/// Parses [TdfDeletedTaskRecord] items from [items].
List<TdfDeletedTaskRecord> _parseDeletedTasks(
  List<Map<String, Object?>> items,
) {
  return <TdfDeletedTaskRecord>[
    for (final item in items)
      TdfDeletedTaskRecord(
        taskId: _requireString(item, 'id'),
        deletedAt: _parseUtcTimestamp(_requireString(item, 'deletedAt')),
        completionsCheckpoint: item['checkpoint'] is int
            ? _requireInt(item, 'checkpoint')
            : 0,
      ),
  ];
}

/// Parses [TdfTaskDependency] items from an optional `blocked` map.
List<TdfTaskDependency> _parseDependencies(Object? rawBlocked) {
  if (rawBlocked is! Map<String, Object?>) {
    return const <TdfTaskDependency>[];
  }
  final result = <TdfTaskDependency>[];
  for (final entry in rawBlocked.entries) {
    final requiredCompletion = entry.value is int ? entry.value as int : 1;
    result.add(
      TdfTaskDependency(
        taskId: entry.key,
        requiredCompletion: requiredCompletion,
      ),
    );
  }
  return TdfTaskDependency.normalizeList(result);
}

/// Parses an optional `dueLeadSeconds` setting (`null` = absent `W_due`, integer seconds otherwise).
Duration? _parseDueLeadWindow(Map<String, Object?> map) {
  if (!map.containsKey('dueLeadSeconds')) {
    return TaskBoardEvaluator.defaultDueLeadWindow;
  }
  final raw = map['dueLeadSeconds'];
  if (raw == null) {
    return null;
  }
  if (raw is int) {
    return Duration(seconds: raw);
  }
  throw StateError('Invalid dueLeadSeconds value: $raw');
}

/// Parses [TaskHistoryEntry] items from [rawHistory].
List<TaskHistoryEntry> _parseHistoryList(Object? rawHistory) {
  if (rawHistory is! List<Object?>) {
    return const <TaskHistoryEntry>[];
  }
  final entries = <TaskHistoryEntry>[];
  for (final element in rawHistory) {
    if (element case final Map<String, Object?> entryMap) {
      entries.add(
        TaskHistoryEntry(
          timestampUtc: _parseUtcTimestamp(
            _requireString(entryMap, 'timestamp'),
          ),
          text: _requireString(entryMap, 'text'),
        ),
      );
    }
  }
  return entries;
}

/// Parses a [TdfLabel] from [map].
TdfLabel _parseLabel(Map<String, Object?> map) {
  final modifiedRaw = map['modified'];
  return TdfLabel(
    id: _requireString(map, 'id'),
    name: _requireString(map, 'name'),
    isScoped: map['scoped'] is bool ? _requireBool(map, 'scoped') : false,
    color: map['color'] is String ? _requireString(map, 'color') : null,
    note: map['note'] is String ? _requireString(map, 'note') : null,
    modifiedAt: modifiedRaw is String ? _parseUtcTimestamp(modifiedRaw) : null,
    links: _parseLinkList(map['links']),
    conditions: _parseConditionList(map['conditions']),
  );
}

/// Parses a list of [TdfLabel] items from [items].
List<TdfLabel> _parseLabelList(List<Map<String, Object?>> items) {
  return <TdfLabel>[for (final item in items) _parseLabel(item)];
}

/// Parses [TaskLink] items from [rawLinks].
List<TaskLink> _parseLinkList(Object? rawLinks) {
  if (rawLinks is! List<Object?>) {
    return const <TaskLink>[];
  }
  final links = <TaskLink>[];
  for (final element in rawLinks) {
    if (element case final Map<String, Object?> linkMap) {
      links.add(
        TaskLink(
          title: _requireString(linkMap, 'title'),
          uri: _requireString(linkMap, 'uri'),
        ),
      );
    }
  }
  return links;
}

/// Parses a local calendar `<YYYY-MM-DD HH:MM[:SS]>` string into a [TdfLocalDateTime].
TdfLocalDateTime _parseLocalTimestamp(String raw) {
  final parsed = TdfLocalDateTime.tryParseInput(raw);
  if (parsed == null) {
    throw StateError('Invalid local timestamp in conformance vector: $raw');
  }
  return parsed;
}

/// Parses a [TdfLocation] from [map].
TdfLocation _parseLocation(Map<String, Object?> map) {
  final latitudeText = _requireString(map, 'latitude');
  final longitudeText = _requireString(map, 'longitude');
  final radiusText = _requireString(map, 'radius');
  final modifiedRaw = map['modified'];
  return TdfLocation(
    id: _requireString(map, 'id'),
    name: _requireString(map, 'name'),
    note: map['note'] is String ? _requireString(map, 'note') : null,
    source: map['source'] is String ? _requireString(map, 'source') : null,
    latitude: double.parse(latitudeText),
    longitude: double.parse(longitudeText),
    radius: double.parse(radiusText),
    modifiedAt: modifiedRaw is String ? _parseUtcTimestamp(modifiedRaw) : null,
    rawLatitudeText: TdfLocation.normalizeDecimalText(latitudeText),
    rawLongitudeText: TdfLocation.normalizeDecimalText(longitudeText),
    rawRadiusText: TdfLocation.normalizeDecimalText(radiusText),
  );
}

/// Parses a list of [TdfLocation] items from [items].
List<TdfLocation> _parseLocationList(List<Map<String, Object?>> items) {
  return <TdfLocation>[for (final item in items) _parseLocation(item)];
}

/// Parses a [TdfQueueBlock] from [map].
TdfQueueBlock _parseQueueBlock(Map<String, Object?> map) {
  final modifiedRaw = map['modified'];
  return TdfQueueBlock(
    modifiedAt: modifiedRaw is String ? _parseUtcTimestamp(modifiedRaw) : null,
    taskIds: _parseStringList(map['taskIds']),
  );
}

/// Parses a [TaskRepeatRule] from [map].
TaskRepeatRule _parseRepeatRule(Map<String, Object?> map) {
  final unitToken = _requireString(map, 'unit');
  final unit = RepeatUnit.tryParseToken(unitToken);
  if (unit == null) {
    throw StateError('Invalid repeat unit in vector: $unitToken');
  }
  final clockRaw = map['clock'];
  final clock = clockRaw is String
      ? (TdfRepeatClock.tryParse(clockRaw) ??
            (throw StateError('Invalid repeat clock in vector: $clockRaw')))
      : TdfRepeatClock.midnight;
  return TaskRepeatRule(
    count: _requireInt(map, 'count'),
    unit: unit,
    clock: clock,
    leadDays: map['leadDays'] is int ? _requireInt(map, 'leadDays') : 0,
  );
}

/// Parses a `List<String>` from [rawList].
List<String> _parseStringList(Object? rawList) {
  if (rawList is! List<Object?>) {
    return const <String>[];
  }
  return <String>[
    for (final element in rawList)
      if (element is String) element,
  ];
}

/// Parses [SubtaskItem] checklist steps from [rawSteps].
List<SubtaskItem> _parseSubtaskSteps(Object? rawSteps) {
  if (rawSteps is! List<Object?>) {
    return const <SubtaskItem>[];
  }
  final steps = <SubtaskItem>[];
  for (final element in rawSteps) {
    if (element case final Map<String, Object?> stepMap) {
      steps.add(
        SubtaskItem(
          title: _requireString(stepMap, 'text'),
          isCompleted: _requireBool(stepMap, 'done'),
        ),
      );
    }
  }
  return steps;
}

/// Parses a [TaskItem] from [map].
TaskItem _parseTask(Map<String, Object?> map) {
  final id = _requireString(map, 'id');
  final title = map['title'] is String
      ? _requireString(map, 'title')
      : 'Task $id';
  final createdAt = map['created'] is String
      ? _parseUtcTimestamp(_requireString(map, 'created'))
      : DateTime.utc(2026, 11, 1, 8, 0, 0);
  final modifiedAt = map['modified'] is String
      ? _parseUtcTimestamp(_requireString(map, 'modified'))
      : null;
  final completedAt = map['finished'] is String
      ? _parseUtcTimestamp(_requireString(map, 'finished'))
      : null;
  final suspendedMap = map['suspended'] is Map<String, Object?>
      ? _requireMap(map, 'suspended')
      : null;
  final dueMap = map['due'] is Map<String, Object?>
      ? _requireMap(map, 'due')
      : null;
  final originMap = map['origin'] is Map<String, Object?>
      ? _requireMap(map, 'origin')
      : null;
  final subtasksMap = map['subtasks'] is Map<String, Object?>
      ? _requireMap(map, 'subtasks')
      : null;

  return TaskItem(
    id: id,
    title: title,
    note: map['note'] is String ? _requireString(map, 'note') : null,
    createdAt: createdAt,
    modifiedAt: modifiedAt,
    completions: map['completions'] is int
        ? _requireInt(map, 'completions')
        : 0,
    isCompleted: completedAt != null,
    completedAt: completedAt,
    isPriority: map['priority'] is bool ? _requireBool(map, 'priority') : false,
    labelIds: _parseStringList(map['labels']),
    isSuspendedForever:
        suspendedMap != null &&
        (suspendedMap['forever'] is bool &&
            _requireBool(suspendedMap, 'forever')),
    suspendedAt: suspendedMap != null && suspendedMap['timestamp'] is String
        ? _parseUtcTimestamp(_requireString(suspendedMap, 'timestamp'))
        : null,
    suspendedNote: suspendedMap != null && suspendedMap['note'] is String
        ? _requireString(suspendedMap, 'note')
        : null,
    dueAt: dueMap != null
        ? _parseUtcTimestamp(_requireString(dueMap, 'timestamp'))
        : null,
    dueAnchor: dueMap != null && dueMap['anchor'] is String
        ? _parseLocalTimestamp(_requireString(dueMap, 'anchor'))
        : null,
    isDuePassive:
        dueMap != null &&
        (dueMap['passive'] is bool && _requireBool(dueMap, 'passive')),
    dueNote: dueMap != null && dueMap['note'] is String
        ? _requireString(dueMap, 'note')
        : null,
    origin: originMap != null
        ? TaskOrigin(
            namespace: _requireString(originMap, 'namespace'),
            externalKey: _requireString(originMap, 'externalKey'),
          )
        : null,
    links: _parseLinkList(map['links']),
    history: _parseHistoryList(map['history']),
    repeatRule: map['repeat'] is Map<String, Object?>
        ? _parseRepeatRule(_requireMap(map, 'repeat'))
        : null,
    dependencies: _parseDependencies(map['blocked']),
    conditions: _parseConditionList(map['conditions']),
    subtasksAutoFinish:
        subtasksMap != null &&
        (subtasksMap['autoFinish'] is bool &&
            _requireBool(subtasksMap, 'autoFinish')),
    subtasks: subtasksMap != null
        ? _parseSubtaskSteps(subtasksMap['steps'])
        : const <SubtaskItem>[],
  );
}

/// Parses a list of [TaskItem] instances from [items].
List<TaskItem> _parseTaskList(List<Map<String, Object?>> items) {
  return <TaskItem>[for (final item in items) _parseTask(item)];
}

/// Parses a [TaskTier] enum value by lowercase name.
TaskTier _parseTaskTier(String rawTier) => TaskTier.values.byName(rawTier);

/// Resolves a [TdfTimeZoneContext] from a vector `timeZone` identifier.
TdfTimeZoneContext _parseTimeZone(String rawZoneId) {
  if (rawZoneId == 'missing') {
    return const TdfTimeZoneContext.missing();
  }
  return TdfTimeZoneContext.named(rawZoneId);
}

/// Parses a TDF UTC `<YYYY-MM-DD HH:MM[:SS]>` string into a UTC [DateTime].
DateTime _parseUtcTimestamp(String raw) {
  final parsed = TaskItem.tryParseTdfTimestampInput(raw);
  if (parsed == null) {
    throw StateError('Invalid UTC timestamp in conformance vector: $raw');
  }
  return parsed;
}

/// Extracts a required `bool` property [key] from [map].
bool _requireBool(Map<String, Object?> map, String key) {
  if (map[key] case final bool value) {
    return value;
  }
  throw StateError('Expected bool "$key" in $map');
}

/// Extracts a required `int` property [key] from [map].
int _requireInt(Map<String, Object?> map, String key) {
  if (map[key] case final int value) {
    return value;
  }
  throw StateError('Expected int "$key" in $map');
}

/// Extracts a required `List<Object?>` property [key] from [map].
List<Object?> _requireList(Map<String, Object?> map, String key) {
  if (map[key] case final List<Object?> value) {
    return value;
  }
  throw StateError('Expected list "$key" in $map');
}

/// Extracts a required `Map<String, Object?>` property [key] from [map].
Map<String, Object?> _requireMap(Map<String, Object?> map, String key) {
  if (map[key] case final Map<String, Object?> value) {
    return value;
  }
  throw StateError('Expected object "$key" in $map');
}

/// Extracts a required list of JSON objects for [key] from [map].
List<Map<String, Object?>> _requireMapList(
  Map<String, Object?> map,
  String key,
) {
  final rawList = _requireList(map, key);
  final result = <Map<String, Object?>>[];
  for (final element in rawList) {
    if (element case final Map<String, Object?> itemMap) {
      result.add(itemMap);
    } else {
      throw StateError('Expected object element in "$key": $element');
    }
  }
  return result;
}

/// Extracts a required `String` property [key] from [map].
String _requireString(Map<String, Object?> map, String key) {
  if (map[key] case final String value) {
    return value;
  }
  throw StateError('Expected string "$key" in $map');
}

/// Executes a cross-zone UTC deferral evaluation and cleanup vector (`TDF-CTX-002`, `TDF-CLEAN-001`).
void _runCrossZoneDeferralVector(Map<String, Object?> vector) {
  final vectorId = _requireString(vector, 'id');
  final evaluationUtc = _parseUtcTimestamp(
    _requireString(vector, 'evaluationUtc'),
  );
  final boardMap = _requireMap(vector, 'board');
  final expectedTiers = _requireMap(vector, 'expectedTiers');
  final expectedCleanedTask = _parseTask(
    _requireMap(vector, 'expectedCleanedTask'),
  );
  final zones = _parseStringList(vector['timeZones']);
  for (final zoneName in zones) {
    _runZoneEvaluationCheck(
      vectorId: vectorId,
      zoneName: zoneName,
      boardMap: boardMap,
      evaluationUtc: evaluationUtc,
      expectedTiers: expectedTiers,
      expectedCleanedTask: expectedCleanedTask,
    );
  }
}

/// Executes a single `downgradeTask` conformance vector (`TDF-MUT-005`).
void _runDowngradeVector(Map<String, Object?> vector) {
  final vectorId = _requireString(vector, 'id');
  final now = _parseUtcTimestamp(_requireString(vector, 'now'));
  final mutationAt = _parseUtcTimestamp(_requireString(vector, 'mutationAt'));
  final timeZone = vector['timeZone'] is String
      ? _parseTimeZone(_requireString(vector, 'timeZone'))
      : TdfTimeZoneContext.utc;
  final dueLeadWindow = _parseDueLeadWindow(vector);
  final activeLabelId = vector['activeLabelId'] is String
      ? _requireString(vector, 'activeLabelId')
      : null;

  final initialBoard = _parseBoard(
    _requireMap(vector, 'board'),
    now,
    timeZone: timeZone,
    dueLeadWindow: dueLeadWindow,
  );
  final downgraded = initialBoard.downgradeTask(
    _requireString(vector, 'targetTaskId'),
    currentDate: mutationAt,
    timeZone: timeZone,
    dueLeadWindow: dueLeadWindow,
    activeLabelId: activeLabelId,
  );
  _assertBoardMatchesExpected(
    downgraded,
    _requireMap(vector, 'expected'),
    contextLabel: vectorId,
  );
}

/// Executes a single `W_due` effective-priority tier evaluation vector (`TDF-CTX-001`, `TDF-EVAL-005`).
void _runDueLeadPriorityVector(Map<String, Object?> vector) {
  final vectorId = _requireString(vector, 'id');
  final now = _parseUtcTimestamp(_requireString(vector, 'now'));
  final timeZone = vector['timeZone'] is String
      ? _parseTimeZone(_requireString(vector, 'timeZone'))
      : TdfTimeZoneContext.utc;
  final dueLeadWindow = _parseDueLeadWindow(vector);
  final activeLabelId = vector['activeLabelId'] is String
      ? _requireString(vector, 'activeLabelId')
      : null;

  if (vector['expectedContextError'] case final String expectedErrorName) {
    final expectedKind = TdfContextOutcomeKind.values.byName(expectedErrorName);
    expect(
      () => _parseBoard(
        _requireMap(vector, 'board'),
        now,
        timeZone: timeZone,
        dueLeadWindow: dueLeadWindow,
        activeLabelId: activeLabelId,
      ),
      throwsA(
        isA<TdfContextException>().having(
          (error) => error.kind,
          'kind',
          expectedKind,
        ),
      ),
      reason: '$vectorId: expected TimeZoneContextRequired',
    );
    return;
  }

  final evaluated = _parseBoard(
    _requireMap(vector, 'board'),
    now,
    timeZone: timeZone,
    dueLeadWindow: dueLeadWindow,
    activeLabelId: activeLabelId,
  );
  _assertBoardMatchesExpected(
    evaluated,
    _requireMap(vector, 'expected'),
    contextLabel: vectorId,
  );
}

/// Executes a single declarative merge conformance vector, asserting commutativity and idempotence.
void _runMergeVector(Map<String, Object?> vector) {
  final vectorId = _requireString(vector, 'id');
  final evaluationTime = _parseUtcTimestamp(_requireString(vector, 'now'));
  final timeZone = vector['timeZone'] is String
      ? _parseTimeZone(_requireString(vector, 'timeZone'))
      : TdfTimeZoneContext.utc;
  final cleanupMode = vector['cleanupMode'] is String
      ? TdfCleanupMode.values.byName(_requireString(vector, 'cleanupMode'))
      : TdfCleanupMode.finalStage;
  final assertCommutative = vector['assertCommutative'] is bool
      ? _requireBool(vector, 'assertCommutative')
      : true;

  final baseline = vector['baseline'] is Map<String, Object?>
      ? _parseBoard(
          _requireMap(vector, 'baseline'),
          evaluationTime,
          timeZone: timeZone,
        )
      : null;
  final leftBoard = _parseBoard(
    _requireMap(vector, 'left'),
    evaluationTime,
    timeZone: timeZone,
  );
  final rightBoard = _parseBoard(
    _requireMap(vector, 'right'),
    evaluationTime,
    timeZone: timeZone,
  );
  _assertVersionComparisonAntisymmetry(leftBoard, rightBoard, vectorId);

  if (vector['expectedTdfError'] case final String expectedErrorName) {
    final expectedKind = TdfErrorKind.values.byName(expectedErrorName);
    expect(
      () => _executeMergeCall(
        vector: vector,
        primary: leftBoard,
        secondary: rightBoard,
        baseline: baseline,
        evaluationTime: evaluationTime,
        timeZone: timeZone,
        cleanupMode: cleanupMode,
      ),
      throwsA(
        isA<TdfException>().having((error) => error.kind, 'kind', expectedKind),
      ),
      reason: '$vectorId: expected TdfException($expectedErrorName)',
    );
    return;
  }

  if (vector['expectedOutcome'] case final Map<String, Object?> outcomeMap) {
    _assertSyncOutcomeMatches(
      () => _executeMergeCall(
        vector: vector,
        primary: leftBoard,
        secondary: rightBoard,
        baseline: baseline,
        evaluationTime: evaluationTime,
        timeZone: timeZone,
        cleanupMode: cleanupMode,
      ),
      outcomeMap,
      contextLabel: '$vectorId (forward)',
    );
    if (assertCommutative) {
      _assertSyncOutcomeMatches(
        () => _executeMergeCall(
          vector: vector,
          primary: rightBoard,
          secondary: leftBoard,
          baseline: baseline,
          evaluationTime: evaluationTime,
          timeZone: timeZone,
          cleanupMode: cleanupMode,
        ),
        outcomeMap,
        contextLabel: '$vectorId (reversed)',
      );
    }
    return;
  }

  final expectedMap = _requireMap(vector, 'expected');
  final forward = _executeMergeCall(
    vector: vector,
    primary: leftBoard,
    secondary: rightBoard,
    baseline: baseline,
    evaluationTime: evaluationTime,
    timeZone: timeZone,
    cleanupMode: cleanupMode,
  );
  _assertBoardMatchesExpected(
    forward,
    expectedMap,
    contextLabel: '$vectorId (forward)',
  );

  if (assertCommutative) {
    final reversed = _executeMergeCall(
      vector: vector,
      primary: rightBoard,
      secondary: leftBoard,
      baseline: baseline,
      evaluationTime: evaluationTime,
      timeZone: timeZone,
      cleanupMode: cleanupMode,
    );
    _assertBoardMatchesExpected(
      reversed,
      expectedMap,
      contextLabel: '$vectorId (reversed)',
    );
    expect(
      forward.allTasks,
      equals(reversed.allTasks),
      reason: '$vectorId: merge(B, L, R) == merge(B, R, L) allTasks',
    );
    expect(
      forward.labels,
      equals(reversed.labels),
      reason: '$vectorId: merge(B, L, R) == merge(B, R, L) labels',
    );
    expect(
      forward.locations,
      equals(reversed.locations),
      reason: '$vectorId: merge(B, L, R) == merge(B, R, L) locations',
    );
    expect(
      forward.deletedBlock,
      equals(reversed.deletedBlock),
      reason: '$vectorId: merge(B, L, R) == merge(B, R, L) deletedBlock',
    );
    expect(
      forward.queueBlock,
      equals(reversed.queueBlock),
      reason: '$vectorId: merge(B, L, R) == merge(B, R, L) queueBlock',
    );
  }

  if (cleanupMode == TdfCleanupMode.finalStage) {
    final idempotent = TaskBoardSync.merge(
      primary: forward,
      secondary: forward,
      baseline: forward,
      evaluationTime: evaluationTime,
      timeZone: timeZone,
      cleanupMode: TdfCleanupMode.finalStage,
    );
    expect(
      idempotent.allTasks,
      equals(forward.allTasks),
      reason: '$vectorId: idempotence merge(M, M, M) == M',
    );
    expect(
      idempotent.deletedBlock,
      equals(forward.deletedBlock),
      reason: '$vectorId: idempotence deletedBlock',
    );
    expect(
      idempotent.queueBlock,
      equals(forward.queueBlock),
      reason: '$vectorId: idempotence queueBlock',
    );
  }
}

/// Applies a single Mode 2 completion step to [board] and verifies both `TaskRepeatRule` and `TaskBoard.completeTask`.
TaskBoard _runMode2RecurrenceStep({
  required String vectorId,
  required int stepIndex,
  required TaskBoard board,
  required String taskId,
  required TdfTimeZoneContext timeZone,
  required Map<String, Object?> stepMap,
}) {
  final completedAtUtc = _parseUtcTimestamp(
    _requireString(stepMap, 'completedAtUtc'),
  );
  var workingBoard = board;
  if (stepMap['updatedRepeat'] case final Map<String, Object?> newRepeatMap) {
    workingBoard = workingBoard.updateTask(
      taskId,
      repeatRule: _parseRepeatRule(newRepeatMap),
      currentDate: completedAtUtc.subtract(const Duration(minutes: 1)),
      timeZone: timeZone,
    );
  }
  final beforeTask = workingBoard.findTask(taskId);
  if (beforeTask == null ||
      beforeTask.repeatRule == null ||
      beforeTask.dueAt == null) {
    throw StateError('$vectorId step $stepIndex: missing recurring due task');
  }
  final repeatRule = beforeTask.repeatRule;
  final oldDueAt = beforeTask.dueAt;
  if (repeatRule == null || oldDueAt == null) {
    throw StateError('$vectorId step $stepIndex: unexpected null schedule');
  }

  final directCalc = repeatRule.computeNextMode2Schedule(
    completedAtUtc: completedAtUtc,
    oldDueUtc: oldDueAt,
    oldAnchor: beforeTask.dueAnchor,
    timeZone: timeZone,
  );
  final expectedDueUtc = _parseUtcTimestamp(
    _requireString(stepMap, 'expectedDueUtc'),
  );
  final expectedAnchor = _parseLocalTimestamp(
    _requireString(stepMap, 'expectedDueAnchor'),
  );
  final expectedSuspendedUtc = stepMap['expectedSuspendedUtc'] is String
      ? _parseUtcTimestamp(_requireString(stepMap, 'expectedSuspendedUtc'))
      : null;

  expect(
    directCalc.stepsK,
    equals(_requireInt(stepMap, 'expectedStepsK')),
    reason: '$vectorId step $stepIndex: stepsK',
  );
  expect(
    directCalc.newDueUtc,
    equals(expectedDueUtc),
    reason: '$vectorId step $stepIndex: computeNextMode2Schedule newDueUtc',
  );
  expect(
    directCalc.newAnchor,
    equals(expectedAnchor),
    reason: '$vectorId step $stepIndex: computeNextMode2Schedule newAnchor',
  );
  expect(
    directCalc.newSuspendedUtc,
    equals(expectedSuspendedUtc),
    reason:
        '$vectorId step $stepIndex: computeNextMode2Schedule newSuspendedUtc',
  );

  final afterBoard = workingBoard.completeTask(
    taskId,
    currentDate: completedAtUtc,
    timeZone: timeZone,
    expectedCompletions: beforeTask.completions,
  );
  final afterTask = afterBoard.findTask(taskId);
  expect(
    afterTask,
    isNotNull,
    reason: '$vectorId step $stepIndex: recurring task must remain live',
  );
  if (afterTask == null) {
    return afterBoard;
  }
  expect(
    afterTask.completions,
    equals(beforeTask.completions + 1),
    reason: '$vectorId step $stepIndex: completions incremented by 1',
  );
  expect(
    afterTask.dueAt,
    equals(expectedDueUtc),
    reason: '$vectorId step $stepIndex: completeTask dueAt',
  );
  expect(
    afterTask.dueAnchor,
    equals(expectedAnchor),
    reason: '$vectorId step $stepIndex: completeTask dueAnchor',
  );
  expect(
    afterTask.suspendedAt,
    equals(expectedSuspendedUtc),
    reason: '$vectorId step $stepIndex: completeTask suspendedAt',
  );
  expect(
    afterTask.isDuePassive,
    equals(_requireBool(stepMap, 'expectedDuePassive')),
    reason: '$vectorId step $stepIndex: isDuePassive reset',
  );
  expect(
    afterTask.dueNote,
    equals(stepMap['expectedDueNote']),
    reason: '$vectorId step $stepIndex: dueNote preserved',
  );
  expect(
    afterTask.suspendedNote,
    isNull,
    reason: '$vectorId step $stepIndex: suspendedNote cleared',
  );
  expect(
    afterTask.history,
    equals(beforeTask.history),
    reason: '$vectorId step $stepIndex: history preserved across recurrence',
  );
  expect(
    afterTask.origin,
    equals(beforeTask.origin),
    reason: '$vectorId step $stepIndex: origin preserved across recurrence',
  );
  return afterBoard;
}

/// Executes a multi-step Mode 2 recurrence conformance vector and optional direct `k = 2` commutation check.
void _runMode2RecurrenceVector(Map<String, Object?> vector) {
  final vectorId = _requireString(vector, 'id');
  final timeZone = _parseTimeZone(_requireString(vector, 'timeZone'));
  final initialTask = _parseTask(_requireMap(vector, 'initialTask'));
  final initialEvaluationUtc = _parseUtcTimestamp(
    _requireString(vector, 'initialEvaluationUtc'),
  );
  final initialBoard = TaskBoard.evaluate(
    tasks: <TaskItem>[initialTask],
    queueBlock: TdfQueueBlock(
      modifiedAt: initialTask.createdAt,
      taskIds: <String>[initialTask.id],
    ),
    evaluationTime: initialEvaluationUtc,
    timeZone: timeZone,
  );

  var currentBoard = initialBoard;
  final steps = _requireMapList(vector, 'steps');
  for (var i = 0; i < steps.length; i++) {
    currentBoard = _runMode2RecurrenceStep(
      vectorId: vectorId,
      stepIndex: i + 1,
      board: currentBoard,
      taskId: initialTask.id,
      timeZone: timeZone,
      stepMap: steps[i],
    );
  }

  if (vector['directJumpStep'] case final Map<String, Object?> directStepMap) {
    final directBoard = _runMode2RecurrenceStep(
      vectorId: '$vectorId (directJump)',
      stepIndex: 1,
      board: initialBoard,
      taskId: initialTask.id,
      timeZone: timeZone,
      stepMap: directStepMap,
    );
    final sequentialTask = currentBoard.findTask(initialTask.id);
    final directTask = directBoard.findTask(initialTask.id);
    expect(
      directTask?.dueAt,
      equals(sequentialTask?.dueAt),
      reason: '$vectorId: direct jump dueAt must equal sequential progression',
    );
    expect(
      directTask?.dueAnchor,
      equals(sequentialTask?.dueAnchor),
      reason:
          '$vectorId: direct jump dueAnchor must equal sequential progression',
    );
    expect(
      directTask?.suspendedAt,
      equals(sequentialTask?.suspendedAt),
      reason:
          '$vectorId: direct jump suspendedAt must equal sequential progression',
    );
  }
}

/// Executes a multi-stage synchronization fairness vector (`TDF-MERGE-009`, `TDF-PUB-003`).
void _runMultiStageVector(Map<String, Object?> vector) {
  final vectorId = _requireString(vector, 'id');
  final now = _parseUtcTimestamp(_requireString(vector, 'now'));
  final baseline = _parseBoard(_requireMap(vector, 'baseline'), now);
  final localInput = _parseBoard(_requireMap(vector, 'localInput'), now);
  final stage1Other = _parseBoard(_requireMap(vector, 'stage1Other'), now);
  final remoteBoard = _parseBoard(_requireMap(vector, 'remoteBoard'), now);

  final stage1Deferred = TaskBoardSync.merge(
    primary: localInput,
    secondary: stage1Other,
    baseline: baseline,
    evaluationTime: now,
    cleanupMode: TdfCleanupMode.deferred,
  );
  _assertBoardMatchesExpected(
    stage1Deferred,
    _requireMap(vector, 'expectedStage1Deferred'),
    contextLabel: '$vectorId (stage1 deferred)',
  );

  final stage1Reversed = TaskBoardSync.merge(
    primary: stage1Other,
    secondary: localInput,
    baseline: baseline,
    evaluationTime: now,
    cleanupMode: TdfCleanupMode.deferred,
  );
  expect(
    stage1Deferred.allTasks,
    equals(stage1Reversed.allTasks),
    reason: '$vectorId: stage1 deferred commutativity',
  );

  final stage2Baseline = vector['stage2UsesStage1OtherAsBaseline'] == true
      ? stage1Other
      : baseline;
  final stage2Final = TaskBoardSync.merge(
    primary: stage1Deferred,
    secondary: remoteBoard,
    baseline: stage2Baseline,
    evaluationTime: now,
    cleanupMode: TdfCleanupMode.finalStage,
  );
  final stage2FinalReversed = TaskBoardSync.merge(
    primary: remoteBoard,
    secondary: stage1Deferred,
    baseline: stage2Baseline,
    evaluationTime: now,
    cleanupMode: TdfCleanupMode.finalStage,
  );
  _assertBoardMatchesExpected(
    stage2Final,
    _requireMap(vector, 'expectedStage2Final'),
    contextLabel: '$vectorId (stage2 final)',
  );
  expect(
    stage2Final.allTasks,
    equals(stage2FinalReversed.allTasks),
    reason: '$vectorId: stage2 final commutativity',
  );

  if (vector['assertMatchesDirectThreeWay'] == true) {
    final directFinal = TaskBoardSync.merge(
      primary: localInput,
      secondary: remoteBoard,
      baseline: baseline,
      evaluationTime: now,
      cleanupMode: TdfCleanupMode.finalStage,
    );
    expect(
      stage2Final.allTasks,
      equals(directFinal.allTasks),
      reason: '$vectorId: deferred->final must match direct merge(B, L, R)',
    );
  }
}

/// Executes a single local-to-UTC point conversion vector (`TDF-CAL-001`, `TDF-CTX-001`).
void _runPointConversionVector(Map<String, Object?> vector) {
  final vectorId = _requireString(vector, 'id');
  final timeZone = _parseTimeZone(_requireString(vector, 'timeZone'));
  final localInput = _parseLocalTimestamp(_requireString(vector, 'localInput'));

  if (vector['expectedContextError'] case final String expectedErrorName) {
    final expectedKind = TdfContextOutcomeKind.values.byName(expectedErrorName);
    expect(
      () => timeZone.resolveLocalToUtc(
        localInput.year,
        localInput.month,
        localInput.day,
        localInput.hour,
        localInput.minute,
        localInput.second,
      ),
      throwsA(
        isA<TdfContextException>().having(
          (error) => error.kind,
          'kind',
          expectedKind,
        ),
      ),
      reason: '$vectorId: missing timeZone must throw TimeZoneContextRequired',
    );
    return;
  }

  final resolvedUtc = timeZone.resolveLocalToUtc(
    localInput.year,
    localInput.month,
    localInput.day,
    localInput.hour,
    localInput.minute,
    localInput.second,
  );
  final expectedUtc = _parseUtcTimestamp(_requireString(vector, 'expectedUtc'));
  final expectedResolvedLocal = _parseLocalTimestamp(
    _requireString(vector, 'expectedResolvedLocal'),
  );
  final actualResolvedLocal = TdfLocalDateTime.fromWallClock(
    timeZone.toLocalWallClock(resolvedUtc),
  );

  expect(
    resolvedUtc,
    equals(expectedUtc),
    reason: '$vectorId: resolveLocalToUtc instant mismatch',
  );
  expect(
    actualResolvedLocal,
    equals(expectedResolvedLocal),
    reason: '$vectorId: toLocalWallClock resolved wall time mismatch',
  );
}

/// Executes a `TDF-REC-002` recovery resolution vector (`discard` + `recoverAsNew` ID rewriting).
void _runRecoveryResolutionVector(Map<String, Object?> vector) {
  final vectorId = _requireString(vector, 'id');
  final now = _parseUtcTimestamp(_requireString(vector, 'now'));
  final localBoard = _parseBoard(_requireMap(vector, 'localBoard'), now);
  final sharedBoard = _parseBoard(_requireMap(vector, 'sharedBoard'), now);
  final taskResolutions = _buildRecoveryResolutionMap(
    vector['taskRecoveryResolutions'],
  );
  final labelResolutions = _buildRecoveryResolutionMap(
    vector['labelRecoveryResolutions'],
  );
  final locationResolutions = _buildRecoveryResolutionMap(
    vector['locationRecoveryResolutions'],
  );

  final recovered = TaskBoardSync.recoverAmbiguousEntities(
    localBoard: localBoard,
    sharedBoard: sharedBoard,
    taskRecoveryResolutions: taskResolutions,
    labelRecoveryResolutions: labelResolutions,
    locationRecoveryResolutions: locationResolutions,
    evaluationTime: now,
  );

  expect(
    recovered.deletedBlock.generation,
    equals(_requireInt(vector, 'expectedGeneration')),
    reason: '$vectorId: adopted generation',
  );
  for (final discardedTaskId in _parseStringList(vector['discardedTaskIds'])) {
    expect(
      recovered.findTask(discardedTaskId),
      isNull,
      reason: '$vectorId: discarded task $discardedTaskId must be absent',
    );
  }
  for (final discardedLabelId in _parseStringList(
    vector['discardedLabelIds'],
  )) {
    expect(
      recovered.findLabel(discardedLabelId),
      isNull,
      reason: '$vectorId: discarded label $discardedLabelId must be absent',
    );
  }
  for (final discardedLocationId in _parseStringList(
    vector['discardedLocationIds'],
  )) {
    expect(
      recovered.findLocation(discardedLocationId),
      isNull,
      reason:
          '$vectorId: discarded location $discardedLocationId must be absent',
    );
  }

  final oldKeepLocationId = _requireString(vector, 'recoveredOldLocationId');
  final oldKeepLabelId = _requireString(vector, 'recoveredOldLabelId');
  final oldKeepTaskId = _requireString(vector, 'recoveredOldTaskId');
  final sharedTaskId = _requireString(vector, 'sharedOpenTaskId');

  expect(
    recovered.locations.length,
    equals(1),
    reason: '$vectorId: exactly 1 recovered location expected',
  );
  final newLocation = recovered.locations.single;
  expect(
    isValidLocationId(newLocation.id) && newLocation.id != oldKeepLocationId,
    isTrue,
    reason: '$vectorId: recovered location must receive fresh Base62 ID',
  );

  expect(
    recovered.labels.length,
    equals(1),
    reason: '$vectorId: exactly 1 recovered label expected',
  );
  final newLabel = recovered.labels.single;
  expect(
    isValidLabelId(newLabel.id) && newLabel.id != oldKeepLabelId,
    isTrue,
    reason: '$vectorId: recovered label must receive fresh Base62 ID',
  );
  expect(
    newLabel.conditions,
    equals(<TaskCondition>[
      LocationTaskCondition(locationIds: <String>[newLocation.id]),
    ]),
    reason: '$vectorId: recovered label must rewrite location condition ID',
  );

  final recoveredTask = recovered.allTasks.firstWhere(
    (task) => task.id != sharedTaskId,
  );
  expect(
    isValidTaskId(recoveredTask.id) && recoveredTask.id != oldKeepTaskId,
    isTrue,
    reason: '$vectorId: recovered task must receive fresh Base62 ID',
  );
  expect(
    recoveredTask.dueAnchor,
    equals(
      _parseLocalTimestamp(_requireString(vector, 'expectedRecoveredAnchor')),
    ),
    reason: '$vectorId: recovered task must preserve dueAnchor',
  );
  expect(
    recoveredTask.history,
    equals(_parseHistoryList(vector['expectedRecoveredHistory'])),
    reason: '$vectorId: recovered task must preserve history',
  );
  expect(
    recoveredTask.labelIds,
    equals(<String>[newLabel.id]),
    reason: '$vectorId: recovered task must rewrite labelIds',
  );
  expect(
    recoveredTask.dependencies,
    isEmpty,
    reason: '$vectorId: recovered open task must strip discarded blocked ref',
  );
  expect(
    recoveredTask.conditions,
    equals(<TaskCondition>[
      LocationTaskCondition(locationIds: <String>[newLocation.id]),
    ]),
    reason: '$vectorId: recovered task must rewrite location condition ID',
  );

  final sharedAfter = recovered.findTask(sharedTaskId);
  expect(sharedAfter, isNotNull, reason: '$vectorId: shared task preserved');
  if (sharedAfter == null) {
    return;
  }
  expect(
    sharedAfter.labelIds,
    equals(<String>[newLabel.id]),
    reason: '$vectorId: shared task must rewrite recovered labelId',
  );
  expect(
    sharedAfter.dependencies,
    equals(<TdfTaskDependency>[
      TdfTaskDependency(taskId: recoveredTask.id, requiredCompletion: 1),
    ]),
    reason:
        '$vectorId: shared open task must rewrite kept blocker and strip discarded blocker',
  );
  expect(
    recovered.queueBlock.taskIds,
    equals(<String>[sharedTaskId, recoveredTask.id]),
    reason: '$vectorId: queue must replace old task ID with fresh Base62 ID',
  );
}

/// Executes a single `restoreTask` conformance vector (`TDF-MUT-007`).
void _runRestoreVector(Map<String, Object?> vector) {
  final vectorId = _requireString(vector, 'id');
  final now = _parseUtcTimestamp(_requireString(vector, 'now'));
  final mutationAt = _parseUtcTimestamp(_requireString(vector, 'mutationAt'));
  final targetTier = _parseTaskTier(_requireString(vector, 'targetTier'));
  final initialBoard = _parseBoard(_requireMap(vector, 'board'), now);

  final restored = initialBoard.restoreTask(
    _requireString(vector, 'targetTaskId'),
    targetTier: targetTier,
    currentDate: mutationAt,
  );
  _assertBoardMatchesExpected(
    restored,
    _requireMap(vector, 'expected'),
    contextLabel: vectorId,
  );
}

/// Evaluates and cleans a single cross-zone deferral check in [zoneName].
void _runZoneEvaluationCheck({
  required String vectorId,
  required String zoneName,
  required Map<String, Object?> boardMap,
  required DateTime evaluationUtc,
  required Map<String, Object?> expectedTiers,
  required TaskItem expectedCleanedTask,
}) {
  final zone = _parseTimeZone(zoneName);
  final evaluated = _parseBoard(boardMap, evaluationUtc, timeZone: zone);
  _assertTierIdsMatch(
    evaluated,
    expectedTiers,
    '$vectorId ($zoneName pure eval)',
  );

  final cleaned = TaskBoardSync.stampAndNormalize(
    evaluated,
    evaluationTime: evaluationUtc,
    timeZone: zone,
    cleanupMode: TdfCleanupMode.finalStage,
  );
  _assertSingleExpectedTask(
    cleaned,
    expectedCleanedTask,
    '$vectorId ($zoneName finalStage cleanup)',
  );
}
