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

      final container = ProviderContainer(
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

      // With LocationStatus.unavailable, fix is null so location condition blocks again.
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
  });
}
