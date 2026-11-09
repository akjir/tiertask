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

/// Material 3 task information overlay dialog displaying active task indicators and metadata.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_board.dart';
import '../../models/task_item.dart';
import '../../models/tdf_metadata.dart';
import '../../models/webdav_config.dart';
import '../../providers/config_providers.dart';
import '../../providers/task_providers.dart';
import '../../services/app_logger.dart';
import 'tier_task_subtasks_section.dart';

/// Popup dialog displaying detailed status and indicator information for [task].
class TaskInfoDialog extends ConsumerWidget {
  /// Creates a [TaskInfoDialog].
  const TaskInfoDialog({
    super.key,
    this.initialIndicatorKeyPrefix,
    required this.task,
  });

  /// Optional indicator key prefix that triggered opening this dialog.
  final String? initialIndicatorKeyPrefix;

  /// Task item whose active indicators and details are displayed.
  final TaskItem task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final board =
        ref.watch(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    final configuration =
        ref.watch(webDavConfigProvider).asData?.value ?? const WebDavConfig();
    final nowUtc = ref.watch(clockProvider)().toUtc();
    final sections = _buildSections(
      board: board,
      configuration: configuration,
      localizations: localizations,
      nowUtc: nowUtc,
    );

    return AlertDialog(
      title: _buildDialogTitle(context, localizations),
      content: _buildDialogContent(sections),
      actions: [
        FilledButton(
          key: const ValueKey('task_info_dialog_close_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.actionClose),
        ),
      ],
    );
  }

  /// Builds the prerequisite tasks section when [task] depends on other tasks.
  static _TaskInfoSectionData? _buildBlockedBySection(
    TaskItem task,
    TaskBoard board,
    AppLocalizations localizations,
  ) {
    if (task.dependencies.isEmpty) {
      return null;
    }
    var satisfiedCount = 0;
    final details = <String>[];
    for (final dependency in task.dependencies) {
      final target = board.findTask(dependency.taskId);
      final isSatisfied =
          target == null || target.completions >= dependency.requiredCompletion;
      if (isSatisfied) {
        satisfiedCount++;
      }
      details.add(target?.title ?? dependency.taskId);
    }
    return _TaskInfoSectionData(
      details: details,
      icon: Icons.lock_outline_rounded,
      keyPrefix: 'blocked_by_task_indicator',
      title: localizations.taskBlockedBySectionTitle,
      value: localizations.taskInfoBlockedByProgress(
        satisfiedCount.toString(),
        task.dependencies.length.toString(),
      ),
    );
  }

  /// Builds the activation conditions section when [task] declares conditions.
  static _TaskInfoSectionData? _buildConditionsSection(
    TaskItem task,
    TaskBoard board,
    AppLocalizations localizations,
  ) {
    if (task.conditions.isEmpty) {
      return null;
    }
    final formattedConditions = <String>[
      for (final condition in task.conditions)
        _formatCondition(condition, board, localizations),
    ];
    return _TaskInfoSectionData(
      details: formattedConditions.skip(1).toList(),
      icon: Icons.tune_rounded,
      keyPrefix: 'conditions_task_indicator',
      title: localizations.taskConditionsSectionTitle,
      value: formattedConditions.first,
    );
  }

  /// Builds the scrollable section list inside [TaskInfoDialog].
  Widget _buildDialogContent(List<_TaskInfoSectionData> sections) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _TaskInfoSectionCard(
                data: sections[i],
                isHighlighted:
                    sections[i].keyPrefix == initialIndicatorKeyPrefix,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Builds the dialog header displaying the dialog title and [task] title.
  Widget _buildDialogTitle(
    BuildContext context,
    AppLocalizations localizations,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(localizations.taskInfoDialogTitle),
        const SizedBox(height: 4),
        Text(
          task.title,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// Builds the due deadline section when [task] has a `due` timestamp.
  static _TaskInfoSectionData? _buildDueSection(
    TaskItem task,
    WebDavConfig configuration,
    AppLocalizations localizations,
    DateTime nowUtc,
  ) {
    final dueAt = task.dueAt;
    if (dueAt == null) {
      return null;
    }
    final localDue = configuration.toLocalWallClock(dueAt);
    final timestamp = TaskItem.formatTdfTimestamp(localDue);
    final valueText = dueAt.isAfter(nowUtc)
        ? localizations.taskInfoDueAt(
            timestamp,
            _formatRemainingDuration(dueAt.difference(nowUtc), localizations),
          )
        : localizations.taskInfoDueOverdue(timestamp);
    return _TaskInfoSectionData(
      icon: Icons.event_rounded,
      keyPrefix: 'due_task_badge',
      title: localizations.taskInfoDueLabel,
      value: valueText,
    );
  }

  /// Builds the assigned labels section when [task] references defined labels.
  static _TaskInfoSectionData? _buildLabelsSection(
    TaskItem task,
    TaskBoard board,
    AppLocalizations localizations,
  ) {
    if (task.labelIds.isEmpty) {
      return null;
    }
    final resolvedLabels = resolveTaskLabels(board.sortedLabels, task.labelIds);
    if (resolvedLabels.isEmpty) {
      return null;
    }
    return _TaskInfoSectionData(
      icon: Icons.label_outline_rounded,
      keyPrefix: 'labels_task_indicator',
      labels: resolvedLabels,
      title: localizations.taskLabelsSectionTitle,
      value: '',
    );
  }

  /// Builds the links section when [task] has attached links.
  static _TaskInfoSectionData? _buildLinksSection(
    TaskItem task,
    AppLocalizations localizations,
  ) {
    if (task.links.isEmpty) {
      return null;
    }
    final details = <String>[for (final link in task.links) link.title];
    return _TaskInfoSectionData(
      details: details,
      icon: Icons.link_rounded,
      keyPrefix: 'links_task_indicator',
      title: localizations.linksSectionTitle,
      value: localizations.taskInfoLinksCount(task.links.length.toString()),
    );
  }

  /// Builds the note section when [task] has a non-empty note.
  static _TaskInfoSectionData? _buildNoteSection(
    TaskItem task,
    AppLocalizations localizations,
  ) {
    final note = task.note;
    if (note == null || note.isEmpty) {
      return null;
    }
    return _TaskInfoSectionData(
      icon: Icons.notes_rounded,
      keyPrefix: 'note_task_indicator',
      title: localizations.taskNoteLabel,
      value: note,
    );
  }

  /// Builds the priority section when [task] is marked as priority.
  static _TaskInfoSectionData? _buildPrioritySection(
    TaskItem task,
    AppLocalizations localizations,
  ) {
    if (!task.isPriority) {
      return null;
    }
    return _TaskInfoSectionData(
      icon: Icons.priority_high_rounded,
      keyPrefix: 'priority_task_indicator',
      title: localizations.quickAddPriority,
      value: localizations.taskInfoPriorityValue,
    );
  }

  /// Builds the repeat recurrence section when [task] has a `repeat` rule.
  static _TaskInfoSectionData? _buildRepeatSection(
    TaskItem task,
    AppLocalizations localizations,
  ) {
    final repeatRule = task.repeatRule;
    if (repeatRule == null) {
      return null;
    }
    final unitLabel = _formatRepeatUnit(repeatRule.unit, localizations);
    final details = <String>[
      if (task.completions > 0)
        localizations.taskInfoRepeatCompletions(task.completions.toString()),
    ];
    return _TaskInfoSectionData(
      details: details,
      icon: Icons.repeat_rounded,
      keyPrefix: 'repeat_task_indicator',
      title: localizations.repeatFlagLabel,
      value: localizations.taskInfoRepeatEvery(
        repeatRule.count.toString(),
        unitLabel,
      ),
    );
  }

  /// Collects all active [_TaskInfoSectionData] entries for [task].
  List<_TaskInfoSectionData> _buildSections({
    required TaskBoard board,
    required WebDavConfig configuration,
    required AppLocalizations localizations,
    required DateTime nowUtc,
  }) {
    return <_TaskInfoSectionData>[
      ?_buildPrioritySection(task, localizations),
      ?_buildSuspendedSection(task, configuration, localizations, nowUtc),
      ?_buildDueSection(task, configuration, localizations, nowUtc),
      ?_buildBlockedBySection(task, board, localizations),
      ?_buildConditionsSection(task, board, localizations),
      ?_buildRepeatSection(task, localizations),
      ?_buildLabelsSection(task, board, localizations),
      ?_buildNoteSection(task, localizations),
      ?_buildLinksSection(task, localizations),
      ?_buildSubtasksSection(task, localizations),
    ];
  }

  /// Builds the subtasks progress section when [task] has subtasks.
  static _TaskInfoSectionData? _buildSubtasksSection(
    TaskItem task,
    AppLocalizations localizations,
  ) {
    if (task.subtasks.isEmpty) {
      return null;
    }
    var completedCount = 0;
    for (final subtask in task.subtasks) {
      if (subtask.isCompleted) {
        completedCount++;
      }
    }
    final totalCount = task.subtasks.length;
    final details = <String>[
      if (task.subtasksAutoFinish)
        localizations.taskInfoSubtasksAutoFinishSuffix,
    ];
    return _TaskInfoSectionData(
      details: details,
      icon: task.subtasksAutoFinish
          ? Icons.task_alt_rounded
          : Icons.checklist_rounded,
      keyPrefix: 'subtasks_task_indicator',
      progressValue: completedCount / totalCount,
      title: localizations.subtasksSectionTitle,
      value: localizations.taskInfoSubtasksProgress(
        completedCount.toString(),
        totalCount.toString(),
      ),
    );
  }

  /// Builds the suspension section when [task] is suspended.
  static _TaskInfoSectionData? _buildSuspendedSection(
    TaskItem task,
    WebDavConfig configuration,
    AppLocalizations localizations,
    DateTime nowUtc,
  ) {
    final suspendedAt = task.suspendedAt;
    if (!task.isSuspendedForever && suspendedAt == null) {
      return null;
    }
    if (task.isSuspendedForever ||
        suspendedAt == null ||
        suspendedAt == TaskItem.defaultSuspendedAt) {
      return _TaskInfoSectionData(
        icon: Icons.pause_circle_outline_rounded,
        keyPrefix: 'suspended_task_indicator',
        title: localizations.taskSuspendedLabel,
        value: localizations.taskInfoSuspendedForever,
      );
    }
    final localSuspended = configuration.toLocalWallClock(suspendedAt);
    final timestamp = TaskItem.formatTdfTimestamp(localSuspended);
    final valueText = suspendedAt.isAfter(nowUtc)
        ? localizations.taskInfoSuspendedUntil(
            timestamp,
            _formatRemainingDuration(
              suspendedAt.difference(nowUtc),
              localizations,
            ),
          )
        : localizations.taskInfoSuspendedElapsed(timestamp);
    return _TaskInfoSectionData(
      icon: Icons.pause_circle_outline_rounded,
      keyPrefix: 'suspended_task_indicator',
      title: localizations.taskSuspendedLabel,
      value: valueText,
    );
  }

  /// Formats a single [TaskCondition] into a localized summary line.
  static String _formatCondition(
    TaskCondition condition,
    TaskBoard board,
    AppLocalizations localizations,
  ) {
    return switch (condition) {
      DayTaskCondition() => _formatDayCondition(condition, localizations),
      GlobalResetTaskCondition() => localizations.conditionGlobalAnyLabel,
      GroupResetTaskCondition() => _formatGroupResetCondition(
        condition.targetGroup,
        localizations,
      ),
      LocationTaskCondition() => _formatLocationCondition(condition, board),
      TimeWindowTaskCondition() =>
        '${condition.startToken} - ${condition.endToken}',
    };
  }

  /// Formats a [DayTaskCondition] as a comma-separated list of localized weekday names.
  static String _formatDayCondition(
    DayTaskCondition condition,
    AppLocalizations localizations,
  ) {
    final names = <String>[
      for (final weekday in condition.weekdays)
        _formatWeekday(weekday, localizations),
    ];
    return names.join(', ');
  }

  /// Formats a [ConditionGroup] reset rule into its localized label.
  static String _formatGroupResetCondition(
    ConditionGroup group,
    AppLocalizations localizations,
  ) {
    return switch (group) {
      ConditionGroup.day => localizations.conditionDayAnyLabel,
      ConditionGroup.time => localizations.conditionTimeAnyLabel,
      ConditionGroup.location => localizations.conditionLocationAnyLabel,
    };
  }

  /// Formats a [LocationTaskCondition] by resolving referenced location names from [board].
  static String _formatLocationCondition(
    LocationTaskCondition condition,
    TaskBoard board,
  ) {
    if (condition.locationIds.isEmpty) {
      return '${condition.latitudeText}, ${condition.longitudeText} (${condition.radiusText}m)';
    }
    final names = <String>[
      for (final locationId in condition.locationIds)
        board.findLocation(locationId)?.name ?? locationId,
    ];
    return names.join(', ');
  }

  /// Formats a positive [difference] into days/hours, hours/minutes, or minutes remaining.
  static String _formatRemainingDuration(
    Duration difference,
    AppLocalizations localizations,
  ) {
    if (difference.inDays >= 1) {
      final remainingHours = difference.inHours % 24;
      return localizations.taskInfoDurationDaysHours(
        difference.inDays.toString(),
        remainingHours.toString(),
      );
    }
    if (difference.inHours >= 1) {
      final remainingMinutes = difference.inMinutes % 60;
      return localizations.taskInfoDurationHoursMinutes(
        difference.inHours.toString(),
        remainingMinutes.toString(),
      );
    }
    final minutes = difference.inMinutes < 1 ? 1 : difference.inMinutes;
    return localizations.taskInfoDurationMinutes(minutes.toString());
  }

  /// Resolves the localized label for [unit].
  static String _formatRepeatUnit(
    RepeatUnit unit,
    AppLocalizations localizations,
  ) {
    return switch (unit) {
      RepeatUnit.days => localizations.repeatUnitDays,
      RepeatUnit.weeks => localizations.repeatUnitWeeks,
      RepeatUnit.months => localizations.repeatUnitMonths,
    };
  }

  /// Resolves the localized short weekday name for an ISO-8601 [weekday] (`1..7`).
  static String _formatWeekday(int weekday, AppLocalizations localizations) {
    return switch (weekday) {
      DateTime.monday => localizations.weekdayMon,
      DateTime.tuesday => localizations.weekdayTue,
      DateTime.wednesday => localizations.weekdayWed,
      DateTime.thursday => localizations.weekdayThu,
      DateTime.friday => localizations.weekdayFri,
      DateTime.saturday => localizations.weekdaySat,
      _ => localizations.weekdaySun,
    };
  }
}

/// Card rendering a single active indicator section inside [TaskInfoDialog].
class _TaskInfoSectionCard extends StatelessWidget {
  /// Creates a [_TaskInfoSectionCard].
  const _TaskInfoSectionCard({required this.data, required this.isHighlighted});

  /// Section data to display.
  final _TaskInfoSectionData data;

  /// Whether this section matches the indicator that opened the dialog.
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = isHighlighted
        ? colorScheme.primary.withValues(alpha: 0.5)
        : colorScheme.outlineVariant.withValues(alpha: 0.4);
    final backgroundColor = isHighlighted
        ? colorScheme.primaryContainer.withValues(alpha: 0.25)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35);

    return Container(
      key: ValueKey('task_info_section_${data.keyPrefix}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeaderRow(context),
          if (data.progressValue case final progress?) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress, minHeight: 6),
            ),
          ],
          if (data.labels.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildLabelChips(context),
          ],
          if (data.details.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildDetailsList(context),
          ],
        ],
      ),
    );
  }

  /// Builds the secondary detail lines beneath the primary section value.
  Widget _buildDetailsList(BuildContext context) {
    final detailStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final detail in data.details)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(detail, style: detailStyle),
          ),
      ],
    );
  }

  /// Builds the section header row with leading icon, title, and primary value text.
  Widget _buildHeaderRow(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(data.icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                data.title,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (data.value.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(data.value, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Builds colored label chips for the assigned labels section.
  Widget _buildLabelChips(BuildContext context) {
    final fallbackColor = Theme.of(context).colorScheme.primary;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final label in data.labels)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _resolveLabelColor(label.color, fallbackColor),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(label.name, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
      ],
    );
  }

  /// Resolves the `#RRGGBB` color of [rawHex] or returns [fallback].
  static Color _resolveLabelColor(String? rawHex, Color fallback) {
    final parsed = TdfColor.tryParseArgb(rawHex);
    return parsed != null ? Color(parsed) : fallback;
  }
}

/// Immutable view model for a single section in [TaskInfoDialog].
class _TaskInfoSectionData {
  /// Creates a [_TaskInfoSectionData].
  const _TaskInfoSectionData({
    this.details = const <String>[],
    required this.icon,
    required this.keyPrefix,
    this.labels = const <TdfLabel>[],
    this.progressValue,
    required this.title,
    required this.value,
  });

  /// Additional detail lines rendered beneath [value].
  final List<String> details;

  /// Leading icon representing this indicator category.
  final IconData icon;

  /// Indicator key prefix (`<prefix>_task_indicator` or `due_task_badge`).
  final String keyPrefix;

  /// Resolved labels when rendering the labels section.
  final List<TdfLabel> labels;

  /// Optional progress fraction (`0.0` to `1.0`) for completion bars.
  final double? progressValue;

  /// Localized section heading.
  final String title;

  /// Primary localized status value.
  final String value;
}

/// Opens [TaskInfoDialog] as a modal overlay for [task].
Future<void> showTaskInfoDialog(
  BuildContext context, {
  String? initialIndicatorKeyPrefix,
  required TaskItem task,
}) {
  AppLogger.info(
    LogTag.ui,
    'openTaskInfoDialog id=${task.id} indicator=${initialIndicatorKeyPrefix ?? "summary"}',
  );
  return showDialog<void>(
    context: context,
    builder: (_) => TaskInfoDialog(
      initialIndicatorKeyPrefix: initialIndicatorKeyPrefix,
      task: task,
    ),
  );
}
