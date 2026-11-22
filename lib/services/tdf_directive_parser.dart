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
import '../models/tdf_location.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_sync_metadata.dart';
import '../models/tdf_timezone.dart';
import 'tdf_scanner.dart';

/// Mutable field accumulator for a `deleted` root block during TDF `0.8.0` parsing.
class TdfDeletedDirectiveFields {
  /// Creates an empty [TdfDeletedDirectiveFields].
  TdfDeletedDirectiveFields();

  /// Seen deleted label IDs (`<label-id>`).
  final Set<String> deletedLabelIds = <String>{};

  /// Seen deleted location IDs (`<location-id>`).
  final Set<String> deletedLocationIds = <String>{};

  /// Seen deleted task IDs (`<task-id>`).
  final Set<String> deletedTaskIds = <String>{};

  /// Parsed `generation` counter.
  int? generation;

  /// Parsed deleted label records with their 1-based source line numbers.
  final List<({TdfDeletedLabelRecord record, int line})> labelEntries =
      <({TdfDeletedLabelRecord record, int line})>[];

  /// Parsed deleted location records with their 1-based source line numbers.
  final List<({TdfDeletedLocationRecord record, int line})> locationEntries =
      <({TdfDeletedLocationRecord record, int line})>[];

  /// Parsed deleted task records with their 1-based source line numbers.
  final List<({TdfDeletedTaskRecord record, int line})> taskEntries =
      <({TdfDeletedTaskRecord record, int line})>[];
}

/// Mutable field accumulator for a `label` block during TDF `0.8.0` parsing.
class TdfLabelDirectiveFields {
  /// Creates an empty [TdfLabelDirectiveFields].
  TdfLabelDirectiveFields();

  /// Normalized uppercase `#RRGGBB` `color` literal.
  String? color;

  /// Accumulated condition rules across all inline and block declarations.
  final List<TaskCondition> conditions = <TaskCondition>[];

  /// Repeatable `link` attachments in preserved declaration order.
  final List<TaskLink> links = <TaskLink>[];

  /// Raw `<location-id>` reference count across all `location` condition rules before deduplication.
  int locationRefCount = 0;

  /// Referenced `<location-id>` tokens with their 1-based source line numbers.
  final List<({String locationId, int line})> locationReferences =
      <({String locationId, int line})>[];

  /// Optional explicit `modified` UTC timestamp.
  DateTime? modifiedAt;

  /// Required `name` text.
  String? name;

  /// Optional `note` text.
  String? note;
}

/// Mutable field accumulator for a `location` block during TDF `0.8.0` parsing.
class TdfLocationDirectiveFields {
  /// Creates an empty [TdfLocationDirectiveFields].
  TdfLocationDirectiveFields();

  /// Parsed WGS-84 latitude (`[-90.0, 90.0]`).
  double? latitude;

  /// Normalized decimal string for [latitude].
  String? latitudeText;

  /// Parsed WGS-84 longitude (`[-180.0, 180.0]`).
  double? longitude;

  /// Normalized decimal string for [longitude].
  String? longitudeText;

  /// Optional explicit `modified` UTC timestamp.
  DateTime? modifiedAt;

  /// Required `name` text.
  String? name;

  /// Optional `note` text.
  String? note;

  /// Parsed radius in meters (`(0.0, 100000.0]`).
  double? radius;

  /// Normalized decimal string for [radius].
  String? radiusText;

  /// Optional passive `source` address or location code text.
  String? source;
}

/// Mutable field accumulator for a `queue` root block during TDF `0.8.0` parsing.
class TdfQueueDirectiveFields {
  /// Creates an empty [TdfQueueDirectiveFields].
  TdfQueueDirectiveFields();

  /// Ordered `<task-id>` entries with their 1-based source line numbers.
  final List<({String taskId, int line})> entries =
      <({String taskId, int line})>[];

  /// Required `modified` UTC timestamp.
  DateTime? modifiedAt;

  /// Seen `<task-id>` values in the `queue` block.
  final Set<String> seenTaskIds = <String>{};
}

/// Mutable field accumulator for a `task` block during TDF `0.8.0` parsing.
class TdfTaskDirectiveFields {
  /// Creates an empty [TdfTaskDirectiveFields].
  TdfTaskDirectiveFields();

  /// Seen `blocked` target task IDs mapped to their greatest required completion count.
  final Map<String, int> blockedByCompletions = <String, int>{};

  /// 1-based line number of the `blocked` directive when present.
  int? blockedLine;

  /// Parsed `completions` counter (`0..maxTdfCompletions`).
  int? completions;

  /// Accumulated condition rules across all inline and block declarations.
  final List<TaskCondition> conditions = <TaskCondition>[];

  /// Required `created` UTC timestamp.
  DateTime? createdAt;

  /// Optional intended local calendar schedule `anchor` attached to [dueAt] (`TDF-DIR-004`).
  TdfLocalDateTime? dueAnchor;

  /// Optional `due` UTC deadline timestamp.
  DateTime? dueAt;

  /// Optional trailing `<note>` attached to `due`.
  String? dueNote;

  /// Optional `finished` UTC timestamp.
  DateTime? finishedAt;

  /// Whether a `blocked` directive has already been declared.
  bool hasBlockedDirective = false;

  /// Whether a `labels` directive has already been declared.
  bool hasLabelsDirective = false;

  /// Repeatable `history` entries accumulated inside the `task` block.
  final List<TaskHistoryEntry> history = <TaskHistoryEntry>[];

  /// Whether `due` carries the `passive` modifier.
  bool isDuePassive = false;

  /// Whether `suspended forever` was declared.
  bool isSuspendedForever = false;

  /// Referenced `<label-id>` values with their 1-based source line numbers.
  final List<({String labelId, int line})> labelIds =
      <({String labelId, int line})>[];

  /// Repeatable `link` attachments in preserved declaration order.
  final List<TaskLink> links = <TaskLink>[];

  /// Raw `<location-id>` reference count across all `location` condition rules before deduplication.
  int locationRefCount = 0;

  /// Referenced `<location-id>` tokens with their 1-based source line numbers.
  final List<({String locationId, int line})> locationReferences =
      <({String locationId, int line})>[];

  /// Optional explicit `modified` UTC timestamp.
  DateTime? modifiedAt;

  /// Required `name` text.
  String? name;

  /// Optional `note` text.
  String? note;

  /// Optional passive `origin` correlation pair.
  TaskOrigin? origin;

  /// Raw `history` directive count before deduplication (`0..maxTdfHistoryPerTask`).
  int rawHistoryCount = 0;

  /// Optional `repeat` recurrence rule.
  TaskRepeatRule? repeatRule;

  /// Optional finite `suspended` UTC timestamp.
  DateTime? suspendedAt;

  /// Optional trailing `<note>` attached to `suspended`.
  String? suspendedNote;
}

/// Semantic directive and primitive value parser for `spec/TDF_SPEC_0.8.0.md` Sections 4–6.
abstract final class TdfDirectiveParser {
  /// Forbidden executable or inline-payload URI schemes (`TDF-TYPE-005`).
  static const List<String> _forbiddenUriSchemes = <String>[
    'javascript:',
    'vbscript:',
    'data:',
  ];

  /// Appends a condition rule to [fields] on a `label` block (`TDF-DIR-009`, `TDF-VAL-001`).
  static void addConditionToLabel(
    TdfLabelDirectiveFields fields,
    String ruleType,
    List<TdfScannedToken> args,
    int line, {
    required bool isInlineDirective,
  }) {
    if (!isInlineDirective && !_isDepth2ConditionKeyword(ruleType)) {
      fail(
        TdfErrorKind.unknownDirective,
        line,
        'Unknown directive "$ruleType" inside condition block.',
      );
    }
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
    final group = _tryConditionGroupFromName(ruleType);
    if (group == null) {
      fail(
        TdfErrorKind.invalidCondition,
        line,
        'Invalid condition rule type "$ruleType".',
      );
    }
    if (args.length == 1 && args[0].isBare && args[0].value == 'any') {
      fail(
        TdfErrorKind.invalidCondition,
        line,
        'Group reset "$ruleType any" is forbidden inside a label block.',
      );
    }
    if (group == ConditionGroup.location) {
      final condition = _parseLocationRuleForEntity(
        args: args,
        line: line,
        currentRefCount: fields.locationRefCount,
        onUpdateRefCount: (nextCount) => fields.locationRefCount = nextCount,
        locationReferences: fields.locationReferences,
      );
      fields.conditions.add(condition);
      return;
    }
    fields.conditions.add(_parseConcreteConditionRule(group, args, line));
  }

  /// Appends a condition rule or reset to [fields] on a `task` block (`TDF-DIR-009`, `TDF-VAL-001`).
  static void addConditionToTask(
    TdfTaskDirectiveFields fields,
    String ruleType,
    List<TdfScannedToken> args,
    int line, {
    required bool isInlineDirective,
  }) {
    if (!isInlineDirective && !_isDepth2ConditionKeyword(ruleType)) {
      fail(
        TdfErrorKind.unknownDirective,
        line,
        'Unknown directive "$ruleType" inside condition block.',
      );
    }
    if (fields.conditions.length >= maxTdfConditionRulesPerEntity) {
      fail(
        TdfErrorKind.limitExceeded,
        line,
        'Task exceeds maximum of $maxTdfConditionRulesPerEntity condition rules.',
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
    final group = _tryConditionGroupFromName(ruleType);
    if (group == null ||
        fields.conditions.any((rule) => rule is GlobalResetTaskCondition)) {
      fail(
        TdfErrorKind.invalidCondition,
        line,
        'Invalid or conflicting condition rule "$ruleType" on task.',
      );
    }
    if (args.length == 1 && args[0].isBare && args[0].value == 'any') {
      if (fields.conditions.any((rule) => rule.group == group)) {
        fail(
          TdfErrorKind.invalidCondition,
          line,
          'Cannot repeat or combine "$ruleType any" with "$ruleType" rules on the same task.',
        );
      }
      fields.conditions.add(GroupResetTaskCondition(targetGroup: group));
      return;
    }
    if (_hasGroupReset(fields.conditions, group)) {
      fail(
        TdfErrorKind.invalidCondition,
        line,
        'Cannot combine "$ruleType" rule with "$ruleType any" reset on the same task.',
      );
    }
    if (group == ConditionGroup.location) {
      final condition = _parseLocationRuleForEntity(
        args: args,
        line: line,
        currentRefCount: fields.locationRefCount,
        onUpdateRefCount: (nextCount) => fields.locationRefCount = nextCount,
        locationReferences: fields.locationReferences,
      );
      fields.conditions.add(condition);
      return;
    }
    fields.conditions.add(_parseConcreteConditionRule(group, args, line));
  }

  /// Applies a directive inside a `deleted` block to [fields] (`TDF-ENT-005`).
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
          maxTdfSyncGeneration,
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

  /// Applies a directive inside a `label` block to [fields] (`TDF-ENT-003`).
  static void applyLabelDirective(
    TdfLabelDirectiveFields fields,
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
      case 'link':
        if (fields.links.length >= maxTdfLinksPerLabel) {
          fail(
            TdfErrorKind.limitExceeded,
            line,
            'Label exceeds maximum of $maxTdfLinksPerLabel links.',
          );
        }
        fields.links.add(_parseTaskLink(args, line));
      case 'condition':
        _applyInlineConditionToLabel(fields, args, line);
      case _:
        fail(
          TdfErrorKind.unknownDirective,
          line,
          'Unknown label directive "$directive".',
        );
    }
  }

  /// Applies a directive inside a `location` block to [fields] (`TDF-ENT-004`).
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

  /// Applies a directive inside a `queue` block to [fields] (`TDF-ENT-006`).
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
        if (fields.entries.length >= maxTdfQueueEntries) {
          fail(
            TdfErrorKind.limitExceeded,
            line,
            'Queue block exceeds maximum of $maxTdfQueueEntries entries.',
          );
        }
        if (args.length != 1) {
          fail(
            TdfErrorKind.unexpectedToken,
            line,
            'Queue "task" directive requires exactly 1 <task-id> argument.',
          );
        }
        final token = args[0];
        if (!token.isBare || !isValidEntityId(token.value)) {
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

  /// Applies a directive inside a `task` block to [fields] (`TDF-ENT-002`).
  static void applyTaskDirective(
    TdfTaskDirectiveFields fields,
    String directive,
    List<TdfScannedToken> args,
    int line,
  ) {
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
          maxTdfCompletions,
          'completions',
        );
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
      case 'suspended':
        _applyTaskSuspended(fields, args, line);
      case 'due':
        _applyTaskDue(fields, args, line);
      case 'origin':
        if (fields.origin != null) {
          fail(
            TdfErrorKind.duplicateDirective,
            line,
            'Duplicate task "origin".',
          );
        }
        fields.origin = _parseTaskOrigin(args, line);
      case 'link':
        if (fields.links.length >= maxTdfLinksPerTask) {
          fail(
            TdfErrorKind.limitExceeded,
            line,
            'Task exceeds maximum of $maxTdfLinksPerTask links.',
          );
        }
        fields.links.add(_parseTaskLink(args, line));
      case 'history':
        if (fields.rawHistoryCount >= maxTdfHistoryPerTask) {
          fail(
            TdfErrorKind.limitExceeded,
            line,
            'Task exceeds maximum of $maxTdfHistoryPerTask history entries.',
          );
        }
        fields.rawHistoryCount += 1;
        fields.history.add(_parseTaskHistoryEntry(args, line));
      case 'condition':
        _applyInlineConditionToTask(fields, args, line);
      case _:
        fail(
          TdfErrorKind.unknownDirective,
          line,
          'Unknown task directive "$directive".',
        );
    }
  }

  /// Throws a [TdfException] with [kind], [line], and [message].
  static Never fail(TdfErrorKind kind, int line, String message) =>
      TdfScanner.fail(kind, line, message);

  /// Checks whether [id] is a canonical 10-character Base62 entity identifier (`[0-9A-Za-z]{10}`).
  static bool isValidEntityId(String id) => TdfEntityId.isValid(id);

  /// Parses a `step <bool> "<text>"` directive inside a `subtasks` block (`TDF-DIR-008`).
  static SubtaskItem parseStepDirective(List<TdfScannedToken> args, int line) {
    if (args.length != 2) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Subtask "step" requires <bool> and "<text>".',
      );
    }
    final doneToken = args[0];
    if (!doneToken.isBare ||
        (doneToken.value != 'true' && doneToken.value != 'false')) {
      fail(
        TdfErrorKind.invalidBoolean,
        line,
        'Subtask <bool> must be unquoted true or false.',
      );
    }
    final title = _parseQuotedText(
      <TdfScannedToken>[args[1]],
      line,
      maxTdfTextLength,
      allowMultiline: false,
    );
    return SubtaskItem(title: title, isCompleted: doneToken.value == 'true');
  }

  /// Parses `<YYYY-MM-DD> [<HH:MM[:SS]>]` into a UTC [DateTime] (`0001-01-01 00:00:00`..`9999-12-31 23:59:59`).
  static DateTime parseUtcTimestamp(List<TdfScannedToken> args, int line) {
    final parsedLocal = _parseCalendarTimestampTokens(args, line);
    return DateTime.utc(
      parsedLocal.year,
      parsedLocal.month,
      parsedLocal.day,
      parsedLocal.hour,
      parsedLocal.minute,
      parsedLocal.second,
    );
  }

  /// Parses a `label <label-id> <timestamp>` deletion record inside `deleted`.
  static void _applyDeletedLabelRecord(
    TdfDeletedDirectiveFields fields,
    List<TdfScannedToken> args,
    int line,
  ) {
    _ensureDeletedRecordCapacity(fields, line);
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
    if (!idToken.isBare || !isValidEntityId(idToken.value)) {
      fail(
        TdfErrorKind.invalidIdentifier,
        line,
        'Invalid <label-id> "${idToken.value}" in deleted block.',
      );
    }
    final deletedAt = parseUtcTimestamp(args.sublist(1), line);
    if (!fields.deletedLabelIds.add(idToken.value)) {
      fail(
        TdfErrorKind.duplicateIdentifier,
        line,
        'Duplicate deleted label ID "${idToken.value}".',
      );
    }
    fields.labelEntries.add((
      record: TdfDeletedLabelRecord(
        labelId: idToken.value,
        deletedAt: deletedAt,
      ),
      line: line,
    ));
  }

  /// Parses a `location <location-id> <timestamp>` deletion record inside `deleted`.
  static void _applyDeletedLocationRecord(
    TdfDeletedDirectiveFields fields,
    List<TdfScannedToken> args,
    int line,
  ) {
    _ensureDeletedRecordCapacity(fields, line);
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
    if (!idToken.isBare || !isValidEntityId(idToken.value)) {
      fail(
        TdfErrorKind.invalidIdentifier,
        line,
        'Invalid <location-id> "${idToken.value}" in deleted block.',
      );
    }
    final deletedAt = parseUtcTimestamp(args.sublist(1), line);
    if (!fields.deletedLocationIds.add(idToken.value)) {
      fail(
        TdfErrorKind.duplicateIdentifier,
        line,
        'Duplicate deleted location ID "${idToken.value}".',
      );
    }
    fields.locationEntries.add((
      record: TdfDeletedLocationRecord(
        locationId: idToken.value,
        deletedAt: deletedAt,
      ),
      line: line,
    ));
  }

  /// Parses a `task <task-id> <timestamp> [<completion-count>]` deletion record inside `deleted`.
  static void _applyDeletedTaskRecord(
    TdfDeletedDirectiveFields fields,
    List<TdfScannedToken> args,
    int line,
  ) {
    _ensureDeletedRecordCapacity(fields, line);
    if (args.length < 2 || args.length > 4) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Invalid deleted task record argument count.',
      );
    }
    final idToken = args[0];
    if (!idToken.isBare || !isValidEntityId(idToken.value)) {
      fail(
        TdfErrorKind.invalidIdentifier,
        line,
        'Invalid <task-id> "${idToken.value}" in deleted block.',
      );
    }
    final timestampArgCount = (args.length >= 3 && args[2].value.contains(':'))
        ? 2
        : 1;
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
    final checkpoint = remainingArgs.length == 1
        ? _parseUnsignedIntWithLimit(
            remainingArgs,
            line,
            maxTdfCompletions,
            'completion checkpoint',
          )
        : 0;
    if (!fields.deletedTaskIds.add(idToken.value)) {
      fail(
        TdfErrorKind.duplicateIdentifier,
        line,
        'Duplicate deleted task ID "${idToken.value}".',
      );
    }
    fields.taskEntries.add((
      record: TdfDeletedTaskRecord(
        taskId: idToken.value,
        deletedAt: deletedAt,
        completionsCheckpoint: checkpoint,
      ),
      line: line,
    ));
  }

  /// Validates and applies an inline `condition <type> ...` directive inside a `label` block.
  static void _applyInlineConditionToLabel(
    TdfLabelDirectiveFields fields,
    List<TdfScannedToken> args,
    int line,
  ) {
    if (args.isEmpty) {
      fail(
        TdfErrorKind.missingDirectiveArgument,
        line,
        'Missing condition arguments.',
      );
    }
    final ruleTypeToken = args[0];
    if (!ruleTypeToken.isBare) {
      if (fields.conditions.length >= maxTdfConditionRulesPerEntity) {
        fail(
          TdfErrorKind.limitExceeded,
          line,
          'Label exceeds maximum of $maxTdfConditionRulesPerEntity condition rules.',
        );
      }
      fail(
        TdfErrorKind.invalidCondition,
        line,
        'Condition rule keyword must not be quoted.',
      );
    }
    addConditionToLabel(
      fields,
      ruleTypeToken.value,
      args.sublist(1),
      line,
      isInlineDirective: true,
    );
  }

  /// Validates and applies an inline `condition <type> ...` directive inside a `task` block.
  static void _applyInlineConditionToTask(
    TdfTaskDirectiveFields fields,
    List<TdfScannedToken> args,
    int line,
  ) {
    if (args.isEmpty) {
      fail(
        TdfErrorKind.missingDirectiveArgument,
        line,
        'Missing condition arguments.',
      );
    }
    final ruleTypeToken = args[0];
    if (!ruleTypeToken.isBare) {
      if (fields.conditions.length >= maxTdfConditionRulesPerEntity) {
        fail(
          TdfErrorKind.limitExceeded,
          line,
          'Task exceeds maximum of $maxTdfConditionRulesPerEntity condition rules.',
        );
      }
      fail(
        TdfErrorKind.invalidCondition,
        line,
        'Condition rule keyword must not be quoted.',
      );
    }
    addConditionToTask(
      fields,
      ruleTypeToken.value,
      args.sublist(1),
      line,
      isInlineDirective: true,
    );
  }

  /// Validates and applies `coordinates <lat> <lon>` inside a `location` block (`TDF-ENT-004`).
  static void _applyLocationCoordinates(
    TdfLocationDirectiveFields fields,
    List<TdfScannedToken> args,
    int line,
  ) {
    if (args.length != 2 || args.any((token) => !token.isBare)) {
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

  /// Validates and applies `radius <meters>` inside a `location` block (`TDF-ENT-004`).
  static void _applyLocationRadius(
    TdfLocationDirectiveFields fields,
    List<TdfScannedToken> args,
    int line,
  ) {
    if (args.length != 1 || !args[0].isBare) {
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

  /// Applies `suspended forever ["<note>"]` under `TDF-DIR-003`.
  static void _applySuspendedForever(
    TdfTaskDirectiveFields fields,
    List<TdfScannedToken> args,
    int line,
  ) {
    if (args.length == 1) {
      fields.isSuspendedForever = true;
      return;
    }
    if (args.length == 2 && args[1].isQuoted) {
      fields.isSuspendedForever = true;
      fields.suspendedNote = _validateDecodedText(
        args[1].value,
        line,
        maxTdfNoteLength,
        allowMultiline: true,
      );
      return;
    }
    fail(
      TdfErrorKind.unexpectedToken,
      line,
      'Task "suspended forever" accepts at most 1 trailing quoted <note>.',
    );
  }

  /// Applies `due <timestamp> [anchor <timestamp>] [passive] ["<note>"]` using right-to-left modifier peeling (`TDF-DIR-004`).
  static void _applyTaskDue(
    TdfTaskDirectiveFields fields,
    List<TdfScannedToken> args,
    int line,
  ) {
    if (fields.dueAt != null) {
      fail(TdfErrorKind.duplicateDirective, line, 'Duplicate task "due".');
    }
    if (!args[0].isBare) {
      fail(
        TdfErrorKind.invalidTimestamp,
        line,
        'Task "due" first argument must not be quoted.',
      );
    }
    _rejectQuotedMiddleArgs(args, line, 'due');
    if (args.length >= 2 &&
        args[args.length - 2].isBare &&
        args[args.length - 2].value == 'anchor' &&
        args.last.isQuoted) {
      fail(
        TdfErrorKind.invalidTimestamp,
        line,
        'Task "due" anchor timestamp must not be quoted.',
      );
    }
    var end = args.length;
    TdfScannedToken? rawNoteToken;
    if (end >= 2 && args[end - 1].isQuoted) {
      rawNoteToken = args[end - 1];
      end -= 1;
    }
    var isPassive = false;
    if (end >= 2 && args[end - 1].isBare && args[end - 1].value == 'passive') {
      isPassive = true;
      end -= 1;
    }
    if (end >= 2 && args[end - 1].isBare && args[end - 1].value == 'passive') {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Duplicate "passive" modifier on task "due".',
      );
    }
    final resolvedSchedule = _parseDueAndAnchorSlices(args, end, line);
    String? validatedNote;
    if (rawNoteToken != null) {
      validatedNote = _validateDecodedText(
        rawNoteToken.value,
        line,
        maxTdfNoteLength,
        allowMultiline: true,
      );
    }
    fields.dueAt = resolvedSchedule.dueAt;
    fields.dueAnchor = resolvedSchedule.dueAnchor;
    fields.isDuePassive = isPassive;
    fields.dueNote = validatedNote;
  }

  /// Applies `suspended (<timestamp> | forever) ["<note>"]` inside a `task` block (`TDF-DIR-003`).
  static void _applyTaskSuspended(
    TdfTaskDirectiveFields fields,
    List<TdfScannedToken> args,
    int line,
  ) {
    if (fields.suspendedAt != null || fields.isSuspendedForever) {
      fail(
        TdfErrorKind.duplicateDirective,
        line,
        'Duplicate task "suspended".',
      );
    }
    if (!args[0].isBare) {
      fail(
        TdfErrorKind.invalidTimestamp,
        line,
        'Task "suspended" first argument must not be quoted.',
      );
    }
    _rejectQuotedMiddleArgs(args, line, 'suspended');
    if (args[0].value == 'forever') {
      _applySuspendedForever(fields, args, line);
      return;
    }
    if (args.length >= 2 && args.last.isQuoted) {
      final parsedSuspended = parseUtcTimestamp(
        args.sublist(0, args.length - 1),
        line,
      );
      final validatedNote = _validateDecodedText(
        args.last.value,
        line,
        maxTdfNoteLength,
        allowMultiline: true,
      );
      fields.suspendedAt = parsedSuspended;
      fields.suspendedNote = validatedNote;
      return;
    }
    fields.suspendedAt = parseUtcTimestamp(args, line);
  }

  /// Enforces `MAX_DELETED_RECORDS` before allocating a new tombstone record (`P-BOUND-ALLOC`).
  static void _ensureDeletedRecordCapacity(
    TdfDeletedDirectiveFields fields,
    int line,
  ) {
    final totalRecords =
        fields.taskEntries.length +
        fields.labelEntries.length +
        fields.locationEntries.length;
    if (totalRecords >= maxTdfDeletedRecords) {
      fail(
        TdfErrorKind.limitExceeded,
        line,
        'Deleted block exceeds maximum of $maxTdfDeletedRecords records.',
      );
    }
  }

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

  /// Checks whether [keyword] is one of the recognized depth-`2` `condition { ... }` identifiers (`{day, time, location, any}`).
  static bool _isDepth2ConditionKeyword(String keyword) =>
      keyword == 'day' ||
      keyword == 'time' ||
      keyword == 'location' ||
      keyword == 'any';

  /// Checks whether [unit] is a valid RFC 3986 URI scheme continuation character (`[a-zA-Z0-9+.-]`).
  static bool _isUriSchemeChar(int unit) =>
      _isAsciiAlpha(unit) ||
      TdfScanner.isAsciiDigit(unit) ||
      unit == 0x2B ||
      unit == 0x2D ||
      unit == 0x2E;

  /// Parses `blocked <task-id>[:<count>] ...` arguments, retaining the greatest `<count>` for duplicate target IDs.
  static void _parseBlockedDependencies(
    List<TdfScannedToken> args,
    int line,
    Map<String, int> targetMap,
  ) {
    for (final token in args) {
      _parseSingleBlockedDependency(token, line, targetMap);
    }
  }

  /// Parses `1..2` bare `<YYYY-MM-DD> [<HH:MM[:SS]>]` tokens into a validated [TdfLocalDateTime] (`TDF-TYPE-004`).
  static TdfLocalDateTime _parseCalendarTimestampTokens(
    List<TdfScannedToken> args,
    int line,
  ) {
    if (args.isEmpty || args.length > 2) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Invalid timestamp argument count.',
      );
    }
    if (args.any((token) => !token.isBare)) {
      fail(
        TdfErrorKind.invalidTimestamp,
        line,
        'Timestamp tokens must not be quoted.',
      );
    }
    final parsed = TdfLocalDateTime.tryParse(
      args[0].value,
      args.length == 2 ? args[1].value : null,
    );
    if (parsed == null) {
      fail(
        TdfErrorKind.invalidTimestamp,
        line,
        'Invalid calendar timestamp "${args[0].value}".',
      );
    }
    return parsed;
  }

  /// Parses and normalizes a quoted `"#RRGGBB"` color argument to uppercase (`TDF-MODEL-006`, `TDF-TYPE-005`).
  static String _parseColor(List<TdfScannedToken> args, int line) {
    if (args.length != 1 || !args[0].isQuoted) {
      fail(
        TdfErrorKind.invalidColor,
        line,
        'Label "color" must be a single quoted "#RRGGBB" string.',
      );
    }
    final value = args[0].value;
    if (!TdfColor.isStrictHexColor(value)) {
      fail(
        TdfErrorKind.invalidColor,
        line,
        'Invalid hex color "$value": expected "#RRGGBB".',
      );
    }
    return value.toUpperCase();
  }

  /// Parses a concrete `day` or `time` condition rule.
  static TaskCondition _parseConcreteConditionRule(
    ConditionGroup group,
    List<TdfScannedToken> args,
    int line,
  ) => switch (group) {
    ConditionGroup.day => _parseDayRuleArgs(args, line),
    ConditionGroup.time => _parseTimeRuleArgs(args, line),
    ConditionGroup.location => fail(
      TdfErrorKind.invalidCondition,
      line,
      'Unexpected location dispatch in concrete rule parser.',
    ),
  };

  /// Parses `day <d1> [<d2> ...]` (`TDF-DIR-009`).
  static DayTaskCondition _parseDayRuleArgs(
    List<TdfScannedToken> args,
    int line,
  ) {
    if (args.isEmpty) {
      fail(
        TdfErrorKind.invalidCondition,
        line,
        'Condition "day" requires at least one weekday.',
      );
    }
    final weekdays = <int>[];
    final dayTokens = <String>[];
    for (final token in args) {
      final weekday = token.isBare
          ? DayTaskCondition.parseWeekdayToken(token.value)
          : null;
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

  /// Disambiguates and validates the UTC `due` slice and optional `anchor` slice in `args[0 .. end - 1]` (`TDF-DIR-004`).
  static ({DateTime dueAt, TdfLocalDateTime? dueAnchor})
  _parseDueAndAnchorSlices(List<TdfScannedToken> args, int end, int line) {
    var anchorCount = 0;
    var anchorIndex = -1;
    for (var i = 1; i < end; i++) {
      if (args[i].isBare && args[i].value == 'anchor') {
        anchorCount++;
        anchorIndex = i;
      }
    }
    if (anchorCount > 1) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Duplicate "anchor" modifier on task "due".',
      );
    }
    if (anchorCount == 0) {
      if (end >= 3) {
        fail(
          TdfErrorKind.unexpectedToken,
          line,
          'Unexpected trailing arguments on task "due".',
        );
      }
      return (
        dueAt: parseUtcTimestamp(args.sublist(0, end), line),
        dueAnchor: null,
      );
    }
    for (var i = 1; i < end; i++) {
      if (i != anchorIndex && args[i].isBare && args[i].value == 'passive') {
        fail(
          TdfErrorKind.unexpectedToken,
          line,
          'Misordered "passive" modifier around "anchor" on task "due".',
        );
      }
    }
    final dueSlice = args.sublist(0, anchorIndex);
    final anchorSlice = args.sublist(anchorIndex + 1, end);
    if (dueSlice.length >= 3 ||
        anchorSlice.isEmpty ||
        anchorSlice.length >= 3) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Malformed "due ... anchor ..." timestamp arity.',
      );
    }
    final parsedDueAt = parseUtcTimestamp(dueSlice, line);
    final parsedAnchor = _parseCalendarTimestampTokens(anchorSlice, line);
    return (dueAt: parsedDueAt, dueAnchor: parsedAnchor);
  }

  /// Parses `labels <id1> [<id2> ...]` arguments.
  static void _parseLabelRefs(
    List<TdfScannedToken> args,
    int line,
    List<({String labelId, int line})> target,
  ) {
    for (final token in args) {
      if (!token.isBare || !isValidEntityId(token.value)) {
        fail(
          TdfErrorKind.invalidIdentifier,
          line,
          'Invalid <label-id> "${token.value}".',
        );
      }
      target.add((labelId: token.value, line: line));
    }
  }

  /// Parses `location <loc-1> [<loc-2> ...]` and enforces `MAX_LOCATION_REFS_PER_ENTITY = 63` before deduplication (`TDF-DIR-009`).
  static LocationTaskCondition _parseLocationRuleForEntity({
    required List<TdfScannedToken> args,
    required int line,
    required int currentRefCount,
    required void Function(int) onUpdateRefCount,
    required List<({String locationId, int line})> locationReferences,
  }) {
    if (args.isEmpty) {
      fail(
        TdfErrorKind.invalidCondition,
        line,
        'Condition "location" requires at least 1 <location-id> argument.',
      );
    }
    var refCount = currentRefCount;
    final deduplicatedIds = <String>[];
    for (final token in args) {
      if (refCount >= maxTdfLocationRefsPerEntity) {
        fail(
          TdfErrorKind.limitExceeded,
          line,
          'Entity exceeds maximum of $maxTdfLocationRefsPerEntity location references.',
        );
      }
      if (!token.isBare || !isValidEntityId(token.value)) {
        fail(
          TdfErrorKind.invalidIdentifier,
          line,
          'Invalid <location-id> "${token.value}" in location condition rule.',
        );
      }
      refCount++;
      locationReferences.add((locationId: token.value, line: line));
      if (!deduplicatedIds.contains(token.value)) {
        deduplicatedIds.add(token.value);
      }
    }
    onUpdateRefCount(refCount);
    return LocationTaskCondition(locationIds: deduplicatedIds);
  }

  /// Parses `<HH:MM>` into minutes from midnight (`0..1439`), failing with [TdfErrorKind.invalidCondition] (`TDF-TYPE-004`).
  static int _parseMinutesOfDay(TdfScannedToken token, int line) {
    if (!token.isBare) {
      fail(
        TdfErrorKind.invalidCondition,
        line,
        'Time window token must not be quoted.',
      );
    }
    final raw = token.value;
    final minutes = TdfMetadata.tryParseTimeMinutes(raw);
    if (minutes == null) {
      fail(
        TdfErrorKind.invalidCondition,
        line,
        'Invalid time window token "$raw": expected 00:00..23:59 HH:MM.',
      );
    }
    return minutes;
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
      if (!TdfScanner.isAsciiDigit(raw.codeUnitAt(i))) {
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

  /// Parses and validates a single quoted `<text>` or `<note>` argument (`TDF-TYPE-003`).
  static String _parseQuotedText(
    List<TdfScannedToken> args,
    int line,
    int maxScalars, {
    required bool allowMultiline,
  }) {
    if (args.length != 1 || !args[0].isQuoted) {
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

  /// Parses and validates an unquoted `<repeat-time>` clock token (`HH:MM` or `HH:MM:SS`).
  static TdfRepeatClock _parseRepeatClockToken(
    TdfScannedToken clockToken,
    int line,
  ) {
    if (!clockToken.isBare) {
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
    return parsedClock;
  }

  /// Parses `repeat <count> <days|weeks|months> [<repeat-time>] [lead <lead-count> days]` (`TDF-DIR-001`).
  static TaskRepeatRule _parseRepeatRule(List<TdfScannedToken> args, int line) {
    if (args.length < 2) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Directive "repeat" requires at least <count> and <unit>.',
      );
    }
    if (!args[0].isBare) {
      fail(
        TdfErrorKind.invalidNumber,
        line,
        'Repeat <count> must not be quoted.',
      );
    }
    final count = _parsePositiveIntToken(
      args[0].value,
      line,
      maxTdfRepeatCount,
      'repeat count',
    );
    if (!args[1].isBare) {
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
    var index = 2;
    var clock = TdfRepeatClock.midnight;
    if (index < args.length &&
        !(args[index].isBare && args[index].value == 'lead')) {
      clock = _parseRepeatClockToken(args[index], line);
      index += 1;
    }
    final leadDays = index < args.length
        ? _parseRepeatLeadClause(args, index, line)
        : 0;
    return TaskRepeatRule(
      count: count,
      unit: unit,
      clock: clock,
      leadDays: leadDays,
    );
  }

  /// Parses the trailing `lead <lead-count> days` clause on `repeat` (`TDF-DIR-001`).
  static int _parseRepeatLeadClause(
    List<TdfScannedToken> args,
    int startIndex,
    int line,
  ) {
    if (!args[startIndex].isBare ||
        args[startIndex].value != 'lead' ||
        args.length - startIndex != 3) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Repeat lead clause must have form "lead <lead-count> days".',
      );
    }
    final leadCountToken = args[startIndex + 1];
    if (!leadCountToken.isBare) {
      fail(
        TdfErrorKind.invalidNumber,
        line,
        'Repeat <lead-count> must not be quoted.',
      );
    }
    final leadDays = _parsePositiveIntToken(
      leadCountToken.value,
      line,
      maxTdfRepeatCount,
      'repeat lead count',
    );
    final daysToken = args[startIndex + 2];
    if (!daysToken.isBare || daysToken.value != 'days') {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Repeat lead unit must be unquoted "days".',
      );
    }
    return leadDays;
  }

  /// Parses a single `<task-id>[:<required-completion>]` prerequisite token (`TDF-TYPE-006`).
  static void _parseSingleBlockedDependency(
    TdfScannedToken token,
    int line,
    Map<String, int> targetMap,
  ) {
    if (!token.isBare) {
      fail(
        TdfErrorKind.invalidIdentifier,
        line,
        'Prerequisite token must not be quoted.',
      );
    }
    final raw = token.value;
    final colonIndex = raw.indexOf(':');
    final targetId = colonIndex == -1 ? raw : raw.substring(0, colonIndex);
    if (!isValidEntityId(targetId)) {
      fail(
        TdfErrorKind.invalidIdentifier,
        line,
        'Invalid prerequisite <task-id> "$targetId".',
      );
    }
    var requiredCount = 1;
    if (colonIndex != -1) {
      final countStr = raw.substring(colonIndex + 1);
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
        maxTdfCompletions,
        'prerequisite count',
      );
    }
    final existing = targetMap[targetId];
    if (existing == null || requiredCount > existing) {
      targetMap[targetId] = requiredCount;
    }
  }

  /// Parses and normalizes a `tdf 0.8.0` decimal `<number>` token (`TDF-TYPE-005`).
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
    if (!TdfLocation.isValidNumberToken(raw)) {
      fail(TdfErrorKind.invalidNumber, line, 'Invalid decimal number token.');
    }
    final normalizedText = TdfLocation.normalizeDecimalText(raw);
    final significantDecimals = TdfLocation.countSignificantFractionalDigits(
      normalizedText,
    );
    if (significantDecimals > maxDecimals) {
      fail(
        TdfErrorKind.invalidNumber,
        line,
        'Decimal number exceeds maximum of $maxDecimals fractional digits.',
      );
    }
    final value = double.tryParse(normalizedText);
    if (value == null || !value.isFinite) {
      fail(TdfErrorKind.invalidNumber, line, 'Non-finite decimal number.');
    }
    if (strictlyPositive ? value <= min : value < min) {
      fail(
        TdfErrorKind.invalidNumber,
        line,
        'Decimal number is below minimum $min.',
      );
    }
    if (value > max) {
      fail(
        maxExceedsIsLimitExceeded
            ? TdfErrorKind.limitExceeded
            : TdfErrorKind.invalidNumber,
        line,
        'Decimal number exceeds maximum $max.',
      );
    }
    return (value: value == 0.0 ? 0.0 : value, normalizedText: normalizedText);
  }

  /// Parses `history <timestamp> "<text>"` inside a `task` block (`TDF-DIR-007`).
  static TaskHistoryEntry _parseTaskHistoryEntry(
    List<TdfScannedToken> args,
    int line,
  ) {
    if (args.length < 2 ||
        args.length > 3 ||
        !args.last.isQuoted ||
        (args.length == 3 && !args[1].isBare)) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Task "history" requires <timestamp> and trailing quoted "<text>".',
      );
    }
    final timestampUtc = parseUtcTimestamp(
      args.sublist(0, args.length - 1),
      line,
    );
    final text = _validateDecodedText(
      args.last.value,
      line,
      maxTdfTextLength,
      allowMultiline: false,
    );
    return TaskHistoryEntry(timestampUtc: timestampUtc, text: text);
  }

  /// Parses `link "<title>" "<uri>"` inside a `task` or `label` block (`TDF-DIR-006`, `TDF-TYPE-005`).
  static TaskLink _parseTaskLink(List<TdfScannedToken> args, int line) {
    if (args.length != 2 || !args[0].isQuoted || !args[1].isQuoted) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Directive "link" requires 2 quoted arguments ("<title>" "<uri>").',
      );
    }
    final title = _validateDecodedText(
      args[0].value,
      line,
      maxTdfTextLength,
      allowMultiline: false,
    );
    final uri = _validateDecodedUri(args[1].value, line);
    return TaskLink(title: title, uri: uri);
  }

  /// Parses `origin "<namespace>" "<external-key>"` inside a `task` block (`TDF-DIR-005`).
  static TaskOrigin _parseTaskOrigin(List<TdfScannedToken> args, int line) {
    if (args.length != 2 || !args[0].isQuoted || !args[1].isQuoted) {
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

  /// Parses `time <start> <end>` (`TDF-DIR-009`).
  static TimeWindowTaskCondition _parseTimeRuleArgs(
    List<TdfScannedToken> args,
    int line,
  ) {
    if (args.length != 2) {
      fail(
        TdfErrorKind.invalidCondition,
        line,
        'Condition "time" requires exactly 2 <HH:MM> tokens.',
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
    if (!token.isBare) {
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

  /// Rejects any quoted token in non-final argument slots `1 <= i < args.length - 1`.
  static void _rejectQuotedMiddleArgs(
    List<TdfScannedToken> args,
    int line,
    String directive,
  ) {
    for (var i = 1; i < args.length - 1; i++) {
      if (!args[i].isBare) {
        fail(
          TdfErrorKind.unexpectedToken,
          line,
          'Quoted argument on "$directive" must appear only in the final slot.',
        );
      }
    }
  }

  /// Rejects decoded `\n`, `\r`, or `\t` control units inside single-line `<text>`.
  static void _rejectSingleLineControlUnits(String value, int line) {
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

  /// Maps a condition group keyword (`day`, `time`, `location`) to [ConditionGroup], or returns `null`.
  static ConditionGroup? _tryConditionGroupFromName(String ruleType) =>
      switch (ruleType) {
        'day' => ConditionGroup.day,
        'time' => ConditionGroup.time,
        'location' => ConditionGroup.location,
        _ => null,
      };

  /// Validates decoded `<text>` or `<note>` content under `TDF-TYPE-003` precedence.
  static String _validateDecodedText(
    String value,
    int line,
    int maxScalars, {
    required bool allowMultiline,
  }) {
    if (!allowMultiline) {
      _rejectSingleLineControlUnits(value, line);
    }
    final scalarCount = TdfCalendar.countUnicodeScalars(value);
    if (scalarCount == null) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Text argument contains unpaired UTF-16 surrogate.',
      );
    }
    if (!_hasNonAsciiWhitespaceContent(value)) {
      fail(
        TdfErrorKind.emptyText,
        line,
        'Text argument cannot be empty or ASCII whitespace only.',
      );
    }
    if (scalarCount > maxScalars) {
      fail(
        TdfErrorKind.limitExceeded,
        line,
        'Text argument exceeds maximum of $maxScalars Unicode scalar values.',
      );
    }
    return value;
  }

  /// Validates a decoded `<uri>` string under `TDF-TYPE-005` precedence.
  static String _validateDecodedUri(String uri, int line) {
    final scalarCount = TdfCalendar.countUnicodeScalars(uri);
    if (scalarCount == null) {
      fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Link <uri> contains unpaired UTF-16 surrogate.',
      );
    }
    if (!_hasNonAsciiWhitespaceContent(uri)) {
      fail(
        TdfErrorKind.emptyText,
        line,
        'Link <uri> cannot be empty or ASCII whitespace only.',
      );
    }
    if (scalarCount > maxTdfUriLength) {
      fail(
        TdfErrorKind.limitExceeded,
        line,
        'Link <uri> exceeds maximum of $maxTdfUriLength Unicode scalar values.',
      );
    }
    if (TdfMetadata.containsAsciiControlChar(uri)) {
      fail(
        TdfErrorKind.invalidUri,
        line,
        'Link <uri> cannot contain control characters.',
      );
    }
    if (!_hasValidUriSchemePrefix(uri)) {
      fail(
        TdfErrorKind.invalidUri,
        line,
        'Link <uri> lacks a valid URI scheme.',
      );
    }
    final lowerUri = uri.toLowerCase();
    for (final forbidden in _forbiddenUriSchemes) {
      if (lowerUri.startsWith(forbidden)) {
        fail(
          TdfErrorKind.invalidUri,
          line,
          'Link <uri> uses forbidden scheme "$forbidden".',
        );
      }
    }
    return uri;
  }
}
