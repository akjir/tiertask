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

import 'package:flutter/foundation.dart';

import '../models/task_board.dart';
import '../models/task_item.dart';
import '../models/tdf_error.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_sync_metadata.dart';

/// Stateless canonical `tdf 0.5.1` serializer for `TDF_SPEC.md` Section 7.1 and Section 9.
@immutable
class TdfSerializer {
  /// Private constructor to prevent instantiation.
  const TdfSerializer._();

  /// Canonical TDF specification version string (`tdf 0.5.1`).
  static const String supportedVersion = '0.5.1';

  /// Escapes `\` and `"` and control characters in [value] for a TDF double-quoted string literal.
  static String escapeQuotedString(String value) {
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
        default:
          buffer.writeCharCode(unit);
      }
    }
    buffer.write('"');
    return buffer.toString();
  }

  /// Serializes [board] into a canonical `LF`-terminated `tdf 0.5.1` document string and validates Section 7.1 bounds.
  static String serialize(TaskBoard board) {
    final hasDeleted = !board.deletedBlock.isDefaultEmpty;
    final hasQueue = !board.queueBlock.isDefaultEmpty;
    if (!hasDeleted &&
        !hasQueue &&
        board.labels.isEmpty &&
        board.allTasks.isEmpty) {
      return 'tdf $supportedVersion\n';
    }
    final buffer = StringBuffer('tdf $supportedVersion\n\n');
    if (hasDeleted) {
      _writeDeletedBlock(buffer, board.deletedBlock);
    }
    if (hasQueue) {
      _writeQueueBlock(buffer, board.queueBlock);
    }
    for (final label in board.labels) {
      _writeLabelBlock(buffer, label);
    }
    for (final task in board.allTasks) {
      _writeTaskBlock(buffer, task);
    }
    final output = buffer.toString();
    _validateCanonicalOutputBounds(output);
    return output;
  }

  /// Orders [conditions] into canonical `day`, `time`, and `location` groups per Section 4.3.1.
  static List<TaskCondition> _orderConditionsForSerialization(
    List<TaskCondition> conditions,
  ) {
    final globalResets = <TaskCondition>[];
    final dayRules = <TaskCondition>[];
    final timeRules = <TaskCondition>[];
    final locationRules = <TaskCondition>[];

    for (final rule in conditions) {
      switch (rule.group) {
        case null:
          globalResets.add(rule);
        case ConditionGroup.day:
          dayRules.add(rule);
        case ConditionGroup.time:
          timeRules.add(rule);
        case ConditionGroup.location:
          locationRules.add(rule);
      }
    }

    return <TaskCondition>[
      ...globalResets,
      ...dayRules,
      ...timeRules,
      ...locationRules,
    ];
  }

  /// Validates that [tdfContent] does not exceed [maxTdfFileBytes].
  static void _validateByteLimit(String tdfContent) {
    if (tdfContent.length > maxTdfFileBytes ||
        utf8.encode(tdfContent).length > maxTdfFileBytes) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message:
            'TDF document exceeds maximum file size of $maxTdfFileBytes bytes.',
      );
    }
  }

  /// Validates that serialized [output] obeys [maxTdfFileBytes] and [maxTdfLineCount] per Section 7.1.
  static void _validateCanonicalOutputBounds(String output) {
    _validateByteLimit(output);
    var lineCount = 0;
    for (var i = 0; i < output.length; i++) {
      if (output.codeUnitAt(i) == 0x0A) {
        lineCount++;
        if (lineCount > maxTdfLineCount) {
          throw TdfException(
            kind: TdfErrorKind.limitExceeded,
            line: lineCount,
            message:
                'Canonical TDF output exceeds maximum line count of $maxTdfLineCount.',
          );
        }
      }
    }
  }

  /// Writes canonical `condition` directive(s) or a `condition { ... }` sub-block to [buffer].
  static void _writeConditions(
    StringBuffer buffer,
    List<TaskCondition> conditions,
  ) {
    if (conditions.isEmpty) {
      return;
    }
    final ordered = _orderConditionsForSerialization(conditions);
    if (ordered.length == 1) {
      buffer.write('    condition ');
      buffer.write(ordered.first.toTdfDirectiveArgs());
      buffer.write('\n');
      return;
    }
    buffer.write('    condition {\n');
    for (final rule in ordered) {
      buffer.write('        ');
      buffer.write(rule.toTdfDirectiveArgs());
      buffer.write('\n');
    }
    buffer.write('    }\n');
  }

  /// Writes a canonical `deleted` block to [buffer] per Section 4.4.
  static void _writeDeletedBlock(
    StringBuffer buffer,
    TdfDeletedBlock deletedBlock,
  ) {
    buffer.write('deleted {\n    generation ');
    buffer.write(deletedBlock.generation);
    buffer.write('\n');
    for (final taskRecord in deletedBlock.tasks) {
      buffer.write('    task ');
      buffer.write(taskRecord.taskId);
      buffer.write(' ');
      buffer.write(
        TaskItem.formatTdfTimestampWithSeconds(taskRecord.deletedAt),
      );
      if (taskRecord.completionsCheckpoint > 0) {
        buffer.write(' ');
        buffer.write(taskRecord.completionsCheckpoint);
      }
      buffer.write('\n');
    }
    for (final labelRecord in deletedBlock.labels) {
      buffer.write('    label ');
      buffer.write(labelRecord.labelId);
      buffer.write(' ');
      buffer.write(
        TaskItem.formatTdfTimestampWithSeconds(labelRecord.deletedAt),
      );
      buffer.write('\n');
    }
    buffer.write('}\n\n');
  }

  /// Writes a canonical `label` block to [buffer].
  static void _writeLabelBlock(StringBuffer buffer, TdfLabel label) {
    buffer.write('label ');
    buffer.write(label.id);
    buffer.write(' {\n    name ');
    buffer.write(escapeQuotedString(label.name));
    buffer.write('\n');
    if (label.color case final color?) {
      buffer.write('    color ');
      buffer.write(escapeQuotedString(color));
      buffer.write('\n');
    }
    if (label.note case final note?) {
      buffer.write('    note ');
      buffer.write(escapeQuotedString(note));
      buffer.write('\n');
    }
    if (label.modifiedAt case final modifiedAt?) {
      buffer.write('    modified ');
      buffer.write(TaskItem.formatTdfTimestamp(modifiedAt));
      buffer.write('\n');
    }
    _writeConditions(buffer, label.conditions);
    buffer.write('}\n\n');
  }

  /// Writes a canonical `queue` block to [buffer] per Section 4.5.
  static void _writeQueueBlock(StringBuffer buffer, TdfQueueBlock queueBlock) {
    buffer.write('queue {\n    modified ');
    buffer.write(TaskItem.formatTdfTimestampWithSeconds(queueBlock.modifiedAt));
    buffer.write('\n');
    for (final taskId in queueBlock.taskIds) {
      buffer.write('    task ');
      buffer.write(taskId);
      buffer.write('\n');
    }
    buffer.write('}\n\n');
  }

  /// Writes a canonical `task` block (including optional `condition` and `subtasks`) to [buffer] per Section 9.1.
  static void _writeTaskBlock(StringBuffer buffer, TaskItem task) {
    buffer.write('task ');
    buffer.write(task.id);
    if (task.isPriority) {
      buffer.write(' priority');
    }
    buffer.write(' {\n    name ');
    buffer.write(escapeQuotedString(task.title));
    buffer.write('\n');
    if (task.note case final note?) {
      buffer.write('    note ');
      buffer.write(escapeQuotedString(note));
      buffer.write('\n');
    }
    buffer.write('    created ');
    buffer.write(TaskItem.formatTdfTimestamp(task.createdAt));
    buffer.write('\n');
    if (task.completedAt case final completedAt?) {
      buffer.write('    finished ');
      buffer.write(TaskItem.formatTdfTimestamp(completedAt));
      buffer.write('\n');
    }
    if (task.modifiedAt case final modifiedAt?) {
      buffer.write('    modified ');
      buffer.write(TaskItem.formatTdfTimestamp(modifiedAt));
      buffer.write('\n');
    }
    if (task.completions > 0) {
      buffer.write('    completions ');
      buffer.write(task.completions);
      buffer.write('\n');
    }
    if (task.repeatRule case final repeatRule?) {
      buffer.write('    repeat ');
      buffer.write(repeatRule.toTdfDirectiveArgs());
      buffer.write('\n');
    }
    if (task.labelIds.isNotEmpty) {
      buffer.write('    labels ');
      buffer.write(task.labelIds.join(' '));
      buffer.write('\n');
    }
    if (task.dependencies.isNotEmpty) {
      final normalizedDeps = TdfTaskDependency.normalizeList(task.dependencies);
      buffer.write('    blocked ');
      buffer.write(
        normalizedDeps.map((dep) => dep.formatCanonical()).join(' '),
      );
      buffer.write('\n');
    }
    if (task.isSuspendedForever) {
      buffer.write('    suspended forever\n');
    } else if (task.suspendedAt case final suspendedAt?) {
      buffer.write('    suspended ');
      buffer.write(TaskItem.formatTdfTimestampWithSeconds(suspendedAt));
      buffer.write('\n');
    }
    for (final link in task.links) {
      buffer.write('    link ');
      buffer.write(escapeQuotedString(link.title));
      buffer.write(' ');
      buffer.write(escapeQuotedString(link.uri));
      buffer.write('\n');
    }
    _writeConditions(buffer, task.conditions);
    if (task.subtasks.isNotEmpty || task.subtasksAutoFinish) {
      buffer.write('    subtasks');
      if (task.subtasksAutoFinish) {
        buffer.write(' auto-finish');
      }
      buffer.write(' {\n');
      for (final step in task.subtasks) {
        buffer.write('        step ');
        buffer.write(step.isCompleted ? 'true ' : 'false ');
        buffer.write(escapeQuotedString(step.title));
        buffer.write('\n');
      }
      buffer.write('    }\n');
    }
    buffer.write('}\n\n');
  }
}
