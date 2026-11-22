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

import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../l10n/tier_localization_extension.dart';
import '../models/location_state.dart';
import '../models/task_board_evaluator.dart';
import '../models/task_item.dart';
import '../models/task_tier.dart';
import '../models/tdf_location.dart';
import '../models/tdf_metadata.dart';
import '../models/webdav_config.dart';
import '../providers/floating_notice_providers.dart';
import '../providers/settings_draft_providers.dart';
import '../providers/shell_providers.dart';
import '../providers/task_schedule_helper.dart';
import 'primitives/ui_banner.dart';
import 'primitives/ui_button.dart';
import 'primitives/ui_pill.dart';
import 'tokens/ui_theme_tokens.dart';

/// Immutable collapsed task badge pairing localized [label], [tone], and outline [icon].
@immutable
class TaskCardBadge {
  /// Creates a [TaskCardBadge].
  const TaskCardBadge({
    required this.label,
    required this.tone,
    required this.icon,
  });

  /// Outline icon rendered inside the pill.
  final IconData icon;

  /// Localized text rendered inside the pill.
  final String label;

  /// Semantic design-system pill tone.
  final UiPillTone tone;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskCardBadge &&
        other.label == label &&
        other.tone == tone &&
        other.icon == icon;
  }

  @override
  int get hashCode => Object.hash(label, tone, icon);
}

/// Stateless mapper converting domain models and enums directly to UI tokens,
/// tones, icons, localized chrome labels, and collapsed task badges (`U-BRAND-003`..`004`, `U-CARD-005`).
class UiDomainMappers {
  /// Prevents instantiation of this stateless helper class.
  const UiDomainMappers._();

  /// Builds collapsed primary badges, up to 3 visible secondary badges, and overflow count for [task] (`U-CARD-005`).
  static ({
    List<TaskCardBadge> primary,
    List<TaskCardBadge> visibleSecondary,
    int overflowCount,
  })
  buildTaskCollapsedBadges({
    required TaskItem task,
    required TaskTier tier,
    required bool isSearchMode,
    required String? activeLabelId,
    required Map<String, TdfLabel> labelsById,
    required Map<String, TdfLocation> locationsById,
    required Map<String, TaskItem> tasksById,
    required WebDavConfig config,
    required DateTime nowUtc,
    required DateTime localNow,
    required LocationFix? activeFix,
    required AppLocalizations localizations,
  }) {
    final isActive = !task.isCompleted;
    final isSomeday = tier == TaskTier.someday;
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

    final primary = <TaskCardBadge>[
      if (isSearchMode)
        TaskCardBadge(
          label: localizations.tierName(tier),
          tone: UiPillTone.soft,
          icon: tierIcon(tier),
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

    final hasConditions =
        task.conditions.isNotEmpty || _hasInheritedConditions(task, labelsById);
    final conditionsSatisfied =
        !hasConditions ||
        TaskBoardEvaluator.areTaskConditionsSatisfied(
          task,
          labelsById,
          locationsById,
          localNow,
          activeLabelId,
          activeFix?.latitude,
          activeFix?.longitude,
        );
    final prereqProgress = _countSatisfiedPrerequisites(task, tasksById);
    final hasUnsatisfiedPrereqs =
        prereqProgress.total > 0 &&
        prereqProgress.satisfied < prereqProgress.total;
    final subtasksCompleted = _countCompletedSubtasks(task);
    final repeatSummary = switch (task.repeatRule) {
      final rule? => TaskScheduleHelper.formatRepeatPhrase(rule, localizations),
      null => null,
    };

    final allSecondary = _buildSecondaryBadges(
      task: task,
      isActive: isActive,
      isAutoPrioritized: isAutoPrioritized,
      isSuspended: isSuspended,
      hasUnsatisfiedPrereqs: hasUnsatisfiedPrereqs,
      satisfiedPrereqCount: prereqProgress.satisfied,
      totalPrereqCount: prereqProgress.total,
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
    return (
      primary: primary,
      visibleSecondary: visibleSecondary,
      overflowCount: overflowCount,
    );
  }

  /// Maps domain [AppThemeMode] to Flutter [ThemeMode].
  static ThemeMode flutterThemeMode(AppThemeMode mode) {
    return switch (mode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };
  }

  /// Formats optional WGS-84 coordinates from [fix] to six decimal places.
  static String formatLocationCoordinates6dp(LocationFix? fix) {
    if (fix == null) {
      return '';
    }
    if ((fix.latitude, fix.longitude) case (
      final latitude?,
      final longitude?,
    )) {
      final normalizedLatitude = latitude == 0 ? 0.0 : latitude;
      final normalizedLongitude = longitude == 0 ? 0.0 : longitude;
      return '${normalizedLatitude.toStringAsFixed(6)}, '
          '${normalizedLongitude.toStringAsFixed(6)}';
    }
    return '';
  }

  /// Maps domain [LocationStatus] to its chrome [UiButtonTone].
  static UiButtonTone locationButtonTone(LocationStatus status) {
    return switch (status) {
      LocationStatus.found => UiButtonTone.accent,
      LocationStatus.disabled ||
      LocationStatus.searching ||
      LocationStatus.unavailable => UiButtonTone.neutral,
    };
  }

  /// Maps domain [LocationStatus] to its outline [IconData].
  static IconData locationIcon(LocationStatus status) {
    return switch (status) {
      LocationStatus.disabled ||
      LocationStatus.unavailable => Icons.location_disabled_rounded,
      LocationStatus.searching => Icons.refresh_rounded,
      LocationStatus.found => Icons.my_location_rounded,
    };
  }

  /// Maps an optional domain [LocationSource] to its localized display label.
  static String locationSourceLabel(
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

  /// Maps domain [LocationStatus] to its localized status description.
  static String locationStatusLabel(
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

  /// Maps [FloatingNoticeTone] to design-system [UiBannerTone].
  static UiBannerTone noticeTone(FloatingNoticeTone tone) {
    return switch (tone) {
      FloatingNoticeTone.neutral ||
      FloatingNoticeTone.accent => UiBannerTone.neutral,
      FloatingNoticeTone.warning => UiBannerTone.warning,
      FloatingNoticeTone.danger => UiBannerTone.danger,
      FloatingNoticeTone.success => UiBannerTone.success,
    };
  }

  /// Resolves the localized place name for [locationState], falling back to [AppLocalizations.locationPlaceUnknown].
  static String resolveLocationPlaceLabel(
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

  /// Maps [SettingsBannerTone] to design-system [UiBannerTone].
  static UiBannerTone settingsBannerTone(SettingsBannerTone tone) {
    return switch (tone) {
      SettingsBannerTone.warning => UiBannerTone.warning,
      SettingsBannerTone.danger => UiBannerTone.danger,
      SettingsBannerTone.success => UiBannerTone.success,
    };
  }

  /// Maps [SyncStatusKind] to its chrome [UiButtonTone].
  static UiButtonTone syncButtonTone(SyncStatusKind status) {
    return switch (status) {
      SyncStatusKind.localOnly ||
      SyncStatusKind.synced ||
      SyncStatusKind.syncing => UiButtonTone.muted,
      SyncStatusKind.conflict => UiButtonTone.warning,
      SyncStatusKind.error => UiButtonTone.danger,
    };
  }

  /// Maps [SyncStatusKind] to its outline [IconData].
  static IconData syncIcon(SyncStatusKind status) {
    return switch (status) {
      SyncStatusKind.localOnly => Icons.folder_outlined,
      SyncStatusKind.synced => Icons.cloud_done_outlined,
      SyncStatusKind.syncing => Icons.refresh_rounded,
      SyncStatusKind.conflict => Icons.warning_amber_rounded,
      SyncStatusKind.error => Icons.cloud_off_outlined,
    };
  }

  /// Maps [SyncStatusKind] to its localized top-bar tooltip and status label.
  static String syncStatusLabel(
    SyncStatusKind status,
    AppLocalizations localizations,
  ) {
    return switch (status) {
      SyncStatusKind.localOnly => localizations.syncStatusLocalOnly,
      SyncStatusKind.synced => localizations.syncStatusSynced,
      SyncStatusKind.syncing => localizations.syncStatusSyncing,
      SyncStatusKind.conflict => localizations.syncStatusConflict,
      SyncStatusKind.error => localizations.syncStatusError,
    };
  }

  /// Maps domain [AppThemePalette] to its WCAG AA [UiThemePreset].
  static UiThemePreset themePreset(AppThemePalette palette) {
    return switch (palette) {
      AppThemePalette.calm => UiThemePresets.calm,
      AppThemePalette.plumUmber => UiThemePresets.plumUmber,
    };
  }

  /// Maps domain [TaskTier] to its localized empty-state hint.
  static String tierEmptyHint(TaskTier tier, AppLocalizations localizations) =>
      localizations.tierEmptyHint(tier);

  /// Maps domain [TaskTier] to its canonical outline icon (`U-BRAND-004`).
  static IconData tierIcon(TaskTier tier) {
    return switch (tier) {
      TaskTier.focus => Icons.bolt_outlined,
      TaskTier.ready => Icons.format_list_numbered_rounded,
      TaskTier.planned => Icons.calendar_today_outlined,
      TaskTier.blocked => Icons.block_outlined,
      TaskTier.someday => Icons.lightbulb_outline_rounded,
      TaskTier.completed => Icons.check_circle_outline_rounded,
    };
  }

  /// Maps domain [TaskTier] to its localized tier subtitle.
  static String tierSubtitle(TaskTier tier, AppLocalizations localizations) {
    return switch (tier) {
      TaskTier.focus => localizations.tierFocusSubtitle,
      TaskTier.ready => localizations.tierReadySubtitle,
      TaskTier.planned => localizations.tierPlannedSubtitle,
      TaskTier.blocked => localizations.tierBlockedSubtitle,
      TaskTier.someday => localizations.tierSomedaySubtitle,
      TaskTier.completed => localizations.tierCompletedSubtitle,
    };
  }
}

/// Builds the primary Due or Overdue badge (`U-CARD-005`).
TaskCardBadge _buildDueBadge({
  required DateTime dueAtUtc,
  required bool isActive,
  required bool isOverdue,
  required bool isWithinLead,
  required WebDavConfig config,
  required AppLocalizations localizations,
}) {
  final formatted = TaskScheduleHelper.formatLocalTimestamp(dueAtUtc, config);
  if (isActive && isOverdue) {
    return TaskCardBadge(
      label: localizations.badgeOverduePrefix(formatted),
      tone: UiPillTone.danger,
      icon: Icons.calendar_today_outlined,
    );
  }
  return TaskCardBadge(
    label: localizations.pillDuePrefix(formatted),
    tone: (isActive && isWithinLead) ? UiPillTone.warning : UiPillTone.neutral,
    icon: Icons.calendar_today_outlined,
  );
}

/// Builds the ordered secondary badges matching `U-CARD-005` strict priority order.
List<TaskCardBadge> _buildSecondaryBadges({
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
  final badges = <TaskCardBadge>[];
  if (isActive && task.isPriority) {
    badges.add(
      TaskCardBadge(
        label: localizations.quickAddPriority,
        tone: UiPillTone.accent,
        icon: Icons.bolt_outlined,
      ),
    );
  } else if (isAutoPrioritized) {
    badges.add(
      TaskCardBadge(
        label: localizations.badgeAutoPriority,
        tone: UiPillTone.warning,
        icon: Icons.bolt_outlined,
      ),
    );
  }
  if (isSuspended) {
    final label = task.isSuspendedForever || task.suspendedAt == null
        ? localizations.badgeSuspendedForever
        : localizations.badgeSuspendedUntil(
            TaskScheduleHelper.formatLocalTimestamp(task.suspendedAt, config),
          );
    badges.add(
      TaskCardBadge(
        label: label,
        tone: UiPillTone.warning,
        icon: Icons.pause_circle_outline_rounded,
      ),
    );
  }
  if (hasUnsatisfiedPrereqs) {
    badges.add(
      TaskCardBadge(
        label: localizations.badgeBlockedByProgress(
          '$satisfiedPrereqCount',
          '$totalPrereqCount',
        ),
        tone: UiPillTone.warning,
        icon: Icons.lock_outline_rounded,
      ),
    );
  }
  if (hasConditions) {
    badges.add(
      TaskCardBadge(
        label: localizations.tooltipIndicatorConditions,
        tone: conditionsSatisfied ? UiPillTone.neutral : UiPillTone.warning,
        icon: Icons.tune_rounded,
      ),
    );
  }
  if (task.subtasks.isNotEmpty) {
    badges.add(
      TaskCardBadge(
        label: localizations.badgeStepsProgress(
          '$subtasksCompleted',
          '${task.subtasks.length}',
        ),
        tone: UiPillTone.neutral,
        icon: task.subtasksAutoFinish
            ? Icons.check_box_outlined
            : Icons.checklist_rounded,
      ),
    );
  }
  if (repeatSummary != null) {
    badges.add(
      TaskCardBadge(
        label: repeatSummary,
        tone: UiPillTone.neutral,
        icon: Icons.repeat_rounded,
      ),
    );
  }
  if (task.note case final note? when note.trim().isNotEmpty) {
    badges.add(
      TaskCardBadge(
        label: localizations.tooltipIndicatorNote,
        tone: UiPillTone.neutral,
        icon: Icons.description_outlined,
      ),
    );
  }
  if (task.links.isNotEmpty) {
    final label = task.links.length == 1
        ? localizations.badgeLinkSingular
        : localizations.taskInfoLinksCount('${task.links.length}');
    badges.add(
      TaskCardBadge(
        label: label,
        tone: UiPillTone.neutral,
        icon: Icons.link_rounded,
      ),
    );
  }
  if (task.history.isNotEmpty) {
    badges.add(
      TaskCardBadge(
        label: localizations.badgeHistoryCount('${task.history.length}'),
        tone: UiPillTone.neutral,
        icon: Icons.history_rounded,
      ),
    );
  }
  return badges;
}

/// Counts completed subtasks on [task].
int _countCompletedSubtasks(TaskItem task) {
  var count = 0;
  for (final step in task.subtasks) {
    if (step.isCompleted) {
      count++;
    }
  }
  return count;
}

/// Counts satisfied and total prerequisite dependencies for [task] against [tasksById].
({int satisfied, int total}) _countSatisfiedPrerequisites(
  TaskItem task,
  Map<String, TaskItem> tasksById,
) {
  var satisfied = 0;
  for (final dependency in task.dependencies) {
    final target = tasksById[dependency.taskId];
    if (target != null && target.completions >= dependency.requiredCompletion) {
      satisfied++;
    }
  }
  return (satisfied: satisfied, total: task.dependencies.length);
}

/// Returns `true` when any label assigned to [task] carries inherited activation conditions.
bool _hasInheritedConditions(TaskItem task, Map<String, TdfLabel> labelsById) {
  for (final labelId in task.labelIds) {
    final label = labelsById[labelId];
    if (label != null && label.conditions.isNotEmpty) {
      return true;
    }
  }
  return false;
}
