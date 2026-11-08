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
import 'package:tiertask/models/task_board_sync.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';

DateTime _parseIsoUtc(String raw) => DateTime.parse(raw).toUtc();

TaskItem _buildTaskFromVectorMap(Map<String, Object?> map) {
  final id = map['id'] as String;
  final modifiedRaw = map['modified'] as String?;
  final originMap = map['origin'] as Map<String, Object?>?;
  final repeatMap = map['repeat'] as Map<String, Object?>?;
  final blockedMap = map['blocked'] as Map<String, Object?>?;
  final subtasksMap = map['subtasks'] as Map<String, Object?>?;
  final suspendedRaw = map['suspended'] as String?;
  final dueRaw = map['due'] as String?;
  final finishedRaw = map['finished'] as String?;

  return TaskItem(
    id: id,
    title: 'Task $id',
    createdAt: DateTime.utc(2026, 11, 1, 8, 0, 0),
    modifiedAt: modifiedRaw != null ? _parseIsoUtc(modifiedRaw) : null,
    completions: (map['completions'] as int?) ?? 0,
    isCompleted: finishedRaw != null,
    completedAt: finishedRaw != null ? _parseIsoUtc(finishedRaw) : null,
    isPriority: (map['priority'] as bool?) ?? false,
    suspendedAt: suspendedRaw != null ? _parseIsoUtc(suspendedRaw) : null,
    dueAt: dueRaw != null ? _parseIsoUtc(dueRaw) : null,
    origin: originMap != null
        ? TaskOrigin(
            namespace: originMap['namespace'] as String,
            externalKey: originMap['externalKey'] as String,
          )
        : null,
    repeatRule: repeatMap != null
        ? TaskRepeatRule(
            count: repeatMap['count'] as int,
            unit: RepeatUnit.values.byName(repeatMap['unit'] as String),
          )
        : null,
    dependencies: [
      if (blockedMap != null)
        for (final entry in blockedMap.entries)
          TdfTaskDependency(
            taskId: entry.key,
            requiredCompletion: (entry.value as int?) ?? 1,
          ),
    ],
    subtasksAutoFinish: subtasksMap != null
        ? (subtasksMap['autoFinish'] as bool)
        : true,
    subtasks: [
      if (subtasksMap != null)
        for (final step
            in (subtasksMap['steps'] as List<Object?>)
                .cast<Map<String, Object?>>())
          SubtaskItem(
            title: step['text'] as String,
            isCompleted: step['done'] as bool,
          ),
    ],
  );
}

TdfLocation _buildLocationFromVectorMap(Map<String, Object?> map) {
  final coords = map['coordinates'] as Map<String, Object?>;
  final latStr = coords['latitude'] as String;
  final lonStr = coords['longitude'] as String;
  final radStr = map['radius'] as String;
  return TdfLocation(
    id: map['id'] as String,
    name: map['name'] as String,
    source: map['source'] as String?,
    latitude: double.parse(latStr),
    longitude: double.parse(lonStr),
    radius: double.parse(radStr),
    rawLatitudeText: latStr,
    rawLongitudeText: lonStr,
    rawRadiusText: radStr,
    modifiedAt: _parseIsoUtc(map['modified'] as String),
  );
}

List<TaskCondition> _parseVectorCondition(Object? raw) {
  if (raw == null) return const [];
  if (raw == 'condition location any') {
    return const [
      GroupResetTaskCondition(targetGroup: ConditionGroup.location),
    ];
  }
  final map = raw as Map<String, Object?>;
  final locationIds = (map['locationIds'] as List<Object?>).cast<String>();
  return [LocationTaskCondition(locationIds: locationIds)];
}

void main() {
  final rawJson = File('spec/conformance/v0.6.0/merge/vectors.json')
      .readAsStringSync();
  final decoded = jsonDecode(rawJson) as Map<String, Object?>;
  final vectors = (decoded['vectors'] as List<Object?>)
      .cast<Map<String, Object?>>();
  final vectorsById = <String, Map<String, Object?>>{
    for (final vector in vectors) vector['id'] as String: vector,
  };
  final evalTime = DateTime.utc(2026, 11, 2, 12, 0, 0);

  group('TDF 0.6.0 Three-Way Merge Conformance Vectors', () {
    test('merge_01_atomic_origin_pair merges (namespace, externalKey) atomically and commutatively', () {
      final vector = vectorsById['merge_01_atomic_origin_pair']!;
      final baseTask = _buildTaskFromVectorMap(
        vector['baseline'] as Map<String, Object?>,
      );
      final leftTask = _buildTaskFromVectorMap(
        vector['left'] as Map<String, Object?>,
      );
      final rightTask = _buildTaskFromVectorMap(
        vector['right'] as Map<String, Object?>,
      );
      final expectedTask = _buildTaskFromVectorMap(
        vector['expected'] as Map<String, Object?>,
      );

      final baseBoard = TaskBoard.evaluate(
        tasks: [baseTask],
        evaluationTime: evalTime,
      );
      final leftBoard = TaskBoard.evaluate(
        tasks: [leftTask],
        evaluationTime: evalTime,
      );
      final rightBoard = TaskBoard.evaluate(
        tasks: [rightTask],
        evaluationTime: evalTime,
      );

      for (final (direction, first, second) in [
        ('forward', leftBoard, rightBoard),
        ('reverse', rightBoard, leftBoard),
      ]) {
        final merged = TaskBoardSync.merge(
          primary: first,
          secondary: second,
          baseline: baseBoard,
          evaluationTime: evalTime,
        ).findTask(expectedTask.id)!;
        expect(
          merged.origin,
          equals(expectedTask.origin),
          reason: 'Origin pair mismatch ($direction)',
        );
        expect(
          merged.modifiedAt,
          equals(expectedTask.modifiedAt),
          reason: 'Modified timestamp mismatch ($direction)',
        );
      }
    });

    test('merge_02_same_occurrence_unbundling unbundles priority, suspended, due, repeat, blocked, and subtasks', () {
      final vector = vectorsById['merge_02_same_occurrence_unbundling']!;
      const prereq1 = '3nQp7ROkB8';
      const prereq2 = '5vWx9ZOk91';
      final prereqs = [
        TaskItem(
          id: prereq1,
          title: 'Prereq 1',
          createdAt: DateTime.utc(2026, 11, 1, 8, 0, 0),
          completions: 1,
        ),
        TaskItem(
          id: prereq2,
          title: 'Prereq 2',
          createdAt: DateTime.utc(2026, 11, 1, 8, 0, 0),
          completions: 2,
        ),
      ];
      final baseTask = _buildTaskFromVectorMap(
        vector['baseline'] as Map<String, Object?>,
      );
      final leftTask = _buildTaskFromVectorMap(
        vector['left'] as Map<String, Object?>,
      );
      final rightTask = _buildTaskFromVectorMap(
        vector['right'] as Map<String, Object?>,
      );
      final expectedTask = _buildTaskFromVectorMap(
        vector['expected'] as Map<String, Object?>,
      );

      final baseBoard = TaskBoard.evaluate(
        tasks: [...prereqs, baseTask],
        evaluationTime: evalTime,
      );
      final leftBoard = TaskBoard.evaluate(
        tasks: [...prereqs, leftTask],
        evaluationTime: evalTime,
      );
      final rightBoard = TaskBoard.evaluate(
        tasks: [...prereqs, rightTask],
        evaluationTime: evalTime,
      );

      for (final (direction, first, second) in [
        ('forward', leftBoard, rightBoard),
        ('reverse', rightBoard, leftBoard),
      ]) {
        final merged = TaskBoardSync.merge(
          primary: first,
          secondary: second,
          baseline: baseBoard,
          evaluationTime: evalTime,
        ).findTask(expectedTask.id)!;
        expect(
          merged.isPriority,
          equals(expectedTask.isPriority),
          reason: direction,
        );
        expect(
          merged.suspendedAt,
          equals(expectedTask.suspendedAt),
          reason: direction,
        );
        expect(merged.dueAt, equals(expectedTask.dueAt), reason: direction);
        expect(
          merged.repeatRule,
          equals(expectedTask.repeatRule),
          reason: direction,
        );
        expect(
          merged.dependencies,
          equals(expectedTask.dependencies),
          reason: direction,
        );
        expect(
          merged.subtasks,
          equals(expectedTask.subtasks),
          reason: direction,
        );
        expect(
          merged.modifiedAt,
          equals(expectedTask.modifiedAt),
          reason: direction,
        );
      }
    });

    test('merge_03_coupled_location_coordinates_and_source merges (coordinates, source) atomically with independent radius', () {
      final vector =
          vectorsById['merge_03_coupled_location_coordinates_and_source']!;
      final baseLoc = _buildLocationFromVectorMap(
        vector['baseline'] as Map<String, Object?>,
      );
      final leftLoc = _buildLocationFromVectorMap(
        vector['left'] as Map<String, Object?>,
      );
      final rightLoc = _buildLocationFromVectorMap(
        vector['right'] as Map<String, Object?>,
      );
      final expectedLoc = _buildLocationFromVectorMap(
        vector['expected'] as Map<String, Object?>,
      );

      final baseBoard = TaskBoard.evaluate(
        tasks: const [],
        locations: [baseLoc],
        evaluationTime: evalTime,
      );
      final leftBoard = TaskBoard.evaluate(
        tasks: const [],
        locations: [leftLoc],
        evaluationTime: evalTime,
      );
      final rightBoard = TaskBoard.evaluate(
        tasks: const [],
        locations: [rightLoc],
        evaluationTime: evalTime,
      );

      for (final (direction, first, second) in [
        ('forward', leftBoard, rightBoard),
        ('reverse', rightBoard, leftBoard),
      ]) {
        final merged = TaskBoardSync.merge(
          primary: first,
          secondary: second,
          baseline: baseBoard,
          evaluationTime: evalTime,
        ).findLocation(expectedLoc.id)!;
        expect(
          merged.source,
          isNull,
          reason: 'Coupled source must be cleared ($direction)',
        );
        expect(
          merged.latitudeText,
          equals(expectedLoc.latitudeText),
          reason: direction,
        );
        expect(
          merged.longitudeText,
          equals(expectedLoc.longitudeText),
          reason: direction,
        );
        expect(
          merged.radiusText,
          equals(expectedLoc.radiusText),
          reason: direction,
        );
        expect(
          merged.modifiedAt,
          equals(expectedLoc.modifiedAt),
          reason: direction,
        );
      }
    });

    test('merge_04_location_deletion_cascade_inheritance_trap handles cases A, B, and C commutatively', () {
      final vector =
          vectorsById['merge_04_location_deletion_cascade_inheritance_trap']!;
      const locOverride = TdfLocation(
        id: 'LocOverOk1',
        name: 'Override',
        latitude: 48.0,
        longitude: 11.0,
        radius: 100.0,
      );
      const locHome = TdfLocation(
        id: 'LocHomeOk2',
        name: 'Home',
        latitude: 49.0,
        longitude: 12.0,
        radius: 100.0,
      );
      const labelId = '4x9p2mOkD2';
      const taskId = '8jKaCdOkD2';

      // Case A: label retains location, task override location deleted -> condition location any
      const labelWithHome = TdfLabel(
        id: labelId,
        name: 'Work',
        conditions: [
          LocationTaskCondition(locationIds: ['LocHomeOk2']),
        ],
      );
      final taskBeforeA = TaskItem(
        id: taskId,
        title: 'Task A',
        createdAt: DateTime.utc(2026, 11, 1, 8, 0, 0),
        modifiedAt: DateTime.utc(2026, 11, 1, 9, 0, 0),
        labelIds: const [labelId],
        conditions: const [
          LocationTaskCondition(locationIds: ['LocOverOk1']),
        ],
      );
      final baseA = TaskBoard.evaluate(
        tasks: [taskBeforeA],
        labels: const [labelWithHome],
        locations: const [locOverride, locHome],
        evaluationTime: evalTime,
      );
      final remoteDeletedOverride = TaskBoard.evaluate(
        tasks: [
          taskBeforeA.copyWith(
            conditions: const [
              GroupResetTaskCondition(targetGroup: ConditionGroup.location),
            ],
            modifiedAt: DateTime.utc(2026, 11, 1, 10, 0, 0),
          ),
        ],
        labels: const [labelWithHome],
        locations: const [locHome],
        deletedBlock: TdfDeletedBlock(
          generation: 0,
          locations: [
            TdfDeletedLocationRecord(
              locationId: 'LocOverOk1',
              deletedAt: DateTime.utc(2026, 11, 1, 10, 0, 0),
            ),
          ],
        ),
        evaluationTime: evalTime,
      );
      for (final (first, second) in [
        (baseA, remoteDeletedOverride),
        (remoteDeletedOverride, baseA),
      ]) {
        final mergedA = TaskBoardSync.merge(
          primary: first,
          secondary: second,
          baseline: baseA,
          evaluationTime: evalTime,
        ).findTask(taskId)!;
        expect(
          mergedA.conditions,
          equals(const [
            GroupResetTaskCondition(targetGroup: ConditionGroup.location),
          ]),
        );
      }

      // Case B: label also loses its only location -> task omits condition
      const labelWithShared = TdfLabel(
        id: labelId,
        name: 'Work',
        conditions: [
          LocationTaskCondition(locationIds: ['LocOverOk1']),
        ],
      );
      final baseB = TaskBoard.evaluate(
        tasks: [taskBeforeA],
        labels: const [labelWithShared],
        locations: const [locOverride],
        evaluationTime: evalTime,
      );
      final remoteDeletedShared = TaskBoard.evaluate(
        tasks: [
          taskBeforeA.copyWith(
            conditions: const [],
            modifiedAt: DateTime.utc(2026, 11, 1, 10, 0, 0),
          ),
        ],
        labels: [labelWithShared.copyWith(conditions: const [])],
        locations: const [],
        deletedBlock: TdfDeletedBlock(
          generation: 0,
          locations: [
            TdfDeletedLocationRecord(
              locationId: 'LocOverOk1',
              deletedAt: DateTime.utc(2026, 11, 1, 10, 0, 0),
            ),
          ],
        ),
        evaluationTime: evalTime,
      );
      for (final (first, second) in [
        (baseB, remoteDeletedShared),
        (remoteDeletedShared, baseB),
      ]) {
        final mergedB = TaskBoardSync.merge(
          primary: first,
          secondary: second,
          baseline: baseB,
          evaluationTime: evalTime,
        ).findTask(taskId)!;
        expect(mergedB.conditions, isEmpty);
      }

      // Case C: L explicitly cleared condition (null) while R deleted LocOverOk1 (inserting location any) -> L's explicit removal wins!
      final caseC =
          vector['caseC_three_way_explicit_rule_removal_wins_over_cascade']
              as Map<String, Object?>;
      expect(_parseVectorCondition(caseC['expectedTaskCondition']), isEmpty);
      final leftExplicitClear = TaskBoard.evaluate(
        tasks: [
          taskBeforeA.copyWith(
            conditions: const [],
            modifiedAt: DateTime.utc(2026, 11, 1, 9, 30, 0),
          ),
        ],
        labels: const [labelWithHome],
        locations: const [locOverride, locHome],
        evaluationTime: evalTime,
      );
      for (final (first, second) in [
        (leftExplicitClear, remoteDeletedOverride),
        (remoteDeletedOverride, leftExplicitClear),
      ]) {
        final mergedC = TaskBoardSync.merge(
          primary: first,
          secondary: second,
          baseline: baseA,
          evaluationTime: evalTime,
        ).findTask(taskId)!;
        expect(
          mergedC.conditions,
          isEmpty,
          reason: 'Explicit condition removal on L must win over cascade location any on R',
        );
      }
    });

    test('merge_05_scoped_label_deletion_queue_eviction strips priority, preserves suspended, and evicts from queue', () {
      final vector =
          vectorsById['merge_05_scoped_label_deletion_queue_eviction']!;
      final before = vector['taskBeforeCascade'] as Map<String, Object?>;
      final taskId = before['id'] as String;
      const scopedLabelId = '9kLm2P0aBc';
      const scopedLabel = TdfLabel(
        id: scopedLabelId,
        name: 'Scoped',
        isScoped: true,
      );
      final suspendedTime = _parseIsoUtc(before['suspended'] as String);
      final task = TaskItem(
        id: taskId,
        title: 'Scoped Task',
        createdAt: DateTime.utc(2026, 11, 1, 8, 0, 0),
        modifiedAt: DateTime.utc(2026, 11, 1, 9, 0, 0),
        isPriority: before['priority'] as bool,
        labelIds: const [scopedLabelId],
        suspendedAt: suspendedTime,
      );
      final baseBoard = TaskBoard.evaluate(
        tasks: [task],
        labels: const [scopedLabel],
        queueBlock: TdfQueueBlock(
          modifiedAt: DateTime.utc(2026, 11, 1, 9, 0, 0),
          taskIds: [taskId],
        ),
        evaluationTime: evalTime,
      );
      final remoteDeletedLabel = TaskBoard.evaluate(
        tasks: [
          task.copyWith(
            isPriority: false,
            labelIds: const [],
            modifiedAt: DateTime.utc(2026, 11, 1, 10, 0, 0),
          ),
        ],
        labels: const [],
        deletedBlock: TdfDeletedBlock(
          generation: 0,
          labels: [
            TdfDeletedLabelRecord(
              labelId: scopedLabelId,
              deletedAt: DateTime.utc(2026, 11, 1, 10, 0, 0),
            ),
          ],
        ),
        queueBlock: TdfQueueBlock(
          modifiedAt: DateTime.utc(2026, 11, 1, 10, 0, 0),
          taskIds: const [],
        ),
        evaluationTime: evalTime,
      );

      for (final (first, second) in [
        (baseBoard, remoteDeletedLabel),
        (remoteDeletedLabel, baseBoard),
      ]) {
        final merged = TaskBoardSync.merge(
          primary: first,
          secondary: second,
          baseline: baseBoard,
          evaluationTime: evalTime,
        );
        final mergedTask = merged.findTask(taskId)!;
        expect(mergedTask.isPriority, isFalse);
        expect(mergedTask.labelIds, isEmpty);
        expect(mergedTask.suspendedAt, equals(suspendedTime));
        expect(
          mergedTask.modifiedAt,
          equals(DateTime.utc(2026, 11, 1, 10, 0, 0)),
        );
        expect(merged.queueBlock.taskIds, isNot(contains(taskId)));
      }

      // Concurrent scheduling on L vs. scoped label deletion on R:
      final unscheduledTask = TaskItem(
        id: taskId,
        title: 'Scoped Task',
        createdAt: DateTime.utc(2026, 11, 1, 8, 0, 0),
        modifiedAt: DateTime.utc(2026, 11, 1, 9, 0, 0),
        isPriority: false,
        labelIds: const [scopedLabelId],
      );
      final baseUnscheduled = TaskBoard.evaluate(
        tasks: [unscheduledTask],
        labels: const [scopedLabel],
        queueBlock: TdfQueueBlock(
          modifiedAt: DateTime.utc(2026, 11, 1, 9, 0, 0),
          taskIds: const [],
        ),
        evaluationTime: evalTime,
      );
      final leftScheduled = TaskBoard.evaluate(
        tasks: [
          unscheduledTask.copyWith(
            isPriority: true,
            modifiedAt: DateTime.utc(2026, 11, 1, 10, 5, 0),
          ),
        ],
        labels: const [scopedLabel],
        queueBlock: TdfQueueBlock(
          modifiedAt: DateTime.utc(2026, 11, 1, 10, 5, 0),
          taskIds: [taskId],
        ),
        evaluationTime: evalTime,
      );
      final rightDeletedScoped = TaskBoard.evaluate(
        tasks: [
          unscheduledTask.copyWith(
            isPriority: false,
            labelIds: const [],
            modifiedAt: DateTime.utc(2026, 11, 1, 10, 0, 0),
          ),
        ],
        labels: const [],
        deletedBlock: TdfDeletedBlock(
          generation: 0,
          labels: [
            TdfDeletedLabelRecord(
              labelId: scopedLabelId,
              deletedAt: DateTime.utc(2026, 11, 1, 10, 0, 0),
            ),
          ],
        ),
        queueBlock: TdfQueueBlock(
          modifiedAt: DateTime.utc(2026, 11, 1, 10, 0, 0),
          taskIds: const [],
        ),
        evaluationTime: evalTime,
      );
      for (final (direction, first, second) in [
        ('forward', leftScheduled, rightDeletedScoped),
        ('reverse', rightDeletedScoped, leftScheduled),
      ]) {
        final merged = TaskBoardSync.merge(
          primary: first,
          secondary: second,
          baseline: baseUnscheduled,
          evaluationTime: evalTime,
        );
        final mergedTask = merged.findTask(taskId)!;
        expect(
          mergedTask.labelIds,
          isEmpty,
          reason: 'Deleted scoped label must remain stripped ($direction)',
        );
        expect(
          mergedTask.isPriority,
          isFalse,
          reason:
              'Losing last scoped label must strip concurrent priority ($direction)',
        );
        expect(
          merged.queueBlock.taskIds,
          isNot(contains(taskId)),
          reason:
              'Losing last scoped label must evict task from queue ($direction)',
        );
      }

      // Concurrent unrelated queue edit on L vs. scoped label deletion on R:
      const otherTaskId = '7pQr9mOkD2';
      final otherTask = TaskItem(
        id: otherTaskId,
        title: 'Global Task',
        createdAt: DateTime.utc(2026, 11, 1, 8, 5, 0),
        modifiedAt: DateTime.utc(2026, 11, 1, 9, 0, 0),
      );
      final baseWithQueue = TaskBoard.evaluate(
        tasks: [task, otherTask],
        labels: const [scopedLabel],
        queueBlock: TdfQueueBlock(
          modifiedAt: DateTime.utc(2026, 11, 1, 9, 0, 0),
          taskIds: [taskId],
        ),
        evaluationTime: evalTime,
      );
      final leftNewerQueue = TaskBoard.evaluate(
        tasks: [task, otherTask],
        labels: const [scopedLabel],
        queueBlock: TdfQueueBlock(
          modifiedAt: DateTime.utc(2026, 11, 1, 10, 5, 0),
          taskIds: [taskId, otherTaskId],
        ),
        evaluationTime: evalTime,
      );
      final rightDeletedScopedWithOther = TaskBoard.evaluate(
        tasks: [
          task.copyWith(
            isPriority: false,
            labelIds: const [],
            modifiedAt: DateTime.utc(2026, 11, 1, 10, 0, 0),
          ),
          otherTask,
        ],
        labels: const [],
        deletedBlock: TdfDeletedBlock(
          generation: 0,
          labels: [
            TdfDeletedLabelRecord(
              labelId: scopedLabelId,
              deletedAt: DateTime.utc(2026, 11, 1, 10, 0, 0),
            ),
          ],
        ),
        queueBlock: TdfQueueBlock(
          modifiedAt: DateTime.utc(2026, 11, 1, 10, 0, 0),
          taskIds: const [otherTaskId],
        ),
        evaluationTime: evalTime,
      );
      for (final (direction, first, second) in [
        ('forward', leftNewerQueue, rightDeletedScopedWithOther),
        ('reverse', rightDeletedScopedWithOther, leftNewerQueue),
      ]) {
        final merged = TaskBoardSync.merge(
          primary: first,
          secondary: second,
          baseline: baseWithQueue,
          evaluationTime: evalTime,
        );
        final mergedTask = merged.findTask(taskId)!;
        expect(
          mergedTask.isPriority,
          isFalse,
          reason:
              'Priority must remain false after scoped label deletion ($direction)',
        );
        expect(
          merged.queueBlock.taskIds,
          equals(const [otherTaskId]),
          reason:
              'Scoped task losing last label must be evicted even when L.queue is newer ($direction)',
        );
      }
    });

    test('merge_06_thirty_day_task_tombstone_expiry_blocked_cleanup removes expired blocked references and keeps exact 30d and forward refs', () {
      final vector =
          vectorsById['merge_06_thirty_day_task_tombstone_expiry_blocked_cleanup']!;
      final now = _parseIsoUtc(vector['now'] as String);
      const expiredId = '6uCk8N0aB1';
      const exact30dId = '9aBc2D0eF4';
      const forwardRefId = 'ForwardRe1';
      const depTaskId = '8jKaCdOkD2';

      final deletedBefore = TdfDeletedBlock(
        generation: 4,
        tasks: [
          TdfDeletedTaskRecord(
            taskId: expiredId,
            deletedAt: _parseIsoUtc('2026-11-02T12:00:00Z'),
            completionsCheckpoint: 0,
          ),
          TdfDeletedTaskRecord(
            taskId: exact30dId,
            deletedAt: _parseIsoUtc('2026-11-02T12:00:01Z'),
            completionsCheckpoint: 2,
          ),
        ],
      );
      final depTask = TaskItem(
        id: depTaskId,
        title: 'Dependent',
        createdAt: DateTime.utc(2026, 11, 1, 8, 0, 0),
        modifiedAt: _parseIsoUtc('2026-11-05T10:00:00Z'),
        dependencies: const [
          TdfTaskDependency(taskId: expiredId, requiredCompletion: 1),
          TdfTaskDependency(taskId: exact30dId, requiredCompletion: 3),
          TdfTaskDependency(taskId: forwardRefId, requiredCompletion: 1),
        ],
      );
      final board = TaskBoard.evaluate(
        tasks: [depTask],
        deletedBlock: deletedBefore,
        evaluationTime: now,
      );

      final merged = TaskBoardSync.merge(
        primary: board,
        secondary: board,
        baseline: board,
        evaluationTime: now,
      );
      expect(merged.deletedBlock.generation, equals(5));
      expect(
        merged.deletedBlock.tasks.map((rec) => rec.taskId),
        equals([exact30dId]),
      );
      final cleanedTask = merged.findTask(depTaskId)!;
      expect(cleanedTask.modifiedAt, equals(now));
      expect(
        cleanedTask.dependencies,
        equals(const [
          TdfTaskDependency(taskId: exact30dId, requiredCompletion: 3),
          TdfTaskDependency(taskId: forwardRefId, requiredCompletion: 1),
        ]),
      );
    });

    test('merge_07_deletion_conflict_on_newly_introduced_references triggers DeletionConflict for A_X(T) and A_loc_X(E)', () {
      const labelId = '4x9p2mOkD2';
      const locId = '7pQr9mOkD2';
      const taskId = '8jKaCdOkD2';
      const label = TdfLabel(id: labelId, name: 'Work');
      const location = TdfLocation(
        id: locId,
        name: 'Office',
        latitude: 48.0,
        longitude: 11.0,
        radius: 100.0,
      );

      // Case 1: Newly added label reference on existing task vs concurrent label deletion
      final baseTask = TaskItem(
        id: taskId,
        title: 'Task',
        createdAt: DateTime.utc(2026, 11, 1, 8, 0, 0),
        modifiedAt: DateTime.utc(2026, 11, 1, 9, 0, 0),
      );
      final base1 = TaskBoard.evaluate(
        tasks: [baseTask],
        labels: const [label],
        evaluationTime: evalTime,
      );
      final left1 = TaskBoard.evaluate(
        tasks: [
          baseTask.copyWith(
            labelIds: const [labelId],
            modifiedAt: DateTime.utc(2026, 11, 1, 10, 0, 0),
          ),
        ],
        labels: const [label],
        evaluationTime: evalTime,
      );
      final right1 = TaskBoard.evaluate(
        tasks: [baseTask],
        labels: const [],
        deletedBlock: TdfDeletedBlock(
          generation: 0,
          labels: [
            TdfDeletedLabelRecord(
              labelId: labelId,
              deletedAt: DateTime.utc(2026, 11, 1, 10, 5, 0),
            ),
          ],
        ),
        evaluationTime: evalTime,
      );

      for (final (first, second) in [(left1, right1), (right1, left1)]) {
        expect(
          () => TaskBoardSync.merge(
            primary: first,
            secondary: second,
            baseline: base1,
            evaluationTime: evalTime,
          ),
          throwsA(
            isA<TdfSyncOutcomeException>()
                .having(
                  (error) => error.kind,
                  'kind',
                  TdfSyncOutcomeKind.deletionConflict,
                )
                .having(
                  (error) => error.conflictedLabelIds,
                  'conflictedLabelIds',
                  contains(labelId),
                ),
          ),
        );
      }

      // Case 2: Newly created task referencing location vs concurrent location deletion
      final base2 = TaskBoard.evaluate(
        tasks: const [],
        locations: const [location],
        evaluationTime: evalTime,
      );
      final left2 = TaskBoard.evaluate(
        tasks: [
          baseTask.copyWith(
            conditions: const [
              LocationTaskCondition(locationIds: [locId]),
            ],
            modifiedAt: DateTime.utc(2026, 11, 1, 10, 0, 0),
          ),
        ],
        locations: const [location],
        evaluationTime: evalTime,
      );
      final right2 = TaskBoard.evaluate(
        tasks: const [],
        locations: const [],
        deletedBlock: TdfDeletedBlock(
          generation: 0,
          locations: [
            TdfDeletedLocationRecord(
              locationId: locId,
              deletedAt: DateTime.utc(2026, 11, 1, 10, 5, 0),
            ),
          ],
        ),
        evaluationTime: evalTime,
      );

      for (final (first, second) in [(left2, right2), (right2, left2)]) {
        expect(
          () => TaskBoardSync.merge(
            primary: first,
            secondary: second,
            baseline: base2,
            evaluationTime: evalTime,
          ),
          throwsA(
            isA<TdfSyncOutcomeException>()
                .having(
                  (error) => error.kind,
                  'kind',
                  TdfSyncOutcomeKind.deletionConflict,
                )
                .having(
                  (error) => error.conflictedLocationIds,
                  'conflictedLocationIds',
                  contains(locId),
                ),
          ),
        );
      }
    });
  });
}
