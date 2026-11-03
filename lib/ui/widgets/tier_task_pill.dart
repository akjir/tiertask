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

/// Task pill card with animated subtask expansion, closing, upgrade, and downgrade transitions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import '../../providers/task_providers.dart';
import '../../repositories/link_launcher_repository.dart';
import '../../services/app_logger.dart';
import '../edit_task_screen.dart';

/// Animation duration for expanding and collapsing task subtasks.
const Duration _subtaskExpandDuration = Duration(milliseconds: 220);

/// Animation duration for closing, downgrading, or restoring a task pill.
const Duration _taskExitDuration = Duration(milliseconds: 260);

/// Animation duration for a task upgrading into a tier via auto-pull.
const Duration _taskUpgradeEntryDuration = Duration(milliseconds: 240);

/// Minimal pill card representing a single task entry across all 6 tier panes.
class TierTaskPill extends ConsumerStatefulWidget {
  /// Creates a [TierTaskPill].
  const TierTaskPill({
    super.key,
    this.animateEntry = false,
    required this.canDowngrade,
    required this.isCompleted,
    required this.task,
  });

  /// Whether this pill should play an upgrade entry animation when first mounted.
  final bool animateEntry;

  /// Whether the task belongs to a downgradable tier (`Focus`, `Ready`, or `Planned`).
  final bool canDowngrade;

  /// Whether the task belongs to the completed archive tier.
  final bool isCompleted;

  /// Task item to display.
  final TaskItem task;

  @override
  ConsumerState<TierTaskPill> createState() => _TierTaskPillState();
}

/// Animated container that glides the task note, links, and subtask checklist downward or upward driven by [controller].
class _AnimatedSubtasksSection extends StatelessWidget {
  /// Creates an [_AnimatedSubtasksSection].
  const _AnimatedSubtasksSection({
    required this.controller,
    required this.isExpanded,
    required this.links,
    required this.note,
    required this.subtasks,
    required this.taskId,
    required this.onOpenLink,
    required this.onToggleSubtask,
  });

  /// Animation controller driving the expansion progress between `0.0` and `1.0`.
  final Animation<double> controller;

  /// Whether the note, link, and subtask list is currently expanded.
  final bool isExpanded;

  /// Resource links belonging to [taskId].
  final List<TaskLink> links;

  /// Optional task note belonging to [taskId].
  final String? note;

  /// Callback invoked when a link row is tapped.
  final ValueChanged<String> onOpenLink;

  /// Callback invoked with the zero-based step index when a subtask row is tapped, or `null` when locked.
  final ValueChanged<int>? onToggleSubtask;

  /// Ordered checklist steps belonging to [taskId].
  final List<SubtaskItem> subtasks;

  /// Identifier of the parent task.
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final activeNote = note;
    final hasNote = activeNote != null && activeNote.isNotEmpty;
    if (!hasNote && subtasks.isEmpty && links.isEmpty) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: controller,
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
            child: child,
          ),
        );
      },
      child: _SubtaskStepsColumn(
        links: links,
        note: activeNote,
        subtasks: subtasks,
        taskId: taskId,
        onOpenLink: onOpenLink,
        onToggleSubtask: onToggleSubtask,
      ),
    );
  }
}

/// Wrapper widget applying directional entry, closing, downgrade, and restore animations to [child].
class _AnimatedTaskTransitionWrapper extends StatelessWidget {
  /// Creates an [_AnimatedTaskTransitionWrapper].
  const _AnimatedTaskTransitionWrapper({
    required this.entryAnimation,
    required this.exitAction,
    required this.exitAnimation,
    required this.exitStage1Fraction,
    required this.child,
  });

  /// Pill card subtree being animated.
  final Widget child;

  /// Controller driving the upgrade entry animation (`0.0` to `1.0`).
  final Animation<double> entryAnimation;

  /// Active exit transition, or `null` when the task is not exiting.
  final _TaskExitAction? exitAction;

  /// Controller driving the overall exit sequence (`0.0` to `1.0`).
  final Animation<double> exitAnimation;

  /// Fraction of [exitAnimation] dedicated to Stage 1 subgroup collapse (`0.0` when no subgroup was open).
  final double exitStage1Fraction;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([entryAnimation, exitAnimation]),
      builder: (context, animatedChild) {
        final metrics = _resolveMetrics();
        return IgnorePointer(
          ignoring: exitAction != null,
          child: ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: metrics.heightFactor,
              child: Opacity(
                opacity: metrics.opacity,
                child: FractionalTranslation(
                  translation: metrics.translation,
                  child: Transform.scale(
                    scale: metrics.scale,
                    child: animatedChild,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: child,
    );
  }

  /// Computes layout height factor, opacity, translation, and scale for the current animation frame.
  ({double heightFactor, double opacity, double scale, Offset translation})
  _resolveMetrics() {
    final activeExit = exitAction;
    if (activeExit != null && exitAnimation.value > exitStage1Fraction) {
      final rawStage2 =
          (exitAnimation.value - exitStage1Fraction) /
          (1.0 - exitStage1Fraction);
      final progress = Curves.easeInOutCubic.transform(
        rawStage2.clamp(0.0, 1.0),
      );
      final heightFactor = (1.0 - progress).clamp(0.0, 1.0);
      final opacity = (1.0 - progress).clamp(0.0, 1.0);
      return switch (activeExit) {
        _CompleteTaskExit() || _SubtaskCompleteTaskExit() => (
          heightFactor: heightFactor,
          opacity: opacity,
          scale: 1.0 - (0.04 * progress),
          translation: Offset(0.04 * progress, 0.0),
        ),
        _DowngradeTaskExit() => (
          heightFactor: heightFactor,
          opacity: opacity,
          scale: 1.0,
          translation: Offset(0.18 * progress, 0.0),
        ),
        _RestoreTaskExit() => (
          heightFactor: heightFactor,
          opacity: opacity,
          scale: 1.0,
          translation: Offset(-0.18 * progress, 0.0),
        ),
      };
    }

    if (entryAnimation.value < 1.0) {
      final progress = Curves.easeOutCubic.transform(entryAnimation.value);
      final remaining = 1.0 - progress;
      return (
        heightFactor: progress.clamp(0.0, 1.0),
        opacity: progress.clamp(0.0, 1.0),
        scale: 0.96 + (0.04 * progress),
        translation: Offset(-0.06 * remaining, 0.12 * remaining),
      );
    }

    return (
      heightFactor: 1.0,
      opacity: 1.0,
      scale: 1.0,
      translation: Offset.zero,
    );
  }
}

/// Direct task completion triggered via the leading completion square.
final class _CompleteTaskExit extends _TaskExitAction {
  /// Creates a [_CompleteTaskExit].
  const _CompleteTaskExit();
}

/// Task downgrade triggered via the right-chevron downgrade button.
final class _DowngradeTaskExit extends _TaskExitAction {
  /// Creates a [_DowngradeTaskExit].
  const _DowngradeTaskExit();
}

/// Task restoration (upgrade from `Completed`) triggered via the leading completion square.
final class _RestoreTaskExit extends _TaskExitAction {
  /// Creates a [_RestoreTaskExit].
  const _RestoreTaskExit();
}

/// Task auto-completion triggered by checking the final subtask at [stepIndex].
final class _SubtaskCompleteTaskExit extends _TaskExitAction {
  /// Creates a [_SubtaskCompleteTaskExit].
  const _SubtaskCompleteTaskExit(this.stepIndex);

  /// Zero-based index of the subtask step that triggered auto-completion.
  final int stepIndex;
}

/// Column of note, interactive link, and subtask rows rendered below the main task pill header.
class _SubtaskStepsColumn extends StatelessWidget {
  /// Creates a [_SubtaskStepsColumn].
  const _SubtaskStepsColumn({
    required this.links,
    required this.note,
    required this.subtasks,
    required this.taskId,
    required this.onOpenLink,
    required this.onToggleSubtask,
  });

  /// Resource links belonging to [taskId].
  final List<TaskLink> links;

  /// Optional task note belonging to [taskId].
  final String? note;

  /// Callback invoked when a link row is tapped.
  final ValueChanged<String> onOpenLink;

  /// Callback invoked with the zero-based step index when a subtask row is tapped, or `null` when locked.
  final ValueChanged<int>? onToggleSubtask;

  /// Ordered checklist steps belonging to [taskId].
  final List<SubtaskItem> subtasks;

  /// Identifier of the parent task.
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(context).dividerColor;
    final activeNote = note;
    final toggleCallback = onToggleSubtask;
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
            if (activeNote != null && activeNote.isNotEmpty)
              _TierNoteRow(
                noteKey: ValueKey('task_note_$taskId'),
                note: activeNote,
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
      ),
    );
  }
}

/// Represents the active exit transition on a [TierTaskPill].
sealed class _TaskExitAction {
  /// Creates a [_TaskExitAction].
  const _TaskExitAction();
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
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: link.uri,
      child: InkWell(
        key: linkKey,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 20, 8),
          child: Row(
            children: [
              Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  link.title,
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Row displaying the task [note] with a leading note icon inside [_SubtaskStepsColumn].
class _TierNoteRow extends StatelessWidget {
  /// Creates a [_TierNoteRow].
  const _TierNoteRow({required this.note, required this.noteKey});

  /// Note text to render.
  final String note;

  /// Deterministic widget key for the note row.
  final Key noteKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      key: noteKey,
      padding: const EdgeInsets.fromLTRB(22, 8, 20, 8),
      child: Row(
        children: [
          Icon(
            Icons.notes_rounded,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              note,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
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

  /// Callback invoked when the subtask row is tapped to check or uncheck it, or `null` when locked.
  final VoidCallback? onTap;

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

/// Passive right-side status indicator icons for priority, repeating, note-bearing, link-bearing, and subtask-bearing tasks.
class _TierTaskIndicators extends StatelessWidget {
  /// Creates a [_TierTaskIndicators] row.
  const _TierTaskIndicators({required this.task});

  /// Task item whose passive indicators are displayed.
  final TaskItem task;

  /// Whether [task] carries at least one passive status indicator.
  bool get _hasAnyIndicator {
    final note = task.note;
    return task.isPriority ||
        task.repeatRule != null ||
        (note != null && note.isNotEmpty) ||
        task.links.isNotEmpty ||
        task.subtasks.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasAnyIndicator) {
      return const SizedBox.shrink();
    }
    final localizations = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme.onSurfaceVariant
        .withValues(alpha: 0.55);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final spec in _resolveIndicatorSpecs(localizations))
          _TierTaskIndicatorIcon(
            color: color,
            icon: spec.icon,
            indicatorKey: ValueKey('${spec.keyPrefix}_${task.id}'),
            tooltip: spec.tooltip,
          ),
      ],
    );
  }

  /// Resolves the ordered passive indicator specifications for [task].
  List<({IconData icon, String keyPrefix, String tooltip})>
  _resolveIndicatorSpecs(AppLocalizations localizations) {
    final note = task.note;
    return [
      if (task.isPriority)
        (
          icon: Icons.bolt_rounded,
          keyPrefix: 'priority_task_indicator',
          tooltip: localizations.tooltipIndicatorPriority,
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

/// State for [TierTaskPill] coordinating subtask expansion, closing, downgrade, and upgrade animations.
class _TierTaskPillState extends ConsumerState<TierTaskPill>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  _TaskExitAction? _exitAction;
  late final AnimationController _exitController;
  double _exitInitialSubtaskValue = 0.0;
  double _exitStage1Fraction = 0.0;
  bool _isExpanded = false;
  late final AnimationController _subtaskController;

  /// Whether [widget.task] has a non-empty note, links, or subtasks that can be expanded.
  bool get _hasExpandableDetails {
    final note = widget.task.note;
    return (note != null && note.isNotEmpty) ||
        widget.task.links.isNotEmpty ||
        widget.task.subtasks.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _subtaskController = AnimationController(
      vsync: this,
      duration: _subtaskExpandDuration,
    );
    _exitController =
        AnimationController(vsync: this, duration: _taskExitDuration)
          ..addListener(_handleExitProgressChanged)
          ..addStatusListener(_handleExitStatusChanged);
    _entryController = AnimationController(
      vsync: this,
      duration: _taskUpgradeEntryDuration,
      value: widget.animateEntry ? 0.0 : 1.0,
    );
    if (widget.animateEntry) {
      _entryController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant TierTaskPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasExpandableDetails && _isExpanded) {
      _isExpanded = false;
      _subtaskController.value = 0.0;
    }
  }

  @override
  void dispose() {
    _subtaskController.dispose();
    _exitController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = widget.task;
    final hasExpandableDetails = _hasExpandableDetails;
    final effectiveSubtasks = _resolveDisplayedSubtasks(task.subtasks);

    return _AnimatedTaskTransitionWrapper(
      entryAnimation: _entryController,
      exitAction: _exitAction,
      exitAnimation: _exitController,
      exitStage1Fraction: _exitStage1Fraction,
      child: Padding(
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
                  isCompleted: _resolveEffectiveCompleted(),
                  task: task,
                  onComplete: _handleCompletePressed,
                  onDowngrade: widget.canDowngrade
                      ? _handleDowngradePressed
                      : null,
                  onEdit: () => openEditTaskScreen(context, initialTask: task),
                  onToggleExpand: hasExpandableDetails ? _toggleExpanded : null,
                ),
              ),
              _AnimatedSubtasksSection(
                controller: _subtaskController,
                isExpanded: _isExpanded && hasExpandableDetails,
                links: task.links,
                note: task.note,
                subtasks: effectiveSubtasks,
                taskId: task.id,
                onOpenLink: _handleOpenLink,
                onToggleSubtask: widget.isCompleted
                    ? null
                    : _handleToggleSubtask,
              ),
            ],
          ),
        ),
      ),
    );
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

  /// Starts the closing or restore exit transition when the leading completion button is pressed.
  void _handleCompletePressed() {
    if (widget.isCompleted) {
      _startExitTransition(const _RestoreTaskExit());
      return;
    }
    _startExitTransition(const _CompleteTaskExit());
  }

  /// Starts the rightward downgrade exit transition when the downgrade button is pressed.
  void _handleDowngradePressed() {
    _startExitTransition(const _DowngradeTaskExit());
  }

  /// Synchronizes Stage 1 subgroup collapse progress with [_exitController] when closing an expanded task.
  void _handleExitProgressChanged() {
    if (_exitStage1Fraction <= 0.0) {
      return;
    }
    final value = _exitController.value;
    if (value < _exitStage1Fraction) {
      final stage1Progress = value / _exitStage1Fraction;
      _subtaskController.value =
          _exitInitialSubtaskValue * (1.0 - stage1Progress);
      return;
    }
    if (_subtaskController.value != 0.0) {
      _subtaskController.value = 0.0;
    }
  }

  /// Commits the pending domain mutation to [TaskNotifier] once [_exitController] finishes.
  void _handleExitStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) {
      return;
    }
    final action = _exitAction;
    if (action == null) {
      return;
    }
    final notifier = ref.read(taskNotifierProvider.notifier);
    final taskId = widget.task.id;
    switch (action) {
      case _CompleteTaskExit():
        notifier.completeTask(taskId);
      case _DowngradeTaskExit():
        notifier.downgradeTask(taskId);
        if (mounted) {
          setState(() {
            _exitAction = null;
            _exitStage1Fraction = 0.0;
            _exitController.value = 0.0;
          });
          _entryController.forward(from: 0.0);
        }
      case _RestoreTaskExit():
        notifier.restoreTask(taskId);
      case _SubtaskCompleteTaskExit(:final stepIndex):
        notifier.toggleSubtask(taskId, stepIndex);
    }
  }

  /// Opens [uri] via [linkLauncherRepositoryProvider] and displays a SnackBar if launching fails.
  Future<void> _handleOpenLink(String uri) async {
    try {
      await ref.read(linkLauncherRepositoryProvider).openLink(uri);
    } on LinkLaunchException {
      if (!mounted) return;
      final localizations = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.errorOpenLinkFailed)),
      );
    }
  }

  /// Handles tapping a subtask at [stepIndex], initiating two-stage closing when auto-finish completes.
  void _handleToggleSubtask(int stepIndex) {
    if (_exitAction != null || widget.isCompleted) {
      return;
    }
    final subtasks = widget.task.subtasks;
    if (stepIndex < 0 || stepIndex >= subtasks.length) {
      return;
    }
    final willAutoComplete =
        widget.task.subtasksAutoFinish &&
        !subtasks[stepIndex].isCompleted &&
        _areAllOtherSubtasksCompleted(subtasks, stepIndex);
    if (!willAutoComplete) {
      ref
          .read(taskNotifierProvider.notifier)
          .toggleSubtask(widget.task.id, stepIndex);
      return;
    }
    _startExitTransition(_SubtaskCompleteTaskExit(stepIndex));
  }

  /// Returns the subtask list with the final auto-finishing step marked completed during Stage 1 collapse.
  List<SubtaskItem> _resolveDisplayedSubtasks(List<SubtaskItem> subtasks) {
    if (_exitAction case _SubtaskCompleteTaskExit(:final stepIndex)) {
      return [
        for (var i = 0; i < subtasks.length; i++)
          i == stepIndex
              ? subtasks[i].copyWith(isCompleted: true)
              : subtasks[i],
      ];
    }
    return subtasks;
  }

  /// Resolves the visual completion state shown in [_TierTaskPillRow] during an active transition.
  bool _resolveEffectiveCompleted() {
    return switch (_exitAction) {
      _CompleteTaskExit() || _SubtaskCompleteTaskExit() => true,
      _RestoreTaskExit() => false,
      _DowngradeTaskExit() || null => widget.isCompleted,
    };
  }

  /// Initiates an exit transition, collapsing the subtask subgroup first if currently expanded.
  void _startExitTransition(_TaskExitAction action) {
    if (_exitAction != null) {
      return;
    }
    final subtaskValue = _subtaskController.value;
    _subtaskController.stop();
    final stage1Microseconds =
        (_subtaskExpandDuration.inMicroseconds * subtaskValue).round();
    final stage2Microseconds = _taskExitDuration.inMicroseconds;
    final totalMicroseconds = stage1Microseconds + stage2Microseconds;

    setState(() {
      _exitAction = action;
      _isExpanded = false;
      _exitInitialSubtaskValue = subtaskValue;
      _exitStage1Fraction = stage1Microseconds > 0
          ? stage1Microseconds / totalMicroseconds
          : 0.0;
    });
    _exitController.duration = Duration(microseconds: totalMicroseconds);
    _exitController.forward(from: 0.0);
  }

  /// Toggles the expanded state of the task's details section.
  void _toggleExpanded() {
    if (_exitAction != null) {
      return;
    }
    setState(() {
      _isExpanded = !_isExpanded;
    });
    AppLogger.debug(
      LogTag.ui,
      'Toggled task details task=${widget.task.id} expanded=$_isExpanded',
    );
    if (_isExpanded) {
      _subtaskController.forward();
    } else {
      _subtaskController.reverse();
    }
  }
}
