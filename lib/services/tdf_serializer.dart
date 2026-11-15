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

import 'dart:convert';

import '../models/task_board.dart';
import '../models/task_item.dart';
import '../models/tdf_error.dart';
import '../models/tdf_location.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_sync_metadata.dart';
import 'tdf_directive_parser.dart';
import 'tdf_parser.dart';

/// Canonical TDF 0.7.0 (and optional `0.6.0`) serializer (`spec/TDF_SPEC_0.7.0.md` Sections 4 and 7.1).
abstract final class TdfSerializer {
  /// Serializes [board] into canonical TDF text under [targetSchema], validating all output bounds before returning.
  static String serialize(
    TaskBoard board, {
    TdfSchemaVersion targetSchema = TdfSchemaVersion.v070,
  }) {
    final versionHeader = targetSchema == TdfSchemaVersion.v060
        ? TdfBlockParser.legacyLoadableVersion060
        : TdfBlockParser.supportedVersion;
    final buffer = StringBuffer()..writeln('tdf $versionHeader');

    _serializeDeletedBlock(buffer, board.deletedBlock);
    _serializeQueueBlock(buffer, board.queueBlock);

    final sortedLabels = List<TdfLabel>.from(board.labels)
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final label in sortedLabels) {
      buffer.writeln();
      _serializeLabel(buffer, label, targetSchema);
    }

    if (board.locations.length > maxTdfLocations) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message:
            'Document exceeds maximum of $maxTdfLocations location blocks.',
      );
    }
    final sortedLocations = List<TdfLocation>.from(board.locations)
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final location in sortedLocations) {
      buffer.writeln();
      _serializeLocation(buffer, location);
    }

    final sortedTasks = List<TaskItem>.from(board.allTasks)
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final task in sortedTasks) {
      buffer.writeln();
      _serializeTask(buffer, task, targetSchema);
    }

    final output = buffer.toString();
    _validateOutputBounds(output);
    return output;
  }

  /// Escapes a string for a double-quoted TDF string literal (`\"`, `\\`, `\n`, `\r`, `\t`).
  static String _escapeQuoted(String value) {
    final buffer = StringBuffer('"');
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
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
    buffer.write('"');
    return buffer.toString();
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

  /// Formats a `due` directive argument string under [targetSchema].
  static String _formatDueValue(
    DateTime due,
    TdfSchemaVersion targetSchema, {
    required bool isPassive,
    required String? note,
  }) {
    final base = _formatExplicitSecondsUtcTimestamp(due);
    if (targetSchema == TdfSchemaVersion.v060) {
      return base;
    }
    final passiveSuffix = isPassive ? ' passive' : '';
    final noteSuffix = (note != null && note.isNotEmpty)
        ? ' ${_escapeQuoted(note)}'
        : '';
    return '$base$passiveSuffix$noteSuffix';
  }

  /// Formats a UTC [timestamp] with explicit seconds (`YYYY-MM-DD HH:MM:SS`) for `deleted`, `queue.modified`, `suspended`, `due`, and `history`.
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

  /// Formats a `repeat` rule without `0.7.0` `lead` arguments for `tdf 0.6.0` serialization.
  static String _formatLegacy060RepeatRule(TaskRepeatRule rule) {
    final clockStr = rule.clock.formatCanonical();
    if (clockStr.isEmpty) {
      return '${rule.count} ${rule.unit.tdfToken}';
    }
    return '${rule.count} ${rule.unit.tdfToken} $clockStr';
  }

  /// Formats a `suspended` directive argument string for [task] under [targetSchema], or returns `null` when omitted.
  static String? _formatSuspendedValue(
    TaskItem task,
    TdfSchemaVersion targetSchema,
  ) {
    String? base;
    if (task.isSuspendedForever) {
      base = 'forever';
    } else if (task.suspendedAt case final suspended?) {
      base = _formatExplicitSecondsUtcTimestamp(suspended);
    }
    if (base == null || targetSchema == TdfSchemaVersion.v060) {
      return base;
    }
    final note = task.suspendedNote;
    if (note != null && note.isNotEmpty) {
      return '$base ${_escapeQuoted(note)}';
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

  /// Orders and coalesces [conditions] canonically: `any` first, else `day`, `time`, `location` (`spec/TDF_SPEC_0.6.0.md` Section 4.4.1 & 7.1).
  static List<TaskCondition> _orderConditionsCanonically(
    List<TaskCondition> conditions,
  ) {
    if (conditions.isEmpty) {
      return const <TaskCondition>[];
    }
    if (conditions.any((rule) => rule is GlobalResetTaskCondition)) {
      return const <TaskCondition>[GlobalResetTaskCondition()];
    }
    final coalesced = TdfDirectiveParser.coalesceLocationConditions(conditions);
    final dayRules = <TaskCondition>[];
    final timeRules = <TaskCondition>[];
    final locationRules = <TaskCondition>[];
    for (final rule in coalesced) {
      switch (rule.group) {
        case ConditionGroup.day:
          dayRules.add(rule);
        case ConditionGroup.time:
          timeRules.add(rule);
        case ConditionGroup.location:
          if (rule case final LocationTaskCondition loc
              when loc.locationIds.length > maxTdfLocationRefsPerEntity) {
            throw const TdfException(
              kind: TdfErrorKind.limitExceeded,
              line: 1,
              message:
                  'Condition exceeds maximum of $maxTdfLocationRefsPerEntity location references.',
            );
          }
          locationRules.add(rule);
        case null:
          break;
      }
    }
    return <TaskCondition>[...dayRules, ...timeRules, ...locationRules];
  }

  /// Emits a `condition { ... }` sub-block with aligned rule keys.
  static void _serializeConditionBlock(
    StringBuffer buffer,
    List<TaskCondition> ordered,
  ) {
    final parts = [for (final rule in ordered) _formatConditionRuleParts(rule)];
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

  /// Emits the root-level `deleted` block in canonical order when non-empty or `generation > 0`.
  static void _serializeDeletedBlock(
    StringBuffer buffer,
    TdfDeletedBlock deletedBlock,
  ) {
    if (deletedBlock.isDefaultEmpty) {
      return;
    }
    if (deletedBlock.tasks.length +
            deletedBlock.labels.length +
            deletedBlock.locations.length >
        TdfDeletedBlock.maxDeletedRecords) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message:
            'Deleted block exceeds maximum of ${TdfDeletedBlock.maxDeletedRecords}.',
      );
    }
    buffer
      ..writeln()
      ..writeln('deleted {')
      ..writeln('    generation ${deletedBlock.generation}');
    final sortedTasks = List<TdfDeletedTaskRecord>.from(deletedBlock.tasks)
      ..sort((a, b) => a.taskId.compareTo(b.taskId));
    for (final record in sortedTasks) {
      final ts = _formatExplicitSecondsUtcTimestamp(record.deletedAt);
      if (record.completionsCheckpoint > 0) {
        buffer.writeln(
          '    task ${record.taskId} $ts ${record.completionsCheckpoint}',
        );
      } else {
        buffer.writeln('    task ${record.taskId} $ts');
      }
    }
    final sortedLabels = List<TdfDeletedLabelRecord>.from(deletedBlock.labels)
      ..sort((a, b) => a.labelId.compareTo(b.labelId));
    for (final record in sortedLabels) {
      final ts = _formatExplicitSecondsUtcTimestamp(record.deletedAt);
      buffer.writeln('    label ${record.labelId} $ts');
    }
    final sortedLocations = List<TdfDeletedLocationRecord>.from(
      deletedBlock.locations,
    )..sort((a, b) => a.locationId.compareTo(b.locationId));
    for (final record in sortedLocations) {
      final ts = _formatExplicitSecondsUtcTimestamp(record.deletedAt);
      buffer.writeln('    location ${record.locationId} $ts');
    }
    buffer.writeln('}');
  }

  /// Emits a `label <id> [scoped] { ... }` block in the 6-position canonical order (`spec/TDF_SPEC_0.7.0.md` Section 4.2 & 7.1).
  static void _serializeLabel(
    StringBuffer buffer,
    TdfLabel label,
    TdfSchemaVersion targetSchema,
  ) {
    final isV070 = targetSchema == TdfSchemaVersion.v070;
    if (isV070 && label.links.length > maxTdfLinksPerLabel) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message: 'Label exceeds maximum of $maxTdfLinksPerLabel links.',
      );
    }

    final orderedConditions = _orderConditionsCanonically(label.conditions);
    if (orderedConditions.length > maxTdfConditionRulesPerEntity) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message:
            'Condition block exceeds maximum of $maxTdfConditionRulesPerEntity rules.',
      );
    }

    final scalarLines = <({String key, String value})>[
      (key: 'name', value: _escapeQuoted(label.name)),
      if (label.color case final color?)
        (key: 'color', value: _escapeQuoted(color)),
      if (label.note case final note? when note.isNotEmpty)
        (key: 'note', value: _escapeQuoted(note)),
      if (label.modifiedAt case final modified?
          when modified.toUtc() != TdfLabel.defaultModifiedAt)
        (key: 'modified', value: _formatUtcTimestamp(modified)),
      if (isV070)
        for (final link in label.links)
          (
            key: 'link',
            value: '${_escapeQuoted(link.title)} ${_escapeQuoted(link.uri)}',
          ),
    ];

    final maxAllowedStmts = isV070
        ? maxTdfStmtsPerBlock
        : maxTdfLegacy060StmtsPerBlock;
    final directStmtCount = isV070
        ? label.canonicalDirectChildStatementCount
        : scalarLines.length + (orderedConditions.isNotEmpty ? 1 : 0);
    if (directStmtCount > maxAllowedStmts) {
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message:
            'Label block exceeds maximum of $maxAllowedStmts direct child statements.',
      );
    }

    final scopedSuffix = label.isScoped ? ' scoped' : '';
    buffer.writeln('label ${label.id}$scopedSuffix {');

    String? inlineConditionValue;
    if (orderedConditions.length == 1) {
      final part = _formatConditionRuleParts(orderedConditions.single);
      inlineConditionValue = part.args.isEmpty
          ? part.key
          : '${part.key} ${part.args}';
    }

    var scalarPadWidth = 0;
    for (final line in scalarLines) {
      if (line.key.length > scalarPadWidth) {
        scalarPadWidth = line.key.length;
      }
    }
    if (scalarLines.length == 1 && inlineConditionValue != null) {
      scalarPadWidth = 'condition'.length;
    }

    for (final line in scalarLines) {
      buffer.writeln('    ${line.key.padRight(scalarPadWidth)} ${line.value}');
    }
    if (inlineConditionValue != null) {
      buffer.writeln('    condition $inlineConditionValue');
    } else if (orderedConditions.length > 1) {
      _serializeConditionBlock(buffer, orderedConditions);
    }
    buffer.writeln('}');
  }

  /// Emits a `location <id> { ... }` block in the 6-position canonical order (`spec/TDF_SPEC_0.6.0.md` Section 4.3 & 7.1).
  static void _serializeLocation(StringBuffer buffer, TdfLocation location) {
    buffer.writeln('location ${location.id} {');
    final lines = <({String key, String value})>[
      (key: 'name', value: _escapeQuoted(location.name)),
      if (location.note case final note? when note.isNotEmpty)
        (key: 'note', value: _escapeQuoted(note)),
      if (location.source case final source? when source.isNotEmpty)
        (key: 'source', value: _escapeQuoted(source)),
      (
        key: 'coordinates',
        value: '${location.latitudeText} ${location.longitudeText}',
      ),
      (key: 'radius', value: location.radiusText),
      if (location.modifiedAt case final modified?
          when modified.toUtc() != TdfLocation.defaultModifiedAt)
        (key: 'modified', value: _formatUtcTimestamp(modified)),
    ];
    var maxKeyLen = 0;
    for (final line in lines) {
      if (line.key.length > maxKeyLen) {
        maxKeyLen = line.key.length;
      }
    }
    for (final line in lines) {
      buffer.writeln('    ${line.key.padRight(maxKeyLen)} ${line.value}');
    }
    buffer.writeln('}');
  }

  /// Emits the root-level `queue` block in canonical order when non-empty or `modified > epoch`.
  static void _serializeQueueBlock(
    StringBuffer buffer,
    TdfQueueBlock queueBlock,
  ) {
    if (queueBlock.isDefaultEmpty) {
      return;
    }
    if (queueBlock.taskIds.length > TdfQueueBlock.maxQueueEntries) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message:
            'Queue block exceeds maximum of ${TdfQueueBlock.maxQueueEntries} entries.',
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
  }

  /// Emits a `task <id> [priority] { ... }` block in the 16-position canonical order (`spec/TDF_SPEC_0.7.0.md` Section 4.1.2 & 7.1).
  static void _serializeTask(
    StringBuffer buffer,
    TaskItem task,
    TdfSchemaVersion targetSchema,
  ) {
    final isV070 = targetSchema == TdfSchemaVersion.v070;
    if (task.links.length > TaskLink.maxLinksPerTask) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message: 'Task exceeds maximum of ${TaskLink.maxLinksPerTask} links.',
      );
    }
    if (isV070 && task.history.length > maxTdfHistoryPerTask) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message:
            'Task exceeds maximum of $maxTdfHistoryPerTask history entries.',
      );
    }

    final orderedConditions = _orderConditionsCanonically(task.conditions);
    if (orderedConditions.length > maxTdfConditionRulesPerEntity) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message:
            'Condition block exceeds maximum of $maxTdfConditionRulesPerEntity rules.',
      );
    }

    final suspendedValue = _formatSuspendedValue(task, targetSchema);
    final lines = <({String key, String value})>[
      (key: 'name', value: _escapeQuoted(task.title)),
      if (task.note case final note? when note.isNotEmpty)
        (key: 'note', value: _escapeQuoted(note)),
      (key: 'created', value: _formatUtcTimestamp(task.createdAt)),
      if (task.completedAt case final finished?)
        (key: 'finished', value: _formatUtcTimestamp(finished)),
      if (task.modifiedAt case final modified?)
        (key: 'modified', value: _formatUtcTimestamp(modified)),
      if (task.completions > 0)
        (key: 'completions', value: '${task.completions}'),
      if (task.repeatRule case final repeat?)
        (
          key: 'repeat',
          value: isV070
              ? repeat.toTdfDirectiveArgs()
              : _formatLegacy060RepeatRule(repeat),
        ),
      if (task.labelIds.isNotEmpty)
        (
          key: 'labels',
          value: (List<String>.from(task.labelIds)..sort()).join(' '),
        ),
      if (task.dependencies.isNotEmpty)
        (
          key: 'blocked',
          value: [
            for (final dep in (List<TdfTaskDependency>.from(
              task.dependencies,
            )..sort((a, b) => a.taskId.compareTo(b.taskId))))
              dep.formatCanonical(),
          ].join(' '),
        ),
      if (suspendedValue != null) (key: 'suspended', value: suspendedValue),
      if (task.dueAt case final due?)
        (
          key: 'due',
          value: _formatDueValue(
            due,
            targetSchema,
            isPassive: task.isDuePassive,
            note: task.dueNote,
          ),
        ),
      if (task.origin case final origin?)
        (
          key: 'origin',
          value:
              '${_escapeQuoted(origin.namespace)} ${_escapeQuoted(origin.externalKey)}',
        ),
      for (final link in task.links)
        (
          key: 'link',
          value: '${_escapeQuoted(link.title)} ${_escapeQuoted(link.uri)}',
        ),
      if (isV070)
        for (final entry in task.history)
          (
            key: 'history',
            value:
                '${_formatExplicitSecondsUtcTimestamp(entry.timestampUtc)} ${_escapeQuoted(entry.text)}',
          ),
    ];

    if (orderedConditions.length == 1) {
      final part = _formatConditionRuleParts(orderedConditions.single);
      final inlineValue = part.args.isEmpty
          ? part.key
          : '${part.key} ${part.args}';
      lines.add((key: 'condition', value: inlineValue));
    }

    final maxAllowedStmts = isV070
        ? maxTdfStmtsPerBlock
        : maxTdfLegacy060StmtsPerBlock;
    final directStmtCount = isV070
        ? task.canonicalDirectChildStatementCount
        : lines.length +
              (orderedConditions.length > 1 ? 1 : 0) +
              (task.subtasks.isNotEmpty ? 1 : 0);
    if (directStmtCount > maxAllowedStmts) {
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message:
            'Task block exceeds maximum of $maxAllowedStmts direct child statements.',
      );
    }
    if (task.subtasks.isNotEmpty && task.subtasks.length > maxAllowedStmts) {
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message: 'Subtasks block exceeds maximum of $maxAllowedStmts steps.',
      );
    }

    final prioritySuffix = task.isPriority ? ' priority' : '';
    buffer.writeln('task ${task.id}$prioritySuffix {');

    var maxKeyLen = 0;
    for (final line in lines) {
      if (line.key.length > maxKeyLen) {
        maxKeyLen = line.key.length;
      }
    }
    for (final line in lines) {
      buffer.writeln('    ${line.key.padRight(maxKeyLen)} ${line.value}');
    }

    if (orderedConditions.length > 1) {
      _serializeConditionBlock(buffer, orderedConditions);
    }

    if (task.subtasks.isNotEmpty) {
      final autoFinishSuffix = task.subtasksAutoFinish ? ' auto-finish' : '';
      final hasFalseStep = task.subtasks.any((step) => !step.isCompleted);
      final boolPadWidth = hasFalseStep ? 5 : 4;
      buffer.writeln('    subtasks$autoFinishSuffix {');
      for (final step in task.subtasks) {
        final doneStr = (step.isCompleted ? 'true' : 'false').padRight(
          boolPadWidth,
        );
        buffer.writeln('        step $doneStr ${_escapeQuoted(step.title)}');
      }
      buffer.writeln('    }');
    }

    buffer.writeln('}');
  }

  /// Validates that the serialized canonical output does not exceed `MAX_FILE_BYTES` or `MAX_LINE_COUNT` (`spec/TDF_SPEC_0.6.0.md` Section 7.1).
  static void _validateOutputBounds(String output) {
    final byteLength = utf8.encode(output).length;
    if (byteLength > maxTdfFileBytes) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message: 'Canonical output exceeds maximum of $maxTdfFileBytes bytes.',
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
}
