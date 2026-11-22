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
import '../models/task_board.dart';
import '../models/tdf_error.dart';
import '../models/tdf_location.dart';
import '../models/tdf_metadata.dart';

/// Per-dimension compilation mode for activation condition drafts.
enum ConditionCompileMode {
  /// Inherit condition rules from assigned labels (no own directive emitted).
  inherit,

  /// Override inherited label rules so this dimension always matches.
  any,

  /// Emit explicit custom rules for this dimension.
  custom,
}

/// Stateless helper owning activation condition draft extraction, compilation, and localized summary chip generation.
@immutable
class TaskConditionDraftHelper {
  /// Prevents instantiation of [TaskConditionDraftHelper].
  const TaskConditionDraftHelper._();

  /// Builds read-only condition summary chip records for [ownRules] plus optional [inheritedRules].
  static List<ConditionSummaryChipRecord> buildSummaryChips({
    required List<TaskCondition> ownRules,
    required Iterable<TaskCondition> inheritedRules,
    required Map<String, TdfLocation> locationsById,
    required AppLocalizations localizations,
  }) {
    final chips = <ConditionSummaryChipRecord>[];
    final hasGlobalReset = ownRules.any(
      (condition) => condition is GlobalResetTaskCondition,
    );
    if (hasGlobalReset) {
      chips.add((
        label: localizations.conditionGlobalAnyLabel,
        locationId: null,
        isInherited: false,
      ));
    }
    _appendRuleSummaryChips(
      rules: ownRules,
      isInherited: false,
      locationsById: locationsById,
      localizations: localizations,
      target: chips,
    );
    if (!hasGlobalReset && inheritedRules.isNotEmpty) {
      _appendRuleSummaryChips(
        rules: inheritedRules,
        isInherited: true,
        locationsById: locationsById,
        localizations: localizations,
        target: chips,
      );
    }
    return chips;
  }

  /// Compiles and validates condition draft dimensions into canonical [TaskCondition] rules for a task or label.
  static ({List<TaskCondition> conditions, String? error}) compileConditions({
    required bool ignoreAllLabelConditions,
    required ConditionCompileMode daysMode,
    required List<int> weekdays,
    required ConditionCompileMode timeMode,
    required List<TimeWindowTokenPair> timeWindows,
    required ConditionCompileMode locationMode,
    required List<String> locationIds,
    required TaskBoard board,
    required bool isTask,
    required AppLocalizations localizations,
  }) {
    if (isTask && ignoreAllLabelConditions) {
      return (
        conditions: const <TaskCondition>[GlobalResetTaskCondition()],
        error: null,
      );
    }
    final rules = <TaskCondition>[];

    final dayError = _compileDayDimension(
      mode: daysMode,
      weekdays: weekdays,
      isTask: isTask,
      rules: rules,
      localizations: localizations,
    );
    if (dayError != null) {
      return (conditions: const <TaskCondition>[], error: dayError);
    }

    final timeError = _compileTimeDimension(
      mode: timeMode,
      timeWindows: timeWindows,
      isTask: isTask,
      rules: rules,
      localizations: localizations,
    );
    if (timeError != null) {
      return (conditions: const <TaskCondition>[], error: timeError);
    }

    final locationError = _compileLocationDimension(
      mode: locationMode,
      locationIds: locationIds,
      board: board,
      isTask: isTask,
      rules: rules,
      localizations: localizations,
    );
    if (locationError != null) {
      return (conditions: const <TaskCondition>[], error: locationError);
    }

    return (
      conditions: rules.isEmpty
          ? const <TaskCondition>[]
          : List<TaskCondition>.unmodifiable(rules),
      error: null,
    );
  }

  /// Extracts normalized condition draft fields from [rules] for a task or label.
  static ExtractedConditionDraft extractDraftFields(
    List<TaskCondition> rules, {
    required bool isTask,
  }) {
    final accumulator = _ConditionDraftAccumulator();
    for (final rule in rules) {
      _accumulateConditionRule(rule, accumulator, isTask: isTask);
    }
    accumulator.weekdays.sort();
    return (
      ignoreAllLabelConditions: accumulator.ignoreAll,
      dayAny: accumulator.dayAny,
      weekdays: accumulator.weekdays,
      timeAny: accumulator.timeAny,
      timeWindows: accumulator.timeWindows,
      locationAny: accumulator.locationAny,
      locationIds: accumulator.locationIds,
    );
  }

  /// Resolves the compilation mode for one dimension from entity kind and extracted rule flags.
  static ConditionCompileMode resolveDimensionMode({
    required bool isTask,
    required bool hasRules,
    required bool hasAny,
  }) {
    if (hasRules) {
      return ConditionCompileMode.custom;
    }
    if (isTask && hasAny) {
      return ConditionCompileMode.any;
    }
    return isTask ? ConditionCompileMode.inherit : ConditionCompileMode.custom;
  }
}

/// Mutable accumulator collecting condition dimensions during a single-pass scan of rules.
class _ConditionDraftAccumulator {
  /// Creates an empty [_ConditionDraftAccumulator].
  _ConditionDraftAccumulator();

  /// Unique referenced location identifiers in insertion order.
  final List<String> locationIds = <String>[];

  /// Parsed daily time-window token pairs in declaration order.
  final List<TimeWindowTokenPair> timeWindows = <TimeWindowTokenPair>[];

  /// Unique ISO weekdays collected from day rules.
  final List<int> weekdays = <int>[];

  /// Whether a `day any` group reset was seen.
  bool dayAny = false;

  /// Whether a global `condition any` reset was seen on a task.
  bool ignoreAll = false;

  /// Whether a `location any` group reset was seen.
  bool locationAny = false;

  /// Whether a `time any` group reset was seen.
  bool timeAny = false;
}

/// Read-only condition summary chip data produced by [TaskConditionDraftHelper.buildSummaryChips].
typedef ConditionSummaryChipRecord = ({
  String label,
  String? locationId,
  bool isInherited,
});

/// Normalized condition draft dimensions extracted by [TaskConditionDraftHelper.extractDraftFields].
typedef ExtractedConditionDraft = ({
  bool ignoreAllLabelConditions,
  bool dayAny,
  List<int> weekdays,
  bool timeAny,
  List<TimeWindowTokenPair> timeWindows,
  bool locationAny,
  List<String> locationIds,
});

/// Daily time-window token pair (`HH:MM`..`HH:MM`) used by [TaskConditionDraftHelper].
typedef TimeWindowTokenPair = ({String start, String end});

/// Accumulates one [TaskCondition] into [accumulator] without nesting loops or switches.
void _accumulateConditionRule(
  TaskCondition rule,
  _ConditionDraftAccumulator accumulator, {
  required bool isTask,
}) {
  switch (rule) {
    case GlobalResetTaskCondition():
      if (isTask) {
        accumulator.ignoreAll = true;
      }
    case GroupResetTaskCondition(:final targetGroup):
      _markGroupReset(targetGroup, accumulator);
    case DayTaskCondition(:final weekdays):
      _appendUniqueInts(weekdays, accumulator.weekdays);
    case TimeWindowTaskCondition(:final startToken, :final endToken):
      accumulator.timeWindows.add((start: startToken, end: endToken));
    case LocationTaskCondition(:final locationIds):
      _appendUniqueStrings(locationIds, accumulator.locationIds);
  }
}

/// Validates and appends a custom weekday condition to [rules], returning an error message or `null`.
String? _appendCustomDayCondition({
  required List<int> weekdays,
  required List<TaskCondition> rules,
  required AppLocalizations localizations,
}) {
  for (final weekday in weekdays) {
    if (weekday < DateTime.monday || weekday > DateTime.sunday) {
      return localizations.conditionTimeErrorInvalid;
    }
  }
  if (weekdays.isEmpty) {
    return null;
  }
  if (rules.length >= maxTdfConditionRulesPerEntity) {
    return localizations.errorLocalFileTooLarge;
  }
  rules.add(DayTaskCondition.fromWeekdays(weekdays));
  return null;
}

/// Validates and appends a custom location condition to [rules], enforcing `maxTdfLocationRefsPerEntity` before deduplication.
String? _appendCustomLocationCondition({
  required List<String> locationIds,
  required TaskBoard board,
  required List<TaskCondition> rules,
  required AppLocalizations localizations,
}) {
  if (locationIds.length > maxTdfLocationRefsPerEntity) {
    return localizations.errorLocalFileTooLarge;
  }
  final deduplicatedIds = <String>[];
  final seenIds = <String>{};
  for (final locationId in locationIds) {
    if (board.findLocation(locationId) == null) {
      return localizations.conditionLocationErrorInvalid;
    }
    if (seenIds.add(locationId)) {
      deduplicatedIds.add(locationId);
    }
  }
  if (deduplicatedIds.isEmpty) {
    return null;
  }
  if (rules.length >= maxTdfConditionRulesPerEntity) {
    return localizations.errorLocalFileTooLarge;
  }
  rules.add(LocationTaskCondition.fromIds(deduplicatedIds));
  return null;
}

/// Validates and appends custom time-window conditions to [rules], enforcing `maxTdfConditionRulesPerEntity`.
String? _appendCustomTimeConditions({
  required List<TimeWindowTokenPair> timeWindows,
  required List<TaskCondition> rules,
  required AppLocalizations localizations,
}) {
  for (final window in timeWindows) {
    if (rules.length >= maxTdfConditionRulesPerEntity) {
      return localizations.errorLocalFileTooLarge;
    }
    if (TdfMetadata.containsAsciiControlChar(window.start) ||
        TdfMetadata.containsAsciiControlChar(window.end)) {
      return localizations.conditionTimeErrorInvalid;
    }
    final parsedWindow = TimeWindowTaskCondition.tryParse(
      window.start,
      window.end,
    );
    if (parsedWindow == null) {
      return localizations.conditionTimeErrorInvalid;
    }
    rules.add(parsedWindow);
  }
  return null;
}

/// Appends a [GroupResetTaskCondition] for [targetGroup] respecting `maxTdfConditionRulesPerEntity`.
String? _appendGroupResetRule(
  ConditionGroup targetGroup,
  List<TaskCondition> rules,
  AppLocalizations localizations,
) {
  if (rules.length >= maxTdfConditionRulesPerEntity) {
    return localizations.errorLocalFileTooLarge;
  }
  rules.add(GroupResetTaskCondition(targetGroup: targetGroup));
  return null;
}

/// Appends location condition summary chip records for [locationIds] into [target].
void _appendLocationSummaryChips({
  required List<String> locationIds,
  required bool isInherited,
  required Map<String, TdfLocation> locationsById,
  required List<ConditionSummaryChipRecord> target,
}) {
  for (final locationId in locationIds) {
    final location = locationsById[locationId];
    target.add((
      label: location?.name ?? locationId,
      locationId: location != null ? locationId : null,
      isInherited: isInherited,
    ));
  }
}

/// Appends localized summary chip records for each rule in [rules].
void _appendRuleSummaryChips({
  required Iterable<TaskCondition> rules,
  required bool isInherited,
  required Map<String, TdfLocation> locationsById,
  required AppLocalizations localizations,
  required List<ConditionSummaryChipRecord> target,
}) {
  final dayNames = <String>[
    localizations.weekdayMon,
    localizations.weekdayTue,
    localizations.weekdayWed,
    localizations.weekdayThu,
    localizations.weekdayFri,
    localizations.weekdaySat,
    localizations.weekdaySun,
  ];
  for (final rule in rules) {
    _appendSingleRuleSummaryChips(
      rule: rule,
      isInherited: isInherited,
      dayNames: dayNames,
      locationsById: locationsById,
      localizations: localizations,
      target: target,
    );
  }
}

/// Appends localized summary chip records for a single [rule] into [target].
void _appendSingleRuleSummaryChips({
  required TaskCondition rule,
  required bool isInherited,
  required List<String> dayNames,
  required Map<String, TdfLocation> locationsById,
  required AppLocalizations localizations,
  required List<ConditionSummaryChipRecord> target,
}) {
  switch (rule) {
    case GlobalResetTaskCondition():
      return;
    case GroupResetTaskCondition(:final targetGroup):
      final label = switch (targetGroup) {
        ConditionGroup.day => localizations.conditionDayAnyLabel,
        ConditionGroup.time => localizations.conditionTimeAnyLabel,
        ConditionGroup.location => localizations.conditionLocationAnyLabel,
      };
      target.add((label: label, locationId: null, isInherited: isInherited));
    case DayTaskCondition(:final weekdays):
      final formatted = _formatWeekdaysSummary(weekdays, dayNames);
      if (formatted.isNotEmpty) {
        target.add((
          label: formatted,
          locationId: null,
          isInherited: isInherited,
        ));
      }
    case TimeWindowTaskCondition(:final startToken, :final endToken):
      target.add((
        label: '$startToken - $endToken',
        locationId: null,
        isInherited: isInherited,
      ));
    case LocationTaskCondition(:final locationIds):
      _appendLocationSummaryChips(
        locationIds: locationIds,
        isInherited: isInherited,
        locationsById: locationsById,
        target: target,
      );
  }
}

/// Appends unique integer items from [source] to [target] preserving insertion order.
void _appendUniqueInts(Iterable<int> source, List<int> target) {
  for (final item in source) {
    if (!target.contains(item)) {
      target.add(item);
    }
  }
}

/// Appends unique string items from [source] to [target] preserving insertion order.
void _appendUniqueStrings(Iterable<String> source, List<String> target) {
  for (final item in source) {
    if (!target.contains(item)) {
      target.add(item);
    }
  }
}

/// Compiles the weekday dimension for [mode] and appends to [rules], returning an error or `null`.
String? _compileDayDimension({
  required ConditionCompileMode mode,
  required List<int> weekdays,
  required bool isTask,
  required List<TaskCondition> rules,
  required AppLocalizations localizations,
}) {
  if (!isTask) {
    if (mode == ConditionCompileMode.any || weekdays.isEmpty) {
      return null;
    }
    return _appendCustomDayCondition(
      weekdays: weekdays,
      rules: rules,
      localizations: localizations,
    );
  }
  return switch (mode) {
    ConditionCompileMode.inherit => null,
    ConditionCompileMode.any => _appendGroupResetRule(
      ConditionGroup.day,
      rules,
      localizations,
    ),
    ConditionCompileMode.custom => _appendCustomDayCondition(
      weekdays: weekdays,
      rules: rules,
      localizations: localizations,
    ),
  };
}

/// Compiles the location dimension for [mode] and appends to [rules], returning an error or `null`.
String? _compileLocationDimension({
  required ConditionCompileMode mode,
  required List<String> locationIds,
  required TaskBoard board,
  required bool isTask,
  required List<TaskCondition> rules,
  required AppLocalizations localizations,
}) {
  if (!isTask) {
    if (mode == ConditionCompileMode.any || locationIds.isEmpty) {
      return null;
    }
    return _appendCustomLocationCondition(
      locationIds: locationIds,
      board: board,
      rules: rules,
      localizations: localizations,
    );
  }
  return switch (mode) {
    ConditionCompileMode.inherit => null,
    ConditionCompileMode.any => _appendGroupResetRule(
      ConditionGroup.location,
      rules,
      localizations,
    ),
    ConditionCompileMode.custom => _appendCustomLocationCondition(
      locationIds: locationIds,
      board: board,
      rules: rules,
      localizations: localizations,
    ),
  };
}

/// Compiles the time-window dimension for [mode] and appends to [rules], returning an error or `null`.
String? _compileTimeDimension({
  required ConditionCompileMode mode,
  required List<TimeWindowTokenPair> timeWindows,
  required bool isTask,
  required List<TaskCondition> rules,
  required AppLocalizations localizations,
}) {
  if (!isTask) {
    if (mode == ConditionCompileMode.any || timeWindows.isEmpty) {
      return null;
    }
    return _appendCustomTimeConditions(
      timeWindows: timeWindows,
      rules: rules,
      localizations: localizations,
    );
  }
  return switch (mode) {
    ConditionCompileMode.inherit => null,
    ConditionCompileMode.any => _appendGroupResetRule(
      ConditionGroup.time,
      rules,
      localizations,
    ),
    ConditionCompileMode.custom => _appendCustomTimeConditions(
      timeWindows: timeWindows,
      rules: rules,
      localizations: localizations,
    ),
  };
}

/// Formats valid ISO [weekdays] (`1..7`) into a comma-separated label using [dayNames].
String _formatWeekdaysSummary(List<int> weekdays, List<String> dayNames) {
  final buffer = StringBuffer();
  for (final day in weekdays) {
    if (day < DateTime.monday || day > DateTime.sunday) {
      continue;
    }
    if (buffer.isNotEmpty) {
      buffer.write(', ');
    }
    buffer.write(dayNames[day - 1]);
  }
  return buffer.toString();
}

/// Records a group reset flag on [accumulator] for [targetGroup].
void _markGroupReset(
  ConditionGroup targetGroup,
  _ConditionDraftAccumulator accumulator,
) {
  switch (targetGroup) {
    case ConditionGroup.day:
      accumulator.dayAny = true;
    case ConditionGroup.time:
      accumulator.timeAny = true;
    case ConditionGroup.location:
      accumulator.locationAny = true;
  }
}
