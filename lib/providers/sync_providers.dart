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

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/app_workspace.dart';
import '../models/task_board.dart';
import '../models/task_board_sync.dart';
import '../models/task_item.dart';
import '../models/tdf_error.dart';
import '../models/tdf_timezone.dart';
import '../models/webdav_config.dart';
import '../models/workspace_sync_state.dart';
import '../services/app_logger.dart';
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
  const TaskSyncPipeline._();

  /// Flushes [board] to the local `.tdf` file of [workspace] before unloading when local persistence is enabled.
  static Future<void> flushOutgoingLocalBoard(
    Ref ref,
    AppWorkspace workspace,
    TaskBoard board,
  ) async {
    final config = workspace.config;
    if (!config.storageMode.usesLocal || !config.isLocalConfigured) return;
    try {
      await ref
          .read(localFileRepositoryProvider)
          .saveTdf(_serializeTdf(ref, board));
    } on Object {
      // Best-effort flush before workspace unload.
    }
  }

  /// Explicitly imports and migrates a historical TDF (`0.2.0`–`0.5.0`) or `0.5.1` [rawTdf]
  /// document into `tdf 0.5.1`, invalidates any earlier synchronization baseline per
  /// `TDF_SPEC.md` Section 10.1, and persists the migrated document to active storage.
  static Future<TdfImportResult> importLegacyTdf(
    Ref ref,
    String rawTdf, {
    TdfTimeZoneContext? sourceTimeZone,
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = resolveTimestamps(ref, currentDate);
    final config = resolveCurrentConfig(ref);
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
    if (config.storageMode.usesLocal && config.isLocalConfigured) {
      await ref.read(localFileRepositoryProvider).saveTdf(content);
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
          ),
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
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final current = await settingsRepo.loadWorkspaceSyncState(workspace.id);
    final updated = <String, DateTime>{
      ...current.deletedLabelTimestamps,
      labelId: deletedAt,
    };
    await settingsRepo.saveWorkspaceSyncState(
      workspace.id,
      current.copyWith(deletedLabelTimestamps: updated),
    );
  }

  /// Resets the local file synchronization baseline while preserving the remote WebDAV baseline for [workspaceId].
  static Future<void> resetLocalSyncBaseline(
    Ref ref,
    String workspaceId,
  ) async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final current = await settingsRepo.loadWorkspaceSyncState(workspaceId);
    await settingsRepo.saveWorkspaceSyncState(
      workspaceId,
      WorkspaceSyncState(
        lastSyncedLocalTdf: null,
        lastSyncedRemoteTdf: current.lastSyncedRemoteTdf,
        acknowledgedLocalGeneration: 0,
        acknowledgedRemoteGeneration: current.acknowledgedRemoteGeneration,
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
        candidateBoard: candidateBoard,
        isInitialLoad: isInitialLoad,
        requireTargets: requireTargets,
        onLocalStageMerged: onLocalStageMerged,
      );
      ref.read(syncStateProvider.notifier).setSuccess(DateTime.now());
      return board;
    } on Object catch (error) {
      ref.read(syncStateProvider.notifier).setError(error.toString());
      rethrow;
    }
  }

  /// Executes the two-stage merge pipeline (`In-Memory <-> Local File <-> WebDAV`).
  static Future<TaskBoard> synchronize(
    Ref ref,
    WebDavConfig config, {
    required Map<String, DateTime> pendingDeletedLabelTimestamps,
    TaskBoard? candidateBoard,
    bool isInitialLoad = false,
    bool requireTargets = false,
    void Function(TaskBoard mergedBoard)? onLocalStageMerged,
  }) async {
    final (utcNow, localNow) = resolveTimestamps(ref, null);
    final workspace = await ref.read(activeWorkspaceProvider.future);
    AppLogger.info(
      LogTag.sync,
      'Starting two-stage sync pipeline workspace=${workspace.id} mode=${config.storageMode.name} initial=$isInitialLoad',
    );
    final settingsRepo = ref.read(settingsRepositoryProvider);
    var syncState = await settingsRepo.loadWorkspaceSyncState(workspace.id);
    final deletedLabels = <String, DateTime>{
      ...syncState.deletedLabelTimestamps,
      ...pendingDeletedLabelTimestamps,
    };

    var hasWorking = candidateBoard != null && !isInitialLoad;
    var working = candidateBoard ?? TaskBoard.empty();
    final hasCandidate = candidateBoard != null;

    if (config.storageMode.usesLocal &&
        (requireTargets || config.isLocalConfigured)) {
      final rawLocal = await ref.read(localFileRepositoryProvider).loadTdf();
      if (rawLocal.trim().isNotEmpty) {
        final localBoard = await _parseLocalOrThrow(
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
        working = TaskBoardSync.merge(
          primary: hasWorking ? working : localBoard,
          secondary: localBoard,
          baseline: baseline ?? (hasWorking ? null : localBoard),
          acknowledgedGeneration: baseline != null
              ? syncState.acknowledgedLocalGeneration
              : null,
          deletedLabelTimestamps: deletedLabels,
          evaluationTime: utcNow,
          localEvaluationTime: localNow,
        );
        hasWorking = true;
      }
      if (rawLocal.trim().isNotEmpty || hasWorking || requireTargets) {
        working = TaskBoardSync.stampAndNormalize(
          working,
          evaluationTime: utcNow,
          localEvaluationTime: localNow,
        );
        final serializedLocal = _serializeTdf(ref, working);
        if (requireTargets ||
            hasCandidate ||
            rawLocal.trim() != serializedLocal.trim()) {
          await ref.read(localFileRepositoryProvider).saveTdf(serializedLocal);
        }
        syncState = syncState.copyWith(
          lastSyncedLocalTdf: serializedLocal,
          deletedLabelTimestamps: deletedLabels,
          acknowledgedLocalGeneration: working.deletedBlock.generation,
        );
        await settingsRepo.saveWorkspaceSyncState(workspace.id, syncState);
        if (hasCandidate &&
            onLocalStageMerged != null &&
            ref.read(activeWorkspaceProvider).asData?.value.id ==
                workspace.id) {
          onLocalStageMerged(working);
        }
      }
    }

    if (config.storageMode.usesWebDav &&
        (requireTargets || config.isWebDavConfigured)) {
      final rawRemote = await ref.read(webDavRepositoryProvider).fetchTdf();
      if (rawRemote.trim().isNotEmpty) {
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
        working = TaskBoardSync.merge(
          primary: hasWorking ? working : remoteBoard,
          secondary: remoteBoard,
          baseline: baseline ?? (hasWorking ? null : remoteBoard),
          acknowledgedGeneration: baseline != null
              ? syncState.acknowledgedRemoteGeneration
              : null,
          deletedLabelTimestamps: deletedLabels,
          evaluationTime: utcNow,
          localEvaluationTime: localNow,
        );
        hasWorking = true;
      }
      if (rawRemote.trim().isNotEmpty || hasWorking || requireTargets) {
        working = TaskBoardSync.stampAndNormalize(
          working,
          evaluationTime: utcNow,
          localEvaluationTime: localNow,
        );
        final serializedFinal = _serializeTdf(ref, working);
        if (requireTargets ||
            hasCandidate ||
            config.storageMode == StorageMode.both ||
            rawRemote.trim() != serializedFinal.trim()) {
          await ref.read(webDavRepositoryProvider).saveTdf(serializedFinal);
        }
        syncState = syncState.copyWith(
          lastSyncedRemoteTdf: serializedFinal,
          acknowledgedRemoteGeneration: working.deletedBlock.generation,
        );
        if (config.storageMode.usesLocal &&
            (requireTargets || config.isLocalConfigured)) {
          if (requireTargets ||
              (syncState.lastSyncedLocalTdf ?? '').trim() !=
                  serializedFinal.trim()) {
            await ref
                .read(localFileRepositoryProvider)
                .saveTdf(serializedFinal);
          }
          syncState = syncState.copyWith(
            lastSyncedLocalTdf: serializedFinal,
            acknowledgedLocalGeneration: working.deletedBlock.generation,
          );
        }
      }
    }

    if (!hasWorking) {
      working = TaskBoardSync.stampAndNormalize(
        working,
        evaluationTime: utcNow,
        localEvaluationTime: localNow,
      );
    }

    pendingDeletedLabelTimestamps.clear();
    syncState = syncState.copyWith(
      deletedLabelTimestamps: const <String, DateTime>{},
    );
    await settingsRepo.saveWorkspaceSyncState(workspace.id, syncState);
    AppLogger.info(
      LogTag.sync,
      'Completed two-stage sync pipeline workspace=${workspace.id} tasks=${working.allTasks.length} labels=${working.labels.length}',
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

  /// Serializes [board] into canonical `.tdf` text.
  static String _serializeTdf(Ref ref, TaskBoard board) =>
      ref.read(tdfServiceProvider).serialize(board);

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
    } on TdfException {
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
