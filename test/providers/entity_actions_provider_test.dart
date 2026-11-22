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
import 'package:tiertask/l10n/tier_localization_extension.dart';
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
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/providers/entity_actions_provider.dart';
import 'package:tiertask/providers/floating_notice_providers.dart';
import 'package:tiertask/providers/location_providers.dart';
import 'package:tiertask/providers/location_source_resolver.dart';
import 'package:tiertask/providers/shell_providers.dart';
import 'package:tiertask/providers/sync_providers.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/providers/task_schedule_helper.dart';
import 'package:tiertask/providers/workspace_providers.dart';
import 'package:tiertask/repositories/local_file_repository.dart';
import 'package:tiertask/repositories/location_repository.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/repositories/webdav_repository.dart';
import 'package:tiertask/services/app_logger.dart';
import 'package:tiertask/services/tdf_service.dart';

import '../ui/test_helpers.dart';

class _BlockingTaskNotifier extends TaskNotifier {
  _BlockingTaskNotifier(this._initialBoard);

  final TaskBoard _initialBoard;
  Completer<void>? nextMutationCompleter;
  Exception? nextError;

  @override
  Future<TaskBoard> build() async => _initialBoard;

  @override
  Future<bool> addLabel(
    String name, {
    String? color,
    String? id,
    String? note,
    bool isScoped = false,
    Iterable<TaskLink>? links,
    List<TaskCondition> conditions = const <TaskCondition>[],
    DateTime? currentDate,
  }) async {
    await _awaitGate();
    return true;
  }

  @override
  Future<bool> updateLabel(
    String labelId, {
    String? name,
    String? color,
    bool clearColor = false,
    String? note,
    bool clearNote = false,
    bool? isScoped,
    Iterable<TaskLink>? links,
    List<TaskCondition>? conditions,
    DateTime? currentDate,
  }) async {
    await _awaitGate();
    return true;
  }

  Future<void> _awaitGate() async {
    if (nextMutationCompleter case final completer?) {
      nextMutationCompleter = null;
      await completer.future;
    }
    if (nextError case final error?) {
      nextError = null;
      throw error;
    }
  }
}

class _ControllableWorkspaceNotifier extends ActiveWorkspaceNotifier {
  void emitTransientLoading() {
    state = const AsyncLoading();
  }

  void emitWorkspace(AppWorkspace workspace) {
    state = AsyncData(workspace);
  }
}

class _ControlledLocationNotifier extends LocationNotifier {
  _ControlledLocationNotifier(
    this._initialState, {
    this.refreshedFix,
    this.onRefresh,
  });

  final LocationState _initialState;
  final Future<void> Function(_ControlledLocationNotifier notifier)? onRefresh;
  final LocationFix? refreshedFix;
  int refreshCalls = 0;

  @override
  LocationState build() => _initialState;

  @override
  Future<void> refreshLocation() async {
    refreshCalls++;
    if (onRefresh case final callback?) {
      await callback(this);
      return;
    }
    if (refreshedFix case final fix?) {
      state = LocationState(
        status: LocationStatus.found,
        fix: fix,
        updatedAt: DateTime.utc(2026, 11, 21, 12),
      );
    }
  }
}

class _ControlledSettingsRepository extends InMemorySettingsRepository {
  _ControlledSettingsRepository([super.initialConfig]);

  Completer<void>? activateGate;
  int activateCallCount = 0;
  Completer<void>? createGate;
  int createCallCount = 0;
  Completer<void>? deleteGate;
  int deleteCallCount = 0;
  Exception? nextError;
  Completer<void>? renameGate;
  int renameCallCount = 0;

  @override
  Future<AppWorkspace> activateWorkspace(String workspaceId) async {
    activateCallCount++;
    if (activateGate case final gate?) {
      await gate.future;
    }
    _throwIfConfigured();
    return super.activateWorkspace(workspaceId);
  }

  @override
  Future<AppWorkspace> createWorkspace(
    String name, {
    WebDavConfig? config,
    String? id,
    bool activate = false,
  }) async {
    createCallCount++;
    if (createGate case final gate?) {
      await gate.future;
    }
    _throwIfConfigured();
    return super.createWorkspace(
      name,
      config: config,
      id: id,
      activate: activate,
    );
  }

  @override
  Future<AppWorkspace> deleteWorkspace(String workspaceId) async {
    deleteCallCount++;
    if (deleteGate case final gate?) {
      await gate.future;
    }
    _throwIfConfigured();
    return super.deleteWorkspace(workspaceId);
  }

  @override
  Future<AppWorkspace> renameWorkspace(
    String workspaceId,
    String newName,
  ) async {
    renameCallCount++;
    if (renameGate case final gate?) {
      await gate.future;
    }
    _throwIfConfigured();
    return super.renameWorkspace(workspaceId, newName);
  }

  void _throwIfConfigured() {
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
  }
}

class _DelayedLocationRepository extends FakeLocationRepository {
  Completer<List<GeocodingCandidate>>? nextSearchCompleter;
  Exception? nextSearchError;

  @override
  Future<List<GeocodingCandidate>> searchLocations(String query) {
    if (nextSearchCompleter case final completer?) {
      nextSearchCompleter = null;
      return completer.future;
    }
    if (nextSearchError case final error?) {
      nextSearchError = null;
      return Future<List<GeocodingCandidate>>.error(error);
    }
    return super.searchLocations(query);
  }
}

class _FailingLoadSettingsRepository extends InMemorySettingsRepository {
  _FailingLoadSettingsRepository({required this.onLoad})
    : super(const WebDavConfig(language: AppLanguage.english));

  final Future<void> Function() onLoad;

  @override
  Future<AppWorkspace> loadActiveWorkspace() async {
    await onLoad();
    return super.loadActiveWorkspace();
  }
}

class _FailingWriteLocalFileRepository extends FakeLocalFileRepository {
  _FailingWriteLocalFileRepository({
    required super.config,
    required super.initialTdf,
  });

  bool failNextSave = false;

  @override
  Future<void> saveTdf(String tdfContent) async {
    if (failNextSave) {
      throw const LocalFileException('Disk is read-only');
    }
    await super.saveTdf(tdfContent);
  }
}

class _HookedLocationRepository implements LocationRepository {
  _HookedLocationRepository({this.onDetermineLocation});

  final Future<LocationFix?> Function({required bool forceRefresh})?
  onDetermineLocation;
  int determineCalls = 0;
  bool lastForceRefresh = false;

  @override
  Future<LocationFix?> determineLocation({bool forceRefresh = false}) async {
    determineCalls++;
    lastForceRefresh = forceRefresh;
    if (onDetermineLocation case final callback?) {
      return callback(forceRefresh: forceRefresh);
    }
    return null;
  }

  @override
  Future<List<GeocodingCandidate>> searchLocations(String query) async =>
      const <GeocodingCandidate>[];
}

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
  final Future<void> Function()? onSyncFromRemote;

  int buildCalls = 0;
  int deletionResolveCalls = 0;
  Map<String, TdfDeletionResolution>? lastLabelDeletionResolutions;
  Map<String, TdfRecoveryResolution>? lastLabelRecoveryResolutions;
  Map<String, TdfDeletionResolution>? lastLocationDeletionResolutions;
  Map<String, TdfRecoveryResolution>? lastLocationRecoveryResolutions;
  Map<String, TdfDeletionResolution>? lastTaskDeletionResolutions;
  Map<String, TdfRecoveryResolution>? lastTaskRecoveryResolutions;
  int recoveryResolveCalls = 0;
  int syncCalls = 0;

  @override
  Future<TaskBoard> build() async {
    buildCalls++;
    if (onBuild case final buildHook?) {
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
    if (onResolveDeletionConflicts case final callback?) {
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
    if (onResolveRecovery case final callback?) {
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
    if (onSyncFromRemote case final callback?) {
      await callback();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixedNow = DateTime.utc(2026, 11, 21, 12);
  const englishLocale = Locale('en');
  const germanLocale = Locale('de');
  final englishLocalizations = lookupAppLocalizations(englishLocale);
  final germanLocalizations = lookupAppLocalizations(germanLocale);

  const baseTdf = '''tdf 0.8.0

label work000001 {
  name "Work"
  color "#2196F3"
  modified 2026-11-01 08:00:00
}

location loc0000001 {
  name "Office"
  coordinates 52.52 13.405
  radius 150
  modified 2026-11-01 08:00:00
}
''';

  setUp(() {
    AppLogger.resetForTesting(clock: () => fixedNow);
  });

  tearDown(() {
    AppLogger.resetForTesting();
  });

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

  ({
    ProviderContainer container,
    _FailingWriteLocalFileRepository localRepository,
    _DelayedLocationRepository locationRepository,
    _ControlledLocationNotifier locationNotifier,
  })
  createEntityHarness({
    String initialTdf = baseTdf,
    LocationState locationState = const LocationState.unavailable(),
    LocationFix? refreshedFix,
    WebDavConfig config = const WebDavConfig(language: AppLanguage.english),
    WebDavRepository? webDavRepository,
  }) {
    final settingsRepository = InMemorySettingsRepository(config);
    final localRepository = _FailingWriteLocalFileRepository(
      config: config,
      initialTdf: initialTdf,
    );
    final locationRepository = _DelayedLocationRepository();
    final locationNotifier = _ControlledLocationNotifier(
      locationState,
      refreshedFix: refreshedFix,
    );
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settingsRepository),
        localFileRepositoryProvider.overrideWith((ref) => localRepository),
        if (webDavRepository != null)
          webDavRepositoryProvider.overrideWith((ref) => webDavRepository),
        locationRepositoryProvider.overrideWithValue(locationRepository),
        locationStateProvider.overrideWith(() => locationNotifier),
        clockProvider.overrideWithValue(() => fixedNow),
      ],
    );
    return (
      container: container,
      localRepository: localRepository,
      locationRepository: locationRepository,
      locationNotifier: locationNotifier,
    );
  }

  ProviderContainer createSyncContainer({
    WebDavConfig config = const WebDavConfig(language: AppLanguage.english),
    Locale? localeOverride,
    bool? locationEnabledOverride,
    _ControlledLocationNotifier? locationNotifier,
    LocationRepository? locationRepository,
    _SpyTaskNotifier? taskNotifier,
    SettingsRepository? settingsRepository,
    _ControllableWorkspaceNotifier? workspaceNotifier,
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
        if (workspaceNotifier != null)
          activeWorkspaceProvider.overrideWith(() => workspaceNotifier),
      ],
    );
  }

  ProviderContainer createWorkspaceContainer({
    SettingsRepository? settingsRepository,
    WebDavConfig initialConfig = const WebDavConfig(
      language: AppLanguage.english,
    ),
  }) {
    final repository =
        settingsRepository ?? InMemorySettingsRepository(initialConfig);
    return ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
  }

  Future<void> primeWorkspaceProviders(ProviderContainer container) async {
    await container.read(activeWorkspaceProvider.future);
    await container.read(workspaceSummariesProvider.future);
  }

  group('Immutable state and draft value types', () {
    test(
      'supports value equality, hashCode, copyWith, and unmodifiable lists',
      () {
        const entityStateA = EntityActionsState();
        final entityStateB = entityStateA.copyWith(
          isBusy: true,
          isResolvingLocation: true,
        );
        expect(entityStateA, equals(const EntityActionsState()));
        expect(
          entityStateA.hashCode,
          equals(const EntityActionsState().hashCode),
        );
        expect(entityStateB.isBusy, isTrue);
        expect(entityStateB.isResolvingLocation, isTrue);
        expect(entityStateB, isNot(equals(entityStateA)));
        expect(entityStateB.copyWith(), equals(entityStateB));

        final labelDraftA = LabelDraftInput(
          name: 'Focus',
          colorHex: '#2196F3',
          isScoped: true,
          note: 'Details',
          links: const <TaskLink>[
            TaskLink(title: 'Docs', uri: 'https://example.com'),
          ],
          conditions: ConditionDraft(
            daysMode: ConditionDimensionMode.custom,
            weekdays: const <int>[1, 2],
          ),
        );
        final labelDraftB = labelDraftA.copyWith();
        expect(labelDraftA, equals(labelDraftB));
        expect(labelDraftA.hashCode, equals(labelDraftB.hashCode));
        expect(() => labelDraftA.links.clear(), throwsUnsupportedError);
        expect(labelDraftA.copyWith(name: 'Updated').name, equals('Updated'));
        expect(
          LabelDraftInput(name: 'Default').conditions,
          equals(ConditionDraft()),
        );

        const locationDraftA = LocationDraftInput(
          name: 'Home',
          sourceType: LocationSourceType.address,
          rawSource: 'Berlin',
          rawLatitude: '52.52',
          rawLongitude: '13.405',
          rawRadius: '250m',
          note: 'Entrance',
        );
        final locationDraftB = locationDraftA.copyWith();
        expect(locationDraftA, equals(locationDraftB));
        expect(locationDraftA.hashCode, equals(locationDraftB.hashCode));
        expect(
          locationDraftA.copyWith(rawRadius: '500m').rawRadius,
          equals('500m'),
        );

        const syncStateA = SyncActionsState();
        final syncStateB = syncStateA.copyWith(isBusy: true);
        expect(syncStateA, equals(const SyncActionsState()));
        expect(syncStateA.hashCode, equals(const SyncActionsState().hashCode));
        expect(syncStateB, equals(const SyncActionsState(isBusy: true)));
        expect(syncStateB.copyWith(), equals(syncStateB));
        expect(syncStateA == syncStateB, isFalse);

        const workspaceStateA = WorkspaceActionsState();
        final workspaceStateB = workspaceStateA.copyWith(isBusy: true);
        expect(workspaceStateA.isBusy, isFalse);
        expect(
          workspaceStateB,
          equals(const WorkspaceActionsState(isBusy: true)),
        );
        expect(
          workspaceStateB.hashCode,
          equals(const WorkspaceActionsState(isBusy: true).hashCode),
        );
        expect(workspaceStateB.copyWith(), equals(workspaceStateB));
        expect(workspaceStateA == workspaceStateB, isFalse);
      },
    );
  });

  group('EntityActionsNotifier Labels', () {
    test('quickCreateLabel rotates through all 8 preset colors, auto-expands & reveals, and emits labelSavedNotice', () async {
      final harness = createEntityHarness(initialTdf: 'tdf 0.8.0\n');
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);

      final actions = harness.container.read(entityActionsProvider.notifier);
      for (var i = 0; i < canonicalLabelPresetHexColors.length + 1; i++) {
        final result = await actions.quickCreateLabel('Label $i');
        expect(
          result,
          isA<ActionSucceeded>(),
          reason: 'Expected label $i quick-create to succeed',
        );
        final succeeded = result as ActionSucceeded;
        expect(succeeded.entityId, isNotNull);
        expect(
          succeeded.noticeMessage,
          equals(englishLocalizations.labelSavedNotice),
        );

        final board = harness.container.read(taskNotifierProvider).requireValue;
        final created = board.findLabel(succeeded.entityId ?? '');
        expect(created, isNotNull);
        final expectedColor =
            canonicalLabelPresetHexColors[i %
                canonicalLabelPresetHexColors.length];
        expect(
          created?.color,
          equals(expectedColor),
          reason: 'Rotating preset color mismatch at index $i',
        );

        final shellState = harness.container.read(shellProvider);
        final expectedRef = EntityRef(
          kind: EntityKind.label,
          id: succeeded.entityId ?? '',
        );
        expect(shellState.expandedEntity, equals(expectedRef));
        expect(shellState.revealEntityRequest, equals(expectedRef));

        final notice = harness.container.read(floatingNoticeProvider);
        expect(notice?.message, equals(englishLocalizations.labelSavedNotice));
      }
    });

    test('quickCreateLabel rejects empty, case-insensitive duplicates, >500 scalars, control chars, and unpaired surrogates', () async {
      final harness = createEntityHarness();
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);
      final actions = harness.container.read(entityActionsProvider.notifier);

      final empty = await actions.quickCreateLabel('   ');
      expect(empty, isA<ActionValidationFailed>());
      expect(
        (empty as ActionValidationFailed).message,
        equals(englishLocalizations.labelNameErrorEmpty),
      );

      final duplicate = await actions.quickCreateLabel('  wOrK  ');
      expect(duplicate, isA<ActionValidationFailed>());
      expect(
        (duplicate as ActionValidationFailed).message,
        equals(englishLocalizations.labelNameErrorDuplicate),
      );
      final duplicateNotice = harness.container.read(floatingNoticeProvider);
      expect(duplicateNotice?.tone, equals(FloatingNoticeTone.danger));
      expect(
        duplicateNotice?.message,
        equals(englishLocalizations.labelNameErrorDuplicate),
      );

      final maxScalarsName = '\u{10000}' * maxTdfTextLength;
      final atLimit = await actions.quickCreateLabel(maxScalarsName);
      expect(
        atLimit,
        isA<ActionSucceeded>(),
        reason: '500 Unicode scalars must be accepted',
      );

      final overLimit = await actions.quickCreateLabel(
        'a' * (maxTdfTextLength + 1),
      );
      expect(
        overLimit,
        isA<ActionValidationFailed>(),
        reason: '501 Unicode scalars must be rejected',
      );

      for (final bad in <String>[
        'Line1\nLine2',
        'Tab\tName',
        'Null\x00Byte',
        'Del\x7FChar',
        'Surrogate\uD800Bad',
      ]) {
        final rejected = await actions.quickCreateLabel(bad);
        expect(
          rejected,
          isA<ActionValidationFailed>(),
          reason: 'Control/surrogate input "$bad" must be rejected',
        );
      }
    });

    test('createLabelDraft persists full payload, closes draft, logs redacted telemetry, and auto-expands', () async {
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.info,
        persistToDisk: false,
      );
      final harness = createEntityHarness();
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);

      final shell = harness.container.read(shellProvider.notifier);
      shell.openDraft(EntityDraftKind.label, seedTitle: 'Private');

      final actions = harness.container.read(entityActionsProvider.notifier);
      final result = await actions.createLabelDraft(
        LabelDraftInput(
          name: '  Deep Work  ',
          colorHex: '#4caf50',
          isScoped: true,
          note: 'Line 1\r\nSecret Line 2',
          links: const <TaskLink>[
            TaskLink(
              title: 'Spec Docs',
              uri: 'https://secret.example.com/path',
            ),
          ],
          conditions: ConditionDraft(
            daysMode: ConditionDimensionMode.custom,
            weekdays: const <int>[1, 3, 5],
            timeMode: ConditionDimensionMode.custom,
            timeWindows: const <TimeWindowDraft>[
              TimeWindowDraft(start: '09:00', end: '17:00'),
            ],
            locationMode: ConditionDimensionMode.custom,
            locationIds: const <String>['loc0000001'],
          ),
        ),
      );

      expect(result, isA<ActionSucceeded>());
      final labelId = (result as ActionSucceeded).entityId ?? '';
      expect(labelId, isNotEmpty);

      final board = harness.container.read(taskNotifierProvider).requireValue;
      final created = board.findLabel(labelId);
      expect(created, isNotNull);
      expect(created?.name, equals('Deep Work'));
      expect(created?.color, equals('#4CAF50'));
      expect(created?.isScoped, isTrue);
      expect(created?.note, equals('Line 1\nSecret Line 2'));
      expect(created?.links, hasLength(1));
      expect(created?.links.first.title, equals('Spec Docs'));
      expect(
        created?.links.first.uri,
        equals('https://secret.example.com/path'),
      );
      expect(created?.conditions, hasLength(3));

      final shellState = harness.container.read(shellProvider);
      expect(shellState.activeDraft, isNull);
      expect(
        shellState.expandedEntity,
        equals(EntityRef(kind: EntityKind.label, id: labelId)),
      );
      expect(
        shellState.revealEntityRequest,
        equals(EntityRef(kind: EntityKind.label, id: labelId)),
      );
      expect(
        harness.container.read(floatingNoticeProvider)?.message,
        equals(englishLocalizations.labelSavedNotice),
      );

      final logText = AppLogger.fullLogText;
      expect(logText, contains('ui.entity_draft_committed | kind=label'));
      expect(logText, isNot(contains('Secret Line 2')));
      expect(logText, isNot(contains('secret.example.com')));
    });

    test(
      'createLabelDraft enforces color, note, link, and condition bounds',
      () async {
        final harness = createEntityHarness();
        addTearDown(harness.container.dispose);
        await harness.container.read(taskNotifierProvider.future);
        final actions = harness.container.read(entityActionsProvider.notifier);

        final badColor = await actions.createLabelDraft(
          LabelDraftInput(name: 'BadColor', colorHex: '#12345'),
        );
        expect(badColor, isA<ActionValidationFailed>());
        expect(
          (badColor as ActionValidationFailed).fieldErrors['color'],
          equals(englishLocalizations.labelColorErrorInvalid),
        );

        final longNote = await actions.createLabelDraft(
          LabelDraftInput(name: 'LongNote', note: 'n' * (maxTdfNoteLength + 1)),
        );
        expect(longNote, isA<ActionValidationFailed>());
        expect(
          (longNote as ActionValidationFailed).fieldErrors['note'],
          equals(englishLocalizations.schedulingNoteErrorTooLong),
        );

        final badNoteChar = await actions.createLabelDraft(
          LabelDraftInput(name: 'BadNote', note: 'Bad\x07Bell'),
        );
        expect(badNoteChar, isA<ActionValidationFailed>());
        expect(
          (badNoteChar as ActionValidationFailed).fieldErrors['note'],
          equals(englishLocalizations.schedulingNoteErrorInvalid),
        );

        final tooManyLinks = List<TaskLink>.generate(
          maxTdfLinksPerLabel + 1,
          (i) => TaskLink(title: 'Link $i', uri: 'https://example.com/$i'),
        );
        final linkOverflow = await actions.createLabelDraft(
          LabelDraftInput(name: 'ManyLinks', links: tooManyLinks),
        );
        expect(linkOverflow, isA<ActionValidationFailed>());
        expect(
          (linkOverflow as ActionValidationFailed).fieldErrors['links'],
          equals(englishLocalizations.labelLinkErrorMaxExceeded),
        );

        for (final badLink in const <TaskLink>[
          TaskLink(title: 'XSS', uri: 'javascript:alert(1)'),
          TaskLink(title: 'Data', uri: 'data:text/html,hi'),
          TaskLink(title: 'NoScheme', uri: 'example.com'),
          TaskLink(title: '   ', uri: 'https://example.com'),
        ]) {
          final rejected = await actions.createLabelDraft(
            LabelDraftInput(name: 'BadLink', links: <TaskLink>[badLink]),
          );
          expect(
            rejected,
            isA<ActionValidationFailed>(),
            reason: 'Expected invalid link ${badLink.uri} to fail',
          );
          expect(
            (rejected as ActionValidationFailed).fieldErrors['links'],
            equals(englishLocalizations.linkErrorInvalid),
          );
        }

        final equalTime = await actions.createLabelDraft(
          LabelDraftInput(
            name: 'EqualTime',
            conditions: ConditionDraft(
              timeMode: ConditionDimensionMode.custom,
              timeWindows: const <TimeWindowDraft>[
                TimeWindowDraft(start: '10:00', end: '10:00'),
              ],
            ),
          ),
        );
        expect(equalTime, isA<ActionValidationFailed>());
        expect(
          (equalTime as ActionValidationFailed).fieldErrors['conditions'],
          equals(englishLocalizations.conditionTimeErrorInvalid),
        );

        final unknownLocation = await actions.createLabelDraft(
          LabelDraftInput(
            name: 'UnknownLoc',
            conditions: ConditionDraft(
              locationMode: ConditionDimensionMode.custom,
              locationIds: const <String>['missing001'],
            ),
          ),
        );
        expect(unknownLocation, isA<ActionValidationFailed>());
        expect(
          (unknownLocation as ActionValidationFailed).fieldErrors['conditions'],
          equals(englishLocalizations.conditionLocationErrorInvalid),
        );

        final tooManyLocationRefs = await actions.createLabelDraft(
          LabelDraftInput(
            name: 'TooManyLocRefs',
            conditions: ConditionDraft(
              locationMode: ConditionDimensionMode.custom,
              locationIds: List<String>.filled(
                maxTdfLocationRefsPerEntity + 1,
                'loc0000001',
              ),
            ),
          ),
        );
        expect(tooManyLocationRefs, isA<ActionValidationFailed>());
        expect(
          (tooManyLocationRefs as ActionValidationFailed)
              .fieldErrors['conditions'],
          equals(englishLocalizations.errorLocalFileTooLarge),
        );

        final invalidWeekday = await actions.createLabelDraft(
          LabelDraftInput(
            name: 'BadWeekday',
            conditions: ConditionDraft(
              daysMode: ConditionDimensionMode.custom,
              weekdays: const <int>[0, 8],
            ),
          ),
        );
        expect(invalidWeekday, isA<ActionValidationFailed>());

        final exactLinks = List<TaskLink>.generate(
          maxTdfLinksPerLabel,
          (i) => TaskLink(title: 'Link $i', uri: 'https://example.com/$i'),
        );
        final exactValid = await actions.createLabelDraft(
          LabelDraftInput(
            name: 'ExactBounds',
            note: 'n' * maxTdfNoteLength,
            links: exactLinks,
          ),
        );
        expect(exactValid, isA<ActionSucceeded>());
      },
    );

    test('inline label saves, live Board Scope toggle, clear actions, and deleteLabel without Undo', () async {
      final harness = createEntityHarness();
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);

      final actions = harness.container.read(entityActionsProvider.notifier);
      final shell = harness.container.read(shellProvider.notifier);

      await actions.quickCreateLabel('Personal');

      shell.openInlineEdit(
        InlineEditTarget.label('work000001', LabelSectionKind.title),
      );
      expect(
        await actions.saveLabelName('work000001', 'personal'),
        isA<ActionValidationFailed>(),
      );
      expect(
        await actions.saveLabelName('work000001', 'WORK'),
        isA<ActionSucceeded>(),
      );
      expect(harness.container.read(shellProvider).activeInlineEdit, isNull);
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001')
            ?.name,
        equals('WORK'),
      );

      shell.openInlineEdit(
        InlineEditTarget.label('work000001', LabelSectionKind.note),
      );
      expect(
        await actions.saveLabelNote('work000001', 'Scope guidelines'),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001')
            ?.note,
        equals('Scope guidelines'),
      );
      expect(
        await actions.clearLabelNote('work000001'),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001')
            ?.note,
        isNull,
      );

      expect(
        await actions.saveLabelLinks('work000001', const <TaskLink>[
          TaskLink(title: 'Wiki', uri: 'https://wiki.example'),
        ]),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001')
            ?.links,
        hasLength(1),
      );

      expect(
        await actions.saveLabelColor('work000001', 'bad'),
        isA<ActionValidationFailed>(),
      );
      expect(
        await actions.saveLabelColor('work000001', 'ff9100'),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001')
            ?.color,
        equals('#FF9100'),
      );
      expect(
        await actions.clearLabelColor('work000001'),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001')
            ?.color,
        isNull,
      );

      expect(
        await actions.setLabelScoped('work000001', true),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001')
            ?.isScoped,
        isTrue,
      );
      expect(
        await actions.setLabelScoped('work000001', false),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001')
            ?.isScoped,
        isFalse,
      );

      expect(
        await actions.saveLabelConditions(
          'work000001',
          ConditionDraft(
            daysMode: ConditionDimensionMode.custom,
            weekdays: const <int>[1, 2],
            locationMode: ConditionDimensionMode.custom,
            locationIds: const <String>['loc0000001'],
          ),
        ),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001')
            ?.conditions,
        hasLength(2),
      );
      expect(
        await actions.clearLabelConditions('work000001'),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001')
            ?.conditions,
        isEmpty,
      );

      const labelRef = EntityRef(kind: EntityKind.label, id: 'work000001');
      shell.expandEntity(labelRef);
      shell.requestInlineDelete(labelRef);
      final deleted = await actions.deleteLabel('work000001');
      expect(deleted, isA<ActionSucceeded>());
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLabel('work000001'),
        isNull,
      );
      final shellAfter = harness.container.read(shellProvider);
      expect(shellAfter.expandedEntity, isNull);
      expect(shellAfter.activeDeleteConfirm, isNull);
      final notice = harness.container.read(floatingNoticeProvider);
      expect(notice?.message, equals(englishLocalizations.labelDeletedNotice));
      expect(notice?.hasUndoAction, isFalse);
      expect(harness.container.read(taskUndoStateProvider).canUndo, isFalse);
    });
  });

  group('EntityActionsNotifier Locations', () {
    test('quickCreateLocation seeds foreground GPS fix rounded to 6dp with 200m default radius or falls back to 0, 0', () async {
      final gpsHarness = createEntityHarness(
        initialTdf: 'tdf 0.8.0\n',
        locationState: const LocationState.found(
          fix: LocationFix(latitude: 52.5200089, longitude: 13.4049541),
        ),
      );
      addTearDown(gpsHarness.container.dispose);
      await gpsHarness.container.read(taskNotifierProvider.future);

      final gpsActions = gpsHarness.container.read(
        entityActionsProvider.notifier,
      );
      final gpsResult = await gpsActions.quickCreateLocation('  Home  ');
      expect(gpsResult, isA<ActionSucceeded>());
      final gpsId = (gpsResult as ActionSucceeded).entityId ?? '';
      final createdWithGps = gpsHarness.container
          .read(taskNotifierProvider)
          .requireValue
          .findLocation(gpsId);
      expect(createdWithGps?.name, equals('Home'));
      expect(createdWithGps?.latitude, equals(52.520009));
      expect(createdWithGps?.longitude, equals(13.404954));
      expect(createdWithGps?.radius, equals(200.0));
      expect(
        gpsHarness.container.read(shellProvider).expandedEntity,
        equals(EntityRef(kind: EntityKind.location, id: gpsId)),
      );
      expect(
        gpsHarness.container.read(floatingNoticeProvider)?.message,
        equals(englishLocalizations.locationSavedNotice),
      );

      final noFixHarness = createEntityHarness(initialTdf: 'tdf 0.8.0\n');
      addTearDown(noFixHarness.container.dispose);
      await noFixHarness.container.read(taskNotifierProvider.future);

      final noFixActions = noFixHarness.container.read(
        entityActionsProvider.notifier,
      );
      final noFixResult = await noFixActions.quickCreateLocation('Fallback');
      expect(noFixResult, isA<ActionSucceeded>());
      final noFixId = (noFixResult as ActionSucceeded).entityId ?? '';
      final createdFallback = noFixHarness.container
          .read(taskNotifierProvider)
          .requireValue
          .findLocation(noFixId);
      expect(createdFallback?.latitude, equals(0.0));
      expect(createdFallback?.longitude, equals(0.0));
      expect(createdFallback?.radius, equals(200.0));
    });

    test('createLocationDraft parses radius bounds (0.01m..100km, m/km, comma/dot), coordinates, source, note, and closes draft', () async {
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.info,
        persistToDisk: false,
      );
      final harness = createEntityHarness(initialTdf: 'tdf 0.8.0\n');
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);

      final actions = harness.container.read(entityActionsProvider.notifier);
      final shell = harness.container.read(shellProvider.notifier);

      final radiusCases = <({String input, double expectedMeters})>[
        (input: '0.01m', expectedMeters: 0.01),
        (input: '0,01m', expectedMeters: 0.01),
        (input: '0.00001km', expectedMeters: 0.01),
        (input: '250', expectedMeters: 250.0),
        (input: '1,5km', expectedMeters: 1500.0),
        (input: '1.25 KM', expectedMeters: 1250.0),
        (input: '100000m', expectedMeters: 100000.0),
        (input: '100km', expectedMeters: 100000.0),
        (input: '100,0km', expectedMeters: 100000.0),
      ];
      for (var i = 0; i < radiusCases.length; i++) {
        final testCase = radiusCases[i];
        shell.openDraft(EntityDraftKind.location);
        final result = await actions.createLocationDraft(
          LocationDraftInput(
            name: 'Place $i',
            sourceType: LocationSourceType.address,
            rawSource: 'Alexanderplatz, Berlin',
            rawLatitude: '52,521918',
            rawLongitude: '13,413215',
            rawRadius: testCase.input,
            note: 'Floor 2\r\nSecret entry code',
          ),
        );
        expect(
          result,
          isA<ActionSucceeded>(),
          reason: 'Expected radius "${testCase.input}" to succeed',
        );
        final createdId = (result as ActionSucceeded).entityId ?? '';
        final location = harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLocation(createdId);
        expect(
          location?.radius,
          equals(testCase.expectedMeters),
          reason: 'Radius mismatch for "${testCase.input}"',
        );
        expect(location?.latitude, equals(52.521918));
        expect(location?.longitude, equals(13.413215));
        expect(location?.source, equals('Alexanderplatz, Berlin'));
        expect(location?.note, equals('Floor 2\nSecret entry code'));
        expect(harness.container.read(shellProvider).activeDraft, isNull);
      }

      final logText = AppLogger.fullLogText;
      expect(logText, contains('ui.entity_draft_committed | kind=location'));
      expect(logText, isNot(contains('Secret entry code')));
      expect(logText, isNot(contains('Alexanderplatz')));
      expect(logText, isNot(contains('52.521918')));

      for (final badRadius in const <String>[
        '',
        '0',
        '0.009m',
        '0,004m',
        '-10m',
        '100.01km',
        '100,01km',
        '100001',
        '1,2.3m',
        'NaN',
        '100m\n',
      ]) {
        final rejected = await actions.createLocationDraft(
          LocationDraftInput(
            name: 'BadRadius',
            rawLatitude: '52.52',
            rawLongitude: '13.405',
            rawRadius: badRadius,
          ),
        );
        expect(
          rejected,
          isA<ActionValidationFailed>(),
          reason: 'Expected radius "$badRadius" to be rejected',
        );
        expect(
          (rejected as ActionValidationFailed).fieldErrors['radius'],
          equals(englishLocalizations.locationRadiusErrorInvalid),
        );
      }

      for (final badCoordinates in const <({String lat, String lon})>[
        (lat: '90.01', lon: '0'),
        (lat: '-90.01', lon: '0'),
        (lat: '0', lon: '180.01'),
        (lat: '0', lon: '-180.01'),
        (lat: 'NaN', lon: '0'),
        (lat: '', lon: '13.4'),
      ]) {
        final rejected = await actions.createLocationDraft(
          LocationDraftInput(
            name: 'BadCoordinates',
            rawLatitude: badCoordinates.lat,
            rawLongitude: badCoordinates.lon,
            rawRadius: '100m',
          ),
        );
        expect(
          rejected,
          isA<ActionValidationFailed>(),
          reason:
              'Expected coordinates (${badCoordinates.lat}, ${badCoordinates.lon}) to fail',
        );
        expect(
          (rejected as ActionValidationFailed).fieldErrors['coordinates'],
          equals(englishLocalizations.locationCoordinatesErrorInvalid),
        );
      }

      final controlSource = await actions.createLocationDraft(
        const LocationDraftInput(
          name: 'BadSource',
          sourceType: LocationSourceType.address,
          rawSource: 'Berlin\x00Null',
          rawLatitude: '52.52',
          rawLongitude: '13.405',
          rawRadius: '100m',
        ),
      );
      expect(controlSource, isA<ActionValidationFailed>());
      expect(
        (controlSource as ActionValidationFailed).fieldErrors['source'],
        equals(englishLocalizations.locationSourceErrorEmpty),
      );

      final overlongSource = await actions.createLocationDraft(
        LocationDraftInput(
          name: 'LongSource',
          sourceType: LocationSourceType.address,
          rawSource: 's' * (maxTdfTextLength + 1),
          rawLatitude: '52.52',
          rawLongitude: '13.405',
          rawRadius: '100m',
        ),
      );
      expect(overlongSource, isA<ActionValidationFailed>());
      expect(
        (overlongSource as ActionValidationFailed).fieldErrors['source'],
        equals(englishLocalizations.locationSourceErrorEmpty),
      );
    });

    test('enforces maxTdfLocations = 200 bound in quickCreateLocation and createLocationDraft', () async {
      final buffer = StringBuffer('tdf 0.8.0\n');
      for (var i = 0; i < maxTdfLocations - 1; i++) {
        final idSuffix = i.toString().padLeft(6, '0');
        buffer.writeln('''
location locA$idSuffix {
  name "Loc $i"
  coordinates 52.52 13.405
  radius 100
  modified 2026-11-01 08:00:00
}''');
      }
      final harness = createEntityHarness(initialTdf: buffer.toString());
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);
      final actions = harness.container.read(entityActionsProvider.notifier);

      final atLimit = await actions.quickCreateLocation('Location 200');
      expect(
        atLimit,
        isA<ActionSucceeded>(),
        reason: '200th location must succeed',
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .locations
            .length,
        equals(maxTdfLocations),
      );

      final quickOverflow = await actions.quickCreateLocation('Location 201');
      expect(quickOverflow, isA<ActionValidationFailed>());
      expect(
        harness.container.read(floatingNoticeProvider)?.tone,
        equals(FloatingNoticeTone.danger),
      );

      final draftOverflow = await actions.createLocationDraft(
        const LocationDraftInput(
          name: 'Draft 201',
          rawLatitude: '52.52',
          rawLongitude: '13.405',
          rawRadius: '100m',
        ),
      );
      expect(draftOverflow, isA<ActionValidationFailed>());
    });

    test('inline location saves (name, note, coordinates/source) and deleteLocation without Undo', () async {
      final harness = createEntityHarness();
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);

      final actions = harness.container.read(entityActionsProvider.notifier);
      final shell = harness.container.read(shellProvider.notifier);

      shell.openInlineEdit(
        InlineEditTarget.location('loc0000001', LocationSectionKind.title),
      );
      expect(
        await actions.saveLocationName('loc0000001', 'HQ Berlin'),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLocation('loc0000001')
            ?.name,
        equals('HQ Berlin'),
      );
      expect(harness.container.read(shellProvider).activeInlineEdit, isNull);

      expect(
        await actions.saveLocationNote('loc0000001', 'North wing'),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLocation('loc0000001')
            ?.note,
        equals('North wing'),
      );
      expect(
        await actions.clearLocationNote('loc0000001'),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLocation('loc0000001')
            ?.note,
        isNull,
      );

      expect(
        await actions.saveLocationCoordinates(
          'loc0000001',
          sourceType: LocationSourceType.plusCode,
          rawSource: '9F4MG9X5+XX Berlin',
          rawLatitude: '52.549938',
          rawLongitude: '13.359938',
          rawRadius: '0,5km',
        ),
        isA<ActionSucceeded>(),
      );
      var updated = harness.container
          .read(taskNotifierProvider)
          .requireValue
          .findLocation('loc0000001');
      expect(updated?.source, equals('9F4MG9X5+XX Berlin'));
      expect(updated?.radius, equals(500.0));

      expect(
        await actions.saveLocationCoordinates(
          'loc0000001',
          sourceType: LocationSourceType.gps,
          rawSource: 'ignored in gps mode',
          rawLatitude: '52.52',
          rawLongitude: '13.405',
          rawRadius: '100m',
        ),
        isA<ActionSucceeded>(),
      );
      updated = harness.container
          .read(taskNotifierProvider)
          .requireValue
          .findLocation('loc0000001');
      expect(updated?.source, isNull);
      expect(updated?.radius, equals(100.0));

      const locationRef = EntityRef(
        kind: EntityKind.location,
        id: 'loc0000001',
      );
      shell.expandEntity(locationRef);
      shell.requestInlineDelete(locationRef);
      expect(
        await actions.deleteLocation('loc0000001'),
        isA<ActionSucceeded>(),
      );
      expect(
        harness.container
            .read(taskNotifierProvider)
            .requireValue
            .findLocation('loc0000001'),
        isNull,
      );
      final shellAfter = harness.container.read(shellProvider);
      expect(shellAfter.expandedEntity, isNull);
      expect(shellAfter.activeDeleteConfirm, isNull);
      final notice = harness.container.read(floatingNoticeProvider);
      expect(
        notice?.message,
        equals(englishLocalizations.locationDeletedNotice),
      );
      expect(notice?.hasUndoAction, isFalse);

      expect(
        await actions.saveLabelName('missing001', 'Name'),
        isA<ActionValidationFailed>(),
      );
      expect(
        await actions.setLabelScoped('missing001', true),
        isA<ActionValidationFailed>(),
      );
      expect(
        await actions.saveLocationName('missing001', 'Place'),
        isA<ActionValidationFailed>(),
      );
    });
  });

  group('EntityActionsNotifier GPS, Address & Plus Code resolution', () {
    test('resolveCurrentGpsPosition refreshes missing fix, formats 6dp, and emits gpsAppliedNotice', () async {
      final harness = createEntityHarness(
        refreshedFix: const LocationFix(
          latitude: 52.5200089,
          longitude: 13.4049541,
        ),
      );
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);

      final actions = harness.container.read(entityActionsProvider.notifier);
      final resolved = await actions.resolveCurrentGpsPosition();
      expect(resolved, isNotNull);
      expect(resolved?.latitudeText, equals('52.520009'));
      expect(resolved?.longitudeText, equals('13.404954'));
      expect(harness.locationNotifier.refreshCalls, equals(1));
      expect(
        harness.container.read(floatingNoticeProvider)?.message,
        equals(englishLocalizations.gpsAppliedNotice),
      );

      final unavailableHarness = createEntityHarness();
      addTearDown(unavailableHarness.container.dispose);
      await unavailableHarness.container.read(taskNotifierProvider.future);
      final unavailableActions = unavailableHarness.container.read(
        entityActionsProvider.notifier,
      );
      expect(await unavailableActions.resolveCurrentGpsPosition(), isNull);
      expect(unavailableHarness.container.read(floatingNoticeProvider), isNull);
    });

    test('resolveLocationSource returns real LocationSourceResolutionResult and tracks isResolvingLocation', () async {
      final harness = createEntityHarness();
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);

      final actions = harness.container.read(entityActionsProvider.notifier);

      final fullPlus = await actions.resolveLocationSource(
        sourceType: LocationSourceType.plusCode,
        rawSource: '9F4MG9X5+XX Berlin',
      );
      expect(fullPlus, isA<LocationSourceResolved>());
      final resolvedPlus = fullPlus as LocationSourceResolved;
      expect(resolvedPlus.sourceType, equals(LocationSourceType.plusCode));
      expect(resolvedPlus.normalizedSource, equals('9F4MG9X5+XX Berlin'));
      expect(
        harness.container.read(floatingNoticeProvider)?.message,
        equals(englishLocalizations.locationResolvedNotice),
      );

      final controlInjected = await actions.resolveLocationSource(
        sourceType: LocationSourceType.address,
        rawSource: 'Berlin\nInjected',
      );
      expect(controlInjected, isA<LocationSourceResolutionError>());

      final completer = Completer<List<GeocodingCandidate>>();
      harness.locationRepository.nextSearchCompleter = completer;

      final future = actions.resolveLocationSource(
        sourceType: LocationSourceType.address,
        rawSource: 'Springfield',
      );
      expect(
        harness.container.read(entityActionsProvider).isResolvingLocation,
        isTrue,
      );

      completer.complete(const <GeocodingCandidate>[
        GeocodingCandidate(
          displayName: 'Springfield, IL',
          latitude: 39.7817,
          longitude: -89.6501,
        ),
        GeocodingCandidate(
          displayName: 'Springfield, OR',
          latitude: 44.0462,
          longitude: -123.0220,
        ),
      ]);
      final multiAddress = await future;
      expect(
        harness.container.read(entityActionsProvider).isResolvingLocation,
        isFalse,
      );
      expect(multiAddress, isA<LocationSourceNeedsDisambiguation>());
      final disambiguation = multiAddress as LocationSourceNeedsDisambiguation;
      expect(disambiguation.candidates, hasLength(2));
      expect(
        disambiguation.candidates[1].displayName,
        equals('Springfield, OR'),
      );

      final appliedAddress = actions.applyDisambiguatedCandidate(
        candidate: disambiguation.candidates[1],
        sourceType: disambiguation.sourceType,
      );
      expect(appliedAddress, isA<LocationSourceResolved>());
      expect(
        (appliedAddress as LocationSourceResolved).normalizedSource,
        equals('Springfield, OR'),
      );
      expect(
        harness.container.read(floatingNoticeProvider)?.message,
        equals(englishLocalizations.locationResolvedNotice),
      );

      expect(
        await actions.resolveLocationSource(
          sourceType: LocationSourceType.gps,
          rawSource: 'Berlin',
        ),
        equals(const LocationSourceNotNeeded()),
      );

      harness.locationRepository.searchResults = const <GeocodingCandidate>[];
      expect(
        await actions.resolveLocationSource(
          sourceType: LocationSourceType.address,
          rawSource: 'Nowhere',
        ),
        isA<LocationSourceResolutionError>(),
      );

      harness.locationRepository.searchResults = const <GeocodingCandidate>[
        GeocodingCandidate(
          displayName: 'Munich, Germany',
          latitude: 48.1351,
          longitude: 11.5820,
        ),
      ];
      final singleAddress = await actions.resolveLocationSource(
        sourceType: LocationSourceType.address,
        rawSource: 'Munich',
      );
      expect(singleAddress, isA<LocationSourceResolved>());
      expect(
        (singleAddress as LocationSourceResolved).normalizedSource,
        equals('Munich, Germany'),
      );

      harness.locationRepository.searchResults = const <GeocodingCandidate>[
        GeocodingCandidate(
          displayName: 'Springfield, IL',
          latitude: 39.7817,
          longitude: -89.6501,
        ),
        GeocodingCandidate(
          displayName: 'Springfield, OR',
          latitude: 44.0462,
          longitude: -123.0220,
        ),
      ];
      final shortPlus = await actions.resolveLocationSource(
        sourceType: LocationSourceType.plusCode,
        rawSource: 'G9X5+XX Springfield',
      );
      expect(shortPlus, isA<LocationSourceNeedsDisambiguation>());
      final shortDisambiguation =
          shortPlus as LocationSourceNeedsDisambiguation;
      expect(shortDisambiguation.shortPlusCode, equals('G9X5+XX'));
      expect(shortDisambiguation.localityQuery, equals('Springfield'));

      final appliedShort = actions.applyDisambiguatedCandidate(
        candidate: shortDisambiguation.candidates[0],
        sourceType: shortDisambiguation.sourceType,
        shortPlusCode: shortDisambiguation.shortPlusCode,
        localityQuery: shortDisambiguation.localityQuery,
      );
      expect(appliedShort, isA<LocationSourceResolved>());
      expect(
        (appliedShort as LocationSourceResolved).normalizedSource,
        equals('G9X5+XX Springfield'),
      );

      harness.locationRepository.nextSearchError = Exception('Network timeout');
      final lookupFailed = await actions.resolveLocationSource(
        sourceType: LocationSourceType.address,
        rawSource: 'Berlin',
      );
      expect(lookupFailed, isA<LocationSourceResolutionError>());
      expect(
        harness.container.read(entityActionsProvider).isResolvingLocation,
        isFalse,
      );
    });
  });

  group('EntityActionsNotifier delimiter round-trip, busy guard, workspace switch, and offline StorageMode.both', () {
    test('round-trips quotes, backslashes, braces, and # comments cleanly through TDF 0.8.0 persistence', () async {
      final harness = createEntityHarness(initialTdf: 'tdf 0.8.0\n');
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);
      final actions = harness.container.read(entityActionsProvider.notifier);

      const labelName = r'Work "Q1" {urgent} #core \ team';
      const labelNote = 'Line 1 #comment\n"quoted" \\ {braces}';
      const locationName = r'Cafe "Alpha" {North} #2 \ Patio';
      const locationSource = r'123 "Main" St {Unit 4} #back \ Entrance';

      final labelResult = await actions.createLabelDraft(
        LabelDraftInput(
          name: labelName,
          note: labelNote,
          links: const <TaskLink>[
            TaskLink(
              title: r'Doc "1" {spec} #top \ link',
              uri: 'https://example.com/a?x=1#frag',
            ),
          ],
        ),
      );
      expect(labelResult, isA<ActionSucceeded>());

      final locationResult = await actions.createLocationDraft(
        const LocationDraftInput(
          name: locationName,
          sourceType: LocationSourceType.address,
          rawSource: locationSource,
          rawLatitude: '52.52',
          rawLongitude: '13.405',
          rawRadius: '150m',
          note: labelNote,
        ),
      );
      expect(locationResult, isA<ActionSucceeded>());

      final parsed = const TdfService().parse(
        harness.localRepository.initialTdf,
      );
      expect(parsed.labels.single.name, equals(labelName));
      expect(parsed.labels.single.note, equals(labelNote));
      expect(
        parsed.labels.single.links.single.title,
        equals(r'Doc "1" {spec} #top \ link'),
      );
      expect(parsed.locations.single.name, equals(locationName));
      expect(parsed.locations.single.source, equals(locationSource));
      expect(parsed.locations.single.note, equals(labelNote));
    });

    test('serializes mid-flight mutations via isBusy and surfaces sanitized ActionPersistFailed on error', () async {
      final initialBoard = TaskBoard.empty().addLabel(
        'Work',
        id: 'work000001',
        currentDate: fixedNow,
      );
      final blockingNotifier = _BlockingTaskNotifier(initialBoard);
      final container = ProviderContainer(
        overrides: [
          taskNotifierProvider.overrideWith(() => blockingNotifier),
          appLocaleProvider.overrideWithValue(germanLocale),
          clockProvider.overrideWithValue(() => fixedNow),
        ],
      );
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      final actions = container.read(entityActionsProvider.notifier);
      final completer = Completer<void>();
      blockingNotifier.nextMutationCompleter = completer;

      final firstFuture = actions.quickCreateLabel('Queued');
      expect(container.read(entityActionsProvider).isBusy, isTrue);

      final overlapping = await actions.quickCreateLabel('Concurrent');
      expect(overlapping, isA<ActionPersistFailed>());

      completer.complete();
      expect(await firstFuture, isA<ActionSucceeded>());
      expect(container.read(entityActionsProvider).isBusy, isFalse);

      blockingNotifier.nextError = Exception('SENSITIVE_SECRET_TOKEN_XYZ');
      final failed = await actions.saveLabelName(
        'work000001',
        'Renamed',
        locale: germanLocale,
      );
      expect(failed, isA<ActionPersistFailed>());
      final persistFailure = failed as ActionPersistFailed;
      expect(
        persistFailure.message,
        isNot(contains('SENSITIVE_SECRET_TOKEN_XYZ')),
      );
      expect(persistFailure.message, isNotEmpty);

      blockingNotifier.nextError = const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message: 'raw internal detail',
      );
      final tdfFailed = await actions.saveLabelName(
        'work000001',
        'Renamed',
        locale: germanLocale,
      );
      expect(tdfFailed, isA<ActionPersistFailed>());
      expect(
        (tdfFailed as ActionPersistFailed).message,
        equals(germanLocalizations.errorLocalFileTooLarge),
      );

      final germanEmpty = await actions.quickCreateLabel(
        '   ',
        locale: germanLocale,
      );
      expect(germanEmpty, isA<ActionValidationFailed>());
      expect(
        (germanEmpty as ActionValidationFailed).message,
        equals(germanLocalizations.labelNameErrorEmpty),
      );
    });

    test('resets busy state on actual workspace switch while ignoring transient AsyncLoading', () async {
      final initialBoard = TaskBoard.empty().addLabel(
        'Work',
        id: 'work000001',
        currentDate: fixedNow,
      );
      final blockingNotifier = _BlockingTaskNotifier(initialBoard);
      final workspaceNotifier = _ControllableWorkspaceNotifier();
      final settingsRepository = InMemorySettingsRepository(
        const WebDavConfig(language: AppLanguage.english),
      );
      final secondWorkspace = await settingsRepository.createWorkspace(
        'Second',
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          activeWorkspaceProvider.overrideWith(() => workspaceNotifier),
          taskNotifierProvider.overrideWith(() => blockingNotifier),
          clockProvider.overrideWithValue(() => fixedNow),
        ],
      );
      addTearDown(container.dispose);
      final firstWorkspace = await container.read(
        activeWorkspaceProvider.future,
      );
      await container.read(taskNotifierProvider.future);

      final actions = container.read(entityActionsProvider.notifier);
      final completer = Completer<void>();
      blockingNotifier.nextMutationCompleter = completer;

      final inFlight = actions.quickCreateLabel('MidFlight');
      expect(container.read(entityActionsProvider).isBusy, isTrue);

      workspaceNotifier.emitTransientLoading();
      expect(
        container.read(entityActionsProvider).isBusy,
        isTrue,
        reason:
            'Transient AsyncLoading must not clear EntityActionsState.isBusy',
      );

      workspaceNotifier.emitWorkspace(firstWorkspace);
      expect(
        container.read(entityActionsProvider).isBusy,
        isTrue,
        reason: 'Reloading the same workspace must not clear EntityActionsState.isBusy',
      );

      workspaceNotifier.emitWorkspace(secondWorkspace);
      expect(
        container.read(entityActionsProvider).isBusy,
        isFalse,
        reason:
            'Switching to a different workspace must reset EntityActionsState',
      );

      completer.complete();
      await inFlight;
      expect(container.read(entityActionsProvider).isBusy, isFalse);
      expect(
        container.read(floatingNoticeProvider),
        isNull,
        reason: 'Stale completion from previous workspace must not emit toast on new workspace',
      );
    });

    test('offline StorageMode.both inline label and location edits commit locally and close inline editor while keeping sync error banner active', () async {
      const dualConfig = WebDavConfig(
        storageMode: StorageMode.both,
        localFilePath: '/virtual/tasks.tdf',
        serverUrl: 'https://dav.example.com/remote.php/dav/files/user/',
        username: 'user',
        password: 'secret',
        language: AppLanguage.english,
      );
      var isWebDavOffline = false;
      final endpointPath = dualConfig.resolveEndpointUri()?.path ?? '';
      expect(endpointPath, isNotEmpty);
      final remoteStore = <String, String>{endpointPath: baseTdf};
      final webDavRepository = FakeWebDavRepository(
        config: dualConfig,
        shouldFail: () => isWebDavOffline,
        remoteStore: remoteStore,
      );
      final harness = createEntityHarness(
        config: dualConfig,
        webDavRepository: webDavRepository,
      );
      addTearDown(harness.container.dispose);
      await harness.container.read(activeWorkspaceProvider.future);
      await harness.container.read(taskNotifierProvider.future);

      expect(
        harness.container.read(syncStateProvider).errorMessage,
        isNull,
        reason: 'Initial online sync in StorageMode.both must succeed cleanly',
      );

      // Go offline before editing: local writes succeed, remote WebDAV writes fail.
      isWebDavOffline = true;

      final actions = harness.container.read(entityActionsProvider.notifier);
      final shell = harness.container.read(shellProvider.notifier);

      shell.openInlineEdit(
        InlineEditTarget.label('work000001', LabelSectionKind.title),
      );
      final labelResult = await actions.saveLabelName(
        'work000001',
        'Offline Work',
      );
      expect(
        labelResult,
        isA<ActionSucceeded>(),
        reason: 'Locally committed label edit in offline StorageMode.both must succeed',
      );
      expect(
        harness.container.read(shellProvider).activeInlineEdit,
        isNull,
        reason: 'Inline label editor must close after local commit',
      );
      expect(
        harness.container.read(syncStateProvider).errorMessage,
        isNotNull,
        reason: 'Sync error banner must remain active while WebDAV is offline',
      );
      expect(
        const TdfService()
            .parse(harness.localRepository.initialTdf)
            .findLabel('work000001')
            ?.name,
        equals('Offline Work'),
      );

      shell.openInlineEdit(
        InlineEditTarget.location('loc0000001', LocationSectionKind.title),
      );
      final locationResult = await actions.saveLocationName(
        'loc0000001',
        'Offline Office',
      );
      expect(
        locationResult,
        isA<ActionSucceeded>(),
        reason: 'Locally committed location edit in offline StorageMode.both must succeed',
      );
      expect(
        harness.container.read(shellProvider).activeInlineEdit,
        isNull,
        reason: 'Inline location editor must close after local commit',
      );
      expect(
        harness.container.read(syncStateProvider).errorMessage,
        isNotNull,
        reason: 'Sync error banner must remain active while WebDAV is offline',
      );
      expect(
        const TdfService()
            .parse(harness.localRepository.initialTdf)
            .findLocation('loc0000001')
            ?.name,
        equals('Offline Office'),
      );

      // When local persistence itself fails and rolls back, inline editor must stay open.
      harness.localRepository.failNextSave = true;
      shell.openInlineEdit(
        InlineEditTarget.label('work000001', LabelSectionKind.note),
      );
      final localFailure = await actions.saveLabelNote(
        'work000001',
        'Will fail on disk',
      );
      expect(
        localFailure,
        isA<ActionPersistFailed>(),
        reason: 'Rolled-back local write must report ActionPersistFailed',
      );
      expect(
        harness.container.read(shellProvider).activeInlineEdit,
        equals(InlineEditTarget.label('work000001', LabelSectionKind.note)),
        reason: 'Inline editor must remain open when local commit rolls back',
      );
    });
  });

  group('SyncActionsNotifier refreshLocation and syncNow', () {
    test('refreshLocation delegates to LocationNotifier and surfaces mid-flight searching state', () async {
      final lookupCompleter = Completer<LocationFix?>();
      final repository = _HookedLocationRepository(
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
      final container = createSyncContainer(
        config: const WebDavConfig(
          language: AppLanguage.english,
          locationEnabled: true,
        ),
        localeOverride: englishLocale,
        locationRepository: repository,
      );
      addTearDown(container.dispose);

      await container.read(webDavConfigProvider.future);
      container.read(locationStateProvider);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(locationStateProvider).fix?.placeName,
        equals('Initial City'),
      );

      final refreshFuture = container
          .read(syncActionsProvider.notifier)
          .refreshLocation();
      expect(
        container.read(locationStateProvider).status,
        equals(LocationStatus.searching),
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
      expect(await refreshFuture, equals(const ActionSucceeded()));
      expect(
        container.read(locationStateProvider).fix?.placeName,
        equals('Berlin'),
      );
    });

    test('refreshLocation returns ActionPersistFailed when location refresh throws', () async {
      final notifier = _ControlledLocationNotifier(
        const LocationState.unavailable(),
        onRefresh: (_) => Future<void>.error(
          const LocalFileException('Location daemon unavailable'),
        ),
      );
      final container = createSyncContainer(
        localeOverride: englishLocale,
        locationEnabledOverride: true,
        locationNotifier: notifier,
      );
      addTearDown(container.dispose);

      final result = await container
          .read(syncActionsProvider.notifier)
          .refreshLocation();
      expect(result, isA<ActionPersistFailed>());
      expect(
        (result as ActionPersistFailed).message,
        contains('Location daemon unavailable'),
      );
    });

    test('syncNow triggers syncFromRemote with isBusy guard and rejects concurrent calls', () async {
      final syncCompleter = Completer<void>();
      final spyNotifier = _SpyTaskNotifier(
        board: createSampleBoard(),
        onSyncFromRemote: () => syncCompleter.future,
      );
      final container = createSyncContainer(
        localeOverride: englishLocale,
        taskNotifier: spyNotifier,
      );
      addTearDown(container.dispose);
      await container.read(taskNotifierProvider.future);

      final actions = container.read(syncActionsProvider.notifier);
      final firstCall = actions.syncNow();
      expect(container.read(syncActionsProvider).isBusy, isTrue);

      final duplicateCall = await actions.syncNow();
      expect(duplicateCall, isA<ActionPersistFailed>());
      expect(spyNotifier.syncCalls, equals(1));

      syncCompleter.complete();
      expect(await firstCall, equals(const ActionSucceeded()));
      expect(container.read(syncActionsProvider).isBusy, isFalse);
    });

    test('syncNow surfaces sync error recorded on syncStateProvider when syncFromRemote catches internally', () async {
      late ProviderContainer container;
      final spyNotifier = _SpyTaskNotifier(
        board: createSampleBoard(),
        onSyncFromRemote: () async {
          container
              .read(syncStateProvider.notifier)
              .setError('Authentication failed (HTTP 401)');
        },
      );
      container = createSyncContainer(
        localeOverride: englishLocale,
        taskNotifier: spyNotifier,
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(taskNotifierProvider.future);

      final result = await container
          .read(syncActionsProvider.notifier)
          .syncNow();
      expect(result, isA<ActionPersistFailed>());
      expect(
        (result as ActionPersistFailed).message,
        contains('Authentication failed'),
      );
      expect(container.read(syncActionsProvider).isBusy, isFalse);
    });

    test('syncNow invalidates taskNotifierProvider and retries initial load when full-screen file read error is active', () async {
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
      final container = createSyncContainer(
        localeOverride: englishLocale,
        taskNotifier: spyNotifier,
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(taskNotifierProvider.future),
        throwsA(isA<StorageFileReadException>()),
      );

      final failedRetry = await container
          .read(syncActionsProvider.notifier)
          .syncNow();
      expect(failedRetry, isA<ActionPersistFailed>());
      expect(
        (failedRetry as ActionPersistFailed).message,
        contains('Malformed header'),
      );
      expect(spyNotifier.syncCalls, equals(0));
      expect(spyNotifier.buildCalls, equals(2));

      shouldFailLoad = false;
      final recoveredRetry = await container
          .read(syncActionsProvider.notifier)
          .syncNow();
      expect(recoveredRetry, equals(const ActionSucceeded()));
      expect(spyNotifier.buildCalls, equals(3));
      expect(container.read(taskNotifierProvider).asData?.value, sampleBoard);
      expect(container.read(syncActionsProvider).isBusy, isFalse);
    });

    test('syncNow invalidates activeWorkspaceProvider when activeWorkspaceProvider has an error', () async {
      var loadAttempts = 0;
      var shouldFailWorkspace = true;
      final settingsRepo = _FailingLoadSettingsRepository(
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
      final container = createSyncContainer(settingsRepository: settingsRepo);
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
          .read(syncActionsProvider.notifier)
          .syncNow(locale: englishLocale);
      expect(
        retryResult,
        equals(const ActionSucceeded()),
        reason: 'Retry must invalidate activeWorkspaceProvider and reload workspace cleanly',
      );
      expect(loadAttempts, greaterThanOrEqualTo(2));
      expect(container.read(activeWorkspaceProvider).hasValue, isTrue);
      expect(container.read(taskNotifierProvider).hasValue, isTrue);
      expect(container.read(syncActionsProvider).isBusy, isFalse);
    });

    test('syncNow surfaces all TdfSyncOutcomeKind outcomes and fileReadReport with explicit locale', () async {
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
      container = createSyncContainer(
        localeOverride: englishLocale,
        taskNotifier: spyNotifier,
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(taskNotifierProvider.future);

      final outcomeCases = <(TdfSyncOutcomeKind, String)>[
        (
          TdfSyncOutcomeKind.deletionConflict,
          germanLocalizations.syncConflictDeletionBanner,
        ),
        (
          TdfSyncOutcomeKind.recoveryRequired,
          germanLocalizations.syncConflictRecoveryBanner,
        ),
        (
          TdfSyncOutcomeKind.syncGenerationRollback,
          germanLocalizations.syncErrorGenerationRollbackBanner,
        ),
      ];
      for (final (kind, expectedBanner) in outcomeCases) {
        outcomeToEmit = TdfSyncOutcomeException(
          kind: kind,
          message: 'Outcome ${kind.name}',
        );
        reportToEmit = null;
        final result = await container
            .read(syncActionsProvider.notifier)
            .syncNow(locale: germanLocale);
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
          .read(syncActionsProvider.notifier)
          .syncNow(locale: germanLocale);
      expect(reportResult, isA<ActionPersistFailed>());
      expect((reportResult as ActionPersistFailed).message, contains('9.9.9'));
    });
  });

  group('SyncActionsNotifier conflict and recovery resolutions', () {
    test('applyDeletionConflictResolutions passes real TdfDeletionResolution, guards isBusy, navigates to tasks, and shows toast', () async {
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
      final container = createSyncContainer(
        localeOverride: englishLocale,
        taskNotifier: spyNotifier,
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(taskNotifierProvider.future);

      container.read(shellProvider.notifier).openView(ShellView.conflict);
      expect(container.read(shellProvider).view, equals(ShellView.conflict));

      final actions = container.read(syncActionsProvider.notifier);
      final future = actions.applyDeletionConflictResolutions(
        taskDecisions: const <String, TdfDeletionResolution>{
          'task000001': TdfDeletionResolution.undelete,
          'task000002': TdfDeletionResolution.delete,
        },
        labelDecisions: const <String, TdfDeletionResolution>{
          'labl000001': TdfDeletionResolution.delete,
        },
        locationDecisions: const <String, TdfDeletionResolution>{
          'loca000001': TdfDeletionResolution.undelete,
        },
        locale: germanLocale,
      );

      expect(container.read(syncActionsProvider).isBusy, isTrue);

      final duplicate = await actions.applyDeletionConflictResolutions(
        taskDecisions: const <String, TdfDeletionResolution>{},
        labelDecisions: const <String, TdfDeletionResolution>{},
        locationDecisions: const <String, TdfDeletionResolution>{},
      );
      expect(duplicate, isA<ActionPersistFailed>());
      expect(spyNotifier.deletionResolveCalls, equals(1));

      completer.complete(sampleBoard);
      final result = await future;

      expect(
        result,
        equals(
          ActionSucceeded(
            noticeMessage: germanLocalizations.conflictResolvedNotice,
          ),
        ),
      );
      expect(container.read(syncActionsProvider).isBusy, isFalse);
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
      expect(container.read(shellProvider).view, equals(ShellView.tasks));
      final notice = container.read(floatingNoticeProvider);
      expect(
        notice?.message,
        equals(germanLocalizations.conflictResolvedNotice),
      );
      expect(notice?.tone, equals(FloatingNoticeTone.success));
    });

    test('applyDeletionConflictResolutions keeps conflict view open and formats all error variants', () async {
      Object resolutionError = const WebDavException(
        'Server busy',
        statusCode: 503,
      );
      final spyNotifier = _SpyTaskNotifier(
        board: createSampleBoard(),
        onResolveDeletionConflicts: ({
          required taskResolutions,
          required labelResolutions,
          required locationResolutions,
        }) => Future<TaskBoard>.error(resolutionError),
      );
      final container = createSyncContainer(
        localeOverride: englishLocale,
        taskNotifier: spyNotifier,
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(taskNotifierProvider.future);

      container.read(shellProvider.notifier).openView(ShellView.conflict);

      final errorCases = <(Object, String)>[
        (const WebDavException('Server busy', statusCode: 503), 'Server busy'),
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
          englishLocalizations.errorSettingsSaveFailed,
        ),
        (StateError('Unexpected boom'), 'Unexpected boom'),
      ];
      for (final (error, expectedSubstring) in errorCases) {
        resolutionError = error;
        final result = await container
            .read(syncActionsProvider.notifier)
            .applyDeletionConflictResolutions(
              taskDecisions: const <String, TdfDeletionResolution>{
                'task000001': TdfDeletionResolution.undelete,
              },
              labelDecisions: const <String, TdfDeletionResolution>{},
              locationDecisions: const <String, TdfDeletionResolution>{},
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
        expect(container.read(syncActionsProvider).isBusy, isFalse);
        expect(container.read(shellProvider).view, equals(ShellView.conflict));
        expect(container.read(floatingNoticeProvider), isNull);
      }
    });

    test('applyRecoveryResolutions passes real TdfRecoveryResolution, guards isBusy, navigates to tasks, and shows toast', () async {
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
      final container = createSyncContainer(
        localeOverride: englishLocale,
        taskNotifier: spyNotifier,
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(taskNotifierProvider.future);

      container.read(shellProvider.notifier).openView(ShellView.recovery);

      final actions = container.read(syncActionsProvider.notifier);
      final future = actions.applyRecoveryResolutions(
        taskDecisions: const <String, TdfRecoveryResolution>{
          'task000001': TdfRecoveryResolution.recoverAsNew,
          'task000002': TdfRecoveryResolution.discard,
        },
        labelDecisions: const <String, TdfRecoveryResolution>{
          'labl000001': TdfRecoveryResolution.recoverAsNew,
        },
        locationDecisions: const <String, TdfRecoveryResolution>{
          'loca000001': TdfRecoveryResolution.discard,
        },
      );

      expect(container.read(syncActionsProvider).isBusy, isTrue);

      final duplicate = await actions.applyRecoveryResolutions(
        taskDecisions: const <String, TdfRecoveryResolution>{},
        labelDecisions: const <String, TdfRecoveryResolution>{},
        locationDecisions: const <String, TdfRecoveryResolution>{},
      );
      expect(duplicate, isA<ActionPersistFailed>());
      expect(spyNotifier.recoveryResolveCalls, equals(1));

      completer.complete(sampleBoard);
      final result = await future;

      expect(
        result,
        equals(
          ActionSucceeded(
            noticeMessage: englishLocalizations.recoveryResolvedNotice,
          ),
        ),
      );
      expect(container.read(syncActionsProvider).isBusy, isFalse);
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
      expect(container.read(shellProvider).view, equals(ShellView.tasks));
      final notice = container.read(floatingNoticeProvider);
      expect(
        notice?.message,
        equals(englishLocalizations.recoveryResolvedNotice),
      );
      expect(notice?.tone, equals(FloatingNoticeTone.success));
    });

    test('applyRecoveryResolutions keeps recovery view open on TdfSyncOutcomeException failure', () async {
      final spyNotifier = _SpyTaskNotifier(
        board: createSampleBoard(),
        onResolveRecovery:
            ({
              required taskResolutions,
              required labelResolutions,
              required locationResolutions,
            }) => Future<TaskBoard>.error(
              const TdfSyncOutcomeException(
                kind: TdfSyncOutcomeKind.deletionConflict,
                message: 'Secondary conflict encountered',
                conflictedTaskIds: <String>['task000001'],
              ),
            ),
      );
      final container = createSyncContainer(
        localeOverride: englishLocale,
        taskNotifier: spyNotifier,
      );
      addTearDown(container.dispose);
      await container.read(activeWorkspaceProvider.future);
      await container.read(taskNotifierProvider.future);

      container.read(shellProvider.notifier).openView(ShellView.recovery);

      final result = await container
          .read(syncActionsProvider.notifier)
          .applyRecoveryResolutions(
            taskDecisions: const <String, TdfRecoveryResolution>{
              'task000001': TdfRecoveryResolution.recoverAsNew,
            },
            labelDecisions: const <String, TdfRecoveryResolution>{},
            locationDecisions: const <String, TdfRecoveryResolution>{},
          );

      expect(result, isA<ActionPersistFailed>());
      expect(
        (result as ActionPersistFailed).message,
        equals(englishLocalizations.syncConflictDeletionBanner),
      );
      expect(container.read(syncActionsProvider).isBusy, isFalse);
      expect(container.read(shellProvider).view, equals(ShellView.recovery));
      expect(container.read(floatingNoticeProvider), isNull);
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
      final container = createSyncContainer(
        localeOverride: englishLocale,
        settingsRepository: settingsRepository,
        taskNotifier: spyNotifier,
      );
      addTearDown(container.dispose);

      await container.read(activeWorkspaceProvider.future);
      await container.read(taskNotifierProvider.future);
      final secondWorkspace = await container
          .read(activeWorkspaceProvider.notifier)
          .createWorkspace('Second');

      container.read(shellProvider.notifier).openView(ShellView.conflict);

      final resolutionFuture = container
          .read(syncActionsProvider.notifier)
          .applyDeletionConflictResolutions(
            taskDecisions: const <String, TdfDeletionResolution>{
              'task000001': TdfDeletionResolution.undelete,
            },
            labelDecisions: const <String, TdfDeletionResolution>{},
            locationDecisions: const <String, TdfDeletionResolution>{},
          );

      await container
          .read(activeWorkspaceProvider.notifier)
          .switchWorkspace(secondWorkspace.id);
      container.read(shellProvider.notifier).openView(ShellView.settings);

      completer.complete(sampleBoard);
      await resolutionFuture;

      expect(
        container.read(shellProvider).view,
        equals(ShellView.settings),
        reason: 'Stale resolution from previous workspace must not navigate active workspace',
      );
      expect(
        container.read(floatingNoticeProvider),
        isNull,
        reason: 'Stale resolution from previous workspace must not show toast on new workspace',
      );
      expect(container.read(syncActionsProvider).isBusy, isFalse);
    });
  });

  group('WorkspaceActionsNotifier CRUD, validation, and busy guard', () {
    test('creates and activates a workspace by default and emits a surviving workspaceSwitchedNotice toast', () async {
      final container = createWorkspaceContainer();
      addTearDown(container.dispose);
      await primeWorkspaceProviders(container);

      final noticeHistory = <FloatingNotice?>[];
      final subscription = container.listen<FloatingNotice?>(
        floatingNoticeProvider,
        (_, next) => noticeHistory.add(next),
      );
      addTearDown(subscription.close);

      final actions = container.read(workspaceActionsProvider.notifier);
      final result = await actions.createWorkspace('Work');
      await container.read(workspaceSummariesProvider.future);
      await Future<void>.delayed(Duration.zero);

      final expectedNotice = englishLocalizations.workspaceSwitchedNotice(
        'Work',
      );
      expect(
        result,
        equals(
          ActionSucceeded(entityId: 'work', noticeMessage: expectedNotice),
        ),
      );
      expect(container.read(activeWorkspaceProvider).value?.id, equals('work'));

      final activeNotice = container.read(floatingNoticeProvider);
      expect(
        activeNotice?.message,
        equals(expectedNotice),
        reason: 'Toast emitted after workspace activation must survive FloatingNoticeNotifier workspace reset',
      );
      expect(activeNotice?.tone, equals(FloatingNoticeTone.neutral));
      expect(noticeHistory.last?.message, equals(expectedNotice));
    });

    test('creates a workspace with activate false without changing active workspace or emitting switch toast', () async {
      final container = createWorkspaceContainer();
      addTearDown(container.dispose);
      await primeWorkspaceProviders(container);

      final actions = container.read(workspaceActionsProvider.notifier);
      final result = await actions.createWorkspace('Personal', activate: false);
      await container.read(workspaceSummariesProvider.future);

      expect(result, equals(const ActionSucceeded(entityId: 'personal')));
      expect(
        container.read(activeWorkspaceProvider).value?.id,
        equals(AppWorkspace.defaultId),
      );
      expect(container.read(floatingNoticeProvider), isNull);
    });

    test('switches workspace, emits localized toast, and skips duplicate toast on no-op switch', () async {
      final container = createWorkspaceContainer();
      addTearDown(container.dispose);
      await primeWorkspaceProviders(container);

      final actions = container.read(workspaceActionsProvider.notifier);
      await actions.createWorkspace('Arbeit', activate: false);
      await container.read(workspaceSummariesProvider.future);

      final subscription = container.listen<FloatingNotice?>(
        floatingNoticeProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      final switchResult = await actions.switchWorkspace(
        'arbeit',
        locale: germanLocale,
      );
      await container.read(workspaceSummariesProvider.future);
      await Future<void>.delayed(Duration.zero);

      final expectedGermanNotice = germanLocalizations.workspaceSwitchedNotice(
        'Arbeit',
      );
      expect(
        switchResult,
        equals(
          ActionSucceeded(
            entityId: 'arbeit',
            noticeMessage: expectedGermanNotice,
          ),
        ),
      );
      expect(
        container.read(activeWorkspaceProvider).value?.id,
        equals('arbeit'),
      );
      expect(
        container.read(floatingNoticeProvider)?.message,
        equals(expectedGermanNotice),
      );

      container.read(floatingNoticeProvider.notifier).dismiss();
      final noopResult = await actions.switchWorkspace('arbeit');
      expect(noopResult, equals(const ActionSucceeded(entityId: 'arbeit')));
      expect(container.read(floatingNoticeProvider), isNull);
    });

    test('renames active and inactive workspaces and deletes inactive and active workspaces cleanly', () async {
      final container = createWorkspaceContainer();
      addTearDown(container.dispose);
      await primeWorkspaceProviders(container);

      final actions = container.read(workspaceActionsProvider.notifier);
      await actions.createWorkspace('Work', activate: false);
      await actions.createWorkspace('Home');
      await container.read(workspaceSummariesProvider.future);

      final renameActive = await actions.renameWorkspace(
        'home',
        '  Daily Home  ',
      );
      expect(renameActive, equals(const ActionSucceeded(entityId: 'home')));
      expect(
        container.read(activeWorkspaceProvider).value?.name,
        equals('Daily Home'),
      );

      final renameInactive = await actions.renameWorkspace(
        'work',
        'Client Work',
      );
      expect(renameInactive, equals(const ActionSucceeded(entityId: 'work')));

      final deleteInactive = await actions.deleteWorkspace('work');
      expect(deleteInactive, equals(const ActionSucceeded(entityId: 'home')));

      final deleteActive = await actions.deleteWorkspace('home');
      expect(
        deleteActive,
        equals(const ActionSucceeded(entityId: AppWorkspace.defaultId)),
      );
      expect(
        container.read(activeWorkspaceProvider).value?.id,
        equals(AppWorkspace.defaultId),
      );
    });

    test('enforces validation bounds, AppWorkspace.maxWorkspaces = 32, and exhaustive WorkspaceErrorKind mapping', () async {
      final container = createWorkspaceContainer();
      addTearDown(container.dispose);
      await primeWorkspaceProviders(container);
      final actions = container.read(workspaceActionsProvider.notifier);

      for (final invalidName in <String>[
        '',
        '   ',
        'Bad\nName',
        'A' * (AppWorkspace.maxNameLength + 1),
      ]) {
        final result = await actions.createWorkspace(
          invalidName,
          locale: englishLocale,
        );
        expect(
          result,
          equals(
            ActionValidationFailed(
              message: englishLocalizations.errorWorkspaceNameEmpty,
            ),
          ),
          reason:
              'Invalid name length=${invalidName.length} must fail validation',
        );
      }

      expect(
        await actions.createWorkspace('   ', locale: germanLocale),
        equals(
          ActionValidationFailed(
            message: germanLocalizations.errorWorkspaceNameEmpty,
          ),
        ),
      );
      expect(
        await actions.createWorkspace('  tAsKs  ', locale: englishLocale),
        equals(
          ActionValidationFailed(
            message: englishLocalizations.errorWorkspaceNameDuplicate,
          ),
        ),
      );
      expect(
        await actions.deleteWorkspace(
          AppWorkspace.defaultId,
          locale: englishLocale,
        ),
        equals(
          ActionValidationFailed(
            message: englishLocalizations.errorWorkspaceCannotDeleteLast,
          ),
        ),
      );

      for (var i = 2; i <= AppWorkspace.maxWorkspaces; i++) {
        expect(
          await actions.createWorkspace('Board $i', activate: false),
          isA<ActionSucceeded>(),
          reason: 'Creating workspace $i of 32 must succeed',
        );
      }
      expect(
        await actions.createWorkspace('Board 33', locale: englishLocale),
        equals(
          ActionValidationFailed(
            message: englishLocalizations.errorWorkspaceMaxExceeded,
          ),
        ),
      );

      final repository = _ControlledSettingsRepository(
        const WebDavConfig(language: AppLanguage.english),
      );
      final errorContainer = createWorkspaceContainer(
        settingsRepository: repository,
      );
      addTearDown(errorContainer.dispose);
      await primeWorkspaceProviders(errorContainer);
      final errorActions = errorContainer.read(
        workspaceActionsProvider.notifier,
      );

      for (final kind in WorkspaceErrorKind.values) {
        final exception = WorkspaceException(kind, 'Synthetic $kind');
        repository.nextError = exception;
        final result = await errorActions.createWorkspace(
          'Probe ${kind.name}',
          locale: englishLocale,
        );
        final expectedMessage = englishLocalizations.localizeWorkspaceError(
          exception,
        );
        final isPersistenceError = switch (kind) {
          WorkspaceErrorKind.corruptSettingsPayload ||
          WorkspaceErrorKind.unsupportedSettingsSchemaVersion ||
          WorkspaceErrorKind.credentialStorageUnavailable ||
          WorkspaceErrorKind.settingsPersistenceFailed => true,
          WorkspaceErrorKind.emptyName ||
          WorkspaceErrorKind.duplicateName ||
          WorkspaceErrorKind.duplicateFilePath ||
          WorkspaceErrorKind.invalidFilePath ||
          WorkspaceErrorKind.workspaceNotFound ||
          WorkspaceErrorKind.cannotDeleteLastWorkspace ||
          WorkspaceErrorKind.maxWorkspacesExceeded => false,
        };
        if (isPersistenceError) {
          expect(
            result,
            equals(ActionPersistFailed(message: expectedMessage)),
            reason: '$kind must map to ActionPersistFailed',
          );
        } else {
          expect(
            result,
            equals(ActionValidationFailed(message: expectedMessage)),
            reason: '$kind must map to ActionValidationFailed',
          );
        }
        expect(
          errorContainer.read(workspaceActionsProvider).isBusy,
          isFalse,
          reason: 'isBusy must reset after $kind error',
        );
      }

      repository.nextError = Exception('raw internal path /secret/settings');
      expect(
        await errorActions.createWorkspace(
          'Probe Unexpected',
          locale: englishLocale,
        ),
        equals(
          ActionPersistFailed(
            message: englishLocalizations.errorSettingsSaveFailed,
          ),
        ),
      );
      expect(errorContainer.read(workspaceActionsProvider).isBusy, isFalse);
    });

    test('blocks concurrent mutations while busy and completes safely on mid-flight container disposal', () async {
      final repository = _ControlledSettingsRepository(
        const WebDavConfig(language: AppLanguage.english),
      );
      await repository.createWorkspace('Work');

      final container = createWorkspaceContainer(
        settingsRepository: repository,
      );
      addTearDown(container.dispose);
      await primeWorkspaceProviders(container);

      final gate = Completer<void>();
      repository.activateGate = gate;
      repository.activateCallCount = 0;
      repository.createCallCount = 0;
      repository.renameCallCount = 0;
      repository.deleteCallCount = 0;

      final actions = container.read(workspaceActionsProvider.notifier);
      final inFlightSwitch = actions.switchWorkspace('work');
      expect(container.read(workspaceActionsProvider).isBusy, isTrue);

      expect(
        await actions.switchWorkspace('tasks'),
        isA<ActionValidationFailed>(),
      );
      expect(
        await actions.createWorkspace('Other'),
        isA<ActionValidationFailed>(),
      );
      expect(
        await actions.renameWorkspace('work', 'Renamed'),
        isA<ActionValidationFailed>(),
      );
      expect(
        await actions.deleteWorkspace('work'),
        isA<ActionValidationFailed>(),
      );
      expect(repository.activateCallCount, equals(1));
      expect(repository.createCallCount, equals(0));
      expect(repository.renameCallCount, equals(0));
      expect(repository.deleteCallCount, equals(0));

      gate.complete();
      expect(await inFlightSwitch, isA<ActionSucceeded>());
      expect(container.read(workspaceActionsProvider).isBusy, isFalse);

      // Mid-flight container disposal completes safely without throwing.
      final disposeRepository = _ControlledSettingsRepository(
        const WebDavConfig(language: AppLanguage.english),
      );
      final disposeContainer = createWorkspaceContainer(
        settingsRepository: disposeRepository,
      );
      await primeWorkspaceProviders(disposeContainer);

      final disposeGate = Completer<void>();
      disposeRepository.createGate = disposeGate;

      final inFlightCreate = disposeContainer
          .read(workspaceActionsProvider.notifier)
          .createWorkspace('Disposed Target', locale: englishLocale);
      expect(disposeContainer.read(workspaceActionsProvider).isBusy, isTrue);

      disposeContainer.dispose();
      disposeGate.complete();

      expect(
        await inFlightCreate,
        equals(
          ActionPersistFailed(
            message: englishLocalizations.errorSettingsSaveFailed,
          ),
        ),
        reason: 'Mid-flight disposal must not throw UnmountedRefException',
      );
    });

    test('rejects duplicate .tdf path, rename collisions, missing workspace IDs, and logs ui.workspace_action_failed', () async {
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.info,
        persistToDisk: false,
      );
      final container = createWorkspaceContainer();
      addTearDown(container.dispose);
      await primeWorkspaceProviders(container);

      final actions = container.read(workspaceActionsProvider.notifier);
      expect(
        await actions.createWorkspace('My Work', activate: false),
        isA<ActionSucceeded>(),
      );
      expect(
        await actions.createWorkspace('My-Work', locale: englishLocale),
        equals(
          ActionValidationFailed(
            message: englishLocalizations.errorDuplicateWorkspaceFilePath,
          ),
        ),
      );
      expect(
        await actions.renameWorkspace(
          'my_work',
          'tasks',
          locale: englishLocale,
        ),
        equals(
          ActionValidationFailed(
            message: englishLocalizations.errorWorkspaceNameDuplicate,
          ),
        ),
      );
      expect(
        await actions.renameWorkspace('my_work', '   ', locale: englishLocale),
        equals(
          ActionValidationFailed(
            message: englishLocalizations.errorWorkspaceNameEmpty,
          ),
        ),
      );
      expect(
        await actions.switchWorkspace('missing_id'),
        isA<ActionValidationFailed>(),
      );
      expect(
        await actions.renameWorkspace('missing_id', 'Valid Name'),
        isA<ActionValidationFailed>(),
      );
      expect(
        await actions.deleteWorkspace('missing_id'),
        isA<ActionValidationFailed>(),
      );

      final logText = AppLogger.fullLogText;
      expect(
        logText,
        contains(
          'ui.workspace_action_failed | operation=create kind=duplicateFilePath',
        ),
      );
      expect(
        logText,
        contains(
          'ui.workspace_action_failed | operation=rename kind=duplicateName',
        ),
      );
    });
  });

  group('SyncActionsNotifier & EntityActionsNotifier transient AsyncLoading and diagnostic logs', () {
    test('SyncActionsNotifier ignores transient AsyncLoading while busy and logs exact sync and location events', () async {
      AppLogger.setEnabled(
        true,
        minimumLevel: LogLevel.info,
        persistToDisk: false,
      );
      final syncCompleter = Completer<void>();
      final workspaceNotifier = _ControllableWorkspaceNotifier();
      var shouldFailResolve = false;
      final spyNotifier = _SpyTaskNotifier(
        board: createSampleBoard(),
        onSyncFromRemote: () => syncCompleter.future,
        onResolveDeletionConflicts:
            ({
              required taskResolutions,
              required labelResolutions,
              required locationResolutions,
            }) async {
              if (shouldFailResolve) {
                throw const LocalFileException('Conflict write failed');
              }
              return createSampleBoard();
            },
        onResolveRecovery:
            ({
              required taskResolutions,
              required labelResolutions,
              required locationResolutions,
            }) async {
              if (shouldFailResolve) {
                throw const LocalFileException('Recovery write failed');
              }
              return createSampleBoard();
            },
      );
      final locationNotifier = _ControlledLocationNotifier(
        const LocationState.unavailable(),
        onRefresh: (_) =>
            Future<void>.error(const LocalFileException('Sensor unavailable')),
      );
      final container = createSyncContainer(
        localeOverride: englishLocale,
        taskNotifier: spyNotifier,
        locationNotifier: locationNotifier,
        workspaceNotifier: workspaceNotifier,
      );
      addTearDown(container.dispose);
      final initialWorkspace = await container.read(
        activeWorkspaceProvider.future,
      );
      await container.read(taskNotifierProvider.future);

      final syncActions = container.read(syncActionsProvider.notifier);
      final inFlightSync = syncActions.syncNow();
      expect(container.read(syncActionsProvider).isBusy, isTrue);

      workspaceNotifier.emitTransientLoading();
      expect(
        container.read(syncActionsProvider).isBusy,
        isTrue,
        reason: 'Transient AsyncLoading must not clear SyncActionsState.isBusy',
      );
      workspaceNotifier.emitWorkspace(initialWorkspace);
      expect(container.read(syncActionsProvider).isBusy, isTrue);

      syncCompleter.completeError(const LocalFileException('Sync failed'));
      expect(await inFlightSync, isA<ActionPersistFailed>());
      expect(container.read(syncActionsProvider).isBusy, isFalse);

      expect(
        await syncActions.applyDeletionConflictResolutions(
          taskDecisions: const <String, TdfDeletionResolution>{
            'task000001': TdfDeletionResolution.undelete,
          },
          labelDecisions: const <String, TdfDeletionResolution>{},
          locationDecisions: const <String, TdfDeletionResolution>{},
        ),
        isA<ActionSucceeded>(),
      );
      expect(
        await syncActions.applyRecoveryResolutions(
          taskDecisions: const <String, TdfRecoveryResolution>{
            'task000001': TdfRecoveryResolution.recoverAsNew,
          },
          labelDecisions: const <String, TdfRecoveryResolution>{},
          locationDecisions: const <String, TdfRecoveryResolution>{},
        ),
        isA<ActionSucceeded>(),
      );

      shouldFailResolve = true;
      expect(
        await syncActions.applyDeletionConflictResolutions(
          taskDecisions: const <String, TdfDeletionResolution>{},
          labelDecisions: const <String, TdfDeletionResolution>{},
          locationDecisions: const <String, TdfDeletionResolution>{},
        ),
        isA<ActionPersistFailed>(),
      );
      expect(
        await syncActions.applyRecoveryResolutions(
          taskDecisions: const <String, TdfRecoveryResolution>{},
          labelDecisions: const <String, TdfRecoveryResolution>{},
          locationDecisions: const <String, TdfRecoveryResolution>{},
        ),
        isA<ActionPersistFailed>(),
      );
      expect(await syncActions.refreshLocation(), isA<ActionPersistFailed>());

      final logText = AppLogger.fullLogText;
      expect(logText, contains('sync.sync_now_failed'));
      expect(
        logText,
        contains('sync.conflict_resolved | tasks=1 labels=0 locations=0'),
      );
      expect(logText, contains('sync.conflict_resolve_failed'));
      expect(
        logText,
        contains('sync.recovery_resolved | tasks=1 labels=0 locations=0'),
      );
      expect(logText, contains('sync.recovery_resolve_failed'));
      expect(logText, contains('ui.location.refresh_failed'));
    });

    test('EntityActionsNotifier guards overlapping location lookups and rejects unpaired surrogates', () async {
      final harness = createEntityHarness();
      addTearDown(harness.container.dispose);
      await harness.container.read(taskNotifierProvider.future);
      final actions = harness.container.read(entityActionsProvider.notifier);

      final surrogateResult = await actions.resolveLocationSource(
        sourceType: LocationSourceType.plusCode,
        rawSource: '9F4MG9X5+\uD800XX',
      );
      expect(surrogateResult, isA<LocationSourceResolutionError>());
      expect(
        (surrogateResult as LocationSourceResolutionError).localizedMessage,
        equals(englishLocalizations.locationResolveErrorInvalidPlusCode),
      );

      final completer = Completer<List<GeocodingCandidate>>();
      harness.locationRepository.nextSearchCompleter = completer;

      final firstLookup = actions.resolveLocationSource(
        sourceType: LocationSourceType.address,
        rawSource: 'Berlin',
      );
      expect(
        harness.container.read(entityActionsProvider).isResolvingLocation,
        isTrue,
      );

      final overlappingSource = await actions.resolveLocationSource(
        sourceType: LocationSourceType.address,
        rawSource: 'Hamburg',
      );
      expect(overlappingSource, isA<LocationSourceResolutionError>());
      expect(await actions.resolveCurrentGpsPosition(), isNull);

      completer.complete(const <GeocodingCandidate>[
        GeocodingCandidate(
          displayName: 'Berlin, Germany',
          latitude: 52.52,
          longitude: 13.405,
        ),
      ]);
      expect(await firstLookup, isA<LocationSourceResolved>());
      expect(
        harness.container.read(entityActionsProvider).isResolvingLocation,
        isFalse,
      );
    });

    test('EntityActionsNotifier and SyncActionsNotifier reject ABA workspace-switch stale completions and return clear busy messages', () async {
      const workspaceAConfig = WebDavConfig(
        language: AppLanguage.english,
        localFilePath: 'alpha.tdf',
        filePath: 'alpha.tdf',
      );
      const workspaceB = AppWorkspace(
        id: 'workspace_b',
        name: 'Workspace B',
        config: WebDavConfig(
          language: AppLanguage.english,
          localFilePath: 'beta.tdf',
          filePath: 'beta.tdf',
        ),
      );
      final workspaceNotifier = _ControllableWorkspaceNotifier();
      final blockingTask = _BlockingTaskNotifier(TaskBoard.empty());
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(workspaceAConfig),
          ),
          activeWorkspaceProvider.overrideWith(() => workspaceNotifier),
          taskNotifierProvider.overrideWith(() => blockingTask),
          appLocaleProvider.overrideWithValue(englishLocale),
          clockProvider.overrideWithValue(() => fixedNow),
        ],
      );
      addTearDown(container.dispose);

      final workspaceA = await container.read(activeWorkspaceProvider.future);
      await container.read(taskNotifierProvider.future);
      final entitySub = container.listen(entityActionsProvider, (_, _) {});
      addTearDown(entitySub.close);
      final noticeSub = container.listen(floatingNoticeProvider, (_, _) {});
      addTearDown(noticeSub.close);

      // Busy rejection in EntityActionsNotifier must report syncStatusSyncing, not unreadable file error.
      final firstGate = Completer<void>();
      blockingTask.nextMutationCompleter = firstGate;
      final entityActions = container.read(entityActionsProvider.notifier);
      final pendingCreate = entityActions.quickCreateLabel('First');
      final busyResult = await entityActions.quickCreateLabel('Second');
      expect(busyResult, isA<ActionPersistFailed>());
      expect(
        (busyResult as ActionPersistFailed).message,
        equals(englishLocalizations.syncStatusSyncing),
        reason: 'EntityActionsNotifier busy guard must return syncStatusSyncing instead of unreadable local file error',
      );

      // Perform an ABA workspace switch (A -> B -> A) while pendingCreate is suspended!
      workspaceNotifier.emitWorkspace(workspaceB);
      expect(container.read(entityActionsProvider).isBusy, isFalse);
      workspaceNotifier.emitWorkspace(workspaceA);

      // Start a fresh operation in the new Workspace A session so isBusy is true again.
      final secondGate = Completer<void>();
      blockingTask.nextMutationCompleter = secondGate;
      final newSessionCreate = entityActions.quickCreateLabel('Fresh');
      expect(container.read(entityActionsProvider).isBusy, isTrue);

      // Complete the stale first session's operation: ABA guard must NOT clear the new session's isBusy or emit stale notices!
      firstGate.complete();
      await pendingCreate;
      expect(
        container.read(entityActionsProvider).isBusy,
        isTrue,
        reason: 'Stale operation from pre-ABA workspace A must NOT clear isBusy of the new workspace A session',
      );
      expect(
        container.read(floatingNoticeProvider),
        isNull,
        reason: 'Stale operation from pre-ABA workspace A must NOT emit a floating notice into the new session',
      );

      secondGate.complete();
      await newSessionCreate;
      expect(container.read(entityActionsProvider).isBusy, isFalse);

      // SyncActionsNotifier must also reject ABA workspace-switch (A -> B -> A) stale completions.
      final syncGate1 = Completer<void>();
      final syncGate2 = Completer<void>();
      var syncCallCount = 0;
      final syncWorkspaceNotifier = _ControllableWorkspaceNotifier();
      final spySyncTask = _SpyTaskNotifier(
        onSyncFromRemote: () {
          syncCallCount++;
          return syncCallCount == 1 ? syncGate1.future : syncGate2.future;
        },
      );
      final syncContainer = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(workspaceAConfig),
          ),
          activeWorkspaceProvider.overrideWith(() => syncWorkspaceNotifier),
          taskNotifierProvider.overrideWith(() => spySyncTask),
          appLocaleProvider.overrideWithValue(englishLocale),
          clockProvider.overrideWithValue(() => fixedNow),
        ],
      );
      addTearDown(syncContainer.dispose);
      final syncWorkspaceA = await syncContainer.read(
        activeWorkspaceProvider.future,
      );
      await syncContainer.read(taskNotifierProvider.future);
      final syncSub = syncContainer.listen(syncActionsProvider, (_, _) {});
      addTearDown(syncSub.close);

      final syncActions = syncContainer.read(syncActionsProvider.notifier);
      final staleSync = syncActions.syncNow(locale: englishLocale);
      expect(syncContainer.read(syncActionsProvider).isBusy, isTrue);

      // Switch A -> B -> A while staleSync is suspended, then start a fresh sync in the new A session.
      syncWorkspaceNotifier.emitWorkspace(workspaceB);
      expect(syncContainer.read(syncActionsProvider).isBusy, isFalse);
      syncWorkspaceNotifier.emitWorkspace(syncWorkspaceA);

      final freshSync = syncActions.syncNow(locale: englishLocale);
      expect(syncContainer.read(syncActionsProvider).isBusy, isTrue);

      syncGate1.complete();
      await staleSync;
      expect(
        syncContainer.read(syncActionsProvider).isBusy,
        isTrue,
        reason: 'Stale SyncActionsNotifier completion after A -> B -> A must not clear new session isBusy',
      );
      syncGate2.complete();
      await freshSync;
      expect(syncContainer.read(syncActionsProvider).isBusy, isFalse);

      // WorkspaceActionsNotifier busy rejection must return a non-empty localized syncStatusSyncing message.
      final wsRepo = _ControlledSettingsRepository(workspaceAConfig);
      await wsRepo.createWorkspace(
        'Work',
        id: 'work',
        config: const WebDavConfig(
          localFilePath: 'work.tdf',
          filePath: 'work.tdf',
        ),
      );
      final wsContainer = createWorkspaceContainer(settingsRepository: wsRepo);
      addTearDown(wsContainer.dispose);
      await primeWorkspaceProviders(wsContainer);
      final switchGate = Completer<void>();
      wsRepo.activateGate = switchGate;
      final wsActions = wsContainer.read(workspaceActionsProvider.notifier);
      final pendingSwitch = wsActions.switchWorkspace(
        'work',
        locale: englishLocale,
      );
      final wsBusy = await wsActions.renameWorkspace(
        'work',
        'Renamed',
        locale: englishLocale,
      );
      expect(wsBusy, isA<ActionValidationFailed>());
      expect(
        (wsBusy as ActionValidationFailed).message,
        equals(englishLocalizations.syncStatusSyncing),
        reason: 'WorkspaceActionsNotifier busy guard must return localized syncStatusSyncing instead of empty message',
      );
      switchGate.complete();
      await pendingSwitch;
    });
  });
}
