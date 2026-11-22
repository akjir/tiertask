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

import 'package:flutter/foundation.dart';

import '../l10n/app_localizations.dart';
import '../l10n/storage_file_read_localization_extension.dart';
import '../models/location_state.dart';
import '../models/storage_file_read_status.dart';
import '../models/task_board.dart';
import '../models/task_item.dart';
import '../models/task_tier.dart';
import '../models/tdf_error.dart';
import '../models/tdf_location.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_sync_metadata.dart';
import '../models/tdf_timezone.dart';
import '../models/webdav_config.dart';
import 'sync_error_formatter.dart';
import 'task_condition_draft_helper.dart';

/// Canonical `#RRGGBB` preset color swatches offered in label color pickers.
const List<String> canonicalLabelPresetHexColors = <String>[
  '#2196F3',
  '#4CAF50',
  '#FF9100',
  '#E91E63',
  '#9C27B0',
  '#00BCD4',
  '#EB06FF',
  '#00E5FF',
];

/// Minimum accepted geofence radius in meters (`0.01m`).
const double _minLocationRadiusMeters = 0.01;

/// Per-dimension override mode for task activation conditions.
enum ConditionDimensionMode {
  /// Inherit condition rules from assigned labels.
  inherit,

  /// Explicitly override label rules so this dimension always matches.
  any,

  /// Specify explicit custom rules on the task.
  custom,
}

/// Immutable representation of activation condition editor state for a task or label.
@immutable
class ConditionDraft {
  /// Creates a [ConditionDraft].
  ConditionDraft({
    this.ignoreAllLabelConditions = false,
    this.daysMode = ConditionDimensionMode.inherit,
    Iterable<int> weekdays = const <int>[],
    this.timeMode = ConditionDimensionMode.inherit,
    Iterable<TimeWindowDraft> timeWindows = const <TimeWindowDraft>[],
    this.locationMode = ConditionDimensionMode.inherit,
    Iterable<String> locationIds = const <String>[],
  }) : weekdays = List<int>.unmodifiable(weekdays),
       timeWindows = List<TimeWindowDraft>.unmodifiable(timeWindows),
       locationIds = List<String>.unmodifiable(locationIds);

  /// Day dimension mode (`inherit`, `any`, or `custom`).
  final ConditionDimensionMode daysMode;

  /// Whether `condition any` ignores all inherited label conditions.
  final bool ignoreAllLabelConditions;

  /// Selected referenced location identifiers.
  final List<String> locationIds;

  /// Location dimension mode (`inherit`, `any`, or `custom`).
  final ConditionDimensionMode locationMode;

  /// Time dimension mode (`inherit`, `any`, or `custom`).
  final ConditionDimensionMode timeMode;

  /// Configured `HH:MM`..`HH:MM` daily time windows.
  final List<TimeWindowDraft> timeWindows;

  /// Selected ISO weekdays (`1..7`, Monday to Sunday).
  final List<int> weekdays;

  /// Returns a copy of this [ConditionDraft] with updated fields.
  ConditionDraft copyWith({
    bool? ignoreAllLabelConditions,
    ConditionDimensionMode? daysMode,
    Iterable<int>? weekdays,
    ConditionDimensionMode? timeMode,
    Iterable<TimeWindowDraft>? timeWindows,
    ConditionDimensionMode? locationMode,
    Iterable<String>? locationIds,
  }) {
    return ConditionDraft(
      ignoreAllLabelConditions:
          ignoreAllLabelConditions ?? this.ignoreAllLabelConditions,
      daysMode: daysMode ?? this.daysMode,
      weekdays: weekdays ?? this.weekdays,
      timeMode: timeMode ?? this.timeMode,
      timeWindows: timeWindows ?? this.timeWindows,
      locationMode: locationMode ?? this.locationMode,
      locationIds: locationIds ?? this.locationIds,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConditionDraft &&
        other.ignoreAllLabelConditions == ignoreAllLabelConditions &&
        other.daysMode == daysMode &&
        listEquals(other.weekdays, weekdays) &&
        other.timeMode == timeMode &&
        listEquals(other.timeWindows, timeWindows) &&
        other.locationMode == locationMode &&
        listEquals(other.locationIds, locationIds);
  }

  @override
  int get hashCode => Object.hash(
    ignoreAllLabelConditions,
    daysMode,
    Object.hashAll(weekdays),
    timeMode,
    Object.hashAll(timeWindows),
    locationMode,
    Object.hashAll(locationIds),
  );
}

/// Immutable read-only condition summary chip with optional clickable location navigation target.
@immutable
class ConditionSummaryChip {
  /// Creates a [ConditionSummaryChip].
  const ConditionSummaryChip({
    required this.label,
    this.locationId,
    this.isInherited = false,
  });

  /// Whether this rule is inherited from an assigned label.
  final bool isInherited;

  /// Localized human-readable condition summary.
  final String label;

  /// Optional location identifier when tapping navigates to the Locations manager.
  final String? locationId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConditionSummaryChip &&
        other.label == label &&
        other.locationId == locationId &&
        other.isInherited == isInherited;
  }

  @override
  int get hashCode => Object.hash(label, locationId, isInherited);
}

/// Immutable per-target file readability diagnostic line.
@immutable
class FileReadDiagnosticLine {
  /// Creates a [FileReadDiagnosticLine].
  const FileReadDiagnosticLine({
    required this.targetLabel,
    required this.statusText,
    required this.isReadable,
  });

  /// Whether this target was read cleanly.
  final bool isReadable;

  /// Localized readability status or detailed format error text.
  final String statusText;

  /// Localized target label (`Local file` or `Remote file`).
  final String targetLabel;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileReadDiagnosticLine &&
        other.targetLabel == targetLabel &&
        other.statusText == statusText &&
        other.isReadable == isReadable;
  }

  @override
  int get hashCode => Object.hash(targetLabel, statusText, isReadable);
}

/// Immutable resolution state for a task `due` timestamp input.
@immutable
class ResolvedDueDraft {
  /// Creates a [ResolvedDueDraft].
  const ResolvedDueDraft({
    required this.dueAt,
    required this.dueLocalInput,
    required this.dueAnchor,
    required this.isUnchanged,
    required this.isValid,
  });

  /// Preserved or newly derived local wall-clock anchor (`due.anchor`).
  final TdfLocalDateTime? dueAnchor;

  /// Resolved UTC due instant, or `null` when disabled or invalid.
  final DateTime? dueAt;

  /// Newly parsed local wall-clock input when edited, or `null` when unchanged or disabled.
  final TdfLocalDateTime? dueLocalInput;

  /// Whether the edited text exactly matched the initial formatted baseline.
  final bool isUnchanged;

  /// Whether the draft is valid (including when `hasDue` is `false`).
  final bool isValid;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ResolvedDueDraft &&
        other.dueAt == dueAt &&
        other.dueLocalInput == dueLocalInput &&
        other.dueAnchor == dueAnchor &&
        other.isUnchanged == isUnchanged &&
        other.isValid == isValid;
  }

  @override
  int get hashCode =>
      Object.hash(dueAt, dueLocalInput, dueAnchor, isUnchanged, isValid);
}

/// Immutable resolution state for a task `suspended` timestamp input.
@immutable
class ResolvedSuspendedDraft {
  /// Creates a [ResolvedSuspendedDraft].
  const ResolvedSuspendedDraft({
    required this.suspendedAt,
    required this.suspendedLocalInput,
    required this.isForever,
    required this.isValid,
  });

  /// Whether the task is suspended indefinitely (`suspended forever`).
  final bool isForever;

  /// Whether the draft is valid (including when `isSuspended` is `false`).
  final bool isValid;

  /// Preserved UTC instant when unchanged, or `null` when edited, forever, or disabled.
  final DateTime? suspendedAt;

  /// Newly parsed local wall-clock input when edited, or `null` when unchanged, forever, or disabled.
  final TdfLocalDateTime? suspendedLocalInput;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ResolvedSuspendedDraft &&
        other.suspendedAt == suspendedAt &&
        other.suspendedLocalInput == suspendedLocalInput &&
        other.isForever == isForever &&
        other.isValid == isValid;
  }

  @override
  int get hashCode =>
      Object.hash(suspendedAt, suspendedLocalInput, isForever, isValid);
}

/// Stateless helper owning scheduling draft resolution, formatting, condition compilation, and shared TDF validation.
class TaskScheduleHelper {
  /// Prevents instantiation of [TaskScheduleHelper].
  const TaskScheduleHelper._();

  /// Builds the [ConditionDraft] representing [rules] on a task or label.
  static ConditionDraft buildConditionDraft(
    List<TaskCondition> rules, {
    required bool isTask,
  }) {
    final extracted = TaskConditionDraftHelper.extractDraftFields(
      rules,
      isTask: isTask,
    );
    return ConditionDraft(
      ignoreAllLabelConditions: extracted.ignoreAllLabelConditions,
      daysMode: _fromCompileMode(
        TaskConditionDraftHelper.resolveDimensionMode(
          isTask: isTask,
          hasRules: extracted.weekdays.isNotEmpty,
          hasAny: extracted.dayAny,
        ),
      ),
      weekdays: extracted.weekdays,
      timeMode: _fromCompileMode(
        TaskConditionDraftHelper.resolveDimensionMode(
          isTask: isTask,
          hasRules: extracted.timeWindows.isNotEmpty,
          hasAny: extracted.timeAny,
        ),
      ),
      timeWindows: <TimeWindowDraft>[
        for (final window in extracted.timeWindows)
          TimeWindowDraft(start: window.start, end: window.end),
      ],
      locationMode: _fromCompileMode(
        TaskConditionDraftHelper.resolveDimensionMode(
          isTask: isTask,
          hasRules: extracted.locationIds.isNotEmpty,
          hasAny: extracted.locationAny,
        ),
      ),
      locationIds: extracted.locationIds,
    );
  }

  /// Builds read-only condition summary chips for [ownRules] plus optional [inheritedRules].
  static List<ConditionSummaryChip> buildConditionSummaryChips({
    required List<TaskCondition> ownRules,
    required Iterable<TaskCondition> inheritedRules,
    required Map<String, TdfLocation> locationsById,
    required AppLocalizations localizations,
  }) => <ConditionSummaryChip>[
    for (final chip in TaskConditionDraftHelper.buildSummaryChips(
      ownRules: ownRules,
      inheritedRules: inheritedRules,
      locationsById: locationsById,
      localizations: localizations,
    ))
      ConditionSummaryChip(
        label: chip.label,
        locationId: chip.locationId,
        isInherited: chip.isInherited,
      ),
  ];

  /// Collects all live and tombstoned entity identifiers currently referenced on [board].
  static Set<String> collectAllUsedEntityIds(TaskBoard board) => <String>{
    for (final task in board.allTasks) task.id,
    for (final task in board.allTasks) ...task.blockedByTaskIds,
    for (final task in board.allTasks) ...task.labelIds,
    for (final label in board.labels) label.id,
    for (final location in board.locations) location.id,
    for (final record in board.deletedBlock.tasks) record.taskId,
    for (final record in board.deletedBlock.labels) record.labelId,
    for (final record in board.deletedBlock.locations) record.locationId,
  };

  /// Collects selected prerequisite task IDs in canonical board declaration order.
  static List<String> collectOrderedBlockedByIds(
    TaskBoard board,
    Set<String> selectedBlockedByIds,
  ) {
    return <String>[
      for (final task in board.allTasks)
        if (selectedBlockedByIds.contains(task.id)) task.id,
    ];
  }

  /// Collects selected label IDs in canonical board declaration order.
  static List<String> collectOrderedLabelIds(
    TaskBoard board,
    Set<String> selectedLabelIds,
  ) {
    return <String>[
      for (final label in board.labels)
        if (selectedLabelIds.contains(label.id)) label.id,
    ];
  }

  /// Compiles and validates a [ConditionDraft] into canonical [TaskCondition] rules for a task or label.
  static ({List<TaskCondition> conditions, String? error})
  compileConditionDraft({
    required ConditionDraft draft,
    required TaskBoard board,
    required bool isTask,
    required AppLocalizations localizations,
  }) => TaskConditionDraftHelper.compileConditions(
    ignoreAllLabelConditions: draft.ignoreAllLabelConditions,
    daysMode: _toCompileMode(draft.daysMode),
    weekdays: draft.weekdays,
    timeMode: _toCompileMode(draft.timeMode),
    timeWindows: <TimeWindowTokenPair>[
      for (final window in draft.timeWindows)
        (start: window.start, end: window.end),
    ],
    locationMode: _toCompileMode(draft.locationMode),
    locationIds: draft.locationIds,
    board: board,
    isTask: isTask,
    localizations: localizations,
  );

  /// Returns `true` when [anchor] differs in any `(year, month, day, hour, minute, second)` component from [localWallClock].
  static bool differsFromWallClock(
    TdfLocalDateTime anchor,
    DateTime localWallClock,
  ) =>
      anchor.year != localWallClock.year ||
      anchor.month != localWallClock.month ||
      anchor.day != localWallClock.day ||
      anchor.hour != localWallClock.hour ||
      anchor.minute != localWallClock.minute ||
      anchor.second != localWallClock.second;

  /// Formats 4-decimal coordinate and radius summary (`47.1204, 8.5173 · 250m`).
  static String formatCoordinatesSummary(TdfLocation location) {
    final latitude = location.latitude.toStringAsFixed(4);
    final longitude = location.longitude.toStringAsFixed(4);
    return '$latitude, $longitude · ${formatRadiusMeters(location.radius)}';
  }

  /// Formats optional schedule anchor display text when `dueAnchor` differs from wall-clock `dueAt`.
  static String? formatDueAnchor({
    required TaskItem task,
    required WebDavConfig config,
    required AppLocalizations localizations,
  }) {
    final anchor = task.dueAnchor;
    final dueAt = task.dueAt;
    if (anchor == null || dueAt == null) {
      return null;
    }
    final localDue = config.toLocalWallClock(dueAt);
    if (!differsFromWallClock(anchor, localDue)) {
      return null;
    }
    return localizations.taskInfoDueAnchorDetail(anchor.formatCompact());
  }

  /// Formats the auto-priority detail hint inside the expanded Due section.
  static String formatDueAutoPriorityLabel({
    required TaskItem task,
    required bool isAutoPrioritized,
    required DueLeadWindow dueLeadWindow,
    required AppLocalizations localizations,
  }) {
    if (task.isDuePassive) {
      return localizations.taskInfoDuePassiveHint;
    }
    if (dueLeadWindow == DueLeadWindow.off) {
      return localizations.taskInfoDueLeadWindowOffHint;
    }
    if (isAutoPrioritized) {
      return localizations.taskInfoDueAutoPromotedActive;
    }
    if (dueLeadWindow == DueLeadWindow.atDue) {
      return localizations.taskInfoDueAutoPromoteAtDue;
    }
    final shortLabel = switch (dueLeadWindow) {
      DueLeadWindow.off || DueLeadWindow.atDue => '',
      DueLeadWindow.hours12 => localizations.dueLeadWindowShort12Hours,
      DueLeadWindow.hours24 => localizations.dueLeadWindowShort24Hours,
      DueLeadWindow.hours48 => localizations.dueLeadWindowShort48Hours,
      DueLeadWindow.days7 => localizations.dueLeadWindowShort7Days,
    };
    return localizations.taskInfoDueAutoPromoteScheduled(shortLabel);
  }

  /// Formats the Due section primary readout (`timestamp (remaining)` or `Overdue (timestamp)`).
  static String formatDueDetail({
    required DateTime dueAtUtc,
    required DateTime nowUtc,
    required bool isOverdue,
    required WebDavConfig config,
    required AppLocalizations localizations,
  }) {
    final formatted = formatLocalTimestamp(dueAtUtc, config);
    if (isOverdue) {
      return localizations.taskInfoDueOverdue(formatted);
    }
    final duration = formatRemainingDuration(
      dueAtUtc.difference(nowUtc),
      localizations,
    );
    return localizations.taskInfoDueAt(formatted, duration);
  }

  /// Formats per-target diagnostic lines from a [StorageFileReadReport].
  static List<FileReadDiagnosticLine> formatFileReadDiagnosticLines(
    StorageFileReadReport report,
    AppLocalizations localizations,
  ) {
    return <FileReadDiagnosticLine>[
      for (final entry in report.activeEntries)
        FileReadDiagnosticLine(
          targetLabel: localizations.storageFileTargetLabel(entry.target),
          statusText: localizations.storageFileReadEntryText(entry),
          isReadable: entry.isReadable,
        ),
    ];
  }

  /// Formats an initial `suspended` UTC timestamp in [configuration]'s local wall-clock time, returning `''` when `null`.
  static String formatInitialSuspendedText(
    DateTime? suspendedAtUtc, [
    WebDavConfig configuration = const WebDavConfig(),
  ]) {
    if (suspendedAtUtc == null) {
      return '';
    }
    return formatLocalTimestamp(suspendedAtUtc, configuration);
  }

  /// Formats an optional UTC [instantUtc] in [configuration]'s local wall-clock time, or `''` when `null`.
  static String formatLocalTimestamp(
    DateTime? instantUtc,
    WebDavConfig configuration,
  ) {
    if (instantUtc == null) {
      return '';
    }
    return TaskItem.formatTdfTimestamp(
      configuration.toLocalWallClock(instantUtc),
    );
  }

  /// Formats [radiusMeters] compactly as meters or kilometers.
  static String formatRadiusMeters(double radiusMeters) {
    if (radiusMeters >= 1000.0 && radiusMeters % 1000.0 == 0.0) {
      return '${(radiusMeters / 1000.0).toInt()}km';
    }
    if (radiusMeters >= 1000.0) {
      return '${TdfLocation.formatRoundedDouble(radiusMeters / 1000.0, 2)}km';
    }
    return '${TdfLocation.formatRoundedDouble(radiusMeters, 2)}m';
  }

  /// Formats a positive [difference] into days/hours, hours/minutes, or minutes remaining.
  static String formatRemainingDuration(
    Duration difference,
    AppLocalizations localizations,
  ) {
    if (difference.inDays >= 1) {
      final remainingHours = difference.inHours % 24;
      return localizations.taskInfoDurationDaysHours(
        difference.inDays.toString(),
        remainingHours.toString(),
      );
    }
    if (difference.inHours >= 1) {
      final remainingMinutes = difference.inMinutes % 60;
      return localizations.taskInfoDurationHoursMinutes(
        difference.inHours.toString(),
        remainingMinutes.toString(),
      );
    }
    final minutes = difference.inMinutes < 1 ? 1 : difference.inMinutes;
    return localizations.taskInfoDurationMinutes(minutes.toString());
  }

  /// Formats a [TaskRepeatRule] into a localized human-readable interval phrase.
  static String formatRepeatPhrase(
    TaskRepeatRule rule,
    AppLocalizations localizations,
  ) {
    if (rule.count == 1) {
      return switch (rule.unit) {
        RepeatUnit.days => localizations.repeatEveryDay,
        RepeatUnit.weeks => localizations.repeatEveryWeek,
        RepeatUnit.months => localizations.repeatEveryMonth,
      };
    }
    final unitLabel = switch (rule.unit) {
      RepeatUnit.days => localizations.repeatUnitDays,
      RepeatUnit.weeks => localizations.repeatUnitWeeks,
      RepeatUnit.months => localizations.repeatUnitMonths,
    };
    return localizations.taskInfoRepeatEvery('${rule.count}', unitLabel);
  }

  /// Formats the Suspended section primary readout.
  static String formatSuspendedDetail({
    required TaskItem task,
    required DateTime nowUtc,
    required WebDavConfig config,
    required AppLocalizations localizations,
  }) {
    final target = task.suspendedAt;
    if (task.isSuspendedForever || target == null) {
      return localizations.taskInfoSuspendedForever;
    }
    final formatted = formatLocalTimestamp(target, config);
    final duration = formatRemainingDuration(
      target.difference(nowUtc),
      localizations,
    );
    return localizations.taskInfoSuspendedUntil(formatted, duration);
  }

  /// Formats a sanitized localized message for synchronization or resolution [error].
  static String formatSyncError(
    Object error,
    AppLocalizations localizations, {
    bool isSave = false,
  }) =>
      SyncErrorFormatter.formatSyncError(error, localizations, isSave: isSave);

  /// Maps a [TdfSyncOutcomeException] exhaustively to its localized banner message.
  static String formatSyncOutcomeMessage(
    TdfSyncOutcomeException outcome,
    AppLocalizations localizations,
  ) => SyncErrorFormatter.formatSyncOutcomeMessage(outcome, localizations);

  /// Returns `true` when [latitude] and [longitude] are finite WGS-84 coordinates.
  static bool isValidCoordinates(double latitude, double longitude) =>
      latitude.isFinite &&
      latitude >= -90.0 &&
      latitude <= 90.0 &&
      longitude.isFinite &&
      longitude >= -180.0 &&
      longitude <= 180.0;

  /// Maps a domain [TdfErrorKind] exhaustively into a sanitized localized persistence failure message.
  static String mapTdfExceptionMessage(
    TdfErrorKind kind,
    AppLocalizations localizations,
  ) => SyncErrorFormatter.mapTdfExceptionMessage(kind, localizations);

  /// Normalizes user-edited [rawText], collapsing ASCII-whitespace-only strings to `null` and CR/CRLF breaks to `\n`.
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

  /// Parses and validates WGS-84 [rawLatitude] and [rawLongitude] rounded to 6 decimal places.
  static ({double? latitude, double? longitude, String? error})
  parseCoordinates({
    required String rawLatitude,
    required String rawLongitude,
    required AppLocalizations localizations,
  }) {
    final parsedLatitude = _tryParseDecimalString(
      rawLatitude,
      allowNegative: true,
    );
    final parsedLongitude = _tryParseDecimalString(
      rawLongitude,
      allowNegative: true,
    );
    if (parsedLatitude == null ||
        parsedLongitude == null ||
        !isValidCoordinates(parsedLatitude, parsedLongitude)) {
      return (
        latitude: null,
        longitude: null,
        error: localizations.locationCoordinatesErrorInvalid,
      );
    }
    final roundedLatitude = double.tryParse(
      TdfLocation.formatRoundedDouble(parsedLatitude, 6),
    );
    final roundedLongitude = double.tryParse(
      TdfLocation.formatRoundedDouble(parsedLongitude, 6),
    );
    if (roundedLatitude == null ||
        roundedLongitude == null ||
        !isValidCoordinates(roundedLatitude, roundedLongitude)) {
      return (
        latitude: null,
        longitude: null,
        error: localizations.locationCoordinatesErrorInvalid,
      );
    }
    return (
      latitude: roundedLatitude,
      longitude: roundedLongitude,
      error: null,
    );
  }

  /// Parses an optional `#RRGGBB` string into a 32-bit ARGB integer.
  static int? parseLabelColorValue(String? hex) => TdfColor.tryParseArgb(hex);

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

  /// Parses a geofence radius string (`0.01m..100km`, supporting `m`/`km` and `.`/`,`) into meters rounded to 2 decimals.
  static double? parseRadiusMeters(String rawRadius) {
    if (TdfMetadata.containsAsciiControlChar(rawRadius)) {
      return null;
    }
    final trimmed = rawRadius.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final lower = trimmed.toLowerCase();
    var numericPart = trimmed;
    var multiplier = 1.0;
    if (lower.endsWith('km')) {
      numericPart = trimmed.substring(0, trimmed.length - 2).trim();
      multiplier = 1000.0;
    } else if (lower.endsWith('m')) {
      numericPart = trimmed.substring(0, trimmed.length - 1).trim();
    }
    final numeric = _tryParseDecimalString(numericPart, allowNegative: false);
    if (numeric == null) {
      return null;
    }
    final meters = numeric * multiplier;
    if (!meters.isFinite ||
        meters < _minLocationRadiusMeters ||
        meters > maxTdfLocationRadius) {
      return null;
    }
    final roundedMeters = double.tryParse(
      TdfLocation.formatRoundedDouble(meters, 2),
    );
    if (roundedMeters == null ||
        roundedMeters < _minLocationRadiusMeters ||
        roundedMeters > maxTdfLocationRadius) {
      return null;
    }
    return roundedMeters;
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

  /// Resolves the current `due` draft in [configuration]'s local wall-clock time, preserving [initialDueAt] and [initialDueAnchor] when unedited.
  static ResolvedDueDraft resolveDueDraft({
    required WebDavConfig configuration,
    required bool hasDue,
    required String rawDueText,
    required DateTime? initialDueAt,
    required TdfLocalDateTime? initialDueAnchor,
    required String initialDueText,
  }) {
    if (!hasDue) {
      return const ResolvedDueDraft(
        dueAt: null,
        dueLocalInput: null,
        dueAnchor: null,
        isUnchanged: false,
        isValid: true,
      );
    }
    final trimmed = rawDueText.trim();
    if (initialDueAt case final baselineDueAt? when trimmed == initialDueText) {
      return ResolvedDueDraft(
        dueAt: baselineDueAt,
        dueLocalInput: null,
        dueAnchor: initialDueAnchor,
        isUnchanged: true,
        isValid: true,
      );
    }
    final parsed = tryParseLocalDateTimeInput(trimmed, configuration);
    if (parsed == null) {
      return const ResolvedDueDraft(
        dueAt: null,
        dueLocalInput: null,
        dueAnchor: null,
        isUnchanged: false,
        isValid: false,
      );
    }
    return ResolvedDueDraft(
      dueAt: parsed.resolvedUtc,
      dueLocalInput: parsed.localInput,
      dueAnchor: parsed.localInput,
      isUnchanged: false,
      isValid: true,
    );
  }

  /// Resolves [rawTimestamp] in [configuration]'s local wall-clock time to a normalized UTC [DateTime], or `null` if invalid.
  static DateTime? resolveHistoryTimestampUtc({
    required WebDavConfig configuration,
    required DateTime fallbackNowUtc,
    String? preservedTimestampText,
    DateTime? preservedTimestampUtc,
    required String rawTimestamp,
  }) {
    final trimmed = rawTimestamp.trim();
    if (trimmed.isEmpty) {
      final normalizedFallback = TaskItem.normalizeTimestamp(fallbackNowUtc);
      return TdfCalendar.isWithinTimestampBounds(normalizedFallback)
          ? normalizedFallback
          : null;
    }
    if (preservedTimestampUtc != null &&
        preservedTimestampText != null &&
        trimmed == preservedTimestampText) {
      final normalizedPreserved = TaskItem.normalizeTimestamp(
        preservedTimestampUtc,
      );
      return TdfCalendar.isWithinTimestampBounds(normalizedPreserved)
          ? normalizedPreserved
          : null;
    }
    final parsedLocal = TaskItem.tryParseTdfTimestampInput(trimmed);
    if (parsedLocal == null) {
      return null;
    }
    return _tryConvertLocalWallClockToUtc(configuration, parsedLocal);
  }

  /// Resolves the current `suspended` draft in [configuration]'s local wall-clock time, preserving [initialSuspendedAt] when unedited.
  static ResolvedSuspendedDraft resolveSuspendedDraft({
    required WebDavConfig configuration,
    required bool isSuspended,
    required String rawSuspendedText,
    required DateTime? initialSuspendedAt,
    required String initialSuspendedText,
  }) {
    if (!isSuspended) {
      return const ResolvedSuspendedDraft(
        suspendedAt: null,
        suspendedLocalInput: null,
        isForever: false,
        isValid: true,
      );
    }
    final trimmed = rawSuspendedText.trim();
    if (trimmed.isEmpty) {
      return const ResolvedSuspendedDraft(
        suspendedAt: null,
        suspendedLocalInput: null,
        isForever: true,
        isValid: true,
      );
    }
    if (initialSuspendedAt case final baselineSuspendedAt?
        when trimmed == initialSuspendedText) {
      return ResolvedSuspendedDraft(
        suspendedAt: baselineSuspendedAt,
        suspendedLocalInput: null,
        isForever: false,
        isValid: true,
      );
    }
    final parsed = tryParseLocalDateTimeInput(trimmed, configuration);
    if (parsed == null) {
      return const ResolvedSuspendedDraft(
        suspendedAt: null,
        suspendedLocalInput: null,
        isForever: false,
        isValid: false,
      );
    }
    return ResolvedSuspendedDraft(
      suspendedAt: null,
      suspendedLocalInput: parsed.localInput,
      isForever: false,
      isValid: true,
    );
  }

  /// Trims outer ASCII whitespace and collapses internal CR/LF/TAB sequences into single spaces.
  static String sanitizeHistoryText(String rawText) {
    var firstKeep = -1;
    var lastKeep = -1;
    for (var i = 0; i < rawText.length; i++) {
      if (!_isAsciiTrimWhitespace(rawText.codeUnitAt(i))) {
        firstKeep = firstKeep < 0 ? i : firstKeep;
        lastKeep = i;
      }
    }
    if (firstKeep < 0) {
      return '';
    }
    var hasInternalBreak = false;
    for (var i = firstKeep; i <= lastKeep; i++) {
      if (_isInternalLineBreakOrTab(rawText.codeUnitAt(i))) {
        hasInternalBreak = true;
        break;
      }
    }
    if (!hasInternalBreak) {
      return firstKeep == 0 && lastKeep == rawText.length - 1
          ? rawText
          : rawText.substring(firstKeep, lastKeep + 1);
    }
    return _replaceInternalBreaksWithSpaces(rawText, firstKeep, lastKeep);
  }

  /// Returns the soft WIP limit for [tier] ([TaskBoard.focusSoftLimit] for Focus, [TaskBoard.readySoftLimit] for Ready, else `null`).
  static int? tierWipLimit(TaskTier tier) {
    return switch (tier) {
      TaskTier.focus => TaskBoard.focusSoftLimit,
      TaskTier.ready => TaskBoard.readySoftLimit,
      TaskTier.planned ||
      TaskTier.blocked ||
      TaskTier.someday ||
      TaskTier.completed => null,
    };
  }

  /// Parses [rawInput] as a local calendar timestamp and resolves its UTC instant under [configuration] (`TDF-CAL-001`).
  static ({TdfLocalDateTime localInput, DateTime resolvedUtc})?
  tryParseLocalDateTimeInput(String rawInput, WebDavConfig configuration) {
    final parsedWallClock = TaskItem.tryParseTdfTimestampInput(rawInput.trim());
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

  /// Validates [text] against TDF `0.8.0` single-line `<text>` bounds, returning a localized error or `null`.
  static String? validateHistoryText(
    String text,
    AppLocalizations localizations,
  ) {
    final scalarCount = TdfCalendar.countUnicodeScalars(text);
    if (scalarCount == null) {
      return localizations.historyErrorTextInvalid;
    }
    var hasGraphic = false;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit <= 0x1F || unit == 0x7F) {
        return localizations.historyErrorTextInvalid;
      }
      if (unit != 0x20) {
        hasGraphic = true;
      }
    }
    if (!hasGraphic) {
      return localizations.historyErrorTextEmpty;
    }
    if (scalarCount > maxTdfTextLength) {
      return localizations.historyErrorTextTooLong;
    }
    return null;
  }

  /// Validates a single task or label reference link input against TDF `0.8.0` bounds.
  static String? validateLinkInput({
    required String rawTitle,
    required String rawUri,
    required int currentCount,
    required AppLocalizations localizations,
    bool isEditingExisting = false,
    bool isLabel = false,
  }) {
    final maxLinks = isLabel ? maxTdfLinksPerLabel : maxTdfLinksPerTask;
    if (!isEditingExisting && currentCount >= maxLinks) {
      return isLabel
          ? localizations.labelLinkErrorMaxExceeded
          : localizations.linkErrorMaxExceeded;
    }
    final parsed = TaskLink.tryParse(rawTitle: rawTitle, rawUri: rawUri);
    if (parsed == null) {
      return localizations.linkErrorInvalid;
    }
    return null;
  }

  /// Validates a bounded list of [TaskLink] items (`<= 20`) into canonical [TaskLink] models.
  static ({List<TaskLink> links, String? error}) validateLinksList({
    required Iterable<TaskLink> links,
    required AppLocalizations localizations,
    bool isLabel = false,
  }) {
    final maxLinks = isLabel ? maxTdfLinksPerLabel : maxTdfLinksPerTask;
    final maxExceededError = isLabel
        ? localizations.labelLinkErrorMaxExceeded
        : localizations.linkErrorMaxExceeded;
    final validated = <TaskLink>[];
    for (final link in links) {
      if (validated.length >= maxLinks) {
        return (links: const <TaskLink>[], error: maxExceededError);
      }
      final parsed = TaskLink.tryParse(rawTitle: link.title, rawUri: link.uri);
      if (parsed == null) {
        return (
          links: const <TaskLink>[],
          error: localizations.linkErrorInvalid,
        );
      }
      validated.add(parsed);
    }
    return (
      links: validated.isEmpty
          ? const <TaskLink>[]
          : List<TaskLink>.unmodifiable(validated),
      error: null,
    );
  }

  /// Validates an optional location source string according to [sourceType] and single-line `<text>` bounds.
  static ({String? normalizedSource, String? error}) validateLocationSource({
    required LocationSourceType sourceType,
    required String rawSource,
    required AppLocalizations localizations,
  }) {
    if (sourceType == LocationSourceType.gps) {
      return (normalizedSource: null, error: null);
    }
    if (TdfMetadata.containsAsciiControlChar(rawSource)) {
      return (
        normalizedSource: null,
        error: localizations.locationSourceErrorEmpty,
      );
    }
    final trimmed = rawSource.trim();
    if (trimmed.isEmpty) {
      return (normalizedSource: null, error: null);
    }
    final scalarCount = TdfCalendar.countUnicodeScalars(trimmed);
    if (scalarCount == null || scalarCount > maxTdfTextLength) {
      return (
        normalizedSource: null,
        error: localizations.locationSourceErrorEmpty,
      );
    }
    return (normalizedSource: trimmed, error: null);
  }

  /// Validates an optional `#RRGGBB` color input string, rejecting control characters and malformed hex values.
  static ({String? normalizedHex, String? error}) validateOptionalColor(
    String rawColorHex,
    AppLocalizations localizations,
  ) {
    if (TdfMetadata.containsAsciiControlChar(rawColorHex)) {
      return (normalizedHex: null, error: localizations.labelColorErrorInvalid);
    }
    final trimmed = rawColorHex.trim();
    if (trimmed.isEmpty) {
      return (normalizedHex: null, error: null);
    }
    final normalized = TdfColor.normalizeHex(trimmed);
    if (normalized == null) {
      return (normalizedHex: null, error: localizations.labelColorErrorInvalid);
    }
    return (normalizedHex: normalized, error: null);
  }

  /// Validates [note] against `<note>` control-character, surrogate, and `maxTdfNoteLength` (`2000`) bounds.
  static String? validateSchedulingNote(
    String? note,
    AppLocalizations localizations,
  ) {
    if (note == null) {
      return null;
    }
    final scalarCount = TdfCalendar.countUnicodeScalars(note);
    if (scalarCount == null || _containsIllegalNoteControlChar(note)) {
      return localizations.schedulingNoteErrorInvalid;
    }
    if (scalarCount > maxTdfNoteLength) {
      return localizations.schedulingNoteErrorTooLong;
    }
    return null;
  }

  /// Validates single-line `<text>` (`1..500` Unicode scalars, rejecting control characters and unpaired surrogates).
  static ({String trimmed, String? error}) validateSingleLineText({
    required String rawText,
    required String emptyError,
    required String invalidError,
    required String tooLongError,
  }) {
    if (TdfMetadata.containsAsciiControlChar(rawText) ||
        TdfCalendar.countUnicodeScalars(rawText) == null) {
      return (trimmed: '', error: invalidError);
    }
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      return (trimmed: '', error: emptyError);
    }
    final scalarCount = TdfCalendar.countUnicodeScalars(trimmed);
    if (scalarCount == null) {
      return (trimmed: '', error: invalidError);
    }
    if (scalarCount > maxTdfTextLength) {
      return (trimmed: trimmed, error: tooLongError);
    }
    return (trimmed: trimmed, error: null);
  }

  /// Strips blank steps and validates remaining subtasks against `maxTdfStmtsPerBlock` (`1024`) and `maxTdfTextLength` (`500`).
  static ({List<SubtaskItem> subtasks, String? error}) validateSubtasksList({
    required Iterable<SubtaskItem> subtasks,
    required AppLocalizations localizations,
  }) {
    final validated = <SubtaskItem>[];
    for (final step in subtasks) {
      final result = _validateSubtaskStep(step, localizations);
      if (result.error case final error?) {
        return (subtasks: const <SubtaskItem>[], error: error);
      }
      final item = result.item;
      if (item == null) {
        continue;
      }
      if (validated.length >= maxTdfStmtsPerBlock) {
        return (
          subtasks: const <SubtaskItem>[],
          error: localizations.errorLocalFileTooLarge,
        );
      }
      validated.add(item);
    }
    return (
      subtasks: validated.isEmpty
          ? const <SubtaskItem>[]
          : List<SubtaskItem>.unmodifiable(validated),
      error: null,
    );
  }

  /// Validates [rawTitle] against empty and case-insensitive duplicate task title constraints on [board].
  static String? validateTaskTitle({
    required TaskBoard board,
    required String rawTitle,
    required String? excludingTaskId,
    required AppLocalizations localizations,
  }) {
    final trimmed = rawTitle.trim();
    if (trimmed.isEmpty) {
      return localizations.taskNameErrorEmpty;
    }
    if (board.hasDuplicateTaskTitle(
      trimmed,
      excludingTaskId: excludingTaskId,
    )) {
      return localizations.taskNameErrorDuplicate;
    }
    return null;
  }

  /// Converts [parsedLocal] via [configuration] (`TDF-CAL-001`), returning `null` on calendar or context errors.
  static DateTime? _tryConvertLocalWallClockToUtc(
    WebDavConfig configuration,
    DateTime parsedLocal,
  ) {
    try {
      final convertedUtc = TaskItem.normalizeTimestamp(
        configuration.localWallClockToUtc(parsedLocal),
      );
      return TdfCalendar.isWithinTimestampBounds(convertedUtc)
          ? convertedUtc
          : null;
    } on TdfException {
      return null;
    } on TdfContextException {
      return null;
    } on FormatException {
      return null;
    }
  }
}

/// Immutable daily time-window draft pair (`HH:MM`..`HH:MM`).
@immutable
class TimeWindowDraft {
  /// Creates a [TimeWindowDraft].
  const TimeWindowDraft({required this.start, required this.end});

  /// Inclusive end time token (`HH:MM`).
  final String end;

  /// Inclusive start time token (`HH:MM`).
  final String start;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TimeWindowDraft && other.start == start && other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);
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

/// Maps [ConditionCompileMode] to UI [ConditionDimensionMode].
ConditionDimensionMode _fromCompileMode(ConditionCompileMode mode) =>
    switch (mode) {
      ConditionCompileMode.inherit => ConditionDimensionMode.inherit,
      ConditionCompileMode.any => ConditionDimensionMode.any,
      ConditionCompileMode.custom => ConditionDimensionMode.custom,
    };

/// Returns `true` when [unit] is ASCII trim whitespace (`TAB`, `LF`, `CR`, or `SPACE`).
bool _isAsciiTrimWhitespace(int unit) =>
    unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0x20;

/// Returns `true` when [unit] is `TAB`, `LF`, or `CR`.
bool _isInternalLineBreakOrTab(int unit) =>
    unit == 0x09 || unit == 0x0A || unit == 0x0D;

/// Collapses `\r\n`, `\r`, `\n`, and `\t` inside `rawText[start..end]` into single `0x20` spaces.
String _replaceInternalBreaksWithSpaces(String rawText, int start, int end) {
  final buffer = StringBuffer();
  for (var i = start; i <= end; i++) {
    final unit = rawText.codeUnitAt(i);
    if (unit == 0x0D && i < end && rawText.codeUnitAt(i + 1) == 0x0A) {
      buffer.writeCharCode(0x20);
      i++;
    } else if (_isInternalLineBreakOrTab(unit)) {
      buffer.writeCharCode(0x20);
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

/// Maps UI [ConditionDimensionMode] to [ConditionCompileMode].
ConditionCompileMode _toCompileMode(ConditionDimensionMode mode) =>
    switch (mode) {
      ConditionDimensionMode.inherit => ConditionCompileMode.inherit,
      ConditionDimensionMode.any => ConditionCompileMode.any,
      ConditionDimensionMode.custom => ConditionCompileMode.custom,
    };

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

/// Parses a strict finite decimal string accepting `.` or `,` without exponents, or returns `null`.
double? _tryParseDecimalString(String raw, {required bool allowNegative}) {
  if (raw.isEmpty || TdfMetadata.containsAsciiControlChar(raw)) {
    return null;
  }
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.length > maxTdfNumberLength) {
    return null;
  }
  var index = 0;
  if (trimmed.codeUnitAt(0) == 0x2D) {
    if (!allowNegative || trimmed.length == 1) {
      return null;
    }
    index = 1;
  }
  var hasIntegerDigits = false;
  var decimalSeparatorIndex = -1;
  var hasFractionalDigits = false;
  for (; index < trimmed.length; index++) {
    final unit = trimmed.codeUnitAt(index);
    final isDigit = unit >= 0x30 && unit <= 0x39;
    if (isDigit) {
      if (decimalSeparatorIndex < 0) {
        hasIntegerDigits = true;
      } else {
        hasFractionalDigits = true;
      }
      continue;
    }
    final isSeparator = unit == 0x2E || unit == 0x2C;
    if (isSeparator && decimalSeparatorIndex < 0 && hasIntegerDigits) {
      decimalSeparatorIndex = index;
      continue;
    }
    return null;
  }
  if (!hasIntegerDigits ||
      (decimalSeparatorIndex >= 0 && !hasFractionalDigits)) {
    return null;
  }
  final normalized =
      decimalSeparatorIndex >= 0 &&
          trimmed.codeUnitAt(decimalSeparatorIndex) == 0x2C
      ? '${trimmed.substring(0, decimalSeparatorIndex)}.${trimmed.substring(decimalSeparatorIndex + 1)}'
      : trimmed;
  final parsed = double.tryParse(normalized);
  if (parsed == null || parsed.isNaN || parsed.isInfinite) {
    return null;
  }
  return parsed == 0.0 ? 0.0 : parsed;
}

/// Validates a single [step], returning `(item: null, error: null)` when blank or a localized error on invalid bounds.
({SubtaskItem? item, String? error}) _validateSubtaskStep(
  SubtaskItem step,
  AppLocalizations localizations,
) {
  if (TdfMetadata.containsAsciiControlChar(step.title) ||
      TdfCalendar.countUnicodeScalars(step.title) == null) {
    return (item: null, error: localizations.historyErrorTextInvalid);
  }
  final trimmed = step.title.trim();
  if (trimmed.isEmpty) {
    return (item: null, error: null);
  }
  final scalarCount = TdfCalendar.countUnicodeScalars(trimmed);
  if (scalarCount == null) {
    return (item: null, error: localizations.historyErrorTextInvalid);
  }
  if (scalarCount > maxTdfTextLength) {
    return (item: null, error: localizations.historyErrorTextTooLong);
  }
  return (
    item: SubtaskItem(title: trimmed, isCompleted: step.isCompleted),
    error: null,
  );
}
