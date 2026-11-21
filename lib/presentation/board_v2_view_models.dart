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
import '../l10n/storage_file_read_localization_extension.dart';
import '../l10n/tier_localization_extension.dart';
import '../models/app_workspace.dart';
import '../models/location_state.dart';
import '../models/storage_file_read_status.dart';
import '../models/task_board.dart';
import '../models/task_board_evaluator.dart';
import '../models/task_item.dart';
import '../models/task_tier.dart';
import '../models/tdf_error.dart';
import '../models/tdf_location.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_sync_metadata.dart';
import '../models/webdav_config.dart';
import '../providers/config_providers.dart';
import '../providers/location_providers.dart';
import '../providers/sync_providers.dart';
import '../providers/task_providers.dart';
import '../providers/workspace_providers.dart';
import 'app_shell_controller.dart';
import 'board_presentation_providers.dart';
import 'location_editor_controller.dart';
import 'task_editor_controller.dart';
import 'task_info_controller.dart';
import 'ui_v2_shell_models.dart';

/// Canonical rotating eight-color label presets (`spec/UI_DESIGN_SYSTEM.md` `U-COMP-007`).
const List<String> canonicalLabelPresetHexColors = <String>[
  '#2196F3',
  '#4CAF50',
  '#FF9100',
  '#E91E63',
  '#9C27B0',
  '#00BCD4',
  '#EB06FF',
  '#00E5FF',
];

/// Provides the model-free top chrome bar projection for `lib/ui_v2/`.
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

  return BoardChromeViewModel(
    isDevBuild: buildProfile.isDev,
    activeWorkspaceId: workspaceId,
    activeWorkspaceName: workspaceName,
    locationEnabled: locationEnabled,
    locationStatusKind: _mapLocationStatus(locationStatus),
    locationTooltip: localizations.tooltipLocationStatus,
    syncStatusKind: syncStatusKind,
    syncStatusLabel: syncStatusLabel,
    hasWebDav: storageMode.usesWebDav,
    canUndo: undoState.canUndo,
    undoStackDepth: undoState.stackDepth,
    activeFilterLabelName: activeFilterLabelName,
  );
});

/// Provides the model-free Labels manager projection for `lib/ui_v2/`.
final labelsManagerViewModelProvider = Provider<LabelsManagerViewModel>((ref) {
  final locale = ref.watch(appLocaleProvider);
  final localizations = lookupAppLocalizations(locale);
  final board = ref.watch(
    taskNotifierProvider.select(
      (boardAsync) => boardAsync.asData?.value ?? TaskBoard.empty(),
    ),
  );
  final locationsById = <String, TdfLocation>{
    for (final location in board.locations) location.id: location,
  };
  final sortedLabels = TaskBoardEvaluator.sortLabelsAlphabetically(
    board.labels,
  );
  final sortedLocations = TaskBoardEvaluator.sortLocationsAlphabetically(
    board.locations,
  );

  final cards = <LabelCardViewModel>[
    for (final label in sortedLabels)
      _buildLabelCardViewModel(
        label: label,
        openCount: board.openTaskCountForLabel(label.id),
        locationsById: locationsById,
        localizations: localizations,
      ),
  ];

  final locationOptions = <LocationOptionViewModel>[
    for (final location in sortedLocations)
      LocationOptionViewModel(
        id: location.id,
        name: location.name,
        coordinatesSummary: _formatCoordinatesSummary(location),
      ),
  ];

  final nextPresetColorHex =
      canonicalLabelPresetHexColors[board.labels.length %
          canonicalLabelPresetHexColors.length];

  return LabelsManagerViewModel(
    labels: cards,
    allLocations: locationOptions,
    nextPresetColorHex: nextPresetColorHex,
  );
});

/// Provides the model-free Locations manager projection for `lib/ui_v2/`.
final locationsManagerViewModelProvider = Provider<LocationsManagerViewModel>((
  ref,
) {
  final locale = ref.watch(appLocaleProvider);
  final localizations = lookupAppLocalizations(locale);
  final board = ref.watch(
    taskNotifierProvider.select(
      (boardAsync) => boardAsync.asData?.value ?? TaskBoard.empty(),
    ),
  );
  final activeFix = ref.watch(
    locationStateProvider.select(
      (state) => state.status == LocationStatus.found ? state.fix : null,
    ),
  );
  final locationController = ref.watch(locationEditorControllerProvider);
  final sortedLocations = TaskBoardEvaluator.sortLocationsAlphabetically(
    board.locations,
  );

  final cards = <LocationCardViewModel>[
    for (final location in sortedLocations)
      _buildLocationCardViewModel(
        location: location,
        openCount: board.openTaskCountForLocation(location.id),
        locationController: locationController,
        localizations: localizations,
      ),
  ];

  final activeLat = activeFix?.latitude;
  final activeLon = activeFix?.longitude;
  return LocationsManagerViewModel(
    locations: cards,
    hasActiveGpsFix: activeLat != null && activeLon != null,
    activeGpsLatitudeText: activeLat != null
        ? locationController.formatGpsCoordinate(activeLat)
        : null,
    activeGpsLongitudeText: activeLon != null
        ? locationController.formatGpsCoordinate(activeLon)
        : null,
  );
});

/// Provides the model-free Raw `TDF 0.8.0` preview projection for `lib/ui_v2/`.
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

/// Provides the model-free theme preset, brightness mode, and locale snapshot for `lib/main.dart` and `lib/ui_v2/`.
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

/// Provides the model-free sidebar/drawer projection for `lib/ui_v2/`.
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
        label: _tierName(tier, localizations),
        count: board.tasksForTier(_toTaskTier(tier)).length,
        wipLimit: _tierWipLimit(tier),
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
    final colorValue = _parseLabelColorValue(label.color);
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

/// Provides the model-free Tasks and Global Search projection for `lib/ui_v2/`.
final tasksViewModelProvider = Provider<TasksViewModel>((ref) {
  final locale = ref.watch(appLocaleProvider);
  final localizations = lookupAppLocalizations(locale);
  final activeTier = ref.watch(
    appShellControllerProvider.select((shell) => shell.activeTier),
  );
  final activeLabelId = ref.watch(
    appShellControllerProvider.select((shell) => shell.activeLabelId),
  );
  final searchOpen = ref.watch(
    appShellControllerProvider.select((shell) => shell.searchOpen),
  );
  final searchQuery = ref.watch(
    appShellControllerProvider.select((shell) => shell.searchQuery),
  );
  final syncErrorDismissed = ref.watch(
    appShellControllerProvider.select(
      (shell) => shell.syncErrorBannerDismissed,
    ),
  );
  final fileReadDismissed = ref.watch(
    appShellControllerProvider.select((shell) => shell.fileReadBannerDismissed),
  );
  final activeView = ref.watch(
    appShellControllerProvider.select((shell) => shell.view),
  );

  final evaluatedAsync = ref.watch(evaluatedBoardProvider(activeLabelId));
  final syncState = ref.watch(syncStateProvider);
  final config = ref.watch(
    webDavConfigProvider.select(
      (asyncConfig) => asyncConfig.asData?.value ?? const WebDavConfig(),
    ),
  );
  final activeFix = ref.watch(
    locationStateProvider.select(
      (state) => state.status == LocationStatus.found ? state.fix : null,
    ),
  );
  final nowUtc = ref.watch(clockProvider)().toUtc();
  final localNow = config.toLocalWallClock(nowUtc);

  final isInitialLoading = evaluatedAsync.isLoading && !evaluatedAsync.hasValue;
  final fullScreenError = _resolveFullScreenFileReadError(
    evaluatedAsync: evaluatedAsync,
    localizations: localizations,
  );
  final board = evaluatedAsync.asData?.value ?? TaskBoard.empty();
  final labelsById = <String, TdfLabel>{
    for (final label in board.labels) label.id: label,
  };
  final locationsById = <String, TdfLocation>{
    for (final location in board.locations) location.id: location,
  };
  final tasksById = <String, TaskItem>{
    for (final task in board.allTasks) task.id: task,
  };

  final banners = _buildStatusBanners(
    config: config,
    syncState: syncState,
    activeView: activeView,
    syncErrorDismissed: syncErrorDismissed,
    fileReadDismissed: fileReadDismissed,
    fullScreenError: fullScreenError != null,
    localizations: localizations,
  );

  final taskPairs = _collectVisibleTasks(
    board: board,
    activeTier: activeTier,
    searchOpen: searchOpen,
    searchQuery: searchQuery,
  );
  final taskCards = <TaskCardViewModel>[
    for (final entry in taskPairs)
      _buildTaskCardViewModel(
        board: board,
        task: entry.task,
        tier: entry.tier,
        isSearchMode: searchOpen,
        labelsById: labelsById,
        locationsById: locationsById,
        tasksById: tasksById,
        config: config,
        nowUtc: nowUtc,
        localNow: localNow,
        activeFix: activeFix,
        localizations: localizations,
      ),
  ];

  final activeFilterLabel = activeLabelId != null
      ? labelsById[activeLabelId]
      : null;
  final wipLimit = searchOpen ? null : _tierWipLimit(activeTier);
  final countLabel = wipLimit != null
      ? '${taskCards.length} / $wipLimit'
      : '${taskCards.length}';

  final sortedLabels = TaskBoardEvaluator.sortLabelsAlphabetically(
    board.labels,
  );
  final hasScoped = sortedLabels.any((label) => label.isScoped);
  final hasGlobal = sortedLabels.any((label) => !label.isScoped);
  final allLabelOptions = <LabelPickerOptionViewModel>[
    for (final label in sortedLabels)
      LabelPickerOptionViewModel(
        id: label.id,
        name: label.name,
        colorValue: _parseLabelColorValue(label.color),
        isScoped: label.isScoped,
        openCount: board.openTaskCountForLabel(label.id),
      ),
  ];
  final allLocationOptions = <LocationOptionViewModel>[
    for (final location in TaskBoardEvaluator.sortLocationsAlphabetically(
      board.locations,
    ))
      LocationOptionViewModel(
        id: location.id,
        name: location.name,
        coordinatesSummary: _formatCoordinatesSummary(location),
      ),
  ];

  return TasksViewModel(
    isLoading: isInitialLoading,
    fullScreenFileReadError: fullScreenError,
    banners: banners,
    headerTitle: searchOpen
        ? localizations.searchViewTitle
        : _tierName(activeTier, localizations),
    headerSubtitle: searchOpen
        ? localizations.searchViewSubtitle
        : _tierSubtitle(activeTier, localizations),
    headerCountLabel: countLabel,
    activeFilterLabelId: activeFilterLabel?.id,
    activeFilterLabelName: activeFilterLabel?.name,
    activeFilterLabelColorValue: _parseLabelColorValue(
      activeFilterLabel?.color,
    ),
    tierOptions: <CompactTierOptionViewModel>[
      for (final tier in ShellTier.values)
        CompactTierOptionViewModel(
          tier: tier,
          label: _tierName(tier, localizations),
          count: board.tasksForTier(_toTaskTier(tier)).length,
        ),
    ],
    emptyHint: searchOpen
        ? localizations.searchEmptyHint
        : _tierEmptyHint(activeTier, localizations),
    tasks: taskCards,
    allLabels: allLabelOptions,
    allLocations: allLocationOptions,
    hasBothScopedAndGlobalLabels: hasScoped && hasGlobal,
    currentLocalDateTimeHint: TaskEditorController.formatLocalTimestamp(
      nowUtc,
      config,
    ),
  );
});

/// Semantic icon key for collapsed entity card badges mapped inside `lib/ui_v2/`.
enum CardBadgeIconKey {
  /// Tier indicator icon (Search view).
  tierFocus,

  /// Tier indicator icon (Ready).
  tierReady,

  /// Tier indicator icon (Planned).
  tierPlanned,

  /// Tier indicator icon (Blocked).
  tierBlocked,

  /// Tier indicator icon (Someday).
  tierSomeday,

  /// Tier indicator icon (Completed).
  tierCompleted,

  /// Due or overdue deadline indicator.
  due,

  /// Manual or automatic deadline priority indicator.
  priority,

  /// Suspended indicator.
  suspended,

  /// Prerequisite blocker indicator.
  blockedBy,

  /// Activation conditions indicator.
  conditions,

  /// Standard subtasks progress indicator.
  subtasks,

  /// Auto-finish subtasks progress indicator.
  subtasksAutoFinish,

  /// Recurrence interval indicator.
  repeat,

  /// Note indicator.
  note,

  /// Reference links indicator.
  links,

  /// History journal indicator.
  history,
}

/// Top-level banner category distinguishing interactive actions.
enum ShellBannerKind {
  /// WebDAV enabled but unconfigured (`Configure`).
  unconfiguredWebDav,

  /// General sync error or generation rollback (`Retry` + `Settings`).
  syncError,

  /// Partial file-read failure where one storage target remained readable.
  partialFileRead,

  /// Unresolved `TDF-DEL-003` deletion conflict (`Resolve conflict`).
  deletionConflict,

  /// Unresolved `TDF-REC-002` generation recovery (`Open recovery`).
  recoveryRequired,
}

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
    syncStatusKind,
    syncStatusLabel,
    hasWebDav,
    canUndo,
    undoStackDepth,
    activeFilterLabelName,
  );
}

/// Immutable pill badge rendered in a collapsed entity metadata strip.
@immutable
class CardBadgeViewModel {
  /// Creates a [CardBadgeViewModel].
  const CardBadgeViewModel({
    required this.label,
    required this.tone,
    required this.iconKey,
  });

  /// Semantic icon identifier resolved by `lib/ui_v2/ui_v2_icon_mapper.dart`.
  final CardBadgeIconKey iconKey;

  /// Localized badge text.
  final String label;

  /// Visual severity tone.
  final BadgeTone tone;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CardBadgeViewModel &&
        other.label == label &&
        other.tone == tone &&
        other.iconKey == iconKey;
  }

  @override
  int get hashCode => Object.hash(label, tone, iconKey);
}

/// Immutable tier choice for the compact mobile dropdown (`U-UX-003`).
@immutable
class CompactTierOptionViewModel {
  /// Creates a [CompactTierOptionViewModel].
  const CompactTierOptionViewModel({
    required this.tier,
    required this.label,
    required this.count,
  });

  /// Number of tasks in [tier].
  final int count;

  /// Localized tier display name.
  final String label;

  /// Target tier enum.
  final ShellTier tier;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CompactTierOptionViewModel &&
        other.tier == tier &&
        other.label == label &&
        other.count == count;
  }

  @override
  int get hashCode => Object.hash(tier, label, count);
}

/// Immutable model-free representation of activation condition editor state.
@immutable
class ConditionDraftViewModel {
  /// Creates a [ConditionDraftViewModel].
  ConditionDraftViewModel({
    this.ignoreAllLabelConditions = false,
    this.daysMode = ConditionDimensionMode.inherit,
    Iterable<int> selectedWeekdays = const <int>[],
    this.timesMode = ConditionDimensionMode.inherit,
    Iterable<TimeWindowDraftViewModel> timeWindows =
        const <TimeWindowDraftViewModel>[],
    this.locationsMode = ConditionDimensionMode.inherit,
    Iterable<String> selectedLocationIds = const <String>[],
  }) : selectedWeekdays = List<int>.unmodifiable(selectedWeekdays),
       timeWindows = List<TimeWindowDraftViewModel>.unmodifiable(timeWindows),
       selectedLocationIds = List<String>.unmodifiable(selectedLocationIds);

  /// Day dimension mode (`inherit`, `any`, or `custom`).
  final ConditionDimensionMode daysMode;

  /// Whether `condition any` ignores all inherited label conditions.
  final bool ignoreAllLabelConditions;

  /// Location dimension mode (`inherit`, `any`, or `custom`).
  final ConditionDimensionMode locationsMode;

  /// Selected referenced location identifiers.
  final List<String> selectedLocationIds;

  /// Selected ISO weekdays (`1..7`, Monday to Sunday).
  final List<int> selectedWeekdays;

  /// Time dimension mode (`inherit`, `any`, or `custom`).
  final ConditionDimensionMode timesMode;

  /// Configured `HH:MM`..`HH:MM` daily time windows.
  final List<TimeWindowDraftViewModel> timeWindows;

  /// Returns a copy of this [ConditionDraftViewModel] with updated fields.
  ConditionDraftViewModel copyWith({
    bool? ignoreAllLabelConditions,
    ConditionDimensionMode? daysMode,
    Iterable<int>? selectedWeekdays,
    ConditionDimensionMode? timesMode,
    Iterable<TimeWindowDraftViewModel>? timeWindows,
    ConditionDimensionMode? locationsMode,
    Iterable<String>? selectedLocationIds,
  }) {
    return ConditionDraftViewModel(
      ignoreAllLabelConditions:
          ignoreAllLabelConditions ?? this.ignoreAllLabelConditions,
      daysMode: daysMode ?? this.daysMode,
      selectedWeekdays: selectedWeekdays ?? this.selectedWeekdays,
      timesMode: timesMode ?? this.timesMode,
      timeWindows: timeWindows ?? this.timeWindows,
      locationsMode: locationsMode ?? this.locationsMode,
      selectedLocationIds: selectedLocationIds ?? this.selectedLocationIds,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConditionDraftViewModel &&
        other.ignoreAllLabelConditions == ignoreAllLabelConditions &&
        other.daysMode == daysMode &&
        listEquals(other.selectedWeekdays, selectedWeekdays) &&
        other.timesMode == timesMode &&
        listEquals(other.timeWindows, timeWindows) &&
        other.locationsMode == locationsMode &&
        listEquals(other.selectedLocationIds, selectedLocationIds);
  }

  @override
  int get hashCode => Object.hash(
    ignoreAllLabelConditions,
    daysMode,
    Object.hashAll(selectedWeekdays),
    timesMode,
    Object.hashAll(timeWindows),
    locationsMode,
    Object.hashAll(selectedLocationIds),
  );
}

/// Immutable read-only condition summary token with optional clickable location navigation target.
@immutable
class ConditionSummaryChipViewModel {
  /// Creates a [ConditionSummaryChipViewModel].
  const ConditionSummaryChipViewModel({
    required this.label,
    this.locationId,
    this.isInherited = false,
  });

  /// Whether this rule is inherited from an assigned label.
  final bool isInherited;

  /// Localized human-readable condition summary.
  final String label;

  /// Optional location identifier when tapping navigates to the Locations manager.
  final String? locationId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConditionSummaryChipViewModel &&
        other.label == label &&
        other.locationId == locationId &&
        other.isInherited == isInherited;
  }

  @override
  int get hashCode => Object.hash(label, locationId, isInherited);
}

/// Immutable assigned label chip displayed on collapsed or expanded task cards.
@immutable
class EntityLabelChipViewModel {
  /// Creates an [EntityLabelChipViewModel].
  const EntityLabelChipViewModel({
    required this.id,
    required this.name,
    required this.isScoped,
    this.colorValue,
  });

  /// Optional ARGB color integer parsed from `#RRGGBB`.
  final int? colorValue;

  /// Canonical label identifier.
  final String id;

  /// Whether this label scopes its tasks into a dedicated queue.
  final bool isScoped;

  /// Label display name.
  final String name;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EntityLabelChipViewModel &&
        other.id == id &&
        other.name == name &&
        other.colorValue == colorValue &&
        other.isScoped == isScoped;
  }

  @override
  int get hashCode => Object.hash(id, name, colorValue, isScoped);
}

/// Immutable reference link item displayed inside Task and Label cards.
@immutable
class EntityLinkViewModel {
  /// Creates an [EntityLinkViewModel].
  const EntityLinkViewModel({required this.title, required this.uri});

  /// Display title of the reference link.
  final String title;

  /// Validated URI launched through `LinkActionController`.
  final String uri;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EntityLinkViewModel &&
        other.title == title &&
        other.uri == uri;
  }

  @override
  int get hashCode => Object.hash(title, uri);
}

/// Immutable per-target file readability diagnostic line.
@immutable
class FileReadDiagnosticLineViewModel {
  /// Creates a [FileReadDiagnosticLineViewModel].
  const FileReadDiagnosticLineViewModel({
    required this.targetLabel,
    required this.statusText,
    required this.isReadable,
  });

  /// Whether this target was read cleanly.
  final bool isReadable;

  /// Localized readability status or detailed format error text.
  final String statusText;

  /// Localized target label (`Local file` or `Remote file`).
  final String targetLabel;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileReadDiagnosticLineViewModel &&
        other.targetLabel == targetLabel &&
        other.statusText == statusText &&
        other.isReadable == isReadable;
  }

  @override
  int get hashCode => Object.hash(targetLabel, statusText, isReadable);
}

/// Immutable full-screen or banner file-read diagnostic report.
@immutable
class FileReadReportViewModel {
  /// Creates a [FileReadReportViewModel].
  FileReadReportViewModel({
    required this.title,
    required this.summary,
    required Iterable<FileReadDiagnosticLineViewModel> lines,
  }) : lines = List<FileReadDiagnosticLineViewModel>.unmodifiable(lines);

  /// Per-target diagnostic rows.
  final List<FileReadDiagnosticLineViewModel> lines;

  /// Localized summary explaining which target(s) failed.
  final String summary;

  /// Localized heading (`File Read Error`).
  final String title;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileReadReportViewModel &&
        other.title == title &&
        other.summary == summary &&
        listEquals(other.lines, lines);
  }

  @override
  int get hashCode => Object.hash(title, summary, Object.hashAll(lines));
}

/// Immutable Task History Journal row projection.
@immutable
class HistoryEntryViewModel {
  /// Creates a [HistoryEntryViewModel].
  const HistoryEntryViewModel({
    required this.index,
    required this.timestampUtcIso,
    required this.formattedLocalTimestamp,
    required this.text,
  });

  /// Local timestamp formatted in workspace time zone (`YYYY-MM-DD HH:MM`).
  final String formattedLocalTimestamp;

  /// Position in the canonical sorted history list.
  final int index;

  /// Single-line history entry text.
  final String text;

  /// Canonical UTC ISO-8601 timestamp identifying this entry during edits and deletions.
  final String timestampUtcIso;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HistoryEntryViewModel &&
        other.index == index &&
        other.timestampUtcIso == timestampUtcIso &&
        other.formattedLocalTimestamp == formattedLocalTimestamp &&
        other.text == text;
  }

  @override
  int get hashCode =>
      Object.hash(index, timestampUtcIso, formattedLocalTimestamp, text);
}

/// Immutable expandable Label card projection for `LabelsView`.
@immutable
class LabelCardViewModel {
  /// Creates a [LabelCardViewModel].
  LabelCardViewModel({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.colorValue,
    required this.isScoped,
    required this.openCount,
    required this.note,
    required Iterable<EntityLinkViewModel> links,
    required this.hasConditions,
    required Iterable<ConditionSummaryChipViewModel> conditionsSummary,
    required this.conditionDraft,
    required Iterable<LabelSectionKind> unsetSections,
  }) : links = List<EntityLinkViewModel>.unmodifiable(links),
       conditionsSummary = List<ConditionSummaryChipViewModel>.unmodifiable(
         conditionsSummary,
       ),
       unsetSections = List<LabelSectionKind>.unmodifiable(unsetSections);

  /// Normalized `#RRGGBB` hex string, or empty string when unset.
  final String colorHex;

  /// Parsed ARGB integer color, or `null` when unset.
  final int? colorValue;

  /// Editable activation conditions draft state.
  final ConditionDraftViewModel conditionDraft;

  /// Human-readable condition summary chips.
  final List<ConditionSummaryChipViewModel> conditionsSummary;

  /// Whether this label declares inherited activation conditions.
  final bool hasConditions;

  /// Canonical label identifier.
  final String id;

  /// Whether this label acts as a Scoped Queue.
  final bool isScoped;

  /// Reference links attached to this label.
  final List<EntityLinkViewModel> links;

  /// Label display name.
  final String name;

  /// Optional multi-line note.
  final String? note;

  /// Count of open tasks referencing this label.
  final int openCount;

  /// Unset editable sections rendered in the bottom `+ Add` chips bar.
  final List<LabelSectionKind> unsetSections;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LabelCardViewModel &&
        other.id == id &&
        other.name == name &&
        other.colorHex == colorHex &&
        other.colorValue == colorValue &&
        other.isScoped == isScoped &&
        other.openCount == openCount &&
        other.note == note &&
        listEquals(other.links, links) &&
        other.hasConditions == hasConditions &&
        listEquals(other.conditionsSummary, conditionsSummary) &&
        other.conditionDraft == conditionDraft &&
        listEquals(other.unsetSections, unsetSections);
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    colorHex,
    colorValue,
    isScoped,
    openCount,
    note,
    Object.hashAll(links),
    hasConditions,
    Object.hashAll(conditionsSummary),
    conditionDraft,
    Object.hashAll(unsetSections),
  );
}

/// Immutable option row supplied to the Searchable Label Picker (`U-COMP-005`).
@immutable
class LabelPickerOptionViewModel {
  /// Creates a [LabelPickerOptionViewModel].
  const LabelPickerOptionViewModel({
    required this.id,
    required this.name,
    required this.isScoped,
    required this.openCount,
    this.colorValue,
  });

  /// Optional parsed ARGB color integer.
  final int? colorValue;

  /// Canonical label identifier.
  final String id;

  /// Whether this label is a Scoped Queue.
  final bool isScoped;

  /// Label display name.
  final String name;

  /// Open task count referencing this label.
  final int openCount;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LabelPickerOptionViewModel &&
        other.id == id &&
        other.name == name &&
        other.colorValue == colorValue &&
        other.isScoped == isScoped &&
        other.openCount == openCount;
  }

  @override
  int get hashCode => Object.hash(id, name, colorValue, isScoped, openCount);
}

/// Immutable view model for the Labels manager view.
@immutable
class LabelsManagerViewModel {
  /// Creates a [LabelsManagerViewModel].
  LabelsManagerViewModel({
    required Iterable<LabelCardViewModel> labels,
    required Iterable<LocationOptionViewModel> allLocations,
    required this.nextPresetColorHex,
  }) : labels = List<LabelCardViewModel>.unmodifiable(labels),
       allLocations = List<LocationOptionViewModel>.unmodifiable(allLocations);

  /// Available saved locations for inherited GPS conditions.
  final List<LocationOptionViewModel> allLocations;

  /// Alphabetically sorted label cards.
  final List<LabelCardViewModel> labels;

  /// Next rotating preset `#RRGGBB` color assigned on Quick-Create.
  final String nextPresetColorHex;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LabelsManagerViewModel &&
        listEquals(other.labels, labels) &&
        listEquals(other.allLocations, allLocations) &&
        other.nextPresetColorHex == nextPresetColorHex;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(labels),
    Object.hashAll(allLocations),
    nextPresetColorHex,
  );
}

/// Immutable expandable Location card projection for `LocationsView`.
@immutable
class LocationCardViewModel {
  /// Creates a [LocationCardViewModel].
  LocationCardViewModel({
    required this.id,
    required this.name,
    required this.sourceType,
    required this.sourceValue,
    required this.sourceTypeLabel,
    required this.latitudeText,
    required this.longitudeText,
    required this.radiusText,
    required this.coordinatesSummary,
    required this.radiusSummary,
    required this.openCount,
    required this.note,
    required Iterable<LocationSectionKind> unsetSections,
  }) : unsetSections = List<LocationSectionKind>.unmodifiable(unsetSections);

  /// Compact 4dp coordinate + radius summary for collapsed strip.
  final String coordinatesSummary;

  /// Canonical location identifier.
  final String id;

  /// Normalized decimal latitude text for inline editing.
  final String latitudeText;

  /// Normalized decimal longitude text for inline editing.
  final String longitudeText;

  /// Location display name.
  final String name;

  /// Optional multi-line note.
  final String? note;

  /// Count of open tasks referencing this location directly or via labels.
  final int openCount;

  /// Formatted radius display label (e.g. `250m` or `1.5km`).
  final String radiusSummary;

  /// Editable radius text (e.g. `250m`).
  final String radiusText;

  /// Classified coordinate source type.
  final ShellLocationSourceType sourceType;

  /// Localized source type badge label.
  final String sourceTypeLabel;

  /// Raw address or Plus Code string, or empty for direct GPS.
  final String sourceValue;

  /// Unset editable sections rendered in the bottom `+ Add` chips bar.
  final List<LocationSectionKind> unsetSections;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationCardViewModel &&
        other.id == id &&
        other.name == name &&
        other.sourceType == sourceType &&
        other.sourceValue == sourceValue &&
        other.sourceTypeLabel == sourceTypeLabel &&
        other.latitudeText == latitudeText &&
        other.longitudeText == longitudeText &&
        other.radiusText == radiusText &&
        other.coordinatesSummary == coordinatesSummary &&
        other.radiusSummary == radiusSummary &&
        other.openCount == openCount &&
        other.note == note &&
        listEquals(other.unsetSections, unsetSections);
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    sourceType,
    sourceValue,
    sourceTypeLabel,
    latitudeText,
    longitudeText,
    radiusText,
    coordinatesSummary,
    radiusSummary,
    openCount,
    note,
    Object.hashAll(unsetSections),
  );
}

/// Immutable lightweight location reference option for condition pickers.
@immutable
class LocationOptionViewModel {
  /// Creates a [LocationOptionViewModel].
  const LocationOptionViewModel({
    required this.id,
    required this.name,
    required this.coordinatesSummary,
  });

  /// Formatted coordinate and radius preview string.
  final String coordinatesSummary;

  /// Canonical location identifier.
  final String id;

  /// Location display name.
  final String name;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationOptionViewModel &&
        other.id == id &&
        other.name == name &&
        other.coordinatesSummary == coordinatesSummary;
  }

  @override
  int get hashCode => Object.hash(id, name, coordinatesSummary);
}

/// Immutable view model for the Locations manager view.
@immutable
class LocationsManagerViewModel {
  /// Creates a [LocationsManagerViewModel].
  LocationsManagerViewModel({
    required Iterable<LocationCardViewModel> locations,
    required this.hasActiveGpsFix,
    this.activeGpsLatitudeText,
    this.activeGpsLongitudeText,
  }) : locations = List<LocationCardViewModel>.unmodifiable(locations);

  /// Active foreground GPS latitude formatted to 6dp, if available.
  final String? activeGpsLatitudeText;

  /// Active foreground GPS longitude formatted to 6dp, if available.
  final String? activeGpsLongitudeText;

  /// Whether a live foreground GPS fix is currently available.
  final bool hasActiveGpsFix;

  /// Alphabetically sorted location cards.
  final List<LocationCardViewModel> locations;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationsManagerViewModel &&
        listEquals(other.locations, locations) &&
        other.hasActiveGpsFix == hasActiveGpsFix &&
        other.activeGpsLatitudeText == activeGpsLatitudeText &&
        other.activeGpsLongitudeText == activeGpsLongitudeText;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(locations),
    hasActiveGpsFix,
    activeGpsLatitudeText,
    activeGpsLongitudeText,
  );
}

/// Immutable selectable candidate row inside the Prerequisite picker (`U-COMP-005`).
@immutable
class PrerequisiteCandidateViewModel {
  /// Creates a [PrerequisiteCandidateViewModel].
  const PrerequisiteCandidateViewModel({
    required this.id,
    required this.title,
    required this.wouldCreateCycle,
    required this.isSelected,
  });

  /// Candidate task identifier.
  final String id;

  /// Whether this candidate is currently assigned as a prerequisite.
  final bool isSelected;

  /// Candidate task title.
  final String title;

  /// Whether adding this candidate would create a dependency cycle (`Cycle prevented`).
  final bool wouldCreateCycle;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PrerequisiteCandidateViewModel &&
        other.id == id &&
        other.title == title &&
        other.wouldCreateCycle == wouldCreateCycle &&
        other.isSelected == isSelected;
  }

  @override
  int get hashCode => Object.hash(id, title, wouldCreateCycle, isSelected);
}

/// Immutable prerequisite dependency item displayed in an expanded Task card.
@immutable
class PrerequisiteItemViewModel {
  /// Creates a [PrerequisiteItemViewModel].
  const PrerequisiteItemViewModel({
    required this.id,
    required this.title,
    required this.isSatisfied,
    required this.requiredCompletion,
  });

  /// Referenced prerequisite task identifier.
  final String id;

  /// Whether the prerequisite currently meets its completion requirement.
  final bool isSatisfied;

  /// Required completion counter threshold (`>= 1`).
  final int requiredCompletion;

  /// Resolved task title or fallback task ID.
  final String title;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PrerequisiteItemViewModel &&
        other.id == id &&
        other.title == title &&
        other.isSatisfied == isSatisfied &&
        other.requiredCompletion == requiredCompletion;
  }

  @override
  int get hashCode => Object.hash(id, title, isSatisfied, requiredCompletion);
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

/// Immutable operational status banner displayed at the top of Tasks view (`U-UX-007`).
@immutable
class ShellBannerViewModel {
  /// Creates a [ShellBannerViewModel].
  ShellBannerViewModel({
    required this.kind,
    required this.tone,
    required this.message,
    required this.dismissible,
    this.primaryActionLabel,
    this.secondaryActionLabel,
    Iterable<FileReadDiagnosticLineViewModel> diagnosticLines =
        const <FileReadDiagnosticLineViewModel>[],
  }) : diagnosticLines = List<FileReadDiagnosticLineViewModel>.unmodifiable(
         diagnosticLines,
       );

  /// Optional structured per-target diagnostic lines for partial file-read errors.
  final List<FileReadDiagnosticLineViewModel> diagnosticLines;

  /// Whether the user may dismiss this banner.
  final bool dismissible;

  /// Operational banner category.
  final ShellBannerKind kind;

  /// Localized banner body text.
  final String message;

  /// Optional primary banner button label.
  final String? primaryActionLabel;

  /// Optional secondary banner button label.
  final String? secondaryActionLabel;

  /// Visual severity tone.
  final BannerTone tone;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ShellBannerViewModel &&
        other.kind == kind &&
        other.tone == tone &&
        other.message == message &&
        other.dismissible == dismissible &&
        other.primaryActionLabel == primaryActionLabel &&
        other.secondaryActionLabel == secondaryActionLabel &&
        listEquals(other.diagnosticLines, diagnosticLines);
  }

  @override
  int get hashCode => Object.hash(
    kind,
    tone,
    message,
    dismissible,
    primaryActionLabel,
    secondaryActionLabel,
    Object.hashAll(diagnosticLines),
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

/// Immutable subtask row model rendered inside expanded Task cards.
@immutable
class SubtaskViewModel {
  /// Creates a [SubtaskViewModel].
  const SubtaskViewModel({
    required this.index,
    required this.title,
    required this.isCompleted,
  });

  /// Zero-based position in the subtask list.
  final int index;

  /// Whether this subtask step is completed.
  final bool isCompleted;

  /// Step text.
  final String title;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SubtaskViewModel &&
        other.index == index &&
        other.title == title &&
        other.isCompleted == isCompleted;
  }

  @override
  int get hashCode => Object.hash(index, title, isCompleted);
}

/// Immutable expandable Task card projection (`U-CARD-001`..`005`).
@immutable
class TaskCardViewModel {
  /// Creates a [TaskCardViewModel].
  TaskCardViewModel({
    required this.id,
    required this.title,
    required this.tier,
    required this.isCompleted,
    required this.canDowngrade,
    required this.isPriority,
    required this.isAutoPrioritized,
    required this.isSomeday,
    required this.isSuspended,
    required this.isSuspendedIndefinitely,
    required this.placement,
    required Iterable<EntityLabelChipViewModel> assignedLabels,
    required Iterable<CardBadgeViewModel> primaryBadges,
    required Iterable<CardBadgeViewModel> visibleSecondaryBadges,
    required this.overflowSecondaryCount,
    required this.note,
    required Iterable<EntityLinkViewModel> links,
    required Iterable<SubtaskViewModel> subtasks,
    required this.subtasksAutoFinish,
    required this.subtasksCompletedCount,
    required this.subtasksProgressLabel,
    required Iterable<HistoryEntryViewModel> history,
    required this.dueFormatted,
    required this.dueInputInitial,
    required this.dueNote,
    required this.dueAnchorFormatted,
    required this.dueAutoPriorityLabel,
    required this.isDuePassive,
    required this.isOverdue,
    required this.isWithinDueLeadWindow,
    required this.repeatSummary,
    required this.repeatCount,
    required this.repeatUnit,
    required this.repeatLeadDays,
    required this.repeatCompletionsLabel,
    required this.repeatLeadLabel,
    required this.suspendedSummary,
    required this.suspendedInputInitial,
    required this.suspendedNote,
    required Iterable<PrerequisiteItemViewModel> prerequisites,
    required this.prerequisitesProgressLabel,
    required Iterable<PrerequisiteCandidateViewModel> prerequisiteCandidates,
    required this.hasConditions,
    required this.conditionsSatisfied,
    required this.conditionsStatusLabel,
    required Iterable<ConditionSummaryChipViewModel> conditionsSummary,
    required this.conditionDraft,
    required Iterable<TaskSectionKind> unsetSections,
  }) : assignedLabels = List<EntityLabelChipViewModel>.unmodifiable(
         assignedLabels,
       ),
       primaryBadges = List<CardBadgeViewModel>.unmodifiable(primaryBadges),
       visibleSecondaryBadges = List<CardBadgeViewModel>.unmodifiable(
         visibleSecondaryBadges,
       ),
       links = List<EntityLinkViewModel>.unmodifiable(links),
       subtasks = List<SubtaskViewModel>.unmodifiable(subtasks),
       history = List<HistoryEntryViewModel>.unmodifiable(history),
       prerequisites = List<PrerequisiteItemViewModel>.unmodifiable(
         prerequisites,
       ),
       prerequisiteCandidates =
           List<PrerequisiteCandidateViewModel>.unmodifiable(
             prerequisiteCandidates,
           ),
       conditionsSummary = List<ConditionSummaryChipViewModel>.unmodifiable(
         conditionsSummary,
       ),
       unsetSections = List<TaskSectionKind>.unmodifiable(unsetSections);

  /// Assigned label chips (exempt from secondary badge overflow cap).
  final List<EntityLabelChipViewModel> assignedLabels;

  /// Whether the Downgrade chevron action is visible (active tasks in Tiers `0..2`).
  final bool canDowngrade;

  /// Editable activation condition draft state.
  final ConditionDraftViewModel conditionDraft;

  /// Whether effective activation conditions are currently satisfied.
  final bool conditionsSatisfied;

  /// Localized active/unmet condition status line.
  final String conditionsStatusLabel;

  /// Read-only condition summary chips.
  final List<ConditionSummaryChipViewModel> conditionsSummary;

  /// Optional formatted local schedule anchor label.
  final String? dueAnchorFormatted;

  /// Optional auto-priority status line for Due section.
  final String? dueAutoPriorityLabel;

  /// Optional formatted Due timestamp + remaining/overdue readout.
  final String? dueFormatted;

  /// Editable `YYYY-MM-DD HH:MM` Due input seed in workspace time zone.
  final String dueInputInitial;

  /// Optional deadline note text.
  final String? dueNote;

  /// Whether this task has explicit or inherited activation conditions.
  final bool hasConditions;

  /// Chronologically sorted History Journal entries.
  final List<HistoryEntryViewModel> history;

  /// Canonical task identifier.
  final String id;

  /// Whether deadline lead-window auto-priority is currently active.
  final bool isAutoPrioritized;

  /// Whether the task resides in Tier 6 (`Completed`, read-only except Restore/Delete/History).
  final bool isCompleted;

  /// Whether the due deadline is informational (`passive`, auto-priority off).
  final bool isDuePassive;

  /// Whether the active task's due deadline has passed.
  final bool isOverdue;

  /// Whether manual priority is set on the task.
  final bool isPriority;

  /// Whether the task is parked in Someday.
  final bool isSomeday;

  /// Whether the task is currently suspended (indefinitely or until a future timestamp).
  final bool isSuspended;

  /// Whether suspension has no end timestamp.
  final bool isSuspendedIndefinitely;

  /// Whether the active task's due deadline is inside the configured lead window.
  final bool isWithinDueLeadWindow;

  /// Attached reference links.
  final List<EntityLinkViewModel> links;

  /// Optional multi-line task note.
  final String? note;

  /// Count of hidden secondary badges beyond the `3`-pill cap (`0` when `<= 3`).
  final int overflowSecondaryCount;

  /// Current placement mode (`queue`, `priority`, or `someday`).
  final TaskPlacementOption placement;

  /// Candidate tasks available in the inline Prerequisite picker.
  final List<PrerequisiteCandidateViewModel> prerequisiteCandidates;

  /// Assigned prerequisite dependencies.
  final List<PrerequisiteItemViewModel> prerequisites;

  /// Formatted prerequisite satisfaction summary.
  final String? prerequisitesProgressLabel;

  /// Primary badges exempt from secondary overflow (Search Tier badge, Due/Overdue badge).
  final List<CardBadgeViewModel> primaryBadges;

  /// Optional formatted cumulative completions label.
  final String? repeatCompletionsLabel;

  /// Recurrence count (`1..3650`), or `null` when not repeating.
  final int? repeatCount;

  /// Optional recurrence preparation lead days (`0..3650`).
  final int? repeatLeadDays;

  /// Optional localized preparation lead label.
  final String? repeatLeadLabel;

  /// Formatted recurrence interval phrase, or `null` when not repeating.
  final String? repeatSummary;

  /// Recurrence unit, or `null` when not repeating.
  final ShellRepeatUnit? repeatUnit;

  /// Ordered subtasks list.
  final List<SubtaskViewModel> subtasks;

  /// Whether completing the final subtask automatically completes the task.
  final bool subtasksAutoFinish;

  /// Count of checked subtasks.
  final int subtasksCompletedCount;

  /// Formatted subtask progress string (e.g. `1 of 2 completed`).
  final String? subtasksProgressLabel;

  /// Editable `YYYY-MM-DD HH:MM` suspension input seed in workspace time zone.
  final String suspendedInputInitial;

  /// Optional deferral note text.
  final String? suspendedNote;

  /// Formatted suspension summary string, or `null` when not suspended.
  final String? suspendedSummary;

  /// Evaluated task tier.
  final ShellTier tier;

  /// Task title.
  final String title;

  /// Unset editable sections rendered in the bottom `+ Add` chips bar (empty when completed).
  final List<TaskSectionKind> unsetSections;

  /// Up to `3` highest-priority secondary badges in strict `U-CARD-005` order.
  final List<CardBadgeViewModel> visibleSecondaryBadges;

  /// Canonical maximum allowed history entries per task (`maxTdfHistoryPerTask = 500`).
  int get maxHistoryCount => maxTdfHistoryPerTask;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskCardViewModel &&
        other.id == id &&
        other.title == title &&
        other.tier == tier &&
        other.isCompleted == isCompleted &&
        other.canDowngrade == canDowngrade &&
        other.isPriority == isPriority &&
        other.isAutoPrioritized == isAutoPrioritized &&
        other.isSomeday == isSomeday &&
        other.isSuspended == isSuspended &&
        other.isSuspendedIndefinitely == isSuspendedIndefinitely &&
        other.placement == placement &&
        listEquals(other.assignedLabels, assignedLabels) &&
        listEquals(other.primaryBadges, primaryBadges) &&
        listEquals(other.visibleSecondaryBadges, visibleSecondaryBadges) &&
        other.overflowSecondaryCount == overflowSecondaryCount &&
        other.note == note &&
        listEquals(other.links, links) &&
        listEquals(other.subtasks, subtasks) &&
        other.subtasksAutoFinish == subtasksAutoFinish &&
        other.subtasksCompletedCount == subtasksCompletedCount &&
        other.subtasksProgressLabel == subtasksProgressLabel &&
        listEquals(other.history, history) &&
        other.dueFormatted == dueFormatted &&
        other.dueInputInitial == dueInputInitial &&
        other.dueNote == dueNote &&
        other.dueAnchorFormatted == dueAnchorFormatted &&
        other.dueAutoPriorityLabel == dueAutoPriorityLabel &&
        other.isDuePassive == isDuePassive &&
        other.isOverdue == isOverdue &&
        other.isWithinDueLeadWindow == isWithinDueLeadWindow &&
        other.repeatSummary == repeatSummary &&
        other.repeatCount == repeatCount &&
        other.repeatUnit == repeatUnit &&
        other.repeatLeadDays == repeatLeadDays &&
        other.repeatCompletionsLabel == repeatCompletionsLabel &&
        other.repeatLeadLabel == repeatLeadLabel &&
        other.suspendedSummary == suspendedSummary &&
        other.suspendedInputInitial == suspendedInputInitial &&
        other.suspendedNote == suspendedNote &&
        listEquals(other.prerequisites, prerequisites) &&
        other.prerequisitesProgressLabel == prerequisitesProgressLabel &&
        listEquals(other.prerequisiteCandidates, prerequisiteCandidates) &&
        other.hasConditions == hasConditions &&
        other.conditionsSatisfied == conditionsSatisfied &&
        other.conditionsStatusLabel == conditionsStatusLabel &&
        listEquals(other.conditionsSummary, conditionsSummary) &&
        other.conditionDraft == conditionDraft &&
        listEquals(other.unsetSections, unsetSections);
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    id,
    title,
    tier,
    isCompleted,
    canDowngrade,
    isPriority,
    isAutoPrioritized,
    isSomeday,
    isSuspended,
    isSuspendedIndefinitely,
    placement,
    Object.hashAll(assignedLabels),
    Object.hashAll(primaryBadges),
    Object.hashAll(visibleSecondaryBadges),
    overflowSecondaryCount,
    note,
    Object.hashAll(links),
    Object.hashAll(subtasks),
    subtasksAutoFinish,
    subtasksCompletedCount,
    subtasksProgressLabel,
    Object.hashAll(history),
    dueFormatted,
    dueInputInitial,
    dueNote,
    dueAnchorFormatted,
    dueAutoPriorityLabel,
    isDuePassive,
    isOverdue,
    isWithinDueLeadWindow,
    repeatSummary,
    repeatCount,
    repeatUnit,
    repeatLeadDays,
    repeatCompletionsLabel,
    repeatLeadLabel,
    suspendedSummary,
    suspendedInputInitial,
    suspendedNote,
    Object.hashAll(prerequisites),
    prerequisitesProgressLabel,
    Object.hashAll(prerequisiteCandidates),
    hasConditions,
    conditionsSatisfied,
    conditionsStatusLabel,
    Object.hashAll(conditionsSummary),
    conditionDraft,
    Object.hashAll(unsetSections),
  ]);
}

/// Immutable projection for the primary Tasks and Global Search view.
@immutable
class TasksViewModel {
  /// Creates a [TasksViewModel].
  TasksViewModel({
    required this.isLoading,
    required this.fullScreenFileReadError,
    required Iterable<ShellBannerViewModel> banners,
    required this.headerTitle,
    required this.headerSubtitle,
    required this.headerCountLabel,
    required this.activeFilterLabelId,
    required this.activeFilterLabelName,
    required this.activeFilterLabelColorValue,
    required Iterable<CompactTierOptionViewModel> tierOptions,
    required this.emptyHint,
    required Iterable<TaskCardViewModel> tasks,
    required Iterable<LabelPickerOptionViewModel> allLabels,
    required Iterable<LocationOptionViewModel> allLocations,
    required this.hasBothScopedAndGlobalLabels,
    required this.currentLocalDateTimeHint,
  }) : banners = List<ShellBannerViewModel>.unmodifiable(banners),
       tierOptions = List<CompactTierOptionViewModel>.unmodifiable(tierOptions),
       tasks = List<TaskCardViewModel>.unmodifiable(tasks),
       allLabels = List<LabelPickerOptionViewModel>.unmodifiable(allLabels),
       allLocations = List<LocationOptionViewModel>.unmodifiable(allLocations);

  /// Color value of the active filter label, if any.
  final int? activeFilterLabelColorValue;

  /// Active label filter identifier, if any.
  final String? activeFilterLabelId;

  /// Active label filter display name, if any.
  final String? activeFilterLabelName;

  /// Workspace labels supplied to task and composer label pickers.
  final List<LabelPickerOptionViewModel> allLabels;

  /// Workspace locations supplied to task condition pickers.
  final List<LocationOptionViewModel> allLocations;

  /// Active top status banners ordered per `U-UX-007`.
  final List<ShellBannerViewModel> banners;

  /// Current local wall-clock timestamp (`YYYY-MM-DD HH:MM`) in workspace time zone.
  final String currentLocalDateTimeHint;

  /// Localized plain-text empty state message.
  final String emptyHint;

  /// Full-screen file-read error state replacing the Tasks view when all active targets failed.
  final FileReadReportViewModel? fullScreenFileReadError;

  /// Whether workspace contains both scoped and global labels (`U-COMP-005` conditional scope pills).
  final bool hasBothScopedAndGlobalLabels;

  /// Formatted tabular count pill (`N / 3`, `N / 5`, or `N`).
  final String headerCountLabel;

  /// Localized page subtitle.
  final String headerSubtitle;

  /// Localized page heading.
  final String headerTitle;

  /// Whether the initial workspace board load is still in progress.
  final bool isLoading;

  /// Projected task cards for the active tier or Global Search query.
  final List<TaskCardViewModel> tasks;

  /// Six tier dropdown options for compact mobile navigation (`U-UX-003`).
  final List<CompactTierOptionViewModel> tierOptions;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TasksViewModel &&
        other.isLoading == isLoading &&
        other.fullScreenFileReadError == fullScreenFileReadError &&
        listEquals(other.banners, banners) &&
        other.headerTitle == headerTitle &&
        other.headerSubtitle == headerSubtitle &&
        other.headerCountLabel == headerCountLabel &&
        other.activeFilterLabelId == activeFilterLabelId &&
        other.activeFilterLabelName == activeFilterLabelName &&
        other.activeFilterLabelColorValue == activeFilterLabelColorValue &&
        listEquals(other.tierOptions, tierOptions) &&
        other.emptyHint == emptyHint &&
        listEquals(other.tasks, tasks) &&
        listEquals(other.allLabels, allLabels) &&
        listEquals(other.allLocations, allLocations) &&
        other.hasBothScopedAndGlobalLabels == hasBothScopedAndGlobalLabels &&
        other.currentLocalDateTimeHint == currentLocalDateTimeHint;
  }

  @override
  int get hashCode => Object.hash(
    isLoading,
    fullScreenFileReadError,
    Object.hashAll(banners),
    headerTitle,
    headerSubtitle,
    headerCountLabel,
    activeFilterLabelId,
    activeFilterLabelName,
    activeFilterLabelColorValue,
    Object.hashAll(tierOptions),
    emptyHint,
    Object.hashAll(tasks),
    Object.hashAll(allLabels),
    Object.hashAll(allLocations),
    hasBothScopedAndGlobalLabels,
    currentLocalDateTimeHint,
  );
}

/// Immutable daily time-window draft pair (`HH:MM`..`HH:MM`).
@immutable
class TimeWindowDraftViewModel {
  /// Creates a [TimeWindowDraftViewModel].
  const TimeWindowDraftViewModel({required this.start, required this.end});

  /// Inclusive end time token (`HH:MM`).
  final String end;

  /// Inclusive start time token (`HH:MM`).
  final String start;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TimeWindowDraftViewModel &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);
}

/// Evaluates whether [task]'s effective conditions (including inherited labels) are satisfied at [localNow].
bool _areEffectiveConditionsSatisfied({
  required TaskItem task,
  required Map<String, TdfLabel> labelsById,
  required Map<String, TdfLocation> locationsById,
  required DateTime localNow,
  required LocationFix? activeFix,
}) {
  final hasGlobalReset = task.conditions.any(
    (condition) => condition is GlobalResetTaskCondition,
  );
  final inheritedRules = <TaskCondition>[
    if (!hasGlobalReset)
      for (final labelId in task.labelIds)
        if (labelsById[labelId] case final label?) ...label.conditions,
  ];
  for (final group in ConditionGroup.values) {
    final hasGroupReset = task.conditions.any(
      (condition) =>
          condition is GroupResetTaskCondition &&
          condition.targetGroup == group,
    );
    final taskRules = task.conditions
        .where(
          (condition) =>
              condition.group == group &&
              condition is! GroupResetTaskCondition &&
              condition is! GlobalResetTaskCondition,
        )
        .toList();
    final effectiveRules = taskRules.isNotEmpty
        ? taskRules
        : (hasGroupReset
              ? const <TaskCondition>[]
              : inheritedRules
                    .where((condition) => condition.group == group)
                    .toList());
    if (effectiveRules.isEmpty) {
      continue;
    }
    final satisfied = effectiveRules.any(
      (rule) => rule.isSatisfiedAt(
        localNow,
        currentLatitude: activeFix?.latitude,
        currentLongitude: activeFix?.longitude,
        locations: locationsById,
      ),
    );
    if (!satisfied) {
      return false;
    }
  }
  return true;
}

/// Builds the [ConditionDraftViewModel] representing [rules] on a task or label.
ConditionDraftViewModel _buildConditionDraft(
  List<TaskCondition> rules, {
  required bool isTask,
}) {
  final ignoreAll =
      isTask && rules.any((condition) => condition is GlobalResetTaskCondition);
  final weekdays = <int>[];
  final timeWindows = <TimeWindowDraftViewModel>[];
  final locationIds = <String>[];
  var dayAny = false;
  var timeAny = false;
  var locationAny = false;

  for (final rule in rules) {
    switch (rule) {
      case GlobalResetTaskCondition():
        break;
      case GroupResetTaskCondition(:final targetGroup):
        if (targetGroup == ConditionGroup.day) dayAny = true;
        if (targetGroup == ConditionGroup.time) timeAny = true;
        if (targetGroup == ConditionGroup.location) locationAny = true;
      case DayTaskCondition():
        for (final day in rule.weekdays) {
          if (!weekdays.contains(day)) {
            weekdays.add(day);
          }
        }
      case TimeWindowTaskCondition(:final startToken, :final endToken):
        timeWindows.add(
          TimeWindowDraftViewModel(start: startToken, end: endToken),
        );
      case LocationTaskCondition():
        for (final id in rule.locationIds) {
          if (!locationIds.contains(id)) {
            locationIds.add(id);
          }
        }
    }
  }
  weekdays.sort();

  ConditionDimensionMode resolveMode(bool hasRules, bool hasAny) {
    if (hasRules) return ConditionDimensionMode.custom;
    if (isTask && hasAny) return ConditionDimensionMode.any;
    return isTask
        ? ConditionDimensionMode.inherit
        : ConditionDimensionMode.custom;
  }

  return ConditionDraftViewModel(
    ignoreAllLabelConditions: ignoreAll,
    daysMode: resolveMode(weekdays.isNotEmpty, dayAny),
    selectedWeekdays: weekdays,
    timesMode: resolveMode(timeWindows.isNotEmpty, timeAny),
    timeWindows: timeWindows,
    locationsMode: resolveMode(locationIds.isNotEmpty, locationAny),
    selectedLocationIds: locationIds,
  );
}

/// Builds read-only condition summary chips for [rules] plus optional inherited label rules.
List<ConditionSummaryChipViewModel> _buildConditionSummaryChips({
  required List<TaskCondition> ownRules,
  required List<TaskCondition> inheritedRules,
  required Map<String, TdfLocation> locationsById,
  required AppLocalizations localizations,
}) {
  final chips = <ConditionSummaryChipViewModel>[];
  final hasGlobalReset = ownRules.any(
    (condition) => condition is GlobalResetTaskCondition,
  );
  if (hasGlobalReset) {
    chips.add(
      ConditionSummaryChipViewModel(
        label: localizations.conditionGlobalAnyLabel,
      ),
    );
  }
  _appendRuleSummaryChips(
    rules: ownRules,
    isInherited: false,
    locationsById: locationsById,
    localizations: localizations,
    target: chips,
  );
  if (!hasGlobalReset && inheritedRules.isNotEmpty) {
    _appendRuleSummaryChips(
      rules: inheritedRules,
      isInherited: true,
      locationsById: locationsById,
      localizations: localizations,
      target: chips,
    );
  }
  return chips;
}

/// Appends localized summary chips for each rule in [rules].
void _appendRuleSummaryChips({
  required List<TaskCondition> rules,
  required bool isInherited,
  required Map<String, TdfLocation> locationsById,
  required AppLocalizations localizations,
  required List<ConditionSummaryChipViewModel> target,
}) {
  final dayNames = <String>[
    localizations.weekdayMon,
    localizations.weekdayTue,
    localizations.weekdayWed,
    localizations.weekdayThu,
    localizations.weekdayFri,
    localizations.weekdaySat,
    localizations.weekdaySun,
  ];
  for (final rule in rules) {
    switch (rule) {
      case GlobalResetTaskCondition():
        break;
      case GroupResetTaskCondition(:final targetGroup):
        final label = switch (targetGroup) {
          ConditionGroup.day => localizations.conditionDayAnyLabel,
          ConditionGroup.time => localizations.conditionTimeAnyLabel,
          ConditionGroup.location => localizations.conditionLocationAnyLabel,
        };
        target.add(
          ConditionSummaryChipViewModel(label: label, isInherited: isInherited),
        );
      case DayTaskCondition(:final weekdays):
        final formatted = weekdays
            .where((day) => day >= 1 && day <= 7)
            .map((day) => dayNames[day - 1])
            .join(', ');
        if (formatted.isNotEmpty) {
          target.add(
            ConditionSummaryChipViewModel(
              label: formatted,
              isInherited: isInherited,
            ),
          );
        }
      case TimeWindowTaskCondition(:final startToken, :final endToken):
        target.add(
          ConditionSummaryChipViewModel(
            label: '$startToken - $endToken',
            isInherited: isInherited,
          ),
        );
      case LocationTaskCondition(:final locationIds):
        for (final locationId in locationIds) {
          final location = locationsById[locationId];
          target.add(
            ConditionSummaryChipViewModel(
              label: location?.name ?? locationId,
              locationId: location != null ? locationId : null,
              isInherited: isInherited,
            ),
          );
        }
    }
  }
}

/// Builds a single [LabelCardViewModel] from [label].
LabelCardViewModel _buildLabelCardViewModel({
  required TdfLabel label,
  required int openCount,
  required Map<String, TdfLocation> locationsById,
  required AppLocalizations localizations,
}) {
  final summaryChips = _buildConditionSummaryChips(
    ownRules: label.conditions,
    inheritedRules: const <TaskCondition>[],
    locationsById: locationsById,
    localizations: localizations,
  );
  final labelNote = label.note;
  final unset = <LabelSectionKind>[
    if (labelNote == null || labelNote.trim().isEmpty) LabelSectionKind.note,
    if (label.links.isEmpty) LabelSectionKind.links,
    if (label.conditions.isEmpty) LabelSectionKind.conditions,
  ];
  return LabelCardViewModel(
    id: label.id,
    name: label.name,
    colorHex: label.color ?? '',
    colorValue: _parseLabelColorValue(label.color),
    isScoped: label.isScoped,
    openCount: openCount,
    note: label.note,
    links: <EntityLinkViewModel>[
      for (final link in label.links)
        EntityLinkViewModel(title: link.title, uri: link.uri),
    ],
    hasConditions: label.conditions.isNotEmpty,
    conditionsSummary: summaryChips,
    conditionDraft: _buildConditionDraft(label.conditions, isTask: false),
    unsetSections: unset,
  );
}

/// Builds a single [LocationCardViewModel] from [location].
LocationCardViewModel _buildLocationCardViewModel({
  required TdfLocation location,
  required int openCount,
  required LocationEditorController locationController,
  required AppLocalizations localizations,
}) {
  final sourceType = locationController.classifySource(location.source);
  final shellSourceType = switch (sourceType) {
    LocationSourceType.gps => ShellLocationSourceType.gps,
    LocationSourceType.address => ShellLocationSourceType.address,
    LocationSourceType.plusCode => ShellLocationSourceType.plusCode,
  };
  final sourceTypeLabel = switch (shellSourceType) {
    ShellLocationSourceType.gps => localizations.locationSourceTypeGps,
    ShellLocationSourceType.address => localizations.locationSourceTypeAddress,
    ShellLocationSourceType.plusCode =>
      localizations.locationSourceTypePlusCode,
  };
  final rawSource = location.source?.trim() ?? '';
  final sourceValue =
      shellSourceType == ShellLocationSourceType.gps ||
          rawSource.toLowerCase() == 'manual' ||
          rawSource.toLowerCase() == 'gps'
      ? ''
      : rawSource;
  final radiusSummary = _formatRadiusMeters(location.radius);
  final locationNote = location.note;
  final unset = <LocationSectionKind>[
    if (locationNote == null || locationNote.trim().isEmpty)
      LocationSectionKind.note,
  ];
  return LocationCardViewModel(
    id: location.id,
    name: location.name,
    sourceType: shellSourceType,
    sourceValue: sourceValue,
    sourceTypeLabel: sourceTypeLabel,
    latitudeText: location.latitudeText,
    longitudeText: location.longitudeText,
    radiusText: radiusSummary,
    coordinatesSummary: _formatCoordinatesSummary(location),
    radiusSummary: radiusSummary,
    openCount: openCount,
    note: location.note,
    unsetSections: unset,
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

/// Builds the ordered operational status banners for Tasks view (`U-UX-007`).
List<ShellBannerViewModel> _buildStatusBanners({
  required WebDavConfig config,
  required SyncState syncState,
  required ShellView activeView,
  required bool syncErrorDismissed,
  required bool fileReadDismissed,
  required bool fullScreenError,
  required AppLocalizations localizations,
}) {
  if (fullScreenError) {
    return const <ShellBannerViewModel>[];
  }
  final banners = <ShellBannerViewModel>[];
  if (config.storageMode.usesWebDav && !config.isWebDavConfigured) {
    banners.add(
      ShellBannerViewModel(
        kind: ShellBannerKind.unconfiguredWebDav,
        tone: BannerTone.warning,
        message: localizations.unconfiguredBannerText,
        dismissible: false,
        primaryActionLabel: localizations.actionConfigure,
      ),
    );
  }
  final outcome = syncState.syncOutcome;
  if (syncState.hasOpenConflict && outcome != null) {
    switch (outcome.kind) {
      case TdfSyncOutcomeKind.deletionConflict:
        if (activeView != ShellView.conflict) {
          banners.add(
            ShellBannerViewModel(
              kind: ShellBannerKind.deletionConflict,
              tone: BannerTone.warning,
              message:
                  syncState.errorMessage ??
                  localizations.syncConflictDeletionBanner,
              dismissible: false,
              primaryActionLabel: localizations.actionResolveConflict,
            ),
          );
        }
      case TdfSyncOutcomeKind.recoveryRequired:
        if (activeView != ShellView.recovery) {
          banners.add(
            ShellBannerViewModel(
              kind: ShellBannerKind.recoveryRequired,
              tone: BannerTone.warning,
              message:
                  syncState.errorMessage ??
                  localizations.syncConflictRecoveryBanner,
              dismissible: false,
              primaryActionLabel: localizations.actionResolveRecovery,
            ),
          );
        }
      case TdfSyncOutcomeKind.syncGenerationRollback:
        if (!syncErrorDismissed) {
          banners.add(
            ShellBannerViewModel(
              kind: ShellBannerKind.syncError,
              tone: BannerTone.danger,
              message:
                  syncState.errorMessage ??
                  localizations.syncErrorGenerationRollbackBanner,
              dismissible: true,
              primaryActionLabel: localizations.actionRetry,
              secondaryActionLabel: localizations.actionSettings,
            ),
          );
        }
    }
  } else if (syncState.fileReadReport case final report?) {
    if (!fileReadDismissed && report.hasFailure) {
      final scope = report.failureScope;
      banners.add(
        ShellBannerViewModel(
          kind: ShellBannerKind.partialFileRead,
          tone: BannerTone.danger,
          message: scope != null
              ? localizations.storageFileReadSummary(scope)
              : localizations.fileReadErrorTitle,
          dismissible: true,
          primaryActionLabel: localizations.actionRetry,
          secondaryActionLabel: localizations.actionSettings,
          diagnosticLines: _formatFileReadDiagnosticLines(
            report,
            localizations,
          ),
        ),
      );
    }
  } else if (syncState.errorMessage case final errorMessage?) {
    if (!syncErrorDismissed && errorMessage.isNotEmpty) {
      banners.add(
        ShellBannerViewModel(
          kind: ShellBannerKind.syncError,
          tone: BannerTone.danger,
          message: errorMessage,
          dismissible: true,
          primaryActionLabel: localizations.actionRetry,
          secondaryActionLabel: localizations.actionSettings,
        ),
      );
    }
  }
  return banners;
}

/// Builds a single [TaskCardViewModel] enforcing `U-CARD-001`..`005`.
TaskCardViewModel _buildTaskCardViewModel({
  required TaskBoard board,
  required TaskItem task,
  required ShellTier tier,
  required bool isSearchMode,
  required Map<String, TdfLabel> labelsById,
  required Map<String, TdfLocation> locationsById,
  required Map<String, TaskItem> tasksById,
  required WebDavConfig config,
  required DateTime nowUtc,
  required DateTime localNow,
  required LocationFix? activeFix,
  required AppLocalizations localizations,
}) {
  final assignedLabels = <EntityLabelChipViewModel>[
    for (final labelId in task.labelIds)
      if (labelsById[labelId] case final label?)
        EntityLabelChipViewModel(
          id: label.id,
          name: label.name,
          colorValue: _parseLabelColorValue(label.color),
          isScoped: label.isScoped,
        ),
  ];

  final isActive = !task.isCompleted;
  final isSomeday = tier == ShellTier.someday;
  final isSuspended =
      task.isSuspendedForever || task.hasActiveSuspendedAt(nowUtc);
  final dueAt = task.dueAt;
  final isOverdue = isActive && dueAt != null && !dueAt.isAfter(nowUtc);
  final leadDuration = config.dueLeadWindow.duration;
  final isWithinLead =
      isActive &&
      dueAt != null &&
      !task.isDuePassive &&
      task.isWithinDueLeadWindow(nowUtc, leadDuration);
  final isAutoPrioritized =
      isActive && !isSomeday && !task.isPriority && isWithinLead;

  final primaryBadges = <CardBadgeViewModel>[
    if (isSearchMode)
      CardBadgeViewModel(
        label: _tierName(tier, localizations),
        tone: BadgeTone.soft,
        iconKey: _tierBadgeIcon(tier),
      ),
    if (dueAt != null)
      _buildDueBadge(
        dueAtUtc: dueAt,
        isActive: isActive,
        isOverdue: isOverdue,
        isWithinLead: isWithinLead,
        config: config,
        localizations: localizations,
      ),
  ];

  final inheritedConditions = <TaskCondition>[
    for (final labelId in task.labelIds)
      if (labelsById[labelId] case final label?) ...label.conditions,
  ];
  final hasConditions =
      task.conditions.isNotEmpty || inheritedConditions.isNotEmpty;
  final conditionsSatisfied =
      !hasConditions ||
      _areEffectiveConditionsSatisfied(
        task: task,
        labelsById: labelsById,
        locationsById: locationsById,
        localNow: localNow,
        activeFix: activeFix,
      );

  final prereqItems = _buildPrerequisiteItems(task, tasksById);
  final satisfiedPrereqCount = prereqItems
      .where((item) => item.isSatisfied)
      .length;
  final hasUnsatisfiedPrereqs =
      prereqItems.isNotEmpty && satisfiedPrereqCount < prereqItems.length;

  final subtasksCompleted = task.subtasks
      .where((step) => step.isCompleted)
      .length;
  final repeatRule = task.repeatRule;
  final repeatSummary = repeatRule != null
      ? _formatRepeatPhrase(repeatRule, localizations)
      : null;

  final allSecondary = _buildSecondaryBadges(
    task: task,
    isActive: isActive,
    isAutoPrioritized: isAutoPrioritized,
    isSuspended: isSuspended,
    hasUnsatisfiedPrereqs: hasUnsatisfiedPrereqs,
    satisfiedPrereqCount: satisfiedPrereqCount,
    totalPrereqCount: prereqItems.length,
    hasConditions: hasConditions,
    conditionsSatisfied: conditionsSatisfied,
    subtasksCompleted: subtasksCompleted,
    repeatSummary: repeatSummary,
    config: config,
    localizations: localizations,
  );
  final visibleSecondary = allSecondary.length > 3
      ? allSecondary.sublist(0, 3)
      : allSecondary;
  final overflowCount = allSecondary.length > 3 ? allSecondary.length - 3 : 0;

  final dueFormatted = dueAt != null
      ? _formatDueDetail(
          dueAtUtc: dueAt,
          nowUtc: nowUtc,
          isOverdue: isOverdue,
          config: config,
          localizations: localizations,
        )
      : null;
  final dueAnchorFormatted = _formatDueAnchor(
    task: task,
    config: config,
    localizations: localizations,
  );
  final dueAutoPriorityLabel = dueAt != null
      ? _formatDueAutoPriorityLabel(
          task: task,
          isAutoPrioritized: isAutoPrioritized,
          leadWindow: config.dueLeadWindow,
          localizations: localizations,
        )
      : null;

  final suspendedSummary = isSuspended
      ? _formatSuspendedDetail(
          task: task,
          nowUtc: nowUtc,
          config: config,
          localizations: localizations,
        )
      : null;

  final placement = task.isPriority
      ? TaskPlacementOption.priority
      : (isSomeday ? TaskPlacementOption.someday : TaskPlacementOption.queue);

  final historyEntries = <HistoryEntryViewModel>[
    for (var i = 0; i < task.history.length; i++)
      HistoryEntryViewModel(
        index: i,
        timestampUtcIso: task.history[i].timestampUtc.toIso8601String(),
        formattedLocalTimestamp: TaskEditorController.formatLocalTimestamp(
          task.history[i].timestampUtc,
          config,
        ),
        text: task.history[i].text,
      ),
  ];

  final candidates = _buildPrerequisiteCandidates(board, task);
  final conditionSummary = _buildConditionSummaryChips(
    ownRules: task.conditions,
    inheritedRules: inheritedConditions,
    locationsById: locationsById,
    localizations: localizations,
  );

  final unsetSections = task.isCompleted
      ? const <TaskSectionKind>[]
      : _collectUnsetTaskSections(
          task: task,
          isSuspended: isSuspended,
          hasConditions: hasConditions,
        );

  final repeatLeadDays = repeatRule?.leadDays;
  return TaskCardViewModel(
    id: task.id,
    title: task.title,
    tier: tier,
    isCompleted: task.isCompleted,
    canDowngrade:
        isActive &&
        (tier == ShellTier.focus ||
            tier == ShellTier.ready ||
            tier == ShellTier.planned),
    isPriority: task.isPriority,
    isAutoPrioritized: isAutoPrioritized,
    isSomeday: isSomeday,
    isSuspended: isSuspended,
    isSuspendedIndefinitely: task.isSuspendedForever,
    placement: placement,
    assignedLabels: assignedLabels,
    primaryBadges: primaryBadges,
    visibleSecondaryBadges: visibleSecondary,
    overflowSecondaryCount: overflowCount,
    note: task.note,
    links: <EntityLinkViewModel>[
      for (final link in task.links)
        EntityLinkViewModel(title: link.title, uri: link.uri),
    ],
    subtasks: <SubtaskViewModel>[
      for (var i = 0; i < task.subtasks.length; i++)
        SubtaskViewModel(
          index: i,
          title: task.subtasks[i].title,
          isCompleted: task.subtasks[i].isCompleted,
        ),
    ],
    subtasksAutoFinish: task.subtasksAutoFinish,
    subtasksCompletedCount: subtasksCompleted,
    subtasksProgressLabel: task.subtasks.isEmpty
        ? null
        : localizations.taskInfoSubtasksProgress(
            '$subtasksCompleted',
            '${task.subtasks.length}',
          ),
    history: historyEntries,
    dueFormatted: dueFormatted,
    dueInputInitial: dueAt != null
        ? TaskEditorController.formatLocalTimestamp(dueAt, config)
        : '',
    dueNote: task.dueNote,
    dueAnchorFormatted: dueAnchorFormatted,
    dueAutoPriorityLabel: dueAutoPriorityLabel,
    isDuePassive: task.isDuePassive,
    isOverdue: isOverdue,
    isWithinDueLeadWindow: isWithinLead,
    repeatSummary: repeatSummary,
    repeatCount: repeatRule?.count,
    repeatUnit: repeatRule != null ? _mapRepeatUnit(repeatRule.unit) : null,
    repeatLeadDays: repeatLeadDays,
    repeatCompletionsLabel: repeatRule != null && task.completions > 0
        ? localizations.taskInfoRepeatCompletions('${task.completions}')
        : null,
    repeatLeadLabel: repeatLeadDays != null && repeatLeadDays > 0
        ? localizations.taskInfoRepeatLeadDays('$repeatLeadDays')
        : null,
    suspendedSummary: suspendedSummary,
    suspendedInputInitial: task.suspendedAt != null
        ? TaskEditorController.formatInitialSuspendedText(
            task.suspendedAt,
            config,
          )
        : '',
    suspendedNote: task.suspendedNote,
    prerequisites: prereqItems,
    prerequisitesProgressLabel: prereqItems.isEmpty
        ? null
        : localizations.taskInfoBlockedByProgress(
            '$satisfiedPrereqCount',
            '${prereqItems.length}',
          ),
    prerequisiteCandidates: candidates,
    hasConditions: hasConditions,
    conditionsSatisfied: conditionsSatisfied,
    conditionsStatusLabel: conditionsSatisfied
        ? localizations.conditionSatisfiedStatus
        : localizations.conditionBlockedStatus,
    conditionsSummary: conditionSummary,
    conditionDraft: _buildConditionDraft(task.conditions, isTask: true),
    unsetSections: unsetSections,
  );
}

/// Builds the primary Due / Overdue badge (`U-CARD-005`).
CardBadgeViewModel _buildDueBadge({
  required DateTime dueAtUtc,
  required bool isActive,
  required bool isOverdue,
  required bool isWithinLead,
  required WebDavConfig config,
  required AppLocalizations localizations,
}) {
  final formatted = TaskEditorController.formatLocalTimestamp(dueAtUtc, config);
  if (isActive && isOverdue) {
    return CardBadgeViewModel(
      label: localizations.badgeOverduePrefix(formatted),
      tone: BadgeTone.danger,
      iconKey: CardBadgeIconKey.due,
    );
  }
  return CardBadgeViewModel(
    label: localizations.pillDuePrefix(formatted),
    tone: (isActive && isWithinLead) ? BadgeTone.warning : BadgeTone.neutral,
    iconKey: CardBadgeIconKey.due,
  );
}

/// Builds prerequisite picker candidates excluding self and non-selected completed tasks, tagging cycles.
List<PrerequisiteCandidateViewModel> _buildPrerequisiteCandidates(
  TaskBoard board,
  TaskItem task,
) {
  final selectedIds = task.blockedByTaskIds.toSet();
  final candidates = <PrerequisiteCandidateViewModel>[];
  for (final other in board.allTasks) {
    if (other.id == task.id) {
      continue;
    }
    final isSelected = selectedIds.contains(other.id);
    if (other.isCompleted && !isSelected) {
      continue;
    }
    final wouldCycle =
        !isSelected && board.wouldCreateDependencyCycle(task.id, other.id);
    candidates.add(
      PrerequisiteCandidateViewModel(
        id: other.id,
        title: other.title,
        wouldCreateCycle: wouldCycle,
        isSelected: isSelected,
      ),
    );
  }
  candidates.sort(
    (left, right) =>
        left.title.toLowerCase().compareTo(right.title.toLowerCase()),
  );
  return candidates;
}

/// Resolves assigned prerequisite display items and completion satisfaction.
List<PrerequisiteItemViewModel> _buildPrerequisiteItems(
  TaskItem task,
  Map<String, TaskItem> tasksById,
) {
  final items = <PrerequisiteItemViewModel>[];
  for (final dependency in task.dependencies) {
    final target = tasksById[dependency.taskId];
    final satisfied =
        target != null && target.completions >= dependency.requiredCompletion;
    items.add(
      PrerequisiteItemViewModel(
        id: dependency.taskId,
        title: target?.title ?? dependency.taskId,
        isSatisfied: satisfied,
        requiredCompletion: dependency.requiredCompletion,
      ),
    );
  }
  return items;
}

/// Builds the complete ordered list of secondary badges matching `U-CARD-005` strict priority order.
List<CardBadgeViewModel> _buildSecondaryBadges({
  required TaskItem task,
  required bool isActive,
  required bool isAutoPrioritized,
  required bool isSuspended,
  required bool hasUnsatisfiedPrereqs,
  required int satisfiedPrereqCount,
  required int totalPrereqCount,
  required bool hasConditions,
  required bool conditionsSatisfied,
  required int subtasksCompleted,
  required String? repeatSummary,
  required WebDavConfig config,
  required AppLocalizations localizations,
}) {
  final badges = <CardBadgeViewModel>[];
  // 1. Manual Priority OR Automatic Priority escalation.
  if (isActive && task.isPriority) {
    badges.add(
      CardBadgeViewModel(
        label: localizations.quickAddPriority,
        tone: BadgeTone.accent,
        iconKey: CardBadgeIconKey.priority,
      ),
    );
  } else if (isAutoPrioritized) {
    badges.add(
      CardBadgeViewModel(
        label: localizations.badgeAutoPriority,
        tone: BadgeTone.warning,
        iconKey: CardBadgeIconKey.priority,
      ),
    );
  }
  // 2. Suspended.
  if (isSuspended) {
    final label = task.isSuspendedForever || task.suspendedAt == null
        ? localizations.badgeSuspendedForever
        : localizations.badgeSuspendedUntil(
            TaskEditorController.formatLocalTimestamp(task.suspendedAt, config),
          );
    badges.add(
      CardBadgeViewModel(
        label: label,
        tone: BadgeTone.warning,
        iconKey: CardBadgeIconKey.suspended,
      ),
    );
  }
  // 3. Blocked by Prerequisites (omitted once satisfied).
  if (hasUnsatisfiedPrereqs) {
    badges.add(
      CardBadgeViewModel(
        label: localizations.badgeBlockedByProgress(
          '$satisfiedPrereqCount',
          '$totalPrereqCount',
        ),
        tone: BadgeTone.warning,
        iconKey: CardBadgeIconKey.blockedBy,
      ),
    );
  }
  // 4. Activation Conditions.
  if (hasConditions) {
    badges.add(
      CardBadgeViewModel(
        label: localizations.tooltipIndicatorConditions,
        tone: conditionsSatisfied ? BadgeTone.neutral : BadgeTone.warning,
        iconKey: CardBadgeIconKey.conditions,
      ),
    );
  }
  // 5. Subtasks.
  if (task.subtasks.isNotEmpty) {
    badges.add(
      CardBadgeViewModel(
        label: localizations.badgeStepsProgress(
          '$subtasksCompleted',
          '${task.subtasks.length}',
        ),
        tone: BadgeTone.neutral,
        iconKey: task.subtasksAutoFinish
            ? CardBadgeIconKey.subtasksAutoFinish
            : CardBadgeIconKey.subtasks,
      ),
    );
  }
  // 6. Repeat.
  if (repeatSummary != null) {
    badges.add(
      CardBadgeViewModel(
        label: repeatSummary,
        tone: BadgeTone.neutral,
        iconKey: CardBadgeIconKey.repeat,
      ),
    );
  }
  // 7. Note.
  if (task.note case final note? when note.trim().isNotEmpty) {
    badges.add(
      CardBadgeViewModel(
        label: localizations.tooltipIndicatorNote,
        tone: BadgeTone.neutral,
        iconKey: CardBadgeIconKey.note,
      ),
    );
  }
  // 8. Links.
  if (task.links.isNotEmpty) {
    final label = task.links.length == 1
        ? localizations.badgeLinkSingular
        : localizations.taskInfoLinksCount('${task.links.length}');
    badges.add(
      CardBadgeViewModel(
        label: label,
        tone: BadgeTone.neutral,
        iconKey: CardBadgeIconKey.links,
      ),
    );
  }
  // 9. History.
  if (task.history.isNotEmpty) {
    badges.add(
      CardBadgeViewModel(
        label: localizations.badgeHistoryCount('${task.history.length}'),
        tone: BadgeTone.neutral,
        iconKey: CardBadgeIconKey.history,
      ),
    );
  }
  return badges;
}

/// Collects visible unset editable sections for the bottom `+ Add` chips bar on open tasks.
List<TaskSectionKind> _collectUnsetTaskSections({
  required TaskItem task,
  required bool isSuspended,
  required bool hasConditions,
}) {
  final taskNote = task.note;
  return <TaskSectionKind>[
    if (taskNote == null || taskNote.trim().isEmpty) TaskSectionKind.note,
    if (task.links.isEmpty) TaskSectionKind.links,
    if (task.subtasks.isEmpty) TaskSectionKind.subtasks,
    if (task.labelIds.isEmpty) TaskSectionKind.labels,
    if (task.dueAt == null) TaskSectionKind.due,
    if (task.repeatRule == null) TaskSectionKind.repeat,
    if (!isSuspended) TaskSectionKind.suspended,
    if (task.dependencies.isEmpty) TaskSectionKind.prerequisites,
    if (!hasConditions) TaskSectionKind.conditions,
  ];
}

/// Collects `(task, tier)` entries for the active tier or across all six tiers in Global Search.
List<({TaskItem task, ShellTier tier})> _collectVisibleTasks({
  required TaskBoard board,
  required ShellTier activeTier,
  required bool searchOpen,
  required String searchQuery,
}) {
  if (!searchOpen) {
    final tasks = board.tasksForTier(_toTaskTier(activeTier));
    return <({TaskItem task, ShellTier tier})>[
      for (final task in tasks) (task: task, tier: activeTier),
    ];
  }
  final needle = searchQuery.trim().toLowerCase();
  final results = <({TaskItem task, ShellTier tier})>[];
  for (final tier in ShellTier.values) {
    for (final task in board.tasksForTier(_toTaskTier(tier))) {
      if (needle.isEmpty || _matchesSearchQuery(task, needle)) {
        results.add((task: task, tier: tier));
      }
    }
  }
  return results;
}

/// Formats 4-decimal coordinate and radius summary (`47.1204, 8.5173 · 250m`).
String _formatCoordinatesSummary(TdfLocation location) {
  final lat = location.latitude.toStringAsFixed(4);
  final lon = location.longitude.toStringAsFixed(4);
  return '$lat, $lon · ${_formatRadiusMeters(location.radius)}';
}

/// Formats optional schedule anchor display text when `dueAnchor` differs from wall-clock `dueAt`.
String? _formatDueAnchor({
  required TaskItem task,
  required WebDavConfig config,
  required AppLocalizations localizations,
}) {
  final anchor = task.dueAnchor;
  final dueAt = task.dueAt;
  if (anchor == null || dueAt == null) {
    return null;
  }
  final localDue = config.toLocalWallClock(dueAt);
  if (!TaskInfoController.differsFromWallClock(anchor, localDue)) {
    return null;
  }
  return localizations.taskInfoDueAnchorDetail(anchor.formatCompact());
}

/// Formats the auto-priority detail hint inside the expanded Due section.
String _formatDueAutoPriorityLabel({
  required TaskItem task,
  required bool isAutoPrioritized,
  required DueLeadWindow leadWindow,
  required AppLocalizations localizations,
}) {
  if (task.isDuePassive) {
    return localizations.taskInfoDuePassiveHint;
  }
  if (leadWindow == DueLeadWindow.off) {
    return localizations.taskInfoDueLeadWindowOffHint;
  }
  if (isAutoPrioritized) {
    return localizations.taskInfoDueAutoPromotedActive;
  }
  if (leadWindow == DueLeadWindow.atDue) {
    return localizations.taskInfoDueAutoPromoteAtDue;
  }
  final shortLabel = switch (leadWindow) {
    DueLeadWindow.off || DueLeadWindow.atDue => '',
    DueLeadWindow.hours12 => localizations.dueLeadWindowShort12Hours,
    DueLeadWindow.hours24 => localizations.dueLeadWindowShort24Hours,
    DueLeadWindow.hours48 => localizations.dueLeadWindowShort48Hours,
    DueLeadWindow.days7 => localizations.dueLeadWindowShort7Days,
  };
  return localizations.taskInfoDueAutoPromoteScheduled(shortLabel);
}

/// Formats the Due section primary readout (`timestamp (remaining)` or `Overdue (timestamp)`).
String _formatDueDetail({
  required DateTime dueAtUtc,
  required DateTime nowUtc,
  required bool isOverdue,
  required WebDavConfig config,
  required AppLocalizations localizations,
}) {
  final formatted = TaskEditorController.formatLocalTimestamp(dueAtUtc, config);
  if (isOverdue) {
    return localizations.taskInfoDueOverdue(formatted);
  }
  final duration = TaskInfoController.formatRemainingDuration(
    dueAtUtc.difference(nowUtc),
    localizations,
  );
  return localizations.taskInfoDueAt(formatted, duration);
}

/// Formats per-target lines from a [StorageFileReadReport].
List<FileReadDiagnosticLineViewModel> _formatFileReadDiagnosticLines(
  StorageFileReadReport report,
  AppLocalizations localizations,
) {
  return <FileReadDiagnosticLineViewModel>[
    for (final entry in report.activeEntries)
      FileReadDiagnosticLineViewModel(
        targetLabel: localizations.storageFileTargetLabel(entry.target),
        statusText: localizations.storageFileReadEntryText(entry),
        isReadable: entry.isReadable,
      ),
  ];
}

/// Formats [radiusMeters] compactly as meters or kilometers.
String _formatRadiusMeters(double radiusMeters) {
  if (radiusMeters >= 1000.0 && radiusMeters % 1000.0 == 0.0) {
    return '${(radiusMeters / 1000.0).toInt()}km';
  }
  if (radiusMeters >= 1000.0) {
    return '${TdfLocation.formatRoundedDouble(radiusMeters / 1000.0, 2)}km';
  }
  return '${TdfLocation.formatRoundedDouble(radiusMeters, 2)}m';
}

/// Formats a [TaskRepeatRule] into a localized human-readable interval phrase.
String _formatRepeatPhrase(
  TaskRepeatRule rule,
  AppLocalizations localizations,
) {
  if (rule.count == 1) {
    return switch (rule.unit) {
      RepeatUnit.days => localizations.repeatEveryDay,
      RepeatUnit.weeks => localizations.repeatEveryWeek,
      RepeatUnit.months => localizations.repeatEveryMonth,
    };
  }
  final unitLabel = switch (rule.unit) {
    RepeatUnit.days => localizations.repeatUnitDays,
    RepeatUnit.weeks => localizations.repeatUnitWeeks,
    RepeatUnit.months => localizations.repeatUnitMonths,
  };
  return localizations.taskInfoRepeatEvery('${rule.count}', unitLabel);
}

/// Formats the Suspended section primary readout.
String _formatSuspendedDetail({
  required TaskItem task,
  required DateTime nowUtc,
  required WebDavConfig config,
  required AppLocalizations localizations,
}) {
  final target = task.suspendedAt;
  if (task.isSuspendedForever || target == null) {
    return localizations.taskInfoSuspendedForever;
  }
  final formatted = TaskEditorController.formatLocalTimestamp(target, config);
  final duration = TaskInfoController.formatRemainingDuration(
    target.difference(nowUtc),
    localizations,
  );
  return localizations.taskInfoSuspendedUntil(formatted, duration);
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

/// Maps domain [RepeatUnit] to presentation [ShellRepeatUnit].
ShellRepeatUnit _mapRepeatUnit(RepeatUnit unit) {
  return switch (unit) {
    RepeatUnit.days => ShellRepeatUnit.days,
    RepeatUnit.weeks => ShellRepeatUnit.weeks,
    RepeatUnit.months => ShellRepeatUnit.months,
  };
}

/// Checks whether [task] matches lowercase Global Search query [needle].
bool _matchesSearchQuery(TaskItem task, String needle) {
  if (task.title.toLowerCase().contains(needle)) {
    return true;
  }
  if (task.note?.toLowerCase().contains(needle) ?? false) {
    return true;
  }
  for (final subtask in task.subtasks) {
    if (subtask.title.toLowerCase().contains(needle)) {
      return true;
    }
  }
  for (final link in task.links) {
    if (link.title.toLowerCase().contains(needle) ||
        link.uri.toLowerCase().contains(needle)) {
      return true;
    }
  }
  return false;
}

/// Parses an optional `#RRGGBB` string into a 32-bit ARGB integer.
int? _parseLabelColorValue(String? hex) => TdfColor.tryParseArgb(hex);

/// Resolves a full-screen file-read error projection when [evaluatedAsync] failed on initial load.
FileReadReportViewModel? _resolveFullScreenFileReadError({
  required AsyncValue<TaskBoard> evaluatedAsync,
  required AppLocalizations localizations,
}) {
  if (!evaluatedAsync.hasError || evaluatedAsync.hasValue) {
    return null;
  }
  final error = evaluatedAsync.error;
  if (error is StorageFileReadException) {
    final report = error.report;
    final scope = report.failureScope;
    return FileReadReportViewModel(
      title: localizations.fileReadErrorTitle,
      summary: scope != null
          ? localizations.storageFileReadSummary(scope)
          : localizations.fileReadErrorTitle,
      lines: _formatFileReadDiagnosticLines(report, localizations),
    );
  }
  return FileReadReportViewModel(
    title: localizations.fileReadErrorTitle,
    summary: localizations.errorLoadLocalFileFailed(
      error?.toString() ?? localizations.fileReadStatusUnreadable,
    ),
    lines: const <FileReadDiagnosticLineViewModel>[],
  );
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

/// Maps [ShellTier] to its Search badge [CardBadgeIconKey].
CardBadgeIconKey _tierBadgeIcon(ShellTier tier) {
  return switch (tier) {
    ShellTier.focus => CardBadgeIconKey.tierFocus,
    ShellTier.ready => CardBadgeIconKey.tierReady,
    ShellTier.planned => CardBadgeIconKey.tierPlanned,
    ShellTier.blocked => CardBadgeIconKey.tierBlocked,
    ShellTier.someday => CardBadgeIconKey.tierSomeday,
    ShellTier.completed => CardBadgeIconKey.tierCompleted,
  };
}

/// Returns the localized empty-state hint for [tier].
String _tierEmptyHint(ShellTier tier, AppLocalizations localizations) {
  return switch (tier) {
    ShellTier.focus => localizations.emptyFocusHint,
    ShellTier.ready => localizations.emptyReadyHint,
    ShellTier.planned => localizations.emptyPlannedHint,
    ShellTier.blocked => localizations.emptyBlockedHint,
    ShellTier.someday => localizations.emptySomedayHint,
    ShellTier.completed => localizations.emptyCompletedHint,
  };
}

/// Returns the localized tier name for [tier].
String _tierName(ShellTier tier, AppLocalizations localizations) =>
    localizations.tierName(_toTaskTier(tier));

/// Returns the localized tier subtitle for [tier].
String _tierSubtitle(ShellTier tier, AppLocalizations localizations) {
  return switch (tier) {
    ShellTier.focus => localizations.tierFocusSubtitle,
    ShellTier.ready => localizations.tierReadySubtitle,
    ShellTier.planned => localizations.tierPlannedSubtitle,
    ShellTier.blocked => localizations.tierBlockedSubtitle,
    ShellTier.someday => localizations.tierSomedaySubtitle,
    ShellTier.completed => localizations.tierCompletedSubtitle,
  };
}

/// Returns the soft WIP limit for [tier] (`3` for Focus, `5` for Ready, else `null`).
int? _tierWipLimit(ShellTier tier) {
  return switch (tier) {
    ShellTier.focus => 3,
    ShellTier.ready => 5,
    ShellTier.planned ||
    ShellTier.blocked ||
    ShellTier.someday ||
    ShellTier.completed => null,
  };
}

/// Maps presentation [ShellTier] to domain [TaskTier].
TaskTier _toTaskTier(ShellTier tier) {
  return switch (tier) {
    ShellTier.focus => TaskTier.focus,
    ShellTier.ready => TaskTier.ready,
    ShellTier.planned => TaskTier.planned,
    ShellTier.blocked => TaskTier.blocked,
    ShellTier.someday => TaskTier.someday,
    ShellTier.completed => TaskTier.completed,
  };
}
