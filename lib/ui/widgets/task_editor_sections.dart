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
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('task_editor_cancel_button'),
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded),
            label: Text(localizations.actionCancel),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            key: const ValueKey('task_editor_save_button'),
            onPressed: onSave,
            icon: const Icon(Icons.save_outlined),
            label: Text(localizations.actionSave),
          ),
        ),
      ],
    );
  }
}

/// Search-driven multi-select prerequisite task (`blocked`) card inside the task editor.
class TaskEditorBlockedBySection extends StatelessWidget {
  /// Creates a [TaskEditorBlockedBySection].
  const TaskEditorBlockedBySection({
    super.key,
    required this.candidateTasks,
    required this.disabledTaskIds,
    required this.hasSearchText,
    required this.searchController,
    required this.searchQuery,
    required this.selectedBlockedByIds,
    required this.onClearSearch,
    required this.onToggleBlockedBy,
  });

  /// Open tasks that can be referenced as prerequisites.
  final List<TaskItem> candidateTasks;

  /// Task IDs that cannot be selected because they would create a dependency cycle.
  final Set<String> disabledTaskIds;

  /// Whether the search input currently contains non-empty text.
  final bool hasSearchText;

  /// Callback invoked to clear the prerequisite search field.
  final VoidCallback onClearSearch;

  /// Callback invoked when a prerequisite task chip is tapped.
  final ValueChanged<String> onToggleBlockedBy;

  /// Controller for the prerequisite task name search input.
  final TextEditingController searchController;

  /// Current prerequisite task search query.
  final String searchQuery;

  /// Currently selected prerequisite task IDs.
  final Set<String> selectedBlockedByIds;

  @override
  Widget build(BuildContext context) {
    if (candidateTasks.isEmpty) {
      return const SizedBox.shrink();
    }
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    final selectedTasks = _collectSelectedTasks();
    final trimmedQuery = searchQuery.trim();

    return TaskEditorSectionCard(
      cardKey: const ValueKey('task_editor_blocked_card'),
      icon: Icons.lock_outline_rounded,
      title: localizations.taskBlockedBySectionTitle,
      description: localizations.taskBlockedBySectionDescription,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (selectedTasks.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final selected in selectedTasks)
                  TaskEditorChip(
                    chipKey: ValueKey('task_editor_blocked_${selected.id}'),
                    icon: Icons.lock_outline_rounded,
                    label: selected.title,
                    isSelected: true,
                    accentColor: appTheme.warningAccent,
                    onTap: () => onToggleBlockedBy(selected.id),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          _TaskEditorBlockedSearchField(
            controller: searchController,
            hasText: hasSearchText,
            onClear: onClearSearch,
          ),
          if (trimmedQuery.isNotEmpty)
            _buildSuggestionsList(localizations, appTheme, trimmedQuery),
        ],
      ),
    );
  }

  /// Builds the filtered prerequisite suggestion chips for [trimmedQuery].
  Widget _buildSuggestionsList(
    AppLocalizations localizations,
    AppTheme appTheme,
    String trimmedQuery,
  ) {
    final matchingTasks = _collectMatchingUnselectedTasks(trimmedQuery);
    if (matchingTasks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          localizations.blockedBySearchNoResults,
          style: TextStyle(color: appTheme.mutedTextColor, fontSize: 12),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final candidate in matchingTasks)
            TaskEditorChip(
              chipKey: ValueKey('task_editor_blocked_${candidate.id}'),
              icon: Icons.add_link_rounded,
              label: candidate.title,
              isSelected: false,
              isEnabled: !disabledTaskIds.contains(candidate.id),
              accentColor: appTheme.warningAccent,
              onTap: () => onToggleBlockedBy(candidate.id),
            ),
        ],
      ),
    );
  }

  /// Collects unselected candidate tasks whose titles match [trimmedQuery] case-insensitively.
  List<TaskItem> _collectMatchingUnselectedTasks(String trimmedQuery) {
    final normalizedQuery = trimmedQuery.toLowerCase();
    return <TaskItem>[
      for (final candidate in candidateTasks)
        if (!selectedBlockedByIds.contains(candidate.id) &&
            candidate.title.toLowerCase().contains(normalizedQuery))
          candidate,
    ];
  }

  /// Collects currently selected prerequisite tasks in canonical board order.
  List<TaskItem> _collectSelectedTasks() {
    return <TaskItem>[
      for (final candidate in candidateTasks)
        if (selectedBlockedByIds.contains(candidate.id)) candidate,
    ];
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
            ? accentColor
            : (isEnabled ? accentColor : mutedColor.withValues(alpha: 0.4)),
      ),
      label: Text(
        label,
        style: TextStyle(
          color: isSelected
              ? colorScheme.onSurface
              : (isEnabled ? mutedColor : mutedColor.withValues(alpha: 0.4)),
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      backgroundColor: canvasColor,
      disabledColor: canvasColor.withValues(alpha: 0.5),
      selectedColor: accentColor.withValues(alpha: 0.22),
      side: BorderSide(
        color: isSelected
            ? accentColor
            : mutedColor.withValues(alpha: isEnabled ? 0.35 : 0.15),
      ),
      onSelected: isEnabled ? (_) => onTap() : null,
    );
  }
}

/// Multi-select label chip card inside the task editor.
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
    return TaskEditorSectionCard(
      cardKey: const ValueKey('task_editor_labels_card'),
      icon: Icons.label_outline_rounded,
      title: localizations.taskLabelsSectionTitle,
      child: Wrap(
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
    );
  }

  /// Resolves a `#RRGGBB` color string or falls back to [fallback].
  Color _resolveColor(String? rawHex, Color fallback) {
    final parsed = TdfColor.tryParseArgb(rawHex);
    return parsed != null ? Color(parsed) : fallback;
  }
}

/// Card grouping the task title and optional note fields inside the task editor.
class TaskEditorDetailsCard extends StatelessWidget {
  /// Creates a [TaskEditorDetailsCard].
  const TaskEditorDetailsCard({
    super.key,
    required this.errorMessage,
    required this.noteController,
    required this.titleController,
    required this.onSubmit,
  });

  /// Optional validation error message for the task title.
  final String? errorMessage;

  ///Controller for the optional task note input.
  final TextEditingController noteController;

  /// Callback invoked when submitting from the title input field.
  final VoidCallback onSubmit;

  /// Controller for the task title input.
  final TextEditingController titleController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return TaskEditorSectionCard(
      cardKey: const ValueKey('task_editor_details_card'),
      icon: Icons.edit_note_rounded,
      title: localizations.taskDetailsSectionTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TaskEditorTitleField(
            controller: titleController,
            errorMessage: errorMessage,
            onSubmit: onSubmit,
          ),
          const SizedBox(height: 8),
          TaskEditorNoteField(controller: noteController),
        ],
      ),
    );
  }
}

/// Row of Priority, Someday, Suspended, and Repeat chips inside the task editor.
class TaskEditorModeRow extends StatelessWidget {
  /// Creates a [TaskEditorModeRow].
  const TaskEditorModeRow({
    super.key,
    required this.isRepeating,
    required this.isSuspended,
    required this.mode,
    required this.onTogglePriority,
    required this.onToggleRepeat,
    required this.onToggleSomeday,
    required this.onToggleSuspended,
  });

  /// Whether the task has recurrence enabled.
  final bool isRepeating;

  /// Whether the task is marked as suspended.
  final bool isSuspended;

  /// Active scheduling mode.
  final QuickAddMode mode;

  /// Callback invoked when Priority is tapped.
  final VoidCallback onTogglePriority;

  /// Callback invoked when Repeat is tapped.
  final VoidCallback onToggleRepeat;

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
        TaskEditorChip(
          chipKey: const ValueKey('task_editor_repeat_button'),
          icon: Icons.repeat_rounded,
          label: localizations.repeatFlagLabel,
          isSelected: isRepeating,
          accentColor: appTheme.tertiaryAccent,
          onTap: onToggleRepeat,
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
      maxLines: 3,
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

/// Recurrence interval (`repeat <count> <days|weeks|months>`) input row inside the task editor.
class TaskEditorRepeatField extends StatelessWidget {
  /// Creates a [TaskEditorRepeatField].
  const TaskEditorRepeatField({
    super.key,
    required this.countController,
    required this.errorMessage,
    required this.onSelectUnit,
    required this.selectedUnit,
  });

  /// Controller for the numeric repeat interval count (`1..3650`).
  final TextEditingController countController;

  /// Optional validation error message for the repeat interval count.
  final String? errorMessage;

  /// Callback invoked when a [RepeatUnit] chip is selected.
  final ValueChanged<RepeatUnit> onSelectUnit;

  /// Currently selected recurrence unit.
  final RepeatUnit selectedUnit;

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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('task_editor_repeat_count_input'),
          controller: countController,
          keyboardType: TextInputType.number,
          cursorColor: appTheme.tertiaryAccent,
          style: TextStyle(color: appTheme.primaryTextColor, fontSize: 14),
          decoration: InputDecoration(
            labelText: localizations.repeatIntervalLabel,
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
              borderSide: BorderSide(
                color: appTheme.tertiaryAccent,
                width: 1.6,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            TaskEditorChip(
              chipKey: const ValueKey('task_editor_repeat_unit_days'),
              icon: Icons.today_rounded,
              label: localizations.repeatUnitDays,
              isSelected: selectedUnit == RepeatUnit.days,
              accentColor: appTheme.tertiaryAccent,
              onTap: () => onSelectUnit(RepeatUnit.days),
            ),
            TaskEditorChip(
              chipKey: const ValueKey('task_editor_repeat_unit_weeks'),
              icon: Icons.date_range_rounded,
              label: localizations.repeatUnitWeeks,
              isSelected: selectedUnit == RepeatUnit.weeks,
              accentColor: appTheme.tertiaryAccent,
              onTap: () => onSelectUnit(RepeatUnit.weeks),
            ),
            TaskEditorChip(
              chipKey: const ValueKey('task_editor_repeat_unit_months'),
              icon: Icons.calendar_view_month_rounded,
              label: localizations.repeatUnitMonths,
              isSelected: selectedUnit == RepeatUnit.months,
              accentColor: appTheme.tertiaryAccent,
              onTap: () => onSelectUnit(RepeatUnit.months),
            ),
          ],
        ),
      ],
    );
  }
}

/// Card grouping the scheduling mode chips, optional `suspended` timestamp field, and optional `repeat` rule.
class TaskEditorSchedulingCard extends StatelessWidget {
  /// Creates a [TaskEditorSchedulingCard].
  const TaskEditorSchedulingCard({
    super.key,
    required this.hasSuspendedText,
    required this.isRepeating,
    required this.isSuspended,
    required this.mode,
    required this.repeatCountController,
    required this.repeatErrorMessage,
    required this.repeatUnit,
    required this.suspendedController,
    required this.suspendedErrorMessage,
    required this.onClearSuspended,
    required this.onPickSuspendedDate,
    required this.onPickSuspendedTime,
    required this.onSelectRepeatUnit,
    required this.onTogglePriority,
    required this.onToggleRepeat,
    required this.onToggleSomeday,
    required this.onToggleSuspended,
  });

  /// Whether the suspended timestamp field currently contains non-empty text.
  final bool hasSuspendedText;

  /// Whether the task has recurrence enabled.
  final bool isRepeating;

  /// Whether the task is marked as suspended.
  final bool isSuspended;

  /// Active scheduling mode.
  final QuickAddMode mode;

  /// Callback invoked to clear the suspended timestamp field.
  final VoidCallback onClearSuspended;

  /// Callback invoked to open the date picker for the suspended timestamp.
  final VoidCallback onPickSuspendedDate;

  /// Callback invoked to open the time picker for the suspended timestamp.
  final VoidCallback onPickSuspendedTime;

  /// Callback invoked when a [RepeatUnit] is selected.
  final ValueChanged<RepeatUnit> onSelectRepeatUnit;

  /// Callback invoked when Priority is tapped.
  final VoidCallback onTogglePriority;

  /// Callback invoked when Repeat is tapped.
  final VoidCallback onToggleRepeat;

  /// Callback invoked when Someday is tapped.
  final VoidCallback onToggleSomeday;

  /// Callback invoked when Suspended is tapped.
  final VoidCallback onToggleSuspended;

  /// Controller for the numeric repeat interval count.
  final TextEditingController repeatCountController;

  /// Optional validation error message for the repeat interval count.
  final String? repeatErrorMessage;

  /// Selected recurrence unit.
  final RepeatUnit repeatUnit;

  /// Controller for the optional `suspended` timestamp input.
  final TextEditingController suspendedController;

  /// Optional validation error message for the suspended timestamp.
  final String? suspendedErrorMessage;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return TaskEditorSectionCard(
      cardKey: const ValueKey('task_editor_scheduling_card'),
      icon: Icons.tune_rounded,
      title: localizations.taskSchedulingSectionTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TaskEditorModeRow(
            isRepeating: isRepeating,
            isSuspended: isSuspended,
            mode: mode,
            onTogglePriority: onTogglePriority,
            onToggleRepeat: onToggleRepeat,
            onToggleSomeday: onToggleSomeday,
            onToggleSuspended: onToggleSuspended,
          ),
          if (isSuspended) ...[
            const SizedBox(height: 8),
            TaskEditorSuspendedField(
              controller: suspendedController,
              errorMessage: suspendedErrorMessage,
              hasText: hasSuspendedText,
              onClear: onClearSuspended,
              onPickDate: onPickSuspendedDate,
              onPickTime: onPickSuspendedTime,
            ),
          ],
          if (isRepeating) ...[
            const SizedBox(height: 8),
            TaskEditorRepeatField(
              countController: repeatCountController,
              errorMessage: repeatErrorMessage,
              selectedUnit: repeatUnit,
              onSelectUnit: onSelectRepeatUnit,
            ),
          ],
        ],
      ),
    );
  }
}

/// Shared Material 3 card container matching the section groupings on `SettingsScreen`.
class TaskEditorSectionCard extends StatelessWidget {
  /// Creates a [TaskEditorSectionCard].
  const TaskEditorSectionCard({
    super.key,
    required this.cardKey,
    required this.icon,
    required this.title,
    this.description,
    this.child,
    this.trailing,
  });

  /// Deterministic widget key for the card.
  final Key cardKey;

  /// Optional interactive content below the header or description.
  final Widget? child;

  /// Optional section subtitle description.
  final String? description;

  /// Leading header icon.
  final IconData icon;

  /// Section title text.
  final String title;

  /// Optional widget rendered on the right side of the header row.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bodyChild = child;
    final headerTrailing = trailing;
    final subtitleText = description;

    return Card(
      key: cardKey,
      margin: EdgeInsets.zero,
      color: theme.cardColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (headerTrailing != null) ...[
                  const SizedBox(width: 8),
                  headerTrailing,
                ],
              ],
            ),
            if (subtitleText != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitleText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (bodyChild != null) ...[const SizedBox(height: 8), bodyChild],
          ],
        ),
      ),
    );
  }
}

/// Subtasks editor card inside the task editor with `auto-finish` toggle, list, and input row.
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
    return TaskEditorSectionCard(
      cardKey: const ValueKey('task_editor_subtasks_card'),
      icon: Icons.checklist_rounded,
      title: localizations.subtasksSectionTitle,
      trailing: TaskEditorChip(
        chipKey: const ValueKey('task_editor_auto_finish_toggle'),
        icon: Icons.done_all_rounded,
        label: localizations.subtasksAutoFinishLabel,
        isSelected: subtasksAutoFinish,
        accentColor: appTheme.tertiaryAccent,
        onTap: onToggleAutoFinish,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
      ),
    );
  }
}

/// Optional `suspended` timestamp input field with modern date and time picker options.
class TaskEditorSuspendedField extends StatelessWidget {
  /// Creates a [TaskEditorSuspendedField].
  const TaskEditorSuspendedField({
    super.key,
    required this.controller,
    required this.errorMessage,
    required this.hasText,
    required this.onClear,
    required this.onPickDate,
    required this.onPickTime,
  });

  /// Controller for the optional `suspended` timestamp input.
  final TextEditingController controller;

  /// Optional validation error message.
  final String? errorMessage;

  /// Whether the input field currently contains text.
  final bool hasText;

  /// Callback invoked to clear the timestamp input.
  final VoidCallback onClear;

  /// Callback invoked to open the Material 3 date picker.
  final VoidCallback onPickDate;

  /// Callback invoked to open the Material 3 time picker.
  final VoidCallback onPickTime;

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
        suffixIcon: _buildPickerSuffixActions(localizations, appTheme),
        border: defaultBorder,
        enabledBorder: defaultBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: appTheme.warningAccent, width: 1.6),
        ),
      ),
    );
  }

  /// Builds the trailing clear, date picker, and time picker icon buttons.
  Widget _buildPickerSuffixActions(
    AppLocalizations localizations,
    AppTheme appTheme,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasText)
          IconButton(
            key: const ValueKey('task_editor_suspended_clear_button'),
            visualDensity: VisualDensity.compact,
            tooltip: localizations.tooltipClearDate,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: appTheme.mutedTextColor,
            ),
            onPressed: onClear,
          ),
        IconButton(
          key: const ValueKey('task_editor_suspended_date_picker_button'),
          visualDensity: VisualDensity.compact,
          tooltip: localizations.tooltipPickDate,
          icon: Icon(
            Icons.calendar_month_rounded,
            size: 18,
            color: appTheme.warningAccent,
          ),
          onPressed: onPickDate,
        ),
        IconButton(
          key: const ValueKey('task_editor_suspended_time_picker_button'),
          visualDensity: VisualDensity.compact,
          tooltip: localizations.tooltipPickTime,
          icon: Icon(
            Icons.access_time_rounded,
            size: 18,
            color: appTheme.warningAccent,
          ),
          onPressed: onPickTime,
        ),
      ],
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

/// Search field for filtering prerequisite tasks by name inside [TaskEditorBlockedBySection].
class _TaskEditorBlockedSearchField extends StatelessWidget {
  /// Creates a [_TaskEditorBlockedSearchField].
  const _TaskEditorBlockedSearchField({
    required this.controller,
    required this.hasText,
    required this.onClear,
  });

  /// Controller for the prerequisite search query.
  final TextEditingController controller;

  /// Whether the search query is currently non-empty.
  final bool hasText;

  /// Callback invoked when the clear button is tapped.
  final VoidCallback onClear;

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
      key: const ValueKey('task_editor_blocked_search_input'),
      controller: controller,
      cursorColor: appTheme.warningAccent,
      style: TextStyle(color: appTheme.primaryTextColor, fontSize: 14),
      decoration: InputDecoration(
        hintText: localizations.blockedBySearchHint,
        hintStyle: TextStyle(color: appTheme.mutedTextColor),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 18,
          color: appTheme.mutedTextColor,
        ),
        suffixIcon: hasText
            ? IconButton(
                key: const ValueKey('task_editor_blocked_search_clear_button'),
                visualDensity: VisualDensity.compact,
                tooltip: localizations.tooltipClearSearch,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: appTheme.mutedTextColor,
                ),
                onPressed: onClear,
              )
            : null,
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
            backgroundColor: appTheme.secondaryContainerColor,
            foregroundColor: appTheme.onSecondaryContainerColor,
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
