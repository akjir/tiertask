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
import '../../models/tdf_metadata.dart';
import '../app_theme.dart';
import 'clearable_text_field.dart';
import 'condition_editor_controller.dart';
import 'task_editor_sections.dart';

/// Activation conditions (`condition`) editor card shared by task and label editors.
class TaskEditorConditionsSection extends StatelessWidget {
  /// Creates a [TaskEditorConditionsSection].
  const TaskEditorConditionsSection({
    super.key,
    required this.controller,
    this.descriptionOverride,
    this.isSuspended = false,
  });

  /// Controller managing the condition form state.
  final ConditionEditorController controller;

  /// Optional custom section description (defaults to [AppLocalizations.taskConditionsSectionDescription]).
  final String? descriptionOverride;

  /// Whether the enclosing task is suspended (disabling condition evaluation and editing).
  final bool isSuspended;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return TaskEditorSectionCard(
          cardKey: const ValueKey('task_editor_conditions_card'),
          icon: Icons.rule_rounded,
          title: localizations.taskConditionsSectionTitle,
          description:
              descriptionOverride ??
              localizations.taskConditionsSectionDescription,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isSuspended) ...[
                Text(
                  localizations.taskSuspendedDisablesConditionsHint,
                  key: const ValueKey('task_editor_conditions_disabled_hint'),
                  style: TextStyle(color: appTheme.warningAccent, fontSize: 12),
                ),
                const SizedBox(height: 8),
              ],
              IgnorePointer(
                ignoring: isSuspended,
                child: Opacity(
                  opacity: isSuspended ? 0.45 : 1.0,
                  child: _buildConditionControls(
                    context,
                    localizations,
                    appTheme,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Builds the interactive condition controls inside [TaskEditorConditionsSection].
  Widget _buildConditionControls(
    BuildContext context,
    AppLocalizations localizations,
    AppTheme appTheme,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.allowResets) ...[
          TaskEditorChip(
            chipKey: const ValueKey('task_editor_condition_any_toggle'),
            icon: Icons.filter_alt_off_rounded,
            label: localizations.conditionGlobalAnyLabel,
            isSelected: controller.conditionAny,
            accentColor: appTheme.primaryAccent,
            onTap: controller.toggleConditionAny,
          ),
          const SizedBox(height: 12),
        ],
        _TaskEditorConditionDaySection(
          allowResets: controller.allowResets,
          conditionDayAny: controller.conditionDayAny,
          selectedWeekdays: controller.selectedWeekdays,
          onToggleDayAny: controller.toggleDayAny,
          onToggleWeekday: controller.toggleWeekday,
        ),
        const SizedBox(height: 12),
        _TaskEditorConditionTimeSection(
          allowResets: controller.allowResets,
          conditionTimeAny: controller.conditionTimeAny,
          startController: controller.timeStartController,
          endController: controller.timeEndController,
          errorMessage: controller.timeErrorMessage,
          rules: controller.timeRules,
          onAddTimeCondition: () => controller.addTimeCondition(localizations),
          onPickEndTime: () => controller.pickEndTime(context),
          onPickStartTime: () => controller.pickStartTime(context),
          onRemoveTimeCondition: controller.removeTimeCondition,
          onToggleTimeAny: controller.toggleTimeAny,
        ),
        const SizedBox(height: 12),
        _TaskEditorConditionLocationSection(
          allowResets: controller.allowResets,
          conditionLocationAny: controller.conditionLocationAny,
          latController: controller.locationLatController,
          lonController: controller.locationLonController,
          radiusController: controller.locationRadiusController,
          errorMessage: controller.locationErrorMessage,
          rules: controller.locationRules,
          onAddLocationCondition: () =>
              controller.addLocationCondition(localizations),
          onRemoveLocationCondition: controller.removeLocationCondition,
          onToggleLocationAny: controller.toggleLocationAny,
        ),
      ],
    );
  }
}

/// Weekday (`condition day`) editor subgroup inside [TaskEditorConditionsSection].
class _TaskEditorConditionDaySection extends StatelessWidget {
  /// Creates a [_TaskEditorConditionDaySection].
  const _TaskEditorConditionDaySection({
    required this.allowResets,
    required this.conditionDayAny,
    required this.selectedWeekdays,
    required this.onToggleDayAny,
    required this.onToggleWeekday,
  });

  /// Whether the `condition day any` reset chip is shown.
  final bool allowResets;

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
    final appTheme = AppTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildConditionGroupHeader(
          appTheme: appTheme,
          title: localizations.conditionDayGroupTitle,
          allowResets: allowResets,
          resetChipKey: const ValueKey('task_editor_condition_day_any_toggle'),
          resetIcon: Icons.calendar_today_rounded,
          resetLabel: localizations.conditionDayAnyLabel,
          resetTooltip: localizations.tooltipConditionDayAny,
          isResetSelected: conditionDayAny,
          onToggleReset: onToggleDayAny,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var weekday = 1; weekday <= 7; weekday++)
              TaskEditorChip(
                chipKey: ValueKey(
                  'task_editor_condition_day_${DayTaskCondition.canonicalTokens[weekday - 1]}',
                ),
                icon: Icons.event_available_rounded,
                label: _weekdayLabel(localizations, weekday),
                isSelected:
                    !conditionDayAny && selectedWeekdays.contains(weekday),
                accentColor: appTheme.secondaryAccent,
                onTap: () => onToggleWeekday(weekday),
              ),
          ],
        ),
      ],
    );
  }

  /// Returns the localized short label for ISO [weekday] (`1..7`).
  static String _weekdayLabel(AppLocalizations localizations, int weekday) {
    return switch (weekday) {
      1 => localizations.weekdayMon,
      2 => localizations.weekdayTue,
      3 => localizations.weekdayWed,
      4 => localizations.weekdayThu,
      5 => localizations.weekdayFri,
      6 => localizations.weekdaySat,
      _ => localizations.weekdaySun,
    };
  }
}

/// GPS location (`condition location`) editor subgroup inside [TaskEditorConditionsSection].
class _TaskEditorConditionLocationSection extends StatelessWidget {
  /// Creates a [_TaskEditorConditionLocationSection].
  const _TaskEditorConditionLocationSection({
    required this.allowResets,
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

  /// Whether the `condition location any` reset chip is shown.
  final bool allowResets;

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
    final appTheme = AppTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildConditionGroupHeader(
          appTheme: appTheme,
          title: localizations.conditionLocationGroupTitle,
          allowResets: allowResets,
          resetChipKey: const ValueKey(
            'task_editor_condition_location_any_toggle',
          ),
          resetIcon: Icons.public_rounded,
          resetLabel: localizations.conditionLocationAnyLabel,
          resetTooltip: localizations.tooltipConditionLocationAny,
          isResetSelected: conditionLocationAny,
          onToggleReset: onToggleLocationAny,
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < rules.length; i++)
          _TaskEditorRuleRow(
            removeKey: ValueKey('task_editor_remove_location_condition_$i'),
            icon: Icons.place_outlined,
            label:
                '${rules[i].latitude}, ${rules[i].longitude} (${rules[i].radiusMeters}m)',
            tooltip: localizations.tooltipRemoveLocationCondition,
            onRemove: () => onRemoveLocationCondition(i),
          ),
        _buildLocationInputRow(localizations, appTheme),
        if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              errorMessage ?? '',
              style: TextStyle(color: appTheme.errorColor, fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// Builds the latitude, longitude, radius input fields and add button row.
  Widget _buildLocationInputRow(
    AppLocalizations localizations,
    AppTheme appTheme,
  ) {
    return Row(
      children: [
        Expanded(
          child: _buildConditionTextField(
            appTheme: appTheme,
            fieldKey: const ValueKey('task_editor_location_lat_input'),
            controller: latController,
            hintText: localizations.conditionLocationLatHint,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _buildConditionTextField(
            appTheme: appTheme,
            fieldKey: const ValueKey('task_editor_location_lon_input'),
            controller: lonController,
            hintText: localizations.conditionLocationLonHint,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _buildConditionTextField(
            appTheme: appTheme,
            fieldKey: const ValueKey('task_editor_location_radius_input'),
            controller: radiusController,
            hintText: localizations.conditionLocationRadiusHint,
          ),
        ),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          key: const ValueKey('task_editor_add_location_condition_button'),
          style: IconButton.styleFrom(
            backgroundColor: appTheme.secondaryContainerColor,
            foregroundColor: appTheme.onSecondaryContainerColor,
          ),
          tooltip: localizations.tooltipAddLocationCondition,
          onPressed: onAddLocationCondition,
          icon: const Icon(Icons.add_location_alt_rounded),
        ),
      ],
    );
  }
}

/// Time window (`condition time`) editor subgroup inside [TaskEditorConditionsSection].
class _TaskEditorConditionTimeSection extends StatelessWidget {
  /// Creates a [_TaskEditorConditionTimeSection].
  const _TaskEditorConditionTimeSection({
    required this.allowResets,
    required this.conditionTimeAny,
    required this.endController,
    required this.errorMessage,
    required this.rules,
    required this.startController,
    required this.onAddTimeCondition,
    required this.onPickEndTime,
    required this.onPickStartTime,
    required this.onRemoveTimeCondition,
    required this.onToggleTimeAny,
  });

  /// Whether the `condition time any` reset chip is shown.
  final bool allowResets;

  /// Whether `condition time any` is active.
  final bool conditionTimeAny;

  /// Controller for the end time (`HH:MM`).
  final TextEditingController endController;

  /// Validation error message for time input, or `null` when valid.
  final String? errorMessage;

  /// Callback to add a time window condition.
  final VoidCallback onAddTimeCondition;

  /// Callback to open the time picker for the end time field.
  final VoidCallback onPickEndTime;

  /// Callback to open the time picker for the start time field.
  final VoidCallback onPickStartTime;

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
    final appTheme = AppTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildConditionGroupHeader(
          appTheme: appTheme,
          title: localizations.conditionTimeGroupTitle,
          allowResets: allowResets,
          resetChipKey: const ValueKey('task_editor_condition_time_any_toggle'),
          resetIcon: Icons.schedule_rounded,
          resetLabel: localizations.conditionTimeAnyLabel,
          resetTooltip: localizations.tooltipConditionTimeAny,
          isResetSelected: conditionTimeAny,
          onToggleReset: onToggleTimeAny,
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < rules.length; i++)
          _TaskEditorRuleRow(
            removeKey: ValueKey('task_editor_remove_time_condition_$i'),
            icon: Icons.access_time_rounded,
            label: '${rules[i].startToken} - ${rules[i].endToken}',
            tooltip: localizations.tooltipRemoveTimeCondition,
            onRemove: () => onRemoveTimeCondition(i),
          ),
        _buildTimeInputRow(localizations, appTheme),
        if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              errorMessage ?? '',
              style: TextStyle(color: appTheme.errorColor, fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// Builds the start time, end time, and add button row.
  Widget _buildTimeInputRow(AppLocalizations localizations, AppTheme appTheme) {
    return Row(
      children: [
        Expanded(
          child: _buildConditionTextField(
            appTheme: appTheme,
            fieldKey: const ValueKey('task_editor_time_start_input'),
            controller: startController,
            hintText: localizations.conditionTimeStartHint,
            pickerKey: const ValueKey('task_editor_time_start_picker_button'),
            pickerTooltip: localizations.tooltipPickStartTime,
            onPickTime: onPickStartTime,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _buildConditionTextField(
            appTheme: appTheme,
            fieldKey: const ValueKey('task_editor_time_end_input'),
            controller: endController,
            hintText: localizations.conditionTimeEndHint,
            pickerKey: const ValueKey('task_editor_time_end_picker_button'),
            pickerTooltip: localizations.tooltipPickEndTime,
            onPickTime: onPickEndTime,
          ),
        ),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          key: const ValueKey('task_editor_add_time_condition_button'),
          style: IconButton.styleFrom(
            backgroundColor: appTheme.secondaryContainerColor,
            foregroundColor: appTheme.onSecondaryContainerColor,
          ),
          tooltip: localizations.tooltipAddTimeCondition,
          onPressed: onAddTimeCondition,
          icon: const Icon(Icons.more_time_rounded),
        ),
      ],
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
    final appTheme = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: appTheme.tertiaryAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: appTheme.primaryTextColor, fontSize: 13),
            ),
          ),
          IconButton(
            key: removeKey,
            visualDensity: VisualDensity.compact,
            tooltip: tooltip,
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

/// Builds the header row for a condition subgroup with an optional group reset chip.
Widget _buildConditionGroupHeader({
  required AppTheme appTheme,
  required String title,
  required bool allowResets,
  required Key resetChipKey,
  required IconData resetIcon,
  required String resetLabel,
  required String resetTooltip,
  required bool isResetSelected,
  required VoidCallback onToggleReset,
}) {
  return Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: TextStyle(
            color: appTheme.mutedTextColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      if (allowResets)
        TaskEditorChip(
          chipKey: resetChipKey,
          icon: resetIcon,
          label: resetLabel,
          tooltip: resetTooltip,
          isSelected: isResetSelected,
          accentColor: appTheme.tertiaryAccent,
          onTap: onToggleReset,
        ),
    ],
  );
}

/// Builds a compact single-line condition text field with an optional trailing time picker button.
Widget _buildConditionTextField({
  required AppTheme appTheme,
  required Key fieldKey,
  required TextEditingController controller,
  required String hintText,
  Key? pickerKey,
  String? pickerTooltip,
  VoidCallback? onPickTime,
}) {
  final borderRadius = BorderRadius.circular(12);
  final defaultBorder = OutlineInputBorder(
    borderRadius: borderRadius,
    borderSide: BorderSide(
      color: appTheme.mutedTextColor.withValues(alpha: 0.35),
    ),
  );
  return ClearableTextField(
    fieldKey: fieldKey,
    controller: controller,
    clearIconColor: appTheme.mutedTextColor,
    clearIconSize: 16,
    cursorColor: appTheme.tertiaryAccent,
    style: TextStyle(color: appTheme.primaryTextColor, fontSize: 13),
    decoration: InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: appTheme.mutedTextColor, fontSize: 12),
      isDense: true,
      filled: true,
      fillColor: appTheme.canvasColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      suffixIcon: onPickTime != null
          ? IconButton(
              key: pickerKey,
              visualDensity: VisualDensity.compact,
              tooltip: pickerTooltip,
              icon: Icon(
                Icons.access_time_rounded,
                size: 16,
                color: appTheme.tertiaryAccent,
              ),
              onPressed: onPickTime,
            )
          : null,
      border: defaultBorder,
      enabledBorder: defaultBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: appTheme.tertiaryAccent, width: 1.5),
      ),
    ),
  );
}
