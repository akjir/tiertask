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

import '../models/task_item.dart';
import '../models/tdf_error.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_sync_metadata.dart';
import '../models/tdf_timezone.dart';
import 'tdf_scanner.dart';

/// Mutable directive accumulator fields for a `condition { ... }` sub-block.
mixin class TdfConditionDirectiveFields {
  bool allowResets = false;
  bool hasAnyRule = false;
  Object? parentBuilder;
}

/// Mutable directive accumulator fields for the root `deleted` block.
mixin class TdfDeletedDirectiveFields {
  final List<TdfDeletedLabelRecord> labels = <TdfDeletedLabelRecord>[];
  final List<TdfDeletedTaskRecord> tasks = <TdfDeletedTaskRecord>[];
  int? generation;
  TdfEntityIdRegistry? idRegistry;
}

/// Stateless directive and condition rule parser for `TDF_SPEC.md` Section 4.
@immutable
class TdfDirectiveParser {
  /// Private constructor to prevent instantiation.
  const TdfDirectiveParser._();

  /// Adds [rule] to [builder] after verifying `MAX_CONDITION_RULES_PER_ENTITY`.
  static void addConditionToLabel(
    TdfLabelDirectiveFields builder,
    TaskCondition rule,
    int line,
  ) {
    final valid = builder.conditions.length < maxTdfConditionRulesPerEntity;
    _check(valid, TdfErrorKind.limitExceeded, line);
    builder.conditions.add(rule);
  }

  /// Adds [rule] to [builder] after verifying `MAX_CONDITION_RULES_PER_ENTITY` and Section 4.3 reset conflict constraints.
  static void addConditionToTask(
    TdfTaskDirectiveFields builder,
    TaskCondition rule,
    int line,
  ) {
    final valid = builder.conditions.length < maxTdfConditionRulesPerEntity;
    _check(valid, TdfErrorKind.limitExceeded, line);
    if (rule is GlobalResetTaskCondition) {
      _check(builder.conditions.isEmpty, TdfErrorKind.invalidCondition, line);
      builder.conditions.add(rule);
      return;
    }
    final hasAny = builder.conditions.any((c) => c is GlobalResetTaskCondition);
    _check(!hasAny, TdfErrorKind.invalidCondition, line);
    final group = rule.group;
    final hasConflict = rule is GroupResetTaskCondition
        ? builder.conditions.any((c) => c.group == group)
        : builder.conditions.any(
            (c) => c is GroupResetTaskCondition && c.targetGroup == group,
          );
    _check(!hasConflict, TdfErrorKind.invalidCondition, line);
    builder.conditions.add(rule);
  }

  /// Applies a directive inside a `condition { ... }` sub-block to [builder].
  static void applyConditionDirective(
    TdfConditionDirectiveFields builder,
    String directive,
    List<TdfScannedToken> args,
    int line,
  ) {
    _check(directive != 'any', TdfErrorKind.invalidCondition, line);
    final isKnown =
        directive == 'day' || directive == 'time' || directive == 'location';
    _check(isKnown, TdfErrorKind.unknownDirective, line);
    final allowResets = builder.allowResets;
    final rule = _parseConditionGroupRule(directive, args, line, allowResets);
    final parent = builder.parentBuilder;
    if (parent is TdfLabelDirectiveFields) {
      addConditionToLabel(parent, rule, line);
    } else if (parent is TdfTaskDirectiveFields) {
      addConditionToTask(parent, rule, line);
    }
    builder.hasAnyRule = true;
  }

  /// Applies a directive inside the root `deleted` block (`generation`, `task`, or `label`).
  static void applyDeletedDirective(
    TdfDeletedDirectiveFields builder,
    String directive,
    List<TdfScannedToken> args,
    int line,
  ) {
    const maxGeneration = TdfDeletedBlock.maxGeneration;
    const maxRecords = TdfDeletedBlock.maxDeletedRecords;
    final ids = builder.idRegistry ?? TdfEntityIdRegistry();
    final hasCapacity =
        builder.tasks.length + builder.labels.length < maxRecords;
    switch (directive) {
      case 'generation':
        _checkOnce(builder.generation, line);
        builder.generation = requireUnsignedIntArg(args, line, maxGeneration);
      case 'task':
        _check(hasCapacity, TdfErrorKind.limitExceeded, line);
        final record = _parseDeletedTaskRecord(args, line);
        final id = record.taskId;
        final ok = !ids.taskIds.contains(id) && ids.deletedTaskIds.add(id);
        _check(ok, TdfErrorKind.duplicateIdentifier, line);
        builder.tasks.add(record);
      case 'label':
        _check(hasCapacity, TdfErrorKind.limitExceeded, line);
        final record = _parseDeletedLabelRecord(args, line);
        final id = record.labelId;
        final ok = !ids.labelIds.contains(id) && ids.deletedLabelIds.add(id);
        _check(ok, TdfErrorKind.duplicateIdentifier, line);
        builder.labels.add(record);
      default:
        _fail(TdfErrorKind.unknownDirective, line);
    }
  }

  /// Applies a directive inside a `label` block.
  static void applyLabelDirective(
    TdfLabelDirectiveFields builder,
    String directive,
    List<TdfScannedToken> args,
    int line,
  ) {
    switch (directive) {
      case 'name':
        _checkOnce(builder.name, line);
        builder.name = requireQuotedTextArg(args, line, maxTdfTextLength);
      case 'color':
        _checkOnce(builder.color, line);
        builder.color = _requireColorArg(args, line);
      case 'note':
        _checkOnce(builder.note, line);
        builder.note = requireQuotedTextArg(args, line, maxTdfNoteLength, true);
      case 'modified':
        _checkOnce(builder.modifiedAt, line);
        builder.modifiedAt = requireTimestampArgs(args, line);
      case 'condition':
        final rule = parseInlineConditionArgs(args, line, false);
        addConditionToLabel(builder, rule, line);
      default:
        _fail(TdfErrorKind.unknownDirective, line);
    }
  }

  /// Applies a directive inside the root `queue` block (`modified` or `task`).
  static void applyQueueDirective(
    TdfQueueDirectiveFields builder,
    String directive,
    List<TdfScannedToken> args,
    int line,
  ) {
    switch (directive) {
      case 'modified':
        _checkOnce(builder.modifiedAt, line);
        builder.modifiedAt = requireTimestampArgs(args, line);
      case 'task':
        final withinLimit =
            builder.entries.length < TdfQueueBlock.maxQueueEntries;
        _check(withinLimit, TdfErrorKind.limitExceeded, line);
        _check(args.length == 1, TdfErrorKind.unexpectedToken, line);
        final taskId = requireIdentifierArg(args[0], line);
        final isUnique = builder.seenTaskIds.add(taskId);
        _check(isUnique, TdfErrorKind.duplicateIdentifier, line);
        builder.entries.add((taskId: taskId, line: line));
      default:
        _fail(TdfErrorKind.unknownDirective, line);
    }
  }

  /// Applies a `step` directive inside a `subtasks` sub-block and appends to [steps].
  static void applySubtasks(
    List<SubtaskItem> steps,
    String directive,
    List<TdfScannedToken> args,
    int line,
  ) {
    _check(directive == 'step', TdfErrorKind.unknownDirective, line);
    _check(args.length == 2, TdfErrorKind.unexpectedToken, line);
    final isCompleted = requireBooleanArg(args[0], line);
    final title = requireQuotedTextArg([args[1]], line, maxTdfTextLength);
    steps.add(SubtaskItem(title: title, isCompleted: isCompleted));
  }

  /// Applies a directive inside a `task` block.
  static void applyTaskDirective(
    TdfTaskDirectiveFields builder,
    String directive,
    List<TdfScannedToken> args,
    int line,
  ) {
    const maxCompletions = TdfTaskDependency.maxCompletions;
    switch (directive) {
      case 'name':
        _checkOnce(builder.name, line);
        builder.name = requireQuotedTextArg(args, line, maxTdfTextLength);
      case 'note':
        _checkOnce(builder.note, line);
        builder.note = requireQuotedTextArg(args, line, maxTdfNoteLength, true);
      case 'created':
        _checkOnce(builder.createdAt, line);
        builder.createdAt = requireTimestampArgs(args, line);
      case 'queued':
        _check(builder.isLegacy050, TdfErrorKind.unknownDirective, line);
        _checkOnce(builder.legacyQueuedAt, line);
        builder.legacyQueuedAt = requireTimestampArgs(args, line);
      case 'finished':
        _checkOnce(builder.completedAt, line);
        builder.completedAt = requireTimestampArgs(args, line);
        builder.finishedLine = line;
      case 'modified':
        _checkOnce(builder.modifiedAt, line);
        builder.modifiedAt = requireTimestampArgs(args, line);
      case 'completions':
        _checkOnce(builder.completions, line);
        builder.completions = requireUnsignedIntArg(args, line, maxCompletions);
        builder.completionsLine = line;
      case 'suspended':
        _check(!builder.isSuspendedSet, TdfErrorKind.duplicateDirective, line);
        builder.isSuspendedSet = true;
        if (args.length == 1 && args[0].isBare && args[0].value == 'forever') {
          builder.isSuspendedForever = true;
        } else {
          builder.suspendedAt = requireTimestampArgs(args, line);
        }
      case 'repeat':
        _checkOnce(builder.repeatRule, line);
        builder.repeatRule = requireRepeatRuleArgs(args, line);
      case 'labels':
        _checkOnce(builder.canonicalLabelIds, line);
        builder.canonicalLabelIds = <String>[
          for (final token in args)
            requireIdentifierArg(token, line, isValidLabelId),
        ];
        builder.labelsLine = line;
      case 'blocked':
        _checkOnce(builder.dependencies, line);
        builder.dependencies = _requireDependencyListArgs(args, line);
        builder.blockedLine = line;
      case 'link':
        _applyLinkDirective(builder, args, line);
      case 'condition':
        final rule = parseInlineConditionArgs(args, line, true);
        addConditionToTask(builder, rule, line);
      default:
        _fail(TdfErrorKind.unknownDirective, line);
    }
  }

  /// Parses an inline `condition ...` directive on a `label` or `task` block.
  static TaskCondition parseInlineConditionArgs(
    List<TdfScannedToken> args,
    int line,
    bool allowResets,
  ) {
    final hasType = args.isNotEmpty && args[0].isBare;
    _check(hasType, TdfErrorKind.invalidCondition, line);
    final first = args[0].value;
    if (first == 'any') {
      final validAny = allowResets && args.length == 1;
      _check(validAny, TdfErrorKind.invalidCondition, line);
      return const GlobalResetTaskCondition();
    }
    return _parseConditionGroupRule(first, args.sublist(1), line, allowResets);
  }

  /// Validates that [token] is a bare-word boolean literal (`true` or `false`).
  static bool requireBooleanArg(TdfScannedToken token, int line) {
    final isBoolean =
        token.isBare && (token.value == 'true' || token.value == 'false');
    _check(isBoolean, TdfErrorKind.invalidBoolean, line);
    return token.value == 'true';
  }

  /// Validates that [token] is a bare word satisfying [validator].
  static String requireIdentifierArg(
    TdfScannedToken token,
    int line, [
    bool Function(String) validator = isValidTaskId,
  ]) {
    final valid = token.isBare && validator(token.value);
    _check(valid, TdfErrorKind.invalidIdentifier, line);
    return token.value;
  }

  /// Validates that [args] contains a single text argument within [maxScalars] Unicode scalars.
  static String requireQuotedTextArg(
    List<TdfScannedToken> args,
    int line,
    int maxScalars, [
    bool allowWhitespaceOnly = false,
  ]) {
    _check(args.length == 1, TdfErrorKind.unexpectedToken, line);
    final value = args[0].value;
    final nonBlank = allowWhitespaceOnly || value.trim().isNotEmpty;
    _check(nonBlank, TdfErrorKind.emptyText, line);
    _check(value.isNotEmpty, TdfErrorKind.unexpectedToken, line);
    _requireScalarLength(value, maxScalars, line);
    return value;
  }

  /// Validates and parses `repeat <count> <days|weeks|months> [<repeat-time>]` arguments (`1..maxRepeatCount`).
  static TaskRepeatRule requireRepeatRuleArgs(
    List<TdfScannedToken> args,
    int line,
  ) {
    final validArity = args.length >= 2 && args.length <= 3;
    _check(validArity, TdfErrorKind.unexpectedToken, line);
    final parsedCount = args[0].isBare ? int.tryParse(args[0].value) : null;
    if (parsedCount == null || parsedCount < 1) {
      _fail(TdfErrorKind.invalidNumber, line);
    }
    final withinMax = parsedCount <= TaskRepeatRule.maxRepeatCount;
    _check(withinMax, TdfErrorKind.limitExceeded, line);
    final parsedUnit =
        (args[1].isBare ? RepeatUnit.tryParseToken(args[1].value) : null) ??
        _fail(TdfErrorKind.unexpectedToken, line);
    final clock = args.length < 3
        ? TdfRepeatClock.midnight
        : ((args[2].isBare ? TdfRepeatClock.tryParse(args[2].value) : null) ??
              _fail(TdfErrorKind.invalidTime, line));
    return TaskRepeatRule(count: parsedCount, unit: parsedUnit, clock: clock);
  }

  /// Validates and parses `<YYYY-MM-DD> [<HH:MM[:SS]>]` timestamp arguments.
  static DateTime requireTimestampArgs(List<TdfScannedToken> args, int line) {
    final validTokens =
        args.isNotEmpty &&
        args.length <= 2 &&
        args[0].isBare &&
        (args.length == 1 || args[1].isBare);
    _check(validTokens, TdfErrorKind.invalidTimestamp, line);
    final time = args.length == 2 ? args[1].value : null;
    return TdfScanner.parseCanonicalUtcTimestamp(args[0].value, line, time);
  }

  /// Validates a single unsigned integer bare word (`0..maxAllowed` or `1..maxAllowed`).
  static int requireUnsignedIntArg(
    List<TdfScannedToken> args,
    int line,
    int maxAllowed, [
    bool allowZero = true,
  ]) {
    _check(args.length == 1, TdfErrorKind.unexpectedToken, line);
    _check(args[0].isBare, TdfErrorKind.invalidNumber, line);
    return TdfScanner.parseCanonicalInt(
      args[0].value,
      line,
      maxAllowed,
      allowZero: allowZero,
    );
  }

  /// Validates and appends a `link "<title>" "<uri>"` directive to [builder].
  static void _applyLinkDirective(
    TdfTaskDirectiveFields builder,
    List<TdfScannedToken> args,
    int line,
  ) {
    final validArgs = args.length == 2 && args[0].isQuoted && args[1].isQuoted;
    _check(validArgs, TdfErrorKind.unexpectedToken, line);
    final hasRoom = builder.links.length < TaskLink.maxLinksPerTask;
    _check(hasRoom, TdfErrorKind.limitExceeded, line);
    final title = args[0].value;
    final uri = args[1].value;
    final nonEmpty = title.trim().isNotEmpty && uri.trim().isNotEmpty;
    _check(nonEmpty, TdfErrorKind.emptyText, line);
    _requireScalarLength(title, maxTdfTextLength, line);
    _requireScalarLength(uri, TaskLink.maxUriLength, line);
    _check(TdfScanner.isValidUriScheme(uri), TdfErrorKind.invalidUri, line);
    builder.links.add(TaskLink(title: title, uri: uri));
  }

  /// Throws [TdfErrorKind.duplicateDirective] if [current] is already non-null.
  static void _checkOnce(Object? current, int line) =>
      _check(current == null, TdfErrorKind.duplicateDirective, line);

  /// Parses a group condition rule (`day`, `time`, or `location`).
  static TaskCondition _parseConditionGroupRule(
    String conditionType,
    List<TdfScannedToken> ruleArgs,
    int line,
    bool allowResets,
  ) {
    _check(ruleArgs.isNotEmpty, TdfErrorKind.invalidCondition, line);
    if (ruleArgs.length == 1 &&
        ruleArgs[0].isBare &&
        ruleArgs[0].value == 'any') {
      _check(allowResets, TdfErrorKind.invalidCondition, line);
      final group = switch (conditionType) {
        'day' => ConditionGroup.day,
        'time' => ConditionGroup.time,
        'location' => ConditionGroup.location,
        _ => _fail(TdfErrorKind.unknownDirective, line),
      };
      return GroupResetTaskCondition(targetGroup: group);
    }
    return switch (conditionType) {
      'day' => _parseDayRuleArgs(ruleArgs, line),
      'time' => _parseTimeRuleArgs(ruleArgs, line),
      'location' => _parseLocationRuleArgs(ruleArgs, line),
      _ => _fail(TdfErrorKind.unknownDirective, line),
    };
  }

  /// Parses `day <mon|tue|wed|thu|fri|sat|sun ...>` arguments.
  static DayTaskCondition _parseDayRuleArgs(
    List<TdfScannedToken> ruleArgs,
    int line,
  ) {
    final weekdays = <int>[];
    final dayTokens = <String>[];
    for (final token in ruleArgs) {
      final weekday =
          (token.isBare
              ? DayTaskCondition.parseWeekdayToken(token.value)
              : null) ??
          _fail(TdfErrorKind.invalidCondition, line);
      weekdays.add(weekday);
      dayTokens.add(token.value);
    }
    return DayTaskCondition(weekdays: weekdays, dayTokens: dayTokens);
  }

  /// Parses `label <label-id> <timestamp>` inside a `deleted` block.
  static TdfDeletedLabelRecord _parseDeletedLabelRecord(
    List<TdfScannedToken> args,
    int line,
  ) {
    final validArity = args.length >= 2 && args.length <= 3;
    _check(validArity, TdfErrorKind.unexpectedToken, line);
    final labelId = requireIdentifierArg(args[0], line, isValidLabelId);
    final deletedAt = requireTimestampArgs(args.sublist(1), line);
    return TdfDeletedLabelRecord(labelId: labelId, deletedAt: deletedAt);
  }

  /// Parses `task <task-id> <timestamp> [<completion-count>]` inside a `deleted` block per Section 4.4.
  static TdfDeletedTaskRecord _parseDeletedTaskRecord(
    List<TdfScannedToken> args,
    int line,
  ) {
    const maxCompletions = TdfTaskDependency.maxCompletions;
    final validArity = args.length >= 2 && args.length <= 4;
    _check(validArity, TdfErrorKind.unexpectedToken, line);
    final taskId = requireIdentifierArg(args[0], line);
    final hasTime =
        args.length >= 3 && args[2].isBare && args[2].value.contains(':');
    final timeEnd = hasTime ? 3 : 2;
    _check(args.length <= timeEnd + 1, TdfErrorKind.unexpectedToken, line);
    final deletedAt = requireTimestampArgs(args.sublist(1, timeEnd), line);
    final checkpoint = args.length == timeEnd
        ? 0
        : requireUnsignedIntArg([args[timeEnd]], line, maxCompletions);
    return TdfDeletedTaskRecord(
      taskId: taskId,
      deletedAt: deletedAt,
      completionsCheckpoint: checkpoint,
    );
  }

  /// Parses `location <lat> <lon> <radius>` arguments.
  static LocationTaskCondition _parseLocationRuleArgs(
    List<TdfScannedToken> ruleArgs,
    int line,
  ) {
    _check(ruleArgs.length == 3, TdfErrorKind.invalidCondition, line);
    final latitude = _requireNumberToken(ruleArgs[0], line);
    final longitude = _requireNumberToken(ruleArgs[1], line);
    final radiusMeters = _requireNumberToken(ruleArgs[2], line);
    final validBounds =
        latitude >= -90.0 &&
        latitude <= 90.0 &&
        longitude >= -180.0 &&
        longitude <= 180.0 &&
        radiusMeters > 0.0;
    _check(validBounds, TdfErrorKind.invalidCondition, line);
    return LocationTaskCondition(
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );
  }

  /// Parses `time <start_HH:MM> <end_HH:MM>` arguments.
  static TimeWindowTaskCondition _parseTimeRuleArgs(
    List<TdfScannedToken> ruleArgs,
    int line,
  ) {
    final validArgs =
        ruleArgs.length == 2 && ruleArgs[0].isBare && ruleArgs[1].isBare;
    _check(validArgs, TdfErrorKind.invalidTimestamp, line);
    final startMin = TdfScanner.parseLocalClockMinutes(ruleArgs[0].value, line);
    final endMin = TdfScanner.parseLocalClockMinutes(ruleArgs[1].value, line);
    _check(startMin != endMin, TdfErrorKind.invalidCondition, line);
    return TimeWindowTaskCondition(
      startMinutes: startMin,
      endMinutes: endMin,
      startToken: ruleArgs[0].value,
      endToken: ruleArgs[1].value,
    );
  }

  /// Validates that [args] contains a single quoted `#RRGGBB` hexadecimal color string.
  static String _requireColorArg(List<TdfScannedToken> args, int line) {
    _check(args.length == 1, TdfErrorKind.unexpectedToken, line);
    final token = args[0];
    final valid = token.isQuoted && TdfScanner.isValidHexColor(token.value);
    _check(valid, TdfErrorKind.invalidColor, line);
    return token.value.toUpperCase();
  }

  /// Validates and parses `blocked <dependency> [<dependency> ...]` arguments.
  static List<TdfTaskDependency> _requireDependencyListArgs(
    List<TdfScannedToken> args,
    int line,
  ) {
    final parsed = <TdfTaskDependency>[];
    for (final token in args) {
      _check(token.isBare, TdfErrorKind.invalidIdentifier, line);
      final raw = token.value;
      final colonIndex = raw.indexOf(':');
      final idPart = colonIndex < 0 ? raw : raw.substring(0, colonIndex);
      _check(isValidTaskId(idPart), TdfErrorKind.invalidIdentifier, line);
      if (colonIndex < 0) {
        parsed.add(TdfTaskDependency(taskId: idPart));
        continue;
      }
      final reqCount = TdfScanner.parseCanonicalInt(
        raw.substring(colonIndex + 1),
        line,
        TdfTaskDependency.maxCompletions,
        allowZero: false,
      );
      parsed.add(
        TdfTaskDependency(taskId: idPart, requiredCompletion: reqCount),
      );
    }
    return TdfTaskDependency.normalizeList(parsed);
  }

  /// Validates and parses a decimal `<number>` token (`-?[0-9]+(\.[0-9]+)?`).
  static double _requireNumberToken(TdfScannedToken token, int line) {
    final valid = token.isBare && TdfScanner.isValidDecimalLiteral(token.value);
    _check(valid, TdfErrorKind.invalidNumber, line);
    final parsed = double.tryParse(token.value);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      _fail(TdfErrorKind.invalidNumber, line);
    }
    return parsed;
  }

  /// Validates that [text] contains at most [maxScalars] Unicode scalar values.
  static void _requireScalarLength(String text, int maxScalars, int line) {
    final valid = TdfScanner.countUnicodeScalars(text, line) <= maxScalars;
    _check(valid, TdfErrorKind.limitExceeded, line);
  }
}

/// Tracks seen live and deleted task and label identifiers during parsing.
mixin class TdfEntityIdRegistry {
  final Set<String> deletedLabelIds = <String>{};
  final Set<String> deletedTaskIds = <String>{};
  final Set<String> labelIds = <String>{};
  final Set<String> taskIds = <String>{};
}

/// Mutable directive accumulator fields for a `label` block during single-pass parsing.
mixin class TdfLabelDirectiveFields {
  final List<TaskCondition> conditions = <TaskCondition>[];
  String? color;
  DateTime? modifiedAt;
  String? name;
  String? note;
}

/// Mutable directive accumulator fields for the root `queue` block.
mixin class TdfQueueDirectiveFields {
  final List<({String taskId, int line})> entries = [];
  final Set<String> seenTaskIds = <String>{};
  DateTime? modifiedAt;
}

/// Mutable directive accumulator fields for a `task` block during single-pass parsing.
mixin class TdfTaskDirectiveFields {
  final List<TaskCondition> conditions = <TaskCondition>[];
  final List<TaskLink> links = <TaskLink>[];
  int blockedLine = 0;
  List<String>? canonicalLabelIds;
  DateTime? completedAt;
  int? completions;
  int completionsLine = 0;
  DateTime? createdAt;
  List<TdfTaskDependency>? dependencies;
  int finishedLine = 0;
  bool hasSubtasksBlock = false;
  bool isLegacy050 = false;
  bool isSuspendedForever = false;
  bool isSuspendedSet = false;
  int labelsLine = 0;
  DateTime? legacyQueuedAt;
  DateTime? modifiedAt;
  String? name;
  String? note;
  TaskRepeatRule? repeatRule;
  List<SubtaskItem> subtasks = const <SubtaskItem>[];
  bool subtasksAutoFinish = false;
  DateTime? suspendedAt;
}

/// Throws a [TdfException] with [kind] and 1-based [line] when [ok] is `false`.
void _check(bool ok, TdfErrorKind kind, int line) {
  if (!ok) {
    _fail(kind, line);
  }
}

/// Throws a [TdfException] with [kind] and 1-based [line].
Never _fail(TdfErrorKind kind, int line) =>
    TdfScanner.fail(kind, line, 'Invalid TDF (${kind.name}) at line $line.');
