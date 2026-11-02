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
import 'task_editor_sections.dart';

/// Activation conditions (`condition`) editor section inside the task editor.
class TaskEditorConditionsSection extends StatelessWidget {
  /// Creates a [TaskEditorConditionsSection].
  const TaskEditorConditionsSection({
    super.key,
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
    final appTheme = AppTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.sectionTaskConditions,
          style: TextStyle(
            color: appTheme.mutedTextColor,
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
            style: TextStyle(color: appTheme.warningAccent, fontSize: 12),
          ),
        ],
        const SizedBox(height: 6),
        IgnorePointer(
          ignoring: isSuspended,
          child: Opacity(
            opacity: isSuspended ? 0.45 : 1.0,
            child: _buildConditionControls(localizations, appTheme),
          ),
        ),
      ],
    );
  }

  /// Builds the interactive condition controls inside [TaskEditorConditionsSection].
  Widget _buildConditionControls(
    AppLocalizations localizations,
    AppTheme appTheme,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TaskEditorChip(
          chipKey: const ValueKey('task_editor_condition_any_toggle'),
          icon: Icons.filter_alt_off_rounded,
          label: localizations.conditionGlobalAnyLabel,
          isSelected: conditionAny,
          accentColor: appTheme.primaryAccent,
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

/// Weekday (`condition day`) editor subgroup inside [TaskEditorConditionsSection].
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
    final appTheme = AppTheme.of(context);
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
                style: TextStyle(
                  color: appTheme.mutedTextColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TaskEditorChip(
              chipKey: const ValueKey('task_editor_condition_day_any_toggle'),
              icon: Icons.calendar_today_rounded,
              label: localizations.conditionDayAnyLabel,
              isSelected: conditionDayAny,
              accentColor: appTheme.tertiaryAccent,
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
              TaskEditorChip(
                chipKey: ValueKey(
                  'task_editor_condition_day_${DayTaskCondition.canonicalTokens[weekday - 1]}',
                ),
                icon: Icons.event_available_rounded,
                label: dayLabels[weekday] ?? '',
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
}

/// GPS location (`condition location`) editor subgroup inside [TaskEditorConditionsSection].
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
    final appTheme = AppTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                localizations.conditionLocationGroupTitle,
                style: TextStyle(
                  color: appTheme.mutedTextColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TaskEditorChip(
              chipKey: const ValueKey(
                'task_editor_condition_location_any_toggle',
              ),
              icon: Icons.public_rounded,
              label: localizations.conditionLocationAnyLabel,
              isSelected: conditionLocationAny,
              accentColor: appTheme.tertiaryAccent,
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

/// Time window (`condition time`) editor subgroup inside [TaskEditorConditionsSection].
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
    final appTheme = AppTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                localizations.conditionTimeGroupTitle,
                style: TextStyle(
                  color: appTheme.mutedTextColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TaskEditorChip(
              chipKey: const ValueKey('task_editor_condition_time_any_toggle'),
              icon: Icons.schedule_rounded,
              label: localizations.conditionTimeAnyLabel,
              isSelected: conditionTimeAny,
              accentColor: appTheme.tertiaryAccent,
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
    final appTheme = AppTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildCompactField(
                appTheme: appTheme,
                fieldKey: const ValueKey('task_editor_location_lat_input'),
                controller: latController,
                hintText: localizations.conditionLocationLatHint,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildCompactField(
                appTheme: appTheme,
                fieldKey: const ValueKey('task_editor_location_lon_input'),
                controller: lonController,
                hintText: localizations.conditionLocationLonHint,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildCompactField(
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
                backgroundColor: appTheme.secondaryAccent,
                foregroundColor: appTheme.onSecondaryColor,
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
              style: TextStyle(color: appTheme.errorColor, fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// Builds a compact single-line text field for GPS coordinate or radius input.
  Widget _buildCompactField({
    required AppTheme appTheme,
    required Key fieldKey,
    required TextEditingController controller,
    required String hintText,
  }) {
    final borderRadius = BorderRadius.circular(12);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(
        color: appTheme.mutedTextColor.withValues(alpha: 0.35),
      ),
    );
    return TextField(
      key: fieldKey,
      controller: controller,
      cursorColor: appTheme.tertiaryAccent,
      style: TextStyle(color: appTheme.primaryTextColor, fontSize: 13),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: appTheme.mutedTextColor, fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: appTheme.canvasColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: defaultBorder,
        enabledBorder: defaultBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: appTheme.tertiaryAccent, width: 1.5),
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
    final appTheme = AppTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTimeField(
                appTheme: appTheme,
                fieldKey: const ValueKey('task_editor_time_start_input'),
                controller: startController,
                hintText: localizations.conditionTimeStartHint,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildTimeField(
                appTheme: appTheme,
                fieldKey: const ValueKey('task_editor_time_end_input'),
                controller: endController,
                hintText: localizations.conditionTimeEndHint,
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              key: const ValueKey('task_editor_add_time_condition_button'),
              style: IconButton.styleFrom(
                backgroundColor: appTheme.secondaryAccent,
                foregroundColor: appTheme.onSecondaryColor,
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
              style: TextStyle(color: appTheme.errorColor, fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// Builds a compact single-line text field for `HH:MM` time input.
  Widget _buildTimeField({
    required AppTheme appTheme,
    required Key fieldKey,
    required TextEditingController controller,
    required String hintText,
  }) {
    final borderRadius = BorderRadius.circular(12);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(
        color: appTheme.mutedTextColor.withValues(alpha: 0.35),
      ),
    );
    return TextField(
      key: fieldKey,
      controller: controller,
      cursorColor: appTheme.tertiaryAccent,
      style: TextStyle(color: appTheme.primaryTextColor, fontSize: 13),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: appTheme.mutedTextColor, fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: appTheme.canvasColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: defaultBorder,
        enabledBorder: defaultBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: appTheme.tertiaryAccent, width: 1.5),
        ),
      ),
    );
  }
}
