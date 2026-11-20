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

import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/tier_localization_extension.dart';
import '../../models/task_item.dart';
import '../../models/task_tier.dart';
import '../../models/tdf_error.dart';
import '../../models/tdf_sync_metadata.dart';
import '../../models/tdf_timezone.dart';
import '../../models/webdav_config.dart';
import '../app_theme.dart';
import 'clearable_text_field.dart';
import 'task_editor_sections.dart';

/// Row of Priority, Someday, Suspended, Due, and Repeat chips inside the task editor.
class TaskEditorModeRow extends StatelessWidget {
  /// Creates a [TaskEditorModeRow].
  const TaskEditorModeRow({
    super.key,
    this.hasDue = false,
    required this.isRepeating,
    required this.isSuspended,
    required this.mode,
    this.onToggleDue,
    required this.onTogglePriority,
    required this.onToggleRepeat,
    required this.onToggleSomeday,
    required this.onToggleSuspended,
  });

  /// Whether the task has a due date/time enabled.
  final bool hasDue;

  /// Whether the task has recurrence enabled.
  final bool isRepeating;

  /// Whether the task is marked as suspended.
  final bool isSuspended;

  /// Active scheduling mode.
  final QuickAddMode mode;

  /// Callback invoked when Due is tapped.
  final VoidCallback? onToggleDue;

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
          chipKey: const ValueKey('task_editor_due_button'),
          icon: Icons.event_rounded,
          label: localizations.taskDueButtonLabel,
          isSelected: hasDue,
          accentColor: appTheme.secondaryAccent,
          onTap: onToggleDue ?? () {},
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

/// Recurrence interval (`repeat <count> <days|weeks|months> [<repeat-time>] [lead <lead-count> days]`) inputs inside the task editor.
class TaskEditorRepeatField extends StatelessWidget {
  /// Creates a [TaskEditorRepeatField].
  const TaskEditorRepeatField({
    super.key,
    required this.countController,
    required this.errorMessage,
    this.leadDaysController,
    this.leadDaysErrorMessage,
    required this.onSelectUnit,
    required this.selectedUnit,
    this.showLeadDays = false,
  });

  /// Controller for the numeric repeat interval count (`1..3650`).
  final TextEditingController countController;

  /// Optional validation error message for the repeat interval count.
  final String? errorMessage;

  /// Optional controller for the Mode 2 preparation lead offset in days (`0..3650`).
  final TextEditingController? leadDaysController;

  /// Optional validation error message for the preparation lead offset.
  final String? leadDaysErrorMessage;

  /// Callback invoked when a [RepeatUnit] chip is selected.
  final ValueChanged<RepeatUnit> onSelectUnit;

  /// Currently selected recurrence unit.
  final RepeatUnit selectedUnit;

  /// Whether the conditional preparation lead input is visible (`isRepeating && hasDue`).
  final bool showLeadDays;

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
        if (leadDaysController case final activeLeadController?
            when showLeadDays) ...[
          const SizedBox(height: 8),
          _RepeatLeadDaysInput(
            controller: activeLeadController,
            errorMessage: leadDaysErrorMessage,
          ),
        ],
      ],
    );
  }

  /// Parses [rawLeadDays] into a bounded integer in `0..3650`, returning `0` when disabled or blank, or `null` when invalid.
  static int? parseLeadDays({
    required bool hasDue,
    required bool isRepeating,
    required String rawLeadDays,
  }) {
    if (!isRepeating || !hasDue) {
      return 0;
    }
    final trimmed = rawLeadDays.trim();
    if (trimmed.isEmpty) {
      return 0;
    }
    return _tryParseBoundedUnsignedInt(
      trimmed,
      min: 0,
      max: TaskRepeatRule.maxRepeatCount,
    );
  }

  /// Parses [rawCount] into a bounded integer in `1..3650` when [isRepeating] is enabled, or returns `null`.
  static int? parseRepeatCount({
    required bool isRepeating,
    required String rawCount,
  }) {
    if (!isRepeating) {
      return null;
    }
    return _tryParseBoundedUnsignedInt(
      rawCount.trim(),
      min: 1,
      max: TaskRepeatRule.maxRepeatCount,
    );
  }

  /// Resolves the `repeat` rule when [isRepeating] is enabled, preserving [existingClock], or returns `null` when disabled or invalid.
  static TaskRepeatRule? parseRepeatRule({
    TdfRepeatClock existingClock = TdfRepeatClock.midnight,
    bool hasDue = false,
    required bool isRepeating,
    required String rawCount,
    String rawLeadDays = '',
    required RepeatUnit unit,
  }) {
    final parsedCount = parseRepeatCount(
      isRepeating: isRepeating,
      rawCount: rawCount,
    );
    final parsedLeadDays = parseLeadDays(
      hasDue: hasDue,
      isRepeating: isRepeating,
      rawLeadDays: rawLeadDays,
    );
    if (parsedCount == null || parsedLeadDays == null) {
      return null;
    }
    return TaskRepeatRule(
      count: parsedCount,
      unit: unit,
      clock: existingClock,
      leadDays: parsedLeadDays,
    );
  }

  /// Builds the numeric recurrence interval count text field.
  Widget _buildCountField(AppLocalizations localizations, AppTheme appTheme) {
    return ClearableTextField(
      fieldKey: const ValueKey('task_editor_repeat_count_input'),
      controller: countController,
      keyboardType: TextInputType.number,
      cursorColor: appTheme.tertiaryAccent,
      clearIconColor: appTheme.mutedTextColor,
      style: TextStyle(color: appTheme.primaryTextColor, fontSize: 14),
      decoration: _buildSchedulingInputDecoration(
        appTheme: appTheme,
        errorText: errorMessage,
        focusedColor: appTheme.tertiaryAccent,
        labelText: localizations.repeatIntervalLabel,
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

/// Card grouping the scheduling mode chips, optional `suspended` timestamp and note, optional `due` timestamp and note, and optional `repeat` rule.
class TaskEditorSchedulingCard extends StatelessWidget {
  /// Creates a [TaskEditorSchedulingCard].
  const TaskEditorSchedulingCard({
    super.key,
    this.autoPrioritizeDue = true,
    this.dueController,
    this.dueErrorMessage,
    this.dueNoteController,
    this.dueNoteErrorMessage,
    this.hasDue = false,
    required this.isRepeating,
    required this.isSuspended,
    required this.mode,
    this.onClearDue,
    required this.onClearSuspended,
    this.onPickDueDate,
    this.onPickDueTime,
    required this.onPickSuspendedDate,
    required this.onPickSuspendedTime,
    required this.onSelectRepeatUnit,
    this.onToggleAutoPrioritizeDue,
    this.onToggleDue,
    required this.onTogglePriority,
    required this.onToggleRepeat,
    required this.onToggleSomeday,
    required this.onToggleSuspended,
    required this.repeatCountController,
    required this.repeatErrorMessage,
    this.repeatLeadDaysController,
    this.repeatLeadDaysErrorMessage,
    required this.repeatUnit,
    this.showDueAutoPrioritizeToggle = false,
    required this.suspendedController,
    required this.suspendedErrorMessage,
    this.suspendedNoteController,
    this.suspendedNoteErrorMessage,
  });

  /// Whether deadline auto-prioritization (`!isDuePassive`) is enabled.
  final bool autoPrioritizeDue;

  /// Controller for the optional `due` timestamp input.
  final TextEditingController? dueController;

  /// Optional validation error message for the `due` timestamp.
  final String? dueErrorMessage;

  /// Optional controller for the multi-line `dueNote` input.
  final TextEditingController? dueNoteController;

  /// Optional validation error message for the `dueNote` input.
  final String? dueNoteErrorMessage;

  /// Whether the task has a `due` timestamp enabled.
  final bool hasDue;

  /// Whether the task has recurrence enabled.
  final bool isRepeating;

  /// Whether the task is marked as suspended.
  final bool isSuspended;

  /// Active scheduling mode.
  final QuickAddMode mode;

  /// Callback invoked to clear the `due` timestamp field.
  final VoidCallback? onClearDue;

  /// Callback invoked to clear the suspended timestamp field.
  final VoidCallback onClearSuspended;

  /// Callback invoked to open the date picker for the `due` timestamp.
  final VoidCallback? onPickDueDate;

  /// Callback invoked to open the time picker for the `due` timestamp.
  final VoidCallback? onPickDueTime;

  /// Callback invoked to open the date picker for the suspended timestamp.
  final VoidCallback onPickSuspendedDate;

  /// Callback invoked to open the time picker for the suspended timestamp.
  final VoidCallback onPickSuspendedTime;

  /// Callback invoked when a [RepeatUnit] is selected.
  final ValueChanged<RepeatUnit> onSelectRepeatUnit;

  /// Callback invoked when the auto-prioritize deadline switch changes.
  final ValueChanged<bool>? onToggleAutoPrioritizeDue;

  /// Callback invoked when Due is tapped.
  final VoidCallback? onToggleDue;

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

  /// Optional controller for the Mode 2 preparation lead days input.
  final TextEditingController? repeatLeadDaysController;

  /// Optional validation error message for the preparation lead days input.
  final String? repeatLeadDaysErrorMessage;

  /// Selected recurrence unit.
  final RepeatUnit repeatUnit;

  /// Whether the auto-prioritize deadline switch is visible when [hasDue] is `true`.
  final bool showDueAutoPrioritizeToggle;

  /// Controller for the optional `suspended` timestamp input.
  final TextEditingController suspendedController;

  /// Optional validation error message for the suspended timestamp.
  final String? suspendedErrorMessage;

  /// Optional controller for the multi-line `suspendedNote` input.
  final TextEditingController? suspendedNoteController;

  /// Optional validation error message for the `suspendedNote` input.
  final String? suspendedNoteErrorMessage;

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
            hasDue: hasDue,
            isRepeating: isRepeating,
            isSuspended: isSuspended,
            mode: mode,
            onToggleDue: onToggleDue,
            onTogglePriority: onTogglePriority,
            onToggleRepeat: onToggleRepeat,
            onToggleSomeday: onToggleSomeday,
            onToggleSuspended: onToggleSuspended,
          ),
          if (isSuspended) _TaskEditorSuspendedSection(card: this),
          if (dueController case final activeDueController? when hasDue)
            _TaskEditorDueSection(card: this, controller: activeDueController),
          if (isRepeating) _TaskEditorRepeatSection(card: this),
        ],
      ),
    );
  }
}

/// Clearable multi-line text field (`1..3` visible lines, `<= 2000` Unicode scalars) for `suspendedNote` and `dueNote`.
class TaskEditorSchedulingNoteField extends StatelessWidget {
  /// Creates a [TaskEditorSchedulingNoteField].
  const TaskEditorSchedulingNoteField({
    super.key,
    required this.clearButtonKey,
    required this.controller,
    this.errorMessage,
    required this.fieldKey,
    required this.focusedColor,
    required this.hintText,
    required this.labelText,
  });

  /// Widget key for the inline clear button.
  final Key clearButtonKey;

  /// Controller managing the note text.
  final TextEditingController controller;

  /// Optional localized validation error message.
  final String? errorMessage;

  /// Widget key for the underlying [TextField].
  final Key fieldKey;

  /// Accent color applied to the cursor and focused border.
  final Color focusedColor;

  /// Placeholder hint displayed when the field is empty.
  final String hintText;

  /// Floating input label text.
  final String labelText;

  @override
  Widget build(BuildContext context) {
    final appTheme = AppTheme.of(context);
    return ClearableTextField(
      fieldKey: fieldKey,
      clearButtonKey: clearButtonKey,
      clearIconColor: appTheme.mutedTextColor,
      showClearWhenUnfocused: true,
      controller: controller,
      cursorColor: focusedColor,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      minLines: 1,
      maxLines: 3,
      style: TextStyle(color: appTheme.primaryTextColor, fontSize: 14),
      decoration: _buildSchedulingInputDecoration(
        appTheme: appTheme,
        errorText: errorMessage,
        focusedColor: focusedColor,
        hintText: hintText,
        labelText: labelText,
      ),
    );
  }

  /// Normalizes user-edited [rawText], collapsing ASCII-whitespace-only strings to `null` and CR/CRLF line breaks to `\n`.
  static String? normalizeSchedulingNote(String rawText) {
    var hasGraphic = false;
    var firstCrIndex = -1;
    for (var i = 0; i < rawText.length; i++) {
      final unit = rawText.codeUnitAt(i);
      if (unit == 0x0D && firstCrIndex < 0) {
        firstCrIndex = i;
      }
      if (unit != 0x09 && unit != 0x0A && unit != 0x0D && unit != 0x20) {
        hasGraphic = true;
      }
    }
    if (!hasGraphic) {
      return null;
    }
    if (firstCrIndex < 0) {
      return rawText;
    }
    return _collapseCrLineEndings(rawText, firstCrIndex);
  }

  /// Validates [normalizedNote] against `<note>` control-character, surrogate, and `maxTdfNoteLength` (`2000`) bounds.
  static String? validateSchedulingNote(
    String? normalizedNote,
    AppLocalizations localizations,
  ) {
    if (normalizedNote == null) {
      return null;
    }
    final scalarCount = TdfCalendar.countUnicodeScalars(normalizedNote);
    if (scalarCount == null ||
        _containsIllegalNoteControlChar(normalizedNote)) {
      return localizations.schedulingNoteErrorInvalid;
    }
    if (scalarCount > maxTdfNoteLength) {
      return localizations.schedulingNoteErrorTooLong;
    }
    return null;
  }
}

/// Optional `suspended` (or `due`) timestamp input field with modern date and time picker options.
class TaskEditorSuspendedField extends StatelessWidget {
  /// Creates a [TaskEditorSuspendedField].
  const TaskEditorSuspendedField({
    super.key,
    this.clearButtonKey = const ValueKey('task_editor_suspended_clear_button'),
    this.clearTooltipOverride,
    required this.controller,
    this.datePickerKey = const ValueKey(
      'task_editor_suspended_date_picker_button',
    ),
    required this.errorMessage,
    this.fieldKey = const ValueKey('task_editor_suspended_input'),
    this.labelTextOverride,
    required this.onClear,
    required this.onPickDate,
    required this.onPickTime,
    this.timePickerKey = const ValueKey(
      'task_editor_suspended_time_picker_button',
    ),
  });

  /// Widget key for the clear button.
  final Key clearButtonKey;

  /// Optional custom tooltip for the clear button.
  final String? clearTooltipOverride;

  /// Controller for the timestamp input.
  final TextEditingController controller;

  /// Widget key for the date picker button.
  final Key datePickerKey;

  /// Optional validation error message.
  final String? errorMessage;

  /// Widget key for the text field.
  final Key fieldKey;

  /// Optional custom label text.
  final String? labelTextOverride;

  /// Callback invoked to clear the timestamp input.
  final VoidCallback onClear;

  /// Callback invoked to open the Material 3 date picker.
  final VoidCallback onPickDate;

  /// Callback invoked to open the Material 3 time picker.
  final VoidCallback onPickTime;

  /// Widget key for the time picker button.
  final Key timePickerKey;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    return ClearableTextField(
      fieldKey: fieldKey,
      clearButtonKey: clearButtonKey,
      clearTooltip: clearTooltipOverride ?? localizations.tooltipClearDate,
      clearIconColor: appTheme.mutedTextColor,
      showClearWhenUnfocused: true,
      onCleared: onClear,
      controller: controller,
      cursorColor: appTheme.warningAccent,
      style: TextStyle(color: appTheme.primaryTextColor, fontSize: 14),
      decoration: _buildDecoration(localizations, appTheme),
    );
  }

  /// Formats an initial `suspended` UTC timestamp in [configuration]'s local wall-clock time (omitting `defaultSuspendedAt`).
  static String formatInitialText(
    DateTime? suspendedAt, [
    WebDavConfig configuration = const WebDavConfig(),
  ]) {
    if (suspendedAt == null || suspendedAt == TaskItem.defaultSuspendedAt) {
      return '';
    }
    return formatLocalTimestamp(suspendedAt, configuration);
  }

  /// Formats an optional UTC [instant] in [configuration]'s local wall-clock time, or `''` when `null`.
  static String formatLocalTimestamp(
    DateTime? instant,
    WebDavConfig configuration,
  ) {
    if (instant == null) {
      return '';
    }
    return TaskItem.formatTdfTimestamp(configuration.toLocalWallClock(instant));
  }

  /// Opens a Material 3 date picker and returns the updated `YYYY-MM-DD` (or `YYYY-MM-DD HH:MM[:SS]`) text.
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

  /// Parses [rawText] as a local calendar timestamp and resolves its UTC instant under [configuration] (`TDF-CAL-001`), returning `null` if invalid.
  static ({TdfLocalDateTime localInput, DateTime resolvedUtc})?
  tryParseLocalDateTimeInput(String rawText, WebDavConfig configuration) {
    final parsedWallClock = TaskItem.tryParseTdfTimestampInput(rawText.trim());
    if (parsedWallClock == null) {
      return null;
    }
    try {
      final localInput = TdfLocalDateTime.fromWallClock(parsedWallClock);
      final resolvedUtc = TaskItem.normalizeTimestamp(
        configuration.localWallClockToUtc(parsedWallClock),
      );
      if (!TdfCalendar.isWithinTimestampBounds(resolvedUtc)) {
        return null;
      }
      return (localInput: localInput, resolvedUtc: resolvedUtc);
    } on TdfException {
      return null;
    } on TdfContextException {
      return null;
    } on FormatException {
      return null;
    }
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
      labelText: labelTextOverride ?? localizations.taskSuspendedUntilLabel,
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
          key: datePickerKey,
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
          key: timePickerKey,
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

  /// Parses [rawTime] (`HH:MM` or `HH:MM:SS`) into a [TimeOfDay], or returns [fallback] if invalid.
  static TimeOfDay _extractTimeOfDay(String rawTime, TimeOfDay fallback) {
    final parsed = TaskItem.tryParseTdfTimestamp('2000-01-01', rawTime.trim());
    if (parsed == null) {
      return fallback;
    }
    return TimeOfDay(hour: parsed.hour, minute: parsed.minute);
  }

  /// Extracts a valid `HH:MM` or `HH:MM:SS` suffix from [rawInput], or `null`.
  static String? _extractTimeSuffix(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.length <= 10) {
      return null;
    }
    final separator = trimmed.codeUnitAt(10);
    if (separator != 0x20 && separator != 0x09) {
      return null;
    }
    final remainder = trimmed.substring(10).trim();
    return TaskItem.tryParseTdfTimestamp('2000-01-01', remainder) != null
        ? remainder
        : null;
  }

  /// Formats [time] as a zero-padded 24-hour `HH:MM` string.
  static String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Resolves the initial [DateTime] within `2000-01-01..2100-12-31` for the suspended date picker from [rawInput] or [fallback].
  static DateTime _resolveInitialSuspendedDate(
    String rawInput,
    DateTime fallback,
  ) {
    if (_extractDatePart(rawInput) case final datePart?) {
      final parsed = TaskItem.tryParseIsoDate(datePart);
      if (parsed != null && parsed.year >= 2000 && parsed.year <= 2100) {
        return parsed;
      }
    }
    if (fallback.year < 2000) {
      return DateTime.utc(2000);
    }
    if (fallback.year > 2100) {
      return DateTime.utc(2100, 12, 31);
    }
    return DateTime.utc(fallback.year, fallback.month, fallback.day);
  }
}

/// Numeric preparation lead offset (`lead <lead-count> days`) field shown when both `Repeat` and `Due` are active.
class _RepeatLeadDaysInput extends StatelessWidget {
  /// Creates a [_RepeatLeadDaysInput].
  const _RepeatLeadDaysInput({required this.controller, this.errorMessage});

  /// Controller for the numeric preparation lead days (`0..3650`).
  final TextEditingController controller;

  /// Optional localized validation error message.
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    return ClearableTextField(
      fieldKey: const ValueKey('task_editor_repeat_lead_days_input'),
      clearButtonKey: const ValueKey(
        'task_editor_repeat_lead_days_clear_button',
      ),
      clearIconColor: appTheme.mutedTextColor,
      showClearWhenUnfocused: true,
      controller: controller,
      keyboardType: TextInputType.number,
      cursorColor: appTheme.tertiaryAccent,
      style: TextStyle(color: appTheme.primaryTextColor, fontSize: 14),
      decoration: _buildSchedulingInputDecoration(
        appTheme: appTheme,
        errorText: errorMessage,
        focusedColor: appTheme.tertiaryAccent,
        hintText: localizations.repeatLeadDaysHint,
        labelText: localizations.repeatLeadDaysLabel,
      ),
    );
  }
}

/// Labeled switch row toggling deadline auto-prioritization (`!isDuePassive`).
class _TaskEditorDueAutoPrioritizeRow extends StatelessWidget {
  /// Creates a [_TaskEditorDueAutoPrioritizeRow].
  const _TaskEditorDueAutoPrioritizeRow({
    required this.autoPrioritizeDue,
    required this.onChanged,
  });

  /// Whether deadline auto-prioritization is enabled.
  final bool autoPrioritizeDue;

  /// Optional callback invoked when the switch is toggled.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      spacing: 12,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(
                localizations.taskDueAutoPrioritizeLabel,
                style: theme.textTheme.titleSmall,
              ),
              Text(
                localizations.taskDueAutoPrioritizeSubtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Switch(
          key: const ValueKey('task_editor_due_auto_prioritize_switch'),
          value: autoPrioritizeDue,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Renders the `due` timestamp input, optional auto-prioritization switch, and optional `dueNote` input.
class _TaskEditorDueSection extends StatelessWidget {
  /// Creates a [_TaskEditorDueSection].
  const _TaskEditorDueSection({required this.card, required this.controller});

  /// Parent scheduling card configuration.
  final TaskEditorSchedulingCard card;

  /// Active controller for the `due` timestamp input.
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        _TaskEditorDueTimestampField(
          controller: controller,
          errorMessage: card.dueErrorMessage,
          onClear: card.onClearDue,
          onPickDate: card.onPickDueDate,
          onPickTime: card.onPickDueTime,
        ),
        if (card.showDueAutoPrioritizeToggle) ...[
          const SizedBox(height: 8),
          _TaskEditorDueAutoPrioritizeRow(
            autoPrioritizeDue: card.autoPrioritizeDue,
            onChanged: card.onToggleAutoPrioritizeDue,
          ),
        ],
        if (card.dueNoteController case final activeNoteController?) ...[
          const SizedBox(height: 8),
          TaskEditorSchedulingNoteField(
            clearButtonKey: const ValueKey('task_editor_due_note_clear_button'),
            controller: activeNoteController,
            errorMessage: card.dueNoteErrorMessage,
            fieldKey: const ValueKey('task_editor_due_note_input'),
            focusedColor: appTheme.secondaryAccent,
            hintText: localizations.taskDueNoteHint,
            labelText: localizations.taskDueNoteLabel,
          ),
        ],
      ],
    );
  }
}

/// Renders the `due` timestamp picker field inside [_TaskEditorDueSection].
class _TaskEditorDueTimestampField extends StatelessWidget {
  /// Creates a [_TaskEditorDueTimestampField].
  const _TaskEditorDueTimestampField({
    required this.controller,
    required this.errorMessage,
    required this.onClear,
    required this.onPickDate,
    required this.onPickTime,
  });

  /// Controller for the `due` timestamp input.
  final TextEditingController controller;

  /// Optional validation error message for the `due` timestamp.
  final String? errorMessage;

  /// Optional callback invoked to clear the `due` input.
  final VoidCallback? onClear;

  /// Optional callback invoked to pick a `due` date.
  final VoidCallback? onPickDate;

  /// Optional callback invoked to pick a `due` time.
  final VoidCallback? onPickTime;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return TaskEditorSuspendedField(
      controller: controller,
      errorMessage: errorMessage,
      fieldKey: const ValueKey('task_editor_due_input'),
      clearButtonKey: const ValueKey('task_editor_due_clear_button'),
      datePickerKey: const ValueKey('task_editor_due_date_picker_button'),
      timePickerKey: const ValueKey('task_editor_due_time_picker_button'),
      labelTextOverride: localizations.taskDueButtonLabel,
      clearTooltipOverride: localizations.taskDueClearTooltip,
      onClear: onClear ?? controller.clear,
      onPickDate: onPickDate ?? () {},
      onPickTime: onPickTime ?? () {},
    );
  }
}

/// Renders the recurrence section inside [TaskEditorSchedulingCard].
class _TaskEditorRepeatSection extends StatelessWidget {
  /// Creates a [_TaskEditorRepeatSection].
  const _TaskEditorRepeatSection({required this.card});

  /// Parent scheduling card configuration.
  final TaskEditorSchedulingCard card;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TaskEditorRepeatField(
        countController: card.repeatCountController,
        errorMessage: card.repeatErrorMessage,
        leadDaysController: card.repeatLeadDaysController,
        leadDaysErrorMessage: card.repeatLeadDaysErrorMessage,
        onSelectUnit: card.onSelectRepeatUnit,
        selectedUnit: card.repeatUnit,
        showLeadDays: card.hasDue,
      ),
    );
  }
}

/// Renders the `suspended` timestamp field and optional multi-line `suspendedNote` field.
class _TaskEditorSuspendedSection extends StatelessWidget {
  /// Creates a [_TaskEditorSuspendedSection].
  const _TaskEditorSuspendedSection({required this.card});

  /// Parent scheduling card configuration.
  final TaskEditorSchedulingCard card;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        TaskEditorSuspendedField(
          controller: card.suspendedController,
          errorMessage: card.suspendedErrorMessage,
          onClear: card.onClearSuspended,
          onPickDate: card.onPickSuspendedDate,
          onPickTime: card.onPickSuspendedTime,
        ),
        if (card.suspendedNoteController case final activeNoteController?) ...[
          const SizedBox(height: 8),
          TaskEditorSchedulingNoteField(
            clearButtonKey: const ValueKey(
              'task_editor_suspended_note_clear_button',
            ),
            controller: activeNoteController,
            errorMessage: card.suspendedNoteErrorMessage,
            fieldKey: const ValueKey('task_editor_suspended_note_input'),
            focusedColor: appTheme.warningAccent,
            hintText: localizations.taskSuspendedNoteHint,
            labelText: localizations.taskSuspendedNoteLabel,
          ),
        ],
      ],
    );
  }
}

/// Builds a shared dense Material 3 [InputDecoration] for scheduling text inputs.
InputDecoration _buildSchedulingInputDecoration({
  required AppTheme appTheme,
  String? errorText,
  required Color focusedColor,
  String? hintText,
  required String labelText,
}) {
  final borderRadius = BorderRadius.circular(14);
  final defaultBorder = OutlineInputBorder(
    borderRadius: borderRadius,
    borderSide: BorderSide(
      color: appTheme.mutedTextColor.withValues(alpha: 0.35),
    ),
  );
  return InputDecoration(
    labelText: labelText,
    labelStyle: TextStyle(color: appTheme.mutedTextColor),
    hintText: hintText,
    hintStyle: TextStyle(color: appTheme.mutedTextColor),
    errorText: errorText,
    isDense: true,
    filled: true,
    fillColor: appTheme.canvasColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: defaultBorder,
    enabledBorder: defaultBorder,
    focusedBorder: OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: focusedColor, width: 1.6),
    ),
  );
}

/// Collapses `\r\n` and standalone `\r` sequences starting at [firstCrIndex] into `\n` in a single pass.
String _collapseCrLineEndings(String rawText, int firstCrIndex) {
  final buffer = StringBuffer(rawText.substring(0, firstCrIndex));
  for (var i = firstCrIndex; i < rawText.length; i++) {
    final unit = rawText.codeUnitAt(i);
    if (unit == 0x0D) {
      buffer.write('\n');
      if (i + 1 < rawText.length && rawText.codeUnitAt(i + 1) == 0x0A) {
        i++;
      }
      continue;
    }
    buffer.writeCharCode(unit);
  }
  return buffer.toString();
}

/// Returns whether [text] contains any control character disallowed by `<note>` (`0x00..0x1F` except `\t`, `\n`, `\r`, or `0x7F`).
bool _containsIllegalNoteControlChar(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    final isDisallowedLowControl =
        unit <= 0x1F && unit != 0x09 && unit != 0x0A && unit != 0x0D;
    if (isDisallowedLowControl || unit == 0x7F) {
      return true;
    }
  }
  return false;
}

/// Parses an unsigned ASCII decimal integer in `[min, max]` bounded by `maxTdfNumberLength`, or returns `null`.
int? _tryParseBoundedUnsignedInt(
  String trimmed, {
  required int min,
  required int max,
}) {
  if (trimmed.isEmpty || trimmed.length > maxTdfNumberLength) {
    return null;
  }
  var value = 0;
  for (var i = 0; i < trimmed.length; i++) {
    final unit = trimmed.codeUnitAt(i);
    if (unit < 0x30 || unit > 0x39) {
      return null;
    }
    value = (value * 10) + (unit - 0x30);
    if (value > max) {
      return null;
    }
  }
  return value >= min ? value : null;
}
