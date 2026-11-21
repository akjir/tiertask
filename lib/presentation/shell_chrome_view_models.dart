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
import '../models/location_state.dart';
import '../models/task_board.dart';
import '../models/task_board_evaluator.dart';
import '../models/tdf_error.dart';
import '../models/tdf_sync_metadata.dart';
import '../models/webdav_config.dart';
import '../providers/config_providers.dart';
import '../providers/location_providers.dart';
import '../providers/sync_providers.dart';
import '../providers/task_providers.dart';
import '../providers/workspace_providers.dart';
import 'app_shell_controller.dart';
import 'board_presentation_providers.dart';
import 'shell_models.dart';
import 'view_model_primitives.dart';

/// Provides the model-free top chrome bar projection for `lib/ui/`.
final boardChromeViewModelProvider = Provider<BoardChromeViewModel>((ref) {
  final buildProfile = ref.watch(appBuildProfileProvider);
  final locale = ref.watch(appLocaleProvider);
  final localizations = lookupAppLocalizations(locale);
  final workspaceName = ref.watch(
    activeWorkspaceProvider.select(
      (workspace) => workspace.asData?.value.name ?? AppWorkspace.defaultName,
    ),
  );
  final workspaceId = ref.watch(
    activeWorkspaceProvider.select(
      (workspace) => workspace.asData?.value.id ?? AppWorkspace.defaultId,
    ),
  );
  final storageMode = ref.watch(
    webDavConfigProvider.select(
      (config) => config.asData?.value.storageMode ?? StorageMode.local,
    ),
  );
  final locationEnabled = ref.watch(locationEnabledProvider);
  final locationStatus = ref.watch(
    locationStateProvider.select((state) => state.status),
  );
  final syncState = ref.watch(syncStateProvider);
  final undoState = ref.watch(taskUndoStateProvider);
  final activeLabelId = ref.watch(
    appShellControllerProvider.select((shell) => shell.activeLabelId),
  );
  final activeFilterLabelName = ref.watch(
    taskNotifierProvider.select((boardAsync) {
      if (activeLabelId == null) {
        return null;
      }
      return boardAsync.asData?.value.findLabel(activeLabelId)?.name;
    }),
  );

  final syncStatusKind = _resolveSyncStatusKind(
    storageMode: storageMode,
    syncState: syncState,
  );
  final syncStatusLabel = _formatSyncStatusLabel(syncStatusKind, localizations);
  final showWindowControls = ref.watch(supportsDesktopWindowControlsProvider);

  return BoardChromeViewModel(
    isDevBuild: buildProfile.isDev,
    activeWorkspaceId: workspaceId,
    activeWorkspaceName: workspaceName,
    locationEnabled: locationEnabled,
    locationStatusKind: _mapLocationStatus(locationStatus),
    locationTooltip: localizations.tooltipLocationStatus,
    showWindowControls: showWindowControls,
    syncStatusKind: syncStatusKind,
    syncStatusLabel: syncStatusLabel,
    hasWebDav: storageMode.usesWebDav,
    canUndo: undoState.canUndo,
    undoStackDepth: undoState.stackDepth,
    activeFilterLabelName: activeFilterLabelName,
  );
});

/// Provides the model-free Raw `TDF 0.8.0` preview projection for `lib/ui/`.
final rawTdfViewModelProvider = Provider<RawTdfViewModel>((ref) {
  final locale = ref.watch(appLocaleProvider);
  final localizations = lookupAppLocalizations(locale);
  final board = ref.watch(
    taskNotifierProvider.select(
      (boardAsync) => boardAsync.asData?.value ?? TaskBoard.empty(),
    ),
  );
  final previewResult = ref
      .watch(tdfPreviewControllerProvider)
      .serializeBoard(board, locale: locale);
  return switch (previewResult) {
    TdfPreviewSuccess(:final content) => _buildRawTdfSuccess(
      content,
      localizations,
    ),
    TdfPreviewLimitExceeded() => RawTdfViewModel(
      isLimitExceeded: true,
      content: '',
      byteCount: maxTdfFileBytes + 1,
      lineCount: maxTdfLineCount + 1,
      statsLabel: localizations.rawTdfStatsSummary(
        '${maxTdfFileBytes + 1}',
        '${maxTdfLineCount + 1}',
      ),
      limitTitle: localizations.rawTdfLimitExceededTitle,
      limitDescription: localizations.rawTdfLimitExceededDescription,
    ),
  };
});

/// Provides the model-free theme preset, brightness mode, and locale snapshot for `lib/main.dart` and `lib/ui/`.
final shellThemeStateProvider = Provider<ShellThemeState>((ref) {
  final palette = ref.watch(appThemePaletteProvider);
  final themeMode = ref.watch(appThemeModeProvider);
  final locale = ref.watch(appLocaleProvider);
  return ShellThemeState(
    presetKey: switch (palette) {
      AppThemePalette.calm => AppThemePresetKey.calm,
      AppThemePalette.plumUmber => AppThemePresetKey.plumUmber,
    },
    themeMode: switch (themeMode) {
      AppThemeMode.system => ShellThemeMode.system,
      AppThemeMode.light => ShellThemeMode.light,
      AppThemeMode.dark => ShellThemeMode.dark,
    },
    locale: locale,
  );
});

/// Provides the model-free sidebar/drawer projection for `lib/ui/`.
final sidebarViewModelProvider = Provider<SidebarViewModel>((ref) {
  final locale = ref.watch(appLocaleProvider);
  final localizations = lookupAppLocalizations(locale);
  final activeLabelId = ref.watch(
    appShellControllerProvider.select((shell) => shell.activeLabelId),
  );
  final labelsFilterOpen = ref.watch(
    appShellControllerProvider.select((shell) => shell.sidebarLabelsFilterOpen),
  );
  final labelsFilterQuery = ref.watch(
    appShellControllerProvider.select(
      (shell) => shell.sidebarLabelsFilterQuery,
    ),
  );
  final locationsFilterOpen = ref.watch(
    appShellControllerProvider.select(
      (shell) => shell.sidebarLocationsFilterOpen,
    ),
  );
  final locationsFilterQuery = ref.watch(
    appShellControllerProvider.select(
      (shell) => shell.sidebarLocationsFilterQuery,
    ),
  );
  final evaluatedAsync = ref.watch(evaluatedBoardProvider(activeLabelId));
  final board = evaluatedAsync.asData?.value ?? TaskBoard.empty();
  final rawBoard =
      ref.watch(
        taskNotifierProvider.select((asyncBoard) => asyncBoard.asData?.value),
      ) ??
      TaskBoard.empty();
  final storageMode = ref.watch(
    webDavConfigProvider.select(
      (config) => config.asData?.value.storageMode ?? StorageMode.local,
    ),
  );
  final diagnosticsEnabled = ref.watch(diagnosticsEnabledProvider);
  final versionModel = ref.watch(appVersionViewModelProvider);

  final tierItems = <SidebarTierItemViewModel>[
    for (final tier in ShellTier.values)
      SidebarTierItemViewModel(
        tier: tier,
        label: ViewModelFormatters.tierName(tier, localizations),
        count: board.tasksForTier(ViewModelFormatters.toTaskTier(tier)).length,
        wipLimit: ViewModelFormatters.tierWipLimit(tier),
      ),
  ];

  final sortedLabels = TaskBoardEvaluator.sortLabelsAlphabetically(
    rawBoard.labels,
  );
  final normalizedLabelNeedle = labelsFilterOpen
      ? labelsFilterQuery.trim().toLowerCase()
      : '';
  final visibleLabels = <SidebarLabelItemViewModel>[];
  int? activeLabelColorValue;
  for (final label in sortedLabels) {
    final colorValue = ViewModelFormatters.parseLabelColorValue(label.color);
    if (label.id == activeLabelId) {
      activeLabelColorValue = colorValue;
    }
    if (normalizedLabelNeedle.isNotEmpty &&
        !label.name.toLowerCase().contains(normalizedLabelNeedle)) {
      continue;
    }
    visibleLabels.add(
      SidebarLabelItemViewModel(
        id: label.id,
        name: label.name,
        colorValue: colorValue,
        isScoped: label.isScoped,
        openCount: rawBoard.openTaskCountForLabel(label.id),
        isSelected: label.id == activeLabelId,
      ),
    );
  }

  final sortedLocations = TaskBoardEvaluator.sortLocationsAlphabetically(
    rawBoard.locations,
  );
  final normalizedLocationNeedle = locationsFilterOpen
      ? locationsFilterQuery.trim().toLowerCase()
      : '';
  final visibleLocations = <SidebarLocationItemViewModel>[
    for (final location in sortedLocations)
      if (normalizedLocationNeedle.isEmpty ||
          location.name.toLowerCase().contains(normalizedLocationNeedle))
        SidebarLocationItemViewModel(
          id: location.id,
          name: location.name,
          openCount: rawBoard.openTaskCountForLocation(location.id),
        ),
  ];

  final globalOpenCount = rawBoard.allTasks
      .where((task) => !task.isCompleted)
      .length;

  return SidebarViewModel(
    tierItems: tierItems,
    allTasksCount: globalOpenCount,
    labels: visibleLabels,
    totalLabelCount: sortedLabels.length,
    activeLabelColorValue: activeLabelColorValue,
    locations: visibleLocations,
    totalLocationCount: sortedLocations.length,
    showSyncWebDav: storageMode.usesWebDav,
    showDiagnosticLog: diagnosticsEnabled,
    versionLabel: versionModel.versionLabel,
    buildSuffix: versionModel.buildSuffix,
  );
});

/// Immutable top chrome bar projection.
@immutable
class BoardChromeViewModel {
  /// Creates a [BoardChromeViewModel].
  const BoardChromeViewModel({
    required this.isDevBuild,
    required this.activeWorkspaceId,
    required this.activeWorkspaceName,
    required this.locationEnabled,
    required this.locationStatusKind,
    required this.locationTooltip,
    required this.showWindowControls,
    required this.syncStatusKind,
    required this.syncStatusLabel,
    required this.hasWebDav,
    required this.canUndo,
    required this.undoStackDepth,
    this.activeFilterLabelName,
  });

  /// Display name of the currently active label filter, if any.
  final String? activeFilterLabelName;

  /// Identifier of the active workspace.
  final String activeWorkspaceId;

  /// Display name of the active workspace.
  final String activeWorkspaceName;

  /// Whether at least one undo entry is available.
  final bool canUndo;

  /// Whether WebDAV synchronization is enabled for the active workspace.
  final bool hasWebDav;

  /// Whether this binary runs under the `DEV` build profile (`U-BRAND-002`).
  final bool isDevBuild;

  /// Whether foreground location determination is enabled in workspace settings.
  final bool locationEnabled;

  /// Current foreground location lookup state.
  final ShellLocationStatusKind locationStatusKind;

  /// Localized tooltip for the chrome Location Status button.
  final String locationTooltip;

  /// Whether custom frameless desktop window controls and chrome drag/maximize actions are enabled (`true` on Linux/Windows, `false` on Android).
  final bool showWindowControls;

  /// Current synchronization status category.
  final ShellSyncStatusKind syncStatusKind;

  /// Localized label shown beside the chrome Sync icon on desktop.
  final String syncStatusLabel;

  /// Current Undo stack depth (`0..10`).
  final int undoStackDepth;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BoardChromeViewModel &&
        other.isDevBuild == isDevBuild &&
        other.activeWorkspaceId == activeWorkspaceId &&
        other.activeWorkspaceName == activeWorkspaceName &&
        other.locationEnabled == locationEnabled &&
        other.locationStatusKind == locationStatusKind &&
        other.locationTooltip == locationTooltip &&
        other.showWindowControls == showWindowControls &&
        other.syncStatusKind == syncStatusKind &&
        other.syncStatusLabel == syncStatusLabel &&
        other.hasWebDav == hasWebDav &&
        other.canUndo == canUndo &&
        other.undoStackDepth == undoStackDepth &&
        other.activeFilterLabelName == activeFilterLabelName;
  }

  @override
  int get hashCode => Object.hash(
    isDevBuild,
    activeWorkspaceId,
    activeWorkspaceName,
    locationEnabled,
    locationStatusKind,
    locationTooltip,
    showWindowControls,
    syncStatusKind,
    syncStatusLabel,
    hasWebDav,
    canUndo,
    undoStackDepth,
    activeFilterLabelName,
  );
}

/// Immutable Raw `TDF 0.8.0` preview view model.
@immutable
class RawTdfViewModel {
  /// Creates a [RawTdfViewModel].
  const RawTdfViewModel({
    required this.isLimitExceeded,
    required this.content,
    required this.byteCount,
    required this.lineCount,
    required this.statsLabel,
    required this.limitTitle,
    required this.limitDescription,
  });

  /// UTF-8 byte count of the serialized document.
  final int byteCount;

  /// Serialized canonical TDF text, or empty when [isLimitExceeded] is true.
  final String content;

  /// Whether canonical `1 MiB` or `16,384`-line bounds were exceeded.
  final bool isLimitExceeded;

  /// Localized warning description when [isLimitExceeded] is true.
  final String limitDescription;

  /// Localized warning title when [isLimitExceeded] is true.
  final String limitTitle;

  /// Line count of the serialized document.
  final int lineCount;

  /// Localized telemetry summary (`<bytes> bytes / 1 MiB · <lines> lines / 16,384 max`).
  final String statsLabel;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RawTdfViewModel &&
        other.isLimitExceeded == isLimitExceeded &&
        other.content == content &&
        other.byteCount == byteCount &&
        other.lineCount == lineCount &&
        other.statsLabel == statsLabel &&
        other.limitTitle == limitTitle &&
        other.limitDescription == limitDescription;
  }

  @override
  int get hashCode => Object.hash(
    isLimitExceeded,
    content,
    byteCount,
    lineCount,
    statsLabel,
    limitTitle,
    limitDescription,
  );
}

/// Immutable sidebar label row model.
@immutable
class SidebarLabelItemViewModel {
  /// Creates a [SidebarLabelItemViewModel].
  const SidebarLabelItemViewModel({
    required this.id,
    required this.name,
    required this.isScoped,
    required this.openCount,
    required this.isSelected,
    this.colorValue,
  });

  /// Optional ARGB color integer for the color dot.
  final int? colorValue;

  /// Canonical label identifier.
  final String id;

  /// Whether this label is a Scoped Queue.
  final bool isScoped;

  /// Whether this label is the active task filter.
  final bool isSelected;

  /// Label display name.
  final String name;

  /// Count of open tasks referencing this label.
  final int openCount;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SidebarLabelItemViewModel &&
        other.id == id &&
        other.name == name &&
        other.colorValue == colorValue &&
        other.isScoped == isScoped &&
        other.openCount == openCount &&
        other.isSelected == isSelected;
  }

  @override
  int get hashCode =>
      Object.hash(id, name, colorValue, isScoped, openCount, isSelected);
}

/// Immutable sidebar location row model.
@immutable
class SidebarLocationItemViewModel {
  /// Creates a [SidebarLocationItemViewModel].
  const SidebarLocationItemViewModel({
    required this.id,
    required this.name,
    required this.openCount,
  });

  /// Canonical location identifier.
  final String id;

  /// Location display name.
  final String name;

  /// Count of open tasks referencing this location.
  final int openCount;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SidebarLocationItemViewModel &&
        other.id == id &&
        other.name == name &&
        other.openCount == openCount;
  }

  @override
  int get hashCode => Object.hash(id, name, openCount);
}

/// Immutable sidebar tier row model.
@immutable
class SidebarTierItemViewModel {
  /// Creates a [SidebarTierItemViewModel].
  const SidebarTierItemViewModel({
    required this.tier,
    required this.label,
    required this.count,
    this.wipLimit,
  });

  /// Current task count in [tier].
  final int count;

  /// Localized tier display name.
  final String label;

  /// Target tier enum.
  final ShellTier tier;

  /// Optional soft WIP limit (`3` for Focus, `5` for Ready).
  final int? wipLimit;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SidebarTierItemViewModel &&
        other.tier == tier &&
        other.label == label &&
        other.count == count &&
        other.wipLimit == wipLimit;
  }

  @override
  int get hashCode => Object.hash(tier, label, count, wipLimit);
}

/// Immutable sidebar and compact drawer projection.
@immutable
class SidebarViewModel {
  /// Creates a [SidebarViewModel].
  SidebarViewModel({
    required Iterable<SidebarTierItemViewModel> tierItems,
    required this.allTasksCount,
    required Iterable<SidebarLabelItemViewModel> labels,
    required this.totalLabelCount,
    required this.activeLabelColorValue,
    required Iterable<SidebarLocationItemViewModel> locations,
    required this.totalLocationCount,
    required this.showSyncWebDav,
    required this.showDiagnosticLog,
    required this.versionLabel,
    required this.buildSuffix,
  }) : tierItems = List<SidebarTierItemViewModel>.unmodifiable(tierItems),
       labels = List<SidebarLabelItemViewModel>.unmodifiable(labels),
       locations = List<SidebarLocationItemViewModel>.unmodifiable(locations);

  /// Color value of the active filter label for collapsed header dot indicator.
  final int? activeLabelColorValue;

  /// Total open task count shown on the `All Tasks` row.
  final int allTasksCount;

  /// SemVer build metadata suffix (`+<hash>`) rendered dimmed in the footer.
  final String buildSuffix;

  /// Filtered alphabetical label rows.
  final List<SidebarLabelItemViewModel> labels;

  /// Filtered alphabetical location rows.
  final List<SidebarLocationItemViewModel> locations;

  /// Whether the `Diagnostic Log` tools row is shown.
  final bool showDiagnosticLog;

  /// Whether the `Sync with WebDAV` tools row is shown.
  final bool showSyncWebDav;

  /// Fixed six-tier rows with live counts.
  final List<SidebarTierItemViewModel> tierItems;

  /// Unfiltered label count displayed when the Labels section is collapsed.
  final int totalLabelCount;

  /// Unfiltered location count displayed when the Locations section is collapsed.
  final int totalLocationCount;

  /// Primary SemVer version text (`Version X.Y.Z`) pinned to the sidebar footer.
  final String versionLabel;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SidebarViewModel &&
        listEquals(other.tierItems, tierItems) &&
        other.allTasksCount == allTasksCount &&
        listEquals(other.labels, labels) &&
        other.totalLabelCount == totalLabelCount &&
        other.activeLabelColorValue == activeLabelColorValue &&
        listEquals(other.locations, locations) &&
        other.totalLocationCount == totalLocationCount &&
        other.showSyncWebDav == showSyncWebDav &&
        other.showDiagnosticLog == showDiagnosticLog &&
        other.versionLabel == versionLabel &&
        other.buildSuffix == buildSuffix;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(tierItems),
    allTasksCount,
    Object.hashAll(labels),
    totalLabelCount,
    activeLabelColorValue,
    Object.hashAll(locations),
    totalLocationCount,
    showSyncWebDav,
    showDiagnosticLog,
    versionLabel,
    buildSuffix,
  );
}

/// Builds a [RawTdfViewModel] for a successful serialization result.
RawTdfViewModel _buildRawTdfSuccess(
  String content,
  AppLocalizations localizations,
) {
  final bytes = utf8.encode(content).length;
  final lines = content.isEmpty ? 0 : '\n'.allMatches(content).length;
  final exceeded = bytes > maxTdfFileBytes || lines > maxTdfLineCount;
  return RawTdfViewModel(
    isLimitExceeded: exceeded,
    content: exceeded ? '' : content,
    byteCount: bytes,
    lineCount: lines,
    statsLabel: localizations.rawTdfStatsSummary('$bytes', '$lines'),
    limitTitle: localizations.rawTdfLimitExceededTitle,
    limitDescription: localizations.rawTdfLimitExceededDescription,
  );
}

/// Maps [ShellSyncStatusKind] to its localized top chrome label.
String _formatSyncStatusLabel(
  ShellSyncStatusKind kind,
  AppLocalizations localizations,
) {
  return switch (kind) {
    ShellSyncStatusKind.localOnly => localizations.syncStatusLocalOnly,
    ShellSyncStatusKind.synced => localizations.syncStatusSynced,
    ShellSyncStatusKind.syncing => localizations.syncStatusSyncing,
    ShellSyncStatusKind.conflict => localizations.syncStatusConflict,
    ShellSyncStatusKind.error => localizations.syncStatusError,
  };
}

/// Maps domain [LocationStatus] to presentation [ShellLocationStatusKind].
ShellLocationStatusKind _mapLocationStatus(LocationStatus status) {
  return switch (status) {
    LocationStatus.disabled => ShellLocationStatusKind.disabled,
    LocationStatus.searching => ShellLocationStatusKind.searching,
    LocationStatus.found => ShellLocationStatusKind.found,
    LocationStatus.unavailable => ShellLocationStatusKind.unavailable,
  };
}

/// Resolves the top chrome [ShellSyncStatusKind] from storage mode and [SyncState].
ShellSyncStatusKind _resolveSyncStatusKind({
  required StorageMode storageMode,
  required SyncState syncState,
}) {
  if (syncState.isSyncing) {
    return ShellSyncStatusKind.syncing;
  }
  if (syncState.hasOpenConflict) {
    final outcomeKind = syncState.syncOutcome?.kind;
    if (outcomeKind == TdfSyncOutcomeKind.syncGenerationRollback) {
      return ShellSyncStatusKind.error;
    }
    return ShellSyncStatusKind.conflict;
  }
  if (syncState.errorMessage != null || syncState.fileReadReport != null) {
    return ShellSyncStatusKind.error;
  }
  if (!storageMode.usesWebDav) {
    return ShellSyncStatusKind.localOnly;
  }
  return ShellSyncStatusKind.synced;
}
