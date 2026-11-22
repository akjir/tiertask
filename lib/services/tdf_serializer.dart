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

import '../models/task_board.dart';
import '../models/task_item.dart';
import '../models/tdf_error.dart';
import '../models/tdf_location.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_sync_metadata.dart';
import '../models/tdf_timezone.dart';
import 'tdf_directive_parser.dart';
import 'tdf_parser.dart';
import 'tdf_scanner.dart';

/// Byte-exact canonical `tdf 0.8.0` serializer (`spec/TDF_SPEC_0.8.0.md` Section 7).
abstract final class TdfSerializer {
  /// Serializes [board] into canonical `LF`-terminated `tdf 0.8.0` text and validates all output bounds (`TDF-SER-001`–`TDF-SER-005`).
  static String serialize(TaskBoard board) {
    final buffer = StringBuffer()
      ..writeln('tdf ${TdfBlockParser.supportedVersion}');
    var totalBlocks = 0;

    totalBlocks = _incrementBlockCount(
      totalBlocks,
      _serializeDeletedBlock(buffer, board.deletedBlock),
    );
    totalBlocks = _incrementBlockCount(
      totalBlocks,
      _serializeQueueBlock(buffer, board.queueBlock),
    );

    final sortedLabels = List<TdfLabel>.from(board.labels)
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final label in sortedLabels) {
      buffer.writeln();
      totalBlocks = _incrementBlockCount(
        totalBlocks,
        _serializeLabel(buffer, label),
      );
    }

    if (board.locations.length > maxTdfLocations) {
      _failLimitExceeded(
        'Document exceeds maximum of $maxTdfLocations location blocks.',
      );
    }
    final sortedLocations = List<TdfLocation>.from(board.locations)
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final location in sortedLocations) {
      buffer.writeln();
      totalBlocks = _incrementBlockCount(
        totalBlocks,
        _serializeLocation(buffer, location),
      );
    }

    final sortedTasks = List<TaskItem>.from(board.allTasks)
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final task in sortedTasks) {
      buffer.writeln();
      totalBlocks = _incrementBlockCount(
        totalBlocks,
        _serializeTask(buffer, task),
      );
    }

    final output = buffer.toString();
    _validateOutputBounds(output);
    return output;
  }

  /// Appends a single coalesced [rule] into its canonical group bucket.
  static void _appendConditionToGroupBucket(
    TaskCondition rule,
    List<TaskCondition> dayRules,
    List<TaskCondition> timeRules,
    List<TaskCondition> locationRules,
  ) {
    switch (rule.group) {
      case ConditionGroup.day:
        dayRules.add(rule);
      case ConditionGroup.time:
        timeRules.add(rule);
      case ConditionGroup.location:
        if (rule case final LocationTaskCondition locationCondition
            when locationCondition.locationIds.length >
                maxTdfLocationRefsPerEntity) {
          _failLimitExceeded(
            'Condition exceeds maximum of $maxTdfLocationRefsPerEntity location references.',
          );
        }
        locationRules.add(rule);
      case null:
        break;
    }
  }

  /// Validates [value] against [maxScalars] Unicode scalar values and escapes it as a double-quoted TDF string literal.
  static String _escapeBoundedQuoted(
    String value,
    int maxScalars,
    String fieldName,
  ) {
    _validateScalarLength(value, maxScalars, fieldName);
    return _escapeQuoted(value);
  }

  /// Escapes a string for a double-quoted TDF string literal (`\"`, `\\`, `\n`, `\r`, `\t`).
  static String _escapeQuoted(String value) {
    final buffer = StringBuffer('"');
    for (var i = 0; i < value.length; i++) {
      _writeEscapedCodeUnit(buffer, value.codeUnitAt(i));
    }
    buffer.write('"');
    return buffer.toString();
  }

  /// Throws a [TdfException] with [TdfErrorKind.limitExceeded] at line `1`.
  static Never _failLimitExceeded(String message) {
    throw TdfException(
      kind: TdfErrorKind.limitExceeded,
      line: 1,
      message: message,
    );
  }

  /// Formats sorted, deduplicated `blocked` dependencies and enforces `MAX_ARGS_PER_STMT = 64`.
  static String _formatBlockedValue(List<TdfTaskDependency> dependencies) {
    final maxByTaskId = <String, int>{};
    for (final dependency in dependencies) {
      if (dependency.requiredCompletion > maxTdfCompletions) {
        _failLimitExceeded(
          'Prerequisite threshold exceeds maximum of $maxTdfCompletions.',
        );
      }
      final existing = maxByTaskId[dependency.taskId];
      if (existing == null || dependency.requiredCompletion > existing) {
        maxByTaskId[dependency.taskId] = dependency.requiredCompletion;
      }
    }
    if (maxByTaskId.length > maxTdfArgsPerStmt) {
      _failLimitExceeded(
        'Directive "blocked" exceeds maximum of $maxTdfArgsPerStmt arguments.',
      );
    }
    final sortedIds = maxByTaskId.keys.toList()..sort();
    final formatted = <String>[];
    for (final taskId in sortedIds) {
      final requiredCompletion = maxByTaskId[taskId] ?? 1;
      formatted.add(
        TdfTaskDependency(
          taskId: taskId,
          requiredCompletion: requiredCompletion,
        ).formatCanonical(),
      );
    }
    return formatted.join(' ');
  }

  /// Formats a condition rule without the leading `condition` keyword.
  static ({String key, String args}) _formatConditionRuleParts(
    TaskCondition condition,
  ) => switch (condition) {
    DayTaskCondition(:final dayTokens) => (
      key: 'day',
      args: dayTokens.join(' '),
    ),
    GlobalResetTaskCondition() => (key: 'any', args: ''),
    GroupResetTaskCondition(:final targetGroup) => (
      key: targetGroup.name,
      args: 'any',
    ),
    LocationTaskCondition(:final locationIds) => (
      key: 'location',
      args: locationIds.join(' '),
    ),
    TimeWindowTaskCondition(:final startToken, :final endToken) => (
      key: 'time',
      args: '$startToken $endToken',
    ),
  };

  /// Formats a canonical `due <YYYY-MM-DD HH:MM:SS>[ anchor <YYYY-MM-DD HH:MM:SS>][ passive][ "<escaped-note>"]` value (`TDF-SER-003`).
  static String _formatDueValue(
    DateTime due, {
    required TdfLocalDateTime? dueAnchor,
    required bool isPassive,
    required String? note,
  }) {
    final base = _formatExplicitSecondsUtcTimestamp(due);
    final anchorSuffix = dueAnchor != null
        ? ' anchor ${dueAnchor.formatExplicitSeconds()}'
        : '';
    final passiveSuffix = isPassive ? ' passive' : '';
    final noteSuffix = (note != null && note.isNotEmpty)
        ? ' ${_escapeBoundedQuoted(note, maxTdfNoteLength, 'Due note')}'
        : '';
    return '$base$anchorSuffix$passiveSuffix$noteSuffix';
  }

  /// Formats a UTC [timestamp] with explicit seconds (`YYYY-MM-DD HH:MM:SS`).
  static String _formatExplicitSecondsUtcTimestamp(DateTime timestamp) {
    final utc = timestamp.toUtc();
    final year = utc.year.toString().padLeft(4, '0');
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    final hour = utc.hour.toString().padLeft(2, '0');
    final minute = utc.minute.toString().padLeft(2, '0');
    final second = utc.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute:$second';
  }

  /// Formats deduplicated, ASCII-sorted `labels` IDs and enforces `MAX_ARGS_PER_STMT = 64`.
  static String _formatLabelsValue(List<String> labelIds) {
    final deduplicated = labelIds.toSet().toList()..sort();
    if (deduplicated.length > maxTdfArgsPerStmt) {
      _failLimitExceeded(
        'Directive "labels" exceeds maximum of $maxTdfArgsPerStmt arguments.',
      );
    }
    return deduplicated.join(' ');
  }

  /// Formats a `suspended` directive argument string for [task], or returns `null` when omitted.
  static String? _formatSuspendedValue(TaskItem task) {
    String? base;
    if (task.isSuspendedForever) {
      base = 'forever';
    } else if (task.suspendedAt case final suspended?) {
      base = _formatExplicitSecondsUtcTimestamp(suspended);
    }
    if (base == null) {
      return null;
    }
    final note = task.suspendedNote;
    if (note != null && note.isNotEmpty) {
      return '$base ${_escapeBoundedQuoted(note, maxTdfNoteLength, 'Suspended note')}';
    }
    return base;
  }

  /// Formats a UTC [timestamp] as `YYYY-MM-DD HH:MM` when `second == 0`, else `YYYY-MM-DD HH:MM:SS`.
  static String _formatUtcTimestamp(DateTime timestamp) {
    final utc = timestamp.toUtc();
    final year = utc.year.toString().padLeft(4, '0');
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    final hour = utc.hour.toString().padLeft(2, '0');
    final minute = utc.minute.toString().padLeft(2, '0');
    if (utc.second == 0) {
      return '$year-$month-$day $hour:$minute';
    }
    final second = utc.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute:$second';
  }

  /// Adds [addedBlocks] to [currentTotal] and enforces `MAX_BLOCKS_PER_DOC = 4096`.
  static int _incrementBlockCount(int currentTotal, int addedBlocks) {
    final nextTotal = currentTotal + addedBlocks;
    if (nextTotal > maxTdfBlocksPerDoc) {
      _failLimitExceeded(
        'Canonical output exceeds maximum of $maxTdfBlocksPerDoc blocks.',
      );
    }
    return nextTotal;
  }

  /// Orders and coalesces [conditions] canonically and enforces `MAX_CONDITION_RULES_PER_ENTITY` and `MAX_LOCATION_REFS_PER_ENTITY`.
  static List<TaskCondition> _orderConditionsCanonically(
    List<TaskCondition> conditions,
  ) {
    if (conditions.isEmpty) {
      return const <TaskCondition>[];
    }
    if (conditions.length > maxTdfConditionRulesPerEntity) {
      _failLimitExceeded(
        'Condition rules exceed maximum of $maxTdfConditionRulesPerEntity.',
      );
    }
    var rawLocationRefs = 0;
    for (final rule in conditions) {
      if (rule case final LocationTaskCondition locationCondition) {
        rawLocationRefs += locationCondition.locationIds.length;
        if (rawLocationRefs > maxTdfLocationRefsPerEntity) {
          _failLimitExceeded(
            'Condition exceeds maximum of $maxTdfLocationRefsPerEntity location references.',
          );
        }
      }
    }
    if (conditions.any((rule) => rule is GlobalResetTaskCondition)) {
      return const <TaskCondition>[GlobalResetTaskCondition()];
    }
    final coalesced = TdfDirectiveParser.coalesceLocationConditions(conditions);
    final dayRules = <TaskCondition>[];
    final timeRules = <TaskCondition>[];
    final locationRules = <TaskCondition>[];
    for (final rule in coalesced) {
      _appendConditionToGroupBucket(rule, dayRules, timeRules, locationRules);
    }
    return <TaskCondition>[...dayRules, ...timeRules, ...locationRules];
  }

  /// Emits a `condition { ... }` sub-block with `$W_{\text{cond}}$`-aligned rule keys (`TDF-SER-004`).
  static void _serializeConditionBlock(
    StringBuffer buffer,
    List<TaskCondition> ordered,
  ) {
    for (final rule in ordered) {
      _validateConditionArgsBound(rule, isInline: false);
    }
    final parts = <({String key, String args})>[
      for (final rule in ordered) _formatConditionRuleParts(rule),
    ];
    var maxKeyLen = 0;
    for (final part in parts) {
      if (part.key.length > maxKeyLen) {
        maxKeyLen = part.key.length;
      }
    }
    buffer.writeln('    condition {');
    for (final part in parts) {
      buffer.writeln('        ${part.key.padRight(maxKeyLen)} ${part.args}');
    }
    buffer.writeln('    }');
  }

  /// Emits the root-level `deleted` block when `generation > 0` or records exist, returning emitted block count (`0` or `1`).
  static int _serializeDeletedBlock(
    StringBuffer buffer,
    TdfDeletedBlock deletedBlock,
  ) {
    if (deletedBlock.isDefaultEmpty) {
      return 0;
    }
    if (deletedBlock.generation > maxTdfSyncGeneration) {
      _failLimitExceeded(
        'Deleted generation exceeds maximum of $maxTdfSyncGeneration.',
      );
    }
    if (deletedBlock.tasks.length +
            deletedBlock.labels.length +
            deletedBlock.locations.length >
        maxTdfDeletedRecords) {
      _failLimitExceeded(
        'Deleted block exceeds maximum of $maxTdfDeletedRecords records.',
      );
    }
    buffer
      ..writeln()
      ..writeln('deleted {')
      ..writeln('    generation ${deletedBlock.generation}');
    final sortedTasks = List<TdfDeletedTaskRecord>.from(deletedBlock.tasks)
      ..sort((a, b) => a.taskId.compareTo(b.taskId));
    for (final record in sortedTasks) {
      if (record.completionsCheckpoint > maxTdfCompletions) {
        _failLimitExceeded(
          'Deleted task checkpoint exceeds maximum of $maxTdfCompletions.',
        );
      }
      final timestamp = _formatExplicitSecondsUtcTimestamp(record.deletedAt);
      if (record.completionsCheckpoint > 0) {
        buffer.writeln(
          '    task ${record.taskId} $timestamp ${record.completionsCheckpoint}',
        );
      } else {
        buffer.writeln('    task ${record.taskId} $timestamp');
      }
    }
    final sortedLabels = List<TdfDeletedLabelRecord>.from(deletedBlock.labels)
      ..sort((a, b) => a.labelId.compareTo(b.labelId));
    for (final record in sortedLabels) {
      final timestamp = _formatExplicitSecondsUtcTimestamp(record.deletedAt);
      buffer.writeln('    label ${record.labelId} $timestamp');
    }
    final sortedLocations = List<TdfDeletedLocationRecord>.from(
      deletedBlock.locations,
    )..sort((a, b) => a.locationId.compareTo(b.locationId));
    for (final record in sortedLocations) {
      final timestamp = _formatExplicitSecondsUtcTimestamp(record.deletedAt);
      buffer.writeln('    location ${record.locationId} $timestamp');
    }
    buffer.writeln('}');
    return 1;
  }

  /// Emits a `label <id> [scoped] { ... }` block in the 6-position canonical order, returning emitted block count (`1` or `2`).
  static int _serializeLabel(StringBuffer buffer, TdfLabel label) {
    if (label.links.length > maxTdfLinksPerLabel) {
      _failLimitExceeded(
        'Label exceeds maximum of $maxTdfLinksPerLabel links.',
      );
    }
    final orderedConditions = _orderConditionsCanonically(label.conditions);
    final lines = <({String key, String value})>[
      (
        key: 'name',
        value: _escapeBoundedQuoted(label.name, maxTdfTextLength, 'Label name'),
      ),
      if (label.color case final color?)
        (key: 'color', value: _escapeQuoted(color.toUpperCase())),
      if (label.note case final note? when note.isNotEmpty)
        (
          key: 'note',
          value: _escapeBoundedQuoted(note, maxTdfNoteLength, 'Label note'),
        ),
      if (label.modifiedAt case final modified?)
        (key: 'modified', value: _formatUtcTimestamp(modified)),
      for (final link in label.links)
        (
          key: 'link',
          value:
              '${_escapeBoundedQuoted(link.title, maxTdfTextLength, 'Link title')} '
              '${_escapeBoundedQuoted(link.uri, maxTdfUriLength, 'Link URI')}',
        ),
    ];
    if (orderedConditions.length == 1) {
      _validateConditionArgsBound(orderedConditions.single, isInline: true);
      final part = _formatConditionRuleParts(orderedConditions.single);
      final inlineValue = part.args.isEmpty
          ? part.key
          : '${part.key} ${part.args}';
      lines.add((key: 'condition', value: inlineValue));
    }
    final hasConditionBlock = orderedConditions.length > 1;
    final directStmtCount = lines.length + (hasConditionBlock ? 1 : 0);
    if (directStmtCount > maxTdfStmtsPerBlock) {
      _failLimitExceeded(
        'Label block exceeds maximum of $maxTdfStmtsPerBlock direct child statements.',
      );
    }
    final scopedSuffix = label.isScoped ? ' scoped' : '';
    buffer.writeln('label ${label.id}$scopedSuffix {');
    _writeAlignedDirectives(buffer, lines);
    if (hasConditionBlock) {
      _serializeConditionBlock(buffer, orderedConditions);
    }
    buffer.writeln('}');
    return hasConditionBlock ? 2 : 1;
  }

  /// Emits a `location <id> { ... }` block in the 6-position canonical order, returning `1`.
  static int _serializeLocation(StringBuffer buffer, TdfLocation location) {
    if (location.radius > maxTdfLocationRadius) {
      _failLimitExceeded(
        'Location radius exceeds maximum of $maxTdfLocationRadius meters.',
      );
    }
    final latitudeText = location.latitudeText;
    final longitudeText = location.longitudeText;
    final radiusText = location.radiusText;
    _validateNumberLength(latitudeText, 'Location latitude');
    _validateNumberLength(longitudeText, 'Location longitude');
    _validateNumberLength(radiusText, 'Location radius');
    final lines = <({String key, String value})>[
      (
        key: 'name',
        value: _escapeBoundedQuoted(
          location.name,
          maxTdfTextLength,
          'Location name',
        ),
      ),
      if (location.note case final note? when note.isNotEmpty)
        (
          key: 'note',
          value: _escapeBoundedQuoted(note, maxTdfNoteLength, 'Location note'),
        ),
      if (location.source case final source? when source.isNotEmpty)
        (
          key: 'source',
          value: _escapeBoundedQuoted(
            source,
            maxTdfTextLength,
            'Location source',
          ),
        ),
      (key: 'coordinates', value: '$latitudeText $longitudeText'),
      (key: 'radius', value: radiusText),
      if (location.modifiedAt case final modified?)
        (key: 'modified', value: _formatUtcTimestamp(modified)),
    ];
    buffer.writeln('location ${location.id} {');
    _writeAlignedDirectives(buffer, lines);
    buffer.writeln('}');
    return 1;
  }

  /// Emits the root-level `queue` block when non-empty or `modified != epoch`, returning emitted block count (`0` or `1`).
  static int _serializeQueueBlock(
    StringBuffer buffer,
    TdfQueueBlock queueBlock,
  ) {
    if (queueBlock.isDefaultEmpty) {
      return 0;
    }
    if (queueBlock.taskIds.length > maxTdfQueueEntries) {
      _failLimitExceeded(
        'Queue block exceeds maximum of $maxTdfQueueEntries entries.',
      );
    }
    buffer
      ..writeln()
      ..writeln('queue {')
      ..writeln(
        '    modified ${_formatExplicitSecondsUtcTimestamp(queueBlock.modifiedAt)}',
      );
    for (final taskId in queueBlock.taskIds) {
      buffer.writeln('    task $taskId');
    }
    buffer.writeln('}');
    return 1;
  }

  /// Emits a `task <id> [priority] { ... }` block in the 16-position canonical order, returning emitted block count (`1..3`).
  static int _serializeTask(StringBuffer buffer, TaskItem task) {
    if (task.links.length > maxTdfLinksPerTask) {
      _failLimitExceeded('Task exceeds maximum of $maxTdfLinksPerTask links.');
    }
    if (task.history.length > maxTdfHistoryPerTask) {
      _failLimitExceeded(
        'Task exceeds maximum of $maxTdfHistoryPerTask history entries.',
      );
    }
    if (task.completions > maxTdfCompletions) {
      _failLimitExceeded(
        'Task completions exceed maximum of $maxTdfCompletions.',
      );
    }
    if (task.repeatRule case final repeat?
        when repeat.count > maxTdfRepeatCount ||
            repeat.leadDays > maxTdfRepeatCount) {
      _failLimitExceeded(
        'Task repeat count exceeds maximum of $maxTdfRepeatCount.',
      );
    }

    final orderedConditions = _orderConditionsCanonically(task.conditions);
    final suspendedValue = _formatSuspendedValue(task);
    final lines = <({String key, String value})>[
      (
        key: 'name',
        value: _escapeBoundedQuoted(task.title, maxTdfTextLength, 'Task name'),
      ),
      if (task.note case final note? when note.isNotEmpty)
        (
          key: 'note',
          value: _escapeBoundedQuoted(note, maxTdfNoteLength, 'Task note'),
        ),
      (key: 'created', value: _formatUtcTimestamp(task.createdAt)),
      if (task.completedAt case final finished?)
        (key: 'finished', value: _formatUtcTimestamp(finished)),
      if (task.modifiedAt case final modified?)
        (key: 'modified', value: _formatUtcTimestamp(modified)),
      if (task.completions > 0)
        (key: 'completions', value: '${task.completions}'),
      if (task.repeatRule case final repeat?)
        (key: 'repeat', value: repeat.toTdfDirectiveArgs()),
      if (task.labelIds.isNotEmpty)
        (key: 'labels', value: _formatLabelsValue(task.labelIds)),
      if (task.dependencies.isNotEmpty)
        (key: 'blocked', value: _formatBlockedValue(task.dependencies)),
      if (suspendedValue != null) (key: 'suspended', value: suspendedValue),
      if (task.dueAt case final due?)
        (
          key: 'due',
          value: _formatDueValue(
            due,
            dueAnchor: task.dueAnchor,
            isPassive: task.isDuePassive,
            note: task.dueNote,
          ),
        ),
      if (task.origin case final origin?)
        (
          key: 'origin',
          value:
              '${_escapeBoundedQuoted(origin.namespace, maxTdfTextLength, 'Origin namespace')} '
              '${_escapeBoundedQuoted(origin.externalKey, maxTdfTextLength, 'Origin key')}',
        ),
      for (final link in task.links)
        (
          key: 'link',
          value:
              '${_escapeBoundedQuoted(link.title, maxTdfTextLength, 'Link title')} '
              '${_escapeBoundedQuoted(link.uri, maxTdfUriLength, 'Link URI')}',
        ),
      for (final entry in task.history)
        (
          key: 'history',
          value:
              '${_formatExplicitSecondsUtcTimestamp(entry.timestampUtc)} '
              '${_escapeBoundedQuoted(entry.text, maxTdfTextLength, 'History text')}',
        ),
    ];

    if (orderedConditions.length == 1) {
      _validateConditionArgsBound(orderedConditions.single, isInline: true);
      final part = _formatConditionRuleParts(orderedConditions.single);
      final inlineValue = part.args.isEmpty
          ? part.key
          : '${part.key} ${part.args}';
      lines.add((key: 'condition', value: inlineValue));
    }

    final hasConditionBlock = orderedConditions.length > 1;
    final hasSubtasksBlock = task.subtasks.isNotEmpty;
    final directStmtCount =
        lines.length + (hasConditionBlock ? 1 : 0) + (hasSubtasksBlock ? 1 : 0);
    if (directStmtCount > maxTdfStmtsPerBlock) {
      _failLimitExceeded(
        'Task block exceeds maximum of $maxTdfStmtsPerBlock direct child statements.',
      );
    }
    if (hasSubtasksBlock && task.subtasks.length > maxTdfStmtsPerBlock) {
      _failLimitExceeded(
        'Subtasks block exceeds maximum of $maxTdfStmtsPerBlock steps.',
      );
    }

    final prioritySuffix = task.isPriority ? ' priority' : '';
    buffer.writeln('task ${task.id}$prioritySuffix {');
    _writeAlignedDirectives(buffer, lines);

    if (hasConditionBlock) {
      _serializeConditionBlock(buffer, orderedConditions);
    }
    if (hasSubtasksBlock) {
      final autoFinishSuffix = task.subtasksAutoFinish ? ' auto-finish' : '';
      final hasFalseStep = task.subtasks.any((step) => !step.isCompleted);
      final boolPadWidth = hasFalseStep ? 5 : 4;
      buffer.writeln('    subtasks$autoFinishSuffix {');
      for (final step in task.subtasks) {
        final doneStr = (step.isCompleted ? 'true' : 'false').padRight(
          boolPadWidth,
        );
        final escapedTitle = _escapeBoundedQuoted(
          step.title,
          maxTdfTextLength,
          'Subtask step title',
        );
        buffer.writeln('        step $doneStr $escapedTitle');
      }
      buffer.writeln('    }');
    }
    buffer.writeln('}');
    return 1 + (hasConditionBlock ? 1 : 0) + (hasSubtasksBlock ? 1 : 0);
  }

  /// Enforces `MAX_ARGS_PER_STMT = 64` on a serialized condition rule (`TDF-VAL-002`, `TDF-SER-001`).
  static void _validateConditionArgsBound(
    TaskCondition condition, {
    required bool isInline,
  }) {
    if (condition case final DayTaskCondition dayCondition) {
      final maxDayTokens = isInline ? maxTdfArgsPerStmt - 1 : maxTdfArgsPerStmt;
      if (dayCondition.dayTokens.length > maxDayTokens) {
        _failLimitExceeded(
          'Condition "day" exceeds maximum of $maxTdfArgsPerStmt statement arguments.',
        );
      }
    }
  }

  /// Validates that formatted numeric token [value] does not exceed `MAX_NUMBER_LENGTH = 24` ASCII characters (`TDF-VAL-002`).
  static void _validateNumberLength(String value, String fieldName) {
    if (value.length > maxTdfNumberLength) {
      _failLimitExceeded(
        '$fieldName exceeds maximum of $maxTdfNumberLength characters.',
      );
    }
  }

  /// Validates that serialized canonical output does not exceed `MAX_FILE_BYTES` or `MAX_LINE_COUNT` (`TDF-SER-001`).
  static void _validateOutputBounds(String output) {
    if (!TdfScanner.isUtf8ByteLengthWithinBound(output, maxTdfFileBytes)) {
      _failLimitExceeded(
        'Canonical output exceeds maximum of $maxTdfFileBytes bytes.',
      );
    }
    var lineCount = 0;
    for (var i = 0; i < output.length; i++) {
      if (output.codeUnitAt(i) == 0x0A) {
        lineCount++;
        if (lineCount > maxTdfLineCount) {
          throw TdfException(
            kind: TdfErrorKind.limitExceeded,
            line: lineCount,
            message:
                'Canonical output exceeds maximum of $maxTdfLineCount lines.',
          );
        }
      }
    }
    if (output.isNotEmpty && output.codeUnitAt(output.length - 1) != 0x0A) {
      lineCount++;
      if (lineCount > maxTdfLineCount) {
        throw TdfException(
          kind: TdfErrorKind.limitExceeded,
          line: lineCount,
          message:
              'Canonical output exceeds maximum of $maxTdfLineCount lines.',
        );
      }
    }
  }

  /// Validates that [value] contains valid Unicode scalars and does not exceed [maxScalars] (`TDF-TYPE-001`, `TDF-SER-001`).
  static void _validateScalarLength(
    String value,
    int maxScalars,
    String fieldName,
  ) {
    final scalarCount = TdfCalendar.countUnicodeScalars(value);
    if (scalarCount == null) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: 1,
        message: '$fieldName contains an unpaired UTF-16 surrogate.',
      );
    }
    if (scalarCount > maxScalars) {
      _failLimitExceeded(
        '$fieldName exceeds maximum of $maxScalars Unicode scalar values.',
      );
    }
  }

  /// Emits depth-`1` single-line directives aligned uniformly to $W_{\text{dir}}$ (`TDF-SER-004`).
  static void _writeAlignedDirectives(
    StringBuffer buffer,
    List<({String key, String value})> lines,
  ) {
    var padWidth = 0;
    for (final line in lines) {
      if (line.key.length > padWidth) {
        padWidth = line.key.length;
      }
    }
    for (final line in lines) {
      buffer.writeln('    ${line.key.padRight(padWidth)} ${line.value}');
    }
  }

  /// Writes a single UTF-16 code unit into [buffer], escaping `\"`, `\\`, `\n`, `\r`, and `\t`.
  static void _writeEscapedCodeUnit(StringBuffer buffer, int unit) {
    switch (unit) {
      case 0x22:
        buffer.write(r'\"');
      case 0x5C:
        buffer.write(r'\\');
      case 0x0A:
        buffer.write(r'\n');
      case 0x0D:
        buffer.write(r'\r');
      case 0x09:
        buffer.write(r'\t');
      case _:
        buffer.writeCharCode(unit);
    }
  }
}
