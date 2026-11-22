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

import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/board_providers.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/location_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/app_version_repository.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/services/tdf_service.dart';

class _CountingTdfService extends TdfService {
  int serializeCalls = 0;

  @override
  String serialize(TaskBoard board) {
    serializeCalls++;
    return super.serialize(board);
  }
}

final class _DisposalObserver extends ProviderObserver {
  final List<Object> disposedProviders = <Object>[];

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    disposedProviders.add(context.provider);
  }
}

class _OversizedTdfService extends TdfService {
  _OversizedTdfService(this._output);

  final String _output;

  @override
  String serialize(TaskBoard board) => _output;
}

class _PendingTaskNotifier extends TaskNotifier {
  final Completer<TaskBoard> _completer = Completer<TaskBoard>();

  @override
  Future<TaskBoard> build() => _completer.future;
}

class _PendingWebDavConfigNotifier extends WebDavConfigNotifier {
  final Completer<WebDavConfig> _completer = Completer<WebDavConfig>();

  @override
  Future<WebDavConfig> build() => _completer.future;
}

class _StubActiveWorkspaceNotifier extends ActiveWorkspaceNotifier {
  _StubActiveWorkspaceNotifier(this._workspace);

  final AppWorkspace _workspace;

  @override
  Future<AppWorkspace> build() async => _workspace;
}

class _StubLocationNotifier extends LocationNotifier {
  _StubLocationNotifier(this._initialState);

  final LocationState _initialState;

  @override
  LocationState build() => _initialState;

  void setLocationState(LocationState next) {
    state = next;
  }
}

class _StubTaskNotifier extends TaskNotifier {
  _StubTaskNotifier(this._board);

  final TaskBoard _board;

  @override
  Future<TaskBoard> build() async => _board;

  void setBoard(TaskBoard next) {
    state = AsyncData<TaskBoard>(next);
  }
}

class _StubWebDavConfigNotifier extends WebDavConfigNotifier {
  _StubWebDavConfigNotifier(this._configuration);

  final WebDavConfig _configuration;

  @override
  Future<WebDavConfig> build() async => _configuration;

  void setConfiguration(WebDavConfig next) {
    state = AsyncData<WebDavConfig>(next);
  }
}

class _ThrowingTdfService extends TdfService {
  @override
  String serialize(TaskBoard board) {
    throw const TdfException(
      kind: TdfErrorKind.limitExceeded,
      line: 0,
      message: 'Serialized file exceeds maximum allowed byte size.',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.resetForTesting(clock: () => DateTime.utc(2026, 11, 21, 10));
  });

  tearDown(() {
    AppLogger.resetForTesting();
  });

  group('AppVersionDisplay and appVersionDisplayProvider', () {
    test('parses version prefix and build metadata across variants', () {
      const first = AppVersionDisplay(
        versionLabel: 'Version 0.4.0',
        buildSuffix: '+12.abc123.dev',
      );
      expect(
        AppVersionDisplay.fromRawVersion(' v0.4.0+12.abc123.dev '),
        equals(first),
      );
      expect(
        AppVersionDisplay.fromRawVersion('v0.4.0+12.abc123.dev').hashCode,
        equals(first.hashCode),
      );
      expect(
        AppVersionDisplay.fromRawVersion('V1.2.3+99.deadbeef'),
        equals(
          const AppVersionDisplay(
            versionLabel: 'Version 1.2.3',
            buildSuffix: '+99.deadbeef',
          ),
        ),
      );
      expect(
        AppVersionDisplay.fromRawVersion('2.0.0'),
        equals(
          const AppVersionDisplay(
            versionLabel: 'Version 2.0.0',
            buildSuffix: '',
          ),
        ),
      );
    });

    test(
      'falls back to AppVersionRepository.defaultFullVersion when loading',
      () async {
        final container = ProviderContainer(
          overrides: [
            appVersionRepositoryProvider.overrideWithValue(
              const FakeAppVersionRepository(version: 'v0.4.0+5.abcdef1'),
            ),
          ],
        );
        addTearDown(container.dispose);

        expect(
          container.read(appVersionDisplayProvider),
          equals(
            AppVersionDisplay.fromRawVersion(
              AppVersionRepository.defaultFullVersion,
            ),
          ),
        );

        await container.read(appVersionProvider.future);
        expect(
          container.read(appVersionDisplayProvider),
          equals(
            const AppVersionDisplay(
              versionLabel: 'Version 0.4.0',
              buildSuffix: '+5.abcdef1',
            ),
          ),
        );
      },
    );
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
      final deferredTask = TaskItem(
        id: 'deferred',
        title: 'Deferred',
        suspendedAt: DateTime.utc(2026, 11, 21, 11),
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
          tasks: <TaskItem>[completedTask, foreverSuspended],
          nowUtc: now,
          dueLeadWindow: const Duration(hours: 24),
        ),
        isNull,
      );

      expect(
        BoardBoundaryTimer.nextBoundaryUtc(
          tasks: <TaskItem>[deferredTask, activeDue, passiveDue],
          nowUtc: now,
          dueLeadWindow: const Duration(hours: 24),
        ),
        equals(DateTime.utc(2026, 11, 21, 11)),
      );

      expect(
        BoardBoundaryTimer.nextBoundaryUtc(
          tasks: <TaskItem>[passiveDue, activeDue, farFuture],
          nowUtc: now,
          dueLeadWindow: const Duration(hours: 24),
        ),
        equals(DateTime.utc(2026, 11, 21, 12)),
      );

      expect(
        BoardBoundaryTimer.nextBoundaryUtc(
          tasks: <TaskItem>[passiveDue, farFuture],
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

      final subscription = container.listen(
        boardBoundaryTimerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      expect(
        container.read(boardBoundaryTimerProvider),
        equals(DateTime.utc(2026, 11, 21, 10, 0, 1)),
      );
      expect(AppLogger.fullLogText, contains('ui.boundary_timer.scheduled'));

      final notifier = container.read(boardBoundaryTimerProvider.notifier);
      final tickBeforePause = container.read(boundaryTickProvider);
      notifier.handleAppLifecycleState(AppLifecycleState.paused);
      expect(container.read(boardBoundaryTimerProvider), isNull);

      fakeNow = DateTime.utc(2026, 11, 21, 10, 0, 1);
      notifier.handleAppLifecycleState(AppLifecycleState.resumed);
      expect(container.read(boundaryTickProvider), equals(tickBeforePause + 1));
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
      final subscription = container.listen(
        boardBoundaryTimerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      expect(
        container.read(boardBoundaryTimerProvider),
        equals(targetBoundary),
      );
      final initialTick = container.read(boundaryTickProvider);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(container.read(boundaryTickProvider), equals(initialTick));
      expect(
        container.read(boardBoundaryTimerProvider),
        equals(targetBoundary),
      );

      fakeNow = DateTime.utc(2026, 11, 21, 10, 0, 2);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(container.read(boundaryTickProvider), equals(initialTick + 1));
      expect(container.read(boardBoundaryTimerProvider), isNull);
      expect(AppLogger.fullLogText, contains('ui.boundary_timer.fired'));
    });

    test(
      'resume triggers only a single boundary sync instead of double syncing',
      () async {
        var fakeNow = DateTime.utc(2026, 11, 21, 10);
        var clockCalls = 0;
        final dueAt = DateTime.utc(2026, 11, 22, 10, 0, 1);
        final board = TaskBoard.empty().addTask(
          'Resume check',
          id: 't1',
          dueAt: dueAt,
          currentDate: fakeNow,
        );

        final container = ProviderContainer(
          overrides: [
            clockProvider.overrideWithValue(() {
              clockCalls++;
              return fakeNow;
            }),
            taskNotifierProvider.overrideWith(() => _StubTaskNotifier(board)),
            webDavConfigProvider.overrideWith(
              () => _StubWebDavConfigNotifier(
                const WebDavConfig(dueLeadWindow: DueLeadWindow.hours24),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(taskNotifierProvider.future);
        await container.read(webDavConfigProvider.future);

        final subscription = container.listen(
          boardBoundaryTimerProvider,
          (_, _) {},
        );
        addTearDown(subscription.close);

        final notifier = container.read(boardBoundaryTimerProvider.notifier);
        notifier.handleAppLifecycleState(AppLifecycleState.paused);
        expect(container.read(boardBoundaryTimerProvider), isNull);

        final callsBeforeFirstResume = clockCalls;
        final tickBeforeFirstResume = container.read(boundaryTickProvider);
        fakeNow = DateTime.utc(2026, 11, 21, 10, 0, 1);
        notifier.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(
          container.read(boundaryTickProvider),
          equals(tickBeforeFirstResume + 1),
        );
        expect(container.read(boardBoundaryTimerProvider), equals(dueAt));
        expect(
          clockCalls,
          equals(callsBeforeFirstResume + 1),
          reason: 'Resuming must sync exactly once via boundaryTickProvider listener without a duplicate _syncFromProviders call',
        );

        notifier.handleAppLifecycleState(AppLifecycleState.paused);
        final callsBeforeSecondResume = clockCalls;
        fakeNow = DateTime.utc(2026, 11, 22, 11);
        notifier.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(container.read(boardBoundaryTimerProvider), isNull);
        expect(
          clockCalls,
          equals(callsBeforeSecondResume + 1),
          reason: 'Resuming when no future boundaries remain must still sync exactly once',
        );
      },
    );
  });

  group('evaluatedBoardProvider', () {
    test('evaluates board with active label, location fix, clock, lead window, and boundary tick', () async {
      var now = DateTime.utc(2026, 11, 21, 9);
      final board = TaskBoard.empty()
          .addLocation(
            'Office',
            id: 'office',
            latitude: 52.52,
            longitude: 13.405,
            radius: 200,
            currentDate: now,
          )
          .addLabel('Work', id: 'work', isScoped: true, currentDate: now)
          .addTask(
            'Office work',
            id: 't_loc',
            labelIds: const <String>['work'],
            conditions: const <TaskCondition>[
              LocationTaskCondition(locationIds: <String>['office']),
            ],
            dueAt: DateTime.utc(2026, 11, 22, 12),
            targetTier: TaskTier.planned,
            currentDate: now,
          );

      final locationNotifier = _StubLocationNotifier(
        LocationState(
          status: LocationStatus.found,
          fix: const LocationFix(latitude: 48.1351, longitude: 11.5820),
          updatedAt: now,
        ),
      );

      final disposalObserver = _DisposalObserver();
      final container = ProviderContainer(
        observers: [disposalObserver],
        overrides: [
          clockProvider.overrideWithValue(() => now),
          taskNotifierProvider.overrideWith(() => _StubTaskNotifier(board)),
          webDavConfigProvider.overrideWith(
            () => _StubWebDavConfigNotifier(
              const WebDavConfig(dueLeadWindow: DueLeadWindow.hours24),
            ),
          ),
          locationStateProvider.overrideWith(() => locationNotifier),
        ],
      );
      addTearDown(container.dispose);

      await container.read(taskNotifierProvider.future);
      await container.read(webDavConfigProvider.future);

      expect(
        container
            .read(evaluatedBoardProvider(null))
            .value
            ?.findTierOfTask('t_loc'),
        isNull,
      );

      expect(
        container
            .read(evaluatedBoardProvider('work'))
            .value
            ?.findTierOfTask('t_loc'),
        equals(TaskTier.blocked),
      );

      locationNotifier.setLocationState(
        LocationState(
          status: LocationStatus.found,
          fix: const LocationFix(latitude: 52.52, longitude: 13.405),
          updatedAt: now,
        ),
      );
      expect(
        container
            .read(evaluatedBoardProvider('work'))
            .value
            ?.findTierOfTask('t_loc'),
        equals(TaskTier.focus),
      );

      locationNotifier.setLocationState(
        LocationState(
          status: LocationStatus.unavailable,
          fix: const LocationFix(latitude: 52.52, longitude: 13.405),
          updatedAt: now,
        ),
      );
      final unavailableBoard = container
          .read(evaluatedBoardProvider('work'))
          .value;
      expect(unavailableBoard?.findTierOfTask('t_loc'), equals(TaskTier.focus));

      disposalObserver.disposedProviders.clear();
      final temporarySubscription = container.listen(
        evaluatedBoardProvider('work'),
        (_, _) {},
      );
      expect(disposalObserver.disposedProviders, isEmpty);
      temporarySubscription.close();
      await Future<void>.delayed(Duration.zero);
      expect(
        disposalObserver.disposedProviders,
        contains(evaluatedBoardProvider('work')),
        reason: 'evaluatedBoardProvider must autoDispose unused activeLabelId instances',
      );

      final urgentBoard = TaskBoard.empty()
          .addTask('Focus 1', id: 'f1', currentDate: now)
          .addTask('Focus 2', id: 'f2', currentDate: now)
          .addTask('Focus 3', id: 'f3', currentDate: now)
          .addTask('Ready 1', id: 'r1', currentDate: now)
          .addTask(
            'Urgent due task',
            id: 't_due',
            dueAt: now.add(const Duration(hours: 6)),
            currentDate: now,
          );
      final leadOffContainer = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          taskNotifierProvider.overrideWith(
            () => _StubTaskNotifier(urgentBoard),
          ),
          webDavConfigProvider.overrideWith(
            () => _StubWebDavConfigNotifier(
              const WebDavConfig(dueLeadWindow: DueLeadWindow.off),
            ),
          ),
        ],
      );
      addTearDown(leadOffContainer.dispose);
      await leadOffContainer.read(taskNotifierProvider.future);
      await leadOffContainer.read(webDavConfigProvider.future);
      expect(
        leadOffContainer
            .read(evaluatedBoardProvider(null))
            .value
            ?.findTierOfTask('t_due'),
        equals(TaskTier.ready),
      );

      final leadOnContainer = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          taskNotifierProvider.overrideWith(
            () => _StubTaskNotifier(urgentBoard),
          ),
          webDavConfigProvider.overrideWith(
            () => _StubWebDavConfigNotifier(
              const WebDavConfig(dueLeadWindow: DueLeadWindow.hours24),
            ),
          ),
        ],
      );
      addTearDown(leadOnContainer.dispose);
      await leadOnContainer.read(taskNotifierProvider.future);
      await leadOnContainer.read(webDavConfigProvider.future);
      expect(
        leadOnContainer
            .read(evaluatedBoardProvider(null))
            .value
            ?.findTierOfTask('t_due'),
        equals(TaskTier.focus),
      );

      final suspendedBoard = TaskBoard.empty().addTask(
        'Deferred task',
        id: 't_sus',
        suspendedAt: DateTime.utc(2026, 11, 21, 10),
        targetTier: TaskTier.planned,
        currentDate: now,
      );
      final tickContainer = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          taskNotifierProvider.overrideWith(
            () => _StubTaskNotifier(suspendedBoard),
          ),
          webDavConfigProvider.overrideWith(
            () => _StubWebDavConfigNotifier(const WebDavConfig()),
          ),
        ],
      );
      addTearDown(tickContainer.dispose);
      await tickContainer.read(taskNotifierProvider.future);
      await tickContainer.read(webDavConfigProvider.future);

      expect(
        tickContainer
            .read(evaluatedBoardProvider(null))
            .value
            ?.findTierOfTask('t_sus'),
        equals(TaskTier.blocked),
      );
      now = DateTime.utc(2026, 11, 21, 10, 1);
      tickContainer.read(boundaryTickProvider.notifier).increment();
      expect(
        tickContainer
            .read(evaluatedBoardProvider(null))
            .value
            ?.findTierOfTask('t_sus'),
        equals(TaskTier.focus),
      );
    });

    test(
      'skips re-evaluation for theme, language, and diagnostics config changes',
      () async {
        final now = DateTime.utc(2026, 11, 21, 9);
        final board = TaskBoard.empty().addTask(
          'Task 1',
          id: 't_eval_001',
          currentDate: now,
        );
        final configurationNotifier = _StubWebDavConfigNotifier(
          const WebDavConfig(
            themePalette: AppThemePalette.calm,
            themeMode: AppThemeMode.light,
            language: AppLanguage.english,
            dueLeadWindow: DueLeadWindow.hours24,
            timeZoneMode: AppTimeZoneMode.manual,
          ),
        );
        var clockCalls = 0;
        final container = ProviderContainer(
          overrides: [
            clockProvider.overrideWithValue(() {
              clockCalls++;
              return now;
            }),
            taskNotifierProvider.overrideWith(() => _StubTaskNotifier(board)),
            webDavConfigProvider.overrideWith(() => configurationNotifier),
          ],
        );
        addTearDown(container.dispose);

        await container.read(taskNotifierProvider.future);
        await container.read(webDavConfigProvider.future);
        final subscription = container.listen(
          evaluatedBoardProvider(null),
          (_, _) {},
        );
        addTearDown(subscription.close);

        final baselineClockCalls = clockCalls;
        configurationNotifier.setConfiguration(
          const WebDavConfig(
            themePalette: AppThemePalette.plumUmber,
            themeMode: AppThemeMode.dark,
            language: AppLanguage.german,
            diagnosticsEnabled: true,
            dueLeadWindow: DueLeadWindow.hours24,
            timeZoneMode: AppTimeZoneMode.manual,
          ),
        );
        container.read(evaluatedBoardProvider(null));
        expect(
          clockCalls,
          equals(baselineClockCalls),
          reason: 'Non-evaluation preference updates must not recompute evaluatedBoardProvider',
        );

        configurationNotifier.setConfiguration(
          const WebDavConfig(
            themePalette: AppThemePalette.plumUmber,
            themeMode: AppThemeMode.dark,
            language: AppLanguage.german,
            diagnosticsEnabled: true,
            dueLeadWindow: DueLeadWindow.days7,
            timeZoneMode: AppTimeZoneMode.manual,
          ),
        );
        container.read(evaluatedBoardProvider(null));
        expect(
          clockCalls,
          greaterThan(baselineClockCalls),
          reason:
              'Updating dueLeadWindow must re-evaluate evaluatedBoardProvider',
        );
      },
    );

    test('falls back to activeWorkspaceProvider evaluation config while webDavConfigProvider loads', () async {
      final now = DateTime.utc(2026, 11, 21, 9);
      final urgentBoard = TaskBoard.empty()
          .addTask('Focus 1', id: 'f1', currentDate: now)
          .addTask('Focus 2', id: 'f2', currentDate: now)
          .addTask('Focus 3', id: 'f3', currentDate: now)
          .addTask('Ready 1', id: 'r1', currentDate: now)
          .addTask(
            'Urgent due task',
            id: 't_due',
            dueAt: now.add(const Duration(hours: 6)),
            currentDate: now,
          );

      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          taskNotifierProvider.overrideWith(
            () => _StubTaskNotifier(urgentBoard),
          ),
          webDavConfigProvider.overrideWith(_PendingWebDavConfigNotifier.new),
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

      expect(
        container
            .read(evaluatedBoardProvider(null))
            .value
            ?.findTierOfTask('t_due'),
        equals(TaskTier.ready),
        reason: 'While webDavConfigProvider is loading, DueLeadWindow.off from activeWorkspaceProvider must prevent Focus promotion',
      );
    });
  });

  group('rawTdfPreviewProvider', () {
    test('returns empty preview without serializing while taskNotifierProvider is loading', () {
      final countingService = _CountingTdfService();
      final container = ProviderContainer(
        overrides: [
          taskNotifierProvider.overrideWith(_PendingTaskNotifier.new),
          tdfServiceProvider.overrideWithValue(countingService),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(rawTdfPreviewProvider),
        equals(
          const RawTdfPreview(
            isLimitExceeded: false,
            content: '',
            byteCount: 0,
            lineCount: 0,
          ),
        ),
      );
      expect(countingService.serializeCalls, equals(0));
    });

    test(
      'serializes board with accurate UTF-8 byte count and line count',
      () async {
        final now = DateTime.utc(2026, 11, 21, 10);
        final board = TaskBoard.empty().addTask(
          'Übung prüfen',
          id: 't1',
          currentDate: now,
        );
        final container = ProviderContainer(
          overrides: [
            taskNotifierProvider.overrideWith(() => _StubTaskNotifier(board)),
          ],
        );
        addTearDown(container.dispose);

        await container.read(taskNotifierProvider.future);

        final preview = container.read(rawTdfPreviewProvider);
        expect(preview.isLimitExceeded, isFalse);
        expect(preview.errorMessage, isNull);
        expect(preview.content, contains('Übung prüfen'));
        expect(preview.byteCount, equals(utf8.encode(preview.content).length));
        expect(preview.byteCount, greaterThan(preview.content.length));
        expect(
          preview.lineCount,
          equals('\n'.allMatches(preview.content).length),
        );
        expect(
          preview,
          equals(
            RawTdfPreview(
              isLimitExceeded: false,
              content: preview.content,
              byteCount: preview.byteCount,
              lineCount: preview.lineCount,
            ),
          ),
        );
        expect(
          preview.hashCode,
          equals(
            RawTdfPreview(
              isLimitExceeded: false,
              content: preview.content,
              byteCount: preview.byteCount,
              lineCount: preview.lineCount,
            ).hashCode,
          ),
        );
      },
    );

    test(
      'handles TdfException limit-exceeded state with localized error message',
      () async {
        final board = TaskBoard.empty().addTask(
          'Preview task',
          id: 't1',
          currentDate: DateTime.utc(2026, 11, 21),
        );

        final germanContainer = ProviderContainer(
          overrides: [
            taskNotifierProvider.overrideWith(() => _StubTaskNotifier(board)),
            tdfServiceProvider.overrideWithValue(_ThrowingTdfService()),
            appLocaleProvider.overrideWithValue(const Locale('de')),
          ],
        );
        addTearDown(germanContainer.dispose);
        await germanContainer.read(taskNotifierProvider.future);

        expect(
          germanContainer.read(rawTdfPreviewProvider),
          equals(
            RawTdfPreview(
              isLimitExceeded: true,
              content: '',
              byteCount: 0,
              lineCount: 0,
              errorMessage: lookupAppLocalizations(const Locale('de'))
                  .errorLocalFileTooLarge,
            ),
          ),
        );

        final englishContainer = ProviderContainer(
          overrides: [
            taskNotifierProvider.overrideWith(() => _StubTaskNotifier(board)),
            tdfServiceProvider.overrideWithValue(_ThrowingTdfService()),
            appLocaleProvider.overrideWithValue(const Locale('en')),
          ],
        );
        addTearDown(englishContainer.dispose);
        await englishContainer.read(taskNotifierProvider.future);

        expect(
          englishContainer.read(rawTdfPreviewProvider),
          equals(
            RawTdfPreview(
              isLimitExceeded: true,
              content: '',
              byteCount: 0,
              lineCount: 0,
              errorMessage: lookupAppLocalizations(const Locale('en'))
                  .errorLocalFileTooLarge,
            ),
          ),
        );
      },
    );

    test('marks limit exceeded when serialized output surpasses maxTdfLineCount without throwing', () async {
      final board = TaskBoard.empty();
      final oversizedContent = List<String>.filled(
        maxTdfLineCount + 1,
        'x',
      ).join('\n');
      final withTrailingNewline = '$oversizedContent\n';
      final container = ProviderContainer(
        overrides: [
          taskNotifierProvider.overrideWith(() => _StubTaskNotifier(board)),
          tdfServiceProvider.overrideWithValue(
            _OversizedTdfService(withTrailingNewline),
          ),
          appLocaleProvider.overrideWithValue(const Locale('en')),
        ],
      );
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      final preview = container.read(rawTdfPreviewProvider);
      expect(preview.isLimitExceeded, isTrue);
      expect(preview.content, isEmpty);
      expect(preview.lineCount, equals(maxTdfLineCount + 1));
      expect(
        preview.byteCount,
        equals(utf8.encode(withTrailingNewline).length),
      );
      expect(
        preview.errorMessage,
        equals(
          lookupAppLocalizations(const Locale('en')).errorLocalFileTooLarge,
        ),
      );
    });

    test('auto-disposes when listener closes and performs zero serializations on subsequent board updates', () async {
      final now = DateTime.utc(2026, 11, 21, 10);
      final initialBoard = TaskBoard.empty().addTask(
        'Initial',
        id: 't1',
        currentDate: now,
      );
      final taskNotifier = _StubTaskNotifier(initialBoard);
      final countingService = _CountingTdfService();
      final disposalObserver = _DisposalObserver();

      final container = ProviderContainer(
        observers: [disposalObserver],
        overrides: [
          taskNotifierProvider.overrideWith(() => taskNotifier),
          tdfServiceProvider.overrideWithValue(countingService),
        ],
      );
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      final subscription = container.listen(rawTdfPreviewProvider, (_, _) {});
      expect(countingService.serializeCalls, equals(1));
      expect(subscription.read().content, contains('Initial'));

      final updatedBoard = initialBoard.addTask(
        'Second',
        id: 't2',
        currentDate: now,
      );
      taskNotifier.setBoard(updatedBoard);
      expect(subscription.read().content, contains('Second'));
      expect(countingService.serializeCalls, equals(2));

      disposalObserver.disposedProviders.clear();
      subscription.close();
      await Future<void>.delayed(Duration.zero);
      expect(
        disposalObserver.disposedProviders,
        contains(rawTdfPreviewProvider),
        reason: 'rawTdfPreviewProvider must autoDispose once its last listener closes',
      );

      final postDisposeBoard = updatedBoard.addTask(
        'Third',
        id: 't3',
        currentDate: now,
      );
      taskNotifier.setBoard(postDisposeBoard);
      await Future<void>.delayed(Duration.zero);
      expect(
        countingService.serializeCalls,
        equals(2),
        reason: 'Disposed rawTdfPreviewProvider must perform zero serializations on subsequent board updates',
      );
    });
  });

  group('taskPrerequisiteCandidatesProvider', () {
    test('computes sorted draft and task candidates with cross-label cycle detection and completed filtering', () async {
      final fixedNow = DateTime.utc(2026, 11, 21, 10);
      const workLabel = TdfLabel(
        id: 'lblWork001',
        name: 'Work',
        color: '#2196F3',
      );
      final rootTask = TaskItem(
        id: 'tskRoot001',
        title: 'Beta Root',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
        labelIds: const <String>['lblWork001'],
      );
      final unlabeledBridge = TaskItem(
        id: 'tskMid0001',
        title: 'Alpha Bridge',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
        blockedByTaskIds: const <String>['tskRoot001'],
      );
      final leafTask = TaskItem(
        id: 'tskLeaf001',
        title: 'Gamma Leaf',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
        labelIds: const <String>['lblWork001'],
        blockedByTaskIds: const <String>['tskMid0001'],
      );
      final freeTask = TaskItem(
        id: 'tskFree001',
        title: 'delta free',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
      );
      final completedSelected = TaskItem(
        id: 'tskDoneSel',
        title: 'Completed Selected',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
        completedAt: fixedNow,
        isCompleted: true,
        completions: 1,
      );
      final completedUnselected = TaskItem(
        id: 'tskDoneIgn',
        title: 'Completed Ignored',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
        completedAt: fixedNow,
        isCompleted: true,
        completions: 1,
      );
      final taskWithCompletedDependency = TaskItem(
        id: 'tskHasDone',
        title: 'Epsilon Dependent',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
        blockedByTaskIds: const <String>['tskDoneSel'],
      );
      final board = TaskBoard.evaluate(
        tasks: <TaskItem>[
          rootTask,
          unlabeledBridge,
          leafTask,
          freeTask,
          completedSelected,
          completedUnselected,
          taskWithCompletedDependency,
        ],
        labels: const <TdfLabel>[workLabel],
        queueBlock: TdfQueueBlock(
          taskIds: const <String>[
            'tskRoot001',
            'tskMid0001',
            'tskLeaf001',
            'tskFree001',
            'tskHasDone',
          ],
        ),
        evaluationTime: fixedNow,
      );

      final disposalObserver = _DisposalObserver();
      final container = ProviderContainer(
        observers: [disposalObserver],
        overrides: [
          taskNotifierProvider.overrideWith(() => _StubTaskNotifier(board)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      final rootCandidates = container.read(
        taskPrerequisiteCandidatesProvider('tskRoot001'),
      );
      expect(
        rootCandidates,
        equals(const <PrerequisiteCandidate>[
          PrerequisiteCandidate(
            id: 'tskMid0001',
            title: 'Alpha Bridge',
            wouldCreateCycle: true,
            isCompleted: false,
          ),
          PrerequisiteCandidate(
            id: 'tskFree001',
            title: 'delta free',
            wouldCreateCycle: false,
            isCompleted: false,
          ),
          PrerequisiteCandidate(
            id: 'tskHasDone',
            title: 'Epsilon Dependent',
            wouldCreateCycle: false,
            isCompleted: false,
          ),
          PrerequisiteCandidate(
            id: 'tskLeaf001',
            title: 'Gamma Leaf',
            wouldCreateCycle: true,
            isCompleted: false,
          ),
        ]),
        reason: 'Candidates must sort case-insensitively by title, exclude self and unselected completed tasks, and flag direct/transitive cycles',
      );
      expect(
        rootCandidates.first.hashCode,
        equals(
          const PrerequisiteCandidate(
            id: 'tskMid0001',
            title: 'Alpha Bridge',
            wouldCreateCycle: true,
            isCompleted: false,
          ).hashCode,
        ),
      );

      final selectedCompletedCandidates = container.read(
        taskPrerequisiteCandidatesProvider('tskHasDone'),
      );
      expect(
        selectedCompletedCandidates,
        contains(
          const PrerequisiteCandidate(
            id: 'tskDoneSel',
            title: 'Completed Selected',
            wouldCreateCycle: false,
            isCompleted: true,
          ),
        ),
        reason: 'Already-selected completed prerequisite must remain visible with isCompleted=true',
      );
      expect(
        selectedCompletedCandidates.any(
          (candidate) => candidate.id == 'tskDoneIgn',
        ),
        isFalse,
        reason: 'Unselected completed tasks must be excluded',
      );

      final draftCandidates = container.read(
        taskPrerequisiteCandidatesProvider(null),
      );
      expect(
        draftCandidates.map((candidate) => candidate.id).toList(),
        equals(<String>[
          'tskMid0001',
          'tskRoot001',
          'tskFree001',
          'tskHasDone',
          'tskLeaf001',
        ]),
        reason: 'Draft candidates must include all open tasks sorted case-insensitively by title',
      );
      expect(
        draftCandidates.every(
          (candidate) => !candidate.wouldCreateCycle && !candidate.isCompleted,
        ),
        isTrue,
      );

      expect(
        container.read(taskPrerequisiteCandidatesProvider('tskDoneSel')),
        isEmpty,
        reason: 'Completed tasks cannot edit prerequisites',
      );
      expect(
        container.read(taskPrerequisiteCandidatesProvider('unknown999')),
        isEmpty,
        reason: 'Unknown task IDs must yield no prerequisite candidates',
      );

      disposalObserver.disposedProviders.clear();
      final subscription = container.listen(
        taskPrerequisiteCandidatesProvider('tskRoot001'),
        (_, _) {},
      );
      subscription.close();
      await Future<void>.delayed(Duration.zero);
      expect(
        disposalObserver.disposedProviders,
        contains(taskPrerequisiteCandidatesProvider('tskRoot001')),
        reason: 'taskPrerequisiteCandidatesProvider must autoDispose unused family instances',
      );
    });

    test('returns empty list while taskNotifierProvider is loading', () {
      final container = ProviderContainer(
        overrides: [
          taskNotifierProvider.overrideWith(_PendingTaskNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(taskPrerequisiteCandidatesProvider(null)), isEmpty);
      expect(
        container.read(taskPrerequisiteCandidatesProvider('tskRoot001')),
        isEmpty,
      );
    });
  });
}
