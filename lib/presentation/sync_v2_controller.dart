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

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../l10n/storage_file_read_localization_extension.dart';
import '../l10n/tier_localization_extension.dart';
import '../models/app_workspace.dart';
import '../models/location_state.dart';
import '../models/task_board.dart';
import '../models/tdf_error.dart';
import '../models/tdf_sync_metadata.dart';
import '../providers/config_providers.dart';
import '../providers/location_providers.dart';
import '../providers/sync_providers.dart';
import '../providers/task_providers.dart';
import '../providers/workspace_providers.dart';
import '../repositories/local_file_repository.dart';
import '../repositories/webdav_repository.dart';
import '../services/app_logger.dart';
import 'app_shell_controller.dart';
import 'floating_notice_controller.dart';
import 'ui_v2_shell_models.dart';

/// Provides the model-free `TDF-DEL-003` deletion conflict resolution view model for `lib/ui_v2/`.
final conflictResolutionViewModelProvider =
    Provider<ConflictResolutionViewModel>((ref) {
      final locale = ref.watch(appLocaleProvider);
      final localizations = lookupAppLocalizations(locale);
      final outcome = ref.watch(
        syncStateProvider.select((syncState) => syncState.syncOutcome),
      );
      final board = ref.watch(
        taskNotifierProvider.select((boardAsync) => boardAsync.asData?.value),
      );
      if (outcome == null ||
          outcome.kind != TdfSyncOutcomeKind.deletionConflict) {
        return ConflictResolutionViewModel(
          hasConflicts: false,
          title: localizations.conflictResolutionTitle,
          subtitle: localizations.conflictResolutionSubtitle,
          entries: const <ResolutionEntryViewModel>[],
        );
      }
      final entries = _buildResolutionEntries(
        taskIds: outcome.conflictedTaskIds,
        labelIds: outcome.conflictedLabelIds,
        locationIds: outcome.conflictedLocationIds,
        board: board,
        localizations: localizations,
        detail: localizations.syncConflictDeletionBanner,
      );
      return ConflictResolutionViewModel(
        hasConflicts: entries.isNotEmpty,
        title: localizations.conflictResolutionTitle,
        subtitle: localizations.conflictResolutionSubtitle,
        entries: entries,
      );
    });

/// Provides the model-free foreground location status view model for `lib/ui_v2/`.
final locationStatusViewModelProvider = Provider<LocationStatusViewModel>((
  ref,
) {
  final locale = ref.watch(appLocaleProvider);
  final localizations = lookupAppLocalizations(locale);
  final isEnabled = ref.watch(locationEnabledProvider);
  final locationState = ref.watch(locationStateProvider);
  final fix = locationState.fix;

  return LocationStatusViewModel(
    isEnabled: isEnabled,
    statusKind: _mapLocationStatus(locationState.status),
    statusLabel: _formatLocationStatusLabel(
      locationState.status,
      localizations,
    ),
    placeLabel: _resolvePlaceLabel(locationState, localizations),
    coordinatesText: _formatCoordinates6dp(fix),
    sourceLabel: _formatLocationSourceLabel(fix?.source, localizations),
    isRefreshing: locationState.status == LocationStatus.searching,
  );
});

/// Provides the model-free `TDF-REC-002` generation recovery resolution view model for `lib/ui_v2/`.
final recoveryResolutionViewModelProvider =
    Provider<RecoveryResolutionViewModel>((ref) {
      final locale = ref.watch(appLocaleProvider);
      final localizations = lookupAppLocalizations(locale);
      final outcome = ref.watch(
        syncStateProvider.select((syncState) => syncState.syncOutcome),
      );
      final board = ref.watch(
        taskNotifierProvider.select((boardAsync) => boardAsync.asData?.value),
      );
      if (outcome == null ||
          outcome.kind != TdfSyncOutcomeKind.recoveryRequired) {
        return RecoveryResolutionViewModel(
          hasItems: false,
          title: localizations.recoveryResolutionTitle,
          subtitle: localizations.recoveryResolutionSubtitle,
          entries: const <ResolutionEntryViewModel>[],
        );
      }
      final entries = _buildResolutionEntries(
        taskIds: outcome.ambiguousTaskIds,
        labelIds: outcome.ambiguousLabelIds,
        locationIds: outcome.ambiguousLocationIds,
        board: board,
        localizations: localizations,
        detail: localizations.syncConflictRecoveryBanner,
      );
      return RecoveryResolutionViewModel(
        hasItems: entries.isNotEmpty,
        title: localizations.recoveryResolutionTitle,
        subtitle: localizations.recoveryResolutionSubtitle,
        entries: entries,
      );
    });

/// Provides the model-free synchronization, location refresh, and conflict/recovery resolution controller.
final syncV2ControllerProvider =
    NotifierProvider<SyncV2Controller, SyncV2ControllerState>(
      SyncV2Controller.new,
    );

/// Model-free resolution choice for a `TDF-DEL-003` deletion conflict item.
enum ConflictDecisionChoice {
  /// Keeps the concurrent local edit and undeletes the conflicted entity.
  keepEdit,

  /// Confirms deletion of the conflicted entity.
  confirmDelete,
}

/// Model-free resolution choice for a `TDF-REC-002` generation recovery item.
enum RecoveryDecisionChoice {
  /// Recovers the retired local entity under a fresh identifier.
  recoverAsNew,

  /// Discards the retired local entity.
  discardLocal,
}

/// Immutable view model projecting pending `TDF-DEL-003` deletion conflicts.
@immutable
class ConflictResolutionViewModel {
  /// Creates a [ConflictResolutionViewModel].
  ConflictResolutionViewModel({
    required this.hasConflicts,
    required this.title,
    required this.subtitle,
    required Iterable<ResolutionEntryViewModel> entries,
  }) : entries = List<ResolutionEntryViewModel>.unmodifiable(entries);

  /// Conflicted task, label, and location entries awaiting resolution.
  final List<ResolutionEntryViewModel> entries;

  /// Whether at least one deletion conflict entry is active.
  final bool hasConflicts;

  /// Localized explanatory subtitle for the deletion conflict view.
  final String subtitle;

  /// Localized heading for the deletion conflict view.
  final String title;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConflictResolutionViewModel &&
        other.hasConflicts == hasConflicts &&
        other.title == title &&
        other.subtitle == subtitle &&
        listEquals(other.entries, entries);
  }

  @override
  int get hashCode =>
      Object.hash(hasConflicts, title, subtitle, Object.hashAll(entries));
}

/// Immutable view model projecting foreground location determination state.
@immutable
class LocationStatusViewModel {
  /// Creates a [LocationStatusViewModel].
  const LocationStatusViewModel({
    required this.isEnabled,
    required this.statusKind,
    required this.statusLabel,
    required this.placeLabel,
    required this.coordinatesText,
    required this.sourceLabel,
    required this.isRefreshing,
  });

  /// Formatted 6-decimal-place WGS-84 coordinates, or empty when unavailable.
  final String coordinatesText;

  /// Whether foreground location determination is enabled in workspace settings.
  final bool isEnabled;

  /// Whether a foreground location lookup is currently running.
  final bool isRefreshing;

  /// Localized place name, fallback unknown place label, or empty when no fix exists.
  final String placeLabel;

  /// Localized location fix source label, or empty when unavailable.
  final String sourceLabel;

  /// Current model-free location status category.
  final ShellLocationStatusKind statusKind;

  /// Localized status message for the current lookup state.
  final String statusLabel;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationStatusViewModel &&
        other.isEnabled == isEnabled &&
        other.statusKind == statusKind &&
        other.statusLabel == statusLabel &&
        other.placeLabel == placeLabel &&
        other.coordinatesText == coordinatesText &&
        other.sourceLabel == sourceLabel &&
        other.isRefreshing == isRefreshing;
  }

  @override
  int get hashCode => Object.hash(
    isEnabled,
    statusKind,
    statusLabel,
    placeLabel,
    coordinatesText,
    sourceLabel,
    isRefreshing,
  );
}

/// Immutable view model projecting pending `TDF-REC-002` generation recovery items.
@immutable
class RecoveryResolutionViewModel {
  /// Creates a [RecoveryResolutionViewModel].
  RecoveryResolutionViewModel({
    required this.hasItems,
    required this.title,
    required this.subtitle,
    required Iterable<ResolutionEntryViewModel> entries,
  }) : entries = List<ResolutionEntryViewModel>.unmodifiable(entries);

  /// Ambiguous task, label, and location entries awaiting recovery decisions.
  final List<ResolutionEntryViewModel> entries;

  /// Whether at least one generation recovery entry is active.
  final bool hasItems;

  /// Localized explanatory subtitle for the generation recovery view.
  final String subtitle;

  /// Localized heading for the generation recovery view.
  final String title;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RecoveryResolutionViewModel &&
        other.hasItems == hasItems &&
        other.title == title &&
        other.subtitle == subtitle &&
        listEquals(other.entries, entries);
  }

  @override
  int get hashCode =>
      Object.hash(hasItems, title, subtitle, Object.hashAll(entries));
}

/// Immutable card projection for a single conflicted or ambiguous entity.
@immutable
class ResolutionEntryViewModel {
  /// Creates a [ResolutionEntryViewModel].
  const ResolutionEntryViewModel({
    required this.kind,
    required this.kindBadgeLabel,
    required this.id,
    required this.title,
    required this.detail,
  });

  /// Localized conflict or recovery explanation shown on the card.
  final String detail;

  /// Canonical entity identifier.
  final String id;

  /// Entity domain kind (`task`, `label`, or `location`).
  final EntityKind kind;

  /// Localized uppercase badge label for [kind].
  final String kindBadgeLabel;

  /// Resolved display title from the loaded board, or [id] when absent.
  final String title;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ResolutionEntryViewModel &&
        other.kind == kind &&
        other.kindBadgeLabel == kindBadgeLabel &&
        other.id == id &&
        other.title == title &&
        other.detail == detail;
  }

  @override
  int get hashCode => Object.hash(kind, kindBadgeLabel, id, title, detail);
}

/// Coordinates manual synchronization, foreground location refresh, and conflict or recovery resolution intents.
class SyncV2Controller extends Notifier<SyncV2ControllerState> {
  String? _activeWorkspaceId;

  @override
  SyncV2ControllerState build() {
    _activeWorkspaceId = ref.read(activeWorkspaceProvider).asData?.value.id;
    ref.listen<String?>(
      activeWorkspaceProvider.select((workspace) => workspace.asData?.value.id),
      _handleWorkspaceIdChanged,
    );
    return const SyncV2ControllerState();
  }

  /// Applies `TDF-DEL-003` deletion conflict choices, returns to Tasks, and announces completion.
  Future<V2ActionResult> applyDeletionConflictResolutions({
    required Map<String, ConflictDecisionChoice> taskDecisions,
    required Map<String, ConflictDecisionChoice> labelDecisions,
    required Map<String, ConflictDecisionChoice> locationDecisions,
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    if (state.isBusy) {
      return V2ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    final startingWorkspaceId = ref
        .read(activeWorkspaceProvider)
        .asData
        ?.value
        .id;
    state = state.copyWith(isBusy: true);
    try {
      final taskResolutions = _mapConflictDecisions(taskDecisions);
      final labelResolutions = _mapConflictDecisions(labelDecisions);
      final locationResolutions = _mapConflictDecisions(locationDecisions);
      await ref
          .read(taskNotifierProvider.notifier)
          .resolveDeletionConflicts(
            taskResolutions: taskResolutions,
            labelResolutions: labelResolutions,
            locationResolutions: locationResolutions,
          );
      if (!_isStillActiveWorkspace(startingWorkspaceId)) {
        return const V2ActionSucceeded();
      }
      AppLogger.event(
        LogLevel.info,
        LogTag.sync,
        'sync.v2.conflict_resolved',
        fields: <String, Object?>{
          'tasks': taskResolutions.length,
          'labels': labelResolutions.length,
          'locations': locationResolutions.length,
        },
      );
      ref.read(appShellControllerProvider.notifier).openView(ShellView.tasks);
      final noticeMessage = localizations.conflictResolvedNotice;
      ref
          .read(floatingNoticeControllerProvider.notifier)
          .showNotice(noticeMessage, tone: NoticeTone.success);
      return V2ActionSucceeded(noticeMessage: noticeMessage);
    } on Object catch (error) {
      AppLogger.event(
        LogLevel.warn,
        LogTag.sync,
        'sync.v2.conflict_resolve_failed',
        error: error,
      );
      return V2ActionPersistFailed(
        message: _formatSyncError(error, localizations, isSave: true),
      );
    } finally {
      if (_isStillActiveWorkspace(startingWorkspaceId)) {
        state = state.copyWith(isBusy: false);
      }
    }
  }

  /// Applies `TDF-REC-002` generation recovery choices, returns to Tasks, and announces completion.
  Future<V2ActionResult> applyRecoveryResolutions({
    required Map<String, RecoveryDecisionChoice> taskDecisions,
    required Map<String, RecoveryDecisionChoice> labelDecisions,
    required Map<String, RecoveryDecisionChoice> locationDecisions,
    Locale? locale,
  }) async {
    final localizations = _resolveLocalizations(locale);
    if (state.isBusy) {
      return V2ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    final startingWorkspaceId = ref
        .read(activeWorkspaceProvider)
        .asData
        ?.value
        .id;
    state = state.copyWith(isBusy: true);
    try {
      final taskResolutions = _mapRecoveryDecisions(taskDecisions);
      final labelResolutions = _mapRecoveryDecisions(labelDecisions);
      final locationResolutions = _mapRecoveryDecisions(locationDecisions);
      await ref
          .read(taskNotifierProvider.notifier)
          .resolveRecovery(
            taskResolutions: taskResolutions,
            labelResolutions: labelResolutions,
            locationResolutions: locationResolutions,
          );
      if (!_isStillActiveWorkspace(startingWorkspaceId)) {
        return const V2ActionSucceeded();
      }
      AppLogger.event(
        LogLevel.info,
        LogTag.sync,
        'sync.v2.recovery_resolved',
        fields: <String, Object?>{
          'tasks': taskResolutions.length,
          'labels': labelResolutions.length,
          'locations': locationResolutions.length,
        },
      );
      ref.read(appShellControllerProvider.notifier).openView(ShellView.tasks);
      final noticeMessage = localizations.recoveryResolvedNotice;
      ref
          .read(floatingNoticeControllerProvider.notifier)
          .showNotice(noticeMessage, tone: NoticeTone.success);
      return V2ActionSucceeded(noticeMessage: noticeMessage);
    } on Object catch (error) {
      AppLogger.event(
        LogLevel.warn,
        LogTag.sync,
        'sync.v2.recovery_resolve_failed',
        error: error,
      );
      return V2ActionPersistFailed(
        message: _formatSyncError(error, localizations, isSave: true),
      );
    } finally {
      if (_isStillActiveWorkspace(startingWorkspaceId)) {
        state = state.copyWith(isBusy: false);
      }
    }
  }

  /// Triggers an immediate foreground location refresh via [locationStateProvider].
  Future<V2ActionResult> refreshLocation() async {
    final localizations = _resolveLocalizations(null);
    try {
      await ref.read(locationStateProvider.notifier).refreshLocation();
      return const V2ActionSucceeded();
    } on Object catch (error) {
      AppLogger.event(
        LogLevel.warn,
        LogTag.ui,
        'ui.location.refresh_failed',
        error: error,
      );
      return V2ActionPersistFailed(
        message: _formatSyncError(error, localizations),
      );
    }
  }

  /// Synchronizes the active workspace or retries a failed initial board load.
  Future<V2ActionResult> syncNow({Locale? locale}) async {
    final localizations = _resolveLocalizations(locale);
    if (state.isBusy) {
      return V2ActionPersistFailed(message: localizations.syncStatusSyncing);
    }
    final startingWorkspaceId = ref
        .read(activeWorkspaceProvider)
        .asData
        ?.value
        .id;
    state = state.copyWith(isBusy: true);
    try {
      final currentTaskState = ref.read(taskNotifierProvider);
      if (currentTaskState.hasError && !currentTaskState.hasValue) {
        ref.invalidate(taskNotifierProvider);
        await ref.read(taskNotifierProvider.future);
      } else {
        await ref.read(taskNotifierProvider.notifier).syncFromRemote();
      }
      if (!_isStillActiveWorkspace(startingWorkspaceId)) {
        return const V2ActionSucceeded();
      }
      return _inspectPostSyncResult(localizations);
    } on Object catch (error) {
      AppLogger.event(
        LogLevel.warn,
        LogTag.sync,
        'sync.v2.sync_now_failed',
        error: error,
      );
      return V2ActionPersistFailed(
        message: _formatSyncError(error, localizations),
      );
    } finally {
      if (_isStillActiveWorkspace(startingWorkspaceId)) {
        state = state.copyWith(isBusy: false);
      }
    }
  }

  /// Resets transient busy state whenever the active workspace unloads or switches.
  void _handleWorkspaceIdChanged(
    String? previousWorkspaceId,
    String? nextWorkspaceId,
  ) {
    if (nextWorkspaceId == null) {
      if (previousWorkspaceId != null) {
        state = const SyncV2ControllerState();
      }
      return;
    }
    if (_activeWorkspaceId != null && _activeWorkspaceId != nextWorkspaceId) {
      state = const SyncV2ControllerState();
    }
    _activeWorkspaceId = nextWorkspaceId;
  }

  /// Evaluates [syncStateProvider] and [taskNotifierProvider] after a non-throwing sync pass.
  V2ActionResult _inspectPostSyncResult(AppLocalizations localizations) {
    final latestSyncState = ref.read(syncStateProvider);
    if (latestSyncState.syncOutcome case final outcome?) {
      return V2ActionPersistFailed(
        message: _formatSyncOutcomeMessage(outcome, localizations),
      );
    }
    if (latestSyncState.fileReadReport case final fileReadReport?
        when fileReadReport.hasFailure) {
      final formatted = localizations.formatStorageFileReadMessage(
        fileReadReport,
      );
      if (formatted.isNotEmpty) {
        return V2ActionPersistFailed(message: formatted);
      }
    }
    final errorMessage = latestSyncState.errorMessage;
    if (errorMessage != null && errorMessage.trim().isNotEmpty) {
      return V2ActionPersistFailed(message: AppLogger.sanitize(errorMessage));
    }
    final latestTaskState = ref.read(taskNotifierProvider);
    if (latestTaskState.hasError) {
      final error = latestTaskState.error;
      return V2ActionPersistFailed(
        message: error != null
            ? _formatSyncError(error, localizations)
            : localizations.syncStatusError,
      );
    }
    return const V2ActionSucceeded();
  }

  /// Returns `true` when this notifier is still mounted and on [startingWorkspaceId].
  bool _isStillActiveWorkspace(String? startingWorkspaceId) {
    if (!ref.mounted) {
      return false;
    }
    if (startingWorkspaceId == null) {
      return true;
    }
    final currentWorkspaceId = ref
        .read(activeWorkspaceProvider)
        .asData
        ?.value
        .id;
    return currentWorkspaceId == startingWorkspaceId;
  }

  /// Resolves [AppLocalizations] from an explicit [locale] override or [appLocaleProvider].
  AppLocalizations _resolveLocalizations(Locale? locale) =>
      lookupAppLocalizations(locale ?? ref.read(appLocaleProvider));
}

/// Immutable transient busy state for [SyncV2Controller].
@immutable
class SyncV2ControllerState {
  /// Creates a [SyncV2ControllerState].
  const SyncV2ControllerState({this.isBusy = false});

  /// Whether a synchronization or resolution operation is currently running.
  final bool isBusy;

  /// Returns a copy of this [SyncV2ControllerState] with updated fields.
  SyncV2ControllerState copyWith({bool? isBusy}) =>
      SyncV2ControllerState(isBusy: isBusy ?? this.isBusy);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SyncV2ControllerState && other.isBusy == isBusy;
  }

  @override
  int get hashCode => isBusy.hashCode;
}

/// Builds immutable [ResolutionEntryViewModel] entries across tasks, labels, and locations.
List<ResolutionEntryViewModel> _buildResolutionEntries({
  required Iterable<String> taskIds,
  required Iterable<String> labelIds,
  required Iterable<String> locationIds,
  required TaskBoard? board,
  required AppLocalizations localizations,
  required String detail,
}) {
  final entries = <ResolutionEntryViewModel>[];
  for (final taskId in taskIds) {
    entries.add(
      ResolutionEntryViewModel(
        kind: EntityKind.task,
        kindBadgeLabel: localizations.entityKindTaskBadge,
        id: taskId,
        title: _resolveDisplayTitle(
          board?.findTask(taskId)?.title,
          fallbackId: taskId,
        ),
        detail: detail,
      ),
    );
  }
  for (final labelId in labelIds) {
    entries.add(
      ResolutionEntryViewModel(
        kind: EntityKind.label,
        kindBadgeLabel: localizations.entityKindLabelBadge,
        id: labelId,
        title: _resolveDisplayTitle(
          board?.findLabel(labelId)?.name,
          fallbackId: labelId,
        ),
        detail: detail,
      ),
    );
  }
  for (final locationId in locationIds) {
    entries.add(
      ResolutionEntryViewModel(
        kind: EntityKind.location,
        kindBadgeLabel: localizations.entityKindLocationBadge,
        id: locationId,
        title: _resolveDisplayTitle(
          board?.findLocation(locationId)?.name,
          fallbackId: locationId,
        ),
        detail: detail,
      ),
    );
  }
  return entries;
}

/// Formats optional WGS-84 coordinates from [fix] to six decimal places.
String _formatCoordinates6dp(LocationFix? fix) {
  if (fix == null) {
    return '';
  }
  if ((fix.latitude, fix.longitude) case (final latitude?, final longitude?)) {
    final normalizedLatitude = latitude == 0 ? 0.0 : latitude;
    final normalizedLongitude = longitude == 0 ? 0.0 : longitude;
    return '${normalizedLatitude.toStringAsFixed(6)}, '
        '${normalizedLongitude.toStringAsFixed(6)}';
  }
  return '';
}

/// Maps an optional domain [LocationSource] to its localized display label.
String _formatLocationSourceLabel(
  LocationSource? source,
  AppLocalizations localizations,
) {
  return switch (source) {
    LocationSource.gps => localizations.locationSourceGps,
    LocationSource.system => localizations.locationSourceSystem,
    LocationSource.internet => localizations.locationSourceInternet,
    null => '',
  };
}

/// Maps a domain [LocationStatus] to its localized status description.
String _formatLocationStatusLabel(
  LocationStatus status,
  AppLocalizations localizations,
) {
  return switch (status) {
    LocationStatus.disabled => localizations.locationStatusUnavailable,
    LocationStatus.searching => localizations.locationStatusSearching,
    LocationStatus.found => localizations.locationStatusFound,
    LocationStatus.unavailable => localizations.locationStatusUnavailable,
  };
}

/// Formats a sanitized localized message for synchronization or resolution [error].
String _formatSyncError(
  Object error,
  AppLocalizations localizations, {
  bool isSave = false,
}) {
  if (error is TdfSyncOutcomeException) {
    return _formatSyncOutcomeMessage(error, localizations);
  }
  if (error is StorageFileReadException) {
    final formatted = localizations.formatStorageFileReadMessage(error.report);
    if (formatted.isNotEmpty) {
      return formatted;
    }
    return AppLogger.sanitize(error.message);
  }
  if (error is LocalFileException) {
    return AppLogger.sanitize(error.message);
  }
  if (error is WebDavException) {
    return AppLogger.sanitize(error.toString());
  }
  if (error is WorkspaceException) {
    return localizations.localizeWorkspaceError(error);
  }
  if (error is TdfException) {
    return AppLogger.sanitize(error.message);
  }
  final details = AppLogger.sanitize(error.toString());
  return isSave
      ? localizations.errorUnexpectedSave(details)
      : localizations.errorUnexpectedLoad(details);
}

/// Maps a [TdfSyncOutcomeException] exhaustively to its localized banner message.
String _formatSyncOutcomeMessage(
  TdfSyncOutcomeException outcome,
  AppLocalizations localizations,
) {
  return switch (outcome.kind) {
    TdfSyncOutcomeKind.deletionConflict =>
      localizations.syncConflictDeletionBanner,
    TdfSyncOutcomeKind.recoveryRequired =>
      localizations.syncConflictRecoveryBanner,
    TdfSyncOutcomeKind.syncGenerationRollback =>
      localizations.syncErrorGenerationRollbackBanner,
  };
}

/// Maps model-free [ConflictDecisionChoice] entries to domain [TdfDeletionResolution] values.
Map<String, TdfDeletionResolution> _mapConflictDecisions(
  Map<String, ConflictDecisionChoice> decisions,
) {
  return <String, TdfDeletionResolution>{
    for (final entry in decisions.entries)
      entry.key: switch (entry.value) {
        ConflictDecisionChoice.keepEdit => TdfDeletionResolution.undelete,
        ConflictDecisionChoice.confirmDelete => TdfDeletionResolution.delete,
      },
  };
}

/// Maps domain [LocationStatus] exhaustively to presentation [ShellLocationStatusKind].
ShellLocationStatusKind _mapLocationStatus(LocationStatus status) {
  return switch (status) {
    LocationStatus.disabled => ShellLocationStatusKind.disabled,
    LocationStatus.searching => ShellLocationStatusKind.searching,
    LocationStatus.found => ShellLocationStatusKind.found,
    LocationStatus.unavailable => ShellLocationStatusKind.unavailable,
  };
}

/// Maps model-free [RecoveryDecisionChoice] entries to domain [TdfRecoveryResolution] values.
Map<String, TdfRecoveryResolution> _mapRecoveryDecisions(
  Map<String, RecoveryDecisionChoice> decisions,
) {
  return <String, TdfRecoveryResolution>{
    for (final entry in decisions.entries)
      entry.key: switch (entry.value) {
        RecoveryDecisionChoice.recoverAsNew =>
          TdfRecoveryResolution.recoverAsNew,
        RecoveryDecisionChoice.discardLocal => TdfRecoveryResolution.discard,
      },
  };
}

/// Returns [candidate] when non-empty, otherwise falls back to [fallbackId].
String _resolveDisplayTitle(String? candidate, {required String fallbackId}) {
  if (candidate != null && candidate.trim().isNotEmpty) {
    return candidate;
  }
  return fallbackId;
}

/// Resolves the localized place name for [locationState], applying [AppLocalizations.locationPlaceUnknown] when a fix lacks a place name.
String _resolvePlaceLabel(
  LocationState locationState,
  AppLocalizations localizations,
) {
  final fix = locationState.fix;
  final rawPlace = fix?.placeName?.trim();
  if (rawPlace != null && rawPlace.isNotEmpty) {
    return rawPlace;
  }
  if (fix != null || locationState.status == LocationStatus.found) {
    return localizations.locationPlaceUnknown;
  }
  return '';
}
