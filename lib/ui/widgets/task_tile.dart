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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import '../../models/task_tier.dart';
import '../../providers/task_providers.dart';
import 'restore_task_sheet.dart';

/// Material 3 task card with tier-specific quick actions and overflow menu.
class TaskTile extends ConsumerWidget {
  /// Creates a [TaskTile] for [task] inside [tier].
  const TaskTile({
    super.key,
    required this.task,
    required this.tier,
    this.isProminent = false,
  });

  /// Whether to render the card with prominent Tier 1 (`# [1] Focus`) styling.
  final bool isProminent;

  /// Task item displayed by this tile.
  final TaskItem task;

  /// Tier containing [task].
  final TaskTier tier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final notifier = ref.read(taskNotifierProvider.notifier);
    final isDone = tier == TaskTier.completed;

    return Card(
      elevation: isProminent ? 2 : 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: isProminent
          ? colorScheme.primaryContainer.withValues(alpha: 0.45)
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isProminent
              ? colorScheme.primary.withValues(alpha: 0.35)
              : colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 8,
          vertical: isProminent ? 6 : 2,
        ),
        child: Row(
          children: [
            Checkbox(
              value: isDone,
              onChanged: (_) => _toggleCompletion(context, notifier, isDone),
            ),
            Expanded(
              child: _TaskTitleColumn(
                task: task,
                isDone: isDone,
                isProminent: isProminent,
              ),
            ),
            _TaskQuickActions(task: task, tier: tier, notifier: notifier),
            _TaskOverflowMenu(task: task, notifier: notifier),
          ],
        ),
      ),
    );
  }

  /// Toggles completion or prompts for a restore destination tier.
  Future<void> _toggleCompletion(
    BuildContext context,
    TaskNotifier notifier,
    bool isDone,
  ) async {
    if (!isDone) {
      await notifier.completeTask(task.id);
      return;
    }
    final targetTier = await showRestoreTaskSheet(context, task: task);
    if (targetTier != null) {
      await notifier.restoreTask(task.id, targetTier);
    }
  }
}

/// Dialog for editing a task's title text.
class _EditTaskDialog extends StatefulWidget {
  /// Creates an [_EditTaskDialog] initialized with [initialTitle].
  const _EditTaskDialog({required this.initialTitle});

  /// Initial task title text.
  final String initialTitle;

  @override
  State<_EditTaskDialog> createState() => _EditTaskDialogState();
}

/// State for [_EditTaskDialog].
class _EditTaskDialogState extends State<_EditTaskDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(localizations.editTaskDialogTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: localizations.editTaskFieldLabel,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(localizations.actionSave),
        ),
      ],
    );
  }
}

/// Overflow popup menu for moving, editing, or deleting a task.
class _TaskOverflowMenu extends StatelessWidget {
  /// Creates a [_TaskOverflowMenu].
  const _TaskOverflowMenu({required this.task, required this.notifier});

  /// Task controller notifier.
  final TaskNotifier notifier;

  /// Target task item.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return PopupMenuButton<_TaskMenuAction>(
      tooltip: localizations.tooltipMoreActions,
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      onSelected: (action) => _handleMenuAction(context, action),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _TaskMenuAction.move,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.swap_vert_rounded),
            title: Text(localizations.menuMoveTo),
          ),
        ),
        PopupMenuItem(
          value: _TaskMenuAction.edit,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_outlined),
            title: Text(localizations.menuEditText),
          ),
        ),
        PopupMenuItem(
          value: _TaskMenuAction.delete,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline_rounded),
            title: Text(localizations.menuDelete),
          ),
        ),
      ],
    );
  }

  /// Dispatches the selected [_TaskMenuAction].
  Future<void> _handleMenuAction(
    BuildContext context,
    _TaskMenuAction action,
  ) async {
    switch (action) {
      case _TaskMenuAction.move:
        final localizations = AppLocalizations.of(context);
        final selectedTier = await showRestoreTaskSheet(
          context,
          task: task,
          title: localizations.moveTaskTitle,
        );
        if (selectedTier != null) {
          await notifier.moveTask(task.id, selectedTier);
        }
      case _TaskMenuAction.edit:
        final updatedTitle = await showDialog<String>(
          context: context,
          builder: (_) => _EditTaskDialog(initialTitle: task.title),
        );
        if (updatedTitle != null && updatedTitle.trim().isNotEmpty) {
          await notifier.editTaskTitle(task.id, updatedTitle);
        }
      case _TaskMenuAction.delete:
        await notifier.deleteTask(task.id);
    }
  }
}

/// Inline action buttons for downgrading, blocking, or promoting a task.
class _TaskQuickActions extends StatelessWidget {
  /// Creates [_TaskQuickActions].
  const _TaskQuickActions({
    required this.task,
    required this.tier,
    required this.notifier,
  });

  /// Task controller notifier.
  final TaskNotifier notifier;

  /// Target task item.
  final TaskItem task;

  /// Tier containing [task].
  final TaskTier tier;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    if (tier == TaskTier.focus || tier == TaskTier.ready) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: tier == TaskTier.focus
                ? localizations.tooltipDowngradeToReady
                : localizations.tooltipDowngradeToPlanned,
            icon: const Icon(Icons.arrow_downward_rounded, size: 20),
            onPressed: () => notifier.downgradeTask(task.id),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: localizations.tooltipBlockTask,
            icon: Icon(Icons.block_rounded, size: 20, color: colorScheme.error),
            onPressed: () => notifier.blockTask(task.id),
          ),
        ],
      );
    }

    if (tier == TaskTier.blocked || tier == TaskTier.someday) {
      return IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: localizations.tooltipPromoteToPlanned,
        icon: const Icon(Icons.arrow_upward_rounded, size: 20),
        onPressed: () => notifier.moveTask(task.id, TaskTier.planned),
      );
    }

    return const SizedBox.shrink();
  }
}

/// Displays the task title and optional completion date subtitle.
class _TaskTitleColumn extends StatelessWidget {
  /// Creates a [_TaskTitleColumn].
  const _TaskTitleColumn({
    required this.task,
    required this.isDone,
    required this.isProminent,
  });

  /// Whether the task is in the completed tier.
  final bool isDone;

  /// Whether prominent styling is active.
  final bool isProminent;

  /// Task item to display.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final localizations = AppLocalizations.of(context);
    final completedDate = task.completedAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          task.title,
          style:
              (isProminent
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.bodyLarge)
                  ?.copyWith(
                    fontWeight: isProminent ? FontWeight.w600 : FontWeight.w500,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                    color: isDone
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onSurface,
                  ),
        ),
        if (isDone && completedDate != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              localizations.completedOnDate(
                TaskItem.formatIsoDate(completedDate),
              ),
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// Actions available in [_TaskOverflowMenu].
enum _TaskMenuAction { move, edit, delete }
