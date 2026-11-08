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

import '../models/task_item.dart';
import '../models/tdf_error.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_sync_metadata.dart';
import '../models/tdf_timezone.dart';
import 'tdf_scanner.dart';

/// Mutable field accumulator for a `deleted` root block during TDF parsing.
class TdfDeletedDirectiveFields {
  /// Seen deleted label IDs (`<label-id>`).
  final Set<String> deletedLabelIds = <String>{};

  /// Seen deleted location IDs (`<location-id>`).
  final Set<String> deletedLocationIds = <String>{};

  /// Seen deleted task IDs (`<task-id>`).
  final Set<String> deletedTaskIds = <String>{};

  /// Parsed `generation` value.
  int? generation;

  /// Parsed deleted label records.
  final List<TdfDeletedLabelRecord> labels = <TdfDeletedLabelRecord>[];

  /// Parsed deleted location records.
  final List<TdfDeletedLocationRecord> locations = <TdfDeletedLocationRecord>[];

  /// Parsed deleted task records.
  final List<TdfDeletedTaskRecord> tasks = <TdfDeletedTaskRecord>[];
}

/// Mutable field accumulator for a `label` block during TDF parsing.
class TdfLabelDirectiveFields {
  /// Parsed `color` hex literal (`#RRGGBB`).
  String? color;

  /// Accumulated condition rules across all inline and block declarations.
  final List<TaskCondition> conditions = <TaskCondition>[];

  /// Legacy 0.5.x inline location condition tuples in declaration order.
  final List<TdfLegacyInlineLocationRef> legacyInlineLocations =
      <TdfLegacyInlineLocationRef>[];

  /// Raw `<location-id>` reference count across all `location` condition rules before deduplication.
  int locationRefCount = 0;

  /// Referenced `<location-id>` tokens with their source line numbers.
  final List<({String locationId, int line})> locationReferences =
      <({String locationId, int line})>[];

  /// Optional `modified` UTC timestamp.
  DateTime? modifiedAt;

  /// Parsed `name` text.
  String? name;

  /// Optional `note` text.
  String? note;
}

/// Normalized inline location rule from a legacy `0.5.0` or `0.5.1` document (`spec/TDF_SPEC_0.6.0.md` Section 10.7).
class TdfLegacyInlineLocationRef {
  /// Creates a [TdfLegacyInlineLocationRef].
  const TdfLegacyInlineLocationRef({
    required this.sourceId,
    required this.normalizedLatitude,
    required this.normalizedLongitude,
    required this.normalizedRadius,
    required this.latitude,
    required this.longitude,
    required this.radius,
    required this.line,
  });

  /// Parsed numeric latitude.
  final double latitude;

  /// 1-based line number of the rule.
  final int line;

  /// Parsed numeric longitude.
  final double longitude;

  /// Normalized decimal string for latitude (`<= 6` fractional digits).
  final String normalizedLatitude;

  /// Normalized decimal string for longitude (`<= 6` fractional digits).
  final String normalizedLongitude;

  /// Normalized decimal string for radius (`<= 2` fractional digits).
  final String normalizedRadius;

  /// Parsed numeric radius in meters.
  final double radius;

  /// Canonical deduplication key (`<normalizedLat>:<normalizedLon>:<normalizedRadius>`).
  final String sourceId;
}

/// Mutable field accumulator for a `location` block during TDF parsing.
class TdfLocationDirectiveFields {
  /// Parsed WGS-84 latitude (`[-90.0, 90.0]`).
  double? latitude;

  /// Normalized decimal string for [latitude].
  String? latitudeText;

  /// Parsed WGS-84 longitude (`[-180.0, 180.0]`).
  double? longitude;

  /// Normalized decimal string for [longitude].
  String? longitudeText;

  /// Optional `modified` UTC timestamp.
  DateTime? modifiedAt;

  /// Parsed `name` text.
  String? name;

  /// Optional `note` text.
  String? note;

  /// Parsed radius in meters (`(0.0, 100000.0]`).
  double? radius;

  /// Normalized decimal string for [radius].
  String? radiusText;

  /// Optional `source` address or location code text.
  String? source;
}

/// Mutable field accumulator for a `queue` root block during TDF parsing.
class TdfQueueDirectiveFields {
  /// Ordered `<task-id>` entries with their 1-based line numbers.
  final List<({String taskId, int line})> entries =
      <({String taskId, int line})>[];

  /// Parsed `modified` UTC timestamp.
  DateTime? modifiedAt;

  /// Seen `<task-id>` values in the queue block.
  final Set<String> seenTaskIds = <String>{};
}

/// Mutable field accumulator for a `task` block during TDF parsing.
class TdfTaskDirectiveFields {
  /// Seen `blocked` target task IDs mapped to their greatest required completion count.
  final Map<String, int> blockedByCompletions = <String, int>{};

  /// 1-based line number of the `blocked` directive when present.
  int? blockedLine;

  /// Parsed `completions` counter (`0..MAX_COMPLETIONS`).
  int? completions;

  /// Accumulated condition rules across all inline and block declarations.
  final List<TaskCondition> conditions = <TaskCondition>[];

  /// Required `created` UTC timestamp.
  DateTime? createdAt;

  /// Optional `due` UTC deadline timestamp.
  DateTime? dueAt;

  /// Optional `finished` UTC timestamp.
  DateTime? finishedAt;

  /// Whether a `blocked` directive has already been declared.
  bool hasBlockedDirective = false;

  /// Whether a `labels` directive has already been declared.
  bool hasLabelsDirective = false;

  /// Whether `suspended forever` was declared.
  bool isSuspendedForever = false;

  /// Referenced `<label-id>` values with their line numbers.
  final List<({String labelId, int line})> labelIds =
      <({String labelId, int line})>[];

  /// Legacy 0.5.x inline location condition tuples in declaration order.
  final List<TdfLegacyInlineLocationRef> legacyInlineLocations =
      <TdfLegacyInlineLocationRef>[];

  /// Repeatable `link` attachments in declaration order.
  final List<TaskLink> links = <TaskLink>[];

  /// Raw `<location-id>` reference count across all `location` condition rules before deduplication.
  int locationRefCount = 0;

  /// Referenced `<location-id>` tokens with their source line numbers.
  final List<({String locationId, int line})> locationReferences =
      <({String locationId, int line})>[];

  /// Optional `modified` UTC timestamp.
  DateTime? modifiedAt;

  /// Required `name` text.
  String? name;

  /// Optional `note` text.
  String? note;

  /// Optional `origin` correlation pair.
  TaskOrigin? origin;

  /// Optional legacy `queued` UTC timestamp (permitted only when converting `tdf 0.5.0` on load per Section 10.6).
  DateTime? queuedAt;

  /// Optional `repeat` recurrence rule.
  TaskRepeatRule? repeatRule;

  /// Optional finite `suspended` UTC timestamp.
  DateTime? suspendedAt;
}

/// Semantic directive and value parser for TDF 0.6.0 (`spec/TDF_SPEC_0.6.0.md` Sections 2.8, 4, 7, and 8).
abstract final class TdfDirectiveParser {
  /// Forbidden executable or inline-payload URI schemes (`spec/TDF_SPEC_0.6.0.md` Section 2.8).
  static const List<String> _forbiddenUriSchemes = <String>[
    'javascript:',
    'vbscript:',
    'data:',
  ];

  /// Appends a condition rule to [fields] on a `label` block, enforcing `MAX_CONDITION_RULES_PER_ENTITY` and `MAX_LOCATION_REFS_PER_ENTITY`.
  static void addConditionToLabel(
    TdfLabelDirectiveFields fields,
    String ruleType,
    List<TdfScannedToken> args,
    int line, {
    bool isLegacy05x = false,
  }) {
    if (fields.conditions.length >= maxTdfConditionRulesPerEntity) {
      fail(
        TdfErrorKind.limitExceeded,
        line,
        'Label exceeds maximum of $maxTdfConditionRulesPerEntity condition rules.',
      );
    }
    if (ruleType == 'any') {
      fail(
        TdfErrorKind.invalidCondition,
        line,
        'Global reset "any" is forbidden inside a label block.',
      );
    }
    if (args.length == 1 &&
        args[0].kind == TdfTokenKind.bareWord &&
        args[0].value == 'any') {
      fail(
        TdfErrorKind.invalidCondition,
        line,
        'Group reset "$ruleType any" is forbidden inside a label block.',
      );
    }
    if (ruleType == 'location') {
      final condition = _parseLocationRuleForEntity(
        args: args,
        line: line,
        isLegacy05x: isLegacy05x,
        currentRefCount: fields.locationRefCount,
        onUpdateRefCount: (nextCount) => fields.locationRefCount = nextCount,
        locationReferences: fields.locationReferences,
        legacyInlineLocations: fields.legacyInlineLocations,
      );
      fields.conditions.add(condition);
      return;
    }
    final condition = _parseConcreteConditionRule(ruleType, args, line);
    fields.conditions.add(condition);
  }

  /// Appends a condition rule to [fields] on a `task` block, enforcing `MAX_CONDITION_RULES_PER_ENTITY`, `MAX_LOCATION_REFS_PER_ENTITY`, and reset exclusivity.
  static void addConditionToTask(
    TdfTaskDirectiveFields fields,
    String ruleType,
    List<TdfScannedToken> args,
    int line, {
    required bool isInlineDirective,
    bool isLegacy05x = false,
  }) {
    if (fields.conditions.length >= maxTdfConditionRulesPerEntity) {
      fail(
        TdfErrorKind.limitExceeded,
        line,
        'Task exceeds maximum of $maxTdfConditionRulesPerEntity condition rules.',
      );
    }
    if (fields.conditions.any((rule) => rule is GlobalResetTaskCondition)) {
      fail(
        TdfErrorKind.invalidCondition,
        line,
        'Task with "condition any" cannot declare additional condition rules.',
      );
    }
    if (ruleType == 'any') {
      if (!isInlineDirective ||
          args.isNotEmpty ||
          fields.conditions.isNotEmpty) {
        fail(
          TdfErrorKind.invalidCondition,
          line,
          '"condition any" must be a standalone inline directive on a task.',
        );
      }
      fields.conditions.add(const GlobalResetTaskCondition());
      return;
    }
    if (args.length == 1 &&
        args[0].kind == TdfTokenKind.bareWord &&
        args[0].value == 'any') {
      final group = _conditionGroupFromName(ruleType, line);
      if (_hasConditionGroup(fields.conditions, group)) {
        fail(
          TdfErrorKind.invalidCondition,
          line,
          'Cannot combine "$ruleType any" with other "$ruleType" condition rules on the same task.',
        );
      }
      fields.conditions.add(GroupResetTaskCondition(targetGroup: group));
      return;
    }
    final group = _conditionGroupFromName(ruleType, line);
    if (_hasGroupReset(fields.conditions, group)) {
      fail(
        TdfErrorKind.invalidCondition,
        line,
        'Cannot combine "$ruleType" rule with "$ruleType any" reset on the same task.',
      );
    }
    if (ruleType == 'location') {
      final condition = _parseLocationRuleForEntity(
        args: args,
        line: line,
        isLegacy05x: isLegacy05x,
        currentRefCount: fields.locationRefCount,
        onUpdateRefCount: (nextCount) => fields.locationRefCount = nextCount,
        locationReferences: fields.locationReferences,
        legacyInlineLocations: fields.legacyInlineLocations,
      );
      fields.conditions.add(condition);
      return;
    }
    final condition = _parseConcreteConditionRule(ruleType, args, line);
    fields.conditions.add(condition);
  }

  /// Applies a directive inside a `deleted` block to [fields].
  static void applyDeletedDirective(
    TdfDeletedDirectiveFields fields,
    String directive,
    List<TdfScannedToken> args,
    int line,
  ) {
    switch (directive) {
      case 'generation':
        if (fields.generation != null) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate "generation" directive in deleted block.',
          );
        }
        fields.generation = _parseUnsignedIntWithLimit(
          args,
          line,
          TdfDeletedBlock.maxGeneration,
          'generation',
        );
      case 'task':
        _applyDeletedTaskRecord(fields, args, line);
      case 'label':
        _applyDeletedLabelRecord(fields, args, line);
      case 'location':
        _applyDeletedLocationRecord(fields, args, line);
      case _:
        fail(
          TdfErrorKind.unknownDirective,
          line,
          'Unknown directive "$directive" in deleted block.',
        );
    }
  }

  /// Applies a directive inside a `label` block to [fields].
  static void applyLabelDirective(
    TdfLabelDirectiveFields fields,
    String directive,
    List<TdfScannedToken> args,
    int line, {
    bool isLegacy05x = false,
  }) {
    switch (directive) {
      case 'name':
        if (fields.name != null) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate label "name".',
          );
        }
        fields.name = _parseQuotedText(
          args,
          line,
          maxTdfTextLength,
          allowMultiline: false,
        );
      case 'color':
        if (fields.color != null) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate label "color".',
          );
        }
        fields.color = _parseColor(args, line);
      case 'note':
        if (fields.note != null) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate label "note".',
          );
        }
        fields.note = _parseQuotedText(
          args,
          line,
          maxTdfNoteLength,
          allowMultiline: true,
        );
      case 'modified':
        if (fields.modifiedAt != null) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate label "modified".',
          );
        }
        fields.modifiedAt = parseUtcTimestamp(args, line);
      case 'condition':
        if (args.isEmpty) {
          fail(
            TdfErrorKind.missingDirectiveArgument,
            line,
            'Missing condition arguments.',
          );
        }
        final ruleTypeToken = args[0];
        if (ruleTypeToken.kind != TdfTokenKind.bareWord) {
          fail(
            TdfErrorKind.invalidIdentifier,
            line,
            'Condition rule type must not be quoted.',
          );
        }
        addConditionToLabel(
          fields,
          ruleTypeToken.value,
          args.sublist(1),
          line,
          isLegacy05x: isLegacy05x,
        );
      case _:
        fail(
          TdfErrorKind.unknownDirective,
          line,
          'Unknown label directive "$directive".',
        );
    }
  }

  /// Applies a directive inside a `location` block to [fields] (`spec/TDF_SPEC_0.6.0.md` Section 4.3).
  static void applyLocationDirective(
    TdfLocationDirectiveFields fields,
    String directive,
    List<TdfScannedToken> args,
    int line,
  ) {
    switch (directive) {
      case 'name':
        if (fields.name != null) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate location "name".',
          );
        }
        fields.name = _parseQuotedText(
          args,
          line,
          maxTdfTextLength,
          allowMultiline: false,
        );
      case 'note':
        if (fields.note != null) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate location "note".',
          );
        }
        fields.note = _parseQuotedText(
          args,
          line,
          maxTdfNoteLength,
          allowMultiline: true,
        );
      case 'source':
        if (fields.source != null) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate location "source".',
          );
        }
        fields.source = _parseQuotedText(
          args,
          line,
          maxTdfTextLength,
          allowMultiline: false,
        );
      case 'coordinates':
        if (fields.latitude != null) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate location "coordinates".',
          );
        }
        _applyLocationCoordinates(fields, args, line);
      case 'radius':
        if (fields.radius != null) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate location "radius".',
          );
        }
        _applyLocationRadius(fields, args, line);
      case 'modified':
        if (fields.modifiedAt != null) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate location "modified".',
          );
        }
        fields.modifiedAt = parseUtcTimestamp(args, line);
      case _:
        fail(
          TdfErrorKind.unknownDirective,
          line,
          'Unknown location directive "$directive".',
        );
    }
  }

  /// Applies a directive inside a `queue` block to [fields].
  static void applyQueueDirective(
    TdfQueueDirectiveFields fields,
    String directive,
    List<TdfScannedToken> args,
    int line,
  ) {
    switch (directive) {
      case 'modified':
        if (fields.modifiedAt != null) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate "modified" directive in queue block.',
          );
        }
        fields.modifiedAt = parseUtcTimestamp(args, line);
      case 'task':
        if (args.length != 1) {
          fail(
            TdfErrorKind.unexpectedToken,
            line,
            'Queue "task" directive requires exactly 1 <task-id> argument.',
          );
        }
        if (fields.entries.length >= TdfQueueBlock.maxQueueEntries) {
          fail(
            TdfErrorKind.limitExceeded,
            line,
            'Queue block exceeds maximum of ${TdfQueueBlock.maxQueueEntries} entries.',
          );
        }
        final token = args[0];
        if (token.kind != TdfTokenKind.bareWord ||
            !isValidEntityId(token.value)) {
          fail(
            TdfErrorKind.invalidIdentifier,
            line,
            'Invalid <task-id> "${token.value}" in queue block.',
          );
        }
        if (!fields.seenTaskIds.add(token.value)) {
          fail(
            TdfErrorKind.duplicateIdentifier,
            line,
            'Duplicate <task-id> "${token.value}" in queue block.',
          );
        }
        fields.entries.add((taskId: token.value, line: line));
      case _:
        fail(
          TdfErrorKind.unknownDirective,
          line,
          'Unknown directive "$directive" in queue block.',
        );
    }
  }

  /// Applies a directive inside a `task` block to [fields].
  static void applyTaskDirective(
    TdfTaskDirectiveFields fields,
    String directive,
    List<TdfScannedToken> args,
    int line, {
    bool allowLegacyQueued = false,
    bool isLegacy05x = false,
  }) {
    switch (directive) {
      case 'name':
        if (fields.name != null) {
          fail(TdfErrorKind.duplicateDirective, line, 'Duplicate task "name".');
        }
        fields.name = _parseQuotedText(
          args,
          line,
          maxTdfTextLength,
          allowMultiline: false,
        );
      case 'note':
        if (fields.note != null) {
          fail(TdfErrorKind.duplicateDirective, line, 'Duplicate task "note".');
        }
        fields.note = _parseQuotedText(
          args,
          line,
          maxTdfNoteLength,
          allowMultiline: true,
        );
      case 'created':
        if (fields.createdAt != null) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate task "created".',
          );
        }
        fields.createdAt = parseUtcTimestamp(args, line);
      case 'queued':
        if (!allowLegacyQueued) {
          fail(
            TdfErrorKind.unknownDirective,
            line,
            'Unknown task directive "queued".',
          );
        }
        if (fields.queuedAt != null) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate task "queued".',
          );
        }
        fields.queuedAt = parseUtcTimestamp(args, line);
      case 'finished':
        if (fields.finishedAt != null) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate task "finished".',
          );
        }
        fields.finishedAt = parseUtcTimestamp(args, line);
      case 'modified':
        if (fields.modifiedAt != null) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate task "modified".',
          );
        }
        fields.modifiedAt = parseUtcTimestamp(args, line);
      case 'completions':
        if (fields.completions != null) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate task "completions".',
          );
        }
        fields.completions = _parseUnsignedIntWithLimit(
          args,
          line,
          TdfTaskDependency.maxCompletions,
          'completions',
        );
      case 'suspended':
        if (fields.suspendedAt != null || fields.isSuspendedForever) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate task "suspended".',
          );
        }
        if (args.length == 1 &&
            args[0].kind == TdfTokenKind.bareWord &&
            args[0].value == 'forever') {
          fields.isSuspendedForever = true;
        } else {
          fields.suspendedAt = parseUtcTimestamp(args, line);
        }
      case 'due':
        if (fields.dueAt != null) {
          fail(TdfErrorKind.duplicateDirective, line, 'Duplicate task "due".');
        }
        fields.dueAt = parseUtcTimestamp(args, line);
      case 'origin':
        if (fields.origin != null) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate task "origin".',
          );
        }
        fields.origin = _parseTaskOrigin(args, line);
      case 'repeat':
        if (fields.repeatRule != null) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate task "repeat".',
          );
        }
        fields.repeatRule = _parseRepeatRule(args, line);
      case 'labels':
        if (fields.hasLabelsDirective) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate task "labels".',
          );
        }
        fields.hasLabelsDirective = true;
        _parseLabelRefs(args, line, fields.labelIds);
      case 'blocked':
        if (fields.hasBlockedDirective) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate task "blocked".',
          );
        }
        fields.hasBlockedDirective = true;
        fields.blockedLine = line;
        _parseBlockedDependencies(args, line, fields.blockedByCompletions);
      case 'link':
        if (fields.links.length >= TaskLink.maxLinksPerTask) {
          fail(
            TdfErrorKind.limitExceeded,
            line,
            'Task exceeds maximum of ${TaskLink.maxLinksPerTask} links.',
          );
        }
        fields.links.add(_parseTaskLink(args, line));
      case 'condition':
        if (args.isEmpty) {
          fail(
            TdfErrorKind.missingDirectiveArgument,
            line,
            'Missing condition arguments.',
          );
        }
        final ruleTypeToken = args[0];
        if (ruleTypeToken.kind != TdfTokenKind.bareWord) {
          fail(
            TdfErrorKind.invalidIdentifier,
            line,
            'Condition rule type must not be quoted.',
          );
        }
        addConditionToTask(
          fields,
          ruleTypeToken.value,
          args.sublist(1),
          line,
          isInlineDirective: true,
          isLegacy05x: isLegacy05x,
        );
      case _:
        fail(
          TdfErrorKind.unknownDirective,
          line,
          'Unknown task directive "$directive".',
        );
    }
  }

  /// Coalesces multiple [LocationTaskCondition] rules in [conditions] into a single canonical [LocationTaskCondition] in first-seen `<location-id>` order (`spec/TDF_SPEC_0.6.0.md` Section 4.4.1).
  static List<TaskCondition> coalesceLocationConditions(
    List<TaskCondition> conditions,
  ) {
    final seenLocationIds = <String>{};
    final orderedLocationIds = <String>[];
    for (final condition in conditions) {
      if (condition case final LocationTaskCondition loc) {
        _collectDistinctLocationIds(
          loc.locationIds,
          seenLocationIds,
          orderedLocationIds,
        );
      }
    }
    if (orderedLocationIds.isEmpty) {
      return conditions;
    }
    final result = <TaskCondition>[];
    var emittedLocation = false;
    for (final condition in conditions) {
      if (condition is LocationTaskCondition) {
        if (!emittedLocation) {
          result.add(LocationTaskCondition(locationIds: orderedLocationIds));
          emittedLocation = true;
        }
      } else {
        result.add(condition);
      }
    }
    return result;
  }

  /// Throws a [TdfException] with [kind], [line], and [message].
  static Never fail(TdfErrorKind kind, int line, String message) {
    throw TdfException(kind: kind, line: line, message: message);
  }

  /// Checks whether [id] is a canonical 10-character Base62 entity identifier (`[0-9A-Za-z]{10}`).
  static bool isValidEntityId(String id) => _isValidBase62EntityId(id);

  /// Parses a `step <done> "<text>"` directive inside a `subtasks` block.
  static SubtaskItem parseStepDirective(List<TdfScannedToken> args, int line) {
    if (args.length != 2) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Subtask "step" requires <done> and "<text>".',
      );
    }
    final doneToken = args[0];
    if (doneToken.kind != TdfTokenKind.bareWord ||
        (doneToken.value != 'true' && doneToken.value != 'false')) {
      fail(
        TdfErrorKind.invalidBoolean,
        line,
        'Subtask <done> must be unquoted true or false.',
      );
    }
    final title = _parseQuotedText(
      [args[1]],
      line,
      maxTdfTextLength,
      allowMultiline: false,
    );
    return SubtaskItem(title: title, isCompleted: doneToken.value == 'true');
  }

  /// Parses `<YYYY-MM-DD> [<HH:MM[:SS]>]` into a UTC [DateTime] (`0001-01-01 00:00:00`..`9999-12-31 23:59:59`).
  static DateTime parseUtcTimestamp(List<TdfScannedToken> args, int line) {
    if (args.isEmpty || args.length > 2) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Invalid timestamp argument count.',
      );
    }
    if (args.any((token) => token.kind != TdfTokenKind.bareWord)) {
      fail(
        TdfErrorKind.invalidTimestamp,
        line,
        'Timestamp tokens must not be quoted.',
      );
    }
    final datePart = args[0].value;
    if (datePart.length != 10 ||
        datePart.codeUnitAt(4) != 0x2D ||
        datePart.codeUnitAt(7) != 0x2D) {
      fail(
        TdfErrorKind.invalidTimestamp,
        line,
        'Invalid date "$datePart": expected YYYY-MM-DD.',
      );
    }
    final year = _parseFixedDigits(datePart, 0, 4);
    final month = _parseFixedDigits(datePart, 5, 2);
    final day = _parseFixedDigits(datePart, 8, 2);
    if (year == null ||
        month == null ||
        day == null ||
        !TdfCalendar.isValidGregorianDate(year, month, day)) {
      fail(
        TdfErrorKind.invalidTimestamp,
        line,
        'Invalid calendar date "$datePart".',
      );
    }
    var hour = 0;
    var minute = 0;
    var second = 0;
    if (args.length == 2) {
      final timePart = args[1].value;
      final parsedClock = TdfRepeatClock.tryParse(timePart);
      if (parsedClock == null) {
        fail(
          TdfErrorKind.invalidTimestamp,
          line,
          'Invalid time "$timePart": expected HH:MM or HH:MM:SS.',
        );
      }
      hour = parsedClock.hour;
      minute = parsedClock.minute;
      second = parsedClock.second;
    }
    return DateTime.utc(year, month, day, hour, minute, second);
  }

  /// Parses a `label <label-id> <timestamp>` deletion record inside `deleted`.
  static void _applyDeletedLabelRecord(
    TdfDeletedDirectiveFields fields,
    List<TdfScannedToken> args,
    int line,
  ) {
    if (fields.tasks.length + fields.labels.length + fields.locations.length >=
        TdfDeletedBlock.maxDeletedRecords) {
      fail(
        TdfErrorKind.limitExceeded,
        line,
        'Deleted block exceeds maximum of ${TdfDeletedBlock.maxDeletedRecords} records.',
      );
    }
    if (args.length < 2 || args.length > 3) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Deleted label record requires <label-id> and <timestamp>.',
      );
    }
    if (args.length == 3 && !args[2].value.contains(':')) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Deleted label record forbids a completion checkpoint.',
      );
    }
    final idToken = args[0];
    if (idToken.kind != TdfTokenKind.bareWord ||
        !isValidEntityId(idToken.value)) {
      fail(
        TdfErrorKind.invalidIdentifier,
        line,
        'Invalid <label-id> "${idToken.value}" in deleted block.',
      );
    }
    if (!fields.deletedLabelIds.add(idToken.value)) {
      fail(
        TdfErrorKind.duplicateIdentifier,
        line,
        'Duplicate deleted label ID "${idToken.value}".',
      );
    }
    final deletedAt = parseUtcTimestamp(args.sublist(1), line);
    fields.labels.add(
      TdfDeletedLabelRecord(labelId: idToken.value, deletedAt: deletedAt),
    );
  }

  /// Parses a `location <location-id> <timestamp>` deletion record inside `deleted` (`spec/TDF_SPEC_0.6.0.md` Section 4.5).
  static void _applyDeletedLocationRecord(
    TdfDeletedDirectiveFields fields,
    List<TdfScannedToken> args,
    int line,
  ) {
    if (fields.tasks.length + fields.labels.length + fields.locations.length >=
        TdfDeletedBlock.maxDeletedRecords) {
      fail(
        TdfErrorKind.limitExceeded,
        line,
        'Deleted block exceeds maximum of ${TdfDeletedBlock.maxDeletedRecords} records.',
      );
    }
    if (args.length < 2 || args.length > 3) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Deleted location record requires <location-id> and <timestamp>.',
      );
    }
    if (args.length == 3 && !args[2].value.contains(':')) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Deleted location record forbids a completion checkpoint.',
      );
    }
    final idToken = args[0];
    if (idToken.kind != TdfTokenKind.bareWord ||
        !isValidEntityId(idToken.value)) {
      fail(
        TdfErrorKind.invalidIdentifier,
        line,
        'Invalid <location-id> "${idToken.value}" in deleted block.',
      );
    }
    if (!fields.deletedLocationIds.add(idToken.value)) {
      fail(
        TdfErrorKind.duplicateIdentifier,
        line,
        'Duplicate deleted location ID "${idToken.value}".',
      );
    }
    final deletedAt = parseUtcTimestamp(args.sublist(1), line);
    fields.locations.add(
      TdfDeletedLocationRecord(locationId: idToken.value, deletedAt: deletedAt),
    );
  }

  /// Parses a `task <task-id> <timestamp> [<completion-count>]` deletion record inside `deleted`.
  static void _applyDeletedTaskRecord(
    TdfDeletedDirectiveFields fields,
    List<TdfScannedToken> args,
    int line,
  ) {
    if (fields.tasks.length + fields.labels.length + fields.locations.length >=
        TdfDeletedBlock.maxDeletedRecords) {
      fail(
        TdfErrorKind.limitExceeded,
        line,
        'Deleted block exceeds maximum of ${TdfDeletedBlock.maxDeletedRecords} records.',
      );
    }
    if (args.length < 2 || args.length > 4) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Invalid deleted task record argument count.',
      );
    }
    final idToken = args[0];
    if (idToken.kind != TdfTokenKind.bareWord ||
        !isValidEntityId(idToken.value)) {
      fail(
        TdfErrorKind.invalidIdentifier,
        line,
        'Invalid <task-id> "${idToken.value}" in deleted block.',
      );
    }
    if (!fields.deletedTaskIds.add(idToken.value)) {
      fail(
        TdfErrorKind.duplicateIdentifier,
        line,
        'Duplicate deleted task ID "${idToken.value}".',
      );
    }
    var timestampArgCount = 1;
    if (args.length >= 3 && args[2].value.contains(':')) {
      timestampArgCount = 2;
    }
    final timestampArgs = args.sublist(1, 1 + timestampArgCount);
    final remainingArgs = args.sublist(1 + timestampArgCount);
    if (remainingArgs.length > 1) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Extra trailing arguments in deleted task record.',
      );
    }
    final deletedAt = parseUtcTimestamp(timestampArgs, line);
    var checkpoint = 0;
    if (remainingArgs.length == 1) {
      checkpoint = _parseUnsignedIntWithLimit(
        remainingArgs,
        line,
        TdfTaskDependency.maxCompletions,
        'completion checkpoint',
      );
    }
    fields.tasks.add(
      TdfDeletedTaskRecord(
        taskId: idToken.value,
        deletedAt: deletedAt,
        completionsCheckpoint: checkpoint,
      ),
    );
  }

  /// Validates and applies `coordinates <lat> <lon>` inside a `location` block (`spec/TDF_SPEC_0.6.0.md` Section 4.3).
  static void _applyLocationCoordinates(
    TdfLocationDirectiveFields fields,
    List<TdfScannedToken> args,
    int line,
  ) {
    if (args.length != 2 ||
        args.any((token) => token.kind != TdfTokenKind.bareWord)) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Location "coordinates" requires 2 unquoted decimal numbers (<lat> <lon>).',
      );
    }
    final parsedLat = _parseStrictDecimalToken(
      args[0].value,
      line,
      maxDecimals: 6,
      min: -90.0,
      max: 90.0,
      strictlyPositive: false,
    );
    final parsedLon = _parseStrictDecimalToken(
      args[1].value,
      line,
      maxDecimals: 6,
      min: -180.0,
      max: 180.0,
      strictlyPositive: false,
    );
    fields.latitude = parsedLat.value;
    fields.latitudeText = parsedLat.normalizedText;
    fields.longitude = parsedLon.value;
    fields.longitudeText = parsedLon.normalizedText;
  }

  /// Validates and applies `radius <meters>` inside a `location` block (`spec/TDF_SPEC_0.6.0.md` Section 4.3).
  static void _applyLocationRadius(
    TdfLocationDirectiveFields fields,
    List<TdfScannedToken> args,
    int line,
  ) {
    if (args.length != 1 || args[0].kind != TdfTokenKind.bareWord) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Location "radius" requires 1 unquoted decimal number (<meters>).',
      );
    }
    final parsedRadius = _parseStrictDecimalToken(
      args[0].value,
      line,
      maxDecimals: 2,
      min: 0.0,
      max: maxTdfLocationRadius.toDouble(),
      strictlyPositive: true,
      maxExceedsIsLimitExceeded: true,
    );
    fields.radius = parsedRadius.value;
    fields.radiusText = parsedRadius.normalizedText;
  }

  /// Appends unseen `<location-id>` values from [source] into [ordered] using [seen].
  static void _collectDistinctLocationIds(
    List<String> source,
    Set<String> seen,
    List<String> ordered,
  ) {
    for (final id in source) {
      if (seen.add(id)) {
        ordered.add(id);
      }
    }
  }

  /// Maps a condition rule type name (`day`, `time`, `location`) to [ConditionGroup].
  static ConditionGroup _conditionGroupFromName(String ruleType, int line) =>
      switch (ruleType) {
        'day' => ConditionGroup.day,
        'time' => ConditionGroup.time,
        'location' => ConditionGroup.location,
        _ => fail(
          TdfErrorKind.unknownDirective,
          line,
          'Unknown condition type "$ruleType".',
        ),
      };

  /// Checks whether [conditions] already contains a concrete rule for [group].
  static bool _hasConditionGroup(
    List<TaskCondition> conditions,
    ConditionGroup group,
  ) => conditions.any(
    (rule) => rule is! GroupResetTaskCondition && rule.group == group,
  );

  /// Checks whether [conditions] already contains a `<type> any` reset for [group].
  static bool _hasGroupReset(
    List<TaskCondition> conditions,
    ConditionGroup group,
  ) => conditions.any(
    (rule) => rule is GroupResetTaskCondition && rule.targetGroup == group,
  );

  /// Checks whether [value] contains at least one character other than ASCII whitespace (`0x20`, `\t`, `\n`, `\r`).
  static bool _hasNonAsciiWhitespaceContent(String value) {
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit != 0x20 && unit != 0x09 && unit != 0x0A && unit != 0x0D) {
        return true;
      }
    }
    return false;
  }

  /// Checks whether all characters in [source] within `[start, end)` are ASCII decimal digits (`[0-9]`).
  static bool _hasOnlyAsciiDigits(String source, int start, int end) {
    for (var i = start; i < end; i++) {
      if (!_isAsciiDigit(source.codeUnitAt(i))) {
        return false;
      }
    }
    return true;
  }

  /// Checks whether [uri] begins with a valid RFC 3986 URI scheme prefix (`[a-zA-Z][a-zA-Z0-9+.-]*:`).
  static bool _hasValidUriSchemePrefix(String uri) {
    final colonIndex = uri.indexOf(':');
    if (colonIndex <= 0 || !_isAsciiAlpha(uri.codeUnitAt(0))) {
      return false;
    }
    for (var i = 1; i < colonIndex; i++) {
      if (!_isUriSchemeChar(uri.codeUnitAt(i))) {
        return false;
      }
    }
    return true;
  }

  /// Checks whether [unit] is an ASCII letter (`[A-Za-z]`).
  static bool _isAsciiAlpha(int unit) =>
      (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);

  /// Checks whether [unit] is an ASCII decimal digit (`[0-9]`).
  static bool _isAsciiDigit(int unit) => unit >= 0x30 && unit <= 0x39;

  /// Checks whether [unit] is a valid RFC 3986 URI scheme continuation character (`[a-zA-Z0-9+.-]`).
  static bool _isUriSchemeChar(int unit) =>
      _isAsciiAlpha(unit) ||
      _isAsciiDigit(unit) ||
      unit == 0x2B ||
      unit == 0x2D ||
      unit == 0x2E;

  /// Checks whether [id] is a canonical 10-character Base62 entity identifier (`[0-9A-Za-z]{10}`).
  static bool _isValidBase62EntityId(String id) {
    if (id.length != tdfEntityIdLength) {
      return false;
    }
    for (var i = 0; i < tdfEntityIdLength; i++) {
      final unit = id.codeUnitAt(i);
      if (!_isAsciiAlpha(unit) && !_isAsciiDigit(unit)) {
        return false;
      }
    }
    return true;
  }

  /// Checks whether [raw] matches a finite ASCII decimal number (`-?[0-9]+(\.[0-9]+)?`).
  static bool _isValidDecimalNumber(String raw) {
    if (raw.isEmpty) {
      return false;
    }
    final start = raw.codeUnitAt(0) == 0x2D ? 1 : 0;
    if (start >= raw.length) {
      return false;
    }
    final dotIndex = raw.indexOf('.', start);
    if (dotIndex == -1) {
      return _hasOnlyAsciiDigits(raw, start, raw.length);
    }
    if (dotIndex == start || dotIndex == raw.length - 1) {
      return false;
    }
    return _hasOnlyAsciiDigits(raw, start, dotIndex) &&
        _hasOnlyAsciiDigits(raw, dotIndex + 1, raw.length);
  }

  /// Checks whether [value] is a valid `#RRGGBB` hex color string (`^#[0-9a-fA-F]{6}$`).
  static bool _isValidHexColor(String value) {
    if (value.length != 7 || value.codeUnitAt(0) != 0x23) {
      return false;
    }
    for (var i = 1; i < 7; i++) {
      final unit = value.codeUnitAt(i);
      final isHex =
          _isAsciiDigit(unit) ||
          (unit >= 0x41 && unit <= 0x46) ||
          (unit >= 0x61 && unit <= 0x66);
      if (!isHex) {
        return false;
      }
    }
    return true;
  }

  /// Normalizes a validated ASCII decimal string (`-?[0-9]+(\.[0-9]+)?`) per Section 6.7.3 (`-0.0` -> `0`, strip redundant leading/trailing zeros).
  static String _normalizeValidatedDecimalString(String raw) {
    var isNegative = false;
    var digits = raw;
    if (digits.startsWith('-')) {
      isNegative = true;
      digits = digits.substring(1);
    }
    final dotIndex = digits.indexOf('.');
    var intPart = dotIndex == -1 ? digits : digits.substring(0, dotIndex);
    var fracPart = dotIndex == -1 ? '' : digits.substring(dotIndex + 1);

    var intStart = 0;
    while (intStart < intPart.length - 1 &&
        intPart.codeUnitAt(intStart) == 0x30) {
      intStart++;
    }
    intPart = intPart.substring(intStart);

    var fracEnd = fracPart.length;
    while (fracEnd > 0 && fracPart.codeUnitAt(fracEnd - 1) == 0x30) {
      fracEnd--;
    }
    fracPart = fracPart.substring(0, fracEnd);

    if (intPart == '0' && fracPart.isEmpty) {
      return '0';
    }
    final signPrefix = isNegative ? '-' : '';
    return fracPart.isEmpty
        ? '$signPrefix$intPart'
        : '$signPrefix$intPart.$fracPart';
  }

  /// Parses `blocked <task-id>[:<count>] ...` arguments, retaining the greatest `<count>` for duplicate target IDs.
  static void _parseBlockedDependencies(
    List<TdfScannedToken> args,
    int line,
    Map<String, int> targetMap,
  ) {
    for (final token in args) {
      if (token.kind != TdfTokenKind.bareWord) {
        fail(
          TdfErrorKind.invalidIdentifier,
          line,
          'Prerequisite token must not be quoted.',
        );
      }
      final raw = token.value;
      final colonIdx = raw.indexOf(':');
      final String targetId;
      var requiredCount = 1;
      if (colonIdx == -1) {
        targetId = raw;
      } else {
        targetId = raw.substring(0, colonIdx);
        final countStr = raw.substring(colonIdx + 1);
        if (countStr.isEmpty || countStr.contains(':')) {
          fail(
            TdfErrorKind.invalidNumber,
            line,
            'Invalid prerequisite count in "$raw".',
          );
        }
        requiredCount = _parsePositiveIntToken(
          countStr,
          line,
          TdfTaskDependency.maxCompletions,
          'prerequisite count',
        );
      }
      if (!isValidEntityId(targetId)) {
        fail(
          TdfErrorKind.invalidIdentifier,
          line,
          'Invalid prerequisite <task-id> "$targetId".',
        );
      }
      final existing = targetMap[targetId];
      if (existing == null || requiredCount > existing) {
        targetMap[targetId] = requiredCount;
      }
    }
  }

  /// Parses and validates a `"#RRGGBB"` color argument.
  static String _parseColor(List<TdfScannedToken> args, int line) {
    if (args.length != 1 || args[0].kind != TdfTokenKind.quotedString) {
      fail(
        TdfErrorKind.invalidColor,
        line,
        'Label "color" must be a single quoted "#RRGGBB" string.',
      );
    }
    final value = args[0].value;
    if (!_isValidHexColor(value)) {
      fail(
        TdfErrorKind.invalidColor,
        line,
        'Invalid hex color "$value": expected "#RRGGBB".',
      );
    }
    return value;
  }

  /// Parses a concrete `day` or `time` condition rule.
  static TaskCondition _parseConcreteConditionRule(
    String ruleType,
    List<TdfScannedToken> args,
    int line,
  ) => switch (ruleType) {
    'day' => _parseDayRuleArgs(args, line),
    'time' => _parseTimeRuleArgs(args, line),
    _ => fail(
      TdfErrorKind.unknownDirective,
      line,
      'Unknown condition type "$ruleType".',
    ),
  };

  /// Parses `day <d1> [<d2> ...]`.
  static DayTaskCondition _parseDayRuleArgs(
    List<TdfScannedToken> args,
    int line,
  ) {
    if (args.isEmpty) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Condition "day" requires at least one weekday.',
      );
    }
    final weekdays = <int>[];
    final dayTokens = <String>[];
    for (final token in args) {
      if (token.kind != TdfTokenKind.bareWord) {
        fail(
          TdfErrorKind.invalidCondition,
          line,
          'Weekday token must not be quoted.',
        );
      }
      final weekday = DayTaskCondition.parseWeekdayToken(token.value);
      if (weekday == null) {
        fail(
          TdfErrorKind.invalidCondition,
          line,
          'Invalid weekday "${token.value}".',
        );
      }
      if (!weekdays.contains(weekday)) {
        weekdays.add(weekday);
        dayTokens.add(token.value);
      }
    }
    return DayTaskCondition(weekdays: weekdays, dayTokens: dayTokens);
  }

  /// Parses [length] ASCII decimal digits starting at [offset] in [source], or returns `null`.
  static int? _parseFixedDigits(String source, int offset, int length) {
    var result = 0;
    for (var i = 0; i < length; i++) {
      final unit = source.codeUnitAt(offset + i);
      if (unit < 0x30 || unit > 0x39) {
        return null;
      }
      result = result * 10 + (unit - 0x30);
    }
    return result;
  }

  /// Parses `labels <id1> [<id2> ...]` arguments.
  static void _parseLabelRefs(
    List<TdfScannedToken> args,
    int line,
    List<({String labelId, int line})> target,
  ) {
    for (final token in args) {
      if (token.kind != TdfTokenKind.bareWord ||
          !isValidEntityId(token.value)) {
        fail(
          TdfErrorKind.invalidIdentifier,
          line,
          'Invalid <label-id> "${token.value}".',
        );
      }
      target.add((labelId: token.value, line: line));
    }
  }

  /// Parses a legacy `0.5.0`/`0.5.1` inline `location <lat> <lon> <radius>` condition rule (`spec/TDF_SPEC_0.6.0.md` Section 10.7).
  static LocationTaskCondition _parseLegacyInlineLocationRule({
    required List<TdfScannedToken> args,
    required int line,
    required int currentRefCount,
    required void Function(int) onUpdateRefCount,
    required List<TdfLegacyInlineLocationRef> legacyInlineLocations,
  }) {
    if (args.length != 3 ||
        args.any((token) => token.kind != TdfTokenKind.bareWord)) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Legacy 0.5.x condition "location" requires <latitude> <longitude> <radius>.',
      );
    }
    if (currentRefCount >= maxTdfLocationRefsPerEntity) {
      fail(
        TdfErrorKind.limitExceeded,
        line,
        'Entity exceeds maximum of $maxTdfLocationRefsPerEntity location references.',
      );
    }
    onUpdateRefCount(currentRefCount + 1);

    final rawLat = args[0].value;
    final rawLon = args[1].value;
    final rawRadius = args[2].value;

    final parsedLat = _parseLegacyRoundedDecimalToken(
      rawLat,
      line,
      maxDecimals: 6,
      min: -90.0,
      max: 90.0,
      strictlyPositive: false,
    );
    final parsedLon = _parseLegacyRoundedDecimalToken(
      rawLon,
      line,
      maxDecimals: 6,
      min: -180.0,
      max: 180.0,
      strictlyPositive: false,
    );
    final parsedRadius = _parseLegacyRoundedDecimalToken(
      rawRadius,
      line,
      maxDecimals: 2,
      min: 0.0,
      max: maxTdfLocationRadius.toDouble(),
      strictlyPositive: true,
      maxExceedsIsLimitExceeded: true,
    );
    final sourceId =
        '${parsedLat.normalizedText}:${parsedLon.normalizedText}:${parsedRadius.normalizedText}';
    legacyInlineLocations.add(
      TdfLegacyInlineLocationRef(
        sourceId: sourceId,
        normalizedLatitude: parsedLat.normalizedText,
        normalizedLongitude: parsedLon.normalizedText,
        normalizedRadius: parsedRadius.normalizedText,
        latitude: parsedLat.value,
        longitude: parsedLon.value,
        radius: parsedRadius.value,
        line: line,
      ),
    );
    return LocationTaskCondition(locationIds: <String>[sourceId]);
  }

  /// Parses and rounds a legacy `0.5.x` decimal token using exact `half-away-from-zero` decimal rounding per Section 10.7.
  static ({double value, String normalizedText})
  _parseLegacyRoundedDecimalToken(
    String raw,
    int line, {
    required int maxDecimals,
    required double min,
    required double max,
    required bool strictlyPositive,
    bool maxExceedsIsLimitExceeded = false,
  }) {
    if (raw.length > maxTdfNumberLength) {
      fail(
        TdfErrorKind.limitExceeded,
        line,
        'Number token exceeds maximum length of $maxTdfNumberLength characters.',
      );
    }
    if (!_isValidDecimalNumber(raw)) {
      fail(TdfErrorKind.invalidNumber, line, 'Invalid decimal number "$raw".');
    }
    final rawDouble = double.tryParse(raw);
    if (rawDouble == null || !rawDouble.isFinite) {
      fail(TdfErrorKind.invalidNumber, line, 'Non-finite number "$raw".');
    }
    if (strictlyPositive ? rawDouble <= min : rawDouble < min) {
      fail(
        TdfErrorKind.invalidNumber,
        line,
        'Number "$raw" is below minimum $min.',
      );
    }
    if (rawDouble > max) {
      fail(
        maxExceedsIsLimitExceeded
            ? TdfErrorKind.limitExceeded
            : TdfErrorKind.invalidNumber,
        line,
        'Number "$raw" exceeds maximum $max.',
      );
    }
    final normalizedText = _roundDecimalTokenHalfAwayFromZero(raw, maxDecimals);
    final roundedDouble = double.parse(normalizedText);
    if (strictlyPositive && roundedDouble <= 0.0) {
      fail(
        TdfErrorKind.invalidNumber,
        line,
        'Rounded number "$normalizedText" must be strictly positive.',
      );
    }
    return (
      value: roundedDouble == 0.0 ? 0.0 : roundedDouble,
      normalizedText: normalizedText,
    );
  }

  /// Parses `location <loc-1> [<loc-2> ...]` in `0.6.0` or inline `location <lat> <lon> <radius>` in `0.5.x`.
  static LocationTaskCondition _parseLocationRuleForEntity({
    required List<TdfScannedToken> args,
    required int line,
    required bool isLegacy05x,
    required int currentRefCount,
    required void Function(int) onUpdateRefCount,
    required List<({String locationId, int line})> locationReferences,
    required List<TdfLegacyInlineLocationRef> legacyInlineLocations,
  }) {
    if (isLegacy05x) {
      return _parseLegacyInlineLocationRule(
        args: args,
        line: line,
        currentRefCount: currentRefCount,
        onUpdateRefCount: onUpdateRefCount,
        legacyInlineLocations: legacyInlineLocations,
      );
    }
    if (args.isEmpty) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Condition "location" requires at least 1 <location-id> argument.',
      );
    }
    var refCount = currentRefCount;
    final ids = <String>[];
    for (final token in args) {
      if (token.kind != TdfTokenKind.bareWord ||
          !isValidEntityId(token.value)) {
        fail(
          TdfErrorKind.invalidIdentifier,
          line,
          'Invalid <location-id> "${token.value}" in location condition rule.',
        );
      }
      if (refCount >= maxTdfLocationRefsPerEntity) {
        fail(
          TdfErrorKind.limitExceeded,
          line,
          'Entity exceeds maximum of $maxTdfLocationRefsPerEntity location references.',
        );
      }
      refCount++;
      locationReferences.add((locationId: token.value, line: line));
      if (!ids.contains(token.value)) {
        ids.add(token.value);
      }
    }
    onUpdateRefCount(refCount);
    return LocationTaskCondition(locationIds: ids);
  }

  /// Parses `<HH:MM>` into minutes from midnight (`0..1439`).
  static int _parseMinutesOfDay(TdfScannedToken token, int line) {
    if (token.kind != TdfTokenKind.bareWord) {
      fail(
        TdfErrorKind.invalidTimestamp,
        line,
        'Time window token must not be quoted.',
      );
    }
    final raw = token.value;
    if (raw.length != 5 || raw.codeUnitAt(2) != 0x3A) {
      fail(
        TdfErrorKind.invalidTimestamp,
        line,
        'Invalid time window token "$raw": expected HH:MM.',
      );
    }
    final hour = _parseFixedDigits(raw, 0, 2);
    final minute = _parseFixedDigits(raw, 3, 2);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      fail(
        TdfErrorKind.invalidTimestamp,
        line,
        'Time window "$raw" is out of 00:00..23:59 range.',
      );
    }
    return hour * 60 + minute;
  }

  /// Parses a canonical positive integer token (`[1-9][0-9]*`) within `1..maxLimit`.
  static int _parsePositiveIntToken(
    String raw,
    int line,
    int maxLimit,
    String label,
  ) {
    if (raw.length > maxTdfNumberLength) {
      fail(
        TdfErrorKind.limitExceeded,
        line,
        'Invalid $label "$raw": exceeds $maxTdfNumberLength characters.',
      );
    }
    if (raw.isEmpty || raw.codeUnitAt(0) < 0x31 || raw.codeUnitAt(0) > 0x39) {
      fail(
        TdfErrorKind.invalidNumber,
        line,
        'Invalid $label "$raw": expected positive integer without leading zeros.',
      );
    }
    for (var i = 1; i < raw.length; i++) {
      final unit = raw.codeUnitAt(i);
      if (unit < 0x30 || unit > 0x39) {
        fail(
          TdfErrorKind.invalidNumber,
          line,
          'Invalid $label "$raw": non-digit character.',
        );
      }
    }
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed > maxLimit) {
      fail(
        TdfErrorKind.limitExceeded,
        line,
        '$label "$raw" exceeds maximum of $maxLimit.',
      );
    }
    return parsed;
  }

  /// Parses and validates a single quoted `<text>` or `<note>` argument using Unicode scalar value length (`spec/TDF_SPEC_0.6.0.md` Section 2.8).
  static String _parseQuotedText(
    List<TdfScannedToken> args,
    int line,
    int maxScalars, {
    required bool allowMultiline,
  }) {
    if (args.length != 1 || args[0].kind != TdfTokenKind.quotedString) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Expected a single quoted string argument.',
      );
    }
    return _validateDecodedText(
      args[0].value,
      line,
      maxScalars,
      allowMultiline: allowMultiline,
    );
  }

  /// Parses `repeat <count> <days|weeks|months> [<repeat-time>]`.
  static TaskRepeatRule _parseRepeatRule(List<TdfScannedToken> args, int line) {
    if (args.length < 2 || args.length > 3) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Directive "repeat" requires <count> <unit> [<repeat-time>].',
      );
    }
    if (args[0].kind != TdfTokenKind.bareWord) {
      fail(
        TdfErrorKind.invalidNumber,
        line,
        'Repeat <count> must not be quoted.',
      );
    }
    final count = _parsePositiveIntToken(
      args[0].value,
      line,
      TaskRepeatRule.maxRepeatCount,
      'repeat count',
    );
    if (args[1].kind != TdfTokenKind.bareWord) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Repeat <unit> must not be quoted.',
      );
    }
    final unit = RepeatUnit.tryParseToken(args[1].value);
    if (unit == null) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Invalid repeat unit "${args[1].value}".',
      );
    }
    var clock = TdfRepeatClock.midnight;
    if (args.length == 3) {
      final clockToken = args[2];
      if (clockToken.kind != TdfTokenKind.bareWord) {
        fail(
          TdfErrorKind.invalidTime,
          line,
          'Repeat <repeat-time> must not be quoted.',
        );
      }
      final parsedClock = TdfRepeatClock.tryParse(clockToken.value);
      if (parsedClock == null) {
        fail(
          TdfErrorKind.invalidTime,
          line,
          'Invalid <repeat-time> "${clockToken.value}".',
        );
      }
      clock = parsedClock;
    }
    return TaskRepeatRule(count: count, unit: unit, clock: clock);
  }

  /// Parses and validates a native `0.6.0` decimal `<number>` token (`spec/TDF_SPEC_0.6.0.md` Section 4.3).
  static ({double value, String normalizedText}) _parseStrictDecimalToken(
    String raw,
    int line, {
    required int maxDecimals,
    required double min,
    required double max,
    required bool strictlyPositive,
    bool maxExceedsIsLimitExceeded = false,
  }) {
    if (raw.length > maxTdfNumberLength) {
      fail(
        TdfErrorKind.limitExceeded,
        line,
        'Number token exceeds maximum length of $maxTdfNumberLength characters.',
      );
    }
    if (!_isValidDecimalNumber(raw)) {
      fail(TdfErrorKind.invalidNumber, line, 'Invalid decimal number "$raw".');
    }
    final normalizedText = _normalizeValidatedDecimalString(raw);
    final dotIndex = normalizedText.indexOf('.');
    final significantDecimals = dotIndex == -1
        ? 0
        : normalizedText.length - dotIndex - 1;
    if (significantDecimals > maxDecimals) {
      fail(
        TdfErrorKind.invalidNumber,
        line,
        'Decimal number "$raw" exceeds maximum of $maxDecimals fractional digits.',
      );
    }
    final value = double.tryParse(normalizedText);
    if (value == null || !value.isFinite) {
      fail(TdfErrorKind.invalidNumber, line, 'Non-finite number "$raw".');
    }
    if (strictlyPositive ? value <= min : value < min) {
      fail(
        TdfErrorKind.invalidNumber,
        line,
        'Number "$raw" is below minimum $min.',
      );
    }
    if (value > max) {
      fail(
        maxExceedsIsLimitExceeded
            ? TdfErrorKind.limitExceeded
            : TdfErrorKind.invalidNumber,
        line,
        'Number "$raw" exceeds maximum $max.',
      );
    }
    return (value: value == 0.0 ? 0.0 : value, normalizedText: normalizedText);
  }

  /// Parses `link "<title>" "<uri>"` inside a `task` block (`spec/TDF_SPEC_0.6.0.md` Section 2.8 & 4.1.2).
  static TaskLink _parseTaskLink(List<TdfScannedToken> args, int line) {
    if (args.length != 2 ||
        args[0].kind != TdfTokenKind.quotedString ||
        args[1].kind != TdfTokenKind.quotedString) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Task "link" requires 2 quoted arguments ("<title>" "<uri>").',
      );
    }
    final title = _validateDecodedText(
      args[0].value,
      line,
      maxTdfTextLength,
      allowMultiline: false,
    );
    final uri = args[1].value;
    if (!_hasNonAsciiWhitespaceContent(uri)) {
      fail(
        TdfErrorKind.emptyText,
        line,
        'Link <uri> cannot be empty or ASCII whitespace only.',
      );
    }
    final scalarCount = TdfCalendar.countUnicodeScalars(uri);
    if (scalarCount == null || scalarCount > TaskLink.maxUriLength) {
      fail(
        TdfErrorKind.limitExceeded,
        line,
        'Link <uri> exceeds maximum of ${TaskLink.maxUriLength} Unicode scalar values.',
      );
    }
    for (var i = 0; i < uri.length; i++) {
      final unit = uri.codeUnitAt(i);
      if (unit < 0x20 || unit == 0x7F) {
        fail(
          TdfErrorKind.invalidUri,
          line,
          'Link <uri> cannot contain control characters.',
        );
      }
    }
    if (!_hasValidUriSchemePrefix(uri)) {
      fail(
        TdfErrorKind.invalidUri,
        line,
        'Link <uri> "$uri" lacks a valid URI scheme.',
      );
    }
    final lowerUri = uri.toLowerCase();
    for (final forbidden in _forbiddenUriSchemes) {
      if (lowerUri.startsWith(forbidden)) {
        fail(
          TdfErrorKind.invalidUri,
          line,
          'Link <uri> "$uri" uses forbidden scheme "$forbidden".',
        );
      }
    }
    return TaskLink(title: title, uri: uri);
  }

  /// Parses `origin "<namespace>" "<external-key>"` inside a `task` block (`spec/TDF_SPEC_0.6.0.md` Section 4.1.2).
  static TaskOrigin _parseTaskOrigin(List<TdfScannedToken> args, int line) {
    if (args.length != 2 ||
        args[0].kind != TdfTokenKind.quotedString ||
        args[1].kind != TdfTokenKind.quotedString) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Task "origin" requires 2 quoted arguments ("<namespace>" "<external-key>").',
      );
    }
    final namespace = _validateDecodedText(
      args[0].value,
      line,
      maxTdfTextLength,
      allowMultiline: false,
    );
    final externalKey = _validateDecodedText(
      args[1].value,
      line,
      maxTdfTextLength,
      allowMultiline: false,
    );
    return TaskOrigin(namespace: namespace, externalKey: externalKey);
  }

  /// Parses `time <start> <end>`.
  static TimeWindowTaskCondition _parseTimeRuleArgs(
    List<TdfScannedToken> args,
    int line,
  ) {
    if (args.length != 2) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Condition "time" requires <start> and <end>.',
      );
    }
    final startMinutes = _parseMinutesOfDay(args[0], line);
    final endMinutes = _parseMinutesOfDay(args[1], line);
    if (startMinutes == endMinutes) {
      fail(
        TdfErrorKind.invalidCondition,
        line,
        'Condition "time" start and end cannot be equal.',
      );
    }
    return TimeWindowTaskCondition(
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      startToken: args[0].value,
      endToken: args[1].value,
    );
  }

  /// Parses a single canonical non-negative integer argument (`0|[1-9][0-9]*`) within `0..maxLimit`.
  static int _parseUnsignedIntWithLimit(
    List<TdfScannedToken> args,
    int line,
    int maxLimit,
    String label,
  ) {
    if (args.length != 1) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        '$label requires exactly 1 integer argument.',
      );
    }
    final token = args[0];
    if (token.kind != TdfTokenKind.bareWord) {
      fail(
        TdfErrorKind.invalidNumber,
        line,
        '$label argument must not be quoted.',
      );
    }
    final raw = token.value;
    if (raw.length > maxTdfNumberLength) {
      fail(
        TdfErrorKind.limitExceeded,
        line,
        '$label "$raw" exceeds maximum length of $maxTdfNumberLength characters.',
      );
    }
    if (raw == '0') {
      return 0;
    }
    return _parsePositiveIntToken(raw, line, maxLimit, label);
  }

  /// Rounds a validated ASCII decimal string (`-?[0-9]+(\.[0-9]+)?`) to at most [maxDecimals] fractional digits using exact `half-away-from-zero` rounding and normalizes the result (`spec/TDF_SPEC_0.6.0.md` Section 10.7).
  static String _roundDecimalTokenHalfAwayFromZero(
    String raw,
    int maxDecimals,
  ) {
    final isNegative = raw.startsWith('-');
    final unsigned = isNegative ? raw.substring(1) : raw;
    final dotIndex = unsigned.indexOf('.');
    if (dotIndex == -1) {
      return _normalizeValidatedDecimalString(raw);
    }
    final intPart = unsigned.substring(0, dotIndex);
    final fracPart = unsigned.substring(dotIndex + 1);
    if (fracPart.length <= maxDecimals) {
      return _normalizeValidatedDecimalString(raw);
    }
    final roundDigit = fracPart.codeUnitAt(maxDecimals) - 0x30;
    final keptDigits = '$intPart${fracPart.substring(0, maxDecimals)}';
    var scaled = BigInt.parse(keptDigits);
    if (roundDigit >= 5) {
      scaled += BigInt.one;
    }
    final digitsStr = scaled.toString().padLeft(maxDecimals + 1, '0');
    final splitIndex = digitsStr.length - maxDecimals;
    final roundedUnsigned = maxDecimals == 0
        ? digitsStr
        : '${digitsStr.substring(0, splitIndex)}.${digitsStr.substring(splitIndex)}';
    return _normalizeValidatedDecimalString(
      isNegative ? '-$roundedUnsigned' : roundedUnsigned,
    );
  }

  /// Validates decoded text content for non-emptiness, multiline restrictions, and Unicode scalar bounds.
  static String _validateDecodedText(
    String value,
    int line,
    int maxScalars, {
    required bool allowMultiline,
  }) {
    if (!allowMultiline) {
      for (var i = 0; i < value.length; i++) {
        final unit = value.codeUnitAt(i);
        if (unit == 0x0A || unit == 0x0D || unit == 0x09) {
          fail(
            TdfErrorKind.unexpectedToken,
            line,
            'Single-line text cannot contain decoded newline, carriage return, or tab.',
          );
        }
      }
    }
    if (!_hasNonAsciiWhitespaceContent(value)) {
      fail(
        TdfErrorKind.emptyText,
        line,
        'Text argument cannot be empty or ASCII whitespace only.',
      );
    }
    final scalarCount = TdfCalendar.countUnicodeScalars(value);
    if (scalarCount == null || scalarCount > maxScalars) {
      fail(
        TdfErrorKind.limitExceeded,
        line,
        'Text argument exceeds maximum of $maxScalars Unicode scalar values.',
      );
    }
    return value;
  }
}
