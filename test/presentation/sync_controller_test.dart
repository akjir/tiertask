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
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/l10n/app_localizations.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/location_state.dart';
import 'package:tiertask/models/storage_file_read_status.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/presentation/app_shell_controller.dart';
import 'package:tiertask/presentation/floating_notice_controller.dart';
import 'package:tiertask/presentation/shell_models.dart';
import 'package:tiertask/presentation/sync_controller.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/location_providers.dart';
import 'package:tiertask/providers/sync_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/location_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';

import '../ui/test_helpers.dart';

/// Controllable [LocationNotifier] double for deterministic status projections and refresh assertions.
class _FakeLocationNotifier extends LocationNotifier {
  _FakeLocationNotifier({required this.initialState, this.onRefresh});

  final LocationState initialState;
  final Future<void> Function(_FakeLocationNotifier notifier)? onRefresh;
  int refreshCalls = 0;

  @override
  LocationState build() => initialState;

  @override
  Future<void> refreshLocation() async {
    refreshCalls++;
    final callback = onRefresh;
    if (callback != null) {
      await callback(this);
    }
  }

  void setLocationState(LocationState nextState) {
    state = nextState;
  }
}

/// Controllable [LocationRepository] double supporting deferred lookup completion.
class _FakeLocationRepository implements LocationRepository {
  _FakeLocationRepository({this.onDetermineLocation});

  Future<LocationFix?> Function({required bool forceRefresh})?
  onDetermineLocation;
  int determineCalls = 0;
  bool lastForceRefresh = false;

  @override
  Future<LocationFix?> determineLocation({bool forceRefresh = false}) async {
    determineCalls++;
    lastForceRefresh = forceRefresh;
    final callback = onDetermineLocation;
    if (callback != null) {
      return callback(forceRefresh: forceRefresh);
    }
    return null;
  }

  @override
  Future<List<GeocodingCandidate>> searchLocations(String query) async =>
      const <GeocodingCandidate>[];
}

/// Controllable [TaskNotifier] double capturing sync, conflict resolution, and recovery invocations.
class _SpyTaskNotifier extends TaskNotifier {
  _SpyTaskNotifier({
    this.board,
    this.onBuild,
    this.onSyncFromRemote,
    this.onResolveDeletionConflicts,
    this.onResolveRecovery,
  });

  final TaskBoard? board;
  final Future<TaskBoard> Function()? onBuild;
  final Future<void> Function()? onSyncFromRemote;
  final Future<TaskBoard> Function({
    required Map<String, TdfDeletionResolution> taskResolutions,
    required Map<String, TdfDeletionResolution> labelResolutions,
    required Map<String, TdfDeletionResolution> locationResolutions,
  })?
  onResolveDeletionConflicts;
  final Future<TaskBoard> Function({
    required Map<String, TdfRecoveryResolution> taskResolutions,
    required Map<String, TdfRecoveryResolution> labelResolutions,
    required Map<String, TdfRecoveryResolution> locationResolutions,
  })?
  onResolveRecovery;

  int buildCalls = 0;
  int syncCalls = 0;
  int deletionResolveCalls = 0;
  int recoveryResolveCalls = 0;
  Map<String, TdfDeletionResolution>? lastTaskDeletionResolutions;
  Map<String, TdfDeletionResolution>? lastLabelDeletionResolutions;
  Map<String, TdfDeletionResolution>? lastLocationDeletionResolutions;
  Map<String, TdfRecoveryResolution>? lastTaskRecoveryResolutions;
  Map<String, TdfRecoveryResolution>? lastLabelRecoveryResolutions;
  Map<String, TdfRecoveryResolution>? lastLocationRecoveryResolutions;

  @override
  Future<TaskBoard> build() async {
    buildCalls++;
    final buildHook = onBuild;
    if (buildHook != null) {
      return buildHook();
    }
    return board ?? TaskBoard.empty();
  }

  @override
  Future<TaskBoard> resolveDeletionConflicts({
    Map<String, TdfDeletionResolution> taskResolutions = const {},
    Map<String, TdfDeletionResolution> labelResolutions = const {},
    Map<String, TdfDeletionResolution> locationResolutions = const {},
    Map<String, TdfBoundDeletionDecision> boundTaskDecisions = const {},
    Map<String, TdfBoundDeletionDecision> boundLabelDecisions = const {},
    Map<String, TdfBoundDeletionDecision> boundLocationDecisions = const {},
  }) async {
    deletionResolveCalls++;
    lastTaskDeletionResolutions = Map<String, TdfDeletionResolution>.of(
      taskResolutions,
    );
    lastLabelDeletionResolutions = Map<String, TdfDeletionResolution>.of(
      labelResolutions,
    );
    lastLocationDeletionResolutions = Map<String, TdfDeletionResolution>.of(
      locationResolutions,
    );
    final callback = onResolveDeletionConflicts;
    if (callback != null) {
      return callback(
        taskResolutions: taskResolutions,
        labelResolutions: labelResolutions,
        locationResolutions: locationResolutions,
      );
    }
    final resolved = board ?? TaskBoard.empty();
    state = AsyncData(resolved);
    return resolved;
  }

  @override
  Future<TaskBoard> resolveRecovery({
    Map<String, TdfRecoveryResolution> taskResolutions = const {},
    Map<String, TdfRecoveryResolution> labelResolutions = const {},
    Map<String, TdfRecoveryResolution> locationResolutions = const {},
  }) async {
    recoveryResolveCalls++;
    lastTaskRecoveryResolutions = Map<String, TdfRecoveryResolution>.of(
      taskResolutions,
    );
    lastLabelRecoveryResolutions = Map<String, TdfRecoveryResolution>.of(
      labelResolutions,
    );
    lastLocationRecoveryResolutions = Map<String, TdfRecoveryResolution>.of(
      locationResolutions,
    );
    final callback = onResolveRecovery;
    if (callback != null) {
      return callback(
        taskResolutions: taskResolutions,
        labelResolutions: labelResolutions,
        locationResolutions: locationResolutions,
      );
    }
    final resolved = board ?? TaskBoard.empty();
    state = AsyncData(resolved);
    return resolved;
  }

  @override
  Future<void> syncFromRemote() async {
    syncCalls++;
    final callback = onSyncFromRemote;
    if (callback != null) {
      await callback();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixedNow = DateTime.utc(2026, 11, 21, 12, 0);

  TaskBoard createSampleBoard() {
    return TaskBoard.evaluate(
      tasks: <TaskItem>[
        TaskItem(
          id: 'task000001',
          title: 'Write Sync Tests',
          createdAt: fixedNow,
          modifiedAt: fixedNow,
        ),
        TaskItem(
          id: 'task000002',
          title: 'Review Merge Rules',
          createdAt: fixedNow,
          modifiedAt: fixedNow,
        ),
      ],
      labels: <TdfLabel>[
        TdfLabel(
          id: 'labl000001',
          name: 'Work',
          color: '#2196F3',
          modifiedAt: fixedNow,
        ),
      ],
      locations: <TdfLocation>[
        TdfLocation(
          id: 'loca000001',
          name: 'Zurich Office',
          latitude: 47.3769,
          longitude: 8.5417,
          radius: 150.0,
          modifiedAt: fixedNow,
        ),
      ],
      evaluationTime: fixedNow,
    );
  }

  ProviderContainer createContainer({
    WebDavConfig config = const WebDavConfig(language: AppLanguage.english),
    Locale? localeOverride,
    bool? locationEnabledOverride,
    _FakeLocationNotifier? locationNotifier,
    LocationRepository? locationRepository,
    _SpyTaskNotifier? taskNotifier,
    InMemorySettingsRepository? settingsRepository,
  }) {
    final effectiveSettings =
        settingsRepository ?? InMemorySettingsRepository(config);
    return ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(effectiveSettings),
        localFileRepositoryProvider.overrideWith(
          (ref) => FakeLocalFileRepository(
            config: config,
            initialTdf: 'tdf 0.8.0\n',
          ),
        ),
        clockProvider.overrideWithValue(() => fixedNow),
        if (localeOverride != null)
          appLocaleProvider.overrideWithValue(localeOverride),
        if (locationEnabledOverride != null)
          locationEnabledProvider.overrideWithValue(locationEnabledOverride),
        if (locationNotifier != null)
          locationStateProvider.overrideWith(() => locationNotifier),
        if (locationRepository != null)
          locationRepositoryProvider.overrideWithValue(locationRepository),
        if (taskNotifier != null)
          taskNotifierProvider.overrideWith(() => taskNotifier),
      ],
    );
  }

  group('locationStatusViewModelProvider and refreshLocation', () {
    test('projects all LocationStatus and LocationSource variants with 6dp coordinates and place fallback', () {
      final localizationsEn = lookupAppLocalizations(const Locale('en'));
      final locationNotifier = _FakeLocationNotifier(
        initialState: const LocationState.disabled(),
      );
      final container = createContainer(
        localeOverride: const Locale('en'),
        locationEnabledOverride: false,
        locationNotifier: locationNotifier,
      );
      addTearDown(container.dispose);

      final disabledModel = container.read(locationStatusViewModelProvider);
      expect(disabledModel.isEnabled, isFalse);
      expect(
        disabledModel.statusKind,
        equals(ShellLocationStatusKind.disabled),
      );
      expect(
        disabledModel.statusLabel,
        equals(localizationsEn.locationStatusUnavailable),
      );
      expect(disabledModel.placeLabel, isEmpty);
      expect(disabledModel.coordinatesText, isEmpty);
      expect(disabledModel.sourceLabel, isEmpty);
      expect(disabledModel.isRefreshing, isFalse);

      final enabledContainer = createContainer(
        localeOverride: const Locale('en'),
        locationEnabledOverride: true,
        locationNotifier: _FakeLocationNotifier(
          initialState: const LocationState.searching(),
        ),
      );
      addTearDown(enabledContainer.dispose);

      final searchingEmpty = enabledContainer.read(
        locationStatusViewModelProvider,
      );
      expect(searchingEmpty.isEnabled, isTrue);
      expect(
        searchingEmpty.statusKind,
        equals(ShellLocationStatusKind.searching),
      );
      expect(
        searchingEmpty.statusLabel,
        equals(localizationsEn.locationStatusSearching),
      );
      expect(searchingEmpty.placeLabel, isEmpty);
      expect(searchingEmpty.coordinatesText, isEmpty);
      expect(searchingEmpty.sourceLabel, isEmpty);
      expect(searchingEmpty.isRefreshing, isTrue);

      final enabledNotifier = enabledContainer.read(
        locationStateProvider.notifier,
      ) as _FakeLocationNotifier;

      enabledNotifier.setLocationState(
        LocationState.unavailable(updatedAt: fixedNow),
      );
      final unavailableModel = enabledContainer.read(
        locationStatusViewModelProvider,
      );
      expect(
        unavailableModel.statusKind,
        equals(ShellLocationStatusKind.unavailable),
      );
      expect(
        unavailableModel.statusLabel,
        equals(localizationsEn.locationStatusUnavailable),
      );
      expect(unavailableModel.placeLabel, isEmpty);
      expect(unavailableModel.coordinatesText, isEmpty);
      expect(unavailableModel.sourceLabel, isEmpty);
      expect(unavailableModel.isRefreshing, isFalse);

      final sourceCases = <(LocationSource?, String)>[
        (LocationSource.gps, localizationsEn.locationSourceGps),
        (LocationSource.system, localizationsEn.locationSourceSystem),
        (LocationSource.internet, localizationsEn.locationSourceInternet),
        (null, ''),
      ];
      for (final (source, expectedSourceLabel) in sourceCases) {
        enabledNotifier.setLocationState(
          LocationState.found(
            fix: LocationFix(
              latitude: 47.3769,
              longitude: 8.5417,
              placeName: 'Zurich',
              source: source,
            ),
            updatedAt: fixedNow,
          ),
        );
        final foundModel = enabledContainer.read(
          locationStatusViewModelProvider,
        );
        expect(
          foundModel.statusKind,
          equals(ShellLocationStatusKind.found),
          reason: 'Expected found status for source ${source?.name}',
        );
        expect(
          foundModel.statusLabel,
          equals(localizationsEn.locationStatusFound),
          reason: 'Expected found status label for source ${source?.name}',
        );
        expect(
          foundModel.placeLabel,
          equals('Zurich'),
          reason: 'Expected resolved place name for source ${source?.name}',
        );
        expect(
          foundModel.coordinatesText,
          equals('47.376900, 8.541700'),
          reason: 'Expected 6dp coordinates for source ${source?.name}',
        );
        expect(
          foundModel.sourceLabel,
          equals(expectedSourceLabel),
          reason: 'Expected localized source label for ${source?.name}',
        );
        expect(
          foundModel.isRefreshing,
          isFalse,
          reason: 'Found fix must not report isRefreshing',
        );
      }

      // Unknown place fallback when placeName is null or whitespace-only, plus negative and -0.0 coordinates.
      enabledNotifier.setLocationState(
        LocationState.found(
          fix: const LocationFix(
            latitude: -33.86882,
            longitude: 151.20929,
            placeName: '   ',
            source: LocationSource.gps,
          ),
          updatedAt: fixedNow,
        ),
      );
      final fallbackModel = enabledContainer.read(
        locationStatusViewModelProvider,
      );
      expect(
        fallbackModel.placeLabel,
        equals(localizationsEn.locationPlaceUnknown),
      );
      expect(fallbackModel.coordinatesText, equals('-33.868820, 151.209290'));

      enabledNotifier.setLocationState(
        LocationState.found(
          fix: const LocationFix(
            latitude: -0.0,
            longitude: -0.0,
            placeName: 'Null Island',
            source: LocationSource.gps,
          ),
          updatedAt: fixedNow,
        ),
      );
      expect(
        enabledContainer.read(locationStatusViewModelProvider).coordinatesText,
        equals('0.000000, 0.000000'),
      );

      enabledNotifier.setLocationState(
        LocationState.found(
          fix: const LocationFix(placeName: 'City Only'),
          updatedAt: fixedNow,
        ),
      );
      expect(
        enabledContainer.read(locationStatusViewModelProvider).coordinatesText,
        isEmpty,
      );

      // Preserved fix while actively refreshing keeps prior coordinates and marks isRefreshing true.
      enabledNotifier.setLocationState(
        LocationState.searching(
          fix: const LocationFix(
            latitude: 47.3769,
            longitude: 8.5417,
            source: LocationSource.system,
          ),
          updatedAt: fixedNow,
        ),
      );
      final refreshingWithFix = enabledContainer.read(
        locationStatusViewModelProvider,
      );
      expect(refreshingWithFix.isRefreshing, isTrue);
      expect(
        refreshingWithFix.placeLabel,
        equals(localizationsEn.locationPlaceUnknown),
      );
      expect(refreshingWithFix.coordinatesText, equals('47.376900, 8.541700'));
      expect(
        refreshingWithFix.sourceLabel,
        equals(localizationsEn.locationSourceSystem),
      );
    });

    test('refreshLocation delegates to LocationNotifier and surfaces mid-flight searching state', () async {
      final lookupCompleter = Completer<LocationFix?>();
      final repository = _FakeLocationRepository(
        onDetermineLocation: ({required forceRefresh}) {
          if (!forceRefresh) {
            return Future<LocationFix?>.value(
              const LocationFix(
                latitude: 47.0,
                longitude: 8.0,
                placeName: 'Initial City',
                source: LocationSource.internet,
              ),
            );
          }
          return lookupCompleter.future;
        },
      );
      final container = createContainer(
        config: const WebDavConfig(
          language: AppLanguage.english,
          locationEnabled: true,
        ),
        localeOverride: const Locale('en'),
        locationRepository: repository,
      );
      addTearDown(container.dispose);

      // Wait for initial build lookup to settle.
      await container.read(webDavConfigProvider.future);
      container.read(locationStatusViewModelProvider);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(locationStatusViewModelProvider).placeLabel,
        equals('Initial City'),
      );

      final refreshFuture = container
          .read(syncControllerProvider.notifier)
          .refreshLocation();

      expect(
        container.read(locationStatusViewModelProvider).isRefreshing,
        isTrue,
        reason: 'Mid-flight refresh must project isRefreshing = true',
      );
      expect(repository.lastForceRefresh, isTrue);

      lookupCompleter.complete(
        const LocationFix(
          latitude: 52.52,
          longitude: 13.405,
          placeName: 'Berlin',
          source: LocationSource.gps,
        ),
      );
      final result = await refreshFuture;
      expect(result, equals(const ActionSucceeded()));

      final updated = container.read(locationStatusViewModelProvider);
      expect(updated.isRefreshing, isFalse);
      expect(updated.statusKind, equals(ShellLocationStatusKind.found));
      expect(updated.placeLabel, equals('Berlin'));
      expect(updated.coordinatesText, equals('52.520000, 13.405000'));
      expect(updated.sourceLabel, equals('GPS'));
    });

    test('refreshLocation returns ActionPersistFailed when location refresh throws', () async {
      final notifier = _FakeLocationNotifier(
        initialState: const LocationState.unavailable(),
        onRefresh: (_) async {
          throw const LocalFileException('Location daemon unavailable');
        },
      );
      final container = createContainer(
        localeOverride: const Locale('en'),
        locationEnabledOverride: true,
        locationNotifier: notifier,
      );
      addTearDown(container.dispose);

      final result = await container
          .read(syncControllerProvider.notifier)
          .refreshLocation();
      expect(result, isA<ActionPersistFailed>());
      expect(
        (result as ActionPersistFailed).message,
        contains('Location daemon unavailable'),
      );
    });
  });

  group('conflictResolutionViewModelProvider', () {
    test('returns empty inactive projection when syncOutcome is null or another TdfSyncOutcomeKind', () async {
      final localizationsEn = lookupAppLocalizations(const Locale('en'));
      final container = createContainer(
        localeOverride: const Locale('en'),
        taskNotifier: _SpyTaskNotifier(board: createSampleBoard()),
      );
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      final idleModel = container.read(conflictResolutionViewModelProvider);
      expect(idleModel.hasConflicts, isFalse);
      expect(idleModel.entries, isEmpty);
      expect(idleModel.title, equals(localizationsEn.conflictResolutionTitle));
      expect(
        idleModel.subtitle,
        equals(localizationsEn.conflictResolutionSubtitle),
      );

      final nonMatchingKinds = <TdfSyncOutcomeKind>[
        TdfSyncOutcomeKind.recoveryRequired,
        TdfSyncOutcomeKind.syncGenerationRollback,
      ];
      for (final kind in nonMatchingKinds) {
        container
            .read(syncStateProvider.notifier)
            .setConflict(
              'Conflict active',
              outcome: TdfSyncOutcomeException(
                kind: kind,
                message: 'Not a deletion conflict',
                ambiguousTaskIds: const <String>['task000001'],
              ),
            );
        final model = container.read(conflictResolutionViewModelProvider);
        expect(
          model.hasConflicts,
          isFalse,
          reason: 'Conflict ViewModel must stay inactive for ${kind.name}',
        );
        expect(model.entries, isEmpty);
      }
    });

    test('projects conflicted tasks, labels, and locations with board title resolution and ID fallback', () async {
      final localizationsDe = lookupAppLocalizations(const Locale('de'));
      final container = createContainer(
        localeOverride: const Locale('de'),
        taskNotifier: _SpyTaskNotifier(board: createSampleBoard()),
      );
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      container
          .read(syncStateProvider.notifier)
          .setConflict(
            localizationsDe.syncConflictDeletionBanner,
            outcome: const TdfSyncOutcomeException(
              kind: TdfSyncOutcomeKind.deletionConflict,
              message: 'Deletion conflict detected',
              conflictedTaskIds: <String>['task000001', 'missingT01'],
              conflictedLabelIds: <String>['labl000001', 'missingL01'],
              conflictedLocationIds: <String>['loca000001', 'missingG01'],
            ),
          );

      final model = container.read(conflictResolutionViewModelProvider);
      expect(model.hasConflicts, isTrue);
      expect(model.title, equals(localizationsDe.conflictResolutionTitle));
      expect(
        model.subtitle,
        equals(localizationsDe.conflictResolutionSubtitle),
      );
      expect(model.entries, hasLength(6));

      expect(
        model.entries[0],
        equals(
          ResolutionEntryViewModel(
            kind: EntityKind.task,
            kindBadgeLabel: localizationsDe.entityKindTaskBadge,
            id: 'task000001',
            title: 'Write Sync Tests',
            detail: localizationsDe.syncConflictDeletionBanner,
          ),
        ),
      );
      expect(model.entries[1].id, equals('missingT01'));
      expect(model.entries[1].title, equals('missingT01'));

      expect(
        model.entries[2],
        equals(
          ResolutionEntryViewModel(
            kind: EntityKind.label,
            kindBadgeLabel: localizationsDe.entityKindLabelBadge,
            id: 'labl000001',
            title: 'Work',
            detail: localizationsDe.syncConflictDeletionBanner,
          ),
        ),
      );
      expect(model.entries[3].id, equals('missingL01'));
      expect(model.entries[3].title, equals('missingL01'));

      expect(
        model.entries[4],
        equals(
          ResolutionEntryViewModel(
            kind: EntityKind.location,
            kindBadgeLabel: localizationsDe.entityKindLocationBadge,
            id: 'loca000001',
            title: 'Zurich Office',
            detail: localizationsDe.syncConflictDeletionBanner,
          ),
        ),
      );
      expect(model.entries[5].id, equals('missingG01'));
      expect(model.entries[5].title, equals('missingG01'));

      expect(
        () => model.entries.add(model.entries.first),
        throwsUnsupportedError,
      );
    });
  });

  group('recoveryResolutionViewModelProvider', () {
    test('projects ambiguous tasks, labels, and locations and stays inactive for other outcome kinds', () async {
      final localizationsEn = lookupAppLocalizations(const Locale('en'));
      final container = createContainer(
        localeOverride: const Locale('en'),
        taskNotifier: _SpyTaskNotifier(board: createSampleBoard()),
      );
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      expect(
        container.read(recoveryResolutionViewModelProvider).hasItems,
        isFalse,
      );

      container
          .read(syncStateProvider.notifier)
          .setConflict(
            localizationsEn.syncConflictDeletionBanner,
            outcome: const TdfSyncOutcomeException(
              kind: TdfSyncOutcomeKind.deletionConflict,
              message: 'Deletion conflict',
              conflictedTaskIds: <String>['task000001'],
            ),
          );
      expect(
        container.read(recoveryResolutionViewModelProvider).hasItems,
        isFalse,
      );

      container
          .read(syncStateProvider.notifier)
          .setConflict(
            localizationsEn.syncConflictRecoveryBanner,
            outcome: const TdfSyncOutcomeException(
              kind: TdfSyncOutcomeKind.recoveryRequired,
              message: 'Generation advanced',
              ambiguousTaskIds: <String>['task000002', 'orphanT001'],
              ambiguousLabelIds: <String>['labl000001', 'orphanL001'],
              ambiguousLocationIds: <String>['loca000001', 'orphanG001'],
            ),
          );

      final model = container.read(recoveryResolutionViewModelProvider);
      expect(model.hasItems, isTrue);
      expect(model.title, equals(localizationsEn.recoveryResolutionTitle));
      expect(
        model.subtitle,
        equals(localizationsEn.recoveryResolutionSubtitle),
      );
      expect(model.entries, hasLength(6));

      expect(model.entries[0].kind, equals(EntityKind.task));
      expect(
        model.entries[0].kindBadgeLabel,
        equals(localizationsEn.entityKindTaskBadge),
      );
      expect(model.entries[0].title, equals('Review Merge Rules'));
      expect(model.entries[1].title, equals('orphanT001'));

      expect(model.entries[2].kind, equals(EntityKind.label));
      expect(model.entries[2].title, equals('Work'));
      expect(model.entries[3].title, equals('orphanL001'));

      expect(model.entries[4].kind, equals(EntityKind.location));
      expect(model.entries[4].title, equals('Zurich Office'));
      expect(model.entries[5].title, equals('orphanG001'));
      expect(
        model.entries[5].detail,
        equals(localizationsEn.syncConflictRecoveryBanner),
      );
    });
  });

  group('SyncController.syncNow', () {
    test(
      'triggers syncFromRemote with isBusy guard and rejects concurrent calls',
      () async {
        final syncCompleter = Completer<void>();
        final spyNotifier = _SpyTaskNotifier(
          board: createSampleBoard(),
          onSyncFromRemote: () => syncCompleter.future,
        );
        final container = createContainer(
          localeOverride: const Locale('en'),
          taskNotifier: spyNotifier,
        );
        addTearDown(container.dispose);
        await container.read(taskNotifierProvider.future);

        final controller = container.read(syncControllerProvider.notifier);
        final firstCall = controller.syncNow();
        expect(container.read(syncControllerProvider).isBusy, isTrue);

        final duplicateCall = await controller.syncNow();
        expect(duplicateCall, isA<ActionPersistFailed>());
        expect(spyNotifier.syncCalls, equals(1));

        syncCompleter.complete();
        final firstResult = await firstCall;
        expect(firstResult, equals(const ActionSucceeded()));
        expect(container.read(syncControllerProvider).isBusy, isFalse);
      },
    );

    test('surfaces sync error recorded on syncStateProvider when syncFromRemote catches internally', () async {
      late ProviderContainer container;
      final spyNotifier = _SpyTaskNotifier(
        board: createSampleBoard(),
        onSyncFromRemote: () async {
          container
              .read(syncStateProvider.notifier)
              .setError('Authentication failed (HTTP 401)');
        },
      );
      container = createContainer(
        localeOverride: const Locale('en'),
        taskNotifier: spyNotifier,
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(taskNotifierProvider.future);

      final result = await container
          .read(syncControllerProvider.notifier)
          .syncNow();
      expect(result, isA<ActionPersistFailed>());
      expect(
        (result as ActionPersistFailed).message,
        contains('Authentication failed'),
      );
      expect(container.read(syncControllerProvider).isBusy, isFalse);
    });

    test('invalidates taskNotifierProvider and retries initial load when full-screen file read error is active', () async {
      var shouldFailLoad = true;
      final sampleBoard = createSampleBoard();
      const failureReport = StorageFileReadReport(
        local: StorageFileReadStatus.unreadable(
          StorageFileTarget.local,
          detail: 'Malformed header',
          line: 1,
        ),
      );
      final spyNotifier = _SpyTaskNotifier(
        onBuild: () async {
          if (shouldFailLoad) {
            throw const StorageFileReadException(
              'The local file could not be read.',
              report: failureReport,
            );
          }
          return sampleBoard;
        },
      );
      final container = createContainer(
        localeOverride: const Locale('en'),
        taskNotifier: spyNotifier,
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(taskNotifierProvider.future),
        throwsA(isA<StorageFileReadException>()),
      );
      expect(container.read(taskNotifierProvider).hasError, isTrue);
      expect(container.read(taskNotifierProvider).hasValue, isFalse);

      // Retry while still broken returns formatted ActionPersistFailed.
      final failedRetry = await container
          .read(syncControllerProvider.notifier)
          .syncNow();
      expect(failedRetry, isA<ActionPersistFailed>());
      expect(
        (failedRetry as ActionPersistFailed).message,
        contains('Malformed header'),
      );
      expect(spyNotifier.syncCalls, equals(0));
      expect(spyNotifier.buildCalls, equals(2));

      // Fix file and retry: invalidates taskNotifierProvider and loads board cleanly.
      shouldFailLoad = false;
      final recoveredRetry = await container
          .read(syncControllerProvider.notifier)
          .syncNow();
      expect(recoveredRetry, equals(const ActionSucceeded()));
      expect(spyNotifier.buildCalls, equals(3));
      expect(container.read(taskNotifierProvider).asData?.value, sampleBoard);
      expect(container.read(syncControllerProvider).isBusy, isFalse);
    });

    test('invalidates activeWorkspaceProvider when activeWorkspaceProvider has an error on syncNow retry', () async {
      var loadAttempts = 0;
      var shouldFailWorkspace = true;
      final settingsRepo = _FailingSettingsRepository(
        onLoad: () async {
          loadAttempts++;
          if (shouldFailWorkspace) {
            throw const WorkspaceException(
              WorkspaceErrorKind.unsupportedSettingsSchemaVersion,
              'Settings schemaVersion 2 is newer than supported version 1.',
            );
          }
        },
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepo),
          localFileRepositoryProvider.overrideWithValue(
            FakeLocalFileRepository(
              config: const WebDavConfig(language: AppLanguage.english),
              initialTdf: 'tdf 0.8.0\n',
            ),
          ),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 10, 12)),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(activeWorkspaceProvider.future),
        throwsA(isA<WorkspaceException>()),
      );
      await expectLater(
        container.read(taskNotifierProvider.future),
        throwsA(anything),
      );
      expect(loadAttempts, equals(1));
      expect(container.read(activeWorkspaceProvider).hasError, isTrue);

      shouldFailWorkspace = false;
      final retryResult = await container
          .read(syncControllerProvider.notifier)
          .syncNow(locale: const Locale('en'));
      expect(
        retryResult,
        equals(const ActionSucceeded()),
        reason: 'Retry must invalidate activeWorkspaceProvider and reload workspace cleanly',
      );
      expect(loadAttempts, greaterThanOrEqualTo(2));
      expect(container.read(activeWorkspaceProvider).hasValue, isTrue);
      expect(container.read(taskNotifierProvider).hasValue, isTrue);
      expect(container.read(syncControllerProvider).isBusy, isFalse);
    });
  });

  group('SyncController conflict and recovery resolutions', () {
    test('applyDeletionConflictResolutions maps decisions, guards isBusy, navigates to tasks, and shows localized toast', () async {
      final completer = Completer<TaskBoard>();
      final sampleBoard = createSampleBoard();
      final spyNotifier = _SpyTaskNotifier(
        board: sampleBoard,
        onResolveDeletionConflicts: ({
          required taskResolutions,
          required labelResolutions,
          required locationResolutions,
        }) => completer.future,
      );
      final container = createContainer(
        localeOverride: const Locale('en'),
        taskNotifier: spyNotifier,
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(taskNotifierProvider.future);

      container
          .read(appShellControllerProvider.notifier)
          .openView(ShellView.conflict);
      expect(
        container.read(appShellControllerProvider).view,
        equals(ShellView.conflict),
      );

      final controller = container.read(syncControllerProvider.notifier);
      final future = controller.applyDeletionConflictResolutions(
        taskDecisions: const <String, ConflictDecisionChoice>{
          'task000001': ConflictDecisionChoice.keepEdit,
          'task000002': ConflictDecisionChoice.confirmDelete,
        },
        labelDecisions: const <String, ConflictDecisionChoice>{
          'labl000001': ConflictDecisionChoice.confirmDelete,
        },
        locationDecisions: const <String, ConflictDecisionChoice>{
          'loca000001': ConflictDecisionChoice.keepEdit,
        },
        locale: const Locale('de'),
      );

      expect(container.read(syncControllerProvider).isBusy, isTrue);

      // Concurrent submission while busy is rejected cleanly.
      final duplicate = await controller.applyDeletionConflictResolutions(
        taskDecisions: const <String, ConflictDecisionChoice>{},
        labelDecisions: const <String, ConflictDecisionChoice>{},
        locationDecisions: const <String, ConflictDecisionChoice>{},
      );
      expect(duplicate, isA<ActionPersistFailed>());
      expect(spyNotifier.deletionResolveCalls, equals(1));

      completer.complete(sampleBoard);
      final result = await future;
      final localizationsDe = lookupAppLocalizations(const Locale('de'));

      expect(
        result,
        equals(
          ActionSucceeded(
            noticeMessage: localizationsDe.conflictResolvedNotice,
          ),
        ),
      );
      expect(container.read(syncControllerProvider).isBusy, isFalse);
      expect(
        spyNotifier.lastTaskDeletionResolutions,
        equals(const <String, TdfDeletionResolution>{
          'task000001': TdfDeletionResolution.undelete,
          'task000002': TdfDeletionResolution.delete,
        }),
      );
      expect(
        spyNotifier.lastLabelDeletionResolutions,
        equals(const <String, TdfDeletionResolution>{
          'labl000001': TdfDeletionResolution.delete,
        }),
      );
      expect(
        spyNotifier.lastLocationDeletionResolutions,
        equals(const <String, TdfDeletionResolution>{
          'loca000001': TdfDeletionResolution.undelete,
        }),
      );
      expect(
        container.read(appShellControllerProvider).view,
        equals(ShellView.tasks),
      );
      final notice = container.read(floatingNoticeControllerProvider);
      expect(notice, isNotNull);
      expect(notice?.message, equals(localizationsDe.conflictResolvedNotice));
      expect(notice?.tone, equals(NoticeTone.success));
    });

    test('applyDeletionConflictResolutions keeps conflict view open and emits ActionPersistFailed on error', () async {
      final spyNotifier = _SpyTaskNotifier(
        board: createSampleBoard(),
        onResolveDeletionConflicts:
            ({
              required taskResolutions,
              required labelResolutions,
              required locationResolutions,
            }) async {
              throw const WebDavException('Server busy', statusCode: 503);
            },
      );
      final container = createContainer(
        localeOverride: const Locale('en'),
        taskNotifier: spyNotifier,
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(taskNotifierProvider.future);

      container
          .read(appShellControllerProvider.notifier)
          .openView(ShellView.conflict);

      final result = await container
          .read(syncControllerProvider.notifier)
          .applyDeletionConflictResolutions(
            taskDecisions: const <String, ConflictDecisionChoice>{
              'task000001': ConflictDecisionChoice.keepEdit,
            },
            labelDecisions: const <String, ConflictDecisionChoice>{},
            locationDecisions: const <String, ConflictDecisionChoice>{},
          );

      expect(result, isA<ActionPersistFailed>());
      expect((result as ActionPersistFailed).message, contains('Server busy'));
      expect(container.read(syncControllerProvider).isBusy, isFalse);
      expect(
        container.read(appShellControllerProvider).view,
        equals(ShellView.conflict),
      );
      expect(container.read(floatingNoticeControllerProvider), isNull);
    });

    test('applyRecoveryResolutions maps decisions, guards isBusy, navigates to tasks, and shows recoveryResolvedNotice', () async {
      final completer = Completer<TaskBoard>();
      final sampleBoard = createSampleBoard();
      final spyNotifier = _SpyTaskNotifier(
        board: sampleBoard,
        onResolveRecovery: ({
          required taskResolutions,
          required labelResolutions,
          required locationResolutions,
        }) => completer.future,
      );
      final container = createContainer(
        localeOverride: const Locale('en'),
        taskNotifier: spyNotifier,
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(taskNotifierProvider.future);

      container
          .read(appShellControllerProvider.notifier)
          .openView(ShellView.recovery);

      final controller = container.read(syncControllerProvider.notifier);
      final future = controller.applyRecoveryResolutions(
        taskDecisions: const <String, RecoveryDecisionChoice>{
          'task000001': RecoveryDecisionChoice.recoverAsNew,
          'task000002': RecoveryDecisionChoice.discardLocal,
        },
        labelDecisions: const <String, RecoveryDecisionChoice>{
          'labl000001': RecoveryDecisionChoice.recoverAsNew,
        },
        locationDecisions: const <String, RecoveryDecisionChoice>{
          'loca000001': RecoveryDecisionChoice.discardLocal,
        },
      );

      expect(container.read(syncControllerProvider).isBusy, isTrue);

      final duplicate = await controller.applyRecoveryResolutions(
        taskDecisions: const <String, RecoveryDecisionChoice>{},
        labelDecisions: const <String, RecoveryDecisionChoice>{},
        locationDecisions: const <String, RecoveryDecisionChoice>{},
      );
      expect(duplicate, isA<ActionPersistFailed>());
      expect(spyNotifier.recoveryResolveCalls, equals(1));

      completer.complete(sampleBoard);
      final result = await future;
      final localizationsEn = lookupAppLocalizations(const Locale('en'));

      expect(
        result,
        equals(
          ActionSucceeded(
            noticeMessage: localizationsEn.recoveryResolvedNotice,
          ),
        ),
      );
      expect(container.read(syncControllerProvider).isBusy, isFalse);
      expect(
        spyNotifier.lastTaskRecoveryResolutions,
        equals(const <String, TdfRecoveryResolution>{
          'task000001': TdfRecoveryResolution.recoverAsNew,
          'task000002': TdfRecoveryResolution.discard,
        }),
      );
      expect(
        spyNotifier.lastLabelRecoveryResolutions,
        equals(const <String, TdfRecoveryResolution>{
          'labl000001': TdfRecoveryResolution.recoverAsNew,
        }),
      );
      expect(
        spyNotifier.lastLocationRecoveryResolutions,
        equals(const <String, TdfRecoveryResolution>{
          'loca000001': TdfRecoveryResolution.discard,
        }),
      );
      expect(
        container.read(appShellControllerProvider).view,
        equals(ShellView.tasks),
      );
      final notice = container.read(floatingNoticeControllerProvider);
      expect(notice, isNotNull);
      expect(notice?.message, equals(localizationsEn.recoveryResolvedNotice));
      expect(notice?.tone, equals(NoticeTone.success));
    });

    test('applyRecoveryResolutions keeps recovery view open on TdfSyncOutcomeException failure', () async {
      final localizationsEn = lookupAppLocalizations(const Locale('en'));
      final spyNotifier = _SpyTaskNotifier(
        board: createSampleBoard(),
        onResolveRecovery:
            ({
              required taskResolutions,
              required labelResolutions,
              required locationResolutions,
            }) async {
              throw const TdfSyncOutcomeException(
                kind: TdfSyncOutcomeKind.deletionConflict,
                message: 'Secondary conflict encountered',
                conflictedTaskIds: <String>['task000001'],
              );
            },
      );
      final container = createContainer(
        localeOverride: const Locale('en'),
        taskNotifier: spyNotifier,
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(taskNotifierProvider.future);

      container
          .read(appShellControllerProvider.notifier)
          .openView(ShellView.recovery);

      final result = await container
          .read(syncControllerProvider.notifier)
          .applyRecoveryResolutions(
            taskDecisions: const <String, RecoveryDecisionChoice>{
              'task000001': RecoveryDecisionChoice.recoverAsNew,
            },
            labelDecisions: const <String, RecoveryDecisionChoice>{},
            locationDecisions: const <String, RecoveryDecisionChoice>{},
          );

      expect(result, isA<ActionPersistFailed>());
      expect(
        (result as ActionPersistFailed).message,
        equals(localizationsEn.syncConflictDeletionBanner),
      );
      expect(container.read(syncControllerProvider).isBusy, isFalse);
      expect(
        container.read(appShellControllerProvider).view,
        equals(ShellView.recovery),
      );
      expect(container.read(floatingNoticeControllerProvider), isNull);
    });

    test('ignores stale completion side effects when active workspace switches mid-flight', () async {
      final completer = Completer<TaskBoard>();
      final settingsRepository = InMemorySettingsRepository(
        const WebDavConfig(language: AppLanguage.english),
      );
      final sampleBoard = createSampleBoard();
      final spyNotifier = _SpyTaskNotifier(
        board: sampleBoard,
        onResolveDeletionConflicts: ({
          required taskResolutions,
          required labelResolutions,
          required locationResolutions,
        }) => completer.future,
      );
      final container = createContainer(
        localeOverride: const Locale('en'),
        settingsRepository: settingsRepository,
        taskNotifier: spyNotifier,
      );
      addTearDown(container.dispose);

      await container.read(activeWorkspaceProvider.future);
      await container.read(taskNotifierProvider.future);
      final secondWorkspace = await container
          .read(activeWorkspaceProvider.notifier)
          .createWorkspace('Second');

      container
          .read(appShellControllerProvider.notifier)
          .openView(ShellView.conflict);

      final resolutionFuture = container
          .read(syncControllerProvider.notifier)
          .applyDeletionConflictResolutions(
            taskDecisions: const <String, ConflictDecisionChoice>{
              'task000001': ConflictDecisionChoice.keepEdit,
            },
            labelDecisions: const <String, ConflictDecisionChoice>{},
            locationDecisions: const <String, ConflictDecisionChoice>{},
          );

      // Switch workspace while conflict resolution is suspended.
      await container
          .read(activeWorkspaceProvider.notifier)
          .switchWorkspace(secondWorkspace.id);
      container
          .read(appShellControllerProvider.notifier)
          .openView(ShellView.settings);

      completer.complete(sampleBoard);
      await resolutionFuture;

      expect(
        container.read(appShellControllerProvider).view,
        equals(ShellView.settings),
        reason: 'Stale resolution from previous workspace must not navigate active workspace',
      );
      expect(
        container.read(floatingNoticeControllerProvider),
        isNull,
        reason: 'Stale resolution from previous workspace must not show toast on new workspace',
      );
      expect(container.read(syncControllerProvider).isBusy, isFalse);
    });

    test('syncNow surfaces all TdfSyncOutcomeKind outcomes and fileReadReport with explicit locale', () async {
      final localizationsDe = lookupAppLocalizations(const Locale('de'));
      late ProviderContainer container;
      TdfSyncOutcomeException? outcomeToEmit;
      StorageFileReadReport? reportToEmit;
      final spyNotifier = _SpyTaskNotifier(
        board: createSampleBoard(),
        onSyncFromRemote: () async {
          if (outcomeToEmit case final outcome?) {
            container
                .read(syncStateProvider.notifier)
                .setConflict('Conflict', outcome: outcome);
            return;
          }
          if (reportToEmit case final report?) {
            container
                .read(syncStateProvider.notifier)
                .setError('Read failed', fileReadReport: report);
          }
        },
      );
      container = createContainer(
        localeOverride: const Locale('en'),
        taskNotifier: spyNotifier,
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(taskNotifierProvider.future);

      final outcomeCases = <(TdfSyncOutcomeKind, String)>[
        (
          TdfSyncOutcomeKind.deletionConflict,
          localizationsDe.syncConflictDeletionBanner,
        ),
        (
          TdfSyncOutcomeKind.recoveryRequired,
          localizationsDe.syncConflictRecoveryBanner,
        ),
        (
          TdfSyncOutcomeKind.syncGenerationRollback,
          localizationsDe.syncErrorGenerationRollbackBanner,
        ),
      ];
      for (final (kind, expectedBanner) in outcomeCases) {
        outcomeToEmit = TdfSyncOutcomeException(
          kind: kind,
          message: 'Outcome ${kind.name}',
        );
        reportToEmit = null;
        final result = await container
            .read(syncControllerProvider.notifier)
            .syncNow(locale: const Locale('de'));
        expect(
          result,
          equals(ActionPersistFailed(message: expectedBanner)),
          reason: 'Expected localized banner for ${kind.name}',
        );
      }

      outcomeToEmit = null;
      reportToEmit = const StorageFileReadReport(
        local: StorageFileReadStatus.unsupportedVersion(
          StorageFileTarget.local,
          version: '9.9.9',
        ),
      );
      final reportResult = await container
          .read(syncControllerProvider.notifier)
          .syncNow(locale: const Locale('de'));
      expect(reportResult, isA<ActionPersistFailed>());
      expect((reportResult as ActionPersistFailed).message, contains('9.9.9'));
    });

    test('conflict and recovery projections fall back to IDs when board failed to load and format error variants', () async {
      final localizationsEn = lookupAppLocalizations(const Locale('en'));
      Object? resolutionError;
      final spyNotifier = _SpyTaskNotifier(
        onBuild: () async {
          throw const LocalFileException('Disk error');
        },
        onResolveDeletionConflicts:
            ({
              required taskResolutions,
              required labelResolutions,
              required locationResolutions,
            }) async {
              throw resolutionError ?? StateError('Unexpected');
            },
      );
      final container = createContainer(
        localeOverride: const Locale('en'),
        taskNotifier: spyNotifier,
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await expectLater(
        container.read(taskNotifierProvider.future),
        throwsA(isA<LocalFileException>()),
      );

      container
          .read(syncStateProvider.notifier)
          .setConflict(
            'Conflict',
            outcome: const TdfSyncOutcomeException(
              kind: TdfSyncOutcomeKind.deletionConflict,
              message: 'Conflict',
              conflictedTaskIds: <String>['unloadedT1'],
              conflictedLabelIds: <String>['unloadedL1'],
              conflictedLocationIds: <String>['unloadedG1'],
            ),
          );
      final conflictModel = container.read(conflictResolutionViewModelProvider);
      expect(
        conflictModel.entries.map((entry) => entry.title).toList(),
        equals(<String>['unloadedT1', 'unloadedL1', 'unloadedG1']),
      );

      final errorCases = <(Object, String)>[
        (const LocalFileException('Local IO failed'), 'Local IO failed'),
        (
          const TdfException(
            kind: TdfErrorKind.circularDependency,
            line: 1,
            message: 'Invalid dependency',
          ),
          'Invalid dependency',
        ),
        (
          const WorkspaceException(
            WorkspaceErrorKind.settingsPersistenceFailed,
            'Save failed',
          ),
          localizationsEn.errorSettingsSaveFailed,
        ),
        (StateError('Unexpected boom'), 'Unexpected boom'),
      ];
      for (final (error, expectedSubstring) in errorCases) {
        resolutionError = error;
        final result = await container
            .read(syncControllerProvider.notifier)
            .applyDeletionConflictResolutions(
              taskDecisions: const <String, ConflictDecisionChoice>{},
              labelDecisions: const <String, ConflictDecisionChoice>{},
              locationDecisions: const <String, ConflictDecisionChoice>{},
            );
        expect(
          result,
          isA<ActionPersistFailed>(),
          reason: 'Expected persist failure for $error',
        );
        expect(
          (result as ActionPersistFailed).message,
          contains(expectedSubstring),
          reason: 'Expected formatted detail for $error',
        );
      }
    });
  });

  group('ViewModel and state equality', () {
    test('supports value equality and copyWith across immutable models', () {
      const stateA = SyncControllerState();
      final stateB = stateA.copyWith(isBusy: true);
      expect(stateA, equals(const SyncControllerState(isBusy: false)));
      expect(stateA.hashCode, equals(const SyncControllerState().hashCode));
      expect(stateB, equals(const SyncControllerState(isBusy: true)));
      expect(stateA == stateB, isFalse);

      const locationA = LocationStatusViewModel(
        isEnabled: true,
        statusKind: ShellLocationStatusKind.found,
        statusLabel: 'Location found',
        placeLabel: 'Zurich',
        coordinatesText: '47.376900, 8.541700',
        sourceLabel: 'GPS',
        isRefreshing: false,
      );
      const locationB = LocationStatusViewModel(
        isEnabled: true,
        statusKind: ShellLocationStatusKind.found,
        statusLabel: 'Location found',
        placeLabel: 'Zurich',
        coordinatesText: '47.376900, 8.541700',
        sourceLabel: 'GPS',
        isRefreshing: false,
      );
      expect(locationA, equals(locationB));
      expect(locationA.hashCode, equals(locationB.hashCode));

      const entry = ResolutionEntryViewModel(
        kind: EntityKind.task,
        kindBadgeLabel: 'TASK',
        id: 'task000001',
        title: 'Task',
        detail: 'Detail',
      );
      final conflictA = ConflictResolutionViewModel(
        hasConflicts: true,
        title: 'Title',
        subtitle: 'Subtitle',
        entries: const <ResolutionEntryViewModel>[entry],
      );
      final conflictB = ConflictResolutionViewModel(
        hasConflicts: true,
        title: 'Title',
        subtitle: 'Subtitle',
        entries: const <ResolutionEntryViewModel>[entry],
      );
      expect(conflictA, equals(conflictB));
      expect(conflictA.hashCode, equals(conflictB.hashCode));

      final recoveryA = RecoveryResolutionViewModel(
        hasItems: true,
        title: 'Title',
        subtitle: 'Subtitle',
        entries: const <ResolutionEntryViewModel>[entry],
      );
      final recoveryB = RecoveryResolutionViewModel(
        hasItems: true,
        title: 'Title',
        subtitle: 'Subtitle',
        entries: const <ResolutionEntryViewModel>[entry],
      );
      expect(recoveryA, equals(recoveryB));
      expect(recoveryA.hashCode, equals(recoveryB.hashCode));
    });

    test('ConflictDecisionsNotifier and RecoveryDecisionsNotifier initialize defaults and update immutably', () {
      final board = createSampleBoard();
      final container = createContainer(
        localeOverride: const Locale('en'),
        taskNotifier: _SpyTaskNotifier(board: board),
      );
      addTearDown(container.dispose);

      container
          .read(syncStateProvider.notifier)
          .setConflict(
            'Deletion conflict',
            outcome: const TdfSyncOutcomeException(
              kind: TdfSyncOutcomeKind.deletionConflict,
              message: 'Deletion conflict',
              conflictedTaskIds: <String>['taskA00001'],
              conflictedLabelIds: <String>['work000001'],
            ),
          );

      final initialConflict = container.read(conflictDecisionsProvider);
      expect(
        initialConflict[resolutionDecisionKey(EntityKind.task, 'taskA00001')],
        equals(ConflictDecisionChoice.keepEdit),
      );
      expect(
        initialConflict[resolutionDecisionKey(EntityKind.label, 'work000001')],
        equals(ConflictDecisionChoice.keepEdit),
      );

      container
          .read(conflictDecisionsProvider.notifier)
          .selectDecision(
            EntityKind.task,
            'taskA00001',
            ConflictDecisionChoice.confirmDelete,
          );
      expect(
        container.read(conflictDecisionsProvider)[resolutionDecisionKey(
          EntityKind.task,
          'taskA00001',
        )],
        equals(ConflictDecisionChoice.confirmDelete),
      );

      container
          .read(syncStateProvider.notifier)
          .setConflict(
            'Recovery required',
            outcome: const TdfSyncOutcomeException(
              kind: TdfSyncOutcomeKind.recoveryRequired,
              message: 'Recovery required',
              ambiguousTaskIds: <String>['taskA00001'],
              ambiguousLocationIds: <String>['home000001'],
            ),
          );

      final initialRecovery = container.read(recoveryDecisionsProvider);
      expect(
        initialRecovery[resolutionDecisionKey(EntityKind.task, 'taskA00001')],
        equals(RecoveryDecisionChoice.recoverAsNew),
      );
      container
          .read(recoveryDecisionsProvider.notifier)
          .selectDecision(
            EntityKind.location,
            'home000001',
            RecoveryDecisionChoice.discardLocal,
          );
      expect(
        container.read(recoveryDecisionsProvider)[resolutionDecisionKey(
          EntityKind.location,
          'home000001',
        )],
        equals(RecoveryDecisionChoice.discardLocal),
      );
    });
  });
}

/// [InMemorySettingsRepository] double whose [loadActiveWorkspace] runs an injectable [onLoad] hook.
class _FailingSettingsRepository extends InMemorySettingsRepository {
  _FailingSettingsRepository({required this.onLoad})
    : super(const WebDavConfig(language: AppLanguage.english));

  final Future<void> Function() onLoad;

  @override
  Future<AppWorkspace> loadActiveWorkspace() async {
    await onLoad();
    return super.loadActiveWorkspace();
  }
}
