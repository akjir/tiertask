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

/// Expandable task ID, note, repeatable links, and interactive subtask checklist section for task pills.
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import '../../models/tdf_metadata.dart';
import '../../repositories/link_launcher_repository.dart';
import '../../services/app_logger.dart';

/// Maximum number of individual status indicator icons rendered on a task pill before collapsing into a summary icon.
const int maxVisibleTaskIndicators = 3;

/// Animation duration for expanding and collapsing task subtasks, notes, and links.
const Duration subtaskExpandDuration = Duration(milliseconds: 220);

/// Animated container that glides the task ID, note, links, and subtask checklist downward or upward driven by [controller].
class AnimatedSubtasksSection extends StatelessWidget {
  /// Creates an [AnimatedSubtasksSection].
  const AnimatedSubtasksSection({
    super.key,
    required this.autoFinishingStepIndex,
    required this.controller,
    required this.isExpanded,
    required this.task,
    required this.onOpenLink,
    required this.onToggleSubtask,
  });

  /// Zero-based step index currently triggering Stage 1 auto-finish collapse, if any.
  final int? autoFinishingStepIndex;

  /// Animation controller driving the expansion progress between `0.0` and `1.0`.
  final Animation<double> controller;

  /// Whether the task ID, note, link, and subtask list is currently expanded.
  final bool isExpanded;

  /// Callback invoked when a link row is tapped.
  final ValueChanged<String> onOpenLink;

  /// Callback invoked with the zero-based step index when a subtask row is tapped, or `null` when locked.
  final ValueChanged<int>? onToggleSubtask;

  /// Parent task whose ID, note, links, and subtasks are displayed.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final detailsChild = isExpanded || controller.value > 0.0
        ? _SubtaskStepsColumn(
            autoFinishingStepIndex: autoFinishingStepIndex,
            task: task,
            onOpenLink: onOpenLink,
            onToggleSubtask: onToggleSubtask,
          )
        : null;
    return AnimatedBuilder(
      animation: controller,
      child: detailsChild,
      builder: (context, child) {
        final rawValue = controller.value;
        if (!isExpanded && rawValue <= 0.0) {
          return const SizedBox.shrink();
        }
        final progress = Curves.easeInOutCubic.transform(rawValue);
        return ClipRect(
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: progress,
            child:
                child ??
                _SubtaskStepsColumn(
                  autoFinishingStepIndex: autoFinishingStepIndex,
                  task: task,
                  onOpenLink: onOpenLink,
                  onToggleSubtask: onToggleSubtask,
                ),
          ),
        );
      },
    );
  }
}

/// Column of task ID, note, interactive link, and subtask rows rendered below the main task pill header.
class _SubtaskStepsColumn extends StatelessWidget {
  /// Creates a [_SubtaskStepsColumn].
  const _SubtaskStepsColumn({
    required this.autoFinishingStepIndex,
    required this.task,
    required this.onOpenLink,
    required this.onToggleSubtask,
  });

  /// Zero-based step index currently triggering Stage 1 auto-finish collapse, if any.
  final int? autoFinishingStepIndex;

  /// Callback invoked when a link row is tapped.
  final ValueChanged<String> onOpenLink;

  /// Callback invoked with the zero-based step index when a subtask row is tapped, or `null` when locked.
  final ValueChanged<int>? onToggleSubtask;

  /// Parent task whose details are rendered.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final taskId = task.id;
    final activeNote = task.note;
    final links = task.links;
    final subtasks = resolveDisplayedSubtasks(
      task.subtasks,
      autoFinishingStepIndex: autoFinishingStepIndex,
    );
    final toggleCallback = onToggleSubtask;
    return _SubtaskStepsDividerBox(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TierTaskIdRow(taskId: taskId),
          if (activeNote != null && activeNote.isNotEmpty)
            _TierNoteRow(
              copyButtonKey: ValueKey('copy_task_note_$taskId'),
              note: activeNote,
              noteKey: ValueKey('task_note_$taskId'),
            ),
          for (var i = 0; i < links.length; i++)
            _TierLinkRow(
              linkKey: ValueKey('task_link_${taskId}_$i'),
              link: links[i],
              onTap: () => onOpenLink(links[i].uri),
            ),
          for (var i = 0; i < subtasks.length; i++)
            _TierSubtaskStepRow(
              stepKey: ValueKey('subtask_step_${taskId}_$i'),
              subtask: subtasks[i],
              onTap: toggleCallback != null ? () => toggleCallback(i) : null,
            ),
        ],
      ),
    );
  }
}

/// Top-bordered container with vertical padding wrapping [_SubtaskStepsColumn] rows.
class _SubtaskStepsDividerBox extends StatelessWidget {
  /// Creates a [_SubtaskStepsDividerBox].
  const _SubtaskStepsDividerBox({required this.child});

  /// Expandable details column rendered beneath the top divider border.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(context).dividerColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: dividerColor, width: 1)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: child,
      ),
    );
  }
}

/// Interactive row representing a single [TaskLink] inside [_SubtaskStepsColumn].
class _TierLinkRow extends StatelessWidget {
  /// Creates a [_TierLinkRow].
  const _TierLinkRow({
    required this.link,
    required this.linkKey,
    required this.onTap,
  });

  /// Link item to render.
  final TaskLink link;

  /// Deterministic widget key for the link row.
  final Key linkKey;

  /// Callback invoked when the link row is tapped to open its URI.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: link.uri,
      child: InkWell(
        key: linkKey,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 20, 8),
          child: _TierLinkRowContent(title: link.title),
        ),
      ),
    );
  }
}

/// Inner icon and title layout for [_TierLinkRow].
class _TierLinkRowContent extends StatelessWidget {
  /// Creates a [_TierLinkRowContent].
  const _TierLinkRowContent({required this.title});

  /// Display title of the task link.
  final String title;

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Icon(Icons.open_in_new_rounded, size: 18, color: primaryColor),
        const SizedBox(width: 18),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: primaryColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// Row displaying the task [note] with a leading note icon and trailing copy button inside [_SubtaskStepsColumn].
class _TierNoteRow extends StatelessWidget {
  /// Creates a [_TierNoteRow].
  const _TierNoteRow({
    required this.copyButtonKey,
    required this.note,
    required this.noteKey,
  });

  /// Deterministic widget key for the trailing copy button.
  final Key copyButtonKey;

  /// Note text to render and copy.
  final String note;

  /// Deterministic widget key for the note row.
  final Key noteKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: noteKey,
      padding: const EdgeInsets.fromLTRB(22, 4, 12, 4),
      child: _TierNoteRowContent(copyButtonKey: copyButtonKey, note: note),
    );
  }
}

/// Inner icon, text, and copy action layout for [_TierNoteRow].
class _TierNoteRowContent extends StatelessWidget {
  /// Creates a [_TierNoteRowContent].
  const _TierNoteRowContent({required this.copyButtonKey, required this.note});

  /// Deterministic widget key for the trailing copy button.
  final Key copyButtonKey;

  /// Note text to display and copy.
  final String note;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(Icons.notes_rounded, size: 18, color: mutedColor),
        const SizedBox(width: 18),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              note,
              style: TextStyle(
                color: mutedColor,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: copyButtonKey,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: localizations.tooltipCopyNote,
          icon: Icon(Icons.copy_rounded, size: 18, color: mutedColor),
          onPressed: () => copyTaskNoteToClipboard(context, note),
        ),
      ],
    );
  }
}

/// Compact circular check indicator rendered at the leading edge of [_TierSubtaskStepRow].
class _TierSubtaskCheckbox extends StatelessWidget {
  /// Creates a [_TierSubtaskCheckbox].
  const _TierSubtaskCheckbox({required this.isCompleted});

  /// Whether the subtask step is completed.
  final bool isCompleted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = isCompleted
        ? colorScheme.primaryContainer
        : colorScheme.onSurfaceVariant;
    final fillColor = isCompleted
        ? colorScheme.primaryContainer
        : Colors.transparent;
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fillColor,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1.8),
      ),
      child: isCompleted
          ? Icon(
              Icons.check_rounded,
              size: 13,
              color: colorScheme.onPrimaryContainer,
            )
          : null,
    );
  }
}

/// Interactive row representing a single subtask step inside [_SubtaskStepsColumn].
class _TierSubtaskStepRow extends StatelessWidget {
  /// Creates a [_TierSubtaskStepRow].
  const _TierSubtaskStepRow({
    required this.stepKey,
    required this.subtask,
    required this.onTap,
  });

  /// Callback invoked when the subtask row is tapped to check or uncheck it, or `null` when locked.
  final VoidCallback? onTap;

  /// Deterministic widget key for the subtask row.
  final Key stepKey;

  /// Subtask step item to render.
  final SubtaskItem subtask;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: stepKey,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 20, 8),
        child: Row(
          children: [
            _TierSubtaskCheckbox(isCompleted: subtask.isCompleted),
            const SizedBox(width: 16),
            Expanded(child: _TierSubtaskStepTitle(subtask: subtask)),
          ],
        ),
      ),
    );
  }
}

/// Styled subtask step title inside [_TierSubtaskStepRow] with line-through decoration when completed.
class _TierSubtaskStepTitle extends StatelessWidget {
  /// Creates a [_TierSubtaskStepTitle].
  const _TierSubtaskStepTitle({required this.subtask});

  /// Subtask step whose title and completion state are rendered.
  final SubtaskItem subtask;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCompleted = subtask.isCompleted;
    return Text(
      subtask.title,
      style: TextStyle(
        color: isCompleted
            ? colorScheme.onSurfaceVariant
            : colorScheme.onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        decoration: isCompleted ? TextDecoration.lineThrough : null,
      ),
    );
  }
}

/// Subtle header row displaying the task [taskId] and a trailing copy button at the top of [_SubtaskStepsColumn].
class _TierTaskIdRow extends StatelessWidget {
  /// Creates a [_TierTaskIdRow].
  const _TierTaskIdRow({required this.taskId});

  /// Task identifier to render and copy.
  final String taskId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey('task_id_$taskId'),
      padding: const EdgeInsets.fromLTRB(22, 2, 12, 2),
      child: _TierTaskIdRowContent(
        copyButtonKey: ValueKey('copy_task_id_$taskId'),
        taskId: taskId,
      ),
    );
  }
}

/// Inner tag icon, subtle task ID label, and copy action layout for [_TierTaskIdRow].
class _TierTaskIdRowContent extends StatelessWidget {
  /// Creates a [_TierTaskIdRowContent].
  const _TierTaskIdRowContent({
    required this.copyButtonKey,
    required this.taskId,
  });

  /// Deterministic widget key for the trailing copy button.
  final Key copyButtonKey;

  /// Task identifier to display and copy.
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final subtleColor = Theme.of(context).colorScheme.onSurfaceVariant
        .withValues(alpha: 0.6);
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Icon(Icons.tag_rounded, size: 14, color: subtleColor),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Text(
            localizations.taskIdRowLabel(taskId),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: subtleColor,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.2,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: copyButtonKey,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
          tooltip: localizations.tooltipCopyTaskId,
          icon: Icon(Icons.copy_rounded, size: 15, color: subtleColor),
          onPressed: () => copyTaskIdToClipboard(context, taskId),
        ),
      ],
    );
  }
}

/// Logs a UI debug trace and forwards or reverses [controller] when [isExpanded] changes for [taskId].
void animateSubtaskSectionToggle(
  AnimationController controller, {
  required bool isExpanded,
  required String taskId,
}) {
  AppLogger.debug(
    LogTag.ui,
    'Toggled task details task=$taskId expanded=$isExpanded',
  );
  if (isExpanded) {
    controller.forward();
  } else {
    controller.reverse();
  }
}

/// Computes total exit duration and Stage 1 subgroup collapse fraction for [subtaskProgress] and [exitDuration].
({double stage1Fraction, Duration totalDuration})
computeSubtaskExitStageTiming({
  required Duration exitDuration,
  required double subtaskProgress,
}) {
  final stage1Microseconds =
      (subtaskExpandDuration.inMicroseconds * subtaskProgress).round();
  final totalMicroseconds = stage1Microseconds + exitDuration.inMicroseconds;
  return (
    stage1Fraction: stage1Microseconds > 0
        ? stage1Microseconds / totalMicroseconds
        : 0.0,
    totalDuration: Duration(microseconds: totalMicroseconds),
  );
}

/// Copies [taskId] to the system clipboard and displays a localized confirmation [SnackBar] on [context].
Future<void> copyTaskIdToClipboard(BuildContext context, String taskId) async {
  if (AppLogger.shouldLog(LogLevel.info)) {
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'task.id.copied',
      fields: {'task': taskId},
    );
  }
  final localizations = AppLocalizations.of(context);
  await _copyTextToClipboardWithSnackBar(
    context,
    snackBarMessage: localizations.taskIdCopiedSnackBar,
    text: taskId,
  );
}

/// Copies [note] to the system clipboard and displays a localized confirmation [SnackBar] on [context].
Future<void> copyTaskNoteToClipboard(BuildContext context, String note) async {
  if (AppLogger.shouldLog(LogLevel.info)) {
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'task.note.copied',
      fields: {'length': note.length},
    );
  }
  final localizations = AppLocalizations.of(context);
  await _copyTextToClipboardWithSnackBar(
    context,
    snackBarMessage: localizations.noteCopiedSnackBar,
    text: note,
  );
}

/// Opens [uri] via [repository] and shows a localized failure [SnackBar] on [context] if launching fails.
Future<void> openTaskResourceLink(
  BuildContext context,
  LinkLauncherRepository repository,
  String uri,
) async {
  try {
    await repository.openLink(uri);
  } on LinkLaunchException {
    if (!context.mounted) {
      return;
    }
    final localizations = AppLocalizations.of(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(localizations.errorOpenLinkFailed)));
  }
}

/// Returns [subtasks] with [autoFinishingStepIndex] marked completed during Stage 1 auto-finish collapse.
List<SubtaskItem> resolveDisplayedSubtasks(
  List<SubtaskItem> subtasks, {
  int? autoFinishingStepIndex,
}) {
  if (autoFinishingStepIndex == null) {
    return subtasks;
  }
  return [
    for (var i = 0; i < subtasks.length; i++)
      i == autoFinishingStepIndex
          ? subtasks[i].copyWith(isCompleted: true)
          : subtasks[i],
  ];
}

/// Resolves all ordered passive status indicator specifications for [task].
List<({IconData icon, String keyPrefix, String tooltip})>
resolveTaskIndicatorSpecs(TaskItem task, AppLocalizations localizations) {
  final note = task.note;
  return [
    if (task.isPriority)
      (
        icon: Icons.bolt_rounded,
        keyPrefix: 'priority_task_indicator',
        tooltip: localizations.tooltipIndicatorPriority,
      ),
    if (task.isSuspendedForever || task.suspendedAt != null)
      (
        icon: Icons.pause_circle_outline_rounded,
        keyPrefix: 'suspended_task_indicator',
        tooltip: localizations.tooltipIndicatorSuspended,
      ),
    if (task.dependencies.isNotEmpty)
      (
        icon: Icons.lock_outline_rounded,
        keyPrefix: 'blocked_by_task_indicator',
        tooltip: localizations.tooltipIndicatorBlockedBy,
      ),
    if (task.conditions.isNotEmpty)
      (
        icon: Icons.rule_rounded,
        keyPrefix: 'conditions_task_indicator',
        tooltip: localizations.tooltipIndicatorConditions,
      ),
    if (task.repeatRule != null)
      (
        icon: Icons.repeat_rounded,
        keyPrefix: 'repeat_task_indicator',
        tooltip: localizations.tooltipIndicatorRepeat,
      ),
    if (note != null && note.isNotEmpty)
      (
        icon: Icons.notes_rounded,
        keyPrefix: 'note_task_indicator',
        tooltip: localizations.tooltipIndicatorNote,
      ),
    if (task.links.isNotEmpty)
      (
        icon: Icons.link_rounded,
        keyPrefix: 'links_task_indicator',
        tooltip: localizations.tooltipIndicatorLinks,
      ),
    if (task.subtasks.isNotEmpty)
      (
        icon: task.subtasksAutoFinish
            ? Icons.fact_check_outlined
            : Icons.checklist_rounded,
        keyPrefix: 'subtasks_task_indicator',
        tooltip: task.subtasksAutoFinish
            ? localizations.tooltipIndicatorSubtasksAutoFinish
            : localizations.tooltipIndicatorSubtasks,
      ),
  ];
}

/// Resolves the ordered [TdfLabel] definitions matching [labelIds] from [sortedLabels].
List<TdfLabel> resolveTaskLabels(
  List<TdfLabel> sortedLabels,
  List<String> labelIds,
) {
  if (labelIds.isEmpty || sortedLabels.isEmpty) {
    return const <TdfLabel>[];
  }
  return <TdfLabel>[
    for (final label in sortedLabels)
      if (labelIds.contains(label.id)) label,
  ];
}

/// Synchronizes [subtaskController] with Stage 1 collapse progress during an exit animation.
void syncSubtaskCollapseProgress(
  AnimationController subtaskController, {
  required double exitProgress,
  required double initialSubtaskValue,
  required double stage1Fraction,
}) {
  if (stage1Fraction <= 0.0) {
    return;
  }
  if (exitProgress < stage1Fraction) {
    subtaskController.value =
        initialSubtaskValue * (1.0 - (exitProgress / stage1Fraction));
    return;
  }
  if (subtaskController.value != 0.0) {
    subtaskController.value = 0.0;
  }
}

/// Returns `true` when toggling [stepIndex] on [task] will auto-finish the task.
bool willSubtaskToggleAutoFinish(TaskItem task, int stepIndex) {
  final subtasks = task.subtasks;
  if (stepIndex < 0 || stepIndex >= subtasks.length) {
    return false;
  }
  return task.subtasksAutoFinish &&
      !subtasks[stepIndex].isCompleted &&
      _areAllOtherSubtasksCompleted(subtasks, stepIndex);
}

/// Returns `true` when every subtask in [subtasks] except [toggledIndex] is already completed.
bool _areAllOtherSubtasksCompleted(
  List<SubtaskItem> subtasks,
  int toggledIndex,
) {
  for (var i = 0; i < subtasks.length; i++) {
    if (i != toggledIndex && !subtasks[i].isCompleted) {
      return false;
    }
  }
  return true;
}

/// Copies [text] to the system clipboard and shows [snackBarMessage] when [context] remains mounted.
Future<void> _copyTextToClipboardWithSnackBar(
  BuildContext context, {
  required String snackBarMessage,
  required String text,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) {
    return;
  }
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(snackBarMessage)));
}
