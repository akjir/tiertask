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
import '../../l10n/tier_localization_extension.dart';
import '../../models/task_board.dart';
import '../../models/task_item.dart';
import '../../models/task_tier.dart';
import '../../models/tdf_metadata.dart';
import '../../providers/task_providers.dart';
import 'quick_add_bar.dart';

const Color _accentAmber = Color(0xFFFFB300);
const Color _accentBlue = Color(0xFF2196F3);
const Color _accentCyan = Color(0xFF00E5FF);
const Color _accentMagenta = Color(0xFFEB06FF);
const Color _canvasColor = Color(0xFF344FA1);
const Color _cardColor = Color(0xFF071A52);
const Color _mutedLabelColor = Color(0xFF9BA8E5);

/// Shared modal dialog used for both extended task creation and editing an existing task.
class TaskEditorDialog extends ConsumerStatefulWidget {
  /// Creates a [TaskEditorDialog].
  const TaskEditorDialog({
    super.key,
    this.initialTask,
    this.initialTitle = '',
    this.initialMode = QuickAddMode.standard,
    this.initialLabelIds = const <String>{},
    this.onSubmitted,
  });

  /// Initial label IDs pre-selected when opening in creation mode.
  final Set<String> initialLabelIds;

  /// Initial scheduling mode when opening in creation mode.
  final QuickAddMode initialMode;

  /// Existing task to edit, or `null` when creating a new task.
  final TaskItem? initialTask;

  /// Initial draft title when opening in creation mode.
  final String initialTitle;

  /// Optional callback invoked after a task is created or updated.
  final VoidCallback? onSubmitted;

  @override
  ConsumerState<TaskEditorDialog> createState() => _TaskEditorDialogState();
}

/// Footer row inside [TaskEditorDialog] containing Cancel and Save actions.
class _TaskEditorActionsRow extends StatelessWidget {
  /// Creates a [_TaskEditorActionsRow].
  const _TaskEditorActionsRow({required this.onCancel, required this.onSave});

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
          style: TextButton.styleFrom(foregroundColor: _mutedLabelColor),
          onPressed: onCancel,
          child: Text(localizations.actionCancel),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const ValueKey('task_editor_save_button'),
          style: FilledButton.styleFrom(
            backgroundColor: _accentMagenta,
            foregroundColor: Colors.white,
          ),
          onPressed: onSave,
          child: Text(localizations.actionSave),
        ),
      ],
    );
  }
}

/// Multi-select prerequisite task (`blocked`) chip group inside [TaskEditorDialog].
class _TaskEditorBlockedBySection extends StatelessWidget {
  /// Creates a [_TaskEditorBlockedBySection].
  const _TaskEditorBlockedBySection({
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Text(
          localizations.sectionBlockedByTasks,
          style: const TextStyle(
            color: _mutedLabelColor,
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
              _TaskEditorChip(
                chipKey: ValueKey('task_editor_blocked_${candidate.id}'),
                icon: Icons.lock_outline_rounded,
                label: candidate.title,
                isSelected: selectedBlockedByIds.contains(candidate.id),
                isEnabled: !disabledTaskIds.contains(candidate.id),
                accentColor: _accentAmber,
                onTap: () => onToggleBlockedBy(candidate.id),
              ),
          ],
        ),
      ],
    );
  }
}

/// Scrollable form content inside [TaskEditorDialog].
class _TaskEditorBody extends StatelessWidget {
  /// Creates a [_TaskEditorBody].
  const _TaskEditorBody({
    required this.candidateBlockerTasks,
    required this.conditionAny,
    required this.conditionDayAny,
    required this.conditionLocationAny,
    required this.conditionTimeAny,
    required this.disabledBlockerIds,
    required this.errorMessage,
    required this.hasSubtaskText,
    required this.isSuspended,
    required this.labels,
    required this.locationErrorMessage,
    required this.locationLatController,
    required this.locationLonController,
    required this.locationRadiusController,
    required this.locationRules,
    required this.mode,
    required this.noteController,
    required this.selectedBlockedByIds,
    required this.selectedLabelIds,
    required this.selectedWeekdays,
    required this.subtaskController,
    required this.subtasks,
    required this.subtasksAutoFinish,
    required this.suspendedController,
    required this.suspendedErrorMessage,
    required this.timeEndController,
    required this.timeErrorMessage,
    required this.timeRules,
    required this.timeStartController,
    required this.titleController,
    required this.onAddLocationCondition,
    required this.onAddSubtask,
    required this.onAddTimeCondition,
    required this.onRemoveLocationCondition,
    required this.onRemoveSubtask,
    required this.onRemoveTimeCondition,
    required this.onSubmit,
    required this.onToggleAutoFinish,
    required this.onToggleBlockedBy,
    required this.onToggleConditionAny,
    required this.onToggleDayAny,
    required this.onToggleLabel,
    required this.onToggleLocationAny,
    required this.onTogglePriority,
    required this.onToggleSomeday,
    required this.onToggleSubtaskStep,
    required this.onToggleSuspended,
    required this.onToggleTimeAny,
    required this.onToggleWeekday,
  });

  /// Open tasks that can be selected as prerequisites.
  final List<TaskItem> candidateBlockerTasks;

  /// Whether `condition any` is active.
  final bool conditionAny;

  /// Whether `condition day any` is active.
  final bool conditionDayAny;

  /// Whether `condition location any` is active.
  final bool conditionLocationAny;

  /// Whether `condition time any` is active.
  final bool conditionTimeAny;

  /// Task IDs disabled due to dependency cycles.
  final Set<String> disabledBlockerIds;

  /// Validation error message for the task title, or `null` when valid.
  final String? errorMessage;

  /// Whether the subtask input field contains non-whitespace text.
  final bool hasSubtaskText;

  /// Whether the task is marked as suspended.
  final bool isSuspended;

  /// Available labels on the board.
  final List<TdfLabel> labels;

  /// Validation error message for GPS location input, or `null` when valid.
  final String? locationErrorMessage;

  /// Controller for GPS latitude input.
  final TextEditingController locationLatController;

  /// Controller for GPS longitude input.
  final TextEditingController locationLonController;

  /// Controller for GPS radius input.
  final TextEditingController locationRadiusController;

  /// Configured GPS location conditions.
  final List<LocationTaskCondition> locationRules;

  /// Active scheduling mode.
  final QuickAddMode mode;

  /// Controller for the optional note input field.
  final TextEditingController noteController;

  /// Callback to add a GPS location condition.
  final VoidCallback onAddLocationCondition;

  /// Callback to append a new subtask step.
  final VoidCallback onAddSubtask;

  /// Callback to add a time window condition.
  final VoidCallback onAddTimeCondition;

  /// Callback to remove the GPS location condition at the given index.
  final ValueChanged<int> onRemoveLocationCondition;

  /// Callback to remove the subtask step at the given index.
  final ValueChanged<int> onRemoveSubtask;

  /// Callback to remove the time window condition at the given index.
  final ValueChanged<int> onRemoveTimeCondition;

  /// Callback to submit the form.
  final VoidCallback onSubmit;

  /// Callback to toggle `subtasks auto-finish`.
  final VoidCallback onToggleAutoFinish;

  /// Callback to toggle a prerequisite task ID.
  final ValueChanged<String> onToggleBlockedBy;

  /// Callback to toggle `condition any`.
  final VoidCallback onToggleConditionAny;

  /// Callback to toggle `condition day any`.
  final VoidCallback onToggleDayAny;

  /// Callback to toggle selection of a label ID.
  final ValueChanged<String> onToggleLabel;

  /// Callback to toggle `condition location any`.
  final VoidCallback onToggleLocationAny;

  /// Callback to toggle Priority mode.
  final VoidCallback onTogglePriority;

  /// Callback to toggle Someday mode.
  final VoidCallback onToggleSomeday;

  /// Callback to toggle completion of the subtask step at the given index.
  final ValueChanged<int> onToggleSubtaskStep;

  /// Callback to toggle Suspended mode.
  final VoidCallback onToggleSuspended;

  /// Callback to toggle `condition time any`.
  final VoidCallback onToggleTimeAny;

  /// Callback to toggle a weekday (`1..7`) in `condition day`.
  final ValueChanged<int> onToggleWeekday;

  /// Selected prerequisite task IDs.
  final Set<String> selectedBlockedByIds;

  /// Selected label IDs.
  final Set<String> selectedLabelIds;

  /// Selected ISO weekdays (`1` = Monday .. `7` = Sunday).
  final Set<int> selectedWeekdays;

  /// Controller for the subtask input field.
  final TextEditingController subtaskController;

  /// Ordered subtask steps.
  final List<SubtaskItem> subtasks;

  /// Whether `subtasks auto-finish` is enabled.
  final bool subtasksAutoFinish;

  /// Controller for the optional `suspended` timestamp field.
  final TextEditingController suspendedController;

  /// Validation error message for the `suspended` timestamp, or `null` when valid.
  final String? suspendedErrorMessage;

  /// Controller for the end of a time window condition.
  final TextEditingController timeEndController;

  /// Validation error message for time window input, or `null` when valid.
  final String? timeErrorMessage;

  /// Configured time window conditions.
  final List<TimeWindowTaskCondition> timeRules;

  /// Controller for the start of a time window condition.
  final TextEditingController timeStartController;

  /// Controller for the task title input field.
  final TextEditingController titleController;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TaskEditorTitleField(
              controller: titleController,
              errorMessage: errorMessage,
              onSubmit: onSubmit,
            ),
            const SizedBox(height: 8),
            _TaskEditorNoteField(controller: noteController),
            const SizedBox(height: 8),
            _TaskEditorModeRow(
              isSuspended: isSuspended,
              mode: mode,
              onTogglePriority: onTogglePriority,
              onToggleSomeday: onToggleSomeday,
              onToggleSuspended: onToggleSuspended,
            ),
            if (isSuspended) ...[
              const SizedBox(height: 8),
              _TaskEditorSuspendedField(
                controller: suspendedController,
                errorMessage: suspendedErrorMessage,
              ),
            ],
            _TaskEditorContextSection(
              labels: labels,
              selectedLabelIds: selectedLabelIds,
              onToggleLabel: onToggleLabel,
            ),
            const SizedBox(height: 8),
            _TaskEditorSubtasksSection(
              hasSubtaskText: hasSubtaskText,
              subtaskController: subtaskController,
              subtasks: subtasks,
              subtasksAutoFinish: subtasksAutoFinish,
              onAddSubtask: onAddSubtask,
              onRemoveSubtask: onRemoveSubtask,
              onToggleAutoFinish: onToggleAutoFinish,
              onToggleSubtaskStep: onToggleSubtaskStep,
            ),
            _TaskEditorBlockedBySection(
              candidateTasks: candidateBlockerTasks,
              disabledTaskIds: disabledBlockerIds,
              selectedBlockedByIds: selectedBlockedByIds,
              onToggleBlockedBy: onToggleBlockedBy,
            ),
            const SizedBox(height: 10),
            _TaskEditorConditionsSection(
              conditionAny: conditionAny,
              conditionDayAny: conditionDayAny,
              conditionLocationAny: conditionLocationAny,
              conditionTimeAny: conditionTimeAny,
              isSuspended: isSuspended,
              locationErrorMessage: locationErrorMessage,
              locationLatController: locationLatController,
              locationLonController: locationLonController,
              locationRadiusController: locationRadiusController,
              locationRules: locationRules,
              selectedWeekdays: selectedWeekdays,
              timeEndController: timeEndController,
              timeErrorMessage: timeErrorMessage,
              timeRules: timeRules,
              timeStartController: timeStartController,
              onAddLocationCondition: onAddLocationCondition,
              onAddTimeCondition: onAddTimeCondition,
              onRemoveLocationCondition: onRemoveLocationCondition,
              onRemoveTimeCondition: onRemoveTimeCondition,
              onToggleConditionAny: onToggleConditionAny,
              onToggleDayAny: onToggleDayAny,
              onToggleLocationAny: onToggleLocationAny,
              onToggleTimeAny: onToggleTimeAny,
              onToggleWeekday: onToggleWeekday,
            ),
          ],
        ),
      ),
    );
  }
}

/// Selectable chip used for labels, prerequisites, conditions, and mode toggles inside [TaskEditorDialog].
class _TaskEditorChip extends StatelessWidget {
  /// Creates a [_TaskEditorChip].
  const _TaskEditorChip({
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
            ? Colors.white
            : (isEnabled
                  ? accentColor
                  : _mutedLabelColor.withValues(alpha: 0.4)),
      ),
      label: Text(
        label,
        style: TextStyle(
          color: isSelected
              ? Colors.white
              : (isEnabled
                    ? _mutedLabelColor
                    : _mutedLabelColor.withValues(alpha: 0.4)),
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      backgroundColor: _canvasColor,
      disabledColor: _canvasColor.withValues(alpha: 0.5),
      selectedColor: accentColor,
      side: BorderSide(
        color: isSelected
            ? accentColor
            : _mutedLabelColor.withValues(alpha: isEnabled ? 0.35 : 0.15),
      ),
      onSelected: isEnabled ? (_) => onTap() : null,
    );
  }
}

/// Weekday (`condition day`) editor subgroup inside [_TaskEditorConditionsSection].
class _TaskEditorConditionDaySection extends StatelessWidget {
  /// Creates a [_TaskEditorConditionDaySection].
  const _TaskEditorConditionDaySection({
    required this.conditionDayAny,
    required this.selectedWeekdays,
    required this.onToggleDayAny,
    required this.onToggleWeekday,
  });

  /// Whether `condition day any` is active.
  final bool conditionDayAny;

  /// Callback to toggle `condition day any`.
  final VoidCallback onToggleDayAny;

  /// Callback to toggle a weekday (`1..7`).
  final ValueChanged<int> onToggleWeekday;

  /// Selected ISO weekdays (`1` = Monday .. `7` = Sunday).
  final Set<int> selectedWeekdays;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final dayLabels = <int, String>{
      1: localizations.weekdayMon,
      2: localizations.weekdayTue,
      3: localizations.weekdayWed,
      4: localizations.weekdayThu,
      5: localizations.weekdayFri,
      6: localizations.weekdaySat,
      7: localizations.weekdaySun,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                localizations.conditionDayGroupTitle,
                style: const TextStyle(
                  color: _mutedLabelColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _TaskEditorChip(
              chipKey: const ValueKey('task_editor_condition_day_any_toggle'),
              icon: Icons.calendar_today_rounded,
              label: localizations.conditionDayAnyLabel,
              isSelected: conditionDayAny,
              accentColor: _accentCyan,
              onTap: onToggleDayAny,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var weekday = 1; weekday <= 7; weekday++)
              _TaskEditorChip(
                chipKey: ValueKey(
                  'task_editor_condition_day_${DayTaskCondition.canonicalTokens[weekday - 1]}',
                ),
                icon: Icons.event_available_rounded,
                label: dayLabels[weekday] ?? '',
                isSelected:
                    !conditionDayAny && selectedWeekdays.contains(weekday),
                accentColor: _accentBlue,
                onTap: () => onToggleWeekday(weekday),
              ),
          ],
        ),
      ],
    );
  }
}

/// GPS location (`condition location`) editor subgroup inside [_TaskEditorConditionsSection].
class _TaskEditorConditionLocationSection extends StatelessWidget {
  /// Creates a [_TaskEditorConditionLocationSection].
  const _TaskEditorConditionLocationSection({
    required this.conditionLocationAny,
    required this.errorMessage,
    required this.latController,
    required this.lonController,
    required this.radiusController,
    required this.rules,
    required this.onAddLocationCondition,
    required this.onRemoveLocationCondition,
    required this.onToggleLocationAny,
  });

  /// Whether `condition location any` is active.
  final bool conditionLocationAny;

  /// Validation error message for GPS input, or `null` when valid.
  final String? errorMessage;

  /// Controller for latitude input.
  final TextEditingController latController;

  /// Controller for longitude input.
  final TextEditingController lonController;

  /// Callback to add a GPS location condition.
  final VoidCallback onAddLocationCondition;

  /// Callback to remove the GPS location condition at the given index.
  final ValueChanged<int> onRemoveLocationCondition;

  /// Callback to toggle `condition location any`.
  final VoidCallback onToggleLocationAny;

  /// Controller for radius input.
  final TextEditingController radiusController;

  /// Configured GPS location conditions.
  final List<LocationTaskCondition> rules;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                localizations.conditionLocationGroupTitle,
                style: const TextStyle(
                  color: _mutedLabelColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _TaskEditorChip(
              chipKey: const ValueKey(
                'task_editor_condition_location_any_toggle',
              ),
              icon: Icons.public_rounded,
              label: localizations.conditionLocationAnyLabel,
              isSelected: conditionLocationAny,
              accentColor: _accentCyan,
              onTap: onToggleLocationAny,
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < rules.length; i++)
          _TaskEditorRuleRow(
            removeKey: ValueKey('task_editor_remove_location_condition_$i'),
            icon: Icons.place_outlined,
            label:
                '${rules[i].latitude}, ${rules[i].longitude} (${rules[i].radiusMeters}m)',
            tooltip: localizations.tooltipRemoveLocationCondition,
            onRemove: () => onRemoveLocationCondition(i),
          ),
        _TaskEditorLocationInputRow(
          latController: latController,
          lonController: lonController,
          radiusController: radiusController,
          errorMessage: errorMessage,
          onAdd: onAddLocationCondition,
        ),
      ],
    );
  }
}

/// Time window (`condition time`) editor subgroup inside [_TaskEditorConditionsSection].
class _TaskEditorConditionTimeSection extends StatelessWidget {
  /// Creates a [_TaskEditorConditionTimeSection].
  const _TaskEditorConditionTimeSection({
    required this.conditionTimeAny,
    required this.endController,
    required this.errorMessage,
    required this.rules,
    required this.startController,
    required this.onAddTimeCondition,
    required this.onRemoveTimeCondition,
    required this.onToggleTimeAny,
  });

  /// Whether `condition time any` is active.
  final bool conditionTimeAny;

  /// Controller for the end time (`HH:MM`).
  final TextEditingController endController;

  /// Validation error message for time input, or `null` when valid.
  final String? errorMessage;

  /// Callback to add a time window condition.
  final VoidCallback onAddTimeCondition;

  /// Callback to remove the time window condition at the given index.
  final ValueChanged<int> onRemoveTimeCondition;

  /// Callback to toggle `condition time any`.
  final VoidCallback onToggleTimeAny;

  /// Configured time window conditions.
  final List<TimeWindowTaskCondition> rules;

  /// Controller for the start time (`HH:MM`).
  final TextEditingController startController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                localizations.conditionTimeGroupTitle,
                style: const TextStyle(
                  color: _mutedLabelColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _TaskEditorChip(
              chipKey: const ValueKey('task_editor_condition_time_any_toggle'),
              icon: Icons.schedule_rounded,
              label: localizations.conditionTimeAnyLabel,
              isSelected: conditionTimeAny,
              accentColor: _accentCyan,
              onTap: onToggleTimeAny,
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < rules.length; i++)
          _TaskEditorRuleRow(
            removeKey: ValueKey('task_editor_remove_time_condition_$i'),
            icon: Icons.access_time_rounded,
            label: '${rules[i].startToken} - ${rules[i].endToken}',
            tooltip: localizations.tooltipRemoveTimeCondition,
            onRemove: () => onRemoveTimeCondition(i),
          ),
        _TaskEditorTimeInputRow(
          startController: startController,
          endController: endController,
          errorMessage: errorMessage,
          onAdd: onAddTimeCondition,
        ),
      ],
    );
  }
}

/// Activation conditions (`condition`) editor section inside [TaskEditorDialog].
class _TaskEditorConditionsSection extends StatelessWidget {
  /// Creates a [_TaskEditorConditionsSection].
  const _TaskEditorConditionsSection({
    required this.conditionAny,
    required this.conditionDayAny,
    required this.conditionLocationAny,
    required this.conditionTimeAny,
    required this.isSuspended,
    required this.locationErrorMessage,
    required this.locationLatController,
    required this.locationLonController,
    required this.locationRadiusController,
    required this.locationRules,
    required this.selectedWeekdays,
    required this.timeEndController,
    required this.timeErrorMessage,
    required this.timeRules,
    required this.timeStartController,
    required this.onAddLocationCondition,
    required this.onAddTimeCondition,
    required this.onRemoveLocationCondition,
    required this.onRemoveTimeCondition,
    required this.onToggleConditionAny,
    required this.onToggleDayAny,
    required this.onToggleLocationAny,
    required this.onToggleTimeAny,
    required this.onToggleWeekday,
  });

  /// Whether `condition any` is active.
  final bool conditionAny;

  /// Whether `condition day any` is active.
  final bool conditionDayAny;

  /// Whether `condition location any` is active.
  final bool conditionLocationAny;

  /// Whether `condition time any` is active.
  final bool conditionTimeAny;

  /// Whether the task is suspended (disabling condition evaluation and editing).
  final bool isSuspended;

  /// Validation error message for GPS location input, or `null` when valid.
  final String? locationErrorMessage;

  /// Controller for GPS latitude input.
  final TextEditingController locationLatController;

  /// Controller for GPS longitude input.
  final TextEditingController locationLonController;

  /// Controller for GPS radius input.
  final TextEditingController locationRadiusController;

  /// Configured GPS location conditions.
  final List<LocationTaskCondition> locationRules;

  /// Callback to add a GPS location condition.
  final VoidCallback onAddLocationCondition;

  /// Callback to add a time window condition.
  final VoidCallback onAddTimeCondition;

  /// Callback to remove the GPS location condition at the given index.
  final ValueChanged<int> onRemoveLocationCondition;

  /// Callback to remove the time window condition at the given index.
  final ValueChanged<int> onRemoveTimeCondition;

  /// Callback to toggle `condition any`.
  final VoidCallback onToggleConditionAny;

  /// Callback to toggle `condition day any`.
  final VoidCallback onToggleDayAny;

  /// Callback to toggle `condition location any`.
  final VoidCallback onToggleLocationAny;

  /// Callback to toggle `condition time any`.
  final VoidCallback onToggleTimeAny;

  /// Callback to toggle a weekday (`1..7`).
  final ValueChanged<int> onToggleWeekday;

  /// Selected ISO weekdays (`1` = Monday .. `7` = Sunday).
  final Set<int> selectedWeekdays;

  /// Controller for the end of a time window condition.
  final TextEditingController timeEndController;

  /// Validation error message for time window input, or `null` when valid.
  final String? timeErrorMessage;

  /// Configured time window conditions.
  final List<TimeWindowTaskCondition> timeRules;

  /// Controller for the start of a time window condition.
  final TextEditingController timeStartController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.sectionTaskConditions,
          style: const TextStyle(
            color: _mutedLabelColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        if (isSuspended) ...[
          const SizedBox(height: 6),
          Text(
            localizations.taskSuspendedDisablesConditionsHint,
            key: const ValueKey('task_editor_conditions_disabled_hint'),
            style: const TextStyle(color: _accentAmber, fontSize: 12),
          ),
        ],
        const SizedBox(height: 6),
        IgnorePointer(
          ignoring: isSuspended,
          child: Opacity(
            opacity: isSuspended ? 0.45 : 1.0,
            child: _buildConditionControls(localizations),
          ),
        ),
      ],
    );
  }

  /// Builds the interactive condition controls inside [_TaskEditorConditionsSection].
  Widget _buildConditionControls(AppLocalizations localizations) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TaskEditorChip(
          chipKey: const ValueKey('task_editor_condition_any_toggle'),
          icon: Icons.filter_alt_off_rounded,
          label: localizations.conditionGlobalAnyLabel,
          isSelected: conditionAny,
          accentColor: _accentMagenta,
          onTap: onToggleConditionAny,
        ),
        const SizedBox(height: 8),
        _TaskEditorConditionDaySection(
          conditionDayAny: conditionDayAny,
          selectedWeekdays: selectedWeekdays,
          onToggleDayAny: onToggleDayAny,
          onToggleWeekday: onToggleWeekday,
        ),
        const SizedBox(height: 8),
        _TaskEditorConditionTimeSection(
          conditionTimeAny: conditionTimeAny,
          startController: timeStartController,
          endController: timeEndController,
          errorMessage: timeErrorMessage,
          rules: timeRules,
          onAddTimeCondition: onAddTimeCondition,
          onRemoveTimeCondition: onRemoveTimeCondition,
          onToggleTimeAny: onToggleTimeAny,
        ),
        const SizedBox(height: 8),
        _TaskEditorConditionLocationSection(
          conditionLocationAny: conditionLocationAny,
          latController: locationLatController,
          lonController: locationLonController,
          radiusController: locationRadiusController,
          errorMessage: locationErrorMessage,
          rules: locationRules,
          onAddLocationCondition: onAddLocationCondition,
          onRemoveLocationCondition: onRemoveLocationCondition,
          onToggleLocationAny: onToggleLocationAny,
        ),
      ],
    );
  }
}

/// Multi-select label chip group inside [TaskEditorDialog].
class _TaskEditorContextSection extends StatelessWidget {
  /// Creates a [_TaskEditorContextSection].
  const _TaskEditorContextSection({
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          localizations.sectionLabels,
          style: const TextStyle(
            color: _mutedLabelColor,
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
              _TaskEditorChip(
                chipKey: ValueKey('task_editor_label_${label.id}'),
                icon: Icons.label_outline_rounded,
                label: label.name,
                isSelected: selectedLabelIds.contains(label.id),
                accentColor: _resolveColor(label.color, _accentMagenta),
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

/// State for [TaskEditorDialog].
class _TaskEditorDialogState extends ConsumerState<TaskEditorDialog> {
  late final Set<String> _blockedByTaskIds;
  late bool _conditionAny;
  late bool _conditionDayAny;
  late bool _conditionLocationAny;
  late bool _conditionTimeAny;
  String? _errorMessage;
  late bool _isSuspended;
  String? _locationErrorMessage;
  final TextEditingController _locationLatController = TextEditingController();
  final TextEditingController _locationLonController = TextEditingController();
  final TextEditingController _locationRadiusController =
      TextEditingController();
  late final List<LocationTaskCondition> _locationRules;
  late QuickAddMode _mode;
  late final TextEditingController _noteController;
  late final Set<String> _selectedLabelIds;
  late final Set<int> _selectedWeekdays;
  final TextEditingController _subtaskController = TextEditingController();
  late final List<SubtaskItem> _subtasks;
  late bool _subtasksAutoFinish;
  late final TextEditingController _suspendedController;
  String? _suspendedErrorMessage;
  final TextEditingController _timeEndController = TextEditingController();
  String? _timeErrorMessage;
  late final List<TimeWindowTaskCondition> _timeRules;
  final TextEditingController _timeStartController = TextEditingController();
  late final TextEditingController _titleController;

  bool get _hasSubtaskText => _subtaskController.text.trim().isNotEmpty;

  bool get _isEditMode => widget.initialTask != null;

  @override
  void initState() {
    super.initState();
    final task = widget.initialTask;
    _titleController = TextEditingController(
      text: task?.title ?? widget.initialTitle,
    );
    _noteController = TextEditingController(text: task?.note ?? '');
    _mode = task != null ? _resolveInitialMode(task) : widget.initialMode;
    _selectedLabelIds = <String>{
      ...(task != null ? task.labelIds : widget.initialLabelIds),
    };
    _subtasksAutoFinish = task?.subtasksAutoFinish ?? false;
    _subtasks = <SubtaskItem>[if (task != null) ...task.subtasks];
    _blockedByTaskIds = <String>{if (task != null) ...task.blockedByTaskIds};
    _isSuspended = task?.suspendedAt != null;
    _suspendedController = TextEditingController(
      text: _formatInitialSuspendedText(task?.suspendedAt),
    );
    _initializeConditions(task?.conditions ?? const []);

    _titleController.addListener(_handleTitleChanged);
    _subtaskController.addListener(_handleSubtaskInputChanged);
  }

  @override
  void dispose() {
    _titleController.removeListener(_handleTitleChanged);
    _subtaskController.removeListener(_handleSubtaskInputChanged);
    _titleController.dispose();
    _noteController.dispose();
    _subtaskController.dispose();
    _suspendedController.dispose();
    _timeStartController.dispose();
    _timeEndController.dispose();
    _locationLatController.dispose();
    _locationLonController.dispose();
    _locationRadiusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final board =
        ref.watch(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    final localizations = AppLocalizations.of(context);
    final headerTitle = _isEditMode
        ? localizations.editTaskTitle
        : localizations.advancedTaskTitle;

    return Dialog(
      key: const ValueKey('task_editor_dialog'),
      backgroundColor: _cardColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: _canvasColor, width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TaskEditorHeader(
                title: headerTitle,
                onClose: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 8),
              _buildDialogBody(board),
              const SizedBox(height: 12),
              _TaskEditorActionsRow(
                onCancel: () => Navigator.of(context).pop(),
                onSave: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Validates and appends a GPS location condition from the location input controllers.
  void _addLocationCondition() {
    if (_isSuspended) {
      return;
    }
    final localizations = AppLocalizations.of(context);
    final parsed = LocationTaskCondition.tryParse(
      _locationLatController.text,
      _locationLonController.text,
      _locationRadiusController.text,
    );
    if (parsed == null) {
      setState(() {
        _locationErrorMessage = localizations.conditionLocationErrorInvalid;
      });
      return;
    }
    setState(() {
      _conditionAny = false;
      _conditionLocationAny = false;
      if (!_locationRules.contains(parsed)) {
        _locationRules.add(parsed);
      }
      _locationLatController.clear();
      _locationLonController.clear();
      _locationRadiusController.clear();
      _locationErrorMessage = null;
    });
  }

  /// Appends the current non-empty subtask text to [_subtasks].
  void _addSubtask() {
    final text = _subtaskController.text.trim();
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _subtasks.add(SubtaskItem(title: text));
      _subtaskController.clear();
    });
  }

  /// Validates and appends a time window condition from the time input controllers.
  void _addTimeCondition() {
    if (_isSuspended) {
      return;
    }
    final localizations = AppLocalizations.of(context);
    final parsed = TimeWindowTaskCondition.tryParse(
      _timeStartController.text,
      _timeEndController.text,
    );
    if (parsed == null) {
      setState(() {
        _timeErrorMessage = localizations.conditionTimeErrorInvalid;
      });
      return;
    }
    setState(() {
      _conditionAny = false;
      _conditionTimeAny = false;
      if (!_timeRules.contains(parsed)) {
        _timeRules.add(parsed);
      }
      _timeStartController.clear();
      _timeEndController.clear();
      _timeErrorMessage = null;
    });
  }

  /// Builds the scrollable [_TaskEditorBody] with derived prerequisite candidates.
  Widget _buildDialogBody(TaskBoard board) {
    final candidateTasks = _collectCandidateBlockerTasks(board);
    final disabledIds = _collectDisabledBlockerIds(board, candidateTasks);
    return _TaskEditorBody(
      candidateBlockerTasks: candidateTasks,
      conditionAny: _conditionAny,
      conditionDayAny: _conditionDayAny,
      conditionLocationAny: _conditionLocationAny,
      conditionTimeAny: _conditionTimeAny,
      disabledBlockerIds: disabledIds,
      errorMessage: _errorMessage,
      hasSubtaskText: _hasSubtaskText,
      isSuspended: _isSuspended,
      labels: board.labels,
      locationErrorMessage: _locationErrorMessage,
      locationLatController: _locationLatController,
      locationLonController: _locationLonController,
      locationRadiusController: _locationRadiusController,
      locationRules: _locationRules,
      mode: _mode,
      noteController: _noteController,
      selectedBlockedByIds: _blockedByTaskIds,
      selectedLabelIds: _selectedLabelIds,
      selectedWeekdays: _selectedWeekdays,
      subtaskController: _subtaskController,
      subtasks: _subtasks,
      subtasksAutoFinish: _subtasksAutoFinish,
      suspendedController: _suspendedController,
      suspendedErrorMessage: _suspendedErrorMessage,
      timeEndController: _timeEndController,
      timeErrorMessage: _timeErrorMessage,
      timeRules: _timeRules,
      timeStartController: _timeStartController,
      titleController: _titleController,
      onAddLocationCondition: _addLocationCondition,
      onAddSubtask: _addSubtask,
      onAddTimeCondition: _addTimeCondition,
      onRemoveLocationCondition: _removeLocationCondition,
      onRemoveSubtask: _removeSubtask,
      onRemoveTimeCondition: _removeTimeCondition,
      onSubmit: _submit,
      onToggleAutoFinish: _toggleAutoFinish,
      onToggleBlockedBy: (taskId) => _toggleBlockedBy(board, taskId),
      onToggleConditionAny: _toggleConditionAny,
      onToggleDayAny: _toggleDayAny,
      onToggleLabel: _toggleLabel,
      onToggleLocationAny: _toggleLocationAny,
      onTogglePriority: _togglePriority,
      onToggleSomeday: _toggleSomeday,
      onToggleSubtaskStep: _toggleSubtaskStep,
      onToggleSuspended: _toggleSuspended,
      onToggleTimeAny: _toggleTimeAny,
      onToggleWeekday: _toggleWeekday,
    );
  }

  /// Collects open tasks on [board] that can be displayed in the prerequisites section.
  List<TaskItem> _collectCandidateBlockerTasks(TaskBoard board) {
    final currentId = widget.initialTask?.id;
    return <TaskItem>[
      for (final task in board.allTasks)
        if (task.id != currentId &&
            ((!task.isCompleted && task.completedAt == null) ||
                _blockedByTaskIds.contains(task.id)))
          task,
    ];
  }

  /// Collects candidate prerequisite task IDs that would create a dependency cycle.
  Set<String> _collectDisabledBlockerIds(
    TaskBoard board,
    List<TaskItem> candidates,
  ) {
    final currentTask = widget.initialTask;
    if (currentTask == null) {
      return const <String>{};
    }
    return <String>{
      for (final candidate in candidates)
        if (board.wouldCreateDependencyCycle(currentTask.id, candidate.id))
          candidate.id,
    };
  }

  /// Collects selected prerequisite task IDs in canonical board declaration order.
  List<String> _collectOrderedBlockedByIds(TaskBoard board) {
    return <String>[
      for (final task in board.allTasks)
        if (_blockedByTaskIds.contains(task.id)) task.id,
    ];
  }

  /// Collects selected label IDs in canonical board declaration order.
  List<String> _collectOrderedLabelIds(TaskBoard board) {
    return <String>[
      for (final label in board.labels)
        if (_selectedLabelIds.contains(label.id)) label.id,
    ];
  }

  /// Assembles the ordered [TaskCondition] list from the editor state.
  List<TaskCondition> _collectTaskConditions() {
    if (_conditionAny) {
      return const <TaskCondition>[GlobalResetTaskCondition()];
    }
    return <TaskCondition>[
      if (_conditionDayAny)
        const GroupResetTaskCondition(targetGroup: ConditionGroup.day)
      else if (_selectedWeekdays.isNotEmpty)
        DayTaskCondition.fromWeekdays(_selectedWeekdays),
      if (_conditionTimeAny)
        const GroupResetTaskCondition(targetGroup: ConditionGroup.time)
      else
        ..._timeRules,
      if (_conditionLocationAny)
        const GroupResetTaskCondition(targetGroup: ConditionGroup.location)
      else
        ..._locationRules,
    ];
  }

  /// Formats an initial `suspended` timestamp for the input field (omitting `defaultSuspendedAt`).
  static String _formatInitialSuspendedText(DateTime? suspendedAt) {
    if (suspendedAt == null || suspendedAt == TaskItem.defaultSuspendedAt) {
      return '';
    }
    return TaskItem.formatTdfTimestamp(suspendedAt);
  }

  /// Rebuilds when the subtask input field text changes.
  void _handleSubtaskInputChanged() {
    setState(() {});
  }

  /// Clears any validation error when the user edits the title field.
  void _handleTitleChanged() {
    if (_errorMessage == null) {
      return;
    }
    setState(() {
      _errorMessage = null;
    });
  }

  /// Initializes the condition state fields from [initialConditions].
  void _initializeConditions(List<TaskCondition> initialConditions) {
    _conditionAny = false;
    _conditionDayAny = false;
    _conditionTimeAny = false;
    _conditionLocationAny = false;
    _selectedWeekdays = <int>{};
    _timeRules = <TimeWindowTaskCondition>[];
    _locationRules = <LocationTaskCondition>[];

    for (final condition in initialConditions) {
      switch (condition) {
        case GlobalResetTaskCondition():
          _conditionAny = true;
        case GroupResetTaskCondition(:final targetGroup):
          if (targetGroup == ConditionGroup.day) {
            _conditionDayAny = true;
          } else if (targetGroup == ConditionGroup.time) {
            _conditionTimeAny = true;
          } else {
            _conditionLocationAny = true;
          }
        case DayTaskCondition(:final weekdays):
          _selectedWeekdays.addAll(weekdays);
        case TimeWindowTaskCondition():
          _timeRules.add(condition);
        case LocationTaskCondition():
          _locationRules.add(condition);
      }
    }
  }

  /// Persists the created or edited task through [TaskNotifier].
  Future<void> _persistTask(
    TaskBoard board,
    String title,
    List<SubtaskItem> subtasks,
    DateTime? suspendedAt,
  ) async {
    final labelIds = _collectOrderedLabelIds(board);
    final blockedByIds = _collectOrderedBlockedByIds(board);
    final conditions = _collectTaskConditions();
    final noteText = _noteController.text.trim();
    final notifier = ref.read(taskNotifierProvider.notifier);

    if (widget.initialTask case final existingTask?) {
      await notifier.updateTask(
        existingTask.id,
        title: title,
        note: noteText,
        targetTier: _mode.targetTier,
        isPriority: _mode == QuickAddMode.priority,
        subtasksAutoFinish: _subtasksAutoFinish,
        subtasks: subtasks,
        labelIds: labelIds,
        suspendedAt: suspendedAt,
        clearSuspendedAt: !_isSuspended,
        blockedByTaskIds: blockedByIds,
        conditions: conditions,
      );
      return;
    }

    await notifier.addTask(
      title,
      note: noteText.isEmpty ? null : noteText,
      targetTier: _mode.targetTier,
      isPriority: _mode == QuickAddMode.priority,
      subtasksAutoFinish: _subtasksAutoFinish,
      subtasks: subtasks,
      labelIds: labelIds,
      suspendedAt: suspendedAt,
      blockedByTaskIds: blockedByIds,
      conditions: conditions,
    );
  }

  /// Removes the GPS location condition at [index].
  void _removeLocationCondition(int index) {
    setState(() {
      _locationRules.removeAt(index);
    });
  }

  /// Removes the subtask step at [index].
  void _removeSubtask(int index) {
    setState(() {
      _subtasks.removeAt(index);
    });
  }

  /// Removes the time window condition at [index].
  void _removeTimeCondition(int index) {
    setState(() {
      _timeRules.removeAt(index);
    });
  }

  /// Derives the initial [QuickAddMode] for an existing [task].
  static QuickAddMode _resolveInitialMode(TaskItem task) {
    if (task.isCompleted || task.completedAt != null) {
      return QuickAddMode.standard;
    }
    if (task.isPriority) {
      return QuickAddMode.priority;
    }
    if (task.queuedAt == null) {
      return QuickAddMode.someday;
    }
    return QuickAddMode.standard;
  }

  /// Resolves the `suspendedAt` timestamp when [_isSuspended] is enabled, or `null` when disabled.
  DateTime? _resolveSuspendedTimestamp() {
    if (!_isSuspended) {
      return null;
    }
    final rawText = _suspendedController.text.trim();
    if (rawText.isEmpty) {
      return TaskItem.defaultSuspendedAt;
    }
    return TaskItem.tryParseTdfTimestampInput(rawText);
  }

  /// Validates the task inputs and saves the created or updated task.
  Future<void> _submit() async {
    final board =
        ref.read(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    final localizations = AppLocalizations.of(context);
    final validationError = _validateTitle(board, localizations);
    if (validationError != null) {
      setState(() {
        _errorMessage = validationError;
      });
      return;
    }

    final suspendedTimestamp = _resolveSuspendedTimestamp();
    if (_isSuspended && suspendedTimestamp == null) {
      setState(() {
        _suspendedErrorMessage = localizations.taskSuspendedErrorInvalid;
      });
      return;
    }

    final pendingSubtask = _subtaskController.text.trim();
    final effectiveSubtasks = <SubtaskItem>[
      ..._subtasks,
      if (pendingSubtask.isNotEmpty) SubtaskItem(title: pendingSubtask),
    ];

    await _persistTask(
      board,
      _titleController.text.trim(),
      effectiveSubtasks,
      suspendedTimestamp,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    widget.onSubmitted?.call();
  }

  /// Toggles the `subtasks auto-finish` option.
  void _toggleAutoFinish() {
    setState(() {
      _subtasksAutoFinish = !_subtasksAutoFinish;
    });
  }

  /// Toggles prerequisite [blockerTaskId] if it does not introduce a dependency cycle.
  void _toggleBlockedBy(TaskBoard board, String blockerTaskId) {
    if (widget.initialTask case final currentTask?
        when board.wouldCreateDependencyCycle(currentTask.id, blockerTaskId)) {
      return;
    }
    setState(() {
      if (!_blockedByTaskIds.remove(blockerTaskId)) {
        _blockedByTaskIds.add(blockerTaskId);
      }
    });
  }

  /// Toggles the global `condition any` reset directive.
  void _toggleConditionAny() {
    if (_isSuspended) {
      return;
    }
    setState(() {
      _conditionAny = !_conditionAny;
      if (_conditionAny) {
        _conditionDayAny = false;
        _conditionTimeAny = false;
        _conditionLocationAny = false;
        _selectedWeekdays.clear();
        _timeRules.clear();
        _locationRules.clear();
      }
    });
  }

  /// Toggles the `condition day any` group reset directive.
  void _toggleDayAny() {
    if (_isSuspended) {
      return;
    }
    setState(() {
      _conditionDayAny = !_conditionDayAny;
      if (_conditionDayAny) {
        _conditionAny = false;
        _selectedWeekdays.clear();
      }
    });
  }

  /// Toggles selection of [labelId].
  void _toggleLabel(String labelId) {
    setState(() {
      if (!_selectedLabelIds.remove(labelId)) {
        _selectedLabelIds.add(labelId);
      }
    });
  }

  /// Toggles the `condition location any` group reset directive.
  void _toggleLocationAny() {
    if (_isSuspended) {
      return;
    }
    setState(() {
      _conditionLocationAny = !_conditionLocationAny;
      if (_conditionLocationAny) {
        _conditionAny = false;
        _locationRules.clear();
      }
    });
  }

  /// Toggles Priority mode on or off.
  void _togglePriority() {
    setState(() {
      _mode = _mode == QuickAddMode.priority
          ? QuickAddMode.standard
          : QuickAddMode.priority;
    });
  }

  /// Toggles Someday mode on or off.
  void _toggleSomeday() {
    setState(() {
      _mode = _mode == QuickAddMode.someday
          ? QuickAddMode.standard
          : QuickAddMode.someday;
    });
  }

  /// Toggles completion state of the subtask step at [index].
  void _toggleSubtaskStep(int index) {
    final current = _subtasks[index];
    setState(() {
      _subtasks[index] = current.copyWith(isCompleted: !current.isCompleted);
    });
  }

  /// Toggles `suspended` state on or off.
  void _toggleSuspended() {
    setState(() {
      _isSuspended = !_isSuspended;
      _suspendedErrorMessage = null;
    });
  }

  /// Toggles the `condition time any` group reset directive.
  void _toggleTimeAny() {
    if (_isSuspended) {
      return;
    }
    setState(() {
      _conditionTimeAny = !_conditionTimeAny;
      if (_conditionTimeAny) {
        _conditionAny = false;
        _timeRules.clear();
      }
    });
  }

  /// Toggles ISO [weekday] (`1..7`) in `condition day`.
  void _toggleWeekday(int weekday) {
    if (_isSuspended) {
      return;
    }
    setState(() {
      _conditionAny = false;
      _conditionDayAny = false;
      if (!_selectedWeekdays.remove(weekday)) {
        _selectedWeekdays.add(weekday);
      }
    });
  }

  /// Validates the entered task title against empty and duplicate constraints.
  String? _validateTitle(TaskBoard board, AppLocalizations localizations) {
    final trimmed = _titleController.text.trim();
    if (trimmed.isEmpty) {
      return localizations.taskNameErrorEmpty;
    }
    if (board.hasDuplicateTaskTitle(
      trimmed,
      excludingTaskId: widget.initialTask?.id,
    )) {
      return localizations.taskNameErrorDuplicate;
    }
    return null;
  }
}

/// Header row inside [TaskEditorDialog] displaying the dialog title and close button.
class _TaskEditorHeader extends StatelessWidget {
  /// Creates a [_TaskEditorHeader].
  const _TaskEditorHeader({required this.title, required this.onClose});

  /// Callback invoked when the close button is pressed.
  final VoidCallback onClose;

  /// Dialog header title text.
  final String title;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: localizations.actionClose,
          icon: const Icon(Icons.close_rounded, color: _mutedLabelColor),
          onPressed: onClose,
        ),
      ],
    );
  }
}

/// Input row for adding a GPS location condition (`condition location <lat> <lon> <radius>`).
class _TaskEditorLocationInputRow extends StatelessWidget {
  /// Creates a [_TaskEditorLocationInputRow].
  const _TaskEditorLocationInputRow({
    required this.errorMessage,
    required this.latController,
    required this.lonController,
    required this.radiusController,
    required this.onAdd,
  });

  /// Optional validation error message.
  final String? errorMessage;

  /// Controller for latitude input.
  final TextEditingController latController;

  /// Controller for longitude input.
  final TextEditingController lonController;

  /// Callback invoked when the add location button is pressed.
  final VoidCallback onAdd;

  /// Controller for radius input.
  final TextEditingController radiusController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildCompactField(
                fieldKey: const ValueKey('task_editor_location_lat_input'),
                controller: latController,
                hintText: localizations.conditionLocationLatHint,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildCompactField(
                fieldKey: const ValueKey('task_editor_location_lon_input'),
                controller: lonController,
                hintText: localizations.conditionLocationLonHint,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildCompactField(
                fieldKey: const ValueKey('task_editor_location_radius_input'),
                controller: radiusController,
                hintText: localizations.conditionLocationRadiusHint,
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              key: const ValueKey('task_editor_add_location_condition_button'),
              style: IconButton.styleFrom(
                backgroundColor: _accentBlue,
                foregroundColor: Colors.white,
              ),
              tooltip: localizations.tooltipAddLocationCondition,
              onPressed: onAdd,
              icon: const Icon(Icons.add_location_alt_rounded),
            ),
          ],
        ),
        if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              errorMessage ?? '',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// Builds a compact single-line text field for GPS coordinate or radius input.
  Widget _buildCompactField({
    required Key fieldKey,
    required TextEditingController controller,
    required String hintText,
  }) {
    final borderRadius = BorderRadius.circular(12);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: _mutedLabelColor.withValues(alpha: 0.35)),
    );
    return TextField(
      key: fieldKey,
      controller: controller,
      cursorColor: _accentCyan,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: _mutedLabelColor, fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: _canvasColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: defaultBorder,
        enabledBorder: defaultBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: _accentCyan, width: 1.5),
        ),
      ),
    );
  }
}

/// Row of Priority, Someday, and Suspended chips inside [TaskEditorDialog].
class _TaskEditorModeRow extends StatelessWidget {
  /// Creates a [_TaskEditorModeRow].
  const _TaskEditorModeRow({
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
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _TaskEditorChip(
          chipKey: const ValueKey('task_editor_priority_button'),
          icon: Icons.bolt_rounded,
          label: localizations.quickAddPriority,
          isSelected: mode == QuickAddMode.priority,
          accentColor: _accentMagenta,
          onTap: onTogglePriority,
        ),
        _TaskEditorChip(
          chipKey: const ValueKey('task_editor_someday_button'),
          icon: Icons.lightbulb_outline_rounded,
          label: localizations.tierName(TaskTier.someday),
          isSelected: mode == QuickAddMode.someday,
          accentColor: _accentBlue,
          onTap: onToggleSomeday,
        ),
        _TaskEditorChip(
          chipKey: const ValueKey('task_editor_suspended_button'),
          icon: Icons.pause_circle_outline_rounded,
          label: localizations.taskSuspendedLabel,
          isSelected: isSuspended,
          accentColor: _accentAmber,
          onTap: onToggleSuspended,
        ),
      ],
    );
  }
}

/// Optional task note input field inside [TaskEditorDialog].
class _TaskEditorNoteField extends StatelessWidget {
  /// Creates a [_TaskEditorNoteField].
  const _TaskEditorNoteField({required this.controller});

  /// Controller for the note input.
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final borderRadius = BorderRadius.circular(14);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: _mutedLabelColor.withValues(alpha: 0.35)),
    );

    return TextField(
      key: const ValueKey('task_editor_note_input'),
      controller: controller,
      cursorColor: _accentCyan,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      minLines: 1,
      maxLines: 2,
      decoration: InputDecoration(
        labelText: localizations.taskNoteLabel,
        labelStyle: const TextStyle(color: _mutedLabelColor),
        hintText: localizations.taskNoteHint,
        hintStyle: const TextStyle(color: _mutedLabelColor),
        isDense: true,
        filled: true,
        fillColor: _canvasColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: defaultBorder,
        enabledBorder: defaultBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: _accentCyan, width: 1.6),
        ),
      ),
    );
  }
}

/// Single condition rule display row with a remove icon button.
class _TaskEditorRuleRow extends StatelessWidget {
  /// Creates a [_TaskEditorRuleRow].
  const _TaskEditorRuleRow({
    required this.icon,
    required this.label,
    required this.removeKey,
    required this.tooltip,
    required this.onRemove,
  });

  /// Leading icon for the rule.
  final IconData icon;

  /// Formatted rule description.
  final String label;

  /// Callback invoked when the remove button is pressed.
  final VoidCallback onRemove;

  /// Deterministic widget key for the remove button.
  final Key removeKey;

  /// Tooltip for the remove button.
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _accentCyan),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          IconButton(
            key: removeKey,
            visualDensity: VisualDensity.compact,
            tooltip: tooltip,
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: _mutedLabelColor,
            ),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Input row for adding a subtask step inside [_TaskEditorSubtasksSection].
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
    final borderRadius = BorderRadius.circular(14);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: _mutedLabelColor.withValues(alpha: 0.35)),
    );

    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('task_editor_subtask_input'),
            controller: controller,
            cursorColor: _accentCyan,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onAddSubtask(),
            decoration: InputDecoration(
              hintText: localizations.subtaskInputHint,
              hintStyle: const TextStyle(color: _mutedLabelColor),
              isDense: true,
              filled: true,
              fillColor: _canvasColor,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: defaultBorder,
              enabledBorder: defaultBorder,
              focusedBorder: OutlineInputBorder(
                borderRadius: borderRadius,
                borderSide: const BorderSide(color: _accentCyan, width: 1.6),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          key: const ValueKey('task_editor_subtask_add_button'),
          style: IconButton.styleFrom(
            backgroundColor: _accentBlue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _canvasColor.withValues(alpha: 0.55),
            disabledForegroundColor: _mutedLabelColor.withValues(alpha: 0.6),
          ),
          tooltip: localizations.tooltipAddSubtask,
          onPressed: hasText ? onAddSubtask : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

/// Single subtask row inside [_TaskEditorSubtasksSection] with completion toggle and remove action.
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
                color: subtask.isCompleted ? _accentCyan : _mutedLabelColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtask.title,
              style: TextStyle(
                color: subtask.isCompleted ? _mutedLabelColor : Colors.white,
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
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: _mutedLabelColor,
            ),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Subtasks editor section inside [TaskEditorDialog] with `auto-finish` toggle, list, and input row.
class _TaskEditorSubtasksSection extends StatelessWidget {
  /// Creates a [_TaskEditorSubtasksSection].
  const _TaskEditorSubtasksSection({
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                localizations.subtasksSectionTitle,
                style: const TextStyle(
                  color: _mutedLabelColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _TaskEditorChip(
              chipKey: const ValueKey('task_editor_auto_finish_toggle'),
              icon: Icons.done_all_rounded,
              label: localizations.subtasksAutoFinishLabel,
              isSelected: subtasksAutoFinish,
              accentColor: _accentCyan,
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

/// Optional `suspended` timestamp input field inside [TaskEditorDialog].
class _TaskEditorSuspendedField extends StatelessWidget {
  /// Creates a [_TaskEditorSuspendedField].
  const _TaskEditorSuspendedField({
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
    final borderRadius = BorderRadius.circular(14);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: _mutedLabelColor.withValues(alpha: 0.35)),
    );

    return TextField(
      key: const ValueKey('task_editor_suspended_input'),
      controller: controller,
      cursorColor: _accentAmber,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: localizations.taskSuspendedUntilLabel,
        labelStyle: const TextStyle(color: _mutedLabelColor),
        hintText: localizations.taskSuspendedUntilHint,
        hintStyle: const TextStyle(color: _mutedLabelColor),
        errorText: errorMessage,
        isDense: true,
        filled: true,
        fillColor: _canvasColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: defaultBorder,
        enabledBorder: defaultBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: _accentAmber, width: 1.6),
        ),
      ),
    );
  }
}

/// Input row for adding a time window condition (`condition time <HH:MM> <HH:MM>`).
class _TaskEditorTimeInputRow extends StatelessWidget {
  /// Creates a [_TaskEditorTimeInputRow].
  const _TaskEditorTimeInputRow({
    required this.endController,
    required this.errorMessage,
    required this.startController,
    required this.onAdd,
  });

  /// Controller for the end time (`HH:MM`).
  final TextEditingController endController;

  /// Optional validation error message.
  final String? errorMessage;

  /// Callback invoked when the add time window button is pressed.
  final VoidCallback onAdd;

  /// Controller for the start time (`HH:MM`).
  final TextEditingController startController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTimeField(
                fieldKey: const ValueKey('task_editor_time_start_input'),
                controller: startController,
                hintText: localizations.conditionTimeStartHint,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildTimeField(
                fieldKey: const ValueKey('task_editor_time_end_input'),
                controller: endController,
                hintText: localizations.conditionTimeEndHint,
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              key: const ValueKey('task_editor_add_time_condition_button'),
              style: IconButton.styleFrom(
                backgroundColor: _accentBlue,
                foregroundColor: Colors.white,
              ),
              tooltip: localizations.tooltipAddTimeCondition,
              onPressed: onAdd,
              icon: const Icon(Icons.more_time_rounded),
            ),
          ],
        ),
        if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              errorMessage ?? '',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// Builds a compact single-line text field for `HH:MM` time input.
  Widget _buildTimeField({
    required Key fieldKey,
    required TextEditingController controller,
    required String hintText,
  }) {
    final borderRadius = BorderRadius.circular(12);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: _mutedLabelColor.withValues(alpha: 0.35)),
    );
    return TextField(
      key: fieldKey,
      controller: controller,
      cursorColor: _accentCyan,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: _mutedLabelColor, fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: _canvasColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: defaultBorder,
        enabledBorder: defaultBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: _accentCyan, width: 1.5),
        ),
      ),
    );
  }
}

/// Task title input field with inline validation error display inside [TaskEditorDialog].
class _TaskEditorTitleField extends StatelessWidget {
  /// Creates a [_TaskEditorTitleField].
  const _TaskEditorTitleField({
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
    final borderRadius = BorderRadius.circular(14);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: _mutedLabelColor.withValues(alpha: 0.35)),
    );

    return TextField(
      key: const ValueKey('task_editor_title_input'),
      controller: controller,
      autofocus: true,
      cursorColor: _accentMagenta,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmit(),
      decoration: InputDecoration(
        labelText: localizations.taskNameLabel,
        labelStyle: const TextStyle(color: _mutedLabelColor),
        errorText: errorMessage,
        isDense: true,
        filled: true,
        fillColor: _canvasColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: defaultBorder,
        enabledBorder: defaultBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: _accentMagenta, width: 1.6),
        ),
      ),
    );
  }
}

/// Opens [TaskEditorDialog] as a modal dialog for extended task creation or task editing.
Future<void> showTaskEditorDialog(
  BuildContext context, {
  TaskItem? initialTask,
  String initialTitle = '',
  QuickAddMode initialMode = QuickAddMode.standard,
  Set<String> initialLabelIds = const <String>{},
  VoidCallback? onSubmitted,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => TaskEditorDialog(
      initialTask: initialTask,
      initialTitle: initialTitle,
      initialMode: initialMode,
      initialLabelIds: initialLabelIds,
      onSubmitted: onSubmitted,
    ),
  );
}
