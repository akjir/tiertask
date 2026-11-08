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
import '../models/tdf_sync_metadata.dart';
import '../models/tdf_timezone.dart';
import '../models/webdav_config.dart';
import '../models/workspace_sync_state.dart';
import '../repositories/local_file_repository.dart';
import '../services/app_logger.dart';
import '../services/tdf_id_migration.dart';
import '../services/tdf_importer.dart';
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
  });

  /// Optional error message from the most recent synchronization attempt.
  final String? errorMessage;

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
  }) => SyncState(
    isSyncing: isSyncing ?? this.isSyncing,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncState &&
          other.isSyncing == isSyncing &&
          other.lastSyncedAt == lastSyncedAt &&
          other.errorMessage == errorMessage);

  @override
  int get hashCode => Object.hash(isSyncing, lastSyncedAt, errorMessage);
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
  void clearError() => state = state.copyWith(clearError: true);

  /// Records a synchronization failure with [message].
  void setError(String message) =>
      state = state.copyWith(isSyncing: false, errorMessage: message);

  /// Records a successful synchronization at [timestamp].
  void setSuccess(DateTime timestamp) =>
      state = SyncState(isSyncing: false, lastSyncedAt: timestamp);

  /// Marks synchronization as in progress and clears previous errors.
  void setSyncing() =>
      state = state.copyWith(isSyncing: true, clearError: true);
}

/// Stateless two-stage local and WebDAV synchronization and migration pipeline.
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
        syncState.lastSyncedLocalTdf,
        utcNow,
        localNow,
      );
      final published = await _publishLocalWithCasLoop(
        ref,
        config,
        initialDigest: syncState.localSourceDigest,
        initialBaseline: baseline,
        candidateBoard: board,
        deletedLabels: syncState.deletedLabelTimestamps,
        deletedLocations: syncState.deletedLocationTimestamps,
        taskConflictResolutions: const <String, TdfDeletionResolution>{},
        labelConflictResolutions: const <String, TdfDeletionResolution>{},
        locationConflictResolutions: const <String, TdfDeletionResolution>{},
        requireTargets: true,
        skipWriteIfUnchanged: false,
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

  /// Explicitly imports and migrates a historical TDF (`0.2.0`–`0.5.1`) or `0.6.0` [rawTdf]
  /// document into `tdf 0.6.0`, invalidates any earlier synchronization baseline per
  /// `TDF_SPEC.md` Section 10.1, and persists the migrated document to active storage.
  static Future<TdfImportResult> importLegacyTdf(
    Ref ref,
    String rawTdf, {
    TdfTimeZoneContext? sourceTimeZone,
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = resolveTimestamps(ref, currentDate);
    final config = readCurrentConfig(ref);
    final resolvedZone =
        sourceTimeZone ??
        TdfTimeZoneContext.fixedOffset(
          config.timeZoneMode == AppTimeZoneMode.manual
              ? Duration(minutes: config.manualTimeZoneOffsetMinutes)
              : utcNow.toLocal().timeZoneOffset,
        );
    final importResult = TdfImporter.importDocument(
      rawTdf,
      sourceTimeZone: resolvedZone,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
    );
    final workspace = await ref.read(activeWorkspaceProvider.future);
    final content = importResult.migratedTdfContent;
    String? localDigest;
    if (config.storageMode.usesLocal && config.isLocalConfigured) {
      await ref.read(localFileRepositoryProvider).saveTdf(content);
      localDigest = TdfIdMigration.sha256Hex(utf8.encode(content));
    }
    if (config.storageMode.usesWebDav && config.isWebDavConfigured) {
      await ref.read(webDavRepositoryProvider).saveTdf(content);
    }
    final generation = importResult.board.deletedBlock.generation;
    await ref
        .read(settingsRepositoryProvider)
        .saveWorkspaceSyncState(
          workspace.id,
          WorkspaceSyncState(
            lastSyncedLocalTdf: content,
            lastSyncedRemoteTdf: content,
            acknowledgedLocalGeneration: generation,
            acknowledgedRemoteGeneration: generation,
            localSourceDigest: localDigest,
          ),
        );
    AppLogger.info(
      LogTag.sync,
      'Imported legacy TDF document (sourceVersion=${importResult.sourceVersion}, migrated=${importResult.executedSteps.length > 1})',
    );
    return importResult;
  }

  /// Immediately persists a label deletion timestamp to [WorkspaceSyncState] so offline restarts preserve it.
  static Future<void> persistPendingLabelDeletion(
    Ref ref,
    String labelId,
    DateTime deletedAt,
  ) async {
    final workspace = await ref.read(activeWorkspaceProvider.future);
    final settingsRepository = ref.read(settingsRepositoryProvider);
    final current = await settingsRepository.loadWorkspaceSyncState(
      workspace.id,
    );
    final updated = <String, DateTime>{
      ...current.deletedLabelTimestamps,
      labelId: deletedAt,
    };
    await settingsRepository.saveWorkspaceSyncState(
      workspace.id,
      current.copyWith(deletedLabelTimestamps: updated),
    );
  }

  /// Immediately persists a location deletion timestamp to [WorkspaceSyncState] so offline restarts preserve it.
  static Future<void> persistPendingLocationDeletion(
    Ref ref,
    String locationId,
    DateTime deletedAt,
  ) async {
    final workspace = await ref.read(activeWorkspaceProvider.future);
    final settingsRepository = ref.read(settingsRepositoryProvider);
    final current = await settingsRepository.loadWorkspaceSyncState(
      workspace.id,
    );
    final updated = <String, DateTime>{
      ...current.deletedLocationTimestamps,
      locationId: deletedAt,
    };
    await settingsRepository.saveWorkspaceSyncState(
      workspace.id,
      current.copyWith(deletedLocationTimestamps: updated),
    );
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
      WorkspaceSyncState(
        lastSyncedLocalTdf: null,
        lastSyncedRemoteTdf: current.lastSyncedRemoteTdf,
        acknowledgedLocalGeneration: 0,
        acknowledgedRemoteGeneration: current.acknowledgedRemoteGeneration,
        localSourceDigest: null,
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

  /// Wraps [synchronize] with [SyncStateNotifier] status updates.
  static Future<TaskBoard> runSyncWithStatus(
    Ref ref,
    WebDavConfig config, {
    required Map<String, DateTime> pendingDeletedLabelTimestamps,
    Map<String, DateTime>? pendingDeletedLocationTimestamps,
    Map<String, TdfDeletionResolution> taskConflictResolutions = const {},
    Map<String, TdfDeletionResolution> labelConflictResolutions = const {},
    Map<String, TdfDeletionResolution> locationConflictResolutions = const {},
    TaskBoard? candidateBoard,
    bool isInitialLoad = false,
    bool requireTargets = false,
    void Function(TaskBoard mergedBoard)? onLocalStageMerged,
  }) async {
    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      final board = await synchronize(
        ref,
        config,
        pendingDeletedLabelTimestamps: pendingDeletedLabelTimestamps,
        pendingDeletedLocationTimestamps: pendingDeletedLocationTimestamps,
        taskConflictResolutions: taskConflictResolutions,
        labelConflictResolutions: labelConflictResolutions,
        locationConflictResolutions: locationConflictResolutions,
        candidateBoard: candidateBoard,
        isInitialLoad: isInitialLoad,
        requireTargets: requireTargets,
        onLocalStageMerged: onLocalStageMerged,
      );
      ref
          .read(syncStateProvider.notifier)
          .setSuccess(ref.read(clockProvider)().toUtc());
      return board;
    } on Object catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.sync,
        'sync.error',
        fields: <String, Object?>{'mode': config.storageMode.name},
        error: error,
      );
      ref.read(syncStateProvider.notifier).setError(error.toString());
      rethrow;
    }
  }

  /// Executes the two-stage merge pipeline (`In-Memory <-> Local File <-> WebDAV`).
  static Future<TaskBoard> synchronize(
    Ref ref,
    WebDavConfig config, {
    required Map<String, DateTime> pendingDeletedLabelTimestamps,
    Map<String, DateTime>? pendingDeletedLocationTimestamps,
    Map<String, TdfDeletionResolution> taskConflictResolutions = const {},
    Map<String, TdfDeletionResolution> labelConflictResolutions = const {},
    Map<String, TdfDeletionResolution> locationConflictResolutions = const {},
    TaskBoard? candidateBoard,
    bool isInitialLoad = false,
    bool requireTargets = false,
    void Function(TaskBoard mergedBoard)? onLocalStageMerged,
  }) async {
    final (utcNow, localNow) = resolveTimestamps(ref, null);
    final workspace = await ref.read(activeWorkspaceProvider.future);
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
    final deletedLabels = <String, DateTime>{
      ...syncState.deletedLabelTimestamps,
      ...pendingDeletedLabelTimestamps,
    };
    final deletedLocations = <String, DateTime>{
      ...syncState.deletedLocationTimestamps,
      ...?pendingDeletedLocationTimestamps,
    };

    var hasWorking = candidateBoard != null && !isInitialLoad;
    var working = candidateBoard ?? TaskBoard.empty();
    final hasCandidate = candidateBoard != null;

    if (config.storageMode.usesLocal &&
        (requireTargets || config.isLocalConfigured)) {
      (working, hasWorking, syncState) = await _synchronizeLocalStage(
        ref,
        config,
        workspaceId: workspace.id,
        working: working,
        hasWorking: hasWorking,
        hasCandidate: hasCandidate,
        requireTargets: requireTargets,
        syncState: syncState,
        deletedLabels: deletedLabels,
        deletedLocations: deletedLocations,
        taskConflictResolutions: taskConflictResolutions,
        labelConflictResolutions: labelConflictResolutions,
        locationConflictResolutions: locationConflictResolutions,
        utcNow: utcNow,
        localNow: localNow,
        onLocalStageMerged: onLocalStageMerged,
      );
      AppLogger.event(
        LogLevel.info,
        LogTag.sync,
        'sync.stage.local',
        fields: <String, Object?>{
          'workspace': workspace.id,
          'tasks': working.allTasks.length,
          'labels': working.labels.length,
          'locations': working.locations.length,
        },
      );
    }

    if (config.storageMode.usesWebDav &&
        (requireTargets || config.isWebDavConfigured)) {
      (working, hasWorking, syncState) = await _synchronizeRemoteStage(
        ref,
        config,
        working: working,
        hasWorking: hasWorking,
        hasCandidate: hasCandidate,
        requireTargets: requireTargets,
        syncState: syncState,
        deletedLabels: deletedLabels,
        deletedLocations: deletedLocations,
        taskConflictResolutions: taskConflictResolutions,
        labelConflictResolutions: labelConflictResolutions,
        locationConflictResolutions: locationConflictResolutions,
        utcNow: utcNow,
        localNow: localNow,
      );
      AppLogger.event(
        LogLevel.info,
        LogTag.sync,
        'sync.stage.remote',
        fields: <String, Object?>{
          'workspace': workspace.id,
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
      );
    }

    pendingDeletedLabelTimestamps.clear();
    pendingDeletedLocationTimestamps?.clear();
    syncState = syncState.copyWith(
      deletedLabelTimestamps: const <String, DateTime>{},
      deletedLocationTimestamps: const <String, DateTime>{},
    );
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
    DateTime utcNow,
    DateTime localNow,
  ) async {
    try {
      final rawRemote = await ref.read(webDavRepositoryProvider).fetchTdf();
      if (rawRemote.trim().isNotEmpty) {
        _parseTdf(ref, rawRemote, utcNow, localNow);
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
    required String serializedFinal,
    required String trimmedFinal,
    required Map<String, DateTime> deletedLabels,
    required Map<String, DateTime> deletedLocations,
    required Map<String, TdfDeletionResolution> taskConflictResolutions,
    required Map<String, TdfDeletionResolution> labelConflictResolutions,
    required Map<String, TdfDeletionResolution> locationConflictResolutions,
    required bool requireTargets,
    required DateTime utcNow,
    required DateTime localNow,
  }) async {
    final trimmedLastLocal = (syncState.lastSyncedLocalTdf ?? '').trim();
    final baseline = _tryParseBaseline(
      ref,
      syncState.lastSyncedLocalTdf,
      utcNow,
      localNow,
    );
    final published = await _publishLocalWithCasLoop(
      ref,
      config,
      initialDigest: syncState.localSourceDigest,
      initialBaseline: baseline,
      candidateBoard: candidateBoard,
      deletedLabels: deletedLabels,
      deletedLocations: deletedLocations,
      taskConflictResolutions: taskConflictResolutions,
      labelConflictResolutions: labelConflictResolutions,
      locationConflictResolutions: locationConflictResolutions,
      requireTargets: requireTargets,
      skipWriteIfUnchanged: !requireTargets && trimmedLastLocal == trimmedFinal,
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
      return _parseTdf(ref, rawLocal, utcNow, localNow);
    } on TdfException catch (error) {
      if (error.kind != TdfErrorKind.unsupportedVersion) rethrow;
      final remoteError =
          (config.storageMode.usesWebDav &&
              (requireTargets || config.isWebDavConfigured))
          ? await _checkRemoteUnsupportedVersion(ref, utcNow, localNow)
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
      return _parseTdf(ref, rawRemote, utcNow, localNow);
    } on TdfException catch (error) {
      if (error.kind != TdfErrorKind.unsupportedVersion) rethrow;
      throw _createUnsupportedVersionException(
        config: config,
        remoteError: error,
      );
    }
  }

  /// Parses [rawTdf] using [utcNow] and [localNow].
  static TaskBoard _parseTdf(
    Ref ref,
    String rawTdf,
    DateTime utcNow,
    DateTime localNow,
  ) => ref
      .read(tdfServiceProvider)
      .parse(rawTdf, evaluationTime: utcNow, localEvaluationTime: localNow);

  /// Executes the guarded local publication compare-and-swap (CAS) merge loop (`TDF_SPEC_0.6.0.md` Section 6.8.4).
  static Future<({TaskBoard board, String serialized, String? digest})>
  _publishLocalWithCasLoop(
    Ref ref,
    WebDavConfig config, {
    required String? initialDigest,
    required TaskBoard? initialBaseline,
    required TaskBoard candidateBoard,
    required Map<String, DateTime> deletedLabels,
    required Map<String, DateTime> deletedLocations,
    required Map<String, TdfDeletionResolution> taskConflictResolutions,
    required Map<String, TdfDeletionResolution> labelConflictResolutions,
    required Map<String, TdfDeletionResolution> locationConflictResolutions,
    required bool requireTargets,
    required bool skipWriteIfUnchanged,
    required DateTime utcNow,
    required DateTime localNow,
  }) async {
    final localRepo = ref.read(localFileRepositoryProvider);
    var loopDigest = initialDigest;
    var loopB = initialBaseline;
    var loopL = candidateBoard;
    for (var attempt = 0; attempt <= maxCasRetries; attempt++) {
      final disk = await localRepo.readTdfWithDigest();
      if (disk.digest == loopDigest) {
        final serialized = _serializeTdf(ref, loopL);
        if (attempt > 0 || !skipWriteIfUnchanged) {
          await localRepo.saveTdf(serialized);
          final savedDigest = TdfIdMigration.sha256Hex(utf8.encode(serialized));
          return (board: loopL, serialized: serialized, digest: savedDigest);
        }
        return (board: loopL, serialized: serialized, digest: loopDigest);
      }
      if (attempt >= maxCasRetries) {
        throw const LocalFileException(
          'Local file was modified concurrently and exceeded maximum CAS merge retries (3).',
        );
      }
      (loopB, loopL, loopDigest) = await _retryCasMergeStep(
        ref,
        config,
        disk: disk,
        loopB: loopB,
        loopL: loopL,
        deletedLabels: deletedLabels,
        deletedLocations: deletedLocations,
        taskConflictResolutions: taskConflictResolutions,
        labelConflictResolutions: labelConflictResolutions,
        locationConflictResolutions: locationConflictResolutions,
        requireTargets: requireTargets,
        utcNow: utcNow,
        localNow: localNow,
      );
    }
    throw const LocalFileException(
      'Local file was modified concurrently and exceeded maximum CAS merge retries (3).',
    );
  }

  /// Resolves a single CAS mismatch iteration against the freshly read [disk] snapshot.
  static Future<(TaskBoard?, TaskBoard, String?)> _retryCasMergeStep(
    Ref ref,
    WebDavConfig config, {
    required ({String content, String? digest, bool exists}) disk,
    required TaskBoard? loopB,
    required TaskBoard loopL,
    required Map<String, DateTime> deletedLabels,
    required Map<String, DateTime> deletedLocations,
    required Map<String, TdfDeletionResolution> taskConflictResolutions,
    required Map<String, TdfDeletionResolution> labelConflictResolutions,
    required Map<String, TdfDeletionResolution> locationConflictResolutions,
    required bool requireTargets,
    required DateTime utcNow,
    required DateTime localNow,
  }) async {
    if (!disk.exists || disk.content.trim().isEmpty) {
      final mergedEmpty = TaskBoardSync.merge(
        primary: loopL,
        secondary: TaskBoard.empty(),
        baseline: null,
        acknowledgedGeneration: null,
        requireAcknowledgedGeneration: true,
        deletedLabelTimestamps: deletedLabels,
        deletedLocationTimestamps: deletedLocations,
        taskConflictResolutions: taskConflictResolutions,
        labelConflictResolutions: labelConflictResolutions,
        locationConflictResolutions: locationConflictResolutions,
        evaluationTime: utcNow,
        localEvaluationTime: localNow,
      );
      final normalized = TaskBoardSync.stampAndNormalize(
        mergedEmpty,
        evaluationTime: utcNow,
        localEvaluationTime: localNow,
      );
      return (null, normalized, disk.digest);
    }
    final diskBoard = await _parseLocalOrThrow(
      ref,
      config,
      disk.content,
      requireTargets,
      utcNow,
      localNow,
    );
    final merged = TaskBoardSync.merge(
      primary: loopL,
      secondary: diskBoard,
      baseline: loopB,
      acknowledgedGeneration: loopB?.deletedBlock.generation,
      deletedLabelTimestamps: deletedLabels,
      deletedLocationTimestamps: deletedLocations,
      taskConflictResolutions: taskConflictResolutions,
      labelConflictResolutions: labelConflictResolutions,
      locationConflictResolutions: locationConflictResolutions,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
    );
    final normalized = TaskBoardSync.stampAndNormalize(
      merged,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
    );
    return (diskBoard, normalized, disk.digest);
  }

  /// Serializes [board] into canonical `.tdf` text.
  static String _serializeTdf(Ref ref, TaskBoard board) =>
      ref.read(tdfServiceProvider).serialize(board);

  /// Executes the first-stage local file merge and write-back for [workspaceId].
  static Future<(TaskBoard, bool, WorkspaceSyncState)> _synchronizeLocalStage(
    Ref ref,
    WebDavConfig config, {
    required String workspaceId,
    required TaskBoard working,
    required bool hasWorking,
    required bool hasCandidate,
    required bool requireTargets,
    required WorkspaceSyncState syncState,
    required Map<String, DateTime> deletedLabels,
    required Map<String, DateTime> deletedLocations,
    required Map<String, TdfDeletionResolution> taskConflictResolutions,
    required Map<String, TdfDeletionResolution> labelConflictResolutions,
    required Map<String, TdfDeletionResolution> locationConflictResolutions,
    required DateTime utcNow,
    required DateTime localNow,
    required void Function(TaskBoard mergedBoard)? onLocalStageMerged,
  }) async {
    final initialRead = await ref
        .read(localFileRepositoryProvider)
        .readTdfWithDigest();
    final rawLocal = initialRead.content;
    final trimmedLocal = rawLocal.trim();
    var nextWorking = working;
    var nextHasWorking = hasWorking;
    TaskBoard? localBoard;
    if (trimmedLocal.isNotEmpty) {
      localBoard = await _parseLocalOrThrow(
        ref,
        config,
        rawLocal,
        requireTargets,
        utcNow,
        localNow,
      );
      final baseline = _tryParseBaseline(
        ref,
        syncState.lastSyncedLocalTdf,
        utcNow,
        localNow,
      );
      nextWorking = TaskBoardSync.merge(
        primary: nextHasWorking ? nextWorking : localBoard,
        secondary: localBoard,
        baseline: baseline ?? (nextHasWorking ? null : localBoard),
        acknowledgedGeneration: baseline != null
            ? syncState.acknowledgedLocalGeneration
            : null,
        deletedLabelTimestamps: deletedLabels,
        deletedLocationTimestamps: deletedLocations,
        taskConflictResolutions: taskConflictResolutions,
        labelConflictResolutions: labelConflictResolutions,
        locationConflictResolutions: locationConflictResolutions,
        evaluationTime: utcNow,
        localEvaluationTime: localNow,
      );
      nextHasWorking = true;
    }
    if (trimmedLocal.isEmpty && !nextHasWorking && !requireTargets) {
      return (nextWorking, nextHasWorking, syncState);
    }
    nextWorking = TaskBoardSync.stampAndNormalize(
      nextWorking,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
    );
    final trimmedSerializedLocal = _serializeTdf(ref, nextWorking).trim();
    final published = await _publishLocalWithCasLoop(
      ref,
      config,
      initialDigest: initialRead.digest,
      initialBaseline: localBoard,
      candidateBoard: nextWorking,
      deletedLabels: deletedLabels,
      deletedLocations: deletedLocations,
      taskConflictResolutions: taskConflictResolutions,
      labelConflictResolutions: labelConflictResolutions,
      locationConflictResolutions: locationConflictResolutions,
      requireTargets: requireTargets,
      skipWriteIfUnchanged:
          !requireTargets &&
          !hasCandidate &&
          trimmedLocal == trimmedSerializedLocal,
      utcNow: utcNow,
      localNow: localNow,
    );
    nextWorking = published.board;
    final nextSyncState = syncState.copyWith(
      lastSyncedLocalTdf: published.serialized,
      deletedLabelTimestamps: deletedLabels,
      deletedLocationTimestamps: deletedLocations,
      acknowledgedLocalGeneration: nextWorking.deletedBlock.generation,
      localSourceDigest: published.digest,
    );
    await ref
        .read(settingsRepositoryProvider)
        .saveWorkspaceSyncState(workspaceId, nextSyncState);
    if (hasCandidate &&
        onLocalStageMerged != null &&
        ref.read(activeWorkspaceProvider).asData?.value.id == workspaceId) {
      onLocalStageMerged(nextWorking);
    }
    return (nextWorking, nextHasWorking, nextSyncState);
  }

  /// Executes the second-stage WebDAV remote merge, write-back, and local convergence.
  static Future<(TaskBoard, bool, WorkspaceSyncState)> _synchronizeRemoteStage(
    Ref ref,
    WebDavConfig config, {
    required TaskBoard working,
    required bool hasWorking,
    required bool hasCandidate,
    required bool requireTargets,
    required WorkspaceSyncState syncState,
    required Map<String, DateTime> deletedLabels,
    required Map<String, DateTime> deletedLocations,
    required Map<String, TdfDeletionResolution> taskConflictResolutions,
    required Map<String, TdfDeletionResolution> labelConflictResolutions,
    required Map<String, TdfDeletionResolution> locationConflictResolutions,
    required DateTime utcNow,
    required DateTime localNow,
  }) async {
    final rawRemote = await ref.read(webDavRepositoryProvider).fetchTdf();
    final trimmedRemote = rawRemote.trim();
    var nextWorking = working;
    var nextHasWorking = hasWorking;
    if (trimmedRemote.isNotEmpty) {
      final remoteBoard = _parseRemoteOrThrow(
        ref,
        config,
        rawRemote,
        utcNow,
        localNow,
      );
      final baseline = _tryParseBaseline(
        ref,
        syncState.lastSyncedRemoteTdf,
        utcNow,
        localNow,
      );
      nextWorking = TaskBoardSync.merge(
        primary: nextHasWorking ? nextWorking : remoteBoard,
        secondary: remoteBoard,
        baseline: baseline ?? (nextHasWorking ? null : remoteBoard),
        acknowledgedGeneration: baseline != null
            ? syncState.acknowledgedRemoteGeneration
            : null,
        deletedLabelTimestamps: deletedLabels,
        deletedLocationTimestamps: deletedLocations,
        taskConflictResolutions: taskConflictResolutions,
        labelConflictResolutions: labelConflictResolutions,
        locationConflictResolutions: locationConflictResolutions,
        evaluationTime: utcNow,
        localEvaluationTime: localNow,
      );
      nextHasWorking = true;
    }
    if (trimmedRemote.isEmpty && !nextHasWorking && !requireTargets) {
      return (nextWorking, nextHasWorking, syncState);
    }
    nextWorking = TaskBoardSync.stampAndNormalize(
      nextWorking,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
    );
    final serializedFinal = _serializeTdf(ref, nextWorking);
    final trimmedFinal = serializedFinal.trim();
    if (requireTargets ||
        hasCandidate ||
        config.storageMode == StorageMode.both ||
        trimmedRemote != trimmedFinal) {
      await ref.read(webDavRepositoryProvider).saveTdf(serializedFinal);
    }
    var nextSyncState = syncState.copyWith(
      lastSyncedRemoteTdf: serializedFinal,
      acknowledgedRemoteGeneration: nextWorking.deletedBlock.generation,
    );
    if (config.storageMode.usesLocal &&
        (requireTargets || config.isLocalConfigured)) {
      (nextWorking, nextSyncState) = await _convergeLocalAfterRemoteStage(
        ref,
        config,
        syncState: nextSyncState,
        candidateBoard: nextWorking,
        serializedFinal: serializedFinal,
        trimmedFinal: trimmedFinal,
        deletedLabels: deletedLabels,
        deletedLocations: deletedLocations,
        taskConflictResolutions: taskConflictResolutions,
        labelConflictResolutions: labelConflictResolutions,
        locationConflictResolutions: locationConflictResolutions,
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
    String? rawBaselineTdf,
    DateTime utcNow,
    DateTime localNow,
  ) {
    if (rawBaselineTdf == null || rawBaselineTdf.trim().isEmpty) return null;
    try {
      return _parseTdf(ref, rawBaselineTdf, utcNow, localNow);
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
