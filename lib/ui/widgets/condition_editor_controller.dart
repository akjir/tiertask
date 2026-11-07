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
