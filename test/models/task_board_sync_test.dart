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

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_board_sync.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/repositories/settings_repository.dart';

void main() {
  final evaluationTime = DateTime.utc(2026, 11, 2, 12, 0);

  group('TaskBoardSync Entity-Level Merge & Conflict Resolution', () {
    test('merges disjoint tasks and labels and selects newer modifiedAt per entity across primary and secondary boards', () {
      final t1Old = TaskItem(
        id: 't001',
        title: 'Task 1 Old Title',
        createdAt: DateTime.utc(2026, 11, 1, 8, 0),
        queuedAt: DateTime.utc(2026, 11, 1, 8, 0),
        modifiedAt: DateTime.utc(2026, 11, 1, 9, 0),
      );
      final t1New = t1Old.copyWith(
        title: 'Task 1 Updated Remotely',
        modifiedAt: DateTime.utc(2026, 11, 1, 11, 30),
      );

      final t2New = TaskItem(
        id: 't002',
        title: 'Task 2 Updated Locally',
        createdAt: DateTime.utc(2026, 11, 1, 8, 5),
        queuedAt: DateTime.utc(2026, 11, 1, 8, 5),
        modifiedAt: DateTime.utc(2026, 11, 1, 11, 45),
      );
      final t2Old = t2New.copyWith(
        title: 'Task 2 Old Title',
        modifiedAt: DateTime.utc(2026, 11, 1, 9, 10),
      );

      final t3LocalOnly = TaskItem(
        id: 't003',
        title: 'Created Locally Offline',
        createdAt: DateTime.utc(2026, 11, 1, 10, 0),
        queuedAt: DateTime.utc(2026, 11, 1, 10, 0),
        modifiedAt: DateTime.utc(2026, 11, 1, 10, 0),
      );
      final t4RemoteOnly = TaskItem(
        id: 't004',
        title: 'Created Remotely Offline',
        createdAt: DateTime.utc(2026, 11, 1, 10, 5),
        queuedAt: DateTime.utc(2026, 11, 1, 10, 5),
        modifiedAt: DateTime.utc(2026, 11, 1, 10, 5),
      );

      final labelWorkOld = TdfLabel(
        id: 'work',
        name: 'Work Old',
        color: '#112233',
        modifiedAt: DateTime.utc(2026, 11, 1, 8, 0),
      );
      final labelWorkNew = labelWorkOld.copyWith(
        name: 'Work Updated',
        color: '#445566',
        modifiedAt: DateTime.utc(2026, 11, 1, 11, 0),
      );

      final primary = TaskBoard.evaluate(
        tasks: [t1Old, t2New, t3LocalOnly],
        labels: [labelWorkOld],
        evaluationTime: evaluationTime,
      );
      final secondary = TaskBoard.evaluate(
        tasks: [t1New, t2Old, t4RemoteOnly],
        labels: [labelWorkNew],
        evaluationTime: evaluationTime,
      );

      final merged = TaskBoardSync.merge(
        primary: primary,
        secondary: secondary,
        evaluationTime: evaluationTime,
      );

      expect(
        merged.labels.single.name,
        equals('Work Updated'),
        reason: 'Newer label modifiedAt on secondary must win',
      );
      expect(merged.labels.single.color, equals('#445566'));
      expect(
        merged.findTask('t001')?.title,
        equals('Task 1 Updated Remotely'),
        reason: 'Task t001 has newer modifiedAt on secondary and must win',
      );
      expect(
        merged.findTask('t002')?.title,
        equals('Task 2 Updated Locally'),
        reason: 'Task t002 has newer modifiedAt on primary and must win',
      );
      expect(
        merged.findTask('t003')?.title,
        equals('Created Locally Offline'),
        reason: 'Disjoint task t003 on primary must be preserved',
      );
      expect(
        merged.findTask('t004')?.title,
        equals('Created Remotely Offline'),
        reason: 'Disjoint task t004 on secondary must be preserved',
      );
    });

    test('treats 10-character entity IDs as immutable sync identities where identical IDs unconditionally resolve via modified Last-Write-Wins without ID reassignment', () {
      final sharedExisting = TaskItem(
        id: 'base01OkD2',
        title: 'Base Task',
        createdAt: DateTime.utc(2026, 11, 1, 8, 0),
        queuedAt: DateTime.utc(2026, 11, 1, 8, 0),
        modifiedAt: DateTime.utc(2026, 11, 1, 8, 0),
      );
      final localSameId = TaskItem(
        id: 'same02OkD2',
        title: 'Task Version Older',
        createdAt: DateTime.utc(2026, 11, 1, 9, 0),
        queuedAt: DateTime.utc(2026, 11, 1, 9, 0),
        modifiedAt: DateTime.utc(2026, 11, 1, 9, 0),
      );
      final remoteSameIdNewer = TaskItem(
        id: 'same02OkD2',
        title: 'Task Version Newer',
        createdAt: DateTime.utc(2026, 11, 1, 9, 30),
        queuedAt: DateTime.utc(2026, 11, 1, 9, 30),
        modifiedAt: DateTime.utc(2026, 11, 1, 9, 30),
      );
      final remoteDependent = TaskItem(
        id: 'dep003OkD2',
        title: 'Remote Follow-Up Blocked By same02OkD2',
        createdAt: DateTime.utc(2026, 11, 1, 9, 35),
        queuedAt: DateTime.utc(2026, 11, 1, 9, 35),
        modifiedAt: DateTime.utc(2026, 11, 1, 9, 35),
        blockedByTaskIds: const ['same02OkD2'],
      );

      final primary = TaskBoard.evaluate(
        tasks: [sharedExisting, localSameId],
        evaluationTime: evaluationTime,
      );
      final secondary = TaskBoard.evaluate(
        tasks: [sharedExisting, remoteSameIdNewer, remoteDependent],
        evaluationTime: evaluationTime,
      );

      final merged = TaskBoardSync.merge(
        primary: primary,
        secondary: secondary,
        evaluationTime: evaluationTime,
      );

      expect(
        merged.allTasks.map((task) => task.id).toSet(),
        equals({'base01OkD2', 'same02OkD2', 'dep003OkD2'}),
        reason: 'Identical 10-character task IDs must unconditionally represent the same entity without reassigning to a new ID',
      );
      expect(
        merged.findTask('same02OkD2')?.title,
        equals('Task Version Newer'),
        reason: 'Newer modifiedAt on same02OkD2 must win via Last-Write-Wins',
      );
      expect(
        merged.findTask('dep003OkD2')?.blockedByTaskIds,
        equals(['same02OkD2']),
        reason: 'Blocked reference to same02OkD2 must remain intact',
      );
      expect(merged.blocked.map((task) => task.id), contains('dep003OkD2'));
    });

    test('preserves handwritten labels without modified when not in baseline even if an older deletedLabelTimestamps entry exists, while honoring baseline-aware label and task deletions', () {
      final baselineLabelDeletedLocally = TdfLabel(
        id: 'old_label',
        name: 'Old Label',
        modifiedAt: DateTime.utc(2026, 11, 1, 8, 0),
      );
      final baselineLabelDeletedExternally = TdfLabel(
        id: 'ext_deleted_label',
        name: 'Externally Deleted Label',
        modifiedAt: DateTime.utc(2026, 11, 1, 8, 0),
      );
      final baselineTaskDeletedExternally = TaskItem(
        id: 't_ext_del',
        title: 'Task Deleted In External Editor',
        createdAt: DateTime.utc(2026, 11, 1, 8, 0),
        queuedAt: DateTime.utc(2026, 11, 1, 8, 0),
        modifiedAt: DateTime.utc(2026, 11, 1, 8, 0),
      );
      final baselineTaskDeletedLocally = TaskItem(
        id: 't_loc_del',
        title: 'Task Completed And Pruned Locally',
        createdAt: DateTime.utc(2026, 9, 1, 8, 0),
        queuedAt: DateTime.utc(2026, 9, 1, 8, 0),
        modifiedAt: DateTime.utc(2026, 9, 1, 8, 0),
      );

      final baseline = TaskBoard.evaluate(
        tasks: [baselineTaskDeletedExternally, baselineTaskDeletedLocally],
        labels: [baselineLabelDeletedLocally, baselineLabelDeletedExternally],
        evaluationTime: evaluationTime,
      );

      final primary = TaskBoard.evaluate(
        tasks: [baselineTaskDeletedExternally],
        labels: [baselineLabelDeletedExternally],
        evaluationTime: evaluationTime,
      );

      const handwrittenReaddedLabel = TdfLabel(
        id: 'readded_handwritten',
        name: 'Handwritten Label Without Modified',
      );
      final secondary = TaskBoard.evaluate(
        tasks: [baselineTaskDeletedLocally],
        labels: [baselineLabelDeletedLocally, handwrittenReaddedLabel],
        evaluationTime: evaluationTime,
      );

      final merged = TaskBoardSync.merge(
        primary: primary,
        secondary: secondary,
        baseline: baseline,
        deletedLabelTimestamps: <String, DateTime>{
          'old_label': DateTime.utc(2026, 11, 1, 10, 0),
          'readded_handwritten': DateTime.utc(2026, 11, 1, 9, 0),
        },
        evaluationTime: evaluationTime,
      );

      expect(
        merged.labels.map((label) => label.id),
        equals(['readded_handwritten']),
        reason: 'old_label (deleted locally) and ext_deleted_label (deleted externally relative to baseline) must be omitted, while handwritten label without modified not in baseline must be preserved',
      );
      expect(
        merged.labels.single.modifiedAt,
        equals(evaluationTime),
        reason:
            'Preserved handwritten label must be stamped with evaluationTime',
      );
      expect(
        merged.allTasks,
        isEmpty,
        reason: 't_ext_del (unmodified on primary, absent in secondary, present in baseline) and t_loc_del (absent on primary, unmodified in secondary, present in baseline) must both be omitted',
      );
    });

    test('breaks same-timestamp ties in favor of secondary when an external editor modified a task or label without bumping modified', () {
      final baseTask = TaskItem(
        id: 't001',
        title: 'Original Title',
        note: 'Original note',
        createdAt: DateTime.utc(2026, 11, 1, 8, 0),
        queuedAt: DateTime.utc(2026, 11, 1, 8, 0),
        modifiedAt: DateTime.utc(2026, 11, 1, 9, 0),
      );
      final externallyEditedTask = baseTask.copyWith(
        title: 'Edited In External Text Editor',
        note: 'Updated note without changing modified directive',
      );

      final primary = TaskBoard.evaluate(
        tasks: [baseTask],
        evaluationTime: evaluationTime,
      );
      final secondary = TaskBoard.evaluate(
        tasks: [externallyEditedTask],
        evaluationTime: evaluationTime,
      );

      final merged = TaskBoardSync.merge(
        primary: primary,
        secondary: secondary,
        evaluationTime: evaluationTime,
      );

      final mergedTask = merged.findTask('t001')!;
      expect(
        mergedTask.title,
        equals('Edited In External Text Editor'),
        reason: 'When effectiveModifiedAt is equal but content differs, secondary (incoming file) must win',
      );
      expect(
        mergedTask.modifiedAt,
        equals(evaluationTime),
        reason: 'Winning same-timestamp external edit must advance modifiedAt to evaluationTime',
      );
    });
  });

  group(
    'WorkspaceSyncState Binary Serialization & SettingsRepository Persistence',
    () {
      test('round-trips WorkspaceSyncState binary encoding and persists per-workspace sync state across repository calls', () async {
        final state = WorkspaceSyncState(
          lastSyncedLocalTdf: 'tdf 0.3.0\n\ntask t001 {\n    name "Local"\n    created 2026-11-01 08:00\n}\n\n',
          lastSyncedRemoteTdf: 'tdf 0.3.0\n\ntask t001 {\n    name "Remote"\n    created 2026-11-01 08:00\n}\n\n',
          deletedLabelTimestamps: <String, DateTime>{
            'work': DateTime.utc(2026, 11, 2, 10, 15, 30),
            'home': DateTime.utc(2026, 11, 2, 11, 0, 0),
          },
        );

        final encoded = state.toBytes();
        final decoded = WorkspaceSyncState.fromBytes(encoded);
        expect(
          decoded,
          equals(state),
          reason: 'WorkspaceSyncState binary round-trip must preserve baselines and deletedLabelTimestamps',
        );
        expect(decoded.hashCode, equals(state.hashCode));

        expect(
          WorkspaceSyncState.fromBytes(Uint8List(0)),
          equals(WorkspaceSyncState.empty),
          reason: 'Empty or corrupt binary bytes must safely fall back to WorkspaceSyncState.empty',
        );

        final repository = InMemorySettingsRepository();
        expect(
          await repository.loadWorkspaceSyncState(AppWorkspace.defaultId),
          equals(WorkspaceSyncState.empty),
        );

        await repository.saveWorkspaceSyncState(AppWorkspace.defaultId, state);
        expect(
          await repository.loadWorkspaceSyncState(AppWorkspace.defaultId),
          equals(state),
        );
      });
    },
  );
}
