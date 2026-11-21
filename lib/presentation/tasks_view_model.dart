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
import '../l10n/storage_file_read_localization_extension.dart';
import '../l10n/tier_localization_extension.dart';
import '../models/app_workspace.dart';
import '../models/location_state.dart';
import '../models/storage_file_read_status.dart';
import '../models/task_board.dart';
import '../models/task_board_evaluator.dart';
import '../models/task_item.dart';
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
import '../services/app_logger.dart';
import 'app_shell_controller.dart';
import 'board_presentation_providers.dart';
import 'shell_models.dart';
import 'task_schedule_helper.dart';
import 'view_model_primitives.dart';

/// Provides sorted prerequisite picker candidates for [taskId], or all open tasks when `null` for an uncommitted Task Draft Card.
final taskPrerequisiteCandidatesProvider = Provider.autoDispose
    .family<List<PrerequisiteCandidateViewModel>, String?>((ref, taskId) {
      final board =
          ref.watch(
            taskNotifierProvider.select(
              (boardAsync) => boardAsync.asData?.value,
            ),
          ) ??
          TaskBoard.empty();
      final allTasks = board.allTasks;
      if (taskId == null) {
        return _buildDraftPrerequisiteCandidates(allTasks);
      }
      final task = board.findTask(taskId);
      if (task == null || task.isCompleted) {
        return const <PrerequisiteCandidateViewModel>[];
      }
      return _buildTaskPrerequisiteCandidates(allTasks, task);
    });

/// Provides the model-free Tasks and Global Search projection for `lib/ui/`.
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
  final bannerSuppressionView = ref.watch(
    appShellControllerProvider.select(
      (shell) =>
          shell.view == ShellView.conflict || shell.view == ShellView.recovery
          ? shell.view
          : ShellView.tasks,
    ),
  );

  final workspaceError = ref.watch(
    activeWorkspaceProvider.select(
      (workspace) => workspace.hasError ? workspace.error : null,
    ),
  );
  final evaluatedAsync = ref.watch(evaluatedBoardProvider(activeLabelId));
  final syncBannerState = ref.watch(
    syncStateProvider.select(
      (state) => (
        hasOpenConflict: state.hasOpenConflict,
        syncOutcome: state.syncOutcome,
        fileReadReport: state.fileReadReport,
        errorMessage: state.errorMessage,
      ),
    ),
  );
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

  final fullScreenError = _resolveFullScreenFileReadError(
    evaluatedAsync: evaluatedAsync,
    workspaceError: workspaceError,
    localizations: localizations,
  );
  final isInitialLoading =
      fullScreenError == null &&
      evaluatedAsync.isLoading &&
      !evaluatedAsync.hasValue;
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
    hasOpenConflict: syncBannerState.hasOpenConflict,
    syncOutcome: syncBannerState.syncOutcome,
    fileReadReport: syncBannerState.fileReadReport,
    errorMessage: syncBannerState.errorMessage,
    activeView: bannerSuppressionView,
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
  final wipLimit = searchOpen
      ? null
      : ViewModelFormatters.tierWipLimit(activeTier);
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
        colorValue: ViewModelFormatters.parseLabelColorValue(label.color),
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
        coordinatesSummary: ViewModelFormatters.formatCoordinatesSummary(
          location,
        ),
      ),
  ];

  return TasksViewModel(
    isLoading: isInitialLoading,
    fullScreenFileReadError: fullScreenError,
    banners: banners,
    headerTitle: searchOpen
        ? localizations.searchViewTitle
        : ViewModelFormatters.tierName(activeTier, localizations),
    headerSubtitle: searchOpen
        ? localizations.searchViewSubtitle
        : _tierSubtitle(activeTier, localizations),
    headerCountLabel: countLabel,
    activeFilterLabelId: activeFilterLabel?.id,
    activeFilterLabelName: activeFilterLabel?.name,
    activeFilterLabelColorValue: ViewModelFormatters.parseLabelColorValue(
      activeFilterLabel?.color,
    ),
    tierOptions: <CompactTierOptionViewModel>[
      for (final tier in ShellTier.values)
        CompactTierOptionViewModel(
          tier: tier,
          label: ViewModelFormatters.tierName(tier, localizations),
          count: board
              .tasksForTier(ViewModelFormatters.toTaskTier(tier))
              .length,
        ),
    ],
    emptyHint: searchOpen
        ? localizations.searchEmptyHint
        : _tierEmptyHint(activeTier, localizations),
    tasks: taskCards,
    allLabels: allLabelOptions,
    allLocations: allLocationOptions,
    hasBothScopedAndGlobalLabels: hasScoped && hasGlobal,
    currentLocalDateTimeHint: TaskScheduleHelper.formatLocalTimestamp(
      nowUtc,
      config,
    ),
  );
});

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

/// Builds sorted open-task prerequisite picker candidates for an uncommitted Task Draft Card.
List<PrerequisiteCandidateViewModel> _buildDraftPrerequisiteCandidates(
  List<TaskItem> allTasks,
) {
  final candidates = <PrerequisiteCandidateViewModel>[];
  for (final other in allTasks) {
    if (other.isCompleted) {
      continue;
    }
    candidates.add(
      PrerequisiteCandidateViewModel(
        id: other.id,
        title: other.title,
        wouldCreateCycle: false,
        isSelected: false,
      ),
    );
  }
  candidates.sort(_comparePrerequisiteCandidatesByTitle);
  return List<PrerequisiteCandidateViewModel>.unmodifiable(candidates);
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
  final formatted = TaskScheduleHelper.formatLocalTimestamp(dueAtUtc, config);
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
            TaskScheduleHelper.formatLocalTimestamp(task.suspendedAt, config),
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

/// Builds the ordered operational status banners for Tasks view (`U-UX-007`).
List<ShellBannerViewModel> _buildStatusBanners({
  required WebDavConfig config,
  required bool hasOpenConflict,
  required TdfSyncOutcomeException? syncOutcome,
  required StorageFileReadReport? fileReadReport,
  required String? errorMessage,
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
  if (hasOpenConflict && syncOutcome != null) {
    switch (syncOutcome.kind) {
      case TdfSyncOutcomeKind.deletionConflict:
        if (activeView != ShellView.conflict) {
          banners.add(
            ShellBannerViewModel(
              kind: ShellBannerKind.deletionConflict,
              tone: BannerTone.warning,
              message: errorMessage ?? localizations.syncConflictDeletionBanner,
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
              message: errorMessage ?? localizations.syncConflictRecoveryBanner,
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
                  errorMessage ??
                  localizations.syncErrorGenerationRollbackBanner,
              dismissible: true,
              primaryActionLabel: localizations.actionRetry,
              secondaryActionLabel: localizations.actionSettings,
            ),
          );
        }
    }
  } else if (fileReadReport case final report?) {
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
          diagnosticLines: ViewModelFormatters.formatFileReadDiagnosticLines(
            report,
            localizations,
          ),
        ),
      );
    }
  } else if (errorMessage case final currentErrorMessage?) {
    if (!syncErrorDismissed && currentErrorMessage.isNotEmpty) {
      banners.add(
        ShellBannerViewModel(
          kind: ShellBannerKind.syncError,
          tone: BannerTone.danger,
          message: currentErrorMessage,
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
          colorValue: ViewModelFormatters.parseLabelColorValue(label.color),
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
        label: ViewModelFormatters.tierName(tier, localizations),
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
        formattedLocalTimestamp: TaskScheduleHelper.formatLocalTimestamp(
          task.history[i].timestampUtc,
          config,
        ),
        text: task.history[i].text,
      ),
  ];

  final conditionSummary = ViewModelFormatters.buildConditionSummaryChips(
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
        ? TaskScheduleHelper.formatLocalTimestamp(dueAt, config)
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
        ? TaskScheduleHelper.formatInitialSuspendedText(
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
    hasConditions: hasConditions,
    conditionsSatisfied: conditionsSatisfied,
    conditionsStatusLabel: conditionsSatisfied
        ? localizations.conditionSatisfiedStatus
        : localizations.conditionBlockedStatus,
    conditionsSummary: conditionSummary,
    conditionDraft: ViewModelFormatters.buildConditionDraft(
      task.conditions,
      isTask: true,
    ),
    unsetSections: unsetSections,
  );
}

/// Builds sorted prerequisite picker candidates for [task], tagging cycle-creating candidates in a single $O(N + E)$ pass.
List<PrerequisiteCandidateViewModel> _buildTaskPrerequisiteCandidates(
  List<TaskItem> allTasks,
  TaskItem task,
) {
  final selectedIds = task.blockedByTaskIds.toSet();
  final cyclicIds = TaskBoardEvaluator.collectCycleCreatingPrerequisiteIds(
    taskId: task.id,
    tasks: allTasks,
  );
  final candidates = <PrerequisiteCandidateViewModel>[];
  for (final other in allTasks) {
    if (other.id == task.id) {
      continue;
    }
    final isSelected = selectedIds.contains(other.id);
    if (other.isCompleted && !isSelected) {
      continue;
    }
    final wouldCycle = !isSelected && cyclicIds.contains(other.id);
    candidates.add(
      PrerequisiteCandidateViewModel(
        id: other.id,
        title: other.title,
        wouldCreateCycle: wouldCycle,
        isSelected: isSelected,
      ),
    );
  }
  candidates.sort(_comparePrerequisiteCandidatesByTitle);
  return List<PrerequisiteCandidateViewModel>.unmodifiable(candidates);
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
    final tasks = board.tasksForTier(
      ViewModelFormatters.toTaskTier(activeTier),
    );
    return <({TaskItem task, ShellTier tier})>[
      for (final task in tasks) (task: task, tier: activeTier),
    ];
  }
  final needle = searchQuery.trim().toLowerCase();
  final results = <({TaskItem task, ShellTier tier})>[];
  for (final tier in ShellTier.values) {
    for (final task in board.tasksForTier(
      ViewModelFormatters.toTaskTier(tier),
    )) {
      if (needle.isEmpty || _matchesSearchQuery(task, needle)) {
        results.add((task: task, tier: tier));
      }
    }
  }
  return results;
}

/// Compares two [PrerequisiteCandidateViewModel] items case-insensitively by title.
int _comparePrerequisiteCandidatesByTitle(
  PrerequisiteCandidateViewModel left,
  PrerequisiteCandidateViewModel right,
) => left.title.toLowerCase().compareTo(right.title.toLowerCase());

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
  if (!TaskScheduleHelper.differsFromWallClock(anchor, localDue)) {
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
  final formatted = TaskScheduleHelper.formatLocalTimestamp(dueAtUtc, config);
  if (isOverdue) {
    return localizations.taskInfoDueOverdue(formatted);
  }
  final duration = TaskScheduleHelper.formatRemainingDuration(
    dueAtUtc.difference(nowUtc),
    localizations,
  );
  return localizations.taskInfoDueAt(formatted, duration);
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
  final formatted = TaskScheduleHelper.formatLocalTimestamp(target, config);
  final duration = TaskScheduleHelper.formatRemainingDuration(
    target.difference(nowUtc),
    localizations,
  );
  return localizations.taskInfoSuspendedUntil(formatted, duration);
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

/// Resolves a full-screen file-read or workspace error projection when initial load fails.
FileReadReportViewModel? _resolveFullScreenFileReadError({
  required AsyncValue<TaskBoard> evaluatedAsync,
  required Object? workspaceError,
  required AppLocalizations localizations,
}) {
  final error =
      workspaceError ??
      ((evaluatedAsync.hasError && !evaluatedAsync.hasValue)
          ? evaluatedAsync.error
          : null);
  if (error == null) {
    return null;
  }
  if (error is StorageFileReadException) {
    final report = error.report;
    final scope = report.failureScope;
    return FileReadReportViewModel(
      title: localizations.fileReadErrorTitle,
      summary: scope != null
          ? localizations.storageFileReadSummary(scope)
          : localizations.fileReadErrorTitle,
      lines: ViewModelFormatters.formatFileReadDiagnosticLines(
        report,
        localizations,
      ),
    );
  }
  if (error is WorkspaceException) {
    return FileReadReportViewModel(
      title: localizations.fileReadErrorTitle,
      summary: localizations.localizeWorkspaceError(error),
      lines: const <FileReadDiagnosticLineViewModel>[],
    );
  }
  return FileReadReportViewModel(
    title: localizations.fileReadErrorTitle,
    summary: localizations.errorLoadLocalFileFailed(
      AppLogger.sanitize(error.toString()),
    ),
    lines: const <FileReadDiagnosticLineViewModel>[],
  );
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
String _tierEmptyHint(ShellTier tier, AppLocalizations localizations) =>
    localizations.tierEmptyHint(ViewModelFormatters.toTaskTier(tier));

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
