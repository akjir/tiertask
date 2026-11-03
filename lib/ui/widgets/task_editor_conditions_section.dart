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
import '../../models/tdf_metadata.dart';
import '../app_theme.dart';
import 'clearable_text_field.dart';
import 'task_editor_sections.dart';

/// Shared state controller for editing TDF `condition` rules on both `task` and `label` blocks.
class ConditionEditorController extends ChangeNotifier {
  /// Creates a [ConditionEditorController] initialized with [initialConditions].
  ConditionEditorController({
    Iterable<TaskCondition> initialConditions = const <TaskCondition>[],
    this.allowResets = true,
  }) {
    _initialize(initialConditions);
  }

  /// Whether task-only reset directives (`any`, `day any`, `time any`, `location any`) are permitted.
  final bool allowResets;

  /// Controller for GPS latitude input.
  final TextEditingController locationLatController = TextEditingController();

  /// Controller for GPS longitude input.
  final TextEditingController locationLonController = TextEditingController();

  /// Controller for GPS radius input.
  final TextEditingController locationRadiusController =
      TextEditingController();

  /// Controller for the end of a time window condition.
  final TextEditingController timeEndController = TextEditingController();

  /// Controller for the start of a time window condition.
  final TextEditingController timeStartController = TextEditingController();

  bool _conditionAny = false;
  bool _conditionDayAny = false;
  bool _conditionLocationAny = false;
  bool _conditionTimeAny = false;
  String? _locationErrorMessage;
  final List<LocationTaskCondition> _locationRules = <LocationTaskCondition>[];
  final Set<int> _selectedWeekdays = <int>{};
  String? _timeErrorMessage;
  final List<TimeWindowTaskCondition> _timeRules = <TimeWindowTaskCondition>[];

  /// Whether `condition any` is active.
  bool get conditionAny => _conditionAny;

  /// Whether `condition day any` is active.
  bool get conditionDayAny => _conditionDayAny;

  /// Whether `condition location any` is active.
  bool get conditionLocationAny => _conditionLocationAny;

  /// Whether `condition time any` is active.
  bool get conditionTimeAny => _conditionTimeAny;

  /// Validation error message for GPS location input, or `null` when valid.
  String? get locationErrorMessage => _locationErrorMessage;

  /// Configured GPS location conditions.
  List<LocationTaskCondition> get locationRules =>
      List<LocationTaskCondition>.unmodifiable(_locationRules);

  /// Selected ISO weekdays (`1` = Monday .. `7` = Sunday).
  Set<int> get selectedWeekdays => Set<int>.unmodifiable(_selectedWeekdays);

  /// Validation error message for time window input, or `null` when valid.
  String? get timeErrorMessage => _timeErrorMessage;

  /// Configured time window conditions.
  List<TimeWindowTaskCondition> get timeRules =>
      List<TimeWindowTaskCondition>.unmodifiable(_timeRules);

  @override
  void dispose() {
    timeStartController.dispose();
    timeEndController.dispose();
    locationLatController.dispose();
    locationLonController.dispose();
    locationRadiusController.dispose();
    super.dispose();
  }

  /// Validates and appends a GPS location condition from the location input controllers.
  void addLocationCondition(AppLocalizations localizations) {
    final parsed = LocationTaskCondition.tryParse(
      locationLatController.text,
      locationLonController.text,
      locationRadiusController.text,
    );
    if (parsed == null) {
      _locationErrorMessage = localizations.conditionLocationErrorInvalid;
      notifyListeners();
      return;
    }
    _conditionAny = false;
    _conditionLocationAny = false;
    if (!_locationRules.contains(parsed)) {
      _locationRules.add(parsed);
    }
    locationLatController.clear();
    locationLonController.clear();
    locationRadiusController.clear();
    _locationErrorMessage = null;
    notifyListeners();
  }

  /// Validates and appends a time window condition from the time input controllers.
  void addTimeCondition(AppLocalizations localizations) {
    final parsed = TimeWindowTaskCondition.tryParse(
      timeStartController.text,
      timeEndController.text,
    );
    if (parsed == null) {
      _timeErrorMessage = localizations.conditionTimeErrorInvalid;
      notifyListeners();
      return;
    }
    _conditionAny = false;
    _conditionTimeAny = false;
    if (!_timeRules.contains(parsed)) {
      _timeRules.add(parsed);
    }
    timeStartController.clear();
    timeEndController.clear();
    _timeErrorMessage = null;
    notifyListeners();
  }

  /// Assembles the ordered [TaskCondition] list from the current editor state.
  List<TaskCondition> buildConditions() {
    if (allowResets && _conditionAny) {
      return const <TaskCondition>[GlobalResetTaskCondition()];
    }
    return <TaskCondition>[
      if (allowResets && _conditionDayAny)
        const GroupResetTaskCondition(targetGroup: ConditionGroup.day)
      else if (_selectedWeekdays.isNotEmpty)
        DayTaskCondition.fromWeekdays(_selectedWeekdays),
      if (allowResets && _conditionTimeAny)
        const GroupResetTaskCondition(targetGroup: ConditionGroup.time)
      else
        ..._timeRules,
      if (allowResets && _conditionLocationAny)
        const GroupResetTaskCondition(targetGroup: ConditionGroup.location)
      else
        ..._locationRules,
    ];
  }

  /// Opens the Material 3 time picker for the condition end time field (`17:00` default).
  Future<void> pickEndTime(BuildContext context) async {
    await _pickTimeIntoController(
      context,
      timeEndController,
      defaultTime: const TimeOfDay(hour: 17, minute: 0),
    );
  }

  /// Opens the Material 3 time picker for the condition start time field (`09:00` default).
  Future<void> pickStartTime(BuildContext context) async {
    await _pickTimeIntoController(
      context,
      timeStartController,
      defaultTime: const TimeOfDay(hour: 9, minute: 0),
    );
  }

  /// Removes the GPS location condition at [index].
  void removeLocationCondition(int index) {
    _locationRules.removeAt(index);
    notifyListeners();
  }

  /// Removes the time window condition at [index].
  void removeTimeCondition(int index) {
    _timeRules.removeAt(index);
    notifyListeners();
  }

  /// Toggles the global `condition any` reset flag.
  void toggleConditionAny() {
    if (!allowResets) {
      return;
    }
    _conditionAny = !_conditionAny;
    if (_conditionAny) {
      _conditionDayAny = false;
      _conditionTimeAny = false;
      _conditionLocationAny = false;
      _selectedWeekdays.clear();
      _timeRules.clear();
      _locationRules.clear();
    }
    notifyListeners();
  }

  /// Toggles the `condition day any` group reset flag.
  void toggleDayAny() {
    if (!allowResets) {
      return;
    }
    _conditionDayAny = !_conditionDayAny;
    if (_conditionDayAny) {
      _conditionAny = false;
      _selectedWeekdays.clear();
    }
    notifyListeners();
  }

  /// Toggles the `condition location any` group reset flag.
  void toggleLocationAny() {
    if (!allowResets) {
      return;
    }
    _conditionLocationAny = !_conditionLocationAny;
    if (_conditionLocationAny) {
      _conditionAny = false;
      _locationRules.clear();
    }
    notifyListeners();
  }

  /// Toggles the `condition time any` group reset flag.
  void toggleTimeAny() {
    if (!allowResets) {
      return;
    }
    _conditionTimeAny = !_conditionTimeAny;
    if (_conditionTimeAny) {
      _conditionAny = false;
      _timeRules.clear();
    }
    notifyListeners();
  }

  /// Toggles ISO-8601 [weekday] (`1..7`) in the `condition day` set.
  void toggleWeekday(int weekday) {
    _conditionAny = false;
    _conditionDayAny = false;
    if (!_selectedWeekdays.remove(weekday)) {
      _selectedWeekdays.add(weekday);
    }
    notifyListeners();
  }

  /// Wraps a [showTimePicker] dialog in a 24-hour [MediaQuery] configuration.
  static Widget _build24HourTimePicker(BuildContext context, Widget? child) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child ?? const SizedBox.shrink(),
    );
  }

  /// Parses [rawTime] (`HH:MM`) into a [TimeOfDay], or returns [fallback] if invalid.
  static TimeOfDay _extractTimeOfDay(String rawTime, TimeOfDay fallback) {
    final minutes = TaskItem.tryParseTimeMinutes(rawTime.trim());
    if (minutes == null) {
      return fallback;
    }
    return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  }

  /// Formats [time] as a zero-padded 24-hour `HH:MM` string.
  static String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Initializes the condition state fields from [initialConditions].
  void _initialize(Iterable<TaskCondition> initialConditions) {
    for (final condition in initialConditions) {
      switch (condition) {
        case GlobalResetTaskCondition():
          if (allowResets) {
            _conditionAny = true;
          }
        case GroupResetTaskCondition(:final targetGroup):
          if (!allowResets) {
            break;
          }
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

  /// Opens a 24-hour Material 3 time picker and writes `HH:MM` into [controller].
  Future<void> _pickTimeIntoController(
    BuildContext context,
    TextEditingController controller, {
    required TimeOfDay defaultTime,
  }) async {
    final initialTime = _extractTimeOfDay(controller.text, defaultTime);
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: _build24HourTimePicker,
    );
    if (pickedTime == null) {
      return;
    }
    controller.text = _formatTimeOfDay(pickedTime);
    _timeErrorMessage = null;
    notifyListeners();
  }
}

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
            if (allowResets)
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
            if (allowResets)
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
            if (allowResets)
              TaskEditorChip(
                chipKey: const ValueKey(
                  'task_editor_condition_time_any_toggle',
                ),
                icon: Icons.schedule_rounded,
                label: localizations.conditionTimeAnyLabel,
                isSelected: conditionTimeAny,
                accentColor: appTheme.tertiaryAccent,
                onTap: onToggleTimeAny,
              ),
          ],
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
        _TaskEditorTimeInputRow(
          startController: startController,
          endController: endController,
          errorMessage: errorMessage,
          onAdd: onAddTimeCondition,
          onPickStartTime: onPickStartTime,
          onPickEndTime: onPickEndTime,
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
                backgroundColor: appTheme.secondaryContainerColor,
                foregroundColor: appTheme.onSecondaryContainerColor,
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
    required this.onPickEndTime,
    required this.onPickStartTime,
  });

  /// Controller for the end time (`HH:MM`).
  final TextEditingController endController;

  /// Optional validation error message.
  final String? errorMessage;

  /// Callback invoked when the add time window button is pressed.
  final VoidCallback onAdd;

  /// Callback invoked to open the end time picker.
  final VoidCallback onPickEndTime;

  /// Callback invoked to open the start time picker.
  final VoidCallback onPickStartTime;

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
                pickerKey: const ValueKey(
                  'task_editor_time_start_picker_button',
                ),
                controller: startController,
                hintText: localizations.conditionTimeStartHint,
                pickerTooltip: localizations.tooltipPickStartTime,
                onPickTime: onPickStartTime,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildTimeField(
                appTheme: appTheme,
                fieldKey: const ValueKey('task_editor_time_end_input'),
                pickerKey: const ValueKey('task_editor_time_end_picker_button'),
                controller: endController,
                hintText: localizations.conditionTimeEndHint,
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

  /// Builds a compact single-line text field for `HH:MM` time input with a trailing time picker button.
  Widget _buildTimeField({
    required AppTheme appTheme,
    required Key fieldKey,
    required Key pickerKey,
    required TextEditingController controller,
    required String hintText,
    required String pickerTooltip,
    required VoidCallback onPickTime,
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
        suffixIcon: IconButton(
          key: pickerKey,
          visualDensity: VisualDensity.compact,
          tooltip: pickerTooltip,
          icon: Icon(
            Icons.access_time_rounded,
            size: 16,
            color: appTheme.tertiaryAccent,
          ),
          onPressed: onPickTime,
        ),
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
