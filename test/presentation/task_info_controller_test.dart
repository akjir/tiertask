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

import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_timezone.dart';
import 'package:tiertask/presentation/task_info_controller.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/services/app_logger.dart';

class _TestHistoryTaskNotifier extends TaskNotifier {
  _TestHistoryTaskNotifier(this._initialBoard);

  final TaskBoard _initialBoard;
  Object? errorToThrow;
  bool simulateRollback = false;

  @override
  Future<TaskBoard> build() async => _initialBoard;

  @override
  Future<void> addTaskHistoryEntry(
    String taskId, {
    required DateTime timestampUtc,
    required String text,
    DateTime? currentDate,
  }) async {
    if (errorToThrow case final error?) {
      throw error;
    }
    if (simulateRollback) {
      return;
    }
    final board = state.asData?.value ?? _initialBoard;
    state = AsyncData<TaskBoard>(
      board.addTaskHistoryEntry(
        taskId,
        timestampUtc: timestampUtc,
        text: text,
        currentDate: timestampUtc,
      ),
    );
  }

  @override
  Future<void> removeTaskHistoryEntry(
    String taskId, {
    required DateTime timestampUtc,
    required String text,
    DateTime? currentDate,
  }) async {
    if (errorToThrow case final error?) {
      throw error;
    }
    if (simulateRollback) {
      return;
    }
    final board = state.asData?.value ?? _initialBoard;
    state = AsyncData<TaskBoard>(
      board.removeTaskHistoryEntry(
        taskId,
        entry: TaskHistoryEntry(timestampUtc: timestampUtc, text: text),
        currentDate: currentDate ?? DateTime.utc(2026, 11, 21, 10),
      ),
    );
  }

  @override
  Future<void> updateTaskHistoryEntry(
    String taskId, {
    required DateTime oldTimestampUtc,
    required String oldText,
    required DateTime newTimestampUtc,
    required String newText,
    DateTime? currentDate,
  }) async {
    if (errorToThrow case final error?) {
      throw error;
    }
    if (simulateRollback) {
      return;
    }
    final board = state.asData?.value ?? _initialBoard;
    state = AsyncData<TaskBoard>(
      board.updateTaskHistoryEntry(
        taskId,
        oldEntry: TaskHistoryEntry(
          timestampUtc: oldTimestampUtc,
          text: oldText,
        ),
        newTimestampUtc: newTimestampUtc,
        newText: newText,
        currentDate: currentDate ?? DateTime.utc(2026, 11, 21, 10),
      ),
    );
  }
}

void main() {
  setUp(() {
    AppLogger.resetForTesting(clock: () => DateTime.utc(2026, 11, 21, 10));
  });

  tearDown(() {
    AppLogger.resetForTesting();
  });

  group('TaskInfoController pure formatting helpers', () {
    test(
      'formats remaining durations and detects wall-clock anchor differences',
      () {
        final en = lookupAppLocalizations(const Locale('en'));

        expect(
          TaskInfoController.formatRemainingDuration(
            const Duration(days: 2, hours: 5),
            en,
          ),
          equals(en.taskInfoDurationDaysHours('2', '5')),
        );
        expect(
          TaskInfoController.formatRemainingDuration(
            const Duration(hours: 3, minutes: 15),
            en,
          ),
          equals(en.taskInfoDurationHoursMinutes('3', '15')),
        );
        expect(
          TaskInfoController.formatRemainingDuration(
            const Duration(seconds: 10),
            en,
          ),
          equals(en.taskInfoDurationMinutes('1')),
        );

        final anchor = TdfLocalDateTime(2026, 11, 21, 10, 30);
        expect(
          TaskInfoController.differsFromWallClock(
            anchor,
            DateTime.utc(2026, 11, 21, 10, 30),
          ),
          isFalse,
        );
        expect(
          TaskInfoController.differsFromWallClock(
            anchor,
            DateTime.utc(2026, 11, 21, 11, 30),
          ),
          isTrue,
        );
      },
    );
  });

  group('TaskInfoController history mutations', () {
    test('handles append, inline update, delete, unchanged, rollback, and missing task', () async {
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.info,
        persistToDisk: false,
      );
      final now = DateTime.utc(2026, 11, 21, 10);
      final board = TaskBoard.empty().addTask(
        'Journal task',
        id: 't1',
        currentDate: now,
      );
      final notifier = _TestHistoryTaskNotifier(board);
      final container = ProviderContainer(
        overrides: [
          taskNotifierProvider.overrideWith(() => notifier),
          clockProvider.overrideWithValue(() => now),
          appLocaleProvider.overrideWithValue(const Locale('en')),
        ],
      );
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      final controller = container.read(taskInfoControllerProvider);
      expect(controller.isTaskOnBoard('t1'), isTrue);
      expect(controller.isTaskOnBoard('missing'), isFalse);

      // Missing task -> NotApplied.
      expect(
        await controller.appendHistoryEntry(
          currentTask: TaskItem(id: 'missing', title: 'Missing'),
          rawText: 'Entry',
        ),
        isA<TaskHistoryMutationNotApplied>(),
      );

      // Append committed.
      final taskBefore = container
          .read(taskNotifierProvider)
          .value
          ?.findTask('t1');
      expect(taskBefore, isNotNull);
      if (taskBefore == null) return;
      final appended = await controller.appendHistoryEntry(
        currentTask: taskBefore,
        rawText: '  First\nline  ',
      );
      expect(appended, isA<TaskHistoryMutationCommitted>());
      final entry = TaskHistoryEntry(timestampUtc: now, text: 'First line');
      expect(
        container.read(taskNotifierProvider).value?.findTask('t1')?.history,
        contains(entry),
      );
      expect(
        AppLogger.fullLogText,
        contains('ui.task_info.history_added | id=t1 history_count=1'),
      );
      expect(AppLogger.fullLogText, isNot(contains('First line')));

      // Unchanged raw text and unchanged sanitized text both return Unchanged.
      expect(
        await controller.updateHistoryEntry(
          taskId: 't1',
          originalEntry: entry,
          rawText: 'First line',
        ),
        isA<TaskHistoryMutationUnchanged>(),
      );
      expect(
        await controller.updateHistoryEntry(
          taskId: 't1',
          originalEntry: entry,
          rawText: '  First\tline  ',
        ),
        isA<TaskHistoryMutationUnchanged>(),
      );

      // Inline update preserves original timestampUtc.
      final updated = await controller.updateHistoryEntry(
        taskId: 't1',
        originalEntry: entry,
        rawText: 'Edited entry',
      );
      expect(updated, isA<TaskHistoryMutationCommitted>());
      final replacement = TaskHistoryEntry(
        timestampUtc: now,
        text: 'Edited entry',
      );
      expect(
        container.read(taskNotifierProvider).value?.findTask('t1')?.history,
        equals(<TaskHistoryEntry>[replacement]),
      );
      expect(
        AppLogger.fullLogText,
        contains('ui.task_info.history_updated | id=t1 history_count=1'),
      );

      // Rollback leaves board unchanged -> NotApplied.
      notifier.simulateRollback = true;
      expect(
        await controller.deleteHistoryEntry(taskId: 't1', entry: replacement),
        isA<TaskHistoryMutationNotApplied>(),
      );

      // Delete committed.
      notifier.simulateRollback = false;
      expect(
        await controller.deleteHistoryEntry(taskId: 't1', entry: replacement),
        isA<TaskHistoryMutationCommitted>(),
      );
      expect(
        AppLogger.fullLogText,
        contains('ui.task_info.history_removed | id=t1 history_count=0'),
      );
    });

    test(
      'emits exact validation reason codes and persistence rejection telemetry',
      () async {
        AppLogger.setEnabled(
          true,
          minimumLevel: LogLevel.warn,
          persistToDisk: false,
        );
        var clockNow = DateTime.utc(2026, 11, 21, 10);
        final fullHistory = <TaskHistoryEntry>[
          for (var i = 0; i < maxTdfHistoryPerTask; i++)
            TaskHistoryEntry(
              timestampUtc: DateTime.utc(2026, 1, 1).add(Duration(seconds: i)),
              text: 'entry $i',
            ),
        ];
        final board = TaskBoard.empty().addTask(
          'Full task',
          id: 't1',
          history: fullHistory,
          currentDate: clockNow,
        );
        final notifier = _TestHistoryTaskNotifier(board);
        final container = ProviderContainer(
          overrides: [
            taskNotifierProvider.overrideWith(() => notifier),
            clockProvider.overrideWithValue(() => clockNow),
            appLocaleProvider.overrideWithValue(const Locale('en')),
          ],
        );
        addTearDown(container.dispose);
        await container.read(taskNotifierProvider.future);

        final controller = container.read(taskInfoControllerProvider);
        final task = container.read(taskNotifierProvider).value?.findTask('t1');
        expect(task, isNotNull);
        if (task == null) return;

        // Empty text.
        expect(
          await controller.appendHistoryEntry(
            currentTask: task,
            rawText: '   ',
          ),
          isA<TaskHistoryMutationFailed>(),
        );
        // Control char.
        expect(
          await controller.appendHistoryEntry(
            currentTask: task,
            rawText: 'bad\x00char',
          ),
          isA<TaskHistoryMutationFailed>(),
        );
        // Unpaired surrogate.
        expect(
          await controller.appendHistoryEntry(
            currentTask: task,
            rawText: String.fromCharCode(0xD800),
          ),
          isA<TaskHistoryMutationFailed>(),
        );
        // Text too long.
        expect(
          await controller.appendHistoryEntry(
            currentTask: task,
            rawText: 'x' * (maxTdfTextLength + 1),
          ),
          isA<TaskHistoryMutationFailed>(),
        );
        // Max exceeded.
        expect(
          await controller.appendHistoryEntry(
            currentTask: task,
            rawText: 'overflow entry',
          ),
          isA<TaskHistoryMutationFailed>(),
        );
        // Invalid timestamp bounds (year 10000).
        clockNow = DateTime.utc(10000, 1, 1);
        expect(
          await controller.appendHistoryEntry(
            currentTask: task,
            rawText: 'out of range',
          ),
          isA<TaskHistoryMutationFailed>(),
        );
        clockNow = DateTime.utc(2026, 11, 21, 10);

        // Persistence rejections for TdfErrorKind variants + FormatException.
        final entry0 = fullHistory.first;
        for (final error in const <Object>[
          TdfException(kind: TdfErrorKind.emptyText, line: 0, message: 'e'),
          TdfException(kind: TdfErrorKind.limitExceeded, line: 0, message: 'l'),
          TdfException(
            kind: TdfErrorKind.unexpectedToken,
            line: 0,
            message: 'u',
          ),
          FormatException('bad ts'),
        ]) {
          notifier.errorToThrow = error;
          expect(
            await controller.updateHistoryEntry(
              taskId: 't1',
              originalEntry: entry0,
              rawText: 'valid change',
            ),
            isA<TaskHistoryMutationFailed>(),
            reason: 'Expected TaskHistoryMutationFailed for $error',
          );
        }

        final logText = AppLogger.fullLogText;
        for (final reason in const <String>[
          'reason=empty_text',
          'reason=control_char',
          'reason=unpaired_surrogate',
          'reason=text_too_long',
          'reason=max_exceeded',
          'reason=invalid_timestamp',
          'ui.task_info.history_persist_rejected',
        ]) {
          expect(
            logText,
            contains(reason),
            reason: 'Expected telemetry log to contain $reason',
          );
        }
      },
    );
  });
}
