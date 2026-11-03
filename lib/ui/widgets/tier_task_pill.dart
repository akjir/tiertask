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

/// Task pill card with animated downward subtask expansion and right-side status indicators.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import '../../providers/task_providers.dart';
import '../edit_task_screen.dart';

/// Animation duration for expanding and collapsing task subtasks.
const Duration _subtaskExpandDuration = Duration(milliseconds: 220);

/// Minimal pill card representing a single task entry across all 6 tier panes.
class TierTaskPill extends ConsumerStatefulWidget {
  /// Creates a [TierTaskPill].
  const TierTaskPill({
    super.key,
    required this.canDowngrade,
    required this.isCompleted,
    required this.task,
  });

  /// Whether the task belongs to a downgradable tier (`Focus`, `Ready`, or `Planned`).
  final bool canDowngrade;

  /// Whether the task belongs to the completed archive tier.
  final bool isCompleted;

  /// Task item to display.
  final TaskItem task;

  @override
  ConsumerState<TierTaskPill> createState() => _TierTaskPillState();
}

/// Animated container that glides the subtask checklist downward when [isExpanded] is `true`.
class _AnimatedSubtasksSection extends StatelessWidget {
  /// Creates an [_AnimatedSubtasksSection].
  const _AnimatedSubtasksSection({
    required this.isExpanded,
    required this.subtasks,
    required this.taskId,
    required this.onToggleSubtask,
  });

  /// Whether the subtask list is currently expanded.
  final bool isExpanded;

  /// Callback invoked with the zero-based step index when a subtask row is tapped.
  final ValueChanged<int> onToggleSubtask;

  /// Ordered checklist steps belonging to [taskId].
  final List<SubtaskItem> subtasks;

  /// Identifier of the parent task.
  final String taskId;

  @override
  Widget build(BuildContext context) {
    if (subtasks.isEmpty) {
      return const SizedBox.shrink();
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: isExpanded ? 1.0 : 0.0),
      duration: _subtaskExpandDuration,
      curve: Curves.easeInOutCubic,
      builder: (context, progress, child) {
        if (!isExpanded && progress <= 0.0) {
          return const SizedBox.shrink();
        }
        return ClipRect(
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: progress,
            child: child,
          ),
        );
      },
      child: _SubtaskStepsColumn(
        subtasks: subtasks,
        taskId: taskId,
        onToggleSubtask: onToggleSubtask,
      ),
    );
  }
}

/// Column of interactive subtask rows rendered below the main task pill header.
class _SubtaskStepsColumn extends StatelessWidget {
  /// Creates a [_SubtaskStepsColumn].
  const _SubtaskStepsColumn({
    required this.subtasks,
    required this.taskId,
    required this.onToggleSubtask,
  });

  /// Callback invoked with the zero-based step index when a subtask row is tapped.
  final ValueChanged<int> onToggleSubtask;

  /// Ordered checklist steps belonging to [taskId].
  final List<SubtaskItem> subtasks;

  /// Identifier of the parent task.
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(context).dividerColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: dividerColor, width: 1)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < subtasks.length; i++)
              _TierSubtaskStepRow(
                stepKey: ValueKey('subtask_step_${taskId}_$i'),
                subtask: subtasks[i],
                onTap: () => onToggleSubtask(i),
              ),
          ],
        ),
      ),
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
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isCompleted ? colorScheme.primaryContainer : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: isCompleted
              ? colorScheme.primaryContainer
              : colorScheme.onSurfaceVariant,
          width: 1.8,
        ),
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

  /// Callback invoked when the subtask row is tapped to check or uncheck it.
  final VoidCallback onTap;

  /// Deterministic widget key for the subtask row.
  final Key stepKey;

  /// Subtask step item to render.
  final SubtaskItem subtask;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      key: stepKey,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 20, 8),
        child: Row(
          children: [
            _TierSubtaskCheckbox(isCompleted: subtask.isCompleted),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                subtask.title,
                style: TextStyle(
                  color: subtask.isCompleted
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  decoration: subtask.isCompleted
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact icon button rendered on the right side of [_TierTaskPillRow].
class _TierTaskActionButton extends StatelessWidget {
  /// Creates a [_TierTaskActionButton].
  const _TierTaskActionButton({
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  /// Deterministic widget key for the icon button.
  final Key buttonKey;

  /// Icon displayed inside the button.
  final IconData icon;

  /// Callback invoked when the button is tapped, or `null` when disabled.
  final VoidCallback? onPressed;

  /// Localized tooltip message.
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Center(
        child: IconButton(
          key: buttonKey,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: tooltip,
          icon: Icon(icon, size: 22, color: mutedColor),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// Rounded square button at the leading edge of [_TierTaskPillRow] containing a white circle to complete or restore a task.
class _TierTaskCompletionCircle extends StatelessWidget {
  /// Creates a [_TierTaskCompletionCircle].
  const _TierTaskCompletionCircle({
    required this.buttonKey,
    required this.isCompleted,
    required this.onComplete,
  });

  /// Deterministic widget key for the completion button.
  final Key buttonKey;

  /// Whether the task is already completed.
  final bool isCompleted;

  /// Callback invoked when the completion button is tapped.
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      key: buttonKey,
      borderRadius: BorderRadius.circular(10),
      onTap: onComplete,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: isCompleted
              ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

/// Passive status indicator icon with a localized hover tooltip inside [_TierTaskIndicators].
class _TierTaskIndicatorIcon extends StatelessWidget {
  /// Creates a [_TierTaskIndicatorIcon].
  const _TierTaskIndicatorIcon({
    required this.color,
    required this.icon,
    required this.indicatorKey,
    required this.tooltip,
  });

  /// Muted icon color.
  final Color color;

  /// Icon glyph representing the task attribute.
  final IconData icon;

  /// Deterministic widget key for the indicator icon.
  final Key indicatorKey;

  /// Localized tooltip displayed when hovering over the indicator.
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: tooltip,
        child: Icon(icon, key: indicatorKey, size: 16, color: color),
      ),
    );
  }
}

/// Passive right-side status indicator icons for priority, repeating, and subtask-bearing tasks.
class _TierTaskIndicators extends StatelessWidget {
  /// Creates a [_TierTaskIndicators] row.
  const _TierTaskIndicators({required this.task});

  /// Task item whose passive indicators are displayed.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final hasPriority = task.isPriority;
    final hasRepeat = task.repeatRule != null;
    final hasSubtasks = task.subtasks.isNotEmpty;
    if (!hasPriority && !hasRepeat && !hasSubtasks) {
      return const SizedBox.shrink();
    }

    final localizations = AppLocalizations.of(context);
    final indicatorColor = Theme.of(context).colorScheme.onSurfaceVariant
        .withValues(alpha: 0.55);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasPriority)
          _TierTaskIndicatorIcon(
            color: indicatorColor,
            icon: Icons.bolt_rounded,
            indicatorKey: ValueKey('priority_task_indicator_${task.id}'),
            tooltip: localizations.tooltipIndicatorPriority,
          ),
        if (hasRepeat)
          _TierTaskIndicatorIcon(
            color: indicatorColor,
            icon: Icons.repeat_rounded,
            indicatorKey: ValueKey('repeat_task_indicator_${task.id}'),
            tooltip: localizations.tooltipIndicatorRepeat,
          ),
        if (hasSubtasks)
          _TierTaskIndicatorIcon(
            color: indicatorColor,
            icon: task.subtasksAutoFinish
                ? Icons.fact_check_outlined
                : Icons.checklist_rounded,
            indicatorKey: ValueKey('subtasks_task_indicator_${task.id}'),
            tooltip: task.subtasksAutoFinish
                ? localizations.tooltipIndicatorSubtasksAutoFinish
                : localizations.tooltipIndicatorSubtasks,
          ),
      ],
    );
  }
}

/// Left-hand content area inside [_TierTaskPillRow] containing the completion square, task title, and passive indicators.
class _TierTaskPillContent extends StatelessWidget {
  /// Creates a [_TierTaskPillContent].
  const _TierTaskPillContent({
    required this.isCompleted,
    required this.task,
    required this.onComplete,
    required this.onToggleExpand,
  });

  /// Whether the task is completed.
  final bool isCompleted;

  /// Callback invoked when the leading completion square is pressed.
  final VoidCallback onComplete;

  /// Optional callback invoked when the task content body is tapped to expand or collapse subtasks.
  final VoidCallback? onToggleExpand;

  /// Task item displayed in this content section.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onToggleExpand,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
        child: Row(
          children: [
            _TierTaskCompletionCircle(
              buttonKey: ValueKey('complete_task_button_${task.id}'),
              isCompleted: isCompleted,
              onComplete: onComplete,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                task.title,
                style: TextStyle(
                  color: isCompleted
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            _TierTaskIndicators(task: task),
          ],
        ),
      ),
    );
  }
}

/// Row layout inside [TierTaskPill] combining the task content area, right-chevron downgrade button, and three-dots edit button.
class _TierTaskPillRow extends StatelessWidget {
  /// Creates a [_TierTaskPillRow].
  const _TierTaskPillRow({
    required this.isCompleted,
    required this.task,
    required this.onComplete,
    required this.onDowngrade,
    required this.onEdit,
    required this.onToggleExpand,
  });

  /// Whether the task is completed.
  final bool isCompleted;

  /// Callback invoked when the leading completion square is pressed.
  final VoidCallback onComplete;

  /// Callback invoked when the downgrade button is pressed, or `null` when omitted.
  final VoidCallback? onDowngrade;

  /// Callback invoked when the edit button is pressed.
  final VoidCallback onEdit;

  /// Optional callback invoked when the task body is tapped to expand or collapse subtasks.
  final VoidCallback? onToggleExpand;

  /// Task item displayed in this pill row.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _TierTaskPillContent(
            isCompleted: isCompleted,
            task: task,
            onComplete: onComplete,
            onToggleExpand: onToggleExpand,
          ),
        ),
        if (onDowngrade != null)
          _TierTaskActionButton(
            buttonKey: ValueKey('downgrade_task_button_${task.id}'),
            icon: Icons.chevron_right_rounded,
            tooltip: localizations.tooltipDowngradeTask,
            onPressed: onDowngrade,
          ),
        _TierTaskActionButton(
          buttonKey: ValueKey('edit_task_button_${task.id}'),
          icon: Icons.more_vert_rounded,
          tooltip: localizations.tooltipEditTask,
          onPressed: onEdit,
        ),
        const SizedBox(width: 6),
      ],
    );
  }
}

/// State for [TierTaskPill] managing subtask expansion and collapse.
class _TierTaskPillState extends ConsumerState<TierTaskPill> {
  bool _isExpanded = false;

  @override
  void didUpdateWidget(covariant TierTaskPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.task.subtasks.isEmpty && _isExpanded) {
      _isExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = widget.task;
    final hasSubtasks = task.subtasks.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.cardColor,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IntrinsicHeight(
              child: _TierTaskPillRow(
                isCompleted: widget.isCompleted,
                task: task,
                onComplete: () => widget.isCompleted
                    ? ref
                          .read(taskNotifierProvider.notifier)
                          .restoreTask(task.id)
                    : ref
                          .read(taskNotifierProvider.notifier)
                          .completeTask(task.id),
                onDowngrade: widget.canDowngrade
                    ? () => ref
                          .read(taskNotifierProvider.notifier)
                          .downgradeTask(task.id)
                    : null,
                onEdit: () => openEditTaskScreen(context, initialTask: task),
                onToggleExpand: hasSubtasks ? _toggleExpanded : null,
              ),
            ),
            _AnimatedSubtasksSection(
              isExpanded: _isExpanded && hasSubtasks,
              subtasks: task.subtasks,
              taskId: task.id,
              onToggleSubtask: (stepIndex) => ref
                  .read(taskNotifierProvider.notifier)
                  .toggleSubtask(task.id, stepIndex),
            ),
          ],
        ),
      ),
    );
  }

  /// Toggles the expanded state of the task's subtask checklist.
  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }
}
