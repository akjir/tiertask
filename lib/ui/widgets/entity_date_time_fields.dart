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

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import '../../l10n/app_localizations.dart';

final DateTime _firstPickerDate = DateTime(2000);

/// Upper date bound accepted by Material date pickers.
final DateTime _lastPickerDate = DateTime(2100, 12, 31);

/// Editable monospace `YYYY-MM-DD HH:MM` input paired with Material date and 24-hour time pickers.
class EntityHybridDateTimeField extends StatelessWidget {
  /// Creates an [EntityHybridDateTimeField].
  const EntityHybridDateTimeField({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.fallbackLocalDateTime,
    this.onChanged,
    this.onSubmitted,
  });

  /// Whether the text field requests focus automatically on mount.
  final bool autofocus;

  /// Caller-owned text controller holding the local timestamp string.
  final TextEditingController controller;

  /// Whether manual editing and picker triggers are enabled.
  final bool enabled;

  /// Optional inline validation error text.
  final String? errorText;

  /// Optional parseable `YYYY-MM-DD HH:MM` fallback seeding date and time pickers.
  final String? fallbackLocalDateTime;

  /// Optional caller-owned focus node.
  final FocusNode? focusNode;

  /// Optional helper text below the input.
  final String? helperText;

  /// Optional placeholder hint text (defaults to `YYYY-MM-DD HH:MM`).
  final String? hintText;

  /// Optional field label above the input.
  final String? label;

  /// Optional callback invoked when the timestamp text changes via typing or pickers.
  final ValueChanged<String>? onChanged;

  /// Optional callback invoked when the user submits the field.
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiField(
      kind: UiFieldKind.text,
      controller: controller,
      focusNode: focusNode,
      label: label,
      hintText: hintText ?? localizations.historyTimestampHint,
      helperText: helperText,
      errorText: errorText,
      enabled: enabled,
      autofocus: autofocus,
      isMonospace: true,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      trailingAction: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          UiButton(
            leadingIcon: Icons.calendar_today_outlined,
            variant: UiButtonVariant.icon,
            density: UiButtonDensity.sidebarDesktop,
            tooltip: localizations.tooltipPickDate,
            onPressed: enabled ? () => _pickDate(context) : null,
          ),
          UiButton(
            leadingIcon: Icons.schedule_rounded,
            variant: UiButtonVariant.icon,
            density: UiButtonDensity.sidebarDesktop,
            tooltip: localizations.tooltipPickTime,
            onPressed: enabled ? () => _pickTime(context) : null,
          ),
        ],
      ),
    );
  }

  /// Opens a Material date picker and merges the picked date into `YYYY-MM-DD HH:MM`.
  Future<void> _pickDate(BuildContext context) async {
    final fallback = _parseFallbackDateTime(fallbackLocalDateTime);
    final initialDate = _clampPickerDate(
      _parseLocalDate(controller.text) ?? fallback,
    );
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: _firstPickerDate,
      lastDate: _lastPickerDate,
    );
    if (!context.mounted || pickedDate == null) {
      return;
    }
    final datePart = _formatIsoDate(pickedDate);
    final timePart =
        _extractTimePart(controller.text) ??
        _extractTimePart(fallbackLocalDateTime ?? '') ??
        _formatTimeOfDay(
          TimeOfDay(hour: fallback.hour, minute: fallback.minute),
        );
    final formatted = '$datePart $timePart';
    controller.text = formatted;
    controller.selection = TextSelection.collapsed(offset: formatted.length);
    onChanged?.call(formatted);
  }

  /// Opens a 24-hour Material time picker and merges the picked time into `YYYY-MM-DD HH:MM`.
  Future<void> _pickTime(BuildContext context) async {
    final fallback = _parseFallbackDateTime(fallbackLocalDateTime);
    final initialTime =
        _parseTimeOfDay(controller.text) ??
        TimeOfDay(hour: fallback.hour, minute: fallback.minute);
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: _build24HourTimePicker,
    );
    if (!context.mounted || pickedTime == null) {
      return;
    }
    final datePart =
        _extractDatePart(controller.text) ?? _formatIsoDate(fallback);
    final formatted = '$datePart ${_formatTimeOfDay(pickedTime)}';
    controller.text = formatted;
    controller.selection = TextSelection.collapsed(offset: formatted.length);
    onChanged?.call(formatted);
  }
}

/// Editable monospace `HH:MM` input paired with a 24-hour Material clock picker.
class EntityHybridTimeField extends StatelessWidget {
  /// Creates an [EntityHybridTimeField].
  const EntityHybridTimeField({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.enabled = true,
    this.onSubmitted,
  });

  /// Caller-owned text controller holding the `HH:MM` value.
  final TextEditingController controller;

  /// Whether manual editing and the clock picker button are enabled.
  final bool enabled;

  /// Optional placeholder hint text (defaults to `HH:MM`).
  final String? hintText;

  /// Optional field label above the input.
  final String? label;

  /// Optional callback invoked when the user submits the field.
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiField(
      kind: UiFieldKind.text,
      controller: controller,
      label: label,
      hintText: hintText ?? 'HH:MM',
      enabled: enabled,
      isMonospace: true,
      onSubmitted: onSubmitted,
      trailingAction: UiButton(
        leadingIcon: Icons.schedule_rounded,
        variant: UiButtonVariant.icon,
        density: UiButtonDensity.sidebarDesktop,
        tooltip: localizations.tooltipPickTime,
        onPressed: enabled ? () => _pickTime(context) : null,
      ),
    );
  }

  /// Opens a 24-hour Material time picker and writes canonical `HH:MM` into [controller].
  Future<void> _pickTime(BuildContext context) async {
    final initialTime =
        _parseTimeOfDay(controller.text) ?? const TimeOfDay(hour: 9, minute: 0);
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: _build24HourTimePicker,
    );
    if (!context.mounted || pickedTime == null) {
      return;
    }
    final formatted = _formatTimeOfDay(pickedTime);
    controller.text = formatted;
    controller.selection = TextSelection.collapsed(offset: formatted.length);
  }
}

/// Parses an exact 24-hour `HH:MM` token into minutes since midnight (`0..1439`), or `null` if invalid.
int? parseEntityTimeMinutes(String rawToken) {
  if (rawToken.length != 5 || rawToken.codeUnitAt(2) != 0x3A) {
    return null;
  }
  final hour = _parseAsciiDigits(rawToken, 0, 2);
  final minute = _parseAsciiDigits(rawToken, 3, 2);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

/// Wraps [showTimePicker] in a 24-hour [MediaQuery] configuration.
Widget _build24HourTimePicker(BuildContext context, Widget? child) {
  return MediaQuery(
    data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
    child: child ?? const SizedBox.shrink(),
  );
}

/// Clamps [date] into the inclusive `2000-01-01..2100-12-31` Material date picker bounds.
DateTime _clampPickerDate(DateTime date) {
  final normalized = DateTime(date.year, date.month, date.day);
  if (normalized.isBefore(_firstPickerDate)) {
    return _firstPickerDate;
  }
  if (normalized.isAfter(_lastPickerDate)) {
    return _lastPickerDate;
  }
  return normalized;
}

/// Extracts a validated `YYYY-MM-DD` date prefix from [rawInput], or `null` if invalid.
String? _extractDatePart(String rawInput) {
  final parsed = _parseLocalDate(rawInput);
  if (parsed == null) {
    return null;
  }
  return _formatIsoDate(parsed);
}

/// Extracts a validated `HH:MM` time suffix from [rawInput], or `null` if absent or invalid.
String? _extractTimePart(String rawInput) {
  final trimmed = rawInput.trim();
  if (trimmed.length == 5) {
    return parseEntityTimeMinutes(trimmed) != null ? trimmed : null;
  }
  if (trimmed.length < 16) {
    return null;
  }
  final separator = trimmed.codeUnitAt(10);
  if (separator != 0x20 && separator != 0x54) {
    return null;
  }
  final candidate = trimmed.substring(11, 16);
  if (trimmed.length > 16 && trimmed.substring(16).trim().isNotEmpty) {
    return null;
  }
  return parseEntityTimeMinutes(candidate) != null ? candidate : null;
}

/// Formats [date] into canonical `YYYY-MM-DD`.
String _formatIsoDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// Formats [time] into zero-padded 24-hour `HH:MM`.
String _formatTimeOfDay(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// Parses [length] ASCII digits starting at [start] in [text], or `null` on non-digit input.
int? _parseAsciiDigits(String text, int start, int length) {
  if (start < 0 || start + length > text.length) {
    return null;
  }
  var value = 0;
  for (var offset = 0; offset < length; offset++) {
    final digit = text.codeUnitAt(start + offset) - 0x30;
    if (digit < 0 || digit > 9) {
      return null;
    }
    value = value * 10 + digit;
  }
  return value;
}

/// Parses an optional `YYYY-MM-DD [HH:MM]` fallback timestamp into a local [DateTime], falling back to `DateTime.now()`.
DateTime _parseFallbackDateTime(String? rawFallback) {
  if (rawFallback == null) {
    return DateTime.now();
  }
  final date = _parseLocalDate(rawFallback);
  if (date == null) {
    return DateTime.now();
  }
  final time = _parseTimeOfDay(rawFallback);
  if (time == null) {
    return DateTime(date.year, date.month, date.day);
  }
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// Parses a `YYYY-MM-DD` date prefix from [rawInput], verifying real calendar dates.
DateTime? _parseLocalDate(String rawInput) {
  final trimmed = rawInput.trim();
  if (trimmed.length < 10) {
    return null;
  }
  if (trimmed.codeUnitAt(4) != 0x2D || trimmed.codeUnitAt(7) != 0x2D) {
    return null;
  }
  if (trimmed.length > 10) {
    final separator = trimmed.codeUnitAt(10);
    if (separator != 0x20 && separator != 0x54) {
      return null;
    }
  }
  final year = _parseAsciiDigits(trimmed, 0, 4);
  final month = _parseAsciiDigits(trimmed, 5, 2);
  final day = _parseAsciiDigits(trimmed, 8, 2);
  if (year == null ||
      month == null ||
      day == null ||
      year < 1 ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31) {
    return null;
  }
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

/// Parses a `HH:MM` token or timestamp time suffix into a [TimeOfDay], or `null` if invalid.
TimeOfDay? _parseTimeOfDay(String rawInput) {
  final timeToken = _extractTimePart(rawInput);
  if (timeToken == null) {
    return null;
  }
  final minutes = parseEntityTimeMinutes(timeToken);
  if (minutes == null) {
    return null;
  }
  return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
}
