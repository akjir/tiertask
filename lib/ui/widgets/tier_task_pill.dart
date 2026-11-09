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
import '../../models/tdf_metadata.dart';
import '../../providers/config_providers.dart';
import '../../providers/task_providers.dart';
import '../edit_task_screen.dart';
import 'task_info_dialog.dart';
import 'tier_task_subtasks_section.dart';

/// Animation duration for closing, downgrading, or restoring a task pill.
const Duration _taskExitDuration = Duration(milliseconds: 260);

/// Animation duration for a task upgrading into a tier via auto-pull.
const Duration _taskUpgradeEntryDuration = Duration(milliseconds: 240);

/// Minimal pill card representing a single task entry across all 6 tier panes.
class TierTaskPill extends ConsumerStatefulWidget {
  /// Creates a [TierTaskPill].
  const TierTaskPill({
    super.key,
    this.activeFilterLabelId,
    this.animateEntry = false,
    required this.canDowngrade,
    required this.isCompleted,
    required this.task,
  });

  /// Optional active label filter ID used for scoped downgrade behavior.
  final String? activeFilterLabelId;

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
      final p = Curves.easeInOutCubic.transform(rawStage2.clamp(0.0, 1.0));
      final r = (1.0 - p).clamp(0.0, 1.0);
      final (scale, dx) = switch (activeExit) {
        _CompleteTaskExit() ||
        _SubtaskCompleteTaskExit() => (1.0 - (0.04 * p), 0.04 * p),
        _DowngradeTaskExit() => (1.0, 0.18 * p),
        _RestoreTaskExit() => (1.0, -0.18 * p),
      };
      return (
        heightFactor: r,
        opacity: r,
        scale: scale,
        translation: Offset(dx, 0.0),
      );
    }
    final p = Curves.easeOutCubic
        .transform(entryAnimation.value)
        .clamp(0.0, 1.0);
    final r = 1.0 - p;
    return (
      heightFactor: p,
      opacity: p,
      scale: 0.96 + (0.04 * p),
      translation: Offset(-0.06 * r, 0.12 * r),
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

/// Represents the active exit transition on a [TierTaskPill].
sealed class _TaskExitAction {
  /// Creates a [_TaskExitAction].
  const _TaskExitAction();
}

/// Interactive right-side status indicator icons that open [TaskInfoDialog] when clicked or tapped.
class _TierTaskIndicators extends StatelessWidget {
  /// Creates a [_TierTaskIndicators] row.
  const _TierTaskIndicators({required this.task});

  /// Task item whose status indicators are displayed.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final specs = resolveTaskIndicatorSpecs(task, localizations);
    final dueAt = task.dueAt;
    if (specs.isEmpty && dueAt == null) {
      return const SizedBox.shrink();
    }
    final color = Theme.of(context).colorScheme.onSurfaceVariant
        .withValues(alpha: 0.55);
    final displayedSpecs = _resolveDisplayedSpecs(specs, localizations);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showTaskInfoDialog(context, task: task),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dueAt != null)
              _buildDueBadge(context, localizations, dueAt, color),
            for (final spec in displayedSpecs)
              _buildIndicatorItem(context, spec, color),
          ],
        ),
      ),
    );
  }

  /// Builds the tappable due date badge on the left of the indicator strip.
  Widget _buildDueBadge(
    BuildContext context,
    AppLocalizations localizations,
    DateTime dueAt,
    Color color,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showTaskInfoDialog(
        context,
        task: task,
        initialIndicatorKeyPrefix: 'due_task_badge',
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Text(
          localizations.pillDuePrefix(TaskItem.formatIsoDate(dueAt)),
          key: ValueKey('due_task_badge_${task.id}'),
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Builds a single interactive indicator icon wrapped in a [Tooltip].
  Widget _buildIndicatorItem(
    BuildContext context,
    ({IconData icon, String keyPrefix, String tooltip}) spec,
    Color color,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showTaskInfoDialog(
        context,
        task: task,
        initialIndicatorKeyPrefix: spec.keyPrefix,
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Tooltip(
          message: spec.tooltip,
          child: Icon(
            spec.icon,
            key: ValueKey('${spec.keyPrefix}_${task.id}'),
            size: 16,
            color: color,
          ),
        ),
      ),
    );
  }

  /// Collapses [specs] into a single summary indicator when more than [maxVisibleTaskIndicators] are active.
  static List<({IconData icon, String keyPrefix, String tooltip})>
  _resolveDisplayedSpecs(
    List<({IconData icon, String keyPrefix, String tooltip})> specs,
    AppLocalizations localizations,
  ) {
    if (specs.length <= maxVisibleTaskIndicators) {
      return specs;
    }
    return [
      (
        icon: Icons.info_outline_rounded,
        keyPrefix: 'summary_task_indicator',
        tooltip: localizations.tooltipIndicatorSummary(specs.length.toString()),
      ),
    ];
  }
}

/// Bottom-aligned row of uniform color blocks representing the labels assigned to [taskId].
class _TierTaskLabelIndicators extends StatelessWidget {
  /// Creates a [_TierTaskLabelIndicators] row.
  const _TierTaskLabelIndicators({required this.labels, required this.taskId});

  /// Height of each individual label indicator block.
  static const double blockHeight = 5;

  /// Horizontal spacing between adjacent label indicator blocks.
  static const double blockSpacing = 8;

  /// Width of each individual label indicator block.
  static const double blockWidth = 24;

  /// Ordered labels assigned to [taskId].
  final List<TdfLabel> labels;

  /// Identifier of the task owning these label indicators.
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final fallbackColor = Theme.of(context).colorScheme.onSurfaceVariant
        .withValues(alpha: 0.55);
    return ClipRect(
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: blockSpacing),
            Tooltip(
              message: labels[i].name,
              child: Container(
                key: ValueKey('label_task_indicator_${taskId}_${labels[i].id}'),
                width: blockWidth,
                height: blockHeight,
                decoration: BoxDecoration(
                  color: _resolveColor(labels[i].color, fallbackColor),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Resolves the `#RRGGBB` color of [rawHex] or returns [fallback].
  static Color _resolveColor(String? rawHex, Color fallback) {
    final parsed = TdfColor.tryParseArgb(rawHex);
    return parsed != null ? Color(parsed) : fallback;
  }
}

/// Row layout inside [TierTaskPill] combining the task content area, right-chevron downgrade button, and three-dots edit button.
class _TierTaskPillRow extends StatelessWidget {
  /// Creates a [_TierTaskPillRow].
  const _TierTaskPillRow({
    required this.isCompleted,
    required this.labels,
    required this.task,
    required this.onComplete,
    required this.onDowngrade,
    required this.onEdit,
    required this.onToggleExpand,
  });

  /// Whether the task is completed.
  final bool isCompleted;

  /// Ordered labels assigned to [task].
  final List<TdfLabel> labels;

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
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildContentArea(context)),
          if (onDowngrade != null)
            _buildActionButton(
              buttonKey: ValueKey('downgrade_task_button_${task.id}'),
              color: mutedColor,
              icon: Icons.chevron_right_rounded,
              tooltip: localizations.tooltipDowngradeTask,
              onPressed: onDowngrade,
            ),
          _buildActionButton(
            buttonKey: ValueKey('edit_task_button_${task.id}'),
            color: mutedColor,
            icon: Icons.more_vert_rounded,
            tooltip: localizations.tooltipEditTask,
            onPressed: onEdit,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  /// Builds a compact action icon button on the right side of the pill row.
  Widget _buildActionButton({
    required Key buttonKey,
    required Color color,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Center(
        child: IconButton(
          key: buttonKey,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: tooltip,
          icon: Icon(icon, size: 22, color: color),
          onPressed: onPressed,
        ),
      ),
    );
  }

  /// Builds the rounded square completion button containing a white check circle.
  Widget _buildCompletionButton(BuildContext context) {
    final primaryContainer = Theme.of(context).colorScheme.primaryContainer;
    return InkWell(
      key: ValueKey('complete_task_button_${task.id}'),
      borderRadius: BorderRadius.circular(10),
      onTap: onComplete,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primaryContainer,
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

  /// Builds the tappable left content area containing the completion circle, title, passive indicators, and bottom label blocks.
  Widget _buildContentArea(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final titleStyle = TextStyle(
      color: isCompleted ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
      fontSize: 16,
      fontWeight: FontWeight.w500,
      decoration: isCompleted ? TextDecoration.lineThrough : null,
    );
    return InkWell(
      onTap: onToggleExpand,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
            child: Row(
              children: [
                _buildCompletionButton(context),
                const SizedBox(width: 16),
                Expanded(child: Text(task.title, style: titleStyle)),
                _TierTaskIndicators(task: task),
              ],
            ),
          ),
          if (labels.isNotEmpty)
            Positioned(
              left: 66,
              right: 8,
              bottom: 0,
              child: _TierTaskLabelIndicators(labels: labels, taskId: task.id),
            ),
        ],
      ),
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

  /// Zero-based subtask index currently triggering Stage 1 auto-finish collapse, if any.
  int? get _autoFinishingStepIndex => switch (_exitAction) {
    _SubtaskCompleteTaskExit(:final stepIndex) => stepIndex,
    _CompleteTaskExit() ||
    _DowngradeTaskExit() ||
    _RestoreTaskExit() ||
    null => null,
  };

  /// Visual completion state shown in [_TierTaskPillRow] during an active transition.
  bool get _effectiveCompleted => switch (_exitAction) {
    _CompleteTaskExit() || _SubtaskCompleteTaskExit() => true,
    _RestoreTaskExit() => false,
    _DowngradeTaskExit() || null => widget.isCompleted,
  };

  @override
  void initState() {
    super.initState();
    _subtaskController = AnimationController(
      vsync: this,
      duration: subtaskExpandDuration,
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
    if (!hasExpandableTaskDetails(widget.task) && _isExpanded) {
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
    final task = widget.task;
    final hasExpandableDetails = hasExpandableTaskDetails(task);

    return _AnimatedTaskTransitionWrapper(
      entryAnimation: _entryController,
      exitAction: _exitAction,
      exitAnimation: _exitController,
      exitStage1Fraction: _exitStage1Fraction,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: Theme.of(context).cardColor,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(16),
          child: _buildCardColumn(task, hasExpandableDetails),
        ),
      ),
    );
  }

  /// Builds the pill header row and expandable details section for [task].
  Widget _buildCardColumn(TaskItem task, bool hasExpandableDetails) {
    final sortedLabels = task.labelIds.isEmpty
        ? const <TdfLabel>[]
        : ref.watch(
            taskNotifierProvider.select(
              (board) => board.asData?.value.sortedLabels ?? const <TdfLabel>[],
            ),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TierTaskPillRow(
          isCompleted: _effectiveCompleted,
          labels: resolveTaskLabels(sortedLabels, task.labelIds),
          task: task,
          onComplete: _handleCompletePressed,
          onDowngrade: widget.canDowngrade ? _handleDowngradePressed : null,
          onEdit: () => openEditTaskScreen(context, initialTask: task),
          onToggleExpand: hasExpandableDetails ? _toggleExpanded : null,
        ),
        AnimatedSubtasksSection(
          autoFinishingStepIndex: _autoFinishingStepIndex,
          controller: _subtaskController,
          isExpanded: _isExpanded && hasExpandableDetails,
          task: task,
          onOpenLink: _handleOpenLink,
          onToggleSubtask: widget.isCompleted ? null : _handleToggleSubtask,
        ),
      ],
    );
  }

  /// Starts the closing or restore exit transition when the leading completion button is pressed.
  void _handleCompletePressed() => _startExitTransition(
    widget.isCompleted ? const _RestoreTaskExit() : const _CompleteTaskExit(),
  );

  /// Starts the rightward downgrade exit transition when the downgrade button is pressed.
  void _handleDowngradePressed() =>
      _startExitTransition(const _DowngradeTaskExit());

  /// Synchronizes Stage 1 subgroup collapse progress with [_exitController] when closing an expanded task.
  void _handleExitProgressChanged() => syncSubtaskCollapseProgress(
    _subtaskController,
    exitProgress: _exitController.value,
    initialSubtaskValue: _exitInitialSubtaskValue,
    stage1Fraction: _exitStage1Fraction,
  );

  /// Commits the pending domain mutation to [TaskNotifier] once [_exitController] finishes.
  void _handleExitStatusChanged(AnimationStatus status) {
    final action = _exitAction;
    if (status != AnimationStatus.completed || !mounted || action == null) {
      return;
    }
    final notifier = ref.read(taskNotifierProvider.notifier);
    final taskId = widget.task.id;
    switch (action) {
      case _CompleteTaskExit():
        notifier.completeTask(taskId);
      case _DowngradeTaskExit():
        notifier.downgradeTask(
          taskId,
          activeFilterLabelId: widget.activeFilterLabelId,
        );
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

  /// Opens [uri] via [linkLauncherRepositoryProvider].
  Future<void> _handleOpenLink(String uri) => openTaskResourceLink(
    context,
    ref.read(linkLauncherRepositoryProvider),
    uri,
  );

  /// Handles tapping a subtask at [stepIndex], initiating two-stage closing when auto-finish completes.
  void _handleToggleSubtask(int stepIndex) {
    if (_exitAction != null ||
        widget.isCompleted ||
        stepIndex < 0 ||
        stepIndex >= widget.task.subtasks.length) {
      return;
    }
    if (!willSubtaskToggleAutoFinish(widget.task, stepIndex)) {
      ref
          .read(taskNotifierProvider.notifier)
          .toggleSubtask(widget.task.id, stepIndex);
      return;
    }
    _startExitTransition(_SubtaskCompleteTaskExit(stepIndex));
  }

  /// Initiates an exit transition, collapsing the subtask subgroup first if currently expanded.
  void _startExitTransition(_TaskExitAction action) {
    if (_exitAction != null) {
      return;
    }
    final subtaskValue = _subtaskController.value;
    _subtaskController.stop();
    final timing = computeSubtaskExitStageTiming(
      exitDuration: _taskExitDuration,
      subtaskProgress: subtaskValue,
    );
    setState(() {
      _exitAction = action;
      _isExpanded = false;
      _exitInitialSubtaskValue = subtaskValue;
      _exitStage1Fraction = timing.stage1Fraction;
    });
    _exitController.duration = timing.totalDuration;
    _exitController.forward(from: 0.0);
  }

  /// Toggles the expanded state of the task's details section.
  void _toggleExpanded() {
    if (_exitAction != null) {
      return;
    }
    setState(() => _isExpanded = !_isExpanded);
    animateSubtaskSectionToggle(
      _subtaskController,
      isExpanded: _isExpanded,
      taskId: widget.task.id,
    );
  }
}
