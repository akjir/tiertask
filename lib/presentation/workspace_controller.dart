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
import '../l10n/tier_localization_extension.dart';
import '../models/app_workspace.dart';
import '../models/tdf_file_path.dart';
import '../providers/config_providers.dart';
import '../providers/workspace_providers.dart';
import '../services/app_logger.dart';
import 'floating_notice_controller.dart';
import 'shell_models.dart';

/// Provides the model-free [WorkspaceController] and its [WorkspaceControllerState].
final workspaceControllerProvider =
    NotifierProvider<WorkspaceController, WorkspaceControllerState>(
      WorkspaceController.new,
    );

/// Provides the model-free [WorkspacesViewModel] listing persisted workspaces and active selection state.
final workspacesViewModelProvider = Provider<WorkspacesViewModel>((ref) {
  final activeWorkspaceAsync = ref.watch(activeWorkspaceProvider);
  final summariesAsync = ref.watch(workspaceSummariesProvider);
  final activeWorkspace =
      activeWorkspaceAsync.value ?? AppWorkspace.defaultWorkspace;
  final summaries =
      summariesAsync.value ?? <WorkspaceSummary>[activeWorkspace.summary];
  final canDelete = summaries.length > 1;
  final rows = <WorkspaceRowViewModel>[
    for (final summary in summaries)
      WorkspaceRowViewModel(
        id: summary.id,
        name: summary.name,
        localFileName: TdfFilePath.extractFileNameFromPath(
          summary.localFilePath,
        ),
        isActive: summary.id == activeWorkspace.id,
        canDelete: canDelete,
      ),
  ];
  final isLoading =
      (activeWorkspaceAsync.isLoading && !activeWorkspaceAsync.hasValue) ||
      (summariesAsync.isLoading && !summariesAsync.hasValue);

  return WorkspacesViewModel(
    activeWorkspaceId: activeWorkspace.id,
    workspaces: rows,
    canCreateMore: summaries.length < AppWorkspace.maxWorkspaces,
    isLoading: isLoading,
    maxWorkspaces: AppWorkspace.maxWorkspaces,
  );
});

/// Immutable model-free presentation row for one workspace entry in the workspace manager.
@immutable
class WorkspaceRowViewModel {
  /// Creates a [WorkspaceRowViewModel].
  const WorkspaceRowViewModel({
    required this.id,
    required this.name,
    required this.localFileName,
    required this.isActive,
    required this.canDelete,
  });

  /// Whether deleting this workspace is allowed (requires more than one workspace).
  final bool canDelete;

  /// Canonical workspace identifier.
  final String id;

  /// Whether this workspace is currently active in memory.
  final bool isActive;

  /// Trailing `.tdf` file name extracted from the workspace local file path.
  final String localFileName;

  /// User-facing workspace display name.
  final String name;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WorkspaceRowViewModel &&
        other.id == id &&
        other.name == name &&
        other.localFileName == localFileName &&
        other.isActive == isActive &&
        other.canDelete == canDelete;
  }

  @override
  int get hashCode => Object.hash(id, name, localFileName, isActive, canDelete);
}

/// Model-free intent controller managing workspace creation, switching, renaming, and deletion.
class WorkspaceController extends Notifier<WorkspaceControllerState> {
  @override
  WorkspaceControllerState build() => const WorkspaceControllerState();

  /// Creates a workspace named [rawName], optionally activating it and emitting a localized switch notice.
  Future<ActionResult> createWorkspace(
    String rawName, {
    bool activate = true,
    Locale? locale,
  }) {
    return _runGuardedMutation(
      operation: 'create',
      locale: locale,
      action: (fallbackLocale) async {
        final created = await ref
            .read(activeWorkspaceProvider.notifier)
            .createWorkspace(rawName, activate: activate);
        if (!activate) {
          return ActionSucceeded(entityId: created.id);
        }
        final localizations = _resolveLocalizations(locale, fallbackLocale);
        final noticeMessage = localizations.workspaceSwitchedNotice(
          created.name,
        );
        if (ref.mounted) {
          ref
              .read(floatingNoticeControllerProvider.notifier)
              .showNotice(noticeMessage, tone: NoticeTone.neutral);
        }
        return ActionSucceeded(
          entityId: created.id,
          noticeMessage: noticeMessage,
        );
      },
    );
  }

  /// Deletes the workspace identified by [workspaceId] and maps domain errors to localized results.
  Future<ActionResult> deleteWorkspace(String workspaceId, {Locale? locale}) {
    return _runGuardedMutation(
      operation: 'delete',
      locale: locale,
      action: (_) async {
        final activeAfterDelete = await ref
            .read(activeWorkspaceProvider.notifier)
            .deleteWorkspace(workspaceId);
        return ActionSucceeded(entityId: activeAfterDelete.id);
      },
    );
  }

  /// Renames the workspace identified by [workspaceId] to [rawName].
  Future<ActionResult> renameWorkspace(
    String workspaceId,
    String rawName, {
    Locale? locale,
  }) {
    return _runGuardedMutation(
      operation: 'rename',
      locale: locale,
      action: (_) async {
        final renamed = await ref
            .read(activeWorkspaceProvider.notifier)
            .renameWorkspace(workspaceId, rawName);
        return ActionSucceeded(entityId: renamed.id);
      },
    );
  }

  /// Returns the suggested lowercase `.tdf` filename derived from [rawName].
  String suggestWorkspaceFileName(String rawName) =>
      AppWorkspace.suggestFileName(rawName);

  /// Switches the active workspace to [workspaceId] and emits a localized switch toast when changed.
  Future<ActionResult> switchWorkspace(String workspaceId, {Locale? locale}) {
    return _runGuardedMutation(
      operation: 'switch',
      locale: locale,
      action: (fallbackLocale) async {
        final previousId = ref.read(activeWorkspaceProvider).value?.id;
        final nextWorkspace = await ref
            .read(activeWorkspaceProvider.notifier)
            .switchWorkspace(workspaceId);
        if (previousId == nextWorkspace.id) {
          return ActionSucceeded(entityId: nextWorkspace.id);
        }
        final localizations = _resolveLocalizations(locale, fallbackLocale);
        final noticeMessage = localizations.workspaceSwitchedNotice(
          nextWorkspace.name,
        );
        if (ref.mounted) {
          ref
              .read(floatingNoticeControllerProvider.notifier)
              .showNotice(noticeMessage, tone: NoticeTone.neutral);
        }
        return ActionSucceeded(
          entityId: nextWorkspace.id,
          noticeMessage: noticeMessage,
        );
      },
    );
  }

  /// Resolves [AppLocalizations] from an explicit [locale], live [appLocaleProvider], or [fallbackLocale].
  AppLocalizations _resolveLocalizations(
    Locale? locale,
    Locale fallbackLocale,
  ) {
    final Locale effectiveLocale =
        locale ?? (ref.mounted ? ref.read(appLocaleProvider) : fallbackLocale);
    return lookupAppLocalizations(effectiveLocale);
  }

  /// Runs [action] under the [WorkspaceControllerState.isBusy] guard and maps thrown failures.
  Future<ActionResult> _runGuardedMutation({
    required String operation,
    required Locale? locale,
    required Future<ActionSucceeded> Function(Locale fallbackLocale) action,
  }) async {
    if (state.isBusy) {
      return ActionValidationFailed(message: '');
    }
    final Locale fallbackLocale = locale ?? ref.read(appLocaleProvider);
    state = const WorkspaceControllerState(isBusy: true);
    try {
      return await action(fallbackLocale);
    } on WorkspaceException catch (error) {
      _logWorkspaceActionFailed(
        level: LogLevel.warn,
        operation: operation,
        kind: error.kind.name,
      );
      final localizations = _resolveLocalizations(locale, fallbackLocale);
      return _mapWorkspaceException(error, localizations);
    } on Exception {
      _logWorkspaceActionFailed(
        level: LogLevel.error,
        operation: operation,
        kind: 'unexpected',
      );
      final localizations = _resolveLocalizations(locale, fallbackLocale);
      return ActionPersistFailed(
        message: localizations.errorSettingsSaveFailed,
      );
    } finally {
      if (ref.mounted) {
        state = const WorkspaceControllerState(isBusy: false);
      }
    }
  }
}

/// Immutable transient execution state for [WorkspaceController].
@immutable
class WorkspaceControllerState {
  /// Creates a [WorkspaceControllerState].
  const WorkspaceControllerState({this.isBusy = false});

  /// Whether a workspace mutation is currently executing.
  final bool isBusy;

  /// Returns a copy of this [WorkspaceControllerState] with updated fields.
  WorkspaceControllerState copyWith({bool? isBusy}) =>
      WorkspaceControllerState(isBusy: isBusy ?? this.isBusy);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WorkspaceControllerState && other.isBusy == isBusy;
  }

  @override
  int get hashCode => isBusy.hashCode;
}

/// Immutable model-free projection of all persisted workspaces for the workspace manager modal.
@immutable
class WorkspacesViewModel {
  /// Creates a [WorkspacesViewModel].
  WorkspacesViewModel({
    required this.activeWorkspaceId,
    required Iterable<WorkspaceRowViewModel> workspaces,
    required this.canCreateMore,
    required this.isLoading,
    required this.maxWorkspaces,
  }) : workspaces = List<WorkspaceRowViewModel>.unmodifiable(workspaces);

  /// Identifier of the currently active workspace.
  final String activeWorkspaceId;

  /// Whether another workspace may be created within [maxWorkspaces].
  final bool canCreateMore;

  /// Whether initial workspace metadata is still loading.
  final bool isLoading;

  /// Maximum permitted number of persisted workspaces.
  final int maxWorkspaces;

  /// Unmodifiable ordered list of persisted workspace rows.
  final List<WorkspaceRowViewModel> workspaces;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WorkspacesViewModel &&
        other.activeWorkspaceId == activeWorkspaceId &&
        other.canCreateMore == canCreateMore &&
        other.isLoading == isLoading &&
        other.maxWorkspaces == maxWorkspaces &&
        listEquals(other.workspaces, workspaces);
  }

  @override
  int get hashCode => Object.hash(
    activeWorkspaceId,
    canCreateMore,
    isLoading,
    maxWorkspaces,
    Object.hashAll(workspaces),
  );
}

/// Emits a redacted diagnostic event when a workspace mutation fails.
void _logWorkspaceActionFailed({
  required LogLevel level,
  required String operation,
  required String kind,
}) {
  if (!AppLogger.shouldLog(level)) {
    return;
  }
  AppLogger.event(
    level,
    LogTag.ui,
    'ui.workspace_action_failed',
    fields: <String, Object?>{'operation': operation, 'kind': kind},
  );
}

/// Maps [error] exhaustively to [ActionValidationFailed] or [ActionPersistFailed].
ActionResult _mapWorkspaceException(
  WorkspaceException error,
  AppLocalizations localizations,
) {
  final message = localizations.localizeWorkspaceError(error);
  return switch (error.kind) {
    WorkspaceErrorKind.emptyName ||
    WorkspaceErrorKind.duplicateName ||
    WorkspaceErrorKind.duplicateFilePath ||
    WorkspaceErrorKind.invalidFilePath ||
    WorkspaceErrorKind.workspaceNotFound ||
    WorkspaceErrorKind.cannotDeleteLastWorkspace ||
    WorkspaceErrorKind.maxWorkspacesExceeded => ActionValidationFailed(
      message: message,
    ),
    WorkspaceErrorKind.corruptSettingsPayload ||
    WorkspaceErrorKind.unsupportedSettingsSchemaVersion ||
    WorkspaceErrorKind.credentialStorageUnavailable ||
    WorkspaceErrorKind.settingsPersistenceFailed => ActionPersistFailed(
      message: message,
    ),
  };
}
