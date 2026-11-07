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
import '../../models/task_item.dart';
import '../app_theme.dart';
import 'clearable_text_field.dart';
import 'task_editor_sections.dart';

/// Search-driven multi-select prerequisite task (`blocked`) card inside the task editor.
class TaskEditorBlockedBySection extends StatelessWidget {
  /// Creates a [TaskEditorBlockedBySection].
  const TaskEditorBlockedBySection({
    super.key,
    required this.candidateTasks,
    required this.disabledTaskIds,
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
            _buildSelectedChips(appTheme, selectedTasks),
            const SizedBox(height: 10),
          ],
          _TaskEditorBlockedSearchField(
            controller: searchController,
            onClear: onClearSearch,
          ),
          if (trimmedQuery.isNotEmpty)
            _buildSuggestionsList(localizations, appTheme, trimmedQuery),
        ],
      ),
    );
  }

  /// Builds the chip wrap for currently selected prerequisite tasks.
  Widget _buildSelectedChips(AppTheme appTheme, List<TaskItem> selectedTasks) {
    return Wrap(
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

  /// Callback to toggle completion of the subtask step at the given index, or `null` when locked.
  final ValueChanged<int>? onToggleSubtaskStep;

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
    final toggleCallback = onToggleSubtaskStep;
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
              onToggle: toggleCallback != null ? () => toggleCallback(i) : null,
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

/// Search field for filtering prerequisite tasks by name inside [TaskEditorBlockedBySection].
class _TaskEditorBlockedSearchField extends StatelessWidget {
  /// Creates a [_TaskEditorBlockedSearchField].
  const _TaskEditorBlockedSearchField({
    required this.controller,
    required this.onClear,
  });

  /// Controller for the prerequisite search query.
  final TextEditingController controller;

  /// Callback invoked when the clear button is tapped.
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    return ClearableTextField(
      fieldKey: const ValueKey('task_editor_blocked_search_input'),
      clearButtonKey: const ValueKey('task_editor_blocked_search_clear_button'),
      clearTooltip: localizations.tooltipClearSearch,
      clearIconColor: appTheme.mutedTextColor,
      showClearWhenUnfocused: true,
      onCleared: onClear,
      controller: controller,
      cursorColor: appTheme.warningAccent,
      style: TextStyle(color: appTheme.primaryTextColor, fontSize: 14),
      decoration: _buildDecoration(localizations, appTheme),
    );
  }

  /// Builds the [InputDecoration] for the prerequisite search field.
  InputDecoration _buildDecoration(
    AppLocalizations localizations,
    AppTheme appTheme,
  ) {
    final borderRadius = BorderRadius.circular(14);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(
        color: appTheme.mutedTextColor.withValues(alpha: 0.35),
      ),
    );
    return InputDecoration(
      hintText: localizations.blockedBySearchHint,
      hintStyle: TextStyle(color: appTheme.mutedTextColor),
      prefixIcon: Icon(
        Icons.search_rounded,
        size: 18,
        color: appTheme.mutedTextColor,
      ),
      isDense: true,
      filled: true,
      fillColor: appTheme.canvasColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: defaultBorder,
      enabledBorder: defaultBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: appTheme.warningAccent, width: 1.6),
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
    return Row(
      children: [
        Expanded(child: _buildSubtaskTextField(localizations, appTheme)),
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

  /// Builds the clearable text field for the subtask input row.
  Widget _buildSubtaskTextField(
    AppLocalizations localizations,
    AppTheme appTheme,
  ) {
    final borderRadius = BorderRadius.circular(14);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(
        color: appTheme.mutedTextColor.withValues(alpha: 0.35),
      ),
    );
    return ClearableTextField(
      fieldKey: const ValueKey('task_editor_subtask_input'),
      controller: controller,
      cursorColor: appTheme.tertiaryAccent,
      clearIconColor: appTheme.mutedTextColor,
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
          borderSide: BorderSide(color: appTheme.tertiaryAccent, width: 1.6),
        ),
      ),
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

  /// Callback to toggle completion of this subtask, or `null` when locked.
  final VoidCallback? onToggle;

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
          _buildCompletionToggle(appTheme),
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

  /// Builds the leading completion status icon button for [subtask].
  Widget _buildCompletionToggle(AppTheme appTheme) {
    return InkWell(
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
    );
  }
}
