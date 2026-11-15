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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_board.dart';
import '../../models/task_item.dart';
import '../../models/tdf_metadata.dart';
import '../../models/webdav_config.dart';
import '../../providers/config_providers.dart';
import '../../providers/task_providers.dart';
import '../../services/app_logger.dart';
import 'label_hub_dialog.dart';
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
    ref.watch(boundaryTickProvider);
    final localizations = AppLocalizations.of(context);
    final board =
        ref.watch(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    final currentTask = board.findTask(task.id) ?? task;
    final configuration =
        ref.watch(webDavConfigProvider).asData?.value ?? const WebDavConfig();
    final nowUtc = ref.watch(clockProvider)().toUtc();
    final sections = _buildSections(
      board: board,
      configuration: configuration,
      currentTask: currentTask,
      localizations: localizations,
      nowUtc: nowUtc,
    );

    return AlertDialog(
      title: _buildDialogTitle(context, localizations, currentTask),
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

  /// Builds the prerequisite tasks section when [task] is actively blocked by prerequisites on [board].
  static _TaskInfoSectionData? _buildBlockedBySection(
    TaskItem task,
    TaskBoard board,
    AppLocalizations localizations,
  ) {
    if (task.dependencies.isEmpty) {
      return null;
    }
    var satisfiedCount = 0;
    var hasUnsatisfied = false;
    final details = <String>[];
    for (final dependency in task.dependencies) {
      if (board.deletedBlock.findTaskRecord(dependency.taskId) != null) {
        continue;
      }
      final target = board.findTask(dependency.taskId);
      final isSatisfied =
          target == null || target.completions >= dependency.requiredCompletion;
      if (isSatisfied) {
        satisfiedCount++;
      } else {
        hasUnsatisfied = true;
      }
      details.add(target?.title ?? dependency.taskId);
    }
    if (!hasUnsatisfied) {
      return null;
    }
    return _TaskInfoSectionData(
      details: details,
      icon: Icons.lock_outline_rounded,
      keyPrefix: 'blocked_by_task_indicator',
      title: localizations.taskBlockedBySectionTitle,
      value: localizations.taskInfoBlockedByProgress(
        satisfiedCount.toString(),
        details.length.toString(),
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
        formatConditionSummary(condition, board.locations, localizations),
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

  /// Builds the dialog header displaying the dialog title and [currentTask] title.
  static Widget _buildDialogTitle(
    BuildContext context,
    AppLocalizations localizations,
    TaskItem currentTask,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(localizations.taskInfoDialogTitle),
        const SizedBox(height: 4),
        Text(
          currentTask.title,
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
    final normalizedNow = TaskItem.normalizeTimestamp(nowUtc);
    final localDue = configuration.toLocalWallClock(dueAt);
    final timestamp = TaskItem.formatTdfTimestamp(localDue);
    final valueText = dueAt.isAfter(normalizedNow)
        ? localizations.taskInfoDueAt(
            timestamp,
            _formatRemainingDuration(
              dueAt.difference(normalizedNow),
              localizations,
            ),
          )
        : localizations.taskInfoDueOverdue(timestamp);
    return _TaskInfoSectionData(
      details: _buildDueStatusDetails(
        task,
        configuration,
        localizations,
        normalizedNow,
      ),
      icon: Icons.event_rounded,
      keyPrefix: 'due_task_badge',
      noteBody: task.dueNote,
      noteKey: const ValueKey('task_info_due_note'),
      title: localizations.taskInfoDueLabel,
      value: valueText,
    );
  }

  /// Resolves the exhaustive deadline auto-priority status detail lines for [task].
  static List<String> _buildDueStatusDetails(
    TaskItem task,
    WebDavConfig configuration,
    AppLocalizations localizations,
    DateTime normalizedNow,
  ) {
    if (task.isCompleted || task.completedAt != null) {
      return const <String>[];
    }
    if (task.isDuePassive) {
      return <String>[localizations.taskInfoDuePassiveHint];
    }
    final leadWindow = configuration.dueLeadWindow;
    if (leadWindow == DueLeadWindow.off) {
      return <String>[localizations.taskInfoDueLeadWindowOffHint];
    }
    if (task.isWithinDueLeadWindow(normalizedNow, leadWindow.duration)) {
      return <String>[localizations.taskInfoDueAutoPromotedActive];
    }
    return switch (leadWindow) {
      DueLeadWindow.off => <String>[localizations.taskInfoDueLeadWindowOffHint],
      DueLeadWindow.atDue => <String>[
        localizations.taskInfoDueAutoPromoteAtDue,
      ],
      DueLeadWindow.hours12 => <String>[
        localizations.taskInfoDueAutoPromoteScheduled(
          localizations.dueLeadWindowShort12Hours,
        ),
      ],
      DueLeadWindow.hours24 => <String>[
        localizations.taskInfoDueAutoPromoteScheduled(
          localizations.dueLeadWindowShort24Hours,
        ),
      ],
      DueLeadWindow.hours48 => <String>[
        localizations.taskInfoDueAutoPromoteScheduled(
          localizations.dueLeadWindowShort48Hours,
        ),
      ],
      DueLeadWindow.days7 => <String>[
        localizations.taskInfoDueAutoPromoteScheduled(
          localizations.dueLeadWindowShort7Days,
        ),
      ],
    };
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
      if (repeatRule.leadDays > 0 && task.dueAt != null)
        localizations.taskInfoRepeatLeadDays(repeatRule.leadDays.toString()),
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

  /// Collects all active [_TaskInfoSectionData] entries for [currentTask].
  static List<_TaskInfoSectionData> _buildSections({
    required TaskBoard board,
    required WebDavConfig configuration,
    required TaskItem currentTask,
    required AppLocalizations localizations,
    required DateTime nowUtc,
  }) {
    return <_TaskInfoSectionData>[
      ?_buildPrioritySection(currentTask, localizations),
      ?_buildSuspendedSection(
        currentTask,
        configuration,
        localizations,
        nowUtc,
      ),
      ?_buildDueSection(currentTask, configuration, localizations, nowUtc),
      ?_buildBlockedBySection(currentTask, board, localizations),
      ?_buildConditionsSection(currentTask, board, localizations),
      ?_buildRepeatSection(currentTask, localizations),
      ?_buildLabelsSection(currentTask, board, localizations),
      ?_buildNoteSection(currentTask, localizations),
      ?_buildLinksSection(currentTask, localizations),
      ?_buildSubtasksSection(currentTask, localizations),
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

  /// Builds the suspension section when [task] has an active deferral at [nowUtc].
  static _TaskInfoSectionData? _buildSuspendedSection(
    TaskItem task,
    WebDavConfig configuration,
    AppLocalizations localizations,
    DateTime nowUtc,
  ) {
    if (!task.hasActiveSuspendedAt(nowUtc)) {
      return null;
    }
    final suspendedAt = task.suspendedAt;
    if (task.isSuspendedForever ||
        suspendedAt == null ||
        suspendedAt == TaskItem.defaultSuspendedAt) {
      return _TaskInfoSectionData(
        icon: Icons.pause_circle_outline_rounded,
        keyPrefix: 'suspended_task_indicator',
        noteBody: task.suspendedNote,
        noteKey: const ValueKey('task_info_suspended_note'),
        title: localizations.taskSuspendedLabel,
        value: localizations.taskInfoSuspendedForever,
      );
    }
    final localSuspended = configuration.toLocalWallClock(suspendedAt);
    final timestamp = TaskItem.formatTdfTimestamp(localSuspended);
    final valueText = localizations.taskInfoSuspendedUntil(
      timestamp,
      _formatRemainingDuration(
        suspendedAt.difference(TaskItem.normalizeTimestamp(nowUtc)),
        localizations,
      ),
    );
    return _TaskInfoSectionData(
      icon: Icons.pause_circle_outline_rounded,
      keyPrefix: 'suspended_task_indicator',
      noteBody: task.suspendedNote,
      noteKey: const ValueKey('task_info_suspended_note'),
      title: localizations.taskSuspendedLabel,
      value: valueText,
    );
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
}

/// Interactive colored label [ActionChip] wrap inside [TaskInfoDialog].
class _TaskInfoLabelChips extends StatelessWidget {
  /// Creates [_TaskInfoLabelChips].
  const _TaskInfoLabelChips({required this.labels});

  /// Assigned labels to render.
  final List<TdfLabel> labels;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final fallbackColor = Theme.of(context).colorScheme.primary;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final label in labels)
          ActionChip(
            key: ValueKey('task_info_label_chip_${label.id}'),
            tooltip: localizations.tooltipOpenLabelHub,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            avatar: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _resolveLabelColor(label.color, fallbackColor),
                shape: BoxShape.circle,
              ),
            ),
            label: Text(label.name),
            onPressed: () => showLabelHubDialog(context, labelId: label.id),
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

/// Multi-line selectable scheduling note block rendered inside [_TaskInfoSectionCard].
class _TaskInfoNoteBody extends StatelessWidget {
  /// Creates a [_TaskInfoNoteBody].
  const _TaskInfoNoteBody({required this.note, this.noteKey});

  /// Multi-line scheduling note text.
  final String note;

  /// Optional deterministic widget key for testing.
  final Key? noteKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SelectableText(
        note,
        key: noteKey,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
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
    return Container(
      key: ValueKey('task_info_section_${data.keyPrefix}'),
      padding: const EdgeInsets.all(12),
      decoration: _buildDecoration(Theme.of(context).colorScheme),
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
            _TaskInfoLabelChips(labels: data.labels),
          ],
          if (data.details.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildDetailsList(context),
          ],
          if (data.noteBody case final note? when note.isNotEmpty)
            _TaskInfoNoteBody(note: note, noteKey: data.noteKey),
        ],
      ),
    );
  }

  /// Builds the highlighted or neutral card decoration for [colorScheme].
  BoxDecoration _buildDecoration(ColorScheme colorScheme) {
    final borderColor = isHighlighted
        ? colorScheme.primary.withValues(alpha: 0.5)
        : colorScheme.outlineVariant.withValues(alpha: 0.4);
    final backgroundColor = isHighlighted
        ? colorScheme.primaryContainer.withValues(alpha: 0.25)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35);
    return BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: borderColor),
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
}

/// Immutable view model for a single section in [TaskInfoDialog].
class _TaskInfoSectionData {
  /// Creates a [_TaskInfoSectionData].
  const _TaskInfoSectionData({
    this.details = const <String>[],
    required this.icon,
    required this.keyPrefix,
    this.labels = const <TdfLabel>[],
    this.noteBody,
    this.noteKey,
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

  /// Optional multi-line scheduling note rendered below [details].
  final String? noteBody;

  /// Optional widget key attached to the rendered [SelectableText] note body.
  final Key? noteKey;

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
