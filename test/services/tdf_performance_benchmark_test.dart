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

import 'package:flutter_test/flutter_test.dart';

import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_board_sync.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';
import 'package:tiertask/models/workspace_sync_state.dart';
import 'package:tiertask/services/sha256_service.dart';
import 'package:tiertask/services/tdf_service.dart';

const String _base62Alphabet =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

String _deterministicId(String prefix, int index) {
  final buffer = StringBuffer(prefix);
  var value = index + 1;
  final digits = <int>[];
  while (buffer.length + digits.length < 10) {
    digits.add(value % 62);
    value ~/= 62;
  }
  for (var i = digits.length - 1; i >= 0; i--) {
    buffer.write(_base62Alphabet[digits[i]]);
  }
  return buffer.toString();
}

TaskBoard _buildLargeBenchmarkBoard({
  required int taskCount,
  required int completedCount,
  required int tombstoneCount,
  required DateTime utcNow,
  bool pruneExpiredCompleted = false,
}) {
  final labels = <TdfLabel>[
    for (var i = 0; i < 20; i++)
      TdfLabel(
        id: _deterministicId('LBL0', i),
        name: 'Label $i',
        color: '#2563EB',
        isScoped: i < 4,
        modifiedAt: utcNow,
      ),
  ];
  final locations = <TdfLocation>[
    for (var i = 0; i < 10; i++)
      TdfLocation(
        id: _deterministicId('LOC0', i),
        name: 'Location $i',
        latitude: 48.1351 + (i * 0.01),
        longitude: 11.5820 + (i * 0.01),
        radius: 150,
        modifiedAt: utcNow,
      ),
  ];
  final tasks = <TaskItem>[];
  final queueIds = <String>[];
  final createdAt = utcNow.subtract(const Duration(days: 60));
  final expiredCompletedAt = utcNow.subtract(const Duration(days: 45));
  for (var i = 0; i < taskCount; i++) {
    final id = _deterministicId('TSK0', i);
    final isCompleted = i < completedCount;
    final labelId = labels[i % labels.length].id;
    final locationId = locations[i % locations.length].id;
    final task = TaskItem(
      id: id,
      title: 'Benchmark task $i with structured work payload',
      createdAt: createdAt,
      isCompleted: isCompleted,
      completedAt: isCompleted ? expiredCompletedAt : null,
      modifiedAt: utcNow.subtract(Duration(minutes: i % 1000)),
      labelIds: <String>[labelId, labels[(i + 1) % labels.length].id],
      conditions: i % 5 == 0
          ? <TaskCondition>[
              LocationTaskCondition(locationIds: <String>[locationId]),
            ]
          : const <TaskCondition>[],
      history: <TaskHistoryEntry>[
        TaskHistoryEntry(
          timestampUtc: createdAt.add(const Duration(hours: 1)),
          text: 'Entry A for task $i',
        ),
        TaskHistoryEntry(
          timestampUtc: createdAt.add(const Duration(hours: 2)),
          text: 'Entry B for task $i',
        ),
      ],
      subtasks: i % 3 == 0
          ? <SubtaskItem>[
              SubtaskItem(title: 'Step 1 for $i', isCompleted: isCompleted),
              SubtaskItem(title: 'Step 2 for $i', isCompleted: isCompleted),
            ]
          : const <SubtaskItem>[],
    );
    tasks.add(task);
    if (!isCompleted && i % 4 != 0) {
      queueIds.add(id);
    }
  }
  final deletedAtBase = utcNow.subtract(const Duration(days: 5));
  final deletedTasks = <TdfDeletedTaskRecord>[
    for (var i = 0; i < tombstoneCount; i++)
      TdfDeletedTaskRecord(
        taskId: _deterministicId('DEL0', i),
        deletedAt: deletedAtBase.add(Duration(seconds: i)),
      ),
  ];
  return TaskBoard.evaluate(
    tasks: tasks,
    labels: labels,
    locations: locations,
    queueBlock: TdfQueueBlock(modifiedAt: utcNow, taskIds: queueIds),
    deletedBlock: TdfDeletedBlock(generation: 1, tasks: deletedTasks),
    evaluationTime: utcNow,
    localEvaluationTime: utcNow,
    pruneExpiredCompleted: pruneExpiredCompleted,
  );
}

void main() {
  group('Max-Bound Performance Benchmarks', () {
    final utcNow = DateTime.utc(2026, 11, 22, 12);
    const tdfService = TdfService();

    test('serializes, parses, and evaluates large multi-thousand-entity board within bounds', () {
      final board = _buildLargeBenchmarkBoard(
        taskCount: 1000,
        completedCount: 100,
        tombstoneCount: 1000,
        utcNow: utcNow,
      );

      final serializeWatch = Stopwatch()..start();
      final serialized = tdfService.serialize(board);
      serializeWatch.stop();

      final serializedBytes = utf8.encode(serialized);
      expect(
        serializedBytes.length,
        lessThanOrEqualTo(maxTdfFileBytes),
        reason: 'Benchmark document must remain within maxTdfFileBytes',
      );

      final parseWatch = Stopwatch()..start();
      final parsed = tdfService.parse(
        serialized,
        evaluationTime: utcNow,
        localEvaluationTime: utcNow,
      );
      parseWatch.stop();

      final evalWatch = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        parsed.evaluateForContext(
          evaluationTime: utcNow.add(Duration(minutes: i)),
          localEvaluationTime: utcNow.add(Duration(minutes: i)),
          activeLabelId: i.isEven ? parsed.labels.first.id : null,
        );
      }
      evalWatch.stop();

      expect(
        parsed.allTasks.length,
        equals(1000),
        reason: 'Parse without pruning retains all 1000 tasks',
      );
      expect(
        serializeWatch.elapsedMilliseconds,
        lessThan(1000),
        reason:
            'serialize took ${serializeWatch.elapsedMilliseconds}ms (${serializedBytes.length} bytes)',
      );
      expect(
        parseWatch.elapsedMilliseconds,
        lessThan(1500),
        reason: 'parse took ${parseWatch.elapsedMilliseconds}ms',
      );
      expect(
        evalWatch.elapsedMilliseconds,
        lessThan(1000),
        reason:
            '10x evaluateForContext took ${evalWatch.elapsedMilliseconds}ms',
      );
    });

    test('merges high-tombstone baseline board and prunes expired completed tasks within bounds', () {
      final baseline = _buildLargeBenchmarkBoard(
        taskCount: 600,
        completedCount: 0,
        tombstoneCount: 2000,
        utcNow: utcNow,
      );
      final local = baseline.updateTask(
        baseline.allTasks.first.id,
        title: 'Locally edited benchmark task',
        currentDate: utcNow.add(const Duration(seconds: 5)),
        localEvaluationTime: utcNow.add(const Duration(seconds: 5)),
      );
      final remote = baseline.updateTask(
        baseline.allTasks.last.id,
        title: 'Remotely edited benchmark task',
        currentDate: utcNow.add(const Duration(seconds: 6)),
        localEvaluationTime: utcNow.add(const Duration(seconds: 6)),
      );

      final mergeWatch = Stopwatch()..start();
      final merged = TaskBoardSync.merge(
        primary: local,
        secondary: remote,
        baseline: baseline,
        evaluationTime: utcNow.add(const Duration(seconds: 10)),
        localEvaluationTime: utcNow.add(const Duration(seconds: 10)),
      );
      mergeWatch.stop();

      final pruneSource = _buildLargeBenchmarkBoard(
        taskCount: 700,
        completedCount: 400,
        tombstoneCount: 1000,
        utcNow: utcNow,
      );
      final pruneWatch = Stopwatch()..start();
      final pruned = pruneSource.pruneCompletedTasks(currentDate: utcNow);
      pruneWatch.stop();

      expect(
        merged.deletedBlock.tasks.length,
        equals(2000),
        reason: 'Equal-generation merge must retain all 2000 tombstones',
      );
      expect(
        pruned.completed,
        isEmpty,
        reason: 'All 400 expired completed tasks must be pruned',
      );
      expect(
        mergeWatch.elapsedMilliseconds,
        lessThan(1000),
        reason: 'merge took ${mergeWatch.elapsedMilliseconds}ms',
      );
      expect(
        pruneWatch.elapsedMilliseconds,
        lessThan(500),
        reason: 'pruneCompletedTasks took ${pruneWatch.elapsedMilliseconds}ms',
      );
    });

    test('hashes 1 MiB payload, resolves local timezones, and round-trips large sync state within bounds', () {
      final oneMiB = Uint8List(maxTdfFileBytes);
      for (var i = 0; i < oneMiB.length; i++) {
        oneMiB[i] = i & 0xFF;
      }
      final shaWatch = Stopwatch()..start();
      final digest = Sha256Service.hashHex(oneMiB);
      shaWatch.stop();

      const systemTz = TdfTimeZoneContext.systemLocal();
      final nyTz = TdfTimeZoneContext.named('America/New_York');
      final tzWatch = Stopwatch()..start();
      for (var i = 0; i < 500; i++) {
        final day = (i % 28) + 1;
        final month = (i % 12) + 1;
        systemTz.resolveLocalToUtc(2026, month, day, 9, 30, 0);
        nyTz.resolveLocalToUtc(2026, month, day, 9, 30, 0);
      }
      tzWatch.stop();

      final board = _buildLargeBenchmarkBoard(
        taskCount: 800,
        completedCount: 0,
        tombstoneCount: 500,
        utcNow: utcNow,
      );
      final canonical = tdfService.serialize(board);
      final syncState = WorkspaceSyncState(
        lastSyncedLocalTdf: canonical,
        lastSyncedRemoteTdf: canonical,
        acknowledgedLocalGeneration: 1,
        acknowledgedRemoteGeneration: 1,
        localSourceDigest: digest,
        remoteSourceDigest: digest,
      );
      final stateWatch = Stopwatch()..start();
      final wire = syncState.toBytes();
      final decoded = WorkspaceSyncState.fromBytes(wire);
      stateWatch.stop();

      expect(digest.length, equals(64));
      expect(decoded, equals(syncState));
      expect(
        shaWatch.elapsedMilliseconds,
        lessThan(1000),
        reason: '1 MiB SHA-256 took ${shaWatch.elapsedMilliseconds}ms',
      );
      expect(
        tzWatch.elapsedMilliseconds,
        lessThan(1000),
        reason: '1000x resolveLocalToUtc took ${tzWatch.elapsedMilliseconds}ms',
      );
      expect(
        stateWatch.elapsedMilliseconds,
        lessThan(1000),
        reason:
            'WorkspaceSyncState round-trip took ${stateWatch.elapsedMilliseconds}ms',
      );
    });
  });
}
