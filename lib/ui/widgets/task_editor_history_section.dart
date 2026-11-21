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

/// Task history journal section and single-line history input validator for `EditTaskScreen`.
library;

import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import '../../models/webdav_config.dart';
import '../../presentation/task_editor_controller.dart';
import '../app_theme.dart';
import 'clearable_text_field.dart';
import 'task_editor_sections.dart';

/// Editor card managing chronological [TaskHistoryEntry] drafts inside `EditTaskScreen`.
class TaskEditorHistorySection extends StatelessWidget {
  /// Creates a [TaskEditorHistorySection].
  const TaskEditorHistorySection({
    super.key,
    required this.configuration,
    this.editingIndex,
    required this.entries,
    this.errorMessage,
    required this.onAddOrSaveEntry,
    required this.onCancelEdit,
    required this.onClearTimestamp,
    required this.onEditEntry,
    required this.onPickDate,
    required this.onPickTime,
    required this.onRemoveEntry,
    required this.textController,
    required this.timestampController,
  });

  /// Maximum number of history rows rendered directly inside a [Column] before switching to [ListView.builder].
  static const int maxInlineColumnRows = 5;

  /// Active workspace configuration used to format UTC timestamps into local wall-clock time.
  final WebDavConfig configuration;

  /// Active zero-based entry index being edited in place, or `null` when appending.
  final int? editingIndex;

  /// Canonically sorted draft history entries on the task.
  final List<TaskHistoryEntry> entries;

  /// Optional inline validation error message, or `null` when valid.
  final String? errorMessage;

  /// Callback invoked when the add/update button or `Enter` key is triggered.
  final VoidCallback onAddOrSaveEntry;

  /// Callback invoked to cancel an active inline entry edit.
  final VoidCallback onCancelEdit;

  /// Callback invoked when the timestamp field clear button is pressed.
  final VoidCallback onClearTimestamp;

  /// Callback invoked with the zero-based index to load an entry into the edit inputs.
  final ValueChanged<int> onEditEntry;

  /// Callback invoked when the date picker button is pressed.
  final VoidCallback onPickDate;

  /// Callback invoked when the time picker button is pressed.
  final VoidCallback onPickTime;

  /// Callback invoked with the zero-based index to delete a draft entry.
  final ValueChanged<int> onRemoveEntry;

  /// Controller for the single-line history `<text>` input field.
  final TextEditingController textController;

  /// Controller for the optional local wall-clock `<timestamp>` input field.
  final TextEditingController timestampController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return TaskEditorSectionCard(
      cardKey: const ValueKey('task_editor_history_card'),
      icon: Icons.history_rounded,
      title: localizations.historySectionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (entries.isNotEmpty) ...[
            _TaskEditorHistoryList(
              configuration: configuration,
              editingIndex: editingIndex,
              entries: entries,
              onEditEntry: onEditEntry,
              onRemoveEntry: onRemoveEntry,
            ),
            const SizedBox(height: 8),
          ],
          _TaskEditorHistoryTimestampField(
            controller: timestampController,
            onClearTimestamp: onClearTimestamp,
            onPickDate: onPickDate,
            onPickTime: onPickTime,
          ),
          const SizedBox(height: 8),
          _TaskEditorHistoryTextActionRow(
            isEditing: editingIndex != null,
            onAddOrSaveEntry: onAddOrSaveEntry,
            onCancelEdit: onCancelEdit,
            textController: textController,
          ),
          if (errorMessage case final error?)
            _TaskEditorHistoryErrorText(error),
        ],
      ),
    );
  }

  /// Opens a Material 3 date picker and returns the updated local timestamp text, or `null` if canceled.
  static Future<String?> pickHistoryDate({
    required BuildContext context,
    required String currentText,
    required DateTime fallbackLocal,
  }) async {
    final initialDate = _resolveInitialPickerDate(currentText, fallbackLocal);
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

  /// Opens a 24-hour Material 3 time picker and returns the updated local timestamp text, or `null` if canceled.
  static Future<String?> pickHistoryTime({
    required BuildContext context,
    required String currentText,
    required DateTime fallbackLocal,
  }) async {
    final existingTimeSuffix = _extractTimeSuffix(currentText);
    final initialTime = _extractTimeOfDay(existingTimeSuffix, fallbackLocal);
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: _build24HourTimePicker,
    );
    if (pickedTime == null) {
      return null;
    }
    final datePart =
        _extractDatePart(currentText) ?? TaskItem.formatIsoDate(fallbackLocal);
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

  /// Extracts a valid `YYYY-MM-DD` prefix from [rawInput], or `null` if invalid.
  static String? _extractDatePart(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.length < 10) {
      return null;
    }
    final candidate = trimmed.substring(0, 10);
    return TaskItem.tryParseIsoDate(candidate) != null ? candidate : null;
  }

  /// Resolves the initial [TimeOfDay] from [existingTimeSuffix] or [fallbackLocal].
  static TimeOfDay _extractTimeOfDay(
    String? existingTimeSuffix,
    DateTime fallbackLocal,
  ) {
    if (existingTimeSuffix != null && existingTimeSuffix.length >= 5) {
      final minutes = TaskItem.tryParseTimeMinutes(
        existingTimeSuffix.substring(0, 5),
      );
      if (minutes != null) {
        return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
      }
    }
    return TimeOfDay(hour: fallbackLocal.hour, minute: fallbackLocal.minute);
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

  /// Resolves a picker initial [DateTime] within `2000-01-01..2100-12-31` from [rawInput] or [fallbackLocal].
  static DateTime _resolveInitialPickerDate(
    String rawInput,
    DateTime fallbackLocal,
  ) {
    if (_extractDatePart(rawInput) case final datePart?) {
      final parsed = TaskItem.tryParseIsoDate(datePart);
      if (parsed != null && parsed.year >= 2000 && parsed.year <= 2100) {
        return parsed;
      }
    }
    if (fallbackLocal.year < 2000) {
      return DateTime.utc(2000);
    }
    if (fallbackLocal.year > 2100) {
      return DateTime.utc(2100, 12, 31);
    }
    return DateTime.utc(
      fallbackLocal.year,
      fallbackLocal.month,
      fallbackLocal.day,
    );
  }
}

/// Stateless sanitizer and validator for single-line TDF `history` `<timestamp>` and `<text>` inputs.
class TaskHistoryInputValidator {
  const TaskHistoryInputValidator._();

  /// Resolves [rawTimestamp] in [configuration]'s local wall-clock time to a normalized UTC [DateTime], or `null` if invalid.
  static DateTime? resolveEntryTimestampUtc({
    required WebDavConfig configuration,
    required DateTime fallbackNowUtc,
    String? preservedTimestampText,
    DateTime? preservedTimestampUtc,
    required String rawTimestamp,
  }) => TaskEditorController.resolveHistoryTimestampUtc(
    configuration: configuration,
    fallbackNowUtc: fallbackNowUtc,
    preservedTimestampText: preservedTimestampText,
    preservedTimestampUtc: preservedTimestampUtc,
    rawTimestamp: rawTimestamp,
  );

  /// Trims outer ASCII whitespace and collapses internal CR/LF/TAB sequences into single spaces.
  static String sanitizeSingleLineText(String rawText) =>
      TaskEditorController.sanitizeHistoryText(rawText);

  /// Validates [sanitizedText] against TDF `0.8.0` single-line `<text>` bounds, returning a localized error or `null`.
  static String? validateText(
    String sanitizedText,
    AppLocalizations localizations,
  ) => TaskEditorController.validateHistoryText(sanitizedText, localizations);
}

/// Inline validation error label rendered below the history input fields in [TaskEditorHistorySection].
class _TaskEditorHistoryErrorText extends StatelessWidget {
  /// Creates a [_TaskEditorHistoryErrorText].
  const _TaskEditorHistoryErrorText(this.message);

  /// Localized validation error message.
  final String message;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        message,
        key: const ValueKey('editor_history_error_text'),
        style: TextStyle(color: errorColor, fontSize: 12),
      ),
    );
  }
}

/// Compact icon button used inside [_TaskEditorHistoryRowActions] and [_TaskEditorHistoryTimestampSuffix].
class _TaskEditorHistoryIconButton extends StatelessWidget {
  /// Creates a [_TaskEditorHistoryIconButton].
  const _TaskEditorHistoryIconButton({
    required this.buttonKey,
    this.color,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  /// Deterministic widget key attached to the [IconButton].
  final Key buttonKey;

  /// Optional foreground tint for [icon].
  final Color? color;

  /// Icon glyph to display.
  final IconData icon;

  /// Callback invoked on tap, or `null` when disabled.
  final VoidCallback? onPressed;

  /// Localized accessibility tooltip.
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: buttonKey,
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      icon: Icon(icon, size: 18, color: color),
      onPressed: onPressed,
    );
  }
}

/// Renders draft [TaskHistoryEntry] rows inside a [Column] (`<= 5` items) or virtualized [ListView.builder] (`> 5` items).
class _TaskEditorHistoryList extends StatelessWidget {
  /// Creates a [_TaskEditorHistoryList].
  const _TaskEditorHistoryList({
    required this.configuration,
    required this.editingIndex,
    required this.entries,
    required this.onEditEntry,
    required this.onRemoveEntry,
  });

  /// Fixed viewport height when virtualizing `> 5` history entries.
  static const double virtualizedViewportHeight = 240;

  /// Active workspace configuration for local wall-clock timestamp formatting.
  final WebDavConfig configuration;

  /// Active zero-based index being edited in place, or `null`.
  final int? editingIndex;

  /// Canonically sorted history entries.
  final List<TaskHistoryEntry> entries;

  /// Callback invoked with the zero-based index to begin editing a row.
  final ValueChanged<int> onEditEntry;

  /// Callback invoked with the zero-based index to delete a row.
  final ValueChanged<int> onRemoveEntry;

  @override
  Widget build(BuildContext context) {
    if (entries.length <= TaskEditorHistorySection.maxInlineColumnRows) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [for (var i = 0; i < entries.length; i++) _buildRow(i)],
      );
    }
    return SizedBox(
      height: virtualizedViewportHeight,
      child: ListView.builder(
        key: const ValueKey('editor_history_list'),
        itemCount: entries.length,
        itemBuilder: (_, index) => _buildRow(index),
      ),
    );
  }

  /// Builds the [_TaskEditorHistoryRow] for zero-based [index].
  Widget _buildRow(int index) {
    final entry = entries[index];
    return _TaskEditorHistoryRow(
      configuration: configuration,
      entry: entry,
      index: index,
      isEditing: editingIndex == index,
      onEdit: () => onEditEntry(index),
      onRemove: () => onRemoveEntry(index),
    );
  }
}

/// Single row displaying a draft [TaskHistoryEntry] with edit and delete actions.
class _TaskEditorHistoryRow extends StatelessWidget {
  /// Creates a [_TaskEditorHistoryRow].
  const _TaskEditorHistoryRow({
    required this.configuration,
    required this.entry,
    required this.index,
    required this.isEditing,
    required this.onEdit,
    required this.onRemove,
  });

  /// Active workspace configuration for local wall-clock formatting.
  final WebDavConfig configuration;

  /// History entry displayed in this row.
  final TaskHistoryEntry entry;

  /// Zero-based index of [entry].
  final int index;

  /// Whether this row is actively being edited in place.
  final bool isEditing;

  /// Callback invoked when the edit button is pressed.
  final VoidCallback onEdit;

  /// Callback invoked when the remove button is pressed.
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final appTheme = AppTheme.of(context);
    final decoration = isEditing
        ? BoxDecoration(
            color: appTheme.primaryAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: appTheme.primaryAccent.withValues(alpha: 0.45),
            ),
          )
        : const BoxDecoration();
    return Container(
      key: ValueKey(
        'editor_history_item_${entry.timestampUtc.millisecondsSinceEpoch}_$index',
      ),
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: EdgeInsets.symmetric(horizontal: isEditing ? 8 : 0, vertical: 2),
      decoration: decoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.history_rounded,
              size: 18,
              color: appTheme.primaryAccent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _TaskEditorHistoryRowTexts(
              configuration: configuration,
              entry: entry,
            ),
          ),
          _TaskEditorHistoryRowActions(
            index: index,
            onEdit: onEdit,
            onRemove: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Trailing edit and delete icon buttons inside [_TaskEditorHistoryRow].
class _TaskEditorHistoryRowActions extends StatelessWidget {
  /// Creates [_TaskEditorHistoryRowActions].
  const _TaskEditorHistoryRowActions({
    required this.index,
    required this.onEdit,
    required this.onRemove,
  });

  /// Zero-based index of the history row.
  final int index;

  /// Callback invoked when the edit button is pressed.
  final VoidCallback onEdit;

  /// Callback invoked when the remove button is pressed.
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TaskEditorHistoryIconButton(
          buttonKey: ValueKey('editor_edit_history_$index'),
          color: appTheme.primaryAccent,
          icon: Icons.edit_outlined,
          onPressed: onEdit,
          tooltip: localizations.tooltipEditHistoryEntry,
        ),
        _TaskEditorHistoryIconButton(
          buttonKey: ValueKey('editor_remove_history_$index'),
          color: appTheme.mutedTextColor,
          icon: Icons.close_rounded,
          onPressed: onRemove,
          tooltip: localizations.tooltipDeleteHistoryEntry,
        ),
      ],
    );
  }
}

/// Local wall-clock timestamp and passive [SelectableText] body inside [_TaskEditorHistoryRow].
class _TaskEditorHistoryRowTexts extends StatelessWidget {
  /// Creates [_TaskEditorHistoryRowTexts].
  const _TaskEditorHistoryRowTexts({
    required this.configuration,
    required this.entry,
  });

  /// Active workspace configuration for local wall-clock formatting.
  final WebDavConfig configuration;

  /// History entry whose local timestamp and passive text are rendered.
  final TaskHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final appTheme = AppTheme.of(context);
    final localTimestamp = TaskItem.formatTdfTimestamp(
      configuration.toLocalWallClock(entry.timestampUtc),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          localTimestamp,
          style: TextStyle(
            color: appTheme.mutedTextColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          entry.text,
          style: TextStyle(color: appTheme.primaryTextColor, fontSize: 14),
        ),
      ],
    );
  }
}

/// Add/update and conditional cancel-edit buttons inside [_TaskEditorHistoryTextActionRow].
class _TaskEditorHistorySubmitButtons extends StatelessWidget {
  /// Creates [_TaskEditorHistorySubmitButtons].
  const _TaskEditorHistorySubmitButtons({
    required this.isEditing,
    required this.onAddOrSaveEntry,
    required this.onCancelEdit,
  });

  /// Whether an existing draft row is actively being edited.
  final bool isEditing;

  /// Callback invoked when the add or update button is pressed.
  final VoidCallback onAddOrSaveEntry;

  /// Callback invoked when the cancel-edit button is pressed.
  final VoidCallback onCancelEdit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          key: const ValueKey('editor_add_history_button'),
          tooltip: isEditing
              ? localizations.tooltipSaveHistoryEntry
              : localizations.tooltipAddHistoryEntry,
          onPressed: onAddOrSaveEntry,
          icon: Icon(
            isEditing ? Icons.check_rounded : Icons.add_rounded,
            size: 20,
          ),
        ),
        if (isEditing) ...[
          const SizedBox(width: 4),
          IconButton(
            key: const ValueKey('editor_cancel_edit_history_button'),
            tooltip: localizations.tooltipCancelEditHistoryEntry,
            onPressed: onCancelEdit,
            icon: Icon(
              Icons.close_rounded,
              size: 20,
              color: appTheme.mutedTextColor,
            ),
          ),
        ],
      ],
    );
  }
}

/// Single-line `<text>` input field paired with add/update and cancel buttons inside [TaskEditorHistorySection].
class _TaskEditorHistoryTextActionRow extends StatelessWidget {
  /// Creates a [_TaskEditorHistoryTextActionRow].
  const _TaskEditorHistoryTextActionRow({
    required this.isEditing,
    required this.onAddOrSaveEntry,
    required this.onCancelEdit,
    required this.textController,
  });

  /// Whether an existing draft row is actively being edited.
  final bool isEditing;

  /// Callback invoked when the add/update button or `Enter` key is triggered.
  final VoidCallback onAddOrSaveEntry;

  /// Callback invoked when the cancel-edit button is pressed.
  final VoidCallback onCancelEdit;

  /// Controller bound to the single-line history `<text>` input field.
  final TextEditingController textController;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TaskEditorHistoryTextField(
            controller: textController,
            onSubmitted: onAddOrSaveEntry,
          ),
        ),
        const SizedBox(width: 8),
        _TaskEditorHistorySubmitButtons(
          isEditing: isEditing,
          onAddOrSaveEntry: onAddOrSaveEntry,
          onCancelEdit: onCancelEdit,
        ),
      ],
    );
  }
}

/// Styled [ClearableTextField] for the single-line history `<text>` input.
class _TaskEditorHistoryTextField extends StatelessWidget {
  /// Creates a [_TaskEditorHistoryTextField].
  const _TaskEditorHistoryTextField({
    required this.controller,
    required this.onSubmitted,
  });

  /// Controller bound to the input field.
  final TextEditingController controller;

  /// Callback invoked when the `Done` / `Enter` keyboard action triggers.
  final VoidCallback onSubmitted;

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
    return ClearableTextField(
      fieldKey: const ValueKey('editor_history_text_input'),
      clearButtonKey: const ValueKey('editor_history_text_clear_button'),
      showClearWhenUnfocused: true,
      controller: controller,
      cursorColor: appTheme.primaryAccent,
      clearIconColor: appTheme.mutedTextColor,
      style: TextStyle(color: appTheme.primaryTextColor, fontSize: 14),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmitted(),
      decoration: InputDecoration(
        labelText: localizations.historyEntryTextLabel,
        labelStyle: TextStyle(color: appTheme.mutedTextColor),
        hintText: localizations.historyEntryTextHint,
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
          borderSide: BorderSide(color: appTheme.primaryAccent, width: 1.6),
        ),
      ),
    );
  }
}

/// Optional local wall-clock `<timestamp>` field with clear, date picker, and 24-hour time picker controls.
class _TaskEditorHistoryTimestampField extends StatelessWidget {
  /// Creates a [_TaskEditorHistoryTimestampField].
  const _TaskEditorHistoryTimestampField({
    required this.controller,
    required this.onClearTimestamp,
    required this.onPickDate,
    required this.onPickTime,
  });

  /// Controller bound to the optional timestamp text field.
  final TextEditingController controller;

  /// Callback invoked when the timestamp clear button is pressed.
  final VoidCallback onClearTimestamp;

  /// Callback invoked when the date picker button is pressed.
  final VoidCallback onPickDate;

  /// Callback invoked when the time picker button is pressed.
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
    return ClearableTextField(
      fieldKey: const ValueKey('editor_history_timestamp_input'),
      clearButtonKey: const ValueKey('editor_history_timestamp_clear_button'),
      clearTooltip: localizations.tooltipClearDate,
      clearIconColor: appTheme.mutedTextColor,
      showClearWhenUnfocused: true,
      onCleared: onClearTimestamp,
      controller: controller,
      cursorColor: appTheme.primaryAccent,
      style: TextStyle(color: appTheme.primaryTextColor, fontSize: 14),
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: localizations.historyTimestampLabel,
        labelStyle: TextStyle(color: appTheme.mutedTextColor),
        hintText: localizations.historyTimestampHint,
        hintStyle: TextStyle(color: appTheme.mutedTextColor),
        isDense: true,
        filled: true,
        fillColor: appTheme.canvasColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        suffixIcon: _TaskEditorHistoryTimestampSuffix(
          onPickDate: onPickDate,
          onPickTime: onPickTime,
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

/// Trailing date and 24-hour time picker icon buttons inside [_TaskEditorHistoryTimestampField].
class _TaskEditorHistoryTimestampSuffix extends StatelessWidget {
  /// Creates a [_TaskEditorHistoryTimestampSuffix].
  const _TaskEditorHistoryTimestampSuffix({
    required this.onPickDate,
    required this.onPickTime,
  });

  /// Callback invoked when the date picker button is pressed.
  final VoidCallback onPickDate;

  /// Callback invoked when the time picker button is pressed.
  final VoidCallback onPickTime;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final appTheme = AppTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TaskEditorHistoryIconButton(
          buttonKey: const ValueKey('editor_history_date_picker_button'),
          color: appTheme.primaryAccent,
          icon: Icons.calendar_month_rounded,
          onPressed: onPickDate,
          tooltip: localizations.tooltipPickDate,
        ),
        _TaskEditorHistoryIconButton(
          buttonKey: const ValueKey('editor_history_time_picker_button'),
          color: appTheme.primaryAccent,
          icon: Icons.access_time_rounded,
          onPressed: onPickTime,
          tooltip: localizations.tooltipPickTime,
        ),
      ],
    );
  }
}
