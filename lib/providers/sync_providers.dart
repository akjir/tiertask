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
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../l10n/storage_file_read_localization_extension.dart';
import '../models/app_workspace.dart';
import '../models/storage_file_read_status.dart';
import '../models/task_board.dart';
import '../models/task_board_sync.dart';
import '../models/task_board_sync_scoping.dart';
import '../models/task_item.dart';
import '../models/tdf_error.dart';
import '../models/tdf_sync_metadata.dart';
import '../models/tdf_timezone.dart';
import '../models/webdav_config.dart';
import '../models/workspace_sync_state.dart';
import '../repositories/local_file_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/webdav_repository.dart';
import '../services/app_logger.dart';
import '../services/sha256_service.dart';
import '../services/tdf_service.dart';
import 'config_providers.dart';
import 'sync_error_formatter.dart';
import 'workspace_providers.dart';

/// Provides per-entity `TDF-DEL-003` deletion conflict choices keyed solely by active conflict outcome.
final conflictDecisionsProvider =
    NotifierProvider.autoDispose<
      ConflictDecisionsNotifier,
      Map<String, TdfDeletionResolution>
    >(ConflictDecisionsNotifier.new);

/// Provides per-entity `TDF-REC-002` generation recovery choices keyed solely by active recovery outcome.
final recoveryDecisionsProvider =
    NotifierProvider.autoDispose<
      RecoveryDecisionsNotifier,
      Map<String, TdfRecoveryResolution>
    >(RecoveryDecisionsNotifier.new);

/// Provides the current [SyncState] for local and WebDAV persistence operations.
final syncStateProvider = NotifierProvider<SyncStateNotifier, SyncState>(
  SyncStateNotifier.new,
);

/// Manages per-entity deletion conflict choices defaulting every item to [TdfDeletionResolution.undelete].
class ConflictDecisionsNotifier
    extends Notifier<Map<String, TdfDeletionResolution>> {
  @override
  Map<String, TdfDeletionResolution> build() {
    final outcome = ref.watch(
      syncStateProvider.select((syncState) => syncState.syncOutcome),
    );
    if (outcome == null ||
        outcome.kind != TdfSyncOutcomeKind.deletionConflict) {
      return const <String, TdfDeletionResolution>{};
    }
    return Map<String, TdfDeletionResolution>.unmodifiable(
      <String, TdfDeletionResolution>{
        for (final id in outcome.conflictedTaskIds)
          resolutionDecisionKey('task', id): TdfDeletionResolution.undelete,
        for (final id in outcome.conflictedLabelIds)
          resolutionDecisionKey('label', id): TdfDeletionResolution.undelete,
        for (final id in outcome.conflictedLocationIds)
          resolutionDecisionKey('location', id): TdfDeletionResolution.undelete,
      },
    );
  }

  /// Updates the resolution [choice] for the conflicted entity identified by [decisionKey].
  void selectDecision(String decisionKey, TdfDeletionResolution choice) {
    if (state[decisionKey] == choice) {
      return;
    }
    state = Map<String, TdfDeletionResolution>.unmodifiable(
      <String, TdfDeletionResolution>{...state, decisionKey: choice},
    );
  }
}

/// Manages per-entity generation recovery choices defaulting every item to [TdfRecoveryResolution.recoverAsNew].
class RecoveryDecisionsNotifier
    extends Notifier<Map<String, TdfRecoveryResolution>> {
  @override
  Map<String, TdfRecoveryResolution> build() {
    final outcome = ref.watch(
      syncStateProvider.select((syncState) => syncState.syncOutcome),
    );
    if (outcome == null ||
        outcome.kind != TdfSyncOutcomeKind.recoveryRequired) {
      return const <String, TdfRecoveryResolution>{};
    }
    return Map<String, TdfRecoveryResolution>.unmodifiable(
      <String, TdfRecoveryResolution>{
        for (final id in outcome.ambiguousTaskIds)
          resolutionDecisionKey('task', id): TdfRecoveryResolution.recoverAsNew,
        for (final id in outcome.ambiguousLabelIds)
          resolutionDecisionKey('label', id):
              TdfRecoveryResolution.recoverAsNew,
        for (final id in outcome.ambiguousLocationIds)
          resolutionDecisionKey('location', id):
              TdfRecoveryResolution.recoverAsNew,
      },
    );
  }

  /// Updates the recovery [choice] for the ambiguous entity identified by [decisionKey].
  void selectDecision(String decisionKey, TdfRecoveryResolution choice) {
    if (state[decisionKey] == choice) {
      return;
    }
    state = Map<String, TdfRecoveryResolution>.unmodifiable(
      <String, TdfRecoveryResolution>{...state, decisionKey: choice},
    );
  }
}

/// Represents the current synchronization state for local and WebDAV storage.
@immutable
class SyncState {
  /// Creates a [SyncState] snapshot.
  const SyncState({
    this.isSyncing = false,
    this.lastSyncedAt,
    this.errorMessage,
    this.fileReadReport,
    this.hasOpenConflict = false,
    this.syncOutcome,
  });

  /// Optional error message from the most recent synchronization attempt.
  final String? errorMessage;

  /// Optional structured local/remote readability report when the latest error was a file read failure.
  final StorageFileReadReport? fileReadReport;

  /// Whether an unresolved `TdfSyncOutcomeException` synchronization conflict is active.
  final bool hasOpenConflict;

  /// Whether a synchronization request is currently in flight.
  final bool isSyncing;

  /// Timestamp of the last successful synchronization.
  final DateTime? lastSyncedAt;

  /// Optional structured conflict or recovery outcome when [hasOpenConflict] is true.
  final TdfSyncOutcomeException? syncOutcome;

  /// Returns a copy of this [SyncState] with updated fields.
  SyncState copyWith({
    bool? isSyncing,
    DateTime? lastSyncedAt,
    String? errorMessage,
    bool clearError = false,
    StorageFileReadReport? fileReadReport,
    bool clearFileReadReport = false,
    bool? hasOpenConflict,
    TdfSyncOutcomeException? syncOutcome,
    bool clearSyncOutcome = false,
  }) => SyncState(
    isSyncing: isSyncing ?? this.isSyncing,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    fileReadReport: (clearError || clearFileReadReport)
        ? null
        : (fileReadReport ?? this.fileReadReport),
    hasOpenConflict: hasOpenConflict ?? (!clearError && this.hasOpenConflict),
    syncOutcome: (clearError || clearSyncOutcome)
        ? null
        : (syncOutcome ?? this.syncOutcome),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncState &&
          other.isSyncing == isSyncing &&
          other.lastSyncedAt == lastSyncedAt &&
          other.errorMessage == errorMessage &&
          other.fileReadReport == fileReadReport &&
          other.hasOpenConflict == hasOpenConflict &&
          other.syncOutcome == syncOutcome);

  @override
  int get hashCode => Object.hash(
    isSyncing,
    lastSyncedAt,
    errorMessage,
    fileReadReport,
    hasOpenConflict,
    syncOutcome,
  );
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
  void clearError() => state = state.copyWith(
    clearError: true,
    hasOpenConflict: false,
    clearSyncOutcome: true,
  );

  /// Records an unresolved synchronization conflict with [message] and optional [outcome].
  void setConflict(String message, {TdfSyncOutcomeException? outcome}) =>
      state = state.copyWith(
        isSyncing: false,
        errorMessage: message,
        clearFileReadReport: true,
        hasOpenConflict: true,
        syncOutcome: outcome,
        clearSyncOutcome: outcome == null,
      );

  /// Records a synchronization failure with [message] and optional structured [fileReadReport].
  void setError(String message, {StorageFileReadReport? fileReadReport}) =>
      state = state.copyWith(
        isSyncing: false,
        errorMessage: message,
        fileReadReport: fileReadReport,
        clearFileReadReport: fileReadReport == null,
        hasOpenConflict: false,
        clearSyncOutcome: true,
      );

  /// Records a successful synchronization at [timestamp].
  void setSuccess(DateTime timestamp) =>
      state = SyncState(lastSyncedAt: timestamp);

  /// Marks synchronization as in progress and clears previous errors.
  void setSyncing() => state = state.copyWith(
    isSyncing: true,
    clearError: true,
    hasOpenConflict: false,
    clearSyncOutcome: true,
  );
}

/// Stateless multi-stage local and WebDAV `tdf 0.8.0` synchronization pipeline.
@immutable
class TaskSyncPipeline {
  /// Prevents instantiation of this stateless helper class.
  const TaskSyncPipeline._();

  /// Maximum number of compare-and-swap (CAS) merge retries before aborting local publication (`3`).
  static const int maxCasRetries = 3;

  /// Builds a localized [StorageFileReadException] for a local read failure, probing remote read-only when dual-storage mode is active.
  static Future<StorageFileReadException?> buildLocalReadFailureException(
    Ref ref,
    WebDavConfig config, {
    required Object localError,
    WorkspaceSyncState? syncState,
    bool requireTargets = false,
    WebDavRepository? webDavRepository,
  }) {
    final (utcNow, localNow) = resolveTimestamps(ref, null);
    final willRunRemote =
        config.storageMode.usesWebDav &&
        (requireTargets || config.isWebDavConfigured);
    return _resolveLocalReadFailure(
      ref,
      config,
      localError,
      mode: willRunRemote
          ? _LocalReadErrorMode.probeRemote
          : _LocalReadErrorMode.localOnly,
      webDavRepo: webDavRepository ?? ref.read(webDavRepositoryProvider),
      syncState: syncState,
      utcNow: utcNow,
      localNow: localNow,
    );
  }

  /// Flushes [board] to the local `.tdf` file of [workspace] before unloading when local persistence is enabled.
  static Future<void> flushOutgoingLocalBoard(
    Ref ref,
    AppWorkspace workspace,
    TaskBoard board, {
    LocalFileRepository? localRepository,
  }) async {
    final config = workspace.config;
    if (!config.storageMode.usesLocal || !config.isLocalConfigured) return;
    try {
      final (utcNow, localNow) = resolveTimestamps(ref, null);
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final LocalFileRepository pinnedLocalRepo =
          localRepository ??
          (_isActiveWorkspace(ref, workspace.id)
              ? ref.read(localFileRepositoryProvider)
              : LocalFileRepository(
                  config: config,
                  baseDirectoryPath: ref.read(
                    localStorageDirectoryPathProvider,
                  ),
                  buildProfile: ref.read(appBuildProfileProvider),
                  inMemoryStore: ref.read(inMemoryLocalStoreProvider),
                ));
      final syncState = await settingsRepo.loadWorkspaceSyncState(workspace.id);
      if (!ref.mounted) {
        return;
      }
      final isAuthoritative = !config.storageMode.usesWebDav;
      final published = await _publishLocalWithCasLoop(
        ref,
        config,
        localRepo: pinnedLocalRepo,
        initialDigest: syncState.localSourceDigest,
        initialBaseline: null,
        loadInitialBaseline: () => _tryParseBaseline(
          ref,
          config,
          syncState.lastSyncedLocalTdf,
          utcNow,
          localNow,
        ),
        initialAckGeneration: syncState.acknowledgedLocalGeneration,
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
        readErrorMode: _LocalReadErrorMode.raw,
        utcNow: utcNow,
        localNow: localNow,
      );
      final nextSyncState = syncState.copyWith(
        lastSyncedLocalTdf: published.serialized,
        acknowledgedLocalGeneration: published.board.deletedBlock.generation,
        localSourceDigest: published.digest,
      );
      await _saveSyncStateIfChanged(
        settingsRepo,
        workspace.id,
        nextSyncState,
        syncState,
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
  ) => SyncErrorFormatter.formatSyncOutcomeMessage(
    error,
    lookupAppLocalizations(ref.read(appLocaleProvider)),
  );

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

  /// Wraps [synchronize] with [SyncStateNotifier] status updates scoped to the pinned workspace.
  static Future<TaskBoard> runSyncWithStatus(
    Ref ref,
    WebDavConfig config, {
    String? workspaceId,
    LocalFileRepository? localRepository,
    WebDavRepository? webDavRepository,
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
    bool candidateMatchesLastSyncedLocal = false,
    bool isInitialLoad = false,
    bool requireTargets = false,
    void Function(TaskBoard mergedBoard)? onLocalStageMerged,
  }) async {
    final resolvedWorkspaceId =
        workspaceId ??
        ref.read(activeWorkspaceProvider).asData?.value.id ??
        (await ref.read(activeWorkspaceProvider.future)).id;
    if (!_isActiveWorkspace(ref, resolvedWorkspaceId)) {
      return candidateBoard ?? TaskBoard.empty();
    }
    final LocalFileRepository pinnedLocalRepo =
        localRepository ?? ref.read(localFileRepositoryProvider);
    final WebDavRepository pinnedWebDavRepo =
        webDavRepository ?? ref.read(webDavRepositoryProvider);
    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      final board = await synchronize(
        ref,
        config,
        workspaceId: resolvedWorkspaceId,
        localRepository: pinnedLocalRepo,
        webDavRepository: pinnedWebDavRepo,
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
        candidateMatchesLastSyncedLocal: candidateMatchesLastSyncedLocal,
        isInitialLoad: isInitialLoad,
        requireTargets: requireTargets,
        onLocalStageMerged: onLocalStageMerged,
      );
      if (!_isActiveWorkspace(ref, resolvedWorkspaceId)) {
        return board;
      }
      ref
          .read(syncStateProvider.notifier)
          .setSuccess(ref.read(clockProvider)().toUtc());
      return board;
    } on TdfSyncOutcomeException catch (error) {
      logSyncOutcomeEvent(error, config.storageMode);
      if (_isActiveWorkspace(ref, resolvedWorkspaceId)) {
        ref
            .read(syncStateProvider.notifier)
            .setConflict(formatSyncOutcomeBanner(ref, error), outcome: error);
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
      if (_isActiveWorkspace(ref, resolvedWorkspaceId)) {
        ref
            .read(syncStateProvider.notifier)
            .setError(
              error.toString(),
              fileReadReport: error is StorageFileReadException
                  ? error.report
                  : null,
            );
      }
      rethrow;
    }
  }

  /// Executes the multi-stage merge pipeline (`In-Memory <-> Local File <-> WebDAV`) pinned to the starting workspace and repositories.
  static Future<TaskBoard> synchronize(
    Ref ref,
    WebDavConfig config, {
    String? workspaceId,
    LocalFileRepository? localRepository,
    WebDavRepository? webDavRepository,
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
    bool candidateMatchesLastSyncedLocal = false,
    bool isInitialLoad = false,
    bool requireTargets = false,
    void Function(TaskBoard mergedBoard)? onLocalStageMerged,
  }) async {
    final (utcNow, localNow) = resolveTimestamps(ref, null);
    final resolvedWorkspaceId =
        workspaceId ??
        ref.read(activeWorkspaceProvider).asData?.value.id ??
        (await ref.read(activeWorkspaceProvider.future)).id;
    if (!ref.mounted) {
      return candidateBoard ?? TaskBoard.empty();
    }
    final LocalFileRepository pinnedLocalRepo =
        localRepository ?? ref.read(localFileRepositoryProvider);
    final WebDavRepository pinnedWebDavRepo =
        webDavRepository ?? ref.read(webDavRepositoryProvider);
    final settingsRepository = ref.read(settingsRepositoryProvider);
    AppLogger.event(
      LogLevel.info,
      LogTag.sync,
      'sync.start',
      fields: <String, Object?>{
        'workspace': resolvedWorkspaceId,
        'mode': config.storageMode.name,
        'initial': isInitialLoad,
      },
    );
    var syncState = await settingsRepository.loadWorkspaceSyncState(
      resolvedWorkspaceId,
    );
    var lastPersistedSyncState = syncState;
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
    var localStageBypassedCleanly = false;

    if (config.storageMode.usesLocal &&
        (requireTargets || config.isLocalConfigured)) {
      final localCleanupMode = willRunRemoteStage
          ? TdfCleanupMode.deferred
          : TdfCleanupMode.finalStage;
      (
        working,
        hasWorking,
        syncState,
        lastPersistedSyncState,
        localStageBypassedCleanly,
      ) = await _synchronizeLocalStage(
        ref,
        config,
        workspaceId: resolvedWorkspaceId,
        localRepo: pinnedLocalRepo,
        webDavRepo: pinnedWebDavRepo,
        settingsRepository: settingsRepository,
        working: working,
        candidateOriginBoard: candidateOriginBoard,
        candidateMatchesLastSyncedLocal: candidateMatchesLastSyncedLocal,
        hasWorking: hasWorking,
        hasCandidate: hasCandidate,
        requireTargets: requireTargets,
        willRunRemoteStage: willRunRemoteStage,
        cleanupMode: localCleanupMode,
        isAuthoritativeSource: !willRunRemoteStage,
        syncState: syncState,
        lastPersistedSyncState: lastPersistedSyncState,
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
          'workspace': resolvedWorkspaceId,
          'generation': working.deletedBlock.generation,
          'tasks': working.allTasks.length,
          'labels': working.labels.length,
          'locations': working.locations.length,
        },
      );
    }

    if (willRunRemoteStage) {
      (
        working,
        hasWorking,
        syncState,
        lastPersistedSyncState,
      ) = await _synchronizeRemoteStage(
        ref,
        config,
        workspaceId: resolvedWorkspaceId,
        localRepo: pinnedLocalRepo,
        webDavRepo: pinnedWebDavRepo,
        settingsRepository: settingsRepository,
        working: working,
        candidateOriginBoard: !config.storageMode.usesLocal
            ? candidateOriginBoard
            : null,
        hasWorking: hasWorking,
        hasCandidate: hasCandidate,
        hadLocalBaseline: hadLocalBaseline,
        hadPriorLocalConvergence: hadPriorLocalConvergence,
        workingMatchesRemoteBaseline:
            localStageBypassedCleanly &&
            hadPriorLocalConvergence &&
            syncState.lastSyncedRemoteTdf != null &&
            syncState.lastSyncedLocalTdf == syncState.lastSyncedRemoteTdf,
        requireTargets: requireTargets,
        syncState: syncState,
        lastPersistedSyncState: lastPersistedSyncState,
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
          'workspace': resolvedWorkspaceId,
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

    await _saveSyncStateIfChanged(
      settingsRepository,
      resolvedWorkspaceId,
      syncState,
      lastPersistedSyncState,
    );
    AppLogger.event(
      LogLevel.info,
      LogTag.sync,
      'sync.complete',
      fields: <String, Object?>{
        'workspace': resolvedWorkspaceId,
        'tasks': working.allTasks.length,
        'labels': working.labels.length,
        'locations': working.locations.length,
      },
    );
    return working;
  }

  /// Classifies a file read or parse [error] on [target] into a structured [StorageFileReadStatus].
  static StorageFileReadStatus _classifyReadError(
    StorageFileTarget target,
    Object error,
  ) {
    if (error is TdfException) {
      if (error.kind == TdfErrorKind.unsupportedVersion) {
        return StorageFileReadStatus.unsupportedVersion(
          target,
          version: error.sourceVersion ?? '?',
          cause: error,
        );
      }
      return StorageFileReadStatus.unreadable(
        target,
        detail: error.message,
        line: error.line,
        cause: error,
      );
    }
    if (error is LocalFileException) {
      return StorageFileReadStatus.unreadable(
        target,
        detail: error.message,
        cause: error,
      );
    }
    if (error is WebDavException) {
      return StorageFileReadStatus.unreadable(
        target,
        detail: error.toString(),
        cause: error,
      );
    }
    return StorageFileReadStatus.unreadable(
      target,
      detail: AppLogger.sanitize(error.toString()),
      cause: error,
    );
  }

  /// Computes or reuses the SHA-256 hex digest for [content], offloading payloads of at least [TdfService.isolateOffloadThresholdBytes] to a worker isolate.
  static Future<String> _computeTdfDigestAsync(
    String content, {
    String? knownContent,
    String? knownDigest,
    String? secondaryKnownContent,
    String? secondaryKnownDigest,
  }) async {
    if (knownDigest != null && knownContent == content) {
      return knownDigest;
    }
    if (secondaryKnownDigest != null && secondaryKnownContent == content) {
      return secondaryKnownDigest;
    }
    if (content.length >= TdfService.isolateOffloadThresholdBytes) {
      return Isolate.run(() => Sha256Service.hashHex(utf8.encode(content)));
    }
    final encoded = utf8.encode(content);
    if (encoded.length >= TdfService.isolateOffloadThresholdBytes) {
      return Isolate.run(() => Sha256Service.hashHex(encoded));
    }
    return Sha256Service.hashHex(encoded);
  }

  /// Writes the converged [candidateBoard] back to local storage after the remote WebDAV stage using the CAS-merge loop.
  static Future<(TaskBoard, WorkspaceSyncState)> _convergeLocalAfterRemoteStage(
    Ref ref,
    WebDavConfig config, {
    required LocalFileRepository localRepo,
    required WebDavRepository webDavRepo,
    required WorkspaceSyncState syncState,
    required TaskBoard candidateBoard,
    required String serializedCandidate,
    String? serializedCandidateDigest,
    required _SyncResolutions resolutions,
    required bool requireTargets,
    required DateTime utcNow,
    required DateTime localNow,
  }) async {
    final published = await _publishLocalWithCasLoop(
      ref,
      config,
      localRepo: localRepo,
      webDavRepo: webDavRepo,
      initialDigest: syncState.localSourceDigest,
      initialBaseline: null,
      loadInitialBaseline: () => _tryParseBaseline(
        ref,
        config,
        syncState.lastSyncedLocalTdf,
        utcNow,
        localNow,
      ),
      initialAckGeneration: syncState.acknowledgedLocalGeneration,
      initialCanonicalDiskTdf: syncState.lastSyncedLocalTdf,
      initialSerializedCandidate: serializedCandidate,
      initialSerializedCandidateDigest: serializedCandidateDigest,
      preTransactionGeneration: candidateBoard.deletedBlock.generation,
      candidateBoard: candidateBoard,
      resolutions: resolutions,
      requireTargets: requireTargets,
      skipWriteIfUnchanged: !requireTargets,
      cleanupMode: TdfCleanupMode.finalStage,
      isAuthoritativeSource: false,
      readErrorMode: _LocalReadErrorMode.remoteAlreadyReadable,
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

  /// Builds and logs a localized [StorageFileReadException] (or [UnsupportedTdfVersionException]) for [localStatus] and/or [remoteStatus].
  static StorageFileReadException _createFileReadException({
    required WebDavConfig config,
    StorageFileReadStatus? localStatus,
    StorageFileReadStatus? remoteStatus,
  }) {
    final report = StorageFileReadReport(
      local: localStatus,
      remote: remoteStatus,
    );
    final locale = config.language.resolveLocale(
      PlatformDispatcher.instance.locale,
    );
    final localizations = lookupAppLocalizations(locale);
    final message = localizations.formatStorageFileReadMessage(report);
    AppLogger.event(
      LogLevel.error,
      LogTag.sync,
      'sync.file_read_error',
      fields: <String, Object?>{
        'mode': config.storageMode.name,
        'scope': report.failureScope?.name,
        'local': localStatus?.state.name,
        'remote': remoteStatus?.state.name,
        if (localStatus?.unsupportedVersion != null)
          'local_version': localStatus?.unsupportedVersion,
        if (remoteStatus?.unsupportedVersion != null)
          'remote_version': remoteStatus?.unsupportedVersion,
      },
      error: report.primaryCause,
    );
    if (report.hasUnsupportedVersion) {
      return UnsupportedTdfVersionException(
        message,
        version: report.unsupportedVersionLabel ?? '?',
        report: report,
        cause: _firstUnsupportedTdfCause(report),
      );
    }
    return StorageFileReadException(
      message,
      report: report,
      cause: report.primaryCause,
    );
  }

  /// Fetches the remote `.tdf` document via [webDavRepo], wrapping any read failure into [StorageFileReadException].
  static Future<String> _fetchRemoteOrThrow(
    WebDavConfig config,
    WebDavRepository webDavRepo, {
    required bool hasLocalStage,
  }) async {
    try {
      return await webDavRepo.fetchTdf();
    } on Object catch (error) {
      throw _createFileReadException(
        config: config,
        localStatus: hasLocalStage
            ? const StorageFileReadStatus.readable(StorageFileTarget.local)
            : null,
        remoteStatus: _classifyReadError(StorageFileTarget.remote, error),
      );
    }
  }

  /// Completes Stage 1 without parsing or merging when the local file digest matches the last converged baseline and [working] is unchanged.
  static Future<(TaskBoard, bool, WorkspaceSyncState, WorkspaceSyncState, bool)>
  _finishBypassedLocalStage(
    Ref ref,
    WebDavConfig config, {
    required String workspaceId,
    required LocalFileRepository localRepo,
    required WebDavRepository webDavRepo,
    required SettingsRepository settingsRepository,
    required TaskBoard working,
    required String? initialDigest,
    required bool hasCandidate,
    required bool requireTargets,
    required TdfCleanupMode cleanupMode,
    required bool isAuthoritativeSource,
    required _LocalReadErrorMode readErrorMode,
    required WorkspaceSyncState syncState,
    required WorkspaceSyncState lastPersistedSyncState,
    required _SyncResolutions resolutions,
    required DateTime utcNow,
    required DateTime localNow,
    required TdfTimeZoneContext timeZone,
    required void Function(TaskBoard mergedBoard)? onLocalStageMerged,
  }) async {
    final normalized = TaskBoardSync.stampAndNormalizeWithStatus(
      working,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      dueLeadWindow: config.dueLeadWindow.duration,
      cleanupMode: cleanupMode,
      pruneExpiredDeleted: isAuthoritativeSource,
      pruneExpiredCompleted: isAuthoritativeSource,
      preTransactionGeneration: working.deletedBlock.generation,
    );
    if (!normalized.documentChanged) {
      if (hasCandidate &&
          onLocalStageMerged != null &&
          _isActiveWorkspace(ref, workspaceId)) {
        onLocalStageMerged(normalized.board);
      }
      return (normalized.board, true, syncState, lastPersistedSyncState, true);
    }
    final published = await _publishLocalWithCasLoop(
      ref,
      config,
      localRepo: localRepo,
      webDavRepo: webDavRepo,
      initialDigest: initialDigest,
      initialBaseline: working,
      initialAckGeneration: syncState.acknowledgedLocalGeneration,
      initialCanonicalDiskTdf: syncState.lastSyncedLocalTdf,
      preTransactionGeneration: working.deletedBlock.generation,
      candidateBoard: normalized.board,
      resolutions: resolutions,
      requireTargets: requireTargets,
      skipWriteIfUnchanged: true,
      cleanupMode: cleanupMode,
      isAuthoritativeSource: isAuthoritativeSource,
      readErrorMode: readErrorMode,
      syncStateForRemoteProbe: syncState,
      utcNow: utcNow,
      localNow: localNow,
    );
    if (!ref.mounted) {
      return (published.board, true, syncState, lastPersistedSyncState, false);
    }
    final nextSyncState = syncState.copyWith(
      lastSyncedLocalTdf: published.serialized,
      acknowledgedLocalGeneration: published.board.deletedBlock.generation,
      localSourceDigest: published.digest,
    );
    final persistedState = await _saveSyncStateIfChanged(
      settingsRepository,
      workspaceId,
      nextSyncState,
      lastPersistedSyncState,
    );
    if (hasCandidate &&
        onLocalStageMerged != null &&
        _isActiveWorkspace(ref, workspaceId)) {
      onLocalStageMerged(published.board);
    }
    return (published.board, true, nextSyncState, persistedState, false);
  }

  /// Extracts the first underlying unsupported-version [TdfException] from [report], if present.
  static TdfException? _firstUnsupportedTdfCause(StorageFileReadReport report) {
    if (report.local?.cause case final TdfException error
        when error.kind == TdfErrorKind.unsupportedVersion) {
      return error;
    }
    if (report.remote?.cause case final TdfException error
        when error.kind == TdfErrorKind.unsupportedVersion) {
      return error;
    }
    return null;
  }

  /// Returns `true` when [ref] is still mounted and [workspaceId] remains the active workspace.
  static bool _isActiveWorkspace(Ref ref, String workspaceId) {
    return ref.mounted &&
        ref.read(activeWorkspaceProvider).asData?.value.id == workspaceId;
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
    return _mergeBoards(
      primary: candidate,
      secondary: TaskBoard.empty(),
      baseline: null,
      acknowledgedGeneration: hasLiveEntities ? null : acknowledgedGeneration,
      preTransactionPrimaryGeneration: preTransactionGeneration,
      requireAcknowledgedGeneration: true,
      resolutions: resolutions,
      utcNow: utcNow,
      localNow: localNow,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
    );
  }

  /// Merges [primary] and [secondary] via [TaskBoardSync.merge] using shared [resolutions] and evaluation parameters.
  static TaskBoard _mergeBoards({
    required TaskBoard primary,
    required TaskBoard secondary,
    required TaskBoard? baseline,
    required int? acknowledgedGeneration,
    required int preTransactionPrimaryGeneration,
    bool requireAcknowledgedGeneration = false,
    required _SyncResolutions resolutions,
    required DateTime utcNow,
    required DateTime localNow,
    required TdfTimeZoneContext timeZone,
    required Duration? dueLeadWindow,
    TdfCleanupMode cleanupMode = TdfCleanupMode.finalStage,
    bool pruneExpired = true,
  }) => TaskBoardSync.merge(
    primary: primary,
    secondary: secondary,
    baseline: baseline,
    acknowledgedGeneration: acknowledgedGeneration,
    preTransactionPrimaryGeneration: preTransactionPrimaryGeneration,
    requireAcknowledgedGeneration: requireAcknowledgedGeneration,
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
    pruneExpiredDeleted: pruneExpired,
    pruneExpiredCompleted: pruneExpired,
  );

  /// Parses [rawRemote] and merges it with [working] against [storedRemoteBaselineTdf], or reuses [working] on `HTTP 304 Not Modified`.
  static Future<
    ({
      TaskBoard board,
      bool hasWorking,
      String? canonicalRemoteTdf,
      TaskBoard? remoteBoard,
      bool bypassedMerge,
    })
  >
  _mergeRemoteSnapshot(
    Ref ref,
    WebDavConfig config, {
    required String rawRemote,
    required bool notModified,
    required bool hadPriorRemoteSync,
    required bool hasLocalStage,
    required TaskBoard working,
    required TaskBoard? candidateOriginBoard,
    required bool hasWorking,
    required bool hadPriorLocalConvergence,
    required String? storedRemoteBaselineTdf,
    required TaskBoard? preParsedRemoteBaseline,
    required bool useBaselineBoard,
    required int? acknowledgedGeneration,
    required int preTransactionGeneration,
    required _SyncResolutions resolutions,
    required DateTime utcNow,
    required DateTime localNow,
    required TdfTimeZoneContext timeZone,
  }) async {
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
          bypassedMerge: true,
        );
      }
      if (!hasWorking) {
        if (trimmedRemote.isNotEmpty) {
          final parsed = await _parseRemoteOrThrow(
            ref,
            config,
            rawRemote,
            hasLocalStage: hasLocalStage,
            utcNow: utcNow,
            localNow: localNow,
          );
          return (
            board: parsed,
            hasWorking: true,
            canonicalRemoteTdf: baselineTdf,
            remoteBoard: parsed,
            bypassedMerge: false,
          );
        }
        return (
          board: working,
          hasWorking: false,
          canonicalRemoteTdf: null,
          remoteBoard: null,
          bypassedMerge: false,
        );
      }
    }
    if (trimmedRemote.isEmpty) {
      final scopedEmpty = TaskBoardSyncScoping.scopeCandidateAndBaseline(
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
        bypassedMerge: false,
      );
    }
    final remoteBoard = await _parseRemoteOrThrow(
      ref,
      config,
      rawRemote,
      hasLocalStage: hasLocalStage,
      utcNow: utcNow,
      localNow: localNow,
    );
    if (!ref.mounted) {
      return (
        board: working,
        hasWorking: hasWorking,
        canonicalRemoteTdf: null,
        remoteBoard: remoteBoard,
        bypassedMerge: false,
      );
    }
    final canonicalRemote = notModified ? baselineTdf : null;
    final parsedRemoteBaseline =
        preParsedRemoteBaseline ??
        await _tryParseBaseline(
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
    final scoped = TaskBoardSyncScoping.scopeCandidateAndBaseline(
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
    final merged = _mergeBoards(
      primary: hasWorking ? scoped.candidate : remoteBoard,
      secondary: remoteBoard,
      baseline: scoped.baseline ?? (hasWorking ? null : remoteBoard),
      acknowledgedGeneration: scoped.baseline != null
          ? scoped.ackGeneration
          : effectiveAckGen,
      preTransactionPrimaryGeneration: hasWorking
          ? preTransactionGeneration
          : remoteBoard.deletedBlock.generation,
      resolutions: resolutions,
      utcNow: utcNow,
      localNow: localNow,
      timeZone: timeZone,
      dueLeadWindow: config.dueLeadWindow.duration,
    );
    return (
      board: merged,
      hasWorking: true,
      canonicalRemoteTdf: canonicalRemote,
      remoteBoard: remoteBoard,
      bypassedMerge: false,
    );
  }

  /// Parses [rawLocal], wrapping any read or format error into [StorageFileReadException] according to [readErrorMode].
  static Future<TaskBoard?> _parseLocalOrThrow(
    Ref ref,
    WebDavConfig config,
    String rawLocal, {
    required _LocalReadErrorMode readErrorMode,
    WebDavRepository? webDavRepo,
    WorkspaceSyncState? syncState,
    required DateTime utcNow,
    required DateTime localNow,
  }) async {
    try {
      return await _parseTdf(ref, config, rawLocal, utcNow, localNow);
    } on Object catch (error) {
      if (readErrorMode == _LocalReadErrorMode.raw) {
        rethrow;
      }
      final exception = await _resolveLocalReadFailure(
        ref,
        config,
        error,
        mode: readErrorMode,
        webDavRepo: webDavRepo,
        syncState: syncState,
        utcNow: utcNow,
        localNow: localNow,
      );
      if (exception == null) {
        return null;
      }
      throw exception;
    }
  }

  /// Parses [rawRemote], wrapping any read or format error into [StorageFileReadException].
  static Future<TaskBoard> _parseRemoteOrThrow(
    Ref ref,
    WebDavConfig config,
    String rawRemote, {
    required bool hasLocalStage,
    required DateTime utcNow,
    required DateTime localNow,
  }) async {
    try {
      return await _parseTdf(ref, config, rawRemote, utcNow, localNow);
    } on Object catch (error) {
      throw _createFileReadException(
        config: config,
        localStatus: hasLocalStage
            ? const StorageFileReadStatus.readable(StorageFileTarget.local)
            : null,
        remoteStatus: _classifyReadError(StorageFileTarget.remote, error),
      );
    }
  }

  /// Parses [rawTdf] without 6-tier evaluation for intermediate merge passes using [TdfService.parseAsync].
  static Future<TaskBoard> _parseTdf(
    Ref ref,
    WebDavConfig config,
    String rawTdf,
    DateTime utcNow,
    DateTime localNow,
  ) => ref
      .read(tdfServiceProvider)
      .parseAsync(
        rawTdf,
        evaluationTime: utcNow,
        localEvaluationTime: localNow,
        timeZone: resolveWorkspaceTimeZone(config, utcNow),
        dueLeadWindow: config.dueLeadWindow.duration,
        evaluateTiers: false,
      );

  /// Probes the remote WebDAV `.tdf` file read-only to report whether it is readable or unreadable alongside a local failure.
  static Future<StorageFileReadStatus?> _probeRemoteReadStatus(
    Ref ref,
    WebDavConfig config, {
    WebDavRepository? webDavRepo,
    WorkspaceSyncState? syncState,
    required DateTime utcNow,
    required DateTime localNow,
  }) async {
    if (!ref.mounted) {
      return null;
    }
    try {
      final WebDavRepository resolvedWebDavRepo =
          webDavRepo ?? ref.read(webDavRepositoryProvider);
      if (syncState != null) {
        resolvedWebDavRepo.seedCacheIfEmpty(
          etag: syncState.remoteEtag,
          lastModified: syncState.remoteLastModified,
          content: syncState.lastSyncedRemoteTdf,
        );
      }
      final rawRemote = await resolvedWebDavRepo.fetchTdf();
      if (!ref.mounted) {
        return null;
      }
      final notModified = resolvedWebDavRepo.lastFetchWasNotModified;
      final effectiveRawRemote = switch ((
        notModified,
        rawRemote.trim().isEmpty,
        syncState?.lastSyncedRemoteTdf,
      )) {
        (true, true, final stored?) => stored,
        _ => rawRemote,
      };
      if (effectiveRawRemote.trim().isNotEmpty) {
        await _parseTdf(ref, config, effectiveRawRemote, utcNow, localNow);
      }
      return const StorageFileReadStatus.readable(StorageFileTarget.remote);
    } on Object catch (error) {
      return _classifyReadError(StorageFileTarget.remote, error);
    }
  }

  /// Executes the guarded local publication compare-and-swap (CAS) merge loop while holding `withExclusiveTargetLock` (`TDF-PUB-002`, `TDF-PUB-003`).
  static Future<({TaskBoard board, String serialized, String? digest})>
  _publishLocalWithCasLoop(
    Ref ref,
    WebDavConfig config, {
    required LocalFileRepository localRepo,
    WebDavRepository? webDavRepo,
    required String? initialDigest,
    required TaskBoard? initialBaseline,
    Future<TaskBoard?> Function()? loadInitialBaseline,
    required int? initialAckGeneration,
    required String? initialCanonicalDiskTdf,
    Future<String> Function()? resolveInitialCanonicalDiskTdf,
    String? initialSerializedCandidate,
    String? initialSerializedCandidateDigest,
    required int preTransactionGeneration,
    required TaskBoard candidateBoard,
    required _SyncResolutions resolutions,
    required bool requireTargets,
    required bool skipWriteIfUnchanged,
    required TdfCleanupMode cleanupMode,
    required bool isAuthoritativeSource,
    required _LocalReadErrorMode readErrorMode,
    WorkspaceSyncState? syncStateForRemoteProbe,
    required DateTime utcNow,
    required DateTime localNow,
  }) {
    return localRepo.withExclusiveTargetLock(() async {
      var loopDigest = initialDigest;
      var loopB = initialBaseline;
      var baselineResolved =
          initialBaseline != null || loadInitialBaseline == null;
      var loopAckGen = initialAckGeneration;
      var loopL = candidateBoard;
      for (var attempt = 0; attempt <= maxCasRetries; attempt++) {
        final disk = await _readLocalSnapshotOrThrow(
          ref,
          config,
          localRepo,
          readErrorMode: readErrorMode,
          webDavRepo: webDavRepo,
          syncState: syncStateForRemoteProbe,
          utcNow: utcNow,
          localNow: localNow,
        );
        if (disk == null || !ref.mounted) {
          return (board: loopL, serialized: '', digest: loopDigest);
        }
        final digestMatches =
            (!disk.exists && loopDigest == null) ||
            (disk.exists && disk.digest == loopDigest);
        if (digestMatches) {
          final usedInitialCandidate =
              attempt == 0 && initialSerializedCandidate != null;
          final serialized = usedInitialCandidate
              ? initialSerializedCandidate
              : await _serializeTdf(ref, loopL);
          if (!ref.mounted) {
            return (board: loopL, serialized: serialized, digest: loopDigest);
          }
          var alreadyMatchesDisk =
              disk.exists && disk.content.trim() == serialized.trim();
          if (!alreadyMatchesDisk && disk.exists && attempt == 0) {
            final canonicalDisk =
                initialCanonicalDiskTdf ??
                await resolveInitialCanonicalDiskTdf?.call();
            alreadyMatchesDisk =
                canonicalDisk != null && canonicalDisk == serialized;
          }
          if (attempt > 0 || !skipWriteIfUnchanged || !alreadyMatchesDisk) {
            await localRepo.saveTdf(serialized);
            final savedDigest = await _computeTdfDigestAsync(
              serialized,
              knownContent:
                  usedInitialCandidate &&
                      initialSerializedCandidateDigest != null
                  ? initialSerializedCandidate
                  : (disk.exists && disk.digest != null ? disk.content : null),
              knownDigest:
                  usedInitialCandidate &&
                      initialSerializedCandidateDigest != null
                  ? initialSerializedCandidateDigest
                  : (disk.exists ? disk.digest : null),
            );
            return (board: loopL, serialized: serialized, digest: savedDigest);
          }
          return (board: loopL, serialized: serialized, digest: loopDigest);
        }
        if (attempt >= maxCasRetries) {
          throw const LocalFileException(
            'Local file was modified concurrently and exceeded maximum CAS merge retries (3).',
          );
        }
        if (!baselineResolved) {
          baselineResolved = true;
          loopB = await loadInitialBaseline?.call();
          if (!ref.mounted) {
            return (board: loopL, serialized: '', digest: loopDigest);
          }
          if (loopB == null) {
            loopAckGen = null;
          }
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
          cleanupMode: cleanupMode,
          isAuthoritativeSource: isAuthoritativeSource,
          readErrorMode: readErrorMode,
          webDavRepo: webDavRepo,
          syncStateForRemoteProbe: syncStateForRemoteProbe,
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
    required bool hasLocalStage,
    required TaskBoard working,
    required TaskBoard? initialBaseline,
    Future<TaskBoard?> Function()? loadInitialBaseline,
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
    var baselineResolved =
        initialBaseline != null || loadInitialBaseline == null;
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
        if (!baselineResolved) {
          baselineResolved = true;
          loopBaseline = await loadInitialBaseline?.call();
          if (!ref.mounted) {
            return (loopWorking, currentSerialized);
          }
          if (loopBaseline != null) {
            loopAckGeneration = loopBaseline.deletedBlock.generation;
            loopHadExistingRemote = true;
          }
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
          hasLocalStage: hasLocalStage,
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

  /// Reads the local `.tdf` file via [localRepo], wrapping read errors into [StorageFileReadException] per [readErrorMode].
  static Future<({String content, String? digest, bool exists})?>
  _readLocalSnapshotOrThrow(
    Ref ref,
    WebDavConfig config,
    LocalFileRepository localRepo, {
    required _LocalReadErrorMode readErrorMode,
    WebDavRepository? webDavRepo,
    WorkspaceSyncState? syncState,
    required DateTime utcNow,
    required DateTime localNow,
  }) async {
    try {
      return await localRepo.readTdfWithDigest();
    } on Object catch (error) {
      if (readErrorMode == _LocalReadErrorMode.raw) {
        rethrow;
      }
      final exception = await _resolveLocalReadFailure(
        ref,
        config,
        error,
        mode: readErrorMode,
        webDavRepo: webDavRepo,
        syncState: syncState,
        utcNow: utcNow,
        localNow: localNow,
      );
      if (exception == null) {
        return null;
      }
      throw exception;
    }
  }

  /// Resolves a local file read or parse [localError] into a [StorageFileReadException] according to [mode].
  static Future<StorageFileReadException?> _resolveLocalReadFailure(
    Ref ref,
    WebDavConfig config,
    Object localError, {
    required _LocalReadErrorMode mode,
    WebDavRepository? webDavRepo,
    WorkspaceSyncState? syncState,
    required DateTime utcNow,
    required DateTime localNow,
  }) async {
    final localStatus = _classifyReadError(StorageFileTarget.local, localError);
    switch (mode) {
      case _LocalReadErrorMode.raw:
      case _LocalReadErrorMode.localOnly:
        return _createFileReadException(
          config: config,
          localStatus: localStatus,
        );
      case _LocalReadErrorMode.remoteAlreadyReadable:
        return _createFileReadException(
          config: config,
          localStatus: localStatus,
          remoteStatus: const StorageFileReadStatus.readable(
            StorageFileTarget.remote,
          ),
        );
      case _LocalReadErrorMode.probeRemote:
        final remoteStatus = await _probeRemoteReadStatus(
          ref,
          config,
          webDavRepo: webDavRepo,
          syncState: syncState,
          utcNow: utcNow,
          localNow: localNow,
        );
        if (remoteStatus == null || !ref.mounted) {
          return null;
        }
        return _createFileReadException(
          config: config,
          localStatus: localStatus,
          remoteStatus: remoteStatus,
        );
    }
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
    required TdfCleanupMode cleanupMode,
    required bool isAuthoritativeSource,
    required _LocalReadErrorMode readErrorMode,
    WebDavRepository? webDavRepo,
    WorkspaceSyncState? syncStateForRemoteProbe,
    required DateTime utcNow,
    required DateTime localNow,
  }) async {
    final timeZone = resolveWorkspaceTimeZone(config, utcNow);
    final dueLeadWindow = config.dueLeadWindow.duration;
    if (!disk.exists || disk.content.trim().isEmpty) {
      final wasRemoved = !disk.exists && loopDigest != null;
      final mergedEmpty = _mergeBoards(
        primary: loopL,
        secondary: TaskBoard.empty(),
        baseline: wasRemoved ? null : loopB,
        acknowledgedGeneration: wasRemoved ? null : loopAckGen,
        preTransactionPrimaryGeneration: preTransactionGeneration,
        requireAcknowledgedGeneration: true,
        resolutions: resolutions,
        utcNow: utcNow,
        localNow: localNow,
        timeZone: timeZone,
        dueLeadWindow: dueLeadWindow,
        cleanupMode: cleanupMode,
        pruneExpired: isAuthoritativeSource,
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
      readErrorMode: readErrorMode,
      webDavRepo: webDavRepo,
      syncState: syncStateForRemoteProbe,
      utcNow: utcNow,
      localNow: localNow,
    );
    if (diskBoard == null || !ref.mounted) {
      return (loopB, loopAckGen, loopL, loopDigest);
    }
    final diskGen = diskBoard.deletedBlock.generation;
    final floorGen = preTransactionGeneration >= diskGen
        ? preTransactionGeneration
        : diskGen;
    final merged = _mergeBoards(
      primary: loopL,
      secondary: diskBoard,
      baseline: loopB,
      acknowledgedGeneration: loopAckGen ?? loopB?.deletedBlock.generation,
      preTransactionPrimaryGeneration: preTransactionGeneration,
      resolutions: resolutions,
      utcNow: utcNow,
      localNow: localNow,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      cleanupMode: cleanupMode,
      pruneExpired: isAuthoritativeSource,
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
    required bool hasLocalStage,
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
    final retryRaw = await _fetchRemoteOrThrow(
      config,
      webDavRepo,
      hasLocalStage: hasLocalStage,
    );
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
        preTransactionGeneration: preTransactionGeneration,
      );
      return (null, null, normalized, await _serializeTdf(ref, normalized));
    }
    final retryRemote = await _parseRemoteOrThrow(
      ref,
      config,
      retryRaw,
      hasLocalStage: hasLocalStage,
      utcNow: utcNow,
      localNow: localNow,
    );
    if (!ref.mounted) {
      return (loopBaseline, loopAckGeneration, loopWorking, '');
    }
    final remoteGen = retryRemote.deletedBlock.generation;
    final floorGen = preTransactionGeneration >= remoteGen
        ? preTransactionGeneration
        : remoteGen;
    final merged = _mergeBoards(
      primary: loopWorking,
      secondary: retryRemote,
      baseline: loopBaseline,
      acknowledgedGeneration: effectiveAckGen,
      preTransactionPrimaryGeneration: preTransactionGeneration,
      resolutions: resolutions,
      utcNow: utcNow,
      localNow: localNow,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
    );
    final normalized = TaskBoardSync.stampAndNormalize(
      merged,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      preTransactionGeneration: floorGen,
    );
    return (
      retryRemote,
      remoteGen,
      normalized,
      await _serializeTdf(ref, normalized),
    );
  }

  /// Persists [nextSyncState] for [workspaceId] via [settingsRepository] only when it differs from [lastPersistedSyncState].
  static Future<WorkspaceSyncState> _saveSyncStateIfChanged(
    SettingsRepository settingsRepository,
    String workspaceId,
    WorkspaceSyncState nextSyncState,
    WorkspaceSyncState lastPersistedSyncState,
  ) async {
    if (nextSyncState == lastPersistedSyncState) {
      return lastPersistedSyncState;
    }
    await settingsRepository.saveWorkspaceSyncState(workspaceId, nextSyncState);
    return nextSyncState;
  }

  /// Serializes [board] into canonical `.tdf` text via [TdfService.serializeAsync].
  static Future<String> _serializeTdf(Ref ref, TaskBoard board) =>
      ref.read(tdfServiceProvider).serializeAsync(board);

  /// Returns whether [serializedFinal] must be uploaded to WebDAV given [trimmedRemote], [canonicalRemoteTdf], and lazy [remoteBoard] canonicalization.
  static Future<bool> _shouldSaveToRemote(
    Ref ref,
    WebDavConfig config, {
    required String trimmedRemote,
    required String? canonicalRemoteTdf,
    required TaskBoard? remoteBoard,
    required String serializedFinal,
    required bool requireTargets,
    required bool hasCandidate,
  }) async {
    if (trimmedRemote.isEmpty) {
      return requireTargets ||
          hasCandidate ||
          config.storageMode == StorageMode.both ||
          serializedFinal.trim().isNotEmpty;
    }
    if (canonicalRemoteTdf != null) {
      return canonicalRemoteTdf != serializedFinal;
    }
    if (trimmedRemote == serializedFinal.trim()) {
      return false;
    }
    if (remoteBoard != null) {
      return (await _serializeTdf(ref, remoteBoard)) != serializedFinal;
    }
    return true;
  }

  /// Executes the first-stage local file merge and write-back for [workspaceId].
  static Future<(TaskBoard, bool, WorkspaceSyncState, WorkspaceSyncState, bool)>
  _synchronizeLocalStage(
    Ref ref,
    WebDavConfig config, {
    required String workspaceId,
    required LocalFileRepository localRepo,
    required WebDavRepository webDavRepo,
    required SettingsRepository settingsRepository,
    required TaskBoard working,
    required TaskBoard? candidateOriginBoard,
    required bool candidateMatchesLastSyncedLocal,
    required bool hasWorking,
    required bool hasCandidate,
    required bool requireTargets,
    required bool willRunRemoteStage,
    required TdfCleanupMode cleanupMode,
    required bool isAuthoritativeSource,
    required WorkspaceSyncState syncState,
    required WorkspaceSyncState lastPersistedSyncState,
    required _SyncResolutions resolutions,
    required DateTime utcNow,
    required DateTime localNow,
    required TdfTimeZoneContext timeZone,
    required void Function(TaskBoard mergedBoard)? onLocalStageMerged,
  }) async {
    final readErrorMode = willRunRemoteStage
        ? _LocalReadErrorMode.probeRemote
        : _LocalReadErrorMode.localOnly;
    final initialRead = await _readLocalSnapshotOrThrow(
      ref,
      config,
      localRepo,
      readErrorMode: readErrorMode,
      webDavRepo: webDavRepo,
      syncState: syncState,
      utcNow: utcNow,
      localNow: localNow,
    );
    if (initialRead == null || !ref.mounted) {
      return (working, hasWorking, syncState, lastPersistedSyncState, false);
    }
    final localDigestMatchesBaseline =
        initialRead.exists &&
        initialRead.digest != null &&
        initialRead.digest == syncState.localSourceDigest &&
        syncState.lastSyncedLocalTdf != null;
    final canBypassLocalMerge =
        localDigestMatchesBaseline &&
        hasWorking &&
        !resolutions.hasAny &&
        candidateOriginBoard == null &&
        !requireTargets &&
        candidateMatchesLastSyncedLocal;
    if (canBypassLocalMerge) {
      return _finishBypassedLocalStage(
        ref,
        config,
        workspaceId: workspaceId,
        localRepo: localRepo,
        webDavRepo: webDavRepo,
        settingsRepository: settingsRepository,
        working: working,
        initialDigest: initialRead.digest,
        hasCandidate: hasCandidate,
        requireTargets: requireTargets,
        cleanupMode: cleanupMode,
        isAuthoritativeSource: isAuthoritativeSource,
        readErrorMode: readErrorMode,
        syncState: syncState,
        lastPersistedSyncState: lastPersistedSyncState,
        resolutions: resolutions,
        utcNow: utcNow,
        localNow: localNow,
        timeZone: timeZone,
        onLocalStageMerged: onLocalStageMerged,
      );
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
        readErrorMode: readErrorMode,
        webDavRepo: webDavRepo,
        syncState: syncState,
        utcNow: utcNow,
        localNow: localNow,
      );
      if (localBoard == null || !ref.mounted) {
        return (working, hasWorking, syncState, lastPersistedSyncState, false);
      }
      if (localDigestMatchesBaseline) {
        initialCanonicalDiskTdf = syncState.lastSyncedLocalTdf;
      }
      if (!nextHasWorking || localBoard.deletedBlock.generation > preStageGen) {
        preStageGen = localBoard.deletedBlock.generation;
      }
      final rawBaseline = localDigestMatchesBaseline
          ? localBoard
          : await _tryParseBaseline(
              ref,
              config,
              syncState.lastSyncedLocalTdf,
              utcNow,
              localNow,
            );
      if (!ref.mounted) {
        return (working, hasWorking, syncState, lastPersistedSyncState, false);
      }
      final scoped = TaskBoardSyncScoping.scopeCandidateAndBaseline(
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
      nextWorking = _mergeBoards(
        primary: nextHasWorking ? scoped.candidate : localBoard,
        secondary: localBoard,
        baseline: scoped.baseline ?? (nextHasWorking ? null : localBoard),
        acknowledgedGeneration: scoped.baseline != null
            ? scoped.ackGeneration
            : null,
        preTransactionPrimaryGeneration: nextHasWorking
            ? working.deletedBlock.generation
            : localBoard.deletedBlock.generation,
        resolutions: resolutions,
        utcNow: utcNow,
        localNow: localNow,
        timeZone: timeZone,
        dueLeadWindow: config.dueLeadWindow.duration,
        cleanupMode: cleanupMode,
        pruneExpired: isAuthoritativeSource,
      );
      nextHasWorking = true;
    } else if (!initialRead.exists &&
        syncState.localSourceDigest != null &&
        nextHasWorking) {
      nextWorking = _mergeBoards(
        primary: nextWorking,
        secondary: TaskBoard.empty(),
        baseline: null,
        acknowledgedGeneration: null,
        preTransactionPrimaryGeneration: preStageGen,
        requireAcknowledgedGeneration: true,
        resolutions: resolutions,
        utcNow: utcNow,
        localNow: localNow,
        timeZone: timeZone,
        dueLeadWindow: config.dueLeadWindow.duration,
        cleanupMode: cleanupMode,
        pruneExpired: isAuthoritativeSource,
      );
    } else if (nextHasWorking && candidateOriginBoard != null) {
      final scopedEmpty = TaskBoardSyncScoping.scopeCandidateAndBaseline(
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
      return (
        nextWorking,
        nextHasWorking,
        syncState,
        lastPersistedSyncState,
        false,
      );
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
    final parsedLocalBoard = localBoard;
    final published = await _publishLocalWithCasLoop(
      ref,
      config,
      localRepo: localRepo,
      webDavRepo: webDavRepo,
      initialDigest: initialRead.exists ? initialRead.digest : null,
      initialBaseline: parsedLocalBoard,
      initialAckGeneration: parsedLocalBoard?.deletedBlock.generation,
      initialCanonicalDiskTdf: initialCanonicalDiskTdf,
      resolveInitialCanonicalDiskTdf: parsedLocalBoard != null
          ? () => _serializeTdf(ref, parsedLocalBoard)
          : null,
      preTransactionGeneration: preStageGen,
      candidateBoard: nextWorking,
      resolutions: resolutions,
      requireTargets: requireTargets,
      skipWriteIfUnchanged: !requireTargets,
      cleanupMode: cleanupMode,
      isAuthoritativeSource: isAuthoritativeSource,
      readErrorMode: readErrorMode,
      syncStateForRemoteProbe: syncState,
      utcNow: utcNow,
      localNow: localNow,
    );
    if (!ref.mounted) {
      return (
        published.board,
        nextHasWorking,
        syncState,
        lastPersistedSyncState,
        false,
      );
    }
    nextWorking = published.board;
    final nextSyncState = syncState.copyWith(
      lastSyncedLocalTdf: published.serialized,
      acknowledgedLocalGeneration: nextWorking.deletedBlock.generation,
      localSourceDigest: published.digest,
    );
    final persistedState = await _saveSyncStateIfChanged(
      settingsRepository,
      workspaceId,
      nextSyncState,
      lastPersistedSyncState,
    );
    if (hasCandidate &&
        onLocalStageMerged != null &&
        _isActiveWorkspace(ref, workspaceId)) {
      onLocalStageMerged(nextWorking);
    }
    return (nextWorking, nextHasWorking, nextSyncState, persistedState, false);
  }

  /// Executes the second-stage WebDAV remote merge, write-back, and local convergence.
  static Future<(TaskBoard, bool, WorkspaceSyncState, WorkspaceSyncState)>
  _synchronizeRemoteStage(
    Ref ref,
    WebDavConfig config, {
    required String workspaceId,
    required LocalFileRepository localRepo,
    required WebDavRepository webDavRepo,
    required SettingsRepository settingsRepository,
    required TaskBoard working,
    required TaskBoard? candidateOriginBoard,
    required bool hasWorking,
    required bool hasCandidate,
    required bool hadLocalBaseline,
    required bool hadPriorLocalConvergence,
    required bool workingMatchesRemoteBaseline,
    required bool requireTargets,
    required WorkspaceSyncState syncState,
    required WorkspaceSyncState lastPersistedSyncState,
    required _SyncResolutions resolutions,
    required DateTime utcNow,
    required DateTime localNow,
    required TdfTimeZoneContext timeZone,
  }) async {
    final hasLocalStage =
        config.storageMode.usesLocal &&
        (requireTargets || config.isLocalConfigured);
    webDavRepo.seedCacheIfEmpty(
      etag: syncState.remoteEtag,
      lastModified: syncState.remoteLastModified,
      content: syncState.lastSyncedRemoteTdf,
    );
    final rawRemote = await _fetchRemoteOrThrow(
      config,
      webDavRepo,
      hasLocalStage: hasLocalStage,
    );
    if (!ref.mounted) {
      return (working, hasWorking, syncState, lastPersistedSyncState);
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
    final mergedRemote = await _mergeRemoteSnapshot(
      ref,
      config,
      rawRemote: effectiveRawRemote,
      notModified: notModified,
      hadPriorRemoteSync: syncState.remoteSourceDigest != null,
      hasLocalStage: hasLocalStage,
      working: working,
      candidateOriginBoard: candidateOriginBoard,
      hasWorking: hasWorking,
      hadPriorLocalConvergence: hadPriorLocalConvergence,
      storedRemoteBaselineTdf: syncState.lastSyncedRemoteTdf,
      preParsedRemoteBaseline: workingMatchesRemoteBaseline ? working : null,
      useBaselineBoard: hadLocalBaseline,
      acknowledgedGeneration: syncState.acknowledgedRemoteGeneration,
      preTransactionGeneration: preRemoteGen,
      resolutions: resolutions,
      utcNow: utcNow,
      localNow: localNow,
      timeZone: timeZone,
    );
    if (!ref.mounted) {
      return (working, hasWorking, syncState, lastPersistedSyncState);
    }
    var nextWorking = mergedRemote.board;
    final nextHasWorking = mergedRemote.hasWorking;
    final canonicalRemoteTdf = mergedRemote.canonicalRemoteTdf;
    final remoteBoard = mergedRemote.remoteBoard;
    if (trimmedRemote.isEmpty && !nextHasWorking && !requireTargets) {
      return (nextWorking, nextHasWorking, syncState, lastPersistedSyncState);
    }
    final remoteFloorGen = switch ((hasWorking, remoteBoard)) {
      (false, _) => nextWorking.deletedBlock.generation,
      (true, final remote?)
          when remote.deletedBlock.generation > preRemoteGen =>
        remote.deletedBlock.generation,
      _ => preRemoteGen,
    };
    final normalized = TaskBoardSync.stampAndNormalizeWithStatus(
      nextWorking,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      dueLeadWindow: config.dueLeadWindow.duration,
      preTransactionGeneration: remoteFloorGen,
    );
    nextWorking = normalized.board;
    final reusableLocalTdf =
        mergedRemote.bypassedMerge &&
            !normalized.documentChanged &&
            hasLocalStage
        ? syncState.lastSyncedLocalTdf
        : null;
    var serializedFinal =
        reusableLocalTdf ?? await _serializeTdf(ref, nextWorking);
    if (!ref.mounted) {
      return (nextWorking, nextHasWorking, syncState, lastPersistedSyncState);
    }
    var didSaveRemote = false;
    if (await _shouldSaveToRemote(
      ref,
      config,
      trimmedRemote: trimmedRemote,
      canonicalRemoteTdf: canonicalRemoteTdf,
      remoteBoard: remoteBoard,
      serializedFinal: serializedFinal,
      requireTargets: requireTargets,
      hasCandidate: hasCandidate,
    )) {
      if (!ref.mounted) {
        return (nextWorking, nextHasWorking, syncState, lastPersistedSyncState);
      }
      didSaveRemote = true;
      final casInitialAckGen =
          remoteBoard?.deletedBlock.generation ??
          (notModified ? syncState.acknowledgedRemoteGeneration : null);
      final hadExistingRemote =
          remoteBoard != null ||
          trimmedRemote.isNotEmpty ||
          syncState.remoteSourceDigest != null;
      (nextWorking, serializedFinal) = await _publishRemoteWithCasLoop(
        ref,
        config,
        webDavRepo: webDavRepo,
        hasLocalStage: hasLocalStage,
        working: nextWorking,
        initialBaseline: remoteBoard,
        loadInitialBaseline: remoteBoard == null && notModified
            ? () => _tryParseBaseline(
                ref,
                config,
                syncState.lastSyncedRemoteTdf,
                utcNow,
                localNow,
              )
            : null,
        initialAckGeneration: casInitialAckGen,
        hadExistingRemote: hadExistingRemote,
        preTransactionGeneration: remoteFloorGen,
        serializedCandidate: serializedFinal,
        resolutions: resolutions,
        utcNow: utcNow,
        localNow: localNow,
      );
      if (!ref.mounted) {
        return (nextWorking, nextHasWorking, syncState, lastPersistedSyncState);
      }
    }
    final cachedRemoteDigest = syncState.remoteSourceDigest;
    final String remoteDigest;
    String? serializedFinalDigest;
    if (didSaveRemote) {
      remoteDigest = await _computeTdfDigestAsync(
        serializedFinal,
        knownContent: syncState.lastSyncedLocalTdf,
        knownDigest: syncState.localSourceDigest,
        secondaryKnownContent: syncState.lastSyncedRemoteTdf,
        secondaryKnownDigest: cachedRemoteDigest,
      );
      serializedFinalDigest = remoteDigest;
    } else if (notModified && cachedRemoteDigest != null) {
      remoteDigest = cachedRemoteDigest;
      if (serializedFinal == syncState.lastSyncedLocalTdf) {
        serializedFinalDigest = syncState.localSourceDigest;
      } else if (serializedFinal == syncState.lastSyncedRemoteTdf) {
        serializedFinalDigest = cachedRemoteDigest;
      }
    } else {
      remoteDigest = await _computeTdfDigestAsync(
        effectiveRawRemote,
        knownContent: syncState.lastSyncedLocalTdf,
        knownDigest: syncState.localSourceDigest,
        secondaryKnownContent: syncState.lastSyncedRemoteTdf,
        secondaryKnownDigest: cachedRemoteDigest,
      );
      if (serializedFinal == effectiveRawRemote) {
        serializedFinalDigest = remoteDigest;
      } else if (serializedFinal == syncState.lastSyncedLocalTdf) {
        serializedFinalDigest = syncState.localSourceDigest;
      } else if (serializedFinal == syncState.lastSyncedRemoteTdf) {
        serializedFinalDigest = cachedRemoteDigest;
      }
    }
    var nextSyncState = syncState.copyWith(
      lastSyncedRemoteTdf: serializedFinal,
      acknowledgedRemoteGeneration: nextWorking.deletedBlock.generation,
      remoteSourceDigest: remoteDigest,
      remoteEtag: webDavRepo.cachedEtag,
      clearRemoteEtag: webDavRepo.cachedEtag == null,
      remoteLastModified: webDavRepo.cachedLastModified,
      clearRemoteLastModified: webDavRepo.cachedLastModified == null,
    );
    final persistedAfterRemote = await _saveSyncStateIfChanged(
      settingsRepository,
      workspaceId,
      nextSyncState,
      lastPersistedSyncState,
    );
    if (!ref.mounted) {
      return (nextWorking, nextHasWorking, nextSyncState, persistedAfterRemote);
    }
    final needsLocalConvergence =
        config.storageMode.usesLocal &&
        (requireTargets || config.isLocalConfigured) &&
        (requireTargets ||
            nextSyncState.localSourceDigest == null ||
            serializedFinal != nextSyncState.lastSyncedLocalTdf);
    if (needsLocalConvergence) {
      (nextWorking, nextSyncState) = await _convergeLocalAfterRemoteStage(
        ref,
        config,
        localRepo: localRepo,
        webDavRepo: webDavRepo,
        syncState: nextSyncState,
        candidateBoard: nextWorking,
        serializedCandidate: serializedFinal,
        serializedCandidateDigest: serializedFinalDigest,
        resolutions: resolutions,
        requireTargets: requireTargets,
        utcNow: utcNow,
        localNow: localNow,
      );
    }
    return (nextWorking, nextHasWorking, nextSyncState, persistedAfterRemote);
  }

  /// Parses [rawBaselineTdf] into a [TaskBoard] via [TdfService.parseAsync], or returns `null` when empty or malformed.
  static Future<TaskBoard?> _tryParseBaseline(
    Ref ref,
    WebDavConfig config,
    String? rawBaselineTdf,
    DateTime utcNow,
    DateTime localNow,
  ) async {
    if (rawBaselineTdf == null || rawBaselineTdf.trim().isEmpty) return null;
    try {
      return await _parseTdf(ref, config, rawBaselineTdf, utcNow, localNow);
    } on TdfException catch (error) {
      AppLogger.warn(
        LogTag.sync,
        'Ignoring corrupted local sync baseline (${error.kind.name})',
      );
      return null;
    }
  }
}

/// Exception thrown when one or both active `.tdf` files cannot be read or parsed.
@immutable
class StorageFileReadException implements StorageFileReadError {
  /// Creates a [StorageFileReadException].
  const StorageFileReadException(
    this.message, {
    required this.report,
    this.cause,
  });

  /// Primary underlying exception that caused the read failure.
  final Object? cause;

  /// Localized user-facing summary and per-file readability status message.
  @override
  final String message;

  /// Structured readability report for every active storage target.
  @override
  final StorageFileReadReport report;

  @override
  String toString() => message;
}

/// Exception thrown when a local and/or remote `.tdf` file uses an unsupported TDF version.
@immutable
class UnsupportedTdfVersionException extends StorageFileReadException {
  /// Creates an [UnsupportedTdfVersionException].
  const UnsupportedTdfVersionException(
    super.message, {
    required this.version,
    required super.report,
    TdfException? super.cause,
  });

  /// Detected unsupported TDF version token.
  final String version;
}

/// Strategy for handling local `.tdf` read or parse errors during synchronization stages.
enum _LocalReadErrorMode {
  /// Propagates raw repository or parser exceptions (used for silent outgoing unload flushes).
  raw,

  /// Reports only the local file status without probing WebDAV.
  localOnly,

  /// Probes the remote WebDAV `.tdf` file read-only so both targets are reported.
  probeRemote,

  /// Reports local failure alongside an already-verified readable remote status (Stage 3 convergence).
  remoteAlreadyReadable,
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

/// Builds the canonical map key (`<kind>:<id>`) correlating conflict/recovery decision state entries.
String resolutionDecisionKey(String kindName, String id) => '$kindName:$id';
