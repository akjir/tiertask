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

import '../models/task_board.dart';
import '../models/task_item.dart';
import '../models/tdf_error.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_sync_metadata.dart';
import '../models/tdf_timezone.dart';
import 'tdf_historical_parser.dart';
import 'tdf_id_migration.dart';

/// Stateless serializer, bounds validator, and ID rewriter for historical TDF schemas.
@immutable
class TdfHistoricalSerializer {
  /// Prevents instantiation of this stateless service.
  const TdfHistoricalSerializer._();

  /// Rewrites noncanonical task and label IDs in [doc] using [TdfIdMigration.buildMigrationMap].
  static TdfHistoricalDocument rewriteNoncanonicalIds(
    TdfHistoricalDocument doc, {
    required String sourceVersion,
    required String targetVersion,
  }) {
    final existingCanonicalIds = <String>{};
    final nonCanonicalLabelIds = <String>{};
    final nonCanonicalTaskIds = <String>{};

    for (final label in doc.labels) {
      if (isValidLabelId(label.id)) {
        existingCanonicalIds.add(label.id);
      } else {
        nonCanonicalLabelIds.add(label.id);
      }
    }
    for (final task in doc.tasks) {
      _collectTaskIds(task, existingCanonicalIds, nonCanonicalTaskIds);
    }

    final mapping = TdfIdMigration.buildMigrationMap(
      existingCanonicalIds: existingCanonicalIds,
      nonCanonicalLabelIds: nonCanonicalLabelIds,
      nonCanonicalTaskIds: nonCanonicalTaskIds,
    );

    final mappedLabels = <TdfHistoricalLabel>[
      for (final label in doc.labels)
        label.withId(mapping.resolveLabelId(label.id)),
    ];
    final mappedTasks = <TdfHistoricalTask>[
      for (final task in doc.tasks)
        task.copyWith(
          id: mapping.resolveTaskId(task.id),
          labels: <String>[
            for (final labelId in task.labelIds)
              mapping.resolveLabelId(labelId),
          ],
          blockers: <String>[
            for (final blockerId in task.blockedByTaskIds)
              mapping.resolveTaskId(blockerId),
          ],
        ),
    ];

    return TdfHistoricalDocument(labels: mappedLabels, tasks: mappedTasks);
  }

  /// Serializes an intermediate `0.5.0` document in declaration order.
  static String serializeDocument050({
    required List<TdfLabel> labels,
    required List<({TaskItem task, DateTime? queuedAt})> tasks,
    required TdfQueueBlock queueBlock,
  }) {
    final hasQueue = !queueBlock.isDefaultEmpty;
    if (!hasQueue && labels.isEmpty && tasks.isEmpty) {
      return 'tdf 0.5.0\n';
    }
    final buffer = StringBuffer('tdf 0.5.0\n\n');
    if (hasQueue) {
      _writeQueue050(buffer, queueBlock);
    }
    for (final label in labels) {
      _writeLabel050(buffer, label);
    }
    for (final entry in tasks) {
      _writeTask050(buffer, entry.task, entry.queuedAt);
    }
    return buffer.toString();
  }

  /// Serializes an intermediate `0.5.1` [board] in canonical `0.5.1` order (`spec/TDF_SPEC_0.6.0.md` Section 10.6).
  static String serializeDocument051(TaskBoard board) {
    final buffer = StringBuffer('tdf 0.5.1\n\n');
    if (!board.deletedBlock.isDefaultEmpty) {
      buffer.write(
        'deleted {\n    generation ${board.deletedBlock.generation}\n',
      );
      final sortedTasks = List<TdfDeletedTaskRecord>.from(
        board.deletedBlock.tasks,
      )..sort((a, b) => a.taskId.compareTo(b.taskId));
      for (final record in sortedTasks) {
        final ts = TaskItem.formatTdfTimestampWithSeconds(record.deletedAt);
        if (record.completionsCheckpoint > 0) {
          buffer.write(
            '    task ${record.taskId} $ts ${record.completionsCheckpoint}\n',
          );
        } else {
          buffer.write('    task ${record.taskId} $ts\n');
        }
      }
      final sortedLabels = List<TdfDeletedLabelRecord>.from(
        board.deletedBlock.labels,
      )..sort((a, b) => a.labelId.compareTo(b.labelId));
      for (final record in sortedLabels) {
        final ts = TaskItem.formatTdfTimestampWithSeconds(record.deletedAt);
        buffer.write('    label ${record.labelId} $ts\n');
      }
      buffer.write('}\n\n');
    }
    if (!board.queueBlock.isDefaultEmpty) {
      _writeQueue050(buffer, board.queueBlock);
    }
    final sortedLabels = List<TdfLabel>.from(board.labels)
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final label in sortedLabels) {
      _writeLabel051(buffer, label);
    }
    final sortedTasks = List<TaskItem>.from(board.allTasks)
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final task in sortedTasks) {
      _writeTask051(buffer, task);
    }
    final output = buffer.toString();
    return output == 'tdf 0.5.1\n\n' ? 'tdf 0.5.1\n' : output;
  }

  /// Serializes an intermediate `0.3.0` or `0.4.0` document in declaration order.
  static String serializeHistoricalDocument({
    required String version,
    required List<TdfHistoricalLabel> labels,
    required List<TdfHistoricalTask> tasks,
  }) {
    if (labels.isEmpty && tasks.isEmpty) {
      return 'tdf $version\n';
    }
    final buffer = StringBuffer('tdf $version\n\n');
    for (final label in labels) {
      _writeHistoricalLabel(buffer, label);
    }
    for (final task in tasks) {
      _writeHistoricalTask(buffer, task);
    }
    return buffer.toString();
  }

  /// Validates target `0.5.0` condition count and text length bounds on [label] per Section 10.5.
  static void validateTargetLabelBounds(TdfHistoricalLabel label) {
    final nameScalars = TdfCalendar.countUnicodeScalars(label.name);
    if (nameScalars == null || nameScalars > maxTdfTextLength) {
      throw TdfException(
        kind: nameScalars == null
            ? TdfErrorKind.unexpectedToken
            : TdfErrorKind.limitExceeded,
        line: label.lineOf('name'),
        sourceVersion: '0.4.0',
        targetVersion: '0.5.0',
        message: 'Label name exceeds MAX_TEXT_LENGTH.',
      );
    }
    if (label.note case final note?) {
      final noteScalars = TdfCalendar.countUnicodeScalars(note);
      if (noteScalars == null || noteScalars > maxTdfNoteLength) {
        throw TdfException(
          kind: noteScalars == null
              ? TdfErrorKind.unexpectedToken
              : TdfErrorKind.limitExceeded,
          line: label.lineOf('note'),
          sourceVersion: '0.4.0',
          targetVersion: '0.5.0',
          message: 'Label note exceeds MAX_NOTE_LENGTH.',
        );
      }
    }
    if (label.conditions.length > maxTdfConditionRulesPerEntity) {
      final line = label.conditionLines.length > maxTdfConditionRulesPerEntity
          ? label.conditionLines[maxTdfConditionRulesPerEntity]
          : label.lineOf('header');
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: line,
        sourceVersion: '0.4.0',
        targetVersion: '0.5.0',
        message: 'Label exceeds MAX_CONDITION_RULES_PER_ENTITY (512).',
      );
    }
  }

  /// Validates target `0.5.0` condition count and text length bounds on [task] per Section 10.5.
  static void validateTargetTaskBounds(TdfHistoricalTask task) {
    final nameScalars = TdfCalendar.countUnicodeScalars(task.name);
    if (nameScalars == null || nameScalars > maxTdfTextLength) {
      throw TdfException(
        kind: nameScalars == null
            ? TdfErrorKind.unexpectedToken
            : TdfErrorKind.limitExceeded,
        line: task.lineOf('name'),
        sourceVersion: '0.4.0',
        targetVersion: '0.5.0',
        message: 'Task name exceeds MAX_TEXT_LENGTH.',
      );
    }
    if (task.note case final note?) {
      final noteScalars = TdfCalendar.countUnicodeScalars(note);
      if (noteScalars == null || noteScalars > maxTdfNoteLength) {
        throw TdfException(
          kind: noteScalars == null
              ? TdfErrorKind.unexpectedToken
              : TdfErrorKind.limitExceeded,
          line: task.lineOf('note'),
          sourceVersion: '0.4.0',
          targetVersion: '0.5.0',
          message: 'Task note exceeds MAX_NOTE_LENGTH.',
        );
      }
    }
    if (task.conditions.length > maxTdfConditionRulesPerEntity) {
      final line = task.conditionLines.length > maxTdfConditionRulesPerEntity
          ? task.conditionLines[maxTdfConditionRulesPerEntity]
          : task.lineOf('header');
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: line,
        sourceVersion: '0.4.0',
        targetVersion: '0.5.0',
        message: 'Task exceeds MAX_CONDITION_RULES_PER_ENTITY (512).',
      );
    }
  }

  /// Classifies a task ID and its prerequisite IDs into canonical or noncanonical sets.
  static void _collectTaskIds(
    TdfHistoricalTask task,
    Set<String> existingCanonicalIds,
    Set<String> nonCanonicalTaskIds,
  ) {
    if (isValidTaskId(task.id)) {
      existingCanonicalIds.add(task.id);
    } else {
      nonCanonicalTaskIds.add(task.id);
    }
    for (final blockerId in task.blockedByTaskIds) {
      if (isValidTaskId(blockerId)) {
        existingCanonicalIds.add(blockerId);
      } else {
        nonCanonicalTaskIds.add(blockerId);
      }
    }
  }

  /// Escapes a string value for double-quoted TDF output.
  static String _escapeQuoted(String input) {
    final buffer = StringBuffer('"');
    for (var i = 0; i < input.length; i++) {
      final unit = input.codeUnitAt(i);
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

  /// Writes historical conditions to [buffer] preserving rules in intermediate steps.
  static void _writeHistoricalConditions(
    StringBuffer buffer,
    List<TaskCondition> conditions,
  ) {
    for (final rule in conditions) {
      buffer.write('    condition ${rule.toTdfDirectiveArgs()}\n');
    }
  }

  /// Writes a single historical `label` block into [buffer].
  static void _writeHistoricalLabel(
    StringBuffer buffer,
    TdfHistoricalLabel label,
  ) {
    buffer.write('label ${label.id} {\n');
    buffer.write('    name ${_escapeQuoted(label.name)}\n');
    if (label.color case final color?) {
      buffer.write('    color ${_escapeQuoted(color)}\n');
    }
    if (label.note case final note?) {
      buffer.write('    note ${_escapeQuoted(note)}\n');
    }
    if (label.modifiedAt case final modifiedAt?) {
      buffer.write('    modified ${TaskItem.formatTdfTimestamp(modifiedAt)}\n');
    }
    _writeHistoricalConditions(buffer, label.conditions);
    buffer.write('}\n\n');
  }

  /// Writes historical `link` directives into [buffer].
  static void _writeHistoricalLinks(StringBuffer buffer, List<TaskLink> links) {
    for (final link in links) {
      buffer.write(
        '    link ${_escapeQuoted(link.title)} ${_escapeQuoted(link.uri)}\n',
      );
    }
  }

  /// Writes a historical `subtasks` block into [buffer].
  static void _writeHistoricalSubtasks(
    StringBuffer buffer,
    List<SubtaskItem> subtasks,
    bool autoFinish,
  ) {
    if (subtasks.isEmpty && !autoFinish) {
      return;
    }
    buffer.write('    subtasks');
    if (autoFinish) {
      buffer.write(' auto-finish');
    }
    buffer.write(' {\n');
    for (final step in subtasks) {
      buffer.write(
        '        step ${step.isCompleted ? "true" : "false"} ${_escapeQuoted(step.title)}\n',
      );
    }
    buffer.write('    }\n');
  }

  /// Writes a single historical `task` block into [buffer].
  static void _writeHistoricalTask(
    StringBuffer buffer,
    TdfHistoricalTask task,
  ) {
    buffer.write('task ${task.id}');
    if (task.isPriority) {
      buffer.write(' priority');
    }
    buffer.write(' {\n');
    buffer.write('    name ${_escapeQuoted(task.name)}\n');
    if (task.note case final note?) {
      buffer.write('    note ${_escapeQuoted(note)}\n');
    }
    buffer.write(
      '    created ${TaskItem.formatTdfTimestamp(task.createdAt)}\n',
    );
    if (task.queuedAt case final queuedAt?) {
      buffer.write('    queued ${TaskItem.formatTdfTimestamp(queuedAt)}\n');
    }
    if (task.completedAt case final completedAt?) {
      buffer.write(
        '    finished ${TaskItem.formatTdfTimestamp(completedAt)}\n',
      );
    }
    if (task.modifiedAt case final modifiedAt?) {
      buffer.write('    modified ${TaskItem.formatTdfTimestamp(modifiedAt)}\n');
    }
    if (task.labelIds.isNotEmpty) {
      buffer.write('    labels ${task.labelIds.join(" ")}\n');
    }
    if (task.blockedByTaskIds.isNotEmpty) {
      buffer.write('    blocked ${task.blockedByTaskIds.join(" ")}\n');
    }
    if (task.suspendedAt case final suspendedAt?) {
      buffer.write(
        '    suspended ${TaskItem.formatTdfTimestamp(suspendedAt)}\n',
      );
    }
    if (task.repeatRule case final repeatRule?) {
      buffer.write(
        '    repeat ${repeatRule.count} ${repeatRule.unit.tdfToken}\n',
      );
    }
    _writeHistoricalLinks(buffer, task.links);
    _writeHistoricalConditions(buffer, task.conditions);
    _writeHistoricalSubtasks(buffer, task.subtasks, task.subtasksAutoFinish);
    buffer.write('}\n\n');
  }

  /// Writes a single `0.5.0` `label` block into [buffer].
  static void _writeLabel050(StringBuffer buffer, TdfLabel label) {
    buffer.write('label ${label.id} {\n');
    buffer.write('    name ${_escapeQuoted(label.name)}\n');
    if (label.color case final color?) {
      buffer.write('    color ${_escapeQuoted(color)}\n');
    }
    if (label.note case final note?) {
      buffer.write('    note ${_escapeQuoted(note)}\n');
    }
    if (label.modifiedAt case final modifiedAt?) {
      buffer.write('    modified ${TaskItem.formatTdfTimestamp(modifiedAt)}\n');
    }
    _writeHistoricalConditions(buffer, label.conditions);
    buffer.write('}\n\n');
  }

  /// Writes the shared `0.5.0` `queue` block into [buffer].
  static void _writeQueue050(StringBuffer buffer, TdfQueueBlock queueBlock) {
    buffer.write('queue {\n    modified ');
    buffer.write(TaskItem.formatTdfTimestampWithSeconds(queueBlock.modifiedAt));
    buffer.write('\n');
    for (final taskId in queueBlock.taskIds) {
      buffer.write('    task $taskId\n');
    }
    buffer.write('}\n\n');
  }

  /// Writes a single `0.5.0` `task` block into [buffer].
  static void _writeTask050(
    StringBuffer buffer,
    TaskItem task,
    DateTime? queuedAt,
  ) {
    buffer.write('task ${task.id}');
    if (task.isPriority) {
      buffer.write(' priority');
    }
    buffer.write(' {\n');
    buffer.write('    name ${_escapeQuoted(task.title)}\n');
    if (task.note case final note?) {
      buffer.write('    note ${_escapeQuoted(note)}\n');
    }
    buffer.write(
      '    created ${TaskItem.formatTdfTimestamp(task.createdAt)}\n',
    );
    if (queuedAt case final resolvedQueuedAt?) {
      buffer.write(
        '    queued ${TaskItem.formatTdfTimestamp(resolvedQueuedAt)}\n',
      );
    }
    if (task.completedAt case final completedAt?) {
      buffer.write(
        '    finished ${TaskItem.formatTdfTimestamp(completedAt)}\n',
      );
    }
    if (task.modifiedAt case final modifiedAt?) {
      buffer.write('    modified ${TaskItem.formatTdfTimestamp(modifiedAt)}\n');
    }
    if (task.completions > 0) {
      buffer.write('    completions ${task.completions}\n');
    }
    if (task.labelIds.isNotEmpty) {
      buffer.write('    labels ${task.labelIds.join(" ")}\n');
    }
    if (task.dependencies.isNotEmpty) {
      final dependencies = TdfTaskDependency.normalizeList(task.dependencies);
      buffer.write(
        '    blocked ${dependencies.map((dependency) => dependency.formatCanonical()).join(" ")}\n',
      );
    }
    if (task.isSuspendedForever) {
      buffer.write('    suspended forever\n');
    } else if (task.suspendedAt case final suspendedAt?) {
      buffer.write(
        '    suspended ${TaskItem.formatTdfTimestamp(suspendedAt)}\n',
      );
    }
    if (task.repeatRule case final repeatRule?) {
      buffer.write('    repeat ${repeatRule.toTdfDirectiveArgs()}\n');
    }
    _writeHistoricalLinks(buffer, task.links);
    _writeHistoricalConditions(buffer, task.conditions);
    _writeHistoricalSubtasks(buffer, task.subtasks, task.subtasksAutoFinish);
    buffer.write('}\n\n');
  }

  /// Writes `0.5.1` conditions to [buffer], restoring colon-delimited inline location tuples to space-separated tokens.
  static void _writeConditions051(
    StringBuffer buffer,
    List<TaskCondition> conditions,
  ) {
    if (conditions.isEmpty) {
      return;
    }
    String formatRule(TaskCondition rule) {
      if (rule case final LocationTaskCondition loc) {
        return 'location ${[for (final id in loc.locationIds) id.replaceAll(":", " ")].join(" ")}';
      }
      return rule.toTdfDirectiveArgs();
    }

    if (conditions.length == 1) {
      buffer.write('    condition ${formatRule(conditions.single)}\n');
      return;
    }
    buffer.write('    condition {\n');
    for (final rule in conditions) {
      buffer.write('        ${formatRule(rule)}\n');
    }
    buffer.write('    }\n');
  }

  /// Writes a single `0.5.1` `label` block into [buffer].
  static void _writeLabel051(StringBuffer buffer, TdfLabel label) {
    buffer.write('label ${label.id} {\n');
    buffer.write('    name ${_escapeQuoted(label.name)}\n');
    if (label.color case final color?) {
      buffer.write('    color ${_escapeQuoted(color)}\n');
    }
    if (label.note case final note?) {
      buffer.write('    note ${_escapeQuoted(note)}\n');
    }
    if (label.modifiedAt case final modifiedAt?) {
      buffer.write('    modified ${TaskItem.formatTdfTimestamp(modifiedAt)}\n');
    }
    _writeConditions051(buffer, label.conditions);
    buffer.write('}\n\n');
  }

  /// Writes a single `0.5.1` `task` block into [buffer].
  static void _writeTask051(StringBuffer buffer, TaskItem task) {
    buffer.write('task ${task.id}');
    if (task.isPriority) {
      buffer.write(' priority');
    }
    buffer.write(' {\n');
    buffer.write('    name ${_escapeQuoted(task.title)}\n');
    if (task.note case final note?) {
      buffer.write('    note ${_escapeQuoted(note)}\n');
    }
    buffer.write(
      '    created ${TaskItem.formatTdfTimestamp(task.createdAt)}\n',
    );
    if (task.completedAt case final completedAt?) {
      buffer.write(
        '    finished ${TaskItem.formatTdfTimestamp(completedAt)}\n',
      );
    }
    if (task.modifiedAt case final modifiedAt?) {
      buffer.write('    modified ${TaskItem.formatTdfTimestamp(modifiedAt)}\n');
    }
    if (task.completions > 0) {
      buffer.write('    completions ${task.completions}\n');
    }
    if (task.repeatRule case final repeatRule?) {
      buffer.write('    repeat ${repeatRule.toTdfDirectiveArgs()}\n');
    }
    if (task.labelIds.isNotEmpty) {
      buffer.write('    labels ${task.labelIds.join(" ")}\n');
    }
    if (task.dependencies.isNotEmpty) {
      final dependencies = TdfTaskDependency.normalizeList(task.dependencies);
      buffer.write(
        '    blocked ${dependencies.map((dependency) => dependency.formatCanonical()).join(" ")}\n',
      );
    }
    if (task.isSuspendedForever) {
      buffer.write('    suspended forever\n');
    } else if (task.suspendedAt case final suspendedAt?) {
      buffer.write(
        '    suspended ${TaskItem.formatTdfTimestampWithSeconds(suspendedAt)}\n',
      );
    }
    _writeHistoricalLinks(buffer, task.links);
    _writeConditions051(buffer, task.conditions);
    _writeHistoricalSubtasks(buffer, task.subtasks, task.subtasksAutoFinish);
    buffer.write('}\n\n');
  }
}
