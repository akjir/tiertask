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

import '../../l10n/app_localizations.dart';
import '../../l10n/tier_localization_extension.dart';
import '../../models/task_item.dart';
import '../../models/task_tier.dart';
import '../../models/tdf_metadata.dart';
import '../app_theme.dart';
import 'quick_add_bar.dart';

/// Footer row inside the task editor containing Cancel and Save actions.
class TaskEditorActionsRow extends StatelessWidget {
  /// Creates a [TaskEditorActionsRow].
  const TaskEditorActionsRow({
    super.key,
    required this.onCancel,
    required this.onSave,
  });

  /// Callback invoked when Cancel is pressed.
  final VoidCallback onCancel;

  /// Callback invoked when Save is pressed.
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          key: const ValueKey('task_editor_cancel_button'),
          onPressed: onCancel,
          child: Text(localizations.actionCancel),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const ValueKey('task_editor_save_button'),
          onPressed: onSave,
          child: Text(localizations.actionSave),
        ),
      ],
    );
  }
}

/// Multi-select prerequisite task (`blocked`) chip group inside the task editor.
class TaskEditorBlockedBySection extends StatelessWidget {
  /// Creates a [TaskEditorBlockedBySection].
  const TaskEditorBlockedBySection({
    super.key,
    required this.candidateTasks,
    required this.disabledTaskIds,
    required this.selectedBlockedByIds,
    required this.onToggleBlockedBy,
  });

  /// Open tasks that can be referenced as prerequisites.
  final List<TaskItem> candidateTasks;

  /// Task IDs that cannot be selected because they would create a dependency cycle.
  final Set<String> disabledTaskIds;

  /// Callback invoked when a prerequisite task chip is tapped.
  final ValueChanged<String> onToggleBlockedBy;

  /// Currently selected prerequisite task IDs.
  final Set<String> selectedBlockedByIds;

  @override
  Widget build(BuildContext context) {
    if (candidateTasks.isEmpty) {
      return const SizedBox.shrink();
    }
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Text(
          localizations.sectionBlockedByTasks,
          style: TextStyle(
            color: appTheme.mutedTextColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final candidate in candidateTasks)
              TaskEditorChip(
                chipKey: ValueKey('task_editor_blocked_${candidate.id}'),
                icon: Icons.lock_outline_rounded,
                label: candidate.title,
                isSelected: selectedBlockedByIds.contains(candidate.id),
                isEnabled: !disabledTaskIds.contains(candidate.id),
                accentColor: appTheme.warningAccent,
                onTap: () => onToggleBlockedBy(candidate.id),
              ),
          ],
        ),
      ],
    );
  }
}

/// Selectable chip used for labels, prerequisites, conditions, and mode toggles inside the task editor.
class TaskEditorChip extends StatelessWidget {
  /// Creates a [TaskEditorChip].
  const TaskEditorChip({
    super.key,
    required this.accentColor,
    required this.chipKey,
    required this.icon,
    required this.isSelected,
    required this.label,
    required this.onTap,
    this.isEnabled = true,
  });

  /// Highlight color when selected.
  final Color accentColor;

  /// Deterministic widget key for the chip.
  final Key chipKey;

  /// Leading icon displayed inside the chip.
  final IconData icon;

  /// Whether this chip accepts user interaction.
  final bool isEnabled;

  /// Whether this chip is currently active.
  final bool isSelected;

  /// Text label displayed inside the chip.
  final String label;

  /// Callback invoked when the chip is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mutedColor = colorScheme.onSurfaceVariant;
    final canvasColor = theme.scaffoldBackgroundColor;

    return FilterChip(
      key: chipKey,
      selected: isSelected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected
            ? colorScheme.onPrimary
            : (isEnabled ? accentColor : mutedColor.withValues(alpha: 0.4)),
      ),
      label: Text(
        label,
        style: TextStyle(
          color: isSelected
              ? colorScheme.onPrimary
              : (isEnabled ? mutedColor : mutedColor.withValues(alpha: 0.4)),
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      backgroundColor: canvasColor,
      disabledColor: canvasColor.withValues(alpha: 0.5),
      selectedColor: accentColor,
      side: BorderSide(
        color: isSelected
            ? accentColor
            : mutedColor.withValues(alpha: isEnabled ? 0.35 : 0.15),
      ),
      onSelected: isEnabled ? (_) => onTap() : null,
    );
  }
}

/// Multi-select label chip group inside the task editor.
class TaskEditorContextSection extends StatelessWidget {
  /// Creates a [TaskEditorContextSection].
  const TaskEditorContextSection({
    super.key,
    required this.labels,
    required this.selectedLabelIds,
    required this.onToggleLabel,
  });

  /// Available labels on the board.
  final List<TdfLabel> labels;

  /// Callback invoked when a label chip is tapped.
  final ValueChanged<String> onToggleLabel;

  /// Selected label IDs.
  final Set<String> selectedLabelIds;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) {
      return const SizedBox.shrink();
    }
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          localizations.sectionLabels,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final label in labels)
              TaskEditorChip(
                chipKey: ValueKey('task_editor_label_${label.id}'),
                icon: Icons.label_outline_rounded,
                label: label.name,
                isSelected: selectedLabelIds.contains(label.id),
                accentColor: _resolveColor(label.color, colorScheme.primary),
                onTap: () => onToggleLabel(label.id),
              ),
          ],
        ),
      ],
    );
  }

  /// Resolves a `#RRGGBB` color string or falls back to [fallback].
  Color _resolveColor(String? rawHex, Color fallback) {
    final parsed = TdfColor.tryParseArgb(rawHex);
    return parsed != null ? Color(parsed) : fallback;
  }
}

/// Row of Priority, Someday, and Suspended chips inside the task editor.
class TaskEditorModeRow extends StatelessWidget {
  /// Creates a [TaskEditorModeRow].
  const TaskEditorModeRow({
    super.key,
    required this.isSuspended,
    required this.mode,
    required this.onTogglePriority,
    required this.onToggleSomeday,
    required this.onToggleSuspended,
  });

  /// Whether the task is marked as suspended.
  final bool isSuspended;

  /// Active scheduling mode.
  final QuickAddMode mode;

  /// Callback invoked when Priority is tapped.
  final VoidCallback onTogglePriority;

  /// Callback invoked when Someday is tapped.
  final VoidCallback onToggleSomeday;

  /// Callback invoked when Suspended is tapped.
  final VoidCallback onToggleSuspended;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        TaskEditorChip(
          chipKey: const ValueKey('task_editor_priority_button'),
          icon: Icons.bolt_rounded,
          label: localizations.quickAddPriority,
          isSelected: mode == QuickAddMode.priority,
          accentColor: appTheme.primaryAccent,
          onTap: onTogglePriority,
        ),
        TaskEditorChip(
          chipKey: const ValueKey('task_editor_someday_button'),
          icon: Icons.lightbulb_outline_rounded,
          label: localizations.tierName(TaskTier.someday),
          isSelected: mode == QuickAddMode.someday,
          accentColor: appTheme.secondaryAccent,
          onTap: onToggleSomeday,
        ),
        TaskEditorChip(
          chipKey: const ValueKey('task_editor_suspended_button'),
          icon: Icons.pause_circle_outline_rounded,
          label: localizations.taskSuspendedLabel,
          isSelected: isSuspended,
          accentColor: appTheme.warningAccent,
          onTap: onToggleSuspended,
        ),
      ],
    );
  }
}

/// Optional task note input field inside the task editor.
class TaskEditorNoteField extends StatelessWidget {
  /// Creates a [TaskEditorNoteField].
  const TaskEditorNoteField({super.key, required this.controller});

  /// Controller for the note input.
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    final borderRadius = BorderRadius.circular(14);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(
        color: appTheme.mutedTextColor.withValues(alpha: 0.35),
      ),
    );

    return TextField(
      key: const ValueKey('task_editor_note_input'),
      controller: controller,
      cursorColor: appTheme.tertiaryAccent,
      style: TextStyle(color: appTheme.primaryTextColor, fontSize: 14),
      minLines: 1,
      maxLines: 2,
      decoration: InputDecoration(
        labelText: localizations.taskNoteLabel,
        labelStyle: TextStyle(color: appTheme.mutedTextColor),
        hintText: localizations.taskNoteHint,
        hintStyle: TextStyle(color: appTheme.mutedTextColor),
        isDense: true,
        filled: true,
        fillColor: appTheme.canvasColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: defaultBorder,
        enabledBorder: defaultBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: appTheme.tertiaryAccent, width: 1.6),
        ),
      ),
    );
  }
}

/// Subtasks editor section inside the task editor with `auto-finish` toggle, list, and input row.
class TaskEditorSubtasksSection extends StatelessWidget {
  /// Creates a [TaskEditorSubtasksSection].
  const TaskEditorSubtasksSection({
    super.key,
    required this.hasSubtaskText,
    required this.subtaskController,
    required this.subtasks,
    required this.subtasksAutoFinish,
    required this.onAddSubtask,
    required this.onRemoveSubtask,
    required this.onToggleAutoFinish,
    required this.onToggleSubtaskStep,
  });

  /// Whether the subtask input field contains non-whitespace text.
  final bool hasSubtaskText;

  /// Callback to append a new subtask step.
  final VoidCallback onAddSubtask;

  /// Callback to remove the subtask step at the given index.
  final ValueChanged<int> onRemoveSubtask;

  /// Callback to toggle `subtasks auto-finish`.
  final VoidCallback onToggleAutoFinish;

  /// Callback to toggle completion of the subtask step at the given index.
  final ValueChanged<int> onToggleSubtaskStep;

  /// Controller for the subtask input field.
  final TextEditingController subtaskController;

  /// Ordered subtask steps.
  final List<SubtaskItem> subtasks;

  /// Whether `subtasks auto-finish` is enabled.
  final bool subtasksAutoFinish;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                localizations.subtasksSectionTitle,
                style: TextStyle(
                  color: appTheme.mutedTextColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TaskEditorChip(
              chipKey: const ValueKey('task_editor_auto_finish_toggle'),
              icon: Icons.done_all_rounded,
              label: localizations.subtasksAutoFinishLabel,
              isSelected: subtasksAutoFinish,
              accentColor: appTheme.tertiaryAccent,
              onTap: onToggleAutoFinish,
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < subtasks.length; i++)
          _TaskEditorSubtaskRow(
            index: i,
            subtask: subtasks[i],
            onRemove: () => onRemoveSubtask(i),
            onToggle: () => onToggleSubtaskStep(i),
          ),
        _TaskEditorSubtaskInputRow(
          controller: subtaskController,
          hasText: hasSubtaskText,
          onAddSubtask: onAddSubtask,
        ),
      ],
    );
  }
}

/// Optional `suspended` timestamp input field inside the task editor.
class TaskEditorSuspendedField extends StatelessWidget {
  /// Creates a [TaskEditorSuspendedField].
  const TaskEditorSuspendedField({
    super.key,
    required this.controller,
    required this.errorMessage,
  });

  /// Controller for the optional `suspended` timestamp input.
  final TextEditingController controller;

  /// Optional validation error message.
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    final borderRadius = BorderRadius.circular(14);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(
        color: appTheme.mutedTextColor.withValues(alpha: 0.35),
      ),
    );

    return TextField(
      key: const ValueKey('task_editor_suspended_input'),
      controller: controller,
      cursorColor: appTheme.warningAccent,
      style: TextStyle(color: appTheme.primaryTextColor, fontSize: 14),
      decoration: InputDecoration(
        labelText: localizations.taskSuspendedUntilLabel,
        labelStyle: TextStyle(color: appTheme.mutedTextColor),
        hintText: localizations.taskSuspendedUntilHint,
        hintStyle: TextStyle(color: appTheme.mutedTextColor),
        errorText: errorMessage,
        isDense: true,
        filled: true,
        fillColor: appTheme.canvasColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: defaultBorder,
        enabledBorder: defaultBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: appTheme.warningAccent, width: 1.6),
        ),
      ),
    );
  }
}

/// Task title input field with inline validation error display inside the task editor.
class TaskEditorTitleField extends StatelessWidget {
  /// Creates a [TaskEditorTitleField].
  const TaskEditorTitleField({
    super.key,
    required this.controller,
    required this.errorMessage,
    required this.onSubmit,
  });

  /// Controller for the task title input.
  final TextEditingController controller;

  /// Optional validation error message.
  final String? errorMessage;

  /// Callback invoked when the user submits from the keyboard.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    final borderRadius = BorderRadius.circular(14);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(
        color: appTheme.mutedTextColor.withValues(alpha: 0.35),
      ),
    );

    return TextField(
      key: const ValueKey('task_editor_title_input'),
      controller: controller,
      autofocus: true,
      cursorColor: appTheme.primaryAccent,
      style: TextStyle(color: appTheme.primaryTextColor, fontSize: 15),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmit(),
      decoration: InputDecoration(
        labelText: localizations.taskNameLabel,
        labelStyle: TextStyle(color: appTheme.mutedTextColor),
        errorText: errorMessage,
        isDense: true,
        filled: true,
        fillColor: appTheme.canvasColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: defaultBorder,
        enabledBorder: defaultBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: appTheme.primaryAccent, width: 1.6),
        ),
      ),
    );
  }
}

/// Input row for adding a subtask step inside [TaskEditorSubtasksSection].
class _TaskEditorSubtaskInputRow extends StatelessWidget {
  /// Creates a [_TaskEditorSubtaskInputRow].
  const _TaskEditorSubtaskInputRow({
    required this.controller,
    required this.hasText,
    required this.onAddSubtask,
  });

  /// Controller for the subtask input field.
  final TextEditingController controller;

  /// Whether the input field currently contains non-whitespace text.
  final bool hasText;

  /// Callback invoked when the add subtask button or Enter key is pressed.
  final VoidCallback onAddSubtask;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    final borderRadius = BorderRadius.circular(14);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(
        color: appTheme.mutedTextColor.withValues(alpha: 0.35),
      ),
    );

    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('task_editor_subtask_input'),
            controller: controller,
            cursorColor: appTheme.tertiaryAccent,
            style: TextStyle(color: appTheme.primaryTextColor, fontSize: 14),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onAddSubtask(),
            decoration: InputDecoration(
              hintText: localizations.subtaskInputHint,
              hintStyle: TextStyle(color: appTheme.mutedTextColor),
              isDense: true,
              filled: true,
              fillColor: appTheme.canvasColor,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: defaultBorder,
              enabledBorder: defaultBorder,
              focusedBorder: OutlineInputBorder(
                borderRadius: borderRadius,
                borderSide: BorderSide(
                  color: appTheme.tertiaryAccent,
                  width: 1.6,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          key: const ValueKey('task_editor_subtask_add_button'),
          style: IconButton.styleFrom(
            backgroundColor: appTheme.secondaryAccent,
            foregroundColor: appTheme.onSecondaryColor,
            disabledBackgroundColor: appTheme.canvasColor.withValues(
              alpha: 0.55,
            ),
            disabledForegroundColor: appTheme.mutedTextColor.withValues(
              alpha: 0.6,
            ),
          ),
          tooltip: localizations.tooltipAddSubtask,
          onPressed: hasText ? onAddSubtask : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

/// Single subtask row inside [TaskEditorSubtasksSection] with completion toggle and remove action.
class _TaskEditorSubtaskRow extends StatelessWidget {
  /// Creates a [_TaskEditorSubtaskRow].
  const _TaskEditorSubtaskRow({
    required this.index,
    required this.subtask,
    required this.onRemove,
    required this.onToggle,
  });

  /// Zero-based index of [subtask].
  final int index;

  /// Callback to remove this subtask.
  final VoidCallback onRemove;

  /// Callback to toggle completion of this subtask.
  final VoidCallback onToggle;

  /// Subtask item to display.
  final SubtaskItem subtask;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          InkWell(
            key: ValueKey('task_editor_toggle_subtask_$index'),
            borderRadius: BorderRadius.circular(12),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                subtask.isCompleted
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: subtask.isCompleted
                    ? appTheme.tertiaryAccent
                    : appTheme.mutedTextColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtask.title,
              style: TextStyle(
                color: subtask.isCompleted
                    ? appTheme.mutedTextColor
                    : appTheme.primaryTextColor,
                decoration: subtask.isCompleted
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
          ),
          IconButton(
            key: ValueKey('task_editor_remove_subtask_$index'),
            visualDensity: VisualDensity.compact,
            tooltip: localizations.tooltipRemoveSubtask,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: appTheme.mutedTextColor,
            ),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
