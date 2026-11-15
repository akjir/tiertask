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
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';

DateTime _parseIsoUtc(String raw) => DateTime.parse(raw).toUtc();

TaskRepeatRule? _buildRepeatFromVector(Map<String, Object?>? repeatMap) {
  if (repeatMap == null) return null;
  final atRaw = repeatMap['at'] as String?;
  var clock = TdfRepeatClock.midnight;
  if (atRaw != null) {
    final parts = atRaw.split(':');
    clock = TdfRepeatClock(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
      second: parts.length > 2 ? int.parse(parts[2]) : 0,
    );
  }
  return TaskRepeatRule(
    count: repeatMap['count'] as int,
    unit: RepeatUnit.values.byName(repeatMap['unit'] as String),
    clock: clock,
    leadDays: (repeatMap['leadDays'] as int?) ?? 0,
  );
}

List<TaskHistoryEntry> _buildHistoryFromVector(List<Object?>? rawList) {
  if (rawList == null) return const <TaskHistoryEntry>[];
  return <TaskHistoryEntry>[
    for (final item in rawList.cast<Map<String, Object?>>())
      TaskHistoryEntry(
        timestampUtc: _parseIsoUtc(item['timestamp'] as String),
        text: item['text'] as String,
      ),
  ];
}

TaskItem _buildTaskFromVectorMap(
  Map<String, Object?> map, {
  String? fallbackId,
}) {
  final id = (map['id'] as String?) ?? fallbackId!;
  final modifiedRaw = map['modified'] as String?;
  final finishedRaw = map['finished'] as String?;
  final repeatMap = map['repeat'] as Map<String, Object?>?;
  final suspendedMap = map['suspended'] as Map<String, Object?>?;
  final dueMap = map['due'] as Map<String, Object?>?;
  final blockedMap = map['blocked'] as Map<String, Object?>?;
  final historyRaw = map['history'] as List<Object?>?;

  final isSuspendedForever =
      suspendedMap != null && (suspendedMap['forever'] as bool? ?? false);
  final suspendedTimestampRaw = suspendedMap?['timestamp'] as String?;

  return TaskItem(
    id: id,
    title: 'Task $id',
    createdAt: DateTime.utc(2026, 11, 1, 8, 0, 0),
    modifiedAt: modifiedRaw != null ? _parseIsoUtc(modifiedRaw) : null,
    completions: (map['completions'] as int?) ?? 0,
    isCompleted: finishedRaw != null,
    completedAt: finishedRaw != null ? _parseIsoUtc(finishedRaw) : null,
    isPriority: (map['priority'] as bool?) ?? false,
    isSuspendedForever: isSuspendedForever,
    suspendedAt: suspendedTimestampRaw != null
        ? _parseIsoUtc(suspendedTimestampRaw)
        : null,
    suspendedNote: suspendedMap?['note'] as String?,
    dueAt: dueMap != null ? _parseIsoUtc(dueMap['timestamp'] as String) : null,
    isDuePassive: dueMap != null && (dueMap['passive'] as bool? ?? false),
    dueNote: dueMap?['note'] as String?,
    repeatRule: _buildRepeatFromVector(repeatMap),
    dependencies: <TdfTaskDependency>[
      if (blockedMap != null)
        for (final entry in blockedMap.entries)
          TdfTaskDependency(
            taskId: entry.key,
            requiredCompletion: (entry.value as int?) ?? 1,
          ),
    ],
    history: _buildHistoryFromVector(historyRaw),
  );
}

TdfLabel _buildLabelFromVectorMap(Map<String, Object?> map) {
  final linksRaw = (map['links'] as List<Object?>?) ?? const <Object?>[];
  return TdfLabel(
    id: map['id'] as String,
    name: map['name'] as String,
    isScoped: (map['scoped'] as bool?) ?? false,
    color: map['color'] as String?,
    modifiedAt: _parseIsoUtc(map['modified'] as String),
    links: <TaskLink>[
      for (final link in linksRaw.cast<Map<String, Object?>>())
        TaskLink(title: link['title'] as String, uri: link['uri'] as String),
    ],
  );
}

void _expectMergedTaskMatchesExpected(
  TaskItem merged,
  TaskItem expected, {
  required String reason,
}) {
  expect(
    merged.modifiedAt,
    equals(expected.modifiedAt),
    reason: '$reason modifiedAt',
  );
  expect(
    merged.completions,
    equals(expected.completions),
    reason: '$reason completions',
  );
  expect(
    merged.isCompleted,
    equals(expected.isCompleted),
    reason: '$reason isCompleted',
  );
  expect(
    merged.completedAt,
    equals(expected.completedAt),
    reason: '$reason completedAt',
  );
  expect(
    merged.isPriority,
    equals(expected.isPriority),
    reason: '$reason isPriority',
  );
  expect(
    merged.isSuspendedForever,
    equals(expected.isSuspendedForever),
    reason: '$reason isSuspendedForever',
  );
  expect(
    merged.suspendedAt,
    equals(expected.suspendedAt),
    reason: '$reason suspendedAt',
  );
  expect(
    merged.suspendedNote,
    equals(expected.suspendedNote),
    reason: '$reason suspendedNote',
  );
  expect(merged.dueAt, equals(expected.dueAt), reason: '$reason dueAt');
  expect(
    merged.isDuePassive,
    equals(expected.isDuePassive),
    reason: '$reason isDuePassive',
  );
  expect(merged.dueNote, equals(expected.dueNote), reason: '$reason dueNote');
  expect(
    merged.repeatRule,
    equals(expected.repeatRule),
    reason: '$reason repeatRule',
  );
  expect(
    merged.dependencies,
    equals(expected.dependencies),
    reason: '$reason dependencies',
  );
  expect(merged.history, equals(expected.history), reason: '$reason history');
}

void main() {
  final rawJson = File('spec/conformance/v0.7.0/merge/vectors.json')
      .readAsStringSync();
  final decoded = jsonDecode(rawJson) as Map<String, Object?>;
  final vectors = (decoded['vectors'] as List<Object?>)
      .cast<Map<String, Object?>>();
  final vectorsById = <String, Map<String, Object?>>{
    for (final vector in vectors) vector['id'] as String: vector,
  };

  test(
    'vectors.json declares version 0.7.0 and all 8 conformance vector groups',
    () {
      expect(decoded['version'], equals('0.7.0'));
      expect(vectors, hasLength(8));
    },
  );

  group('TDF 0.7.0 Three-Way Merge Conformance Vectors', () {
    test('merge_01_history_occurrence_independent_set_merge reconciles history across Case 1 and Case 2 symmetrically', () {
      final vector =
          vectorsById['merge_01_history_occurrence_independent_set_merge']!;
      final now = _parseIsoUtc(vector['now'] as String);

      for (final subcaseKey in const <String>[
        'case1_diverging_completions',
        'case2_same_occurrence',
      ]) {
        final subcase = vector[subcaseKey] as Map<String, Object?>;
        final baseTask = _buildTaskFromVectorMap(
          subcase['baseline'] as Map<String, Object?>,
        );
        final leftTask = _buildTaskFromVectorMap(
          subcase['left'] as Map<String, Object?>,
        );
        final rightTask = _buildTaskFromVectorMap(
          subcase['right'] as Map<String, Object?>,
        );
        final expectedTask = _buildTaskFromVectorMap(
          subcase['expected'] as Map<String, Object?>,
        );

        final baseBoard = TaskBoard.evaluate(
          tasks: <TaskItem>[baseTask],
          evaluationTime: now,
        );
        final leftBoard = TaskBoard.evaluate(
          tasks: <TaskItem>[leftTask],
          evaluationTime: now,
        );
        final rightBoard = TaskBoard.evaluate(
          tasks: <TaskItem>[rightTask],
          evaluationTime: now,
        );

        final forwardBoard = TaskBoardSync.merge(
          primary: leftBoard,
          secondary: rightBoard,
          baseline: baseBoard,
          evaluationTime: now,
        );
        final reverseBoard = TaskBoardSync.merge(
          primary: rightBoard,
          secondary: leftBoard,
          baseline: baseBoard,
          evaluationTime: now,
        );
        expect(
          forwardBoard.allTasks,
          equals(reverseBoard.allTasks),
          reason: '$subcaseKey symmetry merge(B, L, R) == merge(B, R, L)',
        );
        _expectMergedTaskMatchesExpected(
          forwardBoard.findTask(expectedTask.id)!,
          expectedTask,
          reason: '$subcaseKey forward',
        );
        _expectMergedTaskMatchesExpected(
          reverseBoard.findTask(expectedTask.id)!,
          expectedTask,
          reason: '$subcaseKey reverse',
        );

        // Idempotence check (Section 6.7.6 Step 1):
        final idempotentBoard = TaskBoardSync.merge(
          primary: forwardBoard,
          secondary: forwardBoard,
          baseline: forwardBoard,
          evaluationTime: now.add(const Duration(minutes: 5)),
        );
        expect(
          idempotentBoard.findTask(expectedTask.id)!.modifiedAt,
          equals(expectedTask.modifiedAt),
          reason: '$subcaseKey idempotent re-merge must preserve modifiedAt',
        );
      }
    });

    test('merge_02_history_baseline_free_two_way_union unions L.history and R.history when baseline is null', () {
      final vector =
          vectorsById['merge_02_history_baseline_free_two_way_union']!;
      final now = _parseIsoUtc(vector['now'] as String);
      expect(vector['baseline'], isNull);

      final leftTask = _buildTaskFromVectorMap(
        vector['left'] as Map<String, Object?>,
      );
      final rightTask = _buildTaskFromVectorMap(
        vector['right'] as Map<String, Object?>,
      );
      final expectedTask = _buildTaskFromVectorMap(
        vector['expected'] as Map<String, Object?>,
      );

      final leftBoard = TaskBoard.evaluate(
        tasks: <TaskItem>[leftTask],
        evaluationTime: now,
      );
      final rightBoard = TaskBoard.evaluate(
        tasks: <TaskItem>[rightTask],
        evaluationTime: now,
      );

      final forwardBoard = TaskBoardSync.merge(
        primary: leftBoard,
        secondary: rightBoard,
        baseline: null,
        evaluationTime: now,
      );
      final reverseBoard = TaskBoardSync.merge(
        primary: rightBoard,
        secondary: leftBoard,
        baseline: null,
        evaluationTime: now,
      );
      expect(
        forwardBoard.allTasks,
        equals(reverseBoard.allTasks),
        reason: 'merge(null, L, R) == merge(null, R, L)',
      );
      _expectMergedTaskMatchesExpected(
        forwardBoard.findTask(expectedTask.id)!,
        expectedTask,
        reason: 'forward',
      );
      _expectMergedTaskMatchesExpected(
        reverseBoard.findTask(expectedTask.id)!,
        expectedTask,
        reason: 'reverse',
      );
    });

    test('merge_03_history_post_merge_limit_exceeded rejects 501 merged history entries with LimitExceeded', () {
      final vector = vectorsById['merge_03_history_post_merge_limit_exceeded']!;
      final now = _parseIsoUtc(vector['now'] as String);
      final taskId = vector['taskId'] as String;
      final leftCount = vector['leftAddedDistinctCount'] as int;
      final rightCount = vector['rightAddedDistinctCount'] as int;

      final baseTask = TaskItem(
        id: taskId,
        title: 'History Bound Task',
        createdAt: DateTime.utc(2026, 11, 1, 0, 0, 0),
        modifiedAt: DateTime.utc(2026, 11, 1, 0, 0, 0),
      );
      final leftHistory = <TaskHistoryEntry>[
        for (var i = 0; i < leftCount; i++)
          TaskHistoryEntry(
            timestampUtc: DateTime.utc(
              2026,
              11,
              1,
              0,
              0,
              0,
            ).add(Duration(seconds: i)),
            text: 'Left entry $i',
          ),
      ];
      final rightHistory = <TaskHistoryEntry>[
        for (var i = 0; i < rightCount; i++)
          TaskHistoryEntry(
            timestampUtc: DateTime.utc(
              2026,
              11,
              2,
              0,
              0,
              0,
            ).add(Duration(seconds: i)),
            text: 'Right entry $i',
          ),
      ];

      final baseBoard = TaskBoard.evaluate(
        tasks: <TaskItem>[baseTask],
        evaluationTime: now,
      );
      final leftBoard = TaskBoard.evaluate(
        tasks: <TaskItem>[
          baseTask.copyWith(
            history: leftHistory,
            modifiedAt: DateTime.utc(2026, 11, 14, 10, 0, 0),
          ),
        ],
        evaluationTime: now,
      );
      final rightBoard = TaskBoard.evaluate(
        tasks: <TaskItem>[
          baseTask.copyWith(
            history: rightHistory,
            modifiedAt: DateTime.utc(2026, 11, 14, 10, 5, 0),
          ),
        ],
        evaluationTime: now,
      );

      for (final (direction, first, second) in <(String, TaskBoard, TaskBoard)>[
        ('forward', leftBoard, rightBoard),
        ('reverse', rightBoard, leftBoard),
      ]) {
        expect(
          () => TaskBoardSync.merge(
            primary: first,
            secondary: second,
            baseline: baseBoard,
            evaluationTime: now,
          ),
          throwsA(
            isA<TdfException>().having(
              (error) => error.kind,
              'kind',
              TdfErrorKind.limitExceeded,
            ),
          ),
          reason: '501 merged history entries must fail ($direction)',
        );
      }
    });

    test('merge_04_deletion_conflict_history_edit_vs_block_cleanup_hygiene triggers conflict on history edit and cleans deletion on block-only cleanup', () {
      final vector =
          vectorsById['merge_04_deletion_conflict_history_edit_vs_block_cleanup_hygiene']!;
      final now = _parseIsoUtc(vector['now'] as String);
      final cases = (vector['cases'] as List<Object?>)
          .cast<Map<String, Object?>>();

      // Case 1: history edit vs opposing deletion -> DeletionConflict
      final case1 = cases[0];
      final taskId1 = case1['taskId'] as String;
      final baseTask1 = _buildTaskFromVectorMap(
        case1['baseline'] as Map<String, Object?>,
        fallbackId: taskId1,
      );
      final leftTask1 = _buildTaskFromVectorMap(
        case1['left'] as Map<String, Object?>,
        fallbackId: taskId1,
      );
      final rightDeletedAt1 = _parseIsoUtc(case1['rightDeletedAt'] as String);

      final baseBoard1 = TaskBoard.evaluate(
        tasks: <TaskItem>[baseTask1],
        evaluationTime: now,
      );
      final leftBoard1 = TaskBoard.evaluate(
        tasks: <TaskItem>[leftTask1],
        evaluationTime: now,
      );
      final rightBoard1 = TaskBoard.evaluate(
        tasks: const <TaskItem>[],
        deletedBlock: TdfDeletedBlock(
          generation: 0,
          tasks: <TdfDeletedTaskRecord>[
            TdfDeletedTaskRecord(
              taskId: taskId1,
              deletedAt: rightDeletedAt1,
              completionsCheckpoint: 0,
            ),
          ],
        ),
        evaluationTime: now,
      );

      for (final (direction, first, second) in <(String, TaskBoard, TaskBoard)>[
        ('forward', leftBoard1, rightBoard1),
        ('reverse', rightBoard1, leftBoard1),
      ]) {
        expect(
          () => TaskBoardSync.merge(
            primary: first,
            secondary: second,
            baseline: baseBoard1,
            evaluationTime: now,
          ),
          throwsA(
            isA<TdfSyncOutcomeException>()
                .having(
                  (error) => error.kind,
                  'kind',
                  TdfSyncOutcomeKind.deletionConflict,
                )
                .having(
                  (error) => error.conflictedTaskIds,
                  'conflictedTaskIds',
                  equals(<String>[taskId1]),
                ),
          ),
          reason:
              'History edit vs deletion must trigger DeletionConflict ($direction)',
        );
      }

      // Case 2: automatic block cleanup only vs opposing deletion -> clean deletion
      final case2 = cases[1];
      final prereqSpec = case2['prerequisiteTask'] as Map<String, Object?>;
      final prereqId = prereqSpec['id'] as String;
      final prereqBase = TaskItem(
        id: prereqId,
        title: 'Prerequisite',
        createdAt: DateTime.utc(2026, 11, 1, 8, 0, 0),
        modifiedAt: DateTime.utc(2026, 11, 14, 8, 0, 0),
        completions: prereqSpec['baselineCompletions'] as int,
      );
      final prereqLeftFinished = _parseIsoUtc(
        prereqSpec['leftFinished'] as String,
      );
      final prereqLeft = prereqBase.copyWith(
        completions: prereqSpec['leftCompletions'] as int,
        isCompleted: true,
        completedAt: prereqLeftFinished,
        modifiedAt: prereqLeftFinished,
      );

      final taskId2 = case2['taskId'] as String;
      final baseTask2 = _buildTaskFromVectorMap(
        case2['baseline'] as Map<String, Object?>,
        fallbackId: taskId2,
      );
      final leftTask2 = _buildTaskFromVectorMap(
        case2['left'] as Map<String, Object?>,
        fallbackId: taskId2,
      );
      final rightDeletedAt2 = _parseIsoUtc(case2['rightDeletedAt'] as String);

      final baseBoard2 = TaskBoard.evaluate(
        tasks: <TaskItem>[prereqBase, baseTask2],
        evaluationTime: now,
      );
      final leftBoard2 = TaskBoard.evaluate(
        tasks: <TaskItem>[prereqLeft, leftTask2],
        evaluationTime: now,
      );
      final rightBoard2 = TaskBoard.evaluate(
        tasks: <TaskItem>[prereqBase],
        deletedBlock: TdfDeletedBlock(
          generation: 0,
          tasks: <TdfDeletedTaskRecord>[
            TdfDeletedTaskRecord(
              taskId: taskId2,
              deletedAt: rightDeletedAt2,
              completionsCheckpoint: 0,
            ),
          ],
        ),
        evaluationTime: now,
      );

      final forwardClean = TaskBoardSync.merge(
        primary: leftBoard2,
        secondary: rightBoard2,
        baseline: baseBoard2,
        evaluationTime: now,
      );
      final reverseClean = TaskBoardSync.merge(
        primary: rightBoard2,
        secondary: leftBoard2,
        baseline: baseBoard2,
        evaluationTime: now,
      );
      expect(
        forwardClean.allTasks,
        equals(reverseClean.allTasks),
        reason: 'Symmetry on clean deletion',
      );
      expect(forwardClean.findTask(taskId2), isNull);
      expect(
        forwardClean.deletedBlock.tasks.map((record) => record.taskId),
        contains(taskId2),
      );
    });

    test('merge_05_label_links_atomic_list_merge merges label links atomically alongside scalar color edits', () {
      final vector = vectorsById['merge_05_label_links_atomic_list_merge']!;
      final now = _parseIsoUtc(vector['now'] as String);

      final baseLabel = _buildLabelFromVectorMap(
        vector['baseline'] as Map<String, Object?>,
      );
      final leftLabel = _buildLabelFromVectorMap(
        vector['left'] as Map<String, Object?>,
      );
      final rightLabel = _buildLabelFromVectorMap(
        vector['right'] as Map<String, Object?>,
      );
      final expectedLabel = _buildLabelFromVectorMap(
        vector['expected'] as Map<String, Object?>,
      );

      final baseBoard = TaskBoard.evaluate(
        tasks: const <TaskItem>[],
        labels: <TdfLabel>[baseLabel],
        evaluationTime: now,
      );
      final leftBoard = TaskBoard.evaluate(
        tasks: const <TaskItem>[],
        labels: <TdfLabel>[leftLabel],
        evaluationTime: now,
      );
      final rightBoard = TaskBoard.evaluate(
        tasks: const <TaskItem>[],
        labels: <TdfLabel>[rightLabel],
        evaluationTime: now,
      );

      final forwardBoard = TaskBoardSync.merge(
        primary: leftBoard,
        secondary: rightBoard,
        baseline: baseBoard,
        evaluationTime: now,
      );
      final reverseBoard = TaskBoardSync.merge(
        primary: rightBoard,
        secondary: leftBoard,
        baseline: baseBoard,
        evaluationTime: now,
      );
      expect(
        forwardBoard.labels,
        equals(reverseBoard.labels),
        reason: 'merge(B, L, R) == merge(B, R, L) for labels',
      );
      final mergedLabel = forwardBoard.findLabel(expectedLabel.id)!;
      expect(mergedLabel.isScoped, equals(expectedLabel.isScoped));
      expect(mergedLabel.name, equals(expectedLabel.name));
      expect(mergedLabel.color, equals(expectedLabel.color));
      expect(mergedLabel.links, equals(expectedLabel.links));
      expect(mergedLabel.modifiedAt, equals(expectedLabel.modifiedAt));
    });

    test('merge_06_case2_suspended_expiry_prenormalization_and_coupled_tuples executes subcases A, B, and C symmetrically', () {
      final vector =
          vectorsById['merge_06_case2_suspended_expiry_prenormalization_and_coupled_tuples']!;
      final now = _parseIsoUtc(vector['now'] as String);

      for (final subcaseKey in const <String>[
        'subcaseA_expired_cleanup_vs_future_extension',
        'subcaseB_expired_cleanup_vs_atomic_due_edit_no_resurrection',
        'subcaseC_both_sides_carry_expired_suspended_cleaned_at_now',
      ]) {
        final subcase = vector[subcaseKey] as Map<String, Object?>;
        final baseTask = _buildTaskFromVectorMap(
          subcase['baseline'] as Map<String, Object?>,
        );
        final leftTask = _buildTaskFromVectorMap(
          subcase['left'] as Map<String, Object?>,
        );
        final rightTask = _buildTaskFromVectorMap(
          subcase['right'] as Map<String, Object?>,
        );
        final expectedTask = _buildTaskFromVectorMap(
          subcase['expected'] as Map<String, Object?>,
        );

        final baseBoard = TaskBoard.evaluate(
          tasks: <TaskItem>[baseTask],
          evaluationTime: now,
        );
        final leftBoard = TaskBoard.evaluate(
          tasks: <TaskItem>[leftTask],
          evaluationTime: now,
        );
        final rightBoard = TaskBoard.evaluate(
          tasks: <TaskItem>[rightTask],
          evaluationTime: now,
        );

        final forwardBoard = TaskBoardSync.merge(
          primary: leftBoard,
          secondary: rightBoard,
          baseline: baseBoard,
          evaluationTime: now,
        );
        final reverseBoard = TaskBoardSync.merge(
          primary: rightBoard,
          secondary: leftBoard,
          baseline: baseBoard,
          evaluationTime: now,
        );
        expect(
          forwardBoard.allTasks,
          equals(reverseBoard.allTasks),
          reason: '$subcaseKey symmetry',
        );
        _expectMergedTaskMatchesExpected(
          forwardBoard.findTask(expectedTask.id)!,
          expectedTask,
          reason: '$subcaseKey forward',
        );
        _expectMergedTaskMatchesExpected(
          reverseBoard.findTask(expectedTask.id)!,
          expectedTask,
          reason: '$subcaseKey reverse',
        );
      }
    });

    test('merge_07_case2_v_repeat_aware_blocked_prenormalization executes subcases 1, 2, and 3 symmetrically', () {
      final vector =
          vectorsById['merge_07_case2_v_repeat_aware_blocked_prenormalization']!;
      final now = _parseIsoUtc(vector['now'] as String);

      for (final subcaseKey in const <String>[
        'subcase1_concurrent_threshold_raise_preserved',
        'subcase2_newly_added_dependent_repeat_pipeline_preserved',
        'subcase3_post_merge_cleanup_when_non_recurring',
      ]) {
        final subcase = vector[subcaseKey] as Map<String, Object?>;
        final prereqSpec = subcase['prerequisite'] as Map<String, Object?>;
        final prereqId = prereqSpec['id'] as String;
        final prereqRepeat = _buildRepeatFromVector(
          prereqSpec['repeat'] as Map<String, Object?>?,
        );
        final prereqLeftFinishedRaw = prereqSpec['leftFinished'] as String?;
        final prereqLeftModifiedRaw = prereqSpec['leftModified'] as String?;

        final prereqBase = TaskItem(
          id: prereqId,
          title: 'Prereq $prereqId',
          createdAt: DateTime.utc(2026, 11, 1, 8, 0, 0),
          modifiedAt: DateTime.utc(2026, 11, 14, 9, 0, 0),
          completions: prereqSpec['baselineCompletions'] as int,
          repeatRule: prereqRepeat,
        );
        final prereqLeft = prereqBase.copyWith(
          completions: prereqSpec['leftCompletions'] as int,
          isCompleted: prereqLeftFinishedRaw != null,
          completedAt: prereqLeftFinishedRaw != null
              ? _parseIsoUtc(prereqLeftFinishedRaw)
              : null,
          modifiedAt: prereqLeftFinishedRaw != null
              ? _parseIsoUtc(prereqLeftFinishedRaw)
              : _parseIsoUtc(prereqLeftModifiedRaw!),
        );
        final prereqRight = prereqBase.copyWith(
          completions: prereqSpec['rightCompletions'] as int,
        );

        final depBase = _buildTaskFromVectorMap(
          subcase['dependentBaseline'] as Map<String, Object?>,
        );
        final depLeft = _buildTaskFromVectorMap(
          subcase['dependentLeft'] as Map<String, Object?>,
        );
        final depRight = _buildTaskFromVectorMap(
          subcase['dependentRight'] as Map<String, Object?>,
        );
        final expectedDep = _buildTaskFromVectorMap(
          subcase['expectedDependent'] as Map<String, Object?>,
        );

        final baseBoard = TaskBoard.evaluate(
          tasks: <TaskItem>[prereqBase, depBase],
          evaluationTime: now,
        );
        final leftBoard = TaskBoard.evaluate(
          tasks: <TaskItem>[prereqLeft, depLeft],
          evaluationTime: now,
        );
        final rightBoard = TaskBoard.evaluate(
          tasks: <TaskItem>[prereqRight, depRight],
          evaluationTime: now,
        );

        final forwardBoard = TaskBoardSync.merge(
          primary: leftBoard,
          secondary: rightBoard,
          baseline: baseBoard,
          evaluationTime: now,
        );
        final reverseBoard = TaskBoardSync.merge(
          primary: rightBoard,
          secondary: leftBoard,
          baseline: baseBoard,
          evaluationTime: now,
        );
        expect(
          forwardBoard.allTasks,
          equals(reverseBoard.allTasks),
          reason: '$subcaseKey symmetry',
        );
        _expectMergedTaskMatchesExpected(
          forwardBoard.findTask(expectedDep.id)!,
          expectedDep,
          reason: '$subcaseKey forward',
        );
        _expectMergedTaskMatchesExpected(
          reverseBoard.findTask(expectedDep.id)!,
          expectedDep,
          reason: '$subcaseKey reverse',
        );
      }
    });

    test('merge_08_history_lifecycle_retention_and_noop_protection preserves history across complete, repeat, and restore and treats duplicate/missing edits as no-ops', () {
      final vector =
          vectorsById['merge_08_history_lifecycle_retention_and_noop_protection']!;
      final initialHistory = _buildHistoryFromVector(
        vector['initialHistory'] as List<Object?>,
      );
      final tCreate = DateTime.utc(2026, 11, 1, 8, 0, 0);
      final tMutate = DateTime.utc(2026, 11, 10, 10, 0, 0);
      final tRestore = DateTime.utc(2026, 11, 10, 11, 0, 0);

      // 1. Standard completion + restoreTask:
      final standardTask = TaskItem(
        id: 'std001OkD2',
        title: 'Standard Task',
        createdAt: tCreate,
        modifiedAt: tCreate,
        suspendedAt: DateTime.utc(2026, 11, 12, 9, 0, 0),
        suspendedNote: 'Snoozed',
        dueAt: DateTime.utc(2026, 11, 15, 17, 0, 0),
        dueNote: 'Hard deadline',
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'other1OkD2', requiredCompletion: 1),
        ],
        history: initialHistory,
      );
      final board1 = TaskBoard.evaluate(
        tasks: <TaskItem>[standardTask],
        evaluationTime: tCreate,
      );
      final afterComplete = board1.completeTask(
        'std001OkD2',
        currentDate: tMutate,
      );
      final completedTask = afterComplete.findTask('std001OkD2')!;
      expect(completedTask.isCompleted, isTrue);
      expect(completedTask.completedAt, isNotNull);
      expect(completedTask.suspendedAt, isNull);
      expect(completedTask.suspendedNote, isNull);
      expect(completedTask.dependencies, isEmpty);
      expect(completedTask.dueAt, equals(standardTask.dueAt));
      expect(completedTask.dueNote, equals('Hard deadline'));
      expect(completedTask.history, equals(initialHistory));

      final afterRestore = afterComplete.restoreTask(
        'std001OkD2',
        targetTier: TaskTier.planned,
        currentDate: tRestore,
      );
      final restoredTask = afterRestore.findTask('std001OkD2')!;
      expect(restoredTask.isCompleted, isFalse);
      expect(restoredTask.completedAt, isNull);
      expect(restoredTask.suspendedAt, isNull);
      expect(restoredTask.suspendedNote, isNull);
      expect(restoredTask.dueAt, isNull);
      expect(restoredTask.dueNote, isNull);
      expect(restoredTask.history, equals(initialHistory));

      // 2. Mode 1 & Mode 2 repeat completions:
      final mode1Task = TaskItem(
        id: 'repM01OkD2',
        title: 'Mode 1 Repeat',
        createdAt: tCreate,
        modifiedAt: tCreate,
        suspendedAt: DateTime.utc(2026, 11, 9, 9, 0, 0),
        suspendedNote: 'Temporary deferral note',
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.weeks),
        history: initialHistory,
      );
      final mode2Task = TaskItem(
        id: 'repM02OkD2',
        title: 'Mode 2 Repeat',
        createdAt: tCreate,
        modifiedAt: tCreate,
        suspendedAt: DateTime.utc(2026, 11, 9, 9, 0, 0),
        suspendedNote: 'Temporary deferral note',
        dueAt: DateTime.utc(2026, 11, 12, 17, 0, 0),
        isDuePassive: true,
        dueNote: 'Recurring cutoff note',
        repeatRule: const TaskRepeatRule(
          count: 1,
          unit: RepeatUnit.weeks,
          leadDays: 2,
        ),
        history: initialHistory,
      );
      final repeatBoard = TaskBoard.evaluate(
        tasks: <TaskItem>[mode1Task, mode2Task],
        evaluationTime: tMutate,
      );
      final afterRepeat = repeatBoard
          .completeTask('repM01OkD2', currentDate: tMutate)
          .completeTask('repM02OkD2', currentDate: tMutate);
      final nextMode1 = afterRepeat.findTask('repM01OkD2')!;
      expect(nextMode1.completions, equals(1));
      expect(nextMode1.suspendedNote, isNull);
      expect(nextMode1.history, equals(initialHistory));

      final nextMode2 = afterRepeat.findTask('repM02OkD2')!;
      expect(nextMode2.completions, equals(1));
      expect(nextMode2.suspendedNote, isNull);
      expect(nextMode2.dueNote, equals('Recurring cutoff note'));
      expect(nextMode2.isDuePassive, isFalse);
      expect(nextMode2.history, equals(initialHistory));

      // 3. No-op duplicate add and missing remove do not advance modifiedAt:
      final beforeNoOpMod = restoredTask.modifiedAt;
      final afterDupAdd = afterRestore.addTaskHistoryEntry(
        'std001OkD2',
        timestampUtc: initialHistory.first.timestampUtc,
        text: initialHistory.first.text,
        currentDate: tRestore.add(const Duration(minutes: 10)),
      );
      expect(
        afterDupAdd.findTask('std001OkD2')!.modifiedAt,
        equals(beforeNoOpMod),
      );
      final afterMissingRemove = afterRestore.removeTaskHistoryEntry(
        'std001OkD2',
        entry: TaskHistoryEntry(
          timestampUtc: DateTime.utc(2026, 11, 3, 12, 0, 0),
          text: 'Non-existent entry',
        ),
        currentDate: tRestore.add(const Duration(minutes: 10)),
      );
      expect(
        afterMissingRemove.findTask('std001OkD2')!.modifiedAt,
        equals(beforeNoOpMod),
      );
    });
  });
}
