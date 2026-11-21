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
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/presentation/board_boundary_timer.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/services/app_logger.dart';

class _StubTaskNotifier extends TaskNotifier {
  _StubTaskNotifier(this._board);

  final TaskBoard _board;

  @override
  Future<TaskBoard> build() async => _board;
}

class _PendingWebDavConfigNotifier extends WebDavConfigNotifier {
  @override
  Future<WebDavConfig> build() async {
    await Future<void>.delayed(const Duration(hours: 1));
    return const WebDavConfig();
  }
}

class _StubActiveWorkspaceNotifier extends ActiveWorkspaceNotifier {
  _StubActiveWorkspaceNotifier(this._workspace);

  final AppWorkspace _workspace;

  @override
  Future<AppWorkspace> build() async => _workspace;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.resetForTesting(clock: () => DateTime.utc(2026, 11, 21, 10));
  });

  tearDown(() {
    AppLogger.resetForTesting();
  });

  group('BoardBoundaryTimer', () {
    test('clampTimerDelay enforces [25ms, 7 days] bounds', () {
      const cases = <(Duration, Duration)>[
        (Duration.zero, BoardBoundaryTimer.minTimerDelay),
        (Duration(milliseconds: -50), BoardBoundaryTimer.minTimerDelay),
        (Duration(milliseconds: 24), BoardBoundaryTimer.minTimerDelay),
        (Duration(milliseconds: 25), BoardBoundaryTimer.minTimerDelay),
        (Duration(seconds: 10), Duration(seconds: 10)),
        (Duration(days: 7), BoardBoundaryTimer.maxTimerChunk),
        (Duration(days: 30), BoardBoundaryTimer.maxTimerChunk),
      ];
      for (final (input, expected) in cases) {
        expect(
          BoardBoundaryTimer.clampTimerDelay(input),
          equals(expected),
          reason: 'clampTimerDelay($input) should return $expected',
        );
      }
    });

    test('nextBoundaryUtc picks earliest future deferral, active lead start, or due boundary', () {
      final now = DateTime.utc(2026, 11, 21, 10);
      final completedTask = TaskItem(
        id: 'done',
        title: 'Done',
        isCompleted: true,
        completedAt: now,
        dueAt: DateTime.utc(2026, 11, 21, 10, 5),
      );
      final foreverSuspended = TaskItem(
        id: 'forever',
        title: 'Forever',
        isSuspendedForever: true,
        suspendedAt: DateTime.utc(2026, 11, 21, 10, 1),
      );
      final passiveDue = TaskItem(
        id: 'passive',
        title: 'Passive',
        dueAt: DateTime.utc(2026, 11, 22, 10),
        isDuePassive: true,
      );
      final activeDue = TaskItem(
        id: 'active',
        title: 'Active',
        dueAt: DateTime.utc(2026, 11, 22, 12),
      );
      final farFuture = TaskItem(
        id: 'far',
        title: 'Far',
        dueAt: DateTime.utc(9999, 12, 31, 23, 59, 59),
      );

      expect(
        BoardBoundaryTimer.nextBoundaryUtc(
          tasks: [completedTask, foreverSuspended],
          nowUtc: now,
          dueLeadWindow: const Duration(hours: 24),
        ),
        isNull,
      );

      expect(
        BoardBoundaryTimer.nextBoundaryUtc(
          tasks: [passiveDue, activeDue, farFuture],
          nowUtc: now,
          dueLeadWindow: const Duration(hours: 24),
        ),
        equals(DateTime.utc(2026, 11, 21, 12)),
      );

      expect(
        BoardBoundaryTimer.nextBoundaryUtc(
          tasks: [passiveDue, farFuture],
          nowUtc: now,
          dueLeadWindow: const Duration(hours: 24),
        ),
        equals(DateTime.utc(2026, 11, 22, 10)),
      );
    });
  });

  group('boardBoundaryTimerProvider', () {
    test('uses activeWorkspaceProvider fallback while webDavConfigProvider loads and fires on boundary', () async {
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.debug,
        persistToDisk: false,
      );
      var fakeNow = DateTime.utc(2026, 11, 21, 10);
      final dueAt = DateTime.utc(2026, 11, 22, 10, 0, 1);
      final board = TaskBoard.empty().addTask(
        'Task 1',
        id: 't1',
        dueAt: dueAt,
        currentDate: fakeNow,
      );

      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => fakeNow),
          taskNotifierProvider.overrideWith(() => _StubTaskNotifier(board)),
          webDavConfigProvider.overrideWith(_PendingWebDavConfigNotifier.new),
          activeWorkspaceProvider.overrideWith(
            () => _StubActiveWorkspaceNotifier(
              const AppWorkspace(
                id: 'tasks',
                name: 'Tasks',
                config: WebDavConfig(dueLeadWindow: DueLeadWindow.hours24),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(taskNotifierProvider.future);
      await container.read(activeWorkspaceProvider.future);

      final sub = container.listen(boardBoundaryTimerProvider, (_, _) {});
      addTearDown(sub.close);

      // With 24h lead window from activeWorkspaceProvider fallback, boundary is 2026-11-21T10:00:01Z.
      expect(
        container.read(boardBoundaryTimerProvider),
        equals(DateTime.utc(2026, 11, 21, 10, 0, 1)),
      );
      expect(AppLogger.fullLogText, contains('ui.boundary_timer.scheduled'));

      // Pause cancels scheduled target; resume increments boundaryTickProvider and re-syncs.
      final notifier = container.read(boardBoundaryTimerProvider.notifier);
      final tickBeforePause = container.read(boundaryTickProvider);
      notifier.handleAppLifecycleState(AppLifecycleState.paused);
      expect(container.read(boardBoundaryTimerProvider), isNull);

      fakeNow = DateTime.utc(2026, 11, 21, 10, 0, 1);
      notifier.handleAppLifecycleState(AppLifecycleState.resumed);
      expect(container.read(boundaryTickProvider), equals(tickBeforePause + 1));
      // After crossing lead-window start, next scheduled boundary is exact dueAt.
      expect(container.read(boardBoundaryTimerProvider), equals(dueAt));
    });

    test('re-arms on early wakeup without spurious tick and increments when target is reached', () async {
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.debug,
        persistToDisk: false,
      );
      var fakeNow = DateTime.utc(2026, 11, 21, 10, 0, 0, 960);
      final targetBoundary = DateTime.utc(2026, 11, 21, 10, 0, 1);
      final board = TaskBoard.empty().addTask(
        'Soon',
        id: 't1',
        dueAt: targetBoundary,
        currentDate: fakeNow,
      );

      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => fakeNow),
          taskNotifierProvider.overrideWith(() => _StubTaskNotifier(board)),
          activeWorkspaceProvider.overrideWith(
            () => _StubActiveWorkspaceNotifier(
              const AppWorkspace(
                id: 'tasks',
                name: 'Tasks',
                config: WebDavConfig(dueLeadWindow: DueLeadWindow.off),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(taskNotifierProvider.future);
      await container.read(activeWorkspaceProvider.future);
      final sub = container.listen(boardBoundaryTimerProvider, (_, _) {});
      addTearDown(sub.close);

      expect(
        container.read(boardBoundaryTimerProvider),
        equals(targetBoundary),
      );
      final initialTick = container.read(boundaryTickProvider);

      // Let timer fire while fakeNow is still before target -> must re-arm without incrementing tick.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(container.read(boundaryTickProvider), equals(initialTick));
      expect(
        container.read(boardBoundaryTimerProvider),
        equals(targetBoundary),
      );

      // Advance fake clock past target -> timer fires, logs event, increments tick.
      fakeNow = DateTime.utc(2026, 11, 21, 10, 0, 2);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(container.read(boundaryTickProvider), equals(initialTick + 1));
      expect(container.read(boardBoundaryTimerProvider), isNull);
      expect(AppLogger.fullLogText, contains('ui.boundary_timer.fired'));
    });
  });
}
