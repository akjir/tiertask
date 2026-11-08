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
import '../app_theme.dart';
import 'clearable_text_field.dart';
import 'task_editor_sections.dart';

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
          tooltip: localizations.tooltipTaskEditorPriority,
          isSelected: mode == QuickAddMode.priority,
          accentColor: appTheme.primaryAccent,
          onTap: onTogglePriority,
        ),
        TaskEditorChip(
          chipKey: const ValueKey('task_editor_someday_button'),
          icon: Icons.lightbulb_outline_rounded,
          label: localizations.tierName(TaskTier.someday),
          tooltip: localizations.tooltipTaskEditorSomeday,
          isSelected: mode == QuickAddMode.someday,
          accentColor: appTheme.secondaryAccent,
          onTap: onToggleSomeday,
        ),
        TaskEditorChip(
          chipKey: const ValueKey('task_editor_suspended_button'),
          icon: Icons.pause_circle_outline_rounded,
          label: localizations.taskSuspendedLabel,
          tooltip: localizations.tooltipTaskEditorSuspended,
          isSelected: isSuspended,
          accentColor: appTheme.warningAccent,
          onTap: onToggleSuspended,
        ),
        TaskEditorChip(
          chipKey: const ValueKey('task_editor_repeat_button'),
          icon: Icons.repeat_rounded,
          label: localizations.repeatFlagLabel,
          tooltip: localizations.tooltipTaskEditorRepeat,
          isSelected: isRepeating,
          accentColor: appTheme.tertiaryAccent,
          onTap: onToggleRepeat,
        ),
      ],
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCountField(localizations, appTheme),
        const SizedBox(height: 8),
        _buildUnitChips(localizations, appTheme),
      ],
    );
  }

  /// Resolves the `repeat` rule when [isRepeating] is enabled, or `null` when disabled or invalid.
  static TaskRepeatRule? parseRepeatRule({
    required bool isRepeating,
    required String rawCount,
    required RepeatUnit unit,
  }) {
    if (!isRepeating) {
      return null;
    }
    final parsedCount = int.tryParse(rawCount.trim());
    if (parsedCount == null ||
        parsedCount < 1 ||
        parsedCount > TaskRepeatRule.maxRepeatCount) {
      return null;
    }
    return TaskRepeatRule(count: parsedCount, unit: unit);
  }

  /// Builds the numeric recurrence interval count text field.
  Widget _buildCountField(AppLocalizations localizations, AppTheme appTheme) {
    final borderRadius = BorderRadius.circular(14);
    final defaultBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(
        color: appTheme.mutedTextColor.withValues(alpha: 0.35),
      ),
    );
    return ClearableTextField(
      fieldKey: const ValueKey('task_editor_repeat_count_input'),
      controller: countController,
      keyboardType: TextInputType.number,
      cursorColor: appTheme.tertiaryAccent,
      clearIconColor: appTheme.mutedTextColor,
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
          borderSide: BorderSide(color: appTheme.tertiaryAccent, width: 1.6),
        ),
      ),
    );
  }

  /// Builds the recurrence unit selection chip row (`days`, `weeks`, `months`).
  Widget _buildUnitChips(AppLocalizations localizations, AppTheme appTheme) {
    return Wrap(
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
    );
  }
}

/// Card grouping the scheduling mode chips, optional `suspended` timestamp field, and optional `repeat` rule.
class TaskEditorSchedulingCard extends StatelessWidget {
  /// Creates a [TaskEditorSchedulingCard].
  const TaskEditorSchedulingCard({
    super.key,
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

/// Optional `suspended` timestamp input field with modern date and time picker options.
class TaskEditorSuspendedField extends StatelessWidget {
  /// Creates a [TaskEditorSuspendedField].
  const TaskEditorSuspendedField({
    super.key,
    required this.controller,
    required this.errorMessage,
    required this.onClear,
    required this.onPickDate,
    required this.onPickTime,
  });

  /// Controller for the optional `suspended` timestamp input.
  final TextEditingController controller;

  /// Optional validation error message.
  final String? errorMessage;

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
    return ClearableTextField(
      fieldKey: const ValueKey('task_editor_suspended_input'),
      clearButtonKey: const ValueKey('task_editor_suspended_clear_button'),
      clearTooltip: localizations.tooltipClearDate,
      clearIconColor: appTheme.mutedTextColor,
      showClearWhenUnfocused: true,
      onCleared: onClear,
      controller: controller,
      cursorColor: appTheme.warningAccent,
      style: TextStyle(color: appTheme.primaryTextColor, fontSize: 14),
      decoration: _buildDecoration(localizations, appTheme),
    );
  }

  /// Formats an initial `suspended` timestamp for the input field (omitting `defaultSuspendedAt`).
  static String formatInitialText(DateTime? suspendedAt) {
    if (suspendedAt == null || suspendedAt == TaskItem.defaultSuspendedAt) {
      return '';
    }
    return TaskItem.formatTdfTimestamp(suspendedAt);
  }

  /// Resolves the `suspendedAt` timestamp when [isSuspended] is enabled, or `null` when disabled.
  static DateTime? parseSuspendedTimestamp({
    required bool isSuspended,
    required String rawText,
  }) {
    if (!isSuspended) {
      return null;
    }
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      return TaskItem.defaultSuspendedAt;
    }
    return TaskItem.tryParseTdfTimestampInput(trimmed);
  }

  /// Opens a Material 3 date picker and returns the updated `YYYY-MM-DD` (or `YYYY-MM-DD HH:MM`) text.
  static Future<String?> pickSuspendedDate({
    required BuildContext context,
    required String currentText,
    required DateTime fallbackDate,
  }) async {
    final initialDate = _resolveInitialSuspendedDate(currentText, fallbackDate);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(2100, 12, 31),
    );
    if (pickedDate == null) {
      return null;
    }
    final formattedDate = TaskItem.formatIsoDate(pickedDate);
    final existingTime = _extractTimeSuffix(currentText);
    return existingTime != null
        ? '$formattedDate $existingTime'
        : formattedDate;
  }

  /// Opens a 24-hour Material 3 time picker and returns the updated `YYYY-MM-DD HH:MM` text.
  static Future<String?> pickSuspendedTime({
    required BuildContext context,
    required String currentText,
    required DateTime fallbackDate,
  }) async {
    final existingTimeSuffix = _extractTimeSuffix(currentText);
    final initialTime = _extractTimeOfDay(
      existingTimeSuffix ?? '',
      const TimeOfDay(hour: 9, minute: 0),
    );
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: _build24HourTimePicker,
    );
    if (pickedTime == null) {
      return null;
    }
    final datePart =
        _extractDatePart(currentText) ?? TaskItem.formatIsoDate(fallbackDate);
    final formattedTime = _formatTimeOfDay(pickedTime);
    return '$datePart $formattedTime';
  }

  /// Wraps a [showTimePicker] dialog in a 24-hour [MediaQuery] configuration.
  static Widget _build24HourTimePicker(BuildContext context, Widget? child) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child ?? const SizedBox.shrink(),
    );
  }

  /// Builds the [InputDecoration] for the suspended timestamp text field.
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
      labelText: localizations.taskSuspendedUntilLabel,
      labelStyle: TextStyle(color: appTheme.mutedTextColor),
      hintText: localizations.taskSuspendedUntilHint,
      hintStyle: TextStyle(color: appTheme.mutedTextColor),
      errorText: errorMessage,
      isDense: true,
      filled: true,
      fillColor: appTheme.canvasColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      suffixIcon: _buildPickerSuffixActions(localizations, appTheme),
      border: defaultBorder,
      enabledBorder: defaultBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: appTheme.warningAccent, width: 1.6),
      ),
    );
  }

  /// Builds the trailing date picker and time picker icon buttons.
  Widget _buildPickerSuffixActions(
    AppLocalizations localizations,
    AppTheme appTheme,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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

  /// Extracts a valid `YYYY-MM-DD` date prefix from [rawInput], or `null` if invalid.
  static String? _extractDatePart(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.length < 10) {
      return null;
    }
    final candidate = trimmed.substring(0, 10);
    return TaskItem.tryParseIsoDate(candidate) != null ? candidate : null;
  }

  /// Parses [rawTime] (`HH:MM`) into a [TimeOfDay], or returns [fallback] if invalid.
  static TimeOfDay _extractTimeOfDay(String rawTime, TimeOfDay fallback) {
    final minutes = TaskItem.tryParseTimeMinutes(rawTime.trim());
    if (minutes == null) {
      return fallback;
    }
    return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  }

  /// Extracts a valid `HH:MM` suffix from a `YYYY-MM-DD HH:MM` timestamp string, or `null`.
  static String? _extractTimeSuffix(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.length <= 10) {
      return null;
    }
    final remainder = trimmed.substring(10).trim();
    if (remainder.length >= 5) {
      final hhMm = remainder.substring(0, 5);
      if (TaskItem.tryParseTimeMinutes(hhMm) != null) {
        return hhMm;
      }
    }
    return null;
  }

  /// Formats [time] as a zero-padded 24-hour `HH:MM` string.
  static String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Resolves the initial [DateTime] for the suspended date picker from [rawInput] or [fallback].
  static DateTime _resolveInitialSuspendedDate(
    String rawInput,
    DateTime fallback,
  ) {
    final datePart = _extractDatePart(rawInput);
    if (datePart != null) {
      final parsed = TaskItem.tryParseIsoDate(datePart);
      if (parsed != null && parsed.year >= 2000 && parsed.year <= 2100) {
        return parsed;
      }
    }
    return DateTime.utc(fallback.year, fallback.month, fallback.day);
  }
}
