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

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/app_workspace.dart';
import '../models/task_board.dart';
import '../models/task_board_sync.dart';
import '../models/task_item.dart';
import '../models/tdf_error.dart';
import '../models/tdf_location.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_payload_comparison.dart';
import '../models/tdf_sync_metadata.dart';
import '../models/tdf_timezone.dart';
import '../models/webdav_config.dart';
import '../models/workspace_sync_state.dart';
import '../repositories/local_file_repository.dart';
import '../repositories/webdav_repository.dart';
import '../services/app_logger.dart';
import '../services/sha256_service.dart';
import 'config_providers.dart';
import 'workspace_providers.dart';

/// Provides the current [SyncState] for local and WebDAV persistence operations.
final syncStateProvider = NotifierProvider<SyncStateNotifier, SyncState>(
  SyncStateNotifier.new,
);

/// Represents the current synchronization state for local and WebDAV storage.
@immutable
class SyncState {
  /// Creates a [SyncState] snapshot.
  const SyncState({
    this.isSyncing = false,
    this.lastSyncedAt,
    this.errorMessage,
    this.hasOpenConflict = false,
  });

  /// Optional error message from the most recent synchronization attempt.
  final String? errorMessage;

  /// Whether an unresolved `TdfSyncOutcomeException` synchronization conflict is active.
  final bool hasOpenConflict;

  /// Whether a synchronization request is currently in flight.
  final bool isSyncing;

  /// Timestamp of the last successful synchronization.
  final DateTime? lastSyncedAt;

  /// Returns a copy of this [SyncState] with updated fields.
  SyncState copyWith({
    bool? isSyncing,
    DateTime? lastSyncedAt,
    String? errorMessage,
    bool clearError = false,
    bool? hasOpenConflict,
  }) => SyncState(
    isSyncing: isSyncing ?? this.isSyncing,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    hasOpenConflict:
        hasOpenConflict ?? (clearError ? false : this.hasOpenConflict),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncState &&
          other.isSyncing == isSyncing &&
          other.lastSyncedAt == lastSyncedAt &&
          other.errorMessage == errorMessage &&
          other.hasOpenConflict == hasOpenConflict);

  @override
  int get hashCode =>
      Object.hash(isSyncing, lastSyncedAt, errorMessage, hasOpenConflict);
}

/// Manages [SyncState] updates during local and WebDAV load and save operations.
class SyncStateNotifier extends Notifier<SyncState> {
  @override
  SyncState build() {
    ref.watch(
      activeWorkspaceProvider.select((workspace) => workspace.asData?.value.id),
    );
    return const SyncState();
  }

  /// Clears any active synchronization error banner.
  void clearError() =>
      state = state.copyWith(clearError: true, hasOpenConflict: false);

  /// Records an unresolved synchronization conflict with [message].
  void setConflict(String message) => state = state.copyWith(
    isSyncing: false,
    errorMessage: message,
    hasOpenConflict: true,
  );

  /// Records a synchronization failure with [message].
  void setError(String message) => state = state.copyWith(
    isSyncing: false,
    errorMessage: message,
    hasOpenConflict: false,
  );

  /// Records a successful synchronization at [timestamp].
  void setSuccess(DateTime timestamp) =>
      state = SyncState(isSyncing: false, lastSyncedAt: timestamp);

  /// Marks synchronization as in progress and clears previous errors.
  void setSyncing() => state = state.copyWith(
    isSyncing: true,
    clearError: true,
    hasOpenConflict: false,
  );
}

/// Stateless multi-stage local and WebDAV `tdf 0.8.0` synchronization pipeline.
@immutable
class TaskSyncPipeline {
  /// Prevents instantiation of this stateless helper class.
  const TaskSyncPipeline._();

  /// Maximum number of compare-and-swap (CAS) merge retries before aborting local publication (`3`).
  static const int maxCasRetries = 3;

  /// Flushes [board] to the local `.tdf` file of [workspace] before unloading when local persistence is enabled.
  static Future<void> flushOutgoingLocalBoard(
    Ref ref,
    AppWorkspace workspace,
    TaskBoard board,
  ) async {
    final config = workspace.config;
    if (!config.storageMode.usesLocal || !config.isLocalConfigured) return;
    try {
      final (utcNow, localNow) = resolveTimestamps(ref, null);
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final syncState = await settingsRepo.loadWorkspaceSyncState(workspace.id);
      final baseline = _tryParseBaseline(
        ref,
        config,
        syncState.lastSyncedLocalTdf,
        utcNow,
        localNow,
      );
      final isAuthoritative = !config.storageMode.usesWebDav;
      final published = await _publishLocalWithCasLoop(
        ref,
        config,
        initialDigest: syncState.localSourceDigest,
        initialBaseline: baseline,
        initialAckGeneration: baseline != null
            ? syncState.acknowledgedLocalGeneration
            : null,
        initialCanonicalDiskTdf: syncState.lastSyncedLocalTdf,
        preTransactionGeneration: board.deletedBlock.generation,
        candidateBoard: board,
        resolutions: _SyncResolutions.empty,
        requireTargets: true,
        skipWriteIfUnchanged: false,
        cleanupMode: isAuthoritative
            ? TdfCleanupMode.finalStage
            : TdfCleanupMode.deferred,
        isAuthoritativeSource: isAuthoritative,
        utcNow: utcNow,
        localNow: localNow,
      );
      await settingsRepo.saveWorkspaceSyncState(
        workspace.id,
        syncState.copyWith(
          lastSyncedLocalTdf: published.serialized,
          acknowledgedLocalGeneration: published.board.deletedBlock.generation,
          localSourceDigest: published.digest,
        ),
      );
    } on Object catch (error) {
      AppLogger.warn(
        LogTag.sync,
        'Failed to flush outgoing local board for workspace ${workspace.id}: $error',
      );
    }
  }

  /// Formats a localized user-facing status banner message for [error].
  static String formatSyncOutcomeBanner(
    Ref ref,
    TdfSyncOutcomeException error,
  ) {
    final localizations = lookupAppLocalizations(ref.read(appLocaleProvider));
    return switch (error.kind) {
      TdfSyncOutcomeKind.deletionConflict =>
        localizations.syncConflictDeletionBanner,
      TdfSyncOutcomeKind.recoveryRequired =>
        localizations.syncConflictRecoveryBanner,
      TdfSyncOutcomeKind.syncGenerationRollback =>
        localizations.syncErrorGenerationRollbackBanner,
    };
  }

  /// Emits a structured `sync.conflict` or `sync.recovery` diagnostic event for [error] without sensitive content.
  static void logSyncOutcomeEvent(
    TdfSyncOutcomeException error,
    StorageMode mode,
  ) {
    if (!AppLogger.shouldLog(LogLevel.warn)) {
      return;
    }
    switch (error.kind) {
      case TdfSyncOutcomeKind.deletionConflict:
        AppLogger.event(
          LogLevel.warn,
          LogTag.sync,
          'sync.conflict',
          fields: <String, Object?>{
            'kind': error.kind.name,
            'mode': mode.name,
            'tasks': error.conflictedTaskIds.length,
            'labels': error.conflictedLabelIds.length,
            'locations': error.conflictedLocationIds.length,
          },
        );
      case TdfSyncOutcomeKind.recoveryRequired:
      case TdfSyncOutcomeKind.syncGenerationRollback:
        AppLogger.event(
          LogLevel.warn,
          LogTag.sync,
          'sync.recovery',
          fields: <String, Object?>{
            'kind': error.kind.name,
            'mode': mode.name,
            'tasks': error.ambiguousTaskIds.length,
            'labels': error.ambiguousLabelIds.length,
            'locations': error.ambiguousLocationIds.length,
          },
        );
    }
  }

  /// Resets the local file synchronization baseline while preserving the remote WebDAV baseline for [workspaceId].
  static Future<void> resetLocalSyncBaseline(
    Ref ref,
    String workspaceId,
  ) async {
    final settingsRepository = ref.read(settingsRepositoryProvider);
    final current = await settingsRepository.loadWorkspaceSyncState(
      workspaceId,
    );
    await settingsRepository.saveWorkspaceSyncState(
      workspaceId,
      current.copyWith(
        clearLastSyncedLocalTdf: true,
        clearAcknowledgedLocalGeneration: true,
        clearLocalSourceDigest: true,
      ),
    );
  }

  /// Resolves the normalized UTC timestamp and configured local wall-clock timestamp.
  static (DateTime utcNow, DateTime localNow) resolveTimestamps(
    Ref ref,
    DateTime? currentDate,
  ) {
    final rawClock = currentDate ?? ref.read(clockProvider)();
    final utcNow = TaskItem.normalizeTimestamp(rawClock.toUtc());
    return (utcNow, readCurrentConfig(ref).toLocalWallClock(utcNow));
  }

  /// Resolves the active [TdfTimeZoneContext] for [config] (`TDF-CTX-001`).
  static TdfTimeZoneContext resolveWorkspaceTimeZone(
    WebDavConfig config, [
    DateTime? utcNow,
  ]) => config.resolveTimeZoneContext();

  /// Wraps [synchronize] with [SyncStateNotifier] status updates.
  static Future<TaskBoard> runSyncWithStatus(
    Ref ref,
    WebDavConfig config, {
    Map<String, TdfDeletionResolution> taskConflictResolutions = const {},
    Map<String, TdfDeletionResolution> labelConflictResolutions = const {},
    Map<String, TdfDeletionResolution> locationConflictResolutions = const {},
    Map<String, TdfBoundDeletionDecision> boundTaskConflictDecisions = const {},
    Map<String, TdfBoundDeletionDecision> boundLabelConflictDecisions =
        const {},
    Map<String, TdfBoundDeletionDecision> boundLocationConflictDecisions =
        const {},
    Map<String, TdfRecoveryResolution> taskRecoveryResolutions = const {},
    Map<String, TdfRecoveryResolution> labelRecoveryResolutions = const {},
    Map<String, TdfRecoveryResolution> locationRecoveryResolutions = const {},
    TaskBoard? candidateBoard,
    TaskBoard? candidateOriginBoard,
    bool isInitialLoad = false,
    bool requireTargets = false,
    void Function(TaskBoard mergedBoard)? onLocalStageMerged,
  }) async {
    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      final board = await synchronize(
        ref,
        config,
        taskConflictResolutions: taskConflictResolutions,
        labelConflictResolutions: labelConflictResolutions,
        locationConflictResolutions: locationConflictResolutions,
        boundTaskConflictDecisions: boundTaskConflictDecisions,
        boundLabelConflictDecisions: boundLabelConflictDecisions,
        boundLocationConflictDecisions: boundLocationConflictDecisions,
        taskRecoveryResolutions: taskRecoveryResolutions,
        labelRecoveryResolutions: labelRecoveryResolutions,
        locationRecoveryResolutions: locationRecoveryResolutions,
        candidateBoard: candidateBoard,
        candidateOriginBoard: candidateOriginBoard,
        isInitialLoad: isInitialLoad,
        requireTargets: requireTargets,
        onLocalStageMerged: onLocalStageMerged,
      );
      if (!ref.mounted) {
        return board;
      }
      ref
          .read(syncStateProvider.notifier)
          .setSuccess(ref.read(clockProvider)().toUtc());
      return board;
    } on TdfSyncOutcomeException catch (error) {
      logSyncOutcomeEvent(error, config.storageMode);
      if (ref.mounted) {
        ref
            .read(syncStateProvider.notifier)
            .setConflict(formatSyncOutcomeBanner(ref, error));
      }
      rethrow;
    } on Object catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.sync,
        'sync.error',
        fields: <String, Object?>{'mode': config.storageMode.name},
        error: error,
      );
      if (ref.mounted) {
        ref.read(syncStateProvider.notifier).setError(error.toString());
      }
      rethrow;
    }
  }

  /// Executes the multi-stage merge pipeline (`In-Memory <-> Local File <-> WebDAV`).
  static Future<TaskBoard> synchronize(
    Ref ref,
    WebDavConfig config, {
    Map<String, TdfDeletionResolution> taskConflictResolutions = const {},
    Map<String, TdfDeletionResolution> labelConflictResolutions = const {},
    Map<String, TdfDeletionResolution> locationConflictResolutions = const {},
    Map<String, TdfBoundDeletionDecision> boundTaskConflictDecisions = const {},
    Map<String, TdfBoundDeletionDecision> boundLabelConflictDecisions =
        const {},
    Map<String, TdfBoundDeletionDecision> boundLocationConflictDecisions =
        const {},
    Map<String, TdfRecoveryResolution> taskRecoveryResolutions = const {},
    Map<String, TdfRecoveryResolution> labelRecoveryResolutions = const {},
    Map<String, TdfRecoveryResolution> locationRecoveryResolutions = const {},
    TaskBoard? candidateBoard,
    TaskBoard? candidateOriginBoard,
    bool isInitialLoad = false,
    bool requireTargets = false,
    void Function(TaskBoard mergedBoard)? onLocalStageMerged,
  }) async {
    final (utcNow, localNow) = resolveTimestamps(ref, null);
    final workspace = await ref.read(activeWorkspaceProvider.future);
    if (!ref.mounted) {
      return candidateBoard ?? TaskBoard.empty();
    }
    AppLogger.event(
      LogLevel.info,
      LogTag.sync,
      'sync.start',
      fields: <String, Object?>{
        'workspace': workspace.id,
        'mode': config.storageMode.name,
        'initial': isInitialLoad,
      },
    );
    final settingsRepository = ref.read(settingsRepositoryProvider);
    var syncState = await settingsRepository.loadWorkspaceSyncState(
      workspace.id,
    );
    if (!ref.mounted) {
      return candidateBoard ?? TaskBoard.empty();
    }
    final hadLocalBaseline =
        !config.storageMode.usesLocal || syncState.lastSyncedLocalTdf != null;
    final hadPriorLocalConvergence =
        !config.storageMode.usesLocal ||
        (syncState.lastSyncedLocalTdf != null &&
            syncState.lastSyncedLocalTdf?.trim() ==
                (syncState.lastSyncedRemoteTdf ?? '').trim());
    final resolutions = _SyncResolutions(
      taskConflicts: taskConflictResolutions,
      labelConflicts: labelConflictResolutions,
      locationConflicts: locationConflictResolutions,
      boundTaskDecisions: boundTaskConflictDecisions,
      boundLabelDecisions: boundLabelConflictDecisions,
      boundLocationDecisions: boundLocationConflictDecisions,
      taskRecoveries: taskRecoveryResolutions,
      labelRecoveries: labelRecoveryResolutions,
      locationRecoveries: locationRecoveryResolutions,
    );

    var hasWorking = candidateBoard != null && !isInitialLoad;
    var working = candidateBoard ?? TaskBoard.empty();
    final hasCandidate = candidateBoard != null;
    final willRunRemoteStage =
        config.storageMode.usesWebDav &&
        (requireTargets || config.isWebDavConfigured);
    final timeZone = resolveWorkspaceTimeZone(config, utcNow);

    if (config.storageMode.usesLocal &&
        (requireTargets || config.isLocalConfigured)) {
      final localCleanupMode = willRunRemoteStage
          ? TdfCleanupMode.deferred
          : TdfCleanupMode.finalStage;
      (working, hasWorking, syncState) = await _synchronizeLocalStage(
        ref,
        config,
        workspaceId: workspace.id,
        working: working,
        candidateOriginBoard: candidateOriginBoard,
        hasWorking: hasWorking,
        hasCandidate: hasCandidate,
        requireTargets: requireTargets,
        cleanupMode: localCleanupMode,
        isAuthoritativeSource: !willRunRemoteStage,
        syncState: syncState,
        resolutions: resolutions,
        utcNow: utcNow,
        localNow: localNow,
        timeZone: timeZone,
        onLocalStageMerged: onLocalStageMerged,
      );
      if (!ref.mounted) {
        return working;
      }
      AppLogger.event(
        LogLevel.info,
        LogTag.sync,
        'sync.stage',
        fields: <String, Object?>{
          'stage': 'local',
          'cleanup': localCleanupMode.name,
          'workspace': workspace.id,
          'generation': working.deletedBlock.generation,
          'tasks': working.allTasks.length,
          'labels': working.labels.length,
          'locations': working.locations.length,
        },
      );
    }

    if (willRunRemoteStage) {
      (working, hasWorking, syncState) = await _synchronizeRemoteStage(
        ref,
        config,
        workspaceId: workspace.id,
        working: working,
        candidateOriginBoard: !config.storageMode.usesLocal
            ? candidateOriginBoard
            : null,
        hasWorking: hasWorking,
        hasCandidate: hasCandidate,
        hadLocalBaseline: hadLocalBaseline,
        hadPriorLocalConvergence: hadPriorLocalConvergence,
        requireTargets: requireTargets,
        syncState: syncState,
        resolutions: resolutions,
        utcNow: utcNow,
        localNow: localNow,
        timeZone: timeZone,
      );
      if (!ref.mounted) {
        return working;
      }
      AppLogger.event(
        LogLevel.info,
        LogTag.sync,
        'sync.stage',
        fields: <String, Object?>{
          'stage': 'remote',
          'cleanup': TdfCleanupMode.finalStage.name,
          'workspace': workspace.id,
          'generation': working.deletedBlock.generation,
          'tasks': working.allTasks.length,
          'labels': working.labels.length,
          'locations': working.locations.length,
        },
      );
    }

    if (!hasWorking) {
      working = TaskBoardSync.stampAndNormalize(
        working,
        evaluationTime: utcNow,
        localEvaluationTime: localNow,
        timeZone: timeZone,
        dueLeadWindow: config.dueLeadWindow.duration,
      );
    }

    await settingsRepository.saveWorkspaceSyncState(workspace.id, syncState);
    AppLogger.event(
      LogLevel.info,
      LogTag.sync,
      'sync.complete',
      fields: <String, Object?>{
        'workspace': workspace.id,
        'tasks': working.allTasks.length,
        'labels': working.labels.length,
        'locations': working.locations.length,
      },
    );
    return working;
  }

  /// Checks whether the remote WebDAV `.tdf` file fails with [TdfErrorKind.unsupportedVersion] without mutating storage.
  static Future<TdfException?> _checkRemoteUnsupportedVersion(
    Ref ref,
    WebDavConfig config,
    DateTime utcNow,
    DateTime localNow,
  ) async {
    try {
      final rawRemote = await ref.read(webDavRepositoryProvider).fetchTdf();
      if (rawRemote.trim().isNotEmpty) {
        _parseTdf(ref, config, rawRemote, utcNow, localNow);
      }
      return null;
    } on TdfException catch (error) {
      return error.kind == TdfErrorKind.unsupportedVersion ? error : null;
    } on Object {
      return null;
    }
  }

  /// Writes the converged [candidateBoard] back to local storage after the remote WebDAV stage using the CAS-merge loop.
  static Future<(TaskBoard, WorkspaceSyncState)> _convergeLocalAfterRemoteStage(
    Ref ref,
    WebDavConfig config, {
    required WorkspaceSyncState syncState,
    required TaskBoard candidateBoard,
    required _SyncResolutions resolutions,
    required bool requireTargets,
    required DateTime utcNow,
    required DateTime localNow,
  }) async {
    final baseline = _tryParseBaseline(
      ref,
      config,
      syncState.lastSyncedLocalTdf,
      utcNow,
      localNow,
    );
    final published = await _publishLocalWithCasLoop(
      ref,
      config,
      initialDigest: syncState.localSourceDigest,
      initialBaseline: baseline,
      initialAckGeneration: baseline != null
          ? syncState.acknowledgedLocalGeneration
          : null,
      initialCanonicalDiskTdf: syncState.lastSyncedLocalTdf,
      preTransactionGeneration: candidateBoard.deletedBlock.generation,
      candidateBoard: candidateBoard,
      resolutions: resolutions,
      requireTargets: requireTargets,
      skipWriteIfUnchanged: !requireTargets,
      cleanupMode: TdfCleanupMode.finalStage,
      isAuthoritativeSource: false,
      utcNow: utcNow,
      localNow: localNow,
    );
    final updatedSyncState = syncState.copyWith(
      lastSyncedLocalTdf: published.serialized,
      acknowledgedLocalGeneration: published.board.deletedBlock.generation,
      localSourceDigest: published.digest,
    );
    return (published.board, updatedSyncState);
  }

  /// Builds and logs a localized [UnsupportedTdfVersionException] for [localError] and/or [remoteError].
  static UnsupportedTdfVersionException _createUnsupportedVersionException({
    required WebDavConfig config,
    TdfException? localError,
    TdfException? remoteError,
  }) {
    final locale = config.language.resolveLocale(
      PlatformDispatcher.instance.locale,
    );
    final localizations = lookupAppLocalizations(locale);
    final localVersion = localError?.sourceVersion;
    final remoteVersion = remoteError?.sourceVersion;
    final String versionLabel;
    final String message;
    if (localError != null && remoteError != null) {
      versionLabel =
          (localVersion != null &&
              remoteVersion != null &&
              localVersion != remoteVersion)
          ? '$localVersion / $remoteVersion'
          : (localVersion ?? remoteVersion ?? '?');
      message = localizations.errorUnsupportedTdfVersionBoth(versionLabel);
    } else if (localError != null) {
      versionLabel = localVersion ?? '?';
      message = localizations.errorUnsupportedTdfVersionLocal(versionLabel);
    } else {
      versionLabel = remoteVersion ?? '?';
      message = localizations.errorUnsupportedTdfVersionRemote(versionLabel);
    }
    AppLogger.error(
      LogTag.sync,
      'Unsupported TDF version detected (local=$localVersion, remote=$remoteVersion): $message',
    );
    return UnsupportedTdfVersionException(
      message,
      version: versionLabel,
      cause: localError ?? remoteError,
    );
  }

  /// Returns `true` when [storedBaseline] diverged from [originTasks], [originLabels], or [originLocations] via additions, deletions, or payload/timestamp edits.
  static bool _didBaselineAdvancePastOrigin(
    TaskBoard storedBaseline,
    Map<String, TaskItem> originTasks,
    Map<String, TdfLabel> originLabels,
    Map<String, TdfLocation> originLocations,
    DateTime utcNow,
  ) =>
      _didBaselineTasksAdvance(storedBaseline, originTasks, utcNow) ||
      _didBaselineLabelsAdvance(storedBaseline, originLabels) ||
      _didBaselineLocationsAdvance(storedBaseline, originLocations);

  /// Returns `true` when [storedBaseline] added, deleted, or modified any label relative to [originLabels].
  static bool _didBaselineLabelsAdvance(
    TaskBoard storedBaseline,
    Map<String, TdfLabel> originLabels,
  ) {
    final storedIds = <String>{};
    for (final label in storedBaseline.labels) {
      storedIds.add(label.id);
      final origin = originLabels[label.id];
      if (origin == null ||
          origin.effectiveModifiedAt != label.effectiveModifiedAt ||
          TdfPayloadComparison.compareLabelPayloads(origin, label) != 0) {
        return true;
      }
    }
    for (final id in originLabels.keys) {
      if (!storedIds.contains(id) &&
          storedBaseline.deletedBlock.findLabelRecord(id) != null) {
        return true;
      }
    }
    return false;
  }

  /// Returns `true` when [storedBaseline] added, deleted, or modified any location relative to [originLocations].
  static bool _didBaselineLocationsAdvance(
    TaskBoard storedBaseline,
    Map<String, TdfLocation> originLocations,
  ) {
    final storedIds = <String>{};
    for (final location in storedBaseline.locations) {
      storedIds.add(location.id);
      final origin = originLocations[location.id];
      if (origin == null ||
          origin.effectiveModifiedAt != location.effectiveModifiedAt ||
          TdfPayloadComparison.compareLocationPayloads(origin, location) != 0) {
        return true;
      }
    }
    for (final id in originLocations.keys) {
      if (!storedIds.contains(id) &&
          storedBaseline.deletedBlock.findLocationRecord(id) != null) {
        return true;
      }
    }
    return false;
  }

  /// Returns `true` when [storedBaseline] added, deleted, or modified any task (modulo automatic open-task block cleanup at [utcNow]) relative to [originTasks].
  static bool _didBaselineTasksAdvance(
    TaskBoard storedBaseline,
    Map<String, TaskItem> originTasks,
    DateTime utcNow,
  ) {
    final storedTasksById = <String, TaskItem>{
      for (final item in storedBaseline.allTasks) item.id: item,
    };
    final storedDeletedTaskIds = <String>{
      for (final record in storedBaseline.deletedBlock.tasks) record.taskId,
    };
    for (final item in storedBaseline.allTasks) {
      final origin = originTasks[item.id];
      if (origin == null ||
          !_isTaskUnchangedModuloBlockCleanup(
            originTask: origin,
            candidateTask: item,
            liveTasksById: storedTasksById,
            deletedTaskIds: storedDeletedTaskIds,
            utcNow: utcNow,
          )) {
        return true;
      }
    }
    for (final id in originTasks.keys) {
      if (!storedTasksById.containsKey(id) &&
          storedBaseline.deletedBlock.findTaskRecord(id) != null) {
        return true;
      }
    }
    return false;
  }

  /// Returns `true` when [candidate] modified or newly referenced any retired entity from [originTasks], [originLabels], or [originLocations].
  static bool _didCandidateModifyRetiredEntities(
    TaskBoard candidate, {
    required Map<String, TaskItem> originTasks,
    required Map<String, TdfLabel> originLabels,
    required Map<String, TdfLocation> originLocations,
    required Map<String, TaskItem> candidateTasksById,
    required Set<String> candidateDeletedTaskIds,
    required Set<String> retiredTaskIds,
    required Set<String> retiredLabelIds,
    required Set<String> retiredLocationIds,
    required DateTime utcNow,
  }) =>
      _didCandidateModifyRetiredTasks(
        candidate,
        originTasks,
        candidateTasksById,
        candidateDeletedTaskIds,
        retiredTaskIds,
        utcNow,
      ) ||
      _didCandidateModifyRetiredLabels(
        candidate,
        originTasks,
        originLabels,
        candidateTasksById,
        candidateDeletedTaskIds,
        retiredLabelIds,
        utcNow,
      ) ||
      _didCandidateModifyRetiredLocations(
        candidate,
        originTasks,
        originLabels,
        originLocations,
        candidateTasksById,
        candidateDeletedTaskIds,
        retiredLocationIds,
        utcNow,
      );

  /// Returns `true` when [candidate] modified a label in [retiredLabelIds] or modified a task that references [retiredLabelIds].
  static bool _didCandidateModifyRetiredLabels(
    TaskBoard candidate,
    Map<String, TaskItem> originTasks,
    Map<String, TdfLabel> originLabels,
    Map<String, TaskItem> candidateTasksById,
    Set<String> candidateDeletedTaskIds,
    Set<String> retiredLabelIds,
    DateTime utcNow,
  ) {
    if (retiredLabelIds.isEmpty) {
      return false;
    }
    for (final label in candidate.labels) {
      if (!retiredLabelIds.contains(label.id)) continue;
      final origin = originLabels[label.id];
      if (origin == null ||
          origin.effectiveModifiedAt != label.effectiveModifiedAt ||
          TdfPayloadComparison.compareLabelPayloads(origin, label) != 0) {
        return true;
      }
    }
    for (final item in candidate.allTasks) {
      if (!_hasAnyId(item.labelIds, retiredLabelIds)) continue;
      final origin = originTasks[item.id];
      if (origin == null ||
          !_isTaskUnchangedModuloBlockCleanup(
            originTask: origin,
            candidateTask: item,
            liveTasksById: candidateTasksById,
            deletedTaskIds: candidateDeletedTaskIds,
            utcNow: utcNow,
          )) {
        return true;
      }
    }
    return false;
  }

  /// Returns `true` when [candidate] modified a location in [retiredLocationIds] or modified a task/label referencing [retiredLocationIds].
  static bool _didCandidateModifyRetiredLocations(
    TaskBoard candidate,
    Map<String, TaskItem> originTasks,
    Map<String, TdfLabel> originLabels,
    Map<String, TdfLocation> originLocations,
    Map<String, TaskItem> candidateTasksById,
    Set<String> candidateDeletedTaskIds,
    Set<String> retiredLocationIds,
    DateTime utcNow,
  ) {
    if (retiredLocationIds.isEmpty) {
      return false;
    }
    for (final location in candidate.locations) {
      if (!retiredLocationIds.contains(location.id)) continue;
      final origin = originLocations[location.id];
      if (origin == null ||
          origin.effectiveModifiedAt != location.effectiveModifiedAt ||
          TdfPayloadComparison.compareLocationPayloads(origin, location) != 0) {
        return true;
      }
    }
    for (final label in candidate.labels) {
      final locIds = _extractConditionLocationIds(label.conditions);
      if (!_hasAnyId(locIds, retiredLocationIds)) continue;
      final origin = originLabels[label.id];
      if (origin == null ||
          origin.effectiveModifiedAt != label.effectiveModifiedAt ||
          TdfPayloadComparison.compareLabelPayloads(origin, label) != 0) {
        return true;
      }
    }
    for (final item in candidate.allTasks) {
      final locIds = _extractConditionLocationIds(item.conditions);
      if (!_hasAnyId(locIds, retiredLocationIds)) continue;
      final origin = originTasks[item.id];
      if (origin == null ||
          !_isTaskUnchangedModuloBlockCleanup(
            originTask: origin,
            candidateTask: item,
            liveTasksById: candidateTasksById,
            deletedTaskIds: candidateDeletedTaskIds,
            utcNow: utcNow,
          )) {
        return true;
      }
    }
    return false;
  }

  /// Returns `true` when [candidate] modified any task in [retiredTaskIds] (ignoring automatic open-task block cleanup at [utcNow]).
  static bool _didCandidateModifyRetiredTasks(
    TaskBoard candidate,
    Map<String, TaskItem> originTasks,
    Map<String, TaskItem> candidateTasksById,
    Set<String> candidateDeletedTaskIds,
    Set<String> retiredTaskIds,
    DateTime utcNow,
  ) {
    if (retiredTaskIds.isEmpty) {
      return false;
    }
    for (final item in candidate.allTasks) {
      if (!retiredTaskIds.contains(item.id)) continue;
      final origin = originTasks[item.id];
      if (origin == null ||
          !_isTaskUnchangedModuloBlockCleanup(
            originTask: origin,
            candidateTask: item,
            liveTasksById: candidateTasksById,
            deletedTaskIds: candidateDeletedTaskIds,
            utcNow: utcNow,
          )) {
        return true;
      }
    }
    return false;
  }

  /// Extracts all referenced location IDs from [conditions].
  static Set<String> _extractConditionLocationIds(
    List<TaskCondition> conditions,
  ) {
    final ids = <String>{};
    for (final rule in conditions) {
      if (rule is LocationTaskCondition && rule.locationIds.isNotEmpty) {
        ids.addAll(rule.locationIds);
      }
    }
    return ids;
  }

  /// Retains baseline labels known to [originLabels] (including tombstoned or retired labels when requested), preferring pre-reconcile [originLabels] revisions unless [baselineLabels] predates [originLabels].
  static List<TdfLabel> _filterBaselineLabels(
    List<TdfLabel> baselineLabels,
    Map<String, TdfLabel> originLabels,
    TdfDeletedBlock storedDeleted, {
    bool includeRetired = false,
  }) {
    final result = <TdfLabel>[];
    final seenIds = <String>{};
    for (final label in baselineLabels) {
      seenIds.add(label.id);
      if (originLabels[label.id] case final origin?) {
        result.add(
          label.effectiveModifiedAt.isBefore(origin.effectiveModifiedAt)
              ? label
              : origin,
        );
      }
    }
    for (final origin in originLabels.values) {
      if (!seenIds.contains(origin.id) &&
          (includeRetired ||
              storedDeleted.findLabelRecord(origin.id) != null)) {
        result.add(origin);
      }
    }
    return result;
  }

  /// Retains baseline locations known to [originLocations] (including tombstoned or retired locations when requested), preferring pre-reconcile [originLocations] revisions unless [baselineLocations] predates [originLocations].
  static List<TdfLocation> _filterBaselineLocations(
    List<TdfLocation> baselineLocations,
    Map<String, TdfLocation> originLocations,
    TdfDeletedBlock storedDeleted, {
    bool includeRetired = false,
  }) {
    final result = <TdfLocation>[];
    final seenIds = <String>{};
    for (final location in baselineLocations) {
      seenIds.add(location.id);
      if (originLocations[location.id] case final origin?) {
        result.add(
          location.effectiveModifiedAt.isBefore(origin.effectiveModifiedAt)
              ? location
              : origin,
        );
      }
    }
    for (final origin in originLocations.values) {
      if (!seenIds.contains(origin.id) &&
          (includeRetired ||
              storedDeleted.findLocationRecord(origin.id) != null)) {
        result.add(origin);
      }
    }
    return result;
  }

  /// Retains baseline tasks known to [originTasks] (including tombstoned or retired tasks when requested), preferring pre-reconcile [originTasks] revisions unless [baselineTasks] predates [originTasks] or differs only by automatic block cleanup.
  static List<TaskItem> _filterBaselineTasks(
    Iterable<TaskItem> baselineTasks,
    Map<String, TaskItem> originTasks,
    TdfDeletedBlock storedDeleted, {
    required Map<String, TaskItem> storedTasksById,
    required Set<String> storedDeletedTaskIds,
    required DateTime utcNow,
    bool includeRetired = false,
  }) {
    final result = <TaskItem>[];
    final seenIds = <String>{};
    for (final item in baselineTasks) {
      seenIds.add(item.id);
      if (originTasks[item.id] case final origin?) {
        final keepBaselineItem =
            item.effectiveModifiedAt.isBefore(origin.effectiveModifiedAt) ||
            _isTaskUnchangedModuloBlockCleanup(
              originTask: origin,
              candidateTask: item,
              liveTasksById: storedTasksById,
              deletedTaskIds: storedDeletedTaskIds,
              utcNow: utcNow,
            );
        result.add(keepBaselineItem ? item : origin);
      }
    }
    for (final origin in originTasks.values) {
      if (!seenIds.contains(origin.id) &&
          (includeRetired || storedDeleted.findTaskRecord(origin.id) != null)) {
        result.add(origin);
      }
    }
    return result;
  }

  /// Returns `true` when any identifier in [ids] is contained in [targetSet].
  static bool _hasAnyId(Iterable<String> ids, Set<String> targetSet) {
    for (final id in ids) {
      if (targetSet.contains(id)) {
        return true;
      }
    }
    return false;
  }

  /// Returns `true` when any dependency in [dependencies] targets an identifier in [retiredTaskIds].
  static bool _hasAnyRetiredDependency(
    List<TdfTaskDependency> dependencies,
    Set<String> retiredTaskIds,
  ) {
    for (final dep in dependencies) {
      if (retiredTaskIds.contains(dep.taskId)) {
        return true;
      }
    }
    return false;
  }

  /// Returns `true` when [candidateTask] and [originTask] represent the same task snapshot modulo automatic open-task block-reason cleanup at [utcNow].
  static bool _isTaskUnchangedModuloBlockCleanup({
    required TaskItem originTask,
    required TaskItem candidateTask,
    required Map<String, TaskItem> liveTasksById,
    required Set<String> deletedTaskIds,
    required DateTime utcNow,
  }) {
    if (originTask == candidateTask) {
      return true;
    }
    if (originTask.completions != candidateTask.completions ||
        originTask.isCompleted != candidateTask.isCompleted ||
        (originTask.completedAt != null) !=
            (candidateTask.completedAt != null)) {
      return false;
    }
    if (TdfPayloadComparison.taskPayloadsEqual(originTask, candidateTask)) {
      return originTask.effectiveModifiedAt ==
          candidateTask.effectiveModifiedAt;
    }
    if (originTask.isCompleted || originTask.completedAt != null) {
      return false;
    }
    return TdfPayloadComparison.taskPayloadsEqualModuloBlockCleanup(
      left: originTask,
      right: candidateTask,
      liveTasksById: liveTasksById,
      deletedTaskIds: deletedTaskIds,
      nowUtc: utcNow,
    );
  }

  /// Reconciles [candidate] against an empty remote WebDAV document when an externally deleted remote requires `TDF-REC-001` verification.
  static TaskBoard _mergeAgainstEmptyRemote(
    TaskBoard candidate, {
    required int? acknowledgedGeneration,
    required int preTransactionGeneration,
    required _SyncResolutions resolutions,
    required DateTime utcNow,
    required DateTime localNow,
    required TdfTimeZoneContext timeZone,
    required Duration? dueLeadWindow,
  }) {
    final hasLiveEntities =
        candidate.allTasks.isNotEmpty ||
        candidate.labels.isNotEmpty ||
        candidate.locations.isNotEmpty;
    final hasAcknowledgedGen =
        acknowledgedGeneration != null && acknowledgedGeneration > 0;
    if (!hasLiveEntities && !hasAcknowledgedGen) {
      return candidate;
    }
    return TaskBoardSync.merge(
      primary: candidate,
      secondary: TaskBoard.empty(),
      baseline: null,
      acknowledgedGeneration: hasLiveEntities ? null : acknowledgedGeneration,
      preTransactionPrimaryGeneration: preTransactionGeneration,
      requireAcknowledgedGeneration: true,
      taskConflictResolutions: resolutions.taskConflicts,
      labelConflictResolutions: resolutions.labelConflicts,
      locationConflictResolutions: resolutions.locationConflicts,
      boundTaskConflictDecisions: resolutions.boundTaskDecisions,
      boundLabelConflictDecisions: resolutions.boundLabelDecisions,
      boundLocationConflictDecisions: resolutions.boundLocationDecisions,
      taskRecoveryResolutions: resolutions.taskRecoveries,
      labelRecoveryResolutions: resolutions.labelRecoveries,
      locationRecoveryResolutions: resolutions.locationRecoveries,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      cleanupMode: TdfCleanupMode.finalStage,
      pruneExpiredDeleted: true,
      pruneExpiredCompleted: true,
    );
  }

  /// Parses [rawRemote] and merges it with [working] against [storedRemoteBaselineTdf], or reuses [working] on `HTTP 304 Not Modified`.
  static ({
    TaskBoard board,
    bool hasWorking,
    String? canonicalRemoteTdf,
    TaskBoard? remoteBoard,
  })
  _mergeRemoteSnapshot(
    Ref ref,
    WebDavConfig config, {
    required String rawRemote,
    required bool notModified,
    required bool hadPriorRemoteSync,
    required TaskBoard working,
    required TaskBoard? candidateOriginBoard,
    required bool hasWorking,
    required bool hadPriorLocalConvergence,
    required String? storedRemoteBaselineTdf,
    required bool useBaselineBoard,
    required int? acknowledgedGeneration,
    required int preTransactionGeneration,
    required _SyncResolutions resolutions,
    required DateTime utcNow,
    required DateTime localNow,
    required TdfTimeZoneContext timeZone,
  }) {
    final baselineTdf = useBaselineBoard ? storedRemoteBaselineTdf : null;
    final trimmedRemote = rawRemote.trim();
    final canBypassMerge =
        notModified && !resolutions.hasAny && candidateOriginBoard == null;
    if (canBypassMerge) {
      if (hasWorking && hadPriorLocalConvergence) {
        return (
          board: working,
          hasWorking: true,
          canonicalRemoteTdf: baselineTdf,
          remoteBoard: null,
        );
      }
      if (!hasWorking) {
        if (trimmedRemote.isNotEmpty) {
          final parsed = _parseRemoteOrThrow(
            ref,
            config,
            rawRemote,
            utcNow,
            localNow,
          );
          return (
            board: parsed,
            hasWorking: true,
            canonicalRemoteTdf: baselineTdf ?? _serializeTdf(ref, parsed),
            remoteBoard: parsed,
          );
        }
        return (
          board: working,
          hasWorking: false,
          canonicalRemoteTdf: null,
          remoteBoard: null,
        );
      }
    }
    if (trimmedRemote.isEmpty) {
      final scopedEmpty = _scopeCandidateAndBaseline(
        candidate: working,
        hasCandidate: hasWorking,
        storedBaseline: null,
        candidateOriginBoard: candidateOriginBoard,
        storedAckGeneration: acknowledgedGeneration,
        utcNow: utcNow,
        localNow: localNow,
        timeZone: timeZone,
        dueLeadWindow: config.dueLeadWindow.duration,
      );
      final mergedEmpty = (!notModified && hadPriorRemoteSync && hasWorking)
          ? _mergeAgainstEmptyRemote(
              scopedEmpty.candidate,
              acknowledgedGeneration: acknowledgedGeneration,
              preTransactionGeneration: preTransactionGeneration,
              resolutions: resolutions,
              utcNow: utcNow,
              localNow: localNow,
              timeZone: timeZone,
              dueLeadWindow: config.dueLeadWindow.duration,
            )
          : scopedEmpty.candidate;
      return (
        board: mergedEmpty,
        hasWorking: hasWorking,
        canonicalRemoteTdf: null,
        remoteBoard: null,
      );
    }
    final remoteBoard = _parseRemoteOrThrow(
      ref,
      config,
      rawRemote,
      utcNow,
      localNow,
    );
    final canonicalRemote = notModified
        ? (baselineTdf ?? _serializeTdf(ref, remoteBoard))
        : _serializeTdf(ref, remoteBoard);
    final parsedRemoteBaseline = _tryParseBaseline(
      ref,
      config,
      storedRemoteBaselineTdf,
      utcNow,
      localNow,
    );
    final rawBaseline = useBaselineBoard ? parsedRemoteBaseline : null;
    final effectiveAckGen = storedRemoteBaselineTdf == null
        ? acknowledgedGeneration
        : (parsedRemoteBaseline != null ? acknowledgedGeneration : null);
    final scoped = _scopeCandidateAndBaseline(
      candidate: working,
      hasCandidate: hasWorking,
      storedBaseline: rawBaseline,
      candidateOriginBoard: candidateOriginBoard,
      storedAckGeneration: effectiveAckGen,
      utcNow: utcNow,
      localNow: localNow,
      timeZone: timeZone,
      dueLeadWindow: config.dueLeadWindow.duration,
    );
    final merged = TaskBoardSync.merge(
      primary: hasWorking ? scoped.candidate : remoteBoard,
      secondary: remoteBoard,
      baseline: scoped.baseline ?? (hasWorking ? null : remoteBoard),
      acknowledgedGeneration: scoped.baseline != null
          ? scoped.ackGeneration
          : effectiveAckGen,
      preTransactionPrimaryGeneration: hasWorking
          ? preTransactionGeneration
          : remoteBoard.deletedBlock.generation,
      taskConflictResolutions: resolutions.taskConflicts,
      labelConflictResolutions: resolutions.labelConflicts,
      locationConflictResolutions: resolutions.locationConflicts,
      boundTaskConflictDecisions: resolutions.boundTaskDecisions,
      boundLabelConflictDecisions: resolutions.boundLabelDecisions,
      boundLocationConflictDecisions: resolutions.boundLocationDecisions,
      taskRecoveryResolutions: resolutions.taskRecoveries,
      labelRecoveryResolutions: resolutions.labelRecoveries,
      locationRecoveryResolutions: resolutions.locationRecoveries,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      dueLeadWindow: config.dueLeadWindow.duration,
      cleanupMode: TdfCleanupMode.finalStage,
      pruneExpiredDeleted: true,
      pruneExpiredCompleted: true,
    );
    return (
      board: merged,
      hasWorking: true,
      canonicalRemoteTdf: canonicalRemote,
      remoteBoard: remoteBoard,
    );
  }

  /// Parses [rawLocal] and converts [TdfErrorKind.unsupportedVersion] into [UnsupportedTdfVersionException].
  static Future<TaskBoard> _parseLocalOrThrow(
    Ref ref,
    WebDavConfig config,
    String rawLocal,
    bool requireTargets,
    DateTime utcNow,
    DateTime localNow,
  ) async {
    try {
      return _parseTdf(ref, config, rawLocal, utcNow, localNow);
    } on TdfException catch (error) {
      if (error.kind != TdfErrorKind.unsupportedVersion) rethrow;
      final remoteError =
          (config.storageMode.usesWebDav &&
              (requireTargets || config.isWebDavConfigured))
          ? await _checkRemoteUnsupportedVersion(ref, config, utcNow, localNow)
          : null;
      throw _createUnsupportedVersionException(
        config: config,
        localError: error,
        remoteError: remoteError,
      );
    }
  }

  /// Parses [rawRemote] and converts [TdfErrorKind.unsupportedVersion] into [UnsupportedTdfVersionException].
  static TaskBoard _parseRemoteOrThrow(
    Ref ref,
    WebDavConfig config,
    String rawRemote,
    DateTime utcNow,
    DateTime localNow,
  ) {
    try {
      return _parseTdf(ref, config, rawRemote, utcNow, localNow);
    } on TdfException catch (error) {
      if (error.kind != TdfErrorKind.unsupportedVersion) rethrow;
      throw _createUnsupportedVersionException(
        config: config,
        remoteError: error,
      );
    }
  }

  /// Parses [rawTdf] using [utcNow], [localNow], and [config]'s workspace time zone context.
  static TaskBoard _parseTdf(
    Ref ref,
    WebDavConfig config,
    String rawTdf,
    DateTime utcNow,
    DateTime localNow,
  ) => ref
      .read(tdfServiceProvider)
      .parse(
        rawTdf,
        evaluationTime: utcNow,
        localEvaluationTime: localNow,
        timeZone: resolveWorkspaceTimeZone(config, utcNow),
        dueLeadWindow: config.dueLeadWindow.duration,
      );

  /// Executes the guarded local publication compare-and-swap (CAS) merge loop while holding `withExclusiveTargetLock` (`TDF-PUB-002`, `TDF-PUB-003`).
  static Future<({TaskBoard board, String serialized, String? digest})>
  _publishLocalWithCasLoop(
    Ref ref,
    WebDavConfig config, {
    required String? initialDigest,
    required TaskBoard? initialBaseline,
    required int? initialAckGeneration,
    required String? initialCanonicalDiskTdf,
    required int preTransactionGeneration,
    required TaskBoard candidateBoard,
    required _SyncResolutions resolutions,
    required bool requireTargets,
    required bool skipWriteIfUnchanged,
    required TdfCleanupMode cleanupMode,
    required bool isAuthoritativeSource,
    required DateTime utcNow,
    required DateTime localNow,
  }) async {
    final localRepo = ref.read(localFileRepositoryProvider);
    return localRepo.withExclusiveTargetLock(() async {
      var loopDigest = initialDigest;
      var loopB = initialBaseline;
      var loopAckGen = initialAckGeneration;
      var loopL = candidateBoard;
      for (var attempt = 0; attempt <= maxCasRetries; attempt++) {
        final disk = await localRepo.readTdfWithDigest();
        if (!ref.mounted) {
          return (board: loopL, serialized: '', digest: loopDigest);
        }
        final digestMatches =
            (!disk.exists && loopDigest == null) ||
            (disk.exists && disk.digest == loopDigest);
        if (digestMatches) {
          final serialized = _serializeTdf(ref, loopL);
          final alreadyMatchesDisk =
              disk.exists &&
              (disk.content.trim() == serialized.trim() ||
                  (attempt == 0 &&
                      initialCanonicalDiskTdf != null &&
                      initialCanonicalDiskTdf == serialized));
          if (attempt > 0 || !skipWriteIfUnchanged || !alreadyMatchesDisk) {
            await localRepo.saveTdf(serialized);
            final savedDigest = Sha256Service.hashHex(utf8.encode(serialized));
            return (board: loopL, serialized: serialized, digest: savedDigest);
          }
          return (board: loopL, serialized: serialized, digest: loopDigest);
        }
        if (attempt >= maxCasRetries) {
          throw const LocalFileException(
            'Local file was modified concurrently and exceeded maximum CAS merge retries (3).',
          );
        }
        (loopB, loopAckGen, loopL, loopDigest) = await _retryCasMergeStep(
          ref,
          config,
          disk: disk,
          loopB: loopB,
          loopAckGen: loopAckGen,
          loopL: loopL,
          loopDigest: loopDigest,
          preTransactionGeneration: preTransactionGeneration,
          resolutions: resolutions,
          requireTargets: requireTargets,
          cleanupMode: cleanupMode,
          isAuthoritativeSource: isAuthoritativeSource,
          utcNow: utcNow,
          localNow: localNow,
        );
        if (!ref.mounted) {
          return (board: loopL, serialized: '', digest: loopDigest);
        }
      }
      throw const LocalFileException(
        'Local file was modified concurrently and exceeded maximum CAS merge retries (3).',
      );
    });
  }

  /// Publishes [serializedCandidate] to WebDAV with bounded `412 Precondition Failed` CAS retry.
  static Future<(TaskBoard, String)> _publishRemoteWithCasLoop(
    Ref ref,
    WebDavConfig config, {
    required WebDavRepository webDavRepo,
    required TaskBoard working,
    required TaskBoard? initialBaseline,
    required int? initialAckGeneration,
    required bool hadExistingRemote,
    required int preTransactionGeneration,
    required String serializedCandidate,
    required _SyncResolutions resolutions,
    required DateTime utcNow,
    required DateTime localNow,
  }) async {
    var loopWorking = working;
    var loopBaseline = initialBaseline;
    var loopAckGeneration = initialAckGeneration;
    var loopHadExistingRemote = hadExistingRemote;
    var currentSerialized = serializedCandidate;
    for (var attempt = 0; attempt <= maxCasRetries; attempt++) {
      try {
        await webDavRepo.saveTdf(currentSerialized);
        return (loopWorking, currentSerialized);
      } on WebDavException catch (error) {
        if (!error.isPreconditionFailed || attempt >= maxCasRetries) rethrow;
        if (!ref.mounted) {
          return (loopWorking, currentSerialized);
        }
        (
          loopBaseline,
          loopAckGeneration,
          loopWorking,
          currentSerialized,
        ) = await _retryRemoteCasMergeStep(
          ref,
          config,
          webDavRepo: webDavRepo,
          loopWorking: loopWorking,
          loopBaseline: loopBaseline,
          loopAckGeneration: loopAckGeneration,
          hadExistingRemote: loopHadExistingRemote,
          preTransactionGeneration: preTransactionGeneration,
          resolutions: resolutions,
          utcNow: utcNow,
          localNow: localNow,
        );
        loopHadExistingRemote = loopBaseline != null;
        if (!ref.mounted) {
          return (loopWorking, currentSerialized);
        }
      }
    }
    return (loopWorking, currentSerialized);
  }

  /// Rebases [candidate] onto [targetGeneration] after stripping untouched entities and `blocked` references retired by an already-acknowledged generation bump.
  static TaskBoard _rebaseCandidateToGeneration(
    TaskBoard candidate, {
    required int targetGeneration,
    required Set<String> retiredTaskIds,
    required Set<String> retiredLabelIds,
    required Set<String> retiredLocationIds,
    required DateTime utcNow,
    required DateTime localNow,
    required TdfTimeZoneContext timeZone,
    required Duration? dueLeadWindow,
  }) {
    final nextTasks = retiredTaskIds.isEmpty
        ? candidate.allTasks
        : <TaskItem>[
            for (final item in candidate.allTasks)
              if (!retiredTaskIds.contains(item.id))
                _stripRetiredTaskDependencies(item, retiredTaskIds, utcNow),
          ];
    final nextLabels = retiredLabelIds.isEmpty
        ? candidate.labels
        : <TdfLabel>[
            for (final label in candidate.labels)
              if (!retiredLabelIds.contains(label.id)) label,
          ];
    final nextLocations = retiredLocationIds.isEmpty
        ? candidate.locations
        : <TdfLocation>[
            for (final loc in candidate.locations)
              if (!retiredLocationIds.contains(loc.id)) loc,
          ];
    final nextQueue = retiredTaskIds.isEmpty
        ? candidate.queueBlock
        : TdfQueueBlock(
            modifiedAt: candidate.queueBlock.modifiedAt,
            taskIds: <String>[
              for (final id in candidate.queueBlock.taskIds)
                if (!retiredTaskIds.contains(id)) id,
            ],
          );
    return TaskBoard.evaluate(
      tasks: nextTasks,
      labels: nextLabels,
      locations: nextLocations,
      deletedBlock: TdfDeletedBlock(
        generation: targetGeneration,
        tasks: candidate.deletedBlock.tasks,
        labels: candidate.deletedBlock.labels,
        locations: candidate.deletedBlock.locations,
      ),
      queueBlock: nextQueue,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      pruneExpiredCompleted: false,
    );
  }

  /// Restores pre-cleanup snapshots from [storedBaseline] or [originTasks] for open tasks in [candidate] whose only change was automatic block-reason cleanup.
  static TaskBoard _restorePreCleanupBystanderTasks({
    required TaskBoard candidate,
    required TaskBoard candidateOriginBoard,
    required TaskBoard? storedBaseline,
    required Map<String, TaskItem> originTasks,
    required Map<String, TaskItem> candidateTasksById,
    required Set<String> candidateDeletedTaskIds,
    required DateTime utcNow,
    required DateTime localNow,
    required TdfTimeZoneContext timeZone,
    required Duration? dueLeadWindow,
  }) {
    final originQueuedIds = candidateOriginBoard.queueBlock.taskIds.toSet();
    final candidateQueuedIds = candidate.queueBlock.taskIds.toSet();
    final storedTasksById = storedBaseline == null
        ? const <String, TaskItem>{}
        : <String, TaskItem>{
            for (final item in storedBaseline.allTasks) item.id: item,
          };
    final storedDeletedTaskIds = storedBaseline == null
        ? const <String>{}
        : <String>{
            for (final record in storedBaseline.deletedBlock.tasks)
              record.taskId,
          };
    var didRestoreAny = false;
    final nextTasks = <TaskItem>[];
    for (final item in candidate.allTasks) {
      final restored = _selectRestoredBystanderTask(
        item: item,
        originTask: originTasks[item.id],
        storedTask: storedTasksById[item.id],
        sameQueueMembership:
            originQueuedIds.contains(item.id) ==
            candidateQueuedIds.contains(item.id),
        candidateTasksById: candidateTasksById,
        candidateDeletedTaskIds: candidateDeletedTaskIds,
        storedTasksById: storedTasksById,
        storedDeletedTaskIds: storedDeletedTaskIds,
        utcNow: utcNow,
      );
      if (!identical(restored, item)) {
        didRestoreAny = true;
      }
      nextTasks.add(restored);
    }
    if (!didRestoreAny) {
      return candidate;
    }
    return TaskBoard.evaluate(
      tasks: nextTasks,
      labels: candidate.labels,
      locations: candidate.locations,
      deletedBlock: candidate.deletedBlock,
      queueBlock: candidate.queueBlock,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      pruneExpiredCompleted: false,
    );
  }

  /// Resolves a single CAS mismatch iteration against the freshly read [disk] snapshot (`TDF-PUB-003` Step 3).
  static Future<(TaskBoard?, int?, TaskBoard, String?)> _retryCasMergeStep(
    Ref ref,
    WebDavConfig config, {
    required ({String content, String? digest, bool exists}) disk,
    required TaskBoard? loopB,
    required int? loopAckGen,
    required TaskBoard loopL,
    required String? loopDigest,
    required int preTransactionGeneration,
    required _SyncResolutions resolutions,
    required bool requireTargets,
    required TdfCleanupMode cleanupMode,
    required bool isAuthoritativeSource,
    required DateTime utcNow,
    required DateTime localNow,
  }) async {
    final timeZone = resolveWorkspaceTimeZone(config, utcNow);
    final dueLeadWindow = config.dueLeadWindow.duration;
    if (!disk.exists || disk.content.trim().isEmpty) {
      final wasRemoved = !disk.exists && loopDigest != null;
      final mergedEmpty = TaskBoardSync.merge(
        primary: loopL,
        secondary: TaskBoard.empty(),
        baseline: wasRemoved ? null : loopB,
        acknowledgedGeneration: wasRemoved ? null : loopAckGen,
        preTransactionPrimaryGeneration: preTransactionGeneration,
        requireAcknowledgedGeneration: true,
        taskConflictResolutions: resolutions.taskConflicts,
        labelConflictResolutions: resolutions.labelConflicts,
        locationConflictResolutions: resolutions.locationConflicts,
        boundTaskConflictDecisions: resolutions.boundTaskDecisions,
        boundLabelConflictDecisions: resolutions.boundLabelDecisions,
        boundLocationConflictDecisions: resolutions.boundLocationDecisions,
        taskRecoveryResolutions: resolutions.taskRecoveries,
        labelRecoveryResolutions: resolutions.labelRecoveries,
        locationRecoveryResolutions: resolutions.locationRecoveries,
        evaluationTime: utcNow,
        localEvaluationTime: localNow,
        timeZone: timeZone,
        dueLeadWindow: dueLeadWindow,
        cleanupMode: cleanupMode,
        pruneExpiredDeleted: isAuthoritativeSource,
        pruneExpiredCompleted: isAuthoritativeSource,
      );
      final normalized = TaskBoardSync.stampAndNormalize(
        mergedEmpty,
        evaluationTime: utcNow,
        localEvaluationTime: localNow,
        timeZone: timeZone,
        dueLeadWindow: dueLeadWindow,
        cleanupMode: cleanupMode,
        pruneExpiredDeleted: isAuthoritativeSource,
        pruneExpiredCompleted: isAuthoritativeSource,
        preTransactionGeneration: preTransactionGeneration,
      );
      return (null, null, normalized, disk.exists ? disk.digest : null);
    }
    final diskBoard = await _parseLocalOrThrow(
      ref,
      config,
      disk.content,
      requireTargets,
      utcNow,
      localNow,
    );
    final diskGen = diskBoard.deletedBlock.generation;
    final floorGen = preTransactionGeneration >= diskGen
        ? preTransactionGeneration
        : diskGen;
    final merged = TaskBoardSync.merge(
      primary: loopL,
      secondary: diskBoard,
      baseline: loopB,
      acknowledgedGeneration: loopAckGen ?? loopB?.deletedBlock.generation,
      preTransactionPrimaryGeneration: preTransactionGeneration,
      taskConflictResolutions: resolutions.taskConflicts,
      labelConflictResolutions: resolutions.labelConflicts,
      locationConflictResolutions: resolutions.locationConflicts,
      boundTaskConflictDecisions: resolutions.boundTaskDecisions,
      boundLabelConflictDecisions: resolutions.boundLabelDecisions,
      boundLocationConflictDecisions: resolutions.boundLocationDecisions,
      taskRecoveryResolutions: resolutions.taskRecoveries,
      labelRecoveryResolutions: resolutions.labelRecoveries,
      locationRecoveryResolutions: resolutions.locationRecoveries,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      cleanupMode: cleanupMode,
      pruneExpiredDeleted: isAuthoritativeSource,
      pruneExpiredCompleted: isAuthoritativeSource,
    );
    final normalized = TaskBoardSync.stampAndNormalize(
      merged,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      cleanupMode: cleanupMode,
      pruneExpiredDeleted: isAuthoritativeSource,
      pruneExpiredCompleted: isAuthoritativeSource,
      preTransactionGeneration: floorGen,
    );
    return (diskBoard, diskGen, normalized, disk.digest);
  }

  /// Resolves a single WebDAV `412 Precondition Failed` CAS mismatch against the freshly fetched remote snapshot.
  static Future<(TaskBoard?, int?, TaskBoard, String)> _retryRemoteCasMergeStep(
    Ref ref,
    WebDavConfig config, {
    required WebDavRepository webDavRepo,
    required TaskBoard loopWorking,
    required TaskBoard? loopBaseline,
    required int? loopAckGeneration,
    required bool hadExistingRemote,
    required int preTransactionGeneration,
    required _SyncResolutions resolutions,
    required DateTime utcNow,
    required DateTime localNow,
  }) async {
    final timeZone = resolveWorkspaceTimeZone(config, utcNow);
    final dueLeadWindow = config.dueLeadWindow.duration;
    final retryRaw = await webDavRepo.fetchTdf();
    if (!ref.mounted) {
      return (loopBaseline, loopAckGeneration, loopWorking, '');
    }
    final effectiveAckGen =
        loopAckGeneration ?? loopBaseline?.deletedBlock.generation;
    if (retryRaw.trim().isEmpty) {
      final mergedEmpty = hadExistingRemote
          ? _mergeAgainstEmptyRemote(
              loopWorking,
              acknowledgedGeneration: effectiveAckGen,
              preTransactionGeneration: preTransactionGeneration,
              resolutions: resolutions,
              utcNow: utcNow,
              localNow: localNow,
              timeZone: timeZone,
              dueLeadWindow: dueLeadWindow,
            )
          : loopWorking;
      final normalized = TaskBoardSync.stampAndNormalize(
        mergedEmpty,
        evaluationTime: utcNow,
        localEvaluationTime: localNow,
        timeZone: timeZone,
        dueLeadWindow: dueLeadWindow,
        cleanupMode: TdfCleanupMode.finalStage,
        pruneExpiredDeleted: true,
        pruneExpiredCompleted: true,
        preTransactionGeneration: preTransactionGeneration,
      );
      return (null, null, normalized, _serializeTdf(ref, normalized));
    }
    final retryRemote = _parseRemoteOrThrow(
      ref,
      config,
      retryRaw,
      utcNow,
      localNow,
    );
    final remoteGen = retryRemote.deletedBlock.generation;
    final floorGen = preTransactionGeneration >= remoteGen
        ? preTransactionGeneration
        : remoteGen;
    final merged = TaskBoardSync.merge(
      primary: loopWorking,
      secondary: retryRemote,
      baseline: loopBaseline,
      acknowledgedGeneration: effectiveAckGen,
      preTransactionPrimaryGeneration: preTransactionGeneration,
      taskConflictResolutions: resolutions.taskConflicts,
      labelConflictResolutions: resolutions.labelConflicts,
      locationConflictResolutions: resolutions.locationConflicts,
      boundTaskConflictDecisions: resolutions.boundTaskDecisions,
      boundLabelConflictDecisions: resolutions.boundLabelDecisions,
      boundLocationConflictDecisions: resolutions.boundLocationDecisions,
      taskRecoveryResolutions: resolutions.taskRecoveries,
      labelRecoveryResolutions: resolutions.labelRecoveries,
      locationRecoveryResolutions: resolutions.locationRecoveries,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      cleanupMode: TdfCleanupMode.finalStage,
      pruneExpiredDeleted: true,
      pruneExpiredCompleted: true,
    );
    final normalized = TaskBoardSync.stampAndNormalize(
      merged,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      cleanupMode: TdfCleanupMode.finalStage,
      pruneExpiredDeleted: true,
      pruneExpiredCompleted: true,
      preTransactionGeneration: floorGen,
    );
    return (retryRemote, remoteGen, normalized, _serializeTdf(ref, normalized));
  }

  /// Scopes [storedBaseline] to [originTasks], [originLabels], and [originLocations] for a queued optimistic mutation.
  static TaskBoard _scopeBaselineToCandidateOrigin(
    TaskBoard storedBaseline,
    TaskBoard candidateOriginBoard, {
    required Map<String, TaskItem> originTasks,
    required Map<String, TdfLabel> originLabels,
    required Map<String, TdfLocation> originLocations,
    required bool useOriginGeneration,
    required DateTime utcNow,
    required DateTime localNow,
    required TdfTimeZoneContext timeZone,
    required Duration? dueLeadWindow,
  }) {
    final queueAdvanced =
        !storedBaseline.queueBlock.modifiedAt.isBefore(
          candidateOriginBoard.queueBlock.modifiedAt,
        ) &&
        TdfPayloadComparison.compareQueueBlocks(
              candidateOriginBoard.queueBlock,
              storedBaseline.queueBlock,
            ) !=
            0;
    if (!useOriginGeneration &&
        !queueAdvanced &&
        !_didBaselineAdvancePastOrigin(
          storedBaseline,
          originTasks,
          originLabels,
          originLocations,
          utcNow,
        )) {
      return storedBaseline;
    }
    final storedDeleted = storedBaseline.deletedBlock;
    final storedTasksById = <String, TaskItem>{
      for (final item in storedBaseline.allTasks) item.id: item,
    };
    final storedDeletedTaskIds = <String>{
      for (final record in storedDeleted.tasks) record.taskId,
    };
    return TaskBoard.evaluate(
      tasks: _filterBaselineTasks(
        storedBaseline.allTasks,
        originTasks,
        storedDeleted,
        storedTasksById: storedTasksById,
        storedDeletedTaskIds: storedDeletedTaskIds,
        utcNow: utcNow,
        includeRetired: useOriginGeneration,
      ),
      labels: _filterBaselineLabels(
        storedBaseline.labels,
        originLabels,
        storedDeleted,
        includeRetired: useOriginGeneration,
      ),
      locations: _filterBaselineLocations(
        storedBaseline.locations,
        originLocations,
        storedDeleted,
        includeRetired: useOriginGeneration,
      ),
      deletedBlock: useOriginGeneration
          ? candidateOriginBoard.deletedBlock
          : storedDeleted,
      queueBlock: queueAdvanced
          ? candidateOriginBoard.queueBlock
          : storedBaseline.queueBlock,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      pruneExpiredCompleted: false,
    );
  }

  /// Aligns [candidate], [storedBaseline], and [storedAckGeneration] against [candidateOriginBoard] across concurrent reconciles, block cleanups, and generation bumps.
  static ({TaskBoard candidate, TaskBoard? baseline, int? ackGeneration})
  _scopeCandidateAndBaseline({
    required TaskBoard candidate,
    required bool hasCandidate,
    required TaskBoard? storedBaseline,
    required TaskBoard? candidateOriginBoard,
    required int? storedAckGeneration,
    required DateTime utcNow,
    required DateTime localNow,
    required TdfTimeZoneContext timeZone,
    required Duration? dueLeadWindow,
  }) {
    if (!hasCandidate || candidateOriginBoard == null) {
      return (
        candidate: candidate,
        baseline: storedBaseline,
        ackGeneration: storedAckGeneration,
      );
    }
    final originTasks = <String, TaskItem>{
      for (final item in candidateOriginBoard.allTasks) item.id: item,
    };
    final candidateTasksById = <String, TaskItem>{
      for (final item in candidate.allTasks) item.id: item,
    };
    final candidateDeletedTaskIds = <String>{
      for (final record in candidate.deletedBlock.tasks) record.taskId,
    };
    var rebasedCandidate = _restorePreCleanupBystanderTasks(
      candidate: candidate,
      candidateOriginBoard: candidateOriginBoard,
      storedBaseline: storedBaseline,
      originTasks: originTasks,
      candidateTasksById: candidateTasksById,
      candidateDeletedTaskIds: candidateDeletedTaskIds,
      utcNow: utcNow,
      localNow: localNow,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
    );
    if (storedBaseline == null) {
      return (
        candidate: rebasedCandidate,
        baseline: null,
        ackGeneration: storedAckGeneration,
      );
    }
    final originLabels = <String, TdfLabel>{
      for (final label in candidateOriginBoard.labels) label.id: label,
    };
    final originLocations = <String, TdfLocation>{
      for (final location in candidateOriginBoard.locations)
        location.id: location,
    };
    final originGen = candidateOriginBoard.deletedBlock.generation;
    final storedGen = storedBaseline.deletedBlock.generation;
    final resolvedAckGen = storedAckGeneration ?? storedGen;
    var useOriginGen = false;
    var effectiveAckGen = resolvedAckGen;

    if (originGen < storedGen && storedGen <= resolvedAckGen) {
      final retiredTaskIds = <String>{
        for (final id in originTasks.keys)
          if (storedBaseline.findTask(id) == null &&
              storedBaseline.deletedBlock.findTaskRecord(id) == null)
            id,
      };
      final retiredLabelIds = <String>{
        for (final id in originLabels.keys)
          if (storedBaseline.findLabel(id) == null &&
              storedBaseline.deletedBlock.findLabelRecord(id) == null)
            id,
      };
      final retiredLocationIds = <String>{
        for (final id in originLocations.keys)
          if (storedBaseline.findLocation(id) == null &&
              storedBaseline.deletedBlock.findLocationRecord(id) == null)
            id,
      };
      if (_didCandidateModifyRetiredEntities(
        candidate,
        originTasks: originTasks,
        originLabels: originLabels,
        originLocations: originLocations,
        candidateTasksById: candidateTasksById,
        candidateDeletedTaskIds: candidateDeletedTaskIds,
        retiredTaskIds: retiredTaskIds,
        retiredLabelIds: retiredLabelIds,
        retiredLocationIds: retiredLocationIds,
        utcNow: utcNow,
      )) {
        useOriginGen = true;
        effectiveAckGen = originGen;
      } else if (rebasedCandidate.deletedBlock.generation == originGen) {
        rebasedCandidate = _rebaseCandidateToGeneration(
          rebasedCandidate,
          targetGeneration: storedGen,
          retiredTaskIds: retiredTaskIds,
          retiredLabelIds: retiredLabelIds,
          retiredLocationIds: retiredLocationIds,
          utcNow: utcNow,
          localNow: localNow,
          timeZone: timeZone,
          dueLeadWindow: dueLeadWindow,
        );
      }
    } else if (originGen < resolvedAckGen) {
      useOriginGen = originGen < storedGen;
      effectiveAckGen = originGen;
    }

    final scopedBaseline = _scopeBaselineToCandidateOrigin(
      storedBaseline,
      candidateOriginBoard,
      originTasks: originTasks,
      originLabels: originLabels,
      originLocations: originLocations,
      useOriginGeneration: useOriginGen,
      utcNow: utcNow,
      localNow: localNow,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
    );
    return (
      candidate: rebasedCandidate,
      baseline: scopedBaseline,
      ackGeneration: effectiveAckGen,
    );
  }

  /// Selects the pre-cleanup snapshot for an untouched open bystander [item], or returns [item] when user-modified.
  static TaskItem _selectRestoredBystanderTask({
    required TaskItem item,
    required TaskItem? originTask,
    required TaskItem? storedTask,
    required bool sameQueueMembership,
    required Map<String, TaskItem> candidateTasksById,
    required Set<String> candidateDeletedTaskIds,
    required Map<String, TaskItem> storedTasksById,
    required Set<String> storedDeletedTaskIds,
    required DateTime utcNow,
  }) {
    if (originTask == null || !sameQueueMembership || item == originTask) {
      return item;
    }
    if (!_isTaskUnchangedModuloBlockCleanup(
      originTask: originTask,
      candidateTask: item,
      liveTasksById: candidateTasksById,
      deletedTaskIds: candidateDeletedTaskIds,
      utcNow: utcNow,
    )) {
      return item;
    }
    if (storedTask != null &&
        _isTaskUnchangedModuloBlockCleanup(
          originTask: originTask,
          candidateTask: storedTask,
          liveTasksById: storedTasksById,
          deletedTaskIds: storedDeletedTaskIds,
          utcNow: utcNow,
        )) {
      return storedTask;
    }
    return originTask;
  }

  /// Serializes [board] into canonical `.tdf` text.
  static String _serializeTdf(Ref ref, TaskBoard board) =>
      ref.read(tdfServiceProvider).serialize(board);

  /// Returns whether [serializedFinal] must be uploaded to WebDAV given [trimmedRemote] and [canonicalRemoteTdf].
  static bool _shouldSaveToRemote(
    WebDavConfig config, {
    required String trimmedRemote,
    required String? canonicalRemoteTdf,
    required String serializedFinal,
    required bool requireTargets,
    required bool hasCandidate,
  }) => trimmedRemote.isEmpty
      ? (requireTargets ||
            hasCandidate ||
            config.storageMode == StorageMode.both ||
            serializedFinal.trim().isNotEmpty)
      : (canonicalRemoteTdf != null
            ? canonicalRemoteTdf != serializedFinal
            : trimmedRemote != serializedFinal.trim());

  /// Strips `blocked` references targeting [retiredTaskIds] from surviving open [item] and advances `modifiedAt` when changed.
  static TaskItem _stripRetiredTaskDependencies(
    TaskItem item,
    Set<String> retiredTaskIds,
    DateTime utcNow,
  ) {
    if (item.isCompleted ||
        item.completedAt != null ||
        item.dependencies.isEmpty ||
        !_hasAnyRetiredDependency(item.dependencies, retiredTaskIds)) {
      return item;
    }
    final remainingDependencies = <TdfTaskDependency>[
      for (final dep in item.dependencies)
        if (!retiredTaskIds.contains(dep.taskId)) dep,
    ];
    final nextModifiedAt = utcNow.isAfter(item.effectiveModifiedAt)
        ? utcNow
        : item.effectiveModifiedAt;
    return item.copyWith(
      blockedByTaskIds: <String>[
        for (final dep in remainingDependencies) dep.taskId,
      ],
      dependencies: remainingDependencies,
      modifiedAt: nextModifiedAt,
    );
  }

  /// Executes the first-stage local file merge and write-back for [workspaceId].
  static Future<(TaskBoard, bool, WorkspaceSyncState)> _synchronizeLocalStage(
    Ref ref,
    WebDavConfig config, {
    required String workspaceId,
    required TaskBoard working,
    required TaskBoard? candidateOriginBoard,
    required bool hasWorking,
    required bool hasCandidate,
    required bool requireTargets,
    required TdfCleanupMode cleanupMode,
    required bool isAuthoritativeSource,
    required WorkspaceSyncState syncState,
    required _SyncResolutions resolutions,
    required DateTime utcNow,
    required DateTime localNow,
    required TdfTimeZoneContext timeZone,
    required void Function(TaskBoard mergedBoard)? onLocalStageMerged,
  }) async {
    final settingsRepository = ref.read(settingsRepositoryProvider);
    final initialRead = await ref
        .read(localFileRepositoryProvider)
        .readTdfWithDigest();
    if (!ref.mounted) {
      return (working, hasWorking, syncState);
    }
    final rawLocal = initialRead.content;
    final trimmedLocal = rawLocal.trim();
    var nextWorking = working;
    var nextHasWorking = hasWorking;
    var preStageGen = working.deletedBlock.generation;
    TaskBoard? localBoard;
    String? initialCanonicalDiskTdf;

    if (trimmedLocal.isNotEmpty) {
      localBoard = await _parseLocalOrThrow(
        ref,
        config,
        rawLocal,
        requireTargets,
        utcNow,
        localNow,
      );
      initialCanonicalDiskTdf = _serializeTdf(ref, localBoard);
      if (!nextHasWorking || localBoard.deletedBlock.generation > preStageGen) {
        preStageGen = localBoard.deletedBlock.generation;
      }
      final rawBaseline = _tryParseBaseline(
        ref,
        config,
        syncState.lastSyncedLocalTdf,
        utcNow,
        localNow,
      );
      final scoped = _scopeCandidateAndBaseline(
        candidate: nextWorking,
        hasCandidate: nextHasWorking,
        storedBaseline: rawBaseline,
        candidateOriginBoard: candidateOriginBoard,
        storedAckGeneration: syncState.acknowledgedLocalGeneration,
        utcNow: utcNow,
        localNow: localNow,
        timeZone: timeZone,
        dueLeadWindow: config.dueLeadWindow.duration,
      );
      nextWorking = TaskBoardSync.merge(
        primary: nextHasWorking ? scoped.candidate : localBoard,
        secondary: localBoard,
        baseline: scoped.baseline ?? (nextHasWorking ? null : localBoard),
        acknowledgedGeneration: scoped.baseline != null
            ? scoped.ackGeneration
            : null,
        preTransactionPrimaryGeneration: nextHasWorking
            ? working.deletedBlock.generation
            : localBoard.deletedBlock.generation,
        taskConflictResolutions: resolutions.taskConflicts,
        labelConflictResolutions: resolutions.labelConflicts,
        locationConflictResolutions: resolutions.locationConflicts,
        boundTaskConflictDecisions: resolutions.boundTaskDecisions,
        boundLabelConflictDecisions: resolutions.boundLabelDecisions,
        boundLocationConflictDecisions: resolutions.boundLocationDecisions,
        taskRecoveryResolutions: resolutions.taskRecoveries,
        labelRecoveryResolutions: resolutions.labelRecoveries,
        locationRecoveryResolutions: resolutions.locationRecoveries,
        evaluationTime: utcNow,
        localEvaluationTime: localNow,
        timeZone: timeZone,
        dueLeadWindow: config.dueLeadWindow.duration,
        cleanupMode: cleanupMode,
        pruneExpiredDeleted: isAuthoritativeSource,
        pruneExpiredCompleted: isAuthoritativeSource,
      );
      nextHasWorking = true;
    } else if (!initialRead.exists &&
        syncState.localSourceDigest != null &&
        nextHasWorking) {
      nextWorking = TaskBoardSync.merge(
        primary: nextWorking,
        secondary: TaskBoard.empty(),
        baseline: null,
        acknowledgedGeneration: null,
        preTransactionPrimaryGeneration: preStageGen,
        requireAcknowledgedGeneration: true,
        taskConflictResolutions: resolutions.taskConflicts,
        labelConflictResolutions: resolutions.labelConflicts,
        locationConflictResolutions: resolutions.locationConflicts,
        boundTaskConflictDecisions: resolutions.boundTaskDecisions,
        boundLabelConflictDecisions: resolutions.boundLabelDecisions,
        boundLocationConflictDecisions: resolutions.boundLocationDecisions,
        taskRecoveryResolutions: resolutions.taskRecoveries,
        labelRecoveryResolutions: resolutions.labelRecoveries,
        locationRecoveryResolutions: resolutions.locationRecoveries,
        evaluationTime: utcNow,
        localEvaluationTime: localNow,
        timeZone: timeZone,
        dueLeadWindow: config.dueLeadWindow.duration,
        cleanupMode: cleanupMode,
        pruneExpiredDeleted: isAuthoritativeSource,
        pruneExpiredCompleted: isAuthoritativeSource,
      );
    } else if (nextHasWorking && candidateOriginBoard != null) {
      final scopedEmpty = _scopeCandidateAndBaseline(
        candidate: nextWorking,
        hasCandidate: true,
        storedBaseline: null,
        candidateOriginBoard: candidateOriginBoard,
        storedAckGeneration: syncState.acknowledgedLocalGeneration,
        utcNow: utcNow,
        localNow: localNow,
        timeZone: timeZone,
        dueLeadWindow: config.dueLeadWindow.duration,
      );
      nextWorking = scopedEmpty.candidate;
    }

    if (trimmedLocal.isEmpty && !nextHasWorking && !requireTargets) {
      return (nextWorking, nextHasWorking, syncState);
    }
    nextWorking = TaskBoardSync.stampAndNormalize(
      nextWorking,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      dueLeadWindow: config.dueLeadWindow.duration,
      cleanupMode: cleanupMode,
      pruneExpiredDeleted: isAuthoritativeSource,
      pruneExpiredCompleted: isAuthoritativeSource,
      preTransactionGeneration: preStageGen,
    );
    final published = await _publishLocalWithCasLoop(
      ref,
      config,
      initialDigest: initialRead.exists ? initialRead.digest : null,
      initialBaseline: localBoard,
      initialAckGeneration: localBoard?.deletedBlock.generation,
      initialCanonicalDiskTdf: initialCanonicalDiskTdf,
      preTransactionGeneration: preStageGen,
      candidateBoard: nextWorking,
      resolutions: resolutions,
      requireTargets: requireTargets,
      skipWriteIfUnchanged: !requireTargets,
      cleanupMode: cleanupMode,
      isAuthoritativeSource: isAuthoritativeSource,
      utcNow: utcNow,
      localNow: localNow,
    );
    if (!ref.mounted) {
      return (published.board, nextHasWorking, syncState);
    }
    nextWorking = published.board;
    final nextSyncState = syncState.copyWith(
      lastSyncedLocalTdf: published.serialized,
      acknowledgedLocalGeneration: nextWorking.deletedBlock.generation,
      localSourceDigest: published.digest,
    );
    await settingsRepository.saveWorkspaceSyncState(workspaceId, nextSyncState);
    if (hasCandidate &&
        onLocalStageMerged != null &&
        ref.mounted &&
        ref.read(activeWorkspaceProvider).asData?.value.id == workspaceId) {
      onLocalStageMerged(nextWorking);
    }
    return (nextWorking, nextHasWorking, nextSyncState);
  }

  /// Executes the second-stage WebDAV remote merge, write-back, and local convergence.
  static Future<(TaskBoard, bool, WorkspaceSyncState)> _synchronizeRemoteStage(
    Ref ref,
    WebDavConfig config, {
    required String workspaceId,
    required TaskBoard working,
    required TaskBoard? candidateOriginBoard,
    required bool hasWorking,
    required bool hasCandidate,
    required bool hadLocalBaseline,
    required bool hadPriorLocalConvergence,
    required bool requireTargets,
    required WorkspaceSyncState syncState,
    required _SyncResolutions resolutions,
    required DateTime utcNow,
    required DateTime localNow,
    required TdfTimeZoneContext timeZone,
  }) async {
    final settingsRepository = ref.read(settingsRepositoryProvider);
    final webDavRepo = ref.read(webDavRepositoryProvider);
    webDavRepo.seedCacheIfEmpty(
      etag: syncState.remoteEtag,
      lastModified: syncState.remoteLastModified,
      content: syncState.lastSyncedRemoteTdf,
    );
    final rawRemote = await webDavRepo.fetchTdf();
    if (!ref.mounted) {
      return (working, hasWorking, syncState);
    }
    final notModified = webDavRepo.lastFetchWasNotModified;
    if (notModified) {
      AppLogger.event(LogLevel.info, LogTag.sync, 'sync.remote.not_modified');
    }
    final effectiveRawRemote = switch ((
      notModified,
      rawRemote.trim().isEmpty,
      syncState.lastSyncedRemoteTdf,
    )) {
      (true, true, final stored?) => stored,
      _ => rawRemote,
    };
    final trimmedRemote = effectiveRawRemote.trim();
    final preRemoteGen = working.deletedBlock.generation;
    final mergedRemote = _mergeRemoteSnapshot(
      ref,
      config,
      rawRemote: effectiveRawRemote,
      notModified: notModified,
      hadPriorRemoteSync: syncState.remoteSourceDigest != null,
      working: working,
      candidateOriginBoard: candidateOriginBoard,
      hasWorking: hasWorking,
      hadPriorLocalConvergence: hadPriorLocalConvergence,
      storedRemoteBaselineTdf: syncState.lastSyncedRemoteTdf,
      useBaselineBoard: hadLocalBaseline,
      acknowledgedGeneration: syncState.acknowledgedRemoteGeneration,
      preTransactionGeneration: preRemoteGen,
      resolutions: resolutions,
      utcNow: utcNow,
      localNow: localNow,
      timeZone: timeZone,
    );
    var nextWorking = mergedRemote.board;
    final nextHasWorking = mergedRemote.hasWorking;
    final canonicalRemoteTdf = mergedRemote.canonicalRemoteTdf;
    final remoteBoard = mergedRemote.remoteBoard;
    if (trimmedRemote.isEmpty && !nextHasWorking && !requireTargets) {
      return (nextWorking, nextHasWorking, syncState);
    }
    final remoteFloorGen = switch ((hasWorking, remoteBoard)) {
      (false, _) => nextWorking.deletedBlock.generation,
      (true, final remote?)
          when remote.deletedBlock.generation > preRemoteGen =>
        remote.deletedBlock.generation,
      _ => preRemoteGen,
    };
    nextWorking = TaskBoardSync.stampAndNormalize(
      nextWorking,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      dueLeadWindow: config.dueLeadWindow.duration,
      cleanupMode: TdfCleanupMode.finalStage,
      pruneExpiredDeleted: true,
      pruneExpiredCompleted: true,
      preTransactionGeneration: remoteFloorGen,
    );
    var serializedFinal = _serializeTdf(ref, nextWorking);
    var didSaveRemote = false;
    if (_shouldSaveToRemote(
      config,
      trimmedRemote: trimmedRemote,
      canonicalRemoteTdf: canonicalRemoteTdf,
      serializedFinal: serializedFinal,
      requireTargets: requireTargets,
      hasCandidate: hasCandidate,
    )) {
      didSaveRemote = true;
      final casInitialBaseline =
          remoteBoard ??
          (notModified
              ? _tryParseBaseline(
                  ref,
                  config,
                  syncState.lastSyncedRemoteTdf,
                  utcNow,
                  localNow,
                )
              : null);
      final casInitialAckGen =
          casInitialBaseline?.deletedBlock.generation ??
          (notModified ? syncState.acknowledgedRemoteGeneration : null);
      final hadExistingRemote =
          casInitialBaseline != null ||
          trimmedRemote.isNotEmpty ||
          syncState.remoteSourceDigest != null;
      (nextWorking, serializedFinal) = await _publishRemoteWithCasLoop(
        ref,
        config,
        webDavRepo: webDavRepo,
        working: nextWorking,
        initialBaseline: casInitialBaseline,
        initialAckGeneration: casInitialAckGen,
        hadExistingRemote: hadExistingRemote,
        preTransactionGeneration: remoteFloorGen,
        serializedCandidate: serializedFinal,
        resolutions: resolutions,
        utcNow: utcNow,
        localNow: localNow,
      );
      if (!ref.mounted) {
        return (nextWorking, nextHasWorking, syncState);
      }
    }
    final remoteDigest = didSaveRemote
        ? Sha256Service.hashHex(utf8.encode(serializedFinal))
        : (notModified
              ? (syncState.remoteSourceDigest ??
                    Sha256Service.hashHex(utf8.encode(effectiveRawRemote)))
              : Sha256Service.hashHex(utf8.encode(effectiveRawRemote)));
    var nextSyncState = syncState.copyWith(
      lastSyncedRemoteTdf: serializedFinal,
      acknowledgedRemoteGeneration: nextWorking.deletedBlock.generation,
      remoteSourceDigest: remoteDigest,
      remoteEtag: webDavRepo.cachedEtag,
      clearRemoteEtag: webDavRepo.cachedEtag == null,
      remoteLastModified: webDavRepo.cachedLastModified,
      clearRemoteLastModified: webDavRepo.cachedLastModified == null,
    );
    await settingsRepository.saveWorkspaceSyncState(workspaceId, nextSyncState);
    if (!ref.mounted) {
      return (nextWorking, nextHasWorking, nextSyncState);
    }
    if (config.storageMode.usesLocal &&
        (requireTargets || config.isLocalConfigured)) {
      (nextWorking, nextSyncState) = await _convergeLocalAfterRemoteStage(
        ref,
        config,
        syncState: nextSyncState,
        candidateBoard: nextWorking,
        resolutions: resolutions,
        requireTargets: requireTargets,
        utcNow: utcNow,
        localNow: localNow,
      );
    }
    return (nextWorking, nextHasWorking, nextSyncState);
  }

  /// Parses [rawBaselineTdf] into a [TaskBoard], or returns `null` when empty or malformed.
  static TaskBoard? _tryParseBaseline(
    Ref ref,
    WebDavConfig config,
    String? rawBaselineTdf,
    DateTime utcNow,
    DateTime localNow,
  ) {
    if (rawBaselineTdf == null || rawBaselineTdf.trim().isEmpty) return null;
    try {
      return _parseTdf(ref, config, rawBaselineTdf, utcNow, localNow);
    } on TdfException catch (error) {
      AppLogger.warn(
        LogTag.sync,
        'Ignoring corrupted local sync baseline (${error.kind.name})',
      );
      return null;
    }
  }
}

/// Exception thrown when a local and/or remote `.tdf` file uses an unsupported TDF version.
@immutable
class UnsupportedTdfVersionException implements Exception {
  /// Creates an [UnsupportedTdfVersionException].
  const UnsupportedTdfVersionException(
    this.message, {
    required this.version,
    this.cause,
  });

  /// Underlying [TdfException] that triggered this error.
  final TdfException? cause;

  /// Localized user-facing description recommending an application update.
  final String message;

  /// Detected unsupported TDF version token.
  final String version;

  @override
  String toString() => message;
}

/// Bundles explicit deletion conflict, bound deletion decision, and recovery resolution maps for a synchronization pass.
@immutable
class _SyncResolutions {
  /// Creates a [_SyncResolutions] bundle.
  const _SyncResolutions({
    this.taskConflicts = const {},
    this.labelConflicts = const {},
    this.locationConflicts = const {},
    this.boundTaskDecisions = const {},
    this.boundLabelDecisions = const {},
    this.boundLocationDecisions = const {},
    this.taskRecoveries = const {},
    this.labelRecoveries = const {},
    this.locationRecoveries = const {},
  });

  /// Empty resolution bundle with zero overrides.
  static const _SyncResolutions empty = _SyncResolutions();

  /// Bound task conflict decisions (`TDF-DEL-003`).
  final Map<String, TdfBoundDeletionDecision> boundLabelDecisions;

  /// Bound location conflict decisions (`TDF-DEL-003`).
  final Map<String, TdfBoundDeletionDecision> boundLocationDecisions;

  /// Bound task conflict decisions (`TDF-DEL-003`).
  final Map<String, TdfBoundDeletionDecision> boundTaskDecisions;

  /// Explicit label deletion conflict resolutions (`TDF-DEL-003`).
  final Map<String, TdfDeletionResolution> labelConflicts;

  /// Explicit label recovery resolutions (`TDF-REC-002`).
  final Map<String, TdfRecoveryResolution> labelRecoveries;

  /// Explicit location deletion conflict resolutions (`TDF-DEL-003`).
  final Map<String, TdfDeletionResolution> locationConflicts;

  /// Explicit location recovery resolutions (`TDF-REC-002`).
  final Map<String, TdfRecoveryResolution> locationRecoveries;

  /// Explicit task deletion conflict resolutions (`TDF-DEL-003`).
  final Map<String, TdfDeletionResolution> taskConflicts;

  /// Explicit task recovery resolutions (`TDF-REC-002`).
  final Map<String, TdfRecoveryResolution> taskRecoveries;

  /// Whether at least one conflict or recovery resolution map is non-empty.
  bool get hasAny =>
      taskConflicts.isNotEmpty ||
      labelConflicts.isNotEmpty ||
      locationConflicts.isNotEmpty ||
      boundTaskDecisions.isNotEmpty ||
      boundLabelDecisions.isNotEmpty ||
      boundLocationDecisions.isNotEmpty ||
      taskRecoveries.isNotEmpty ||
      labelRecoveries.isNotEmpty ||
      locationRecoveries.isNotEmpty;
}
