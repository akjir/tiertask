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
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/presentation/board_presentation_providers.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/location_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/app_version_repository.dart';
import 'package:tiertask/services/tdf_service.dart';

class _StubTaskNotifier extends TaskNotifier {
  _StubTaskNotifier(this._board);

  final TaskBoard _board;

  @override
  Future<TaskBoard> build() async => _board;
}

class _StubWebDavConfigNotifier extends WebDavConfigNotifier {
  _StubWebDavConfigNotifier(this._config);

  final WebDavConfig _config;

  @override
  Future<WebDavConfig> build() async => _config;

  void setConfig(WebDavConfig next) {
    state = AsyncData<WebDavConfig>(next);
  }
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

final class _DisposalObserver extends ProviderObserver {
  final List<Object> disposedProviders = <Object>[];

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    disposedProviders.add(context.provider);
  }
}

void main() {
  group('AppVersionViewModel and appVersionViewModelProvider', () {
    test('parses version prefix and build metadata across variants', () {
      expect(
        AppVersionViewModel.fromRawVersion('v0.4.0+12.abc123.dev'),
        equals(
          const AppVersionViewModel(
            versionLabel: 'Version 0.4.0',
            buildSuffix: '+12.abc123.dev',
          ),
        ),
      );
      expect(
        AppVersionViewModel.fromRawVersion('V1.2.3+99.deadbeef'),
        equals(
          const AppVersionViewModel(
            versionLabel: 'Version 1.2.3',
            buildSuffix: '+99.deadbeef',
          ),
        ),
      );
      expect(
        AppVersionViewModel.fromRawVersion('2.0.0'),
        equals(
          const AppVersionViewModel(
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
          container.read(appVersionViewModelProvider),
          equals(
            AppVersionViewModel.fromRawVersion(
              AppVersionRepository.defaultFullVersion,
            ),
          ),
        );

        await container.read(appVersionProvider.future);
        expect(
          container.read(appVersionViewModelProvider),
          equals(
            const AppVersionViewModel(
              versionLabel: 'Version 0.4.0',
              buildSuffix: '+5.abcdef1',
            ),
          ),
        );
      },
    );
  });

  group('TdfPreviewController', () {
    test('returns TdfPreviewSuccess for valid board and localized TdfPreviewLimitExceeded on TdfException', () {
      final board = TaskBoard.empty().addTask(
        'Preview task',
        id: 't1',
        currentDate: DateTime.utc(2026, 11, 21),
      );

      final successContainer = ProviderContainer();
      addTearDown(successContainer.dispose);

      final successResult = successContainer
          .read(tdfPreviewControllerProvider)
          .serializeBoard(board);
      expect(successResult, isA<TdfPreviewSuccess>());
      expect(
        (successResult as TdfPreviewSuccess).content,
        contains('Preview task'),
      );

      final failingContainer = ProviderContainer(
        overrides: [
          tdfServiceProvider.overrideWithValue(_ThrowingTdfService()),
          appLocaleProvider.overrideWithValue(const Locale('de')),
        ],
      );
      addTearDown(failingContainer.dispose);

      final deResult = failingContainer
          .read(tdfPreviewControllerProvider)
          .serializeBoard(board);
      expect(
        deResult,
        equals(
          TdfPreviewLimitExceeded(
            lookupAppLocalizations(const Locale('de')).errorLocalFileTooLarge,
          ),
        ),
      );

      final enResult = failingContainer
          .read(tdfPreviewControllerProvider)
          .serializeBoard(board, locale: const Locale('en'));
      expect(
        enResult,
        equals(
          TdfPreviewLimitExceeded(
            lookupAppLocalizations(const Locale('en')).errorLocalFileTooLarge,
          ),
        ),
      );
    });
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

      // Scoped label inactive -> hidden from evaluated board.
      expect(
        container
            .read(evaluatedBoardProvider(null))
            .value
            ?.findTierOfTask('t_loc'),
        isNull,
      );

      // Scoped label active but location still outside radius -> blocked.
      expect(
        container
            .read(evaluatedBoardProvider('work'))
            .value
            ?.findTierOfTask('t_loc'),
        equals(TaskTier.blocked),
      );

      // Move inside office radius -> unblocked, pulled into focus (auto-pull fills empty focus).
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

      // With LocationStatus.unavailable, activeFix is null so location conditions fail open.
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

      // Verify autoDispose releases unreferenced family label instances.
      disposalObserver.disposedProviders.clear();
      final tempSub = container.listen(
        evaluatedBoardProvider('work'),
        (_, _) {},
      );
      expect(disposalObserver.disposedProviders, isEmpty);
      tempSub.close();
      await Future<void>.delayed(Duration.zero);
      expect(
        disposalObserver.disposedProviders,
        contains(evaluatedBoardProvider('work')),
        reason: 'evaluatedBoardProvider must autoDispose unused activeLabelId instances',
      );

      // Verify dueLeadWindow promotes an urgent task above filled Focus/Ready slots.
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

      // Verify boundaryTickProvider triggers re-evaluation when clock crosses suspension boundary.
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

    test('evaluatedBoardProvider skips re-evaluation for theme, language, and diagnostics config changes', () async {
      final now = DateTime.utc(2026, 11, 21, 9);
      final board = TaskBoard.empty().addTask(
        'Task 1',
        id: 't_eval_001',
        currentDate: now,
      );
      final configNotifier = _StubWebDavConfigNotifier(
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
          webDavConfigProvider.overrideWith(() => configNotifier),
        ],
      );
      addTearDown(container.dispose);

      await container.read(taskNotifierProvider.future);
      await container.read(webDavConfigProvider.future);
      final sub = container.listen(evaluatedBoardProvider(null), (_, _) {});
      addTearDown(sub.close);

      final baselineClockCalls = clockCalls;
      configNotifier.setConfig(
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

      configNotifier.setConfig(
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
    });
  });
}
