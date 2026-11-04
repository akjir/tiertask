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
import '../models/tdf_metadata.dart';
import '../models/tdf_sync_metadata.dart';
import '../models/tdf_timezone.dart';
import 'app_logger.dart';
import 'tdf_id_migration.dart';
import 'tdf_service.dart';

/// Immutable result of an explicit `TDF_SPEC.md` Section 10 version import operation.
@immutable
class TdfImportResult {
  /// Creates a [TdfImportResult].
  TdfImportResult({
    required this.sourceVersion,
    required Iterable<String> executedSteps,
    required this.migratedTdfContent,
    required this.board,
  }) : executedSteps = List<String>.unmodifiable(executedSteps);

  /// Evaluated target `0.5.0` [TaskBoard].
  final TaskBoard board;

  /// Ordered sequence of schema versions traversed during import (for example `['0.2.0', '0.3.0', '0.4.0', '0.5.0']`).
  final List<String> executedSteps;

  /// Canonical `tdf 0.5.0` document string produced by the migration chain.
  final String migratedTdfContent;

  /// Declared version of the input document (`0.2.0`, `0.3.0`, `0.4.0`, or `0.5.0`).
  final String sourceVersion;
}

/// Stateless service implementing the explicit `0.2.0 -> 0.3.0 -> 0.4.0 -> 0.5.0`
/// version import and adjacent migration chain defined in `TDF_SPEC.md` Section 10.
class TdfImporter {
  const TdfImporter._();

  /// Historical schema snapshot reference for `0.2.0` (`TDF_SPEC.md` Section 10.1.1).
  static const ({String version, String commit, String blob}) schemaRef020 = (
    version: '0.2.0',
    commit: 'e6e6f804608fb00466d265533130c407f114b53e',
    blob: 'e66b5917be314cebbea02d4163987f13018d1f5a',
  );

  /// Historical schema snapshot reference for `0.3.0` (`TDF_SPEC.md` Section 10.1.1).
  static const ({String version, String commit, String blob}) schemaRef030 = (
    version: '0.3.0',
    commit: 'ad4634a090a136b840a232f1830ef3fac3e8b6d4',
    blob: '562df38feb93009c15df998491536d8d44104e9d',
  );

  /// Historical schema snapshot reference for `0.4.0` (`TDF_SPEC.md` Section 10.1.1).
  static const ({String version, String commit, String blob}) schemaRef040 = (
    version: '0.4.0',
    commit: '73bc56a9cd6fb09828df7bb97353b71eee81ddcd',
    blob: '0fdc2ce15a72ba6288fcd59ef4e23ab419d749fb',
  );

  /// Validates and migrates [sourceContent] through the adjacent migration chain (`0.2.0 -> 0.3.0 -> 0.4.0 -> 0.5.0`).
  static TdfImportResult importDocument(
    String sourceContent, {
    TdfTimeZoneContext? sourceTimeZone,
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? evaluationTimeZone,
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
  }) {
    final stopwatch = Stopwatch()..start();
    const service = TdfService();
    final sourceVersion = _detectDeclaredVersion(sourceContent);
    final executedSteps = <String>[sourceVersion];
    var currentDoc = sourceContent;

    if (sourceVersion == '0.2.0') {
      currentDoc = migrate020To030(currentDoc, sourceTimeZone: sourceTimeZone);
      executedSteps.add('0.3.0');
    }
    if (executedSteps.last == '0.3.0') {
      currentDoc = migrate030To040(currentDoc);
      executedSteps.add('0.4.0');
    }
    if (executedSteps.last == '0.4.0') {
      currentDoc = migrate040To050(currentDoc, sourceTimeZone: sourceTimeZone);
      executedSteps.add('0.5.0');
    }

    final board = service.parse(
      currentDoc,
      evaluationTime: evaluationTime,
      localEvaluationTime: localEvaluationTime,
      timeZone: evaluationTimeZone,
      activeLabelId: activeLabelId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
      pruneExpiredCompleted: false,
    );
    final canonicalDoc = service.serialize(board);
    AppLogger.info(
      LogTag.tdf,
      'TdfImporter.importDocument steps=${executedSteps.join("->")} tasks=${board.allTasks.length} labels=${board.labels.length} elapsed=${stopwatch.elapsedMilliseconds}ms',
    );
    return TdfImportResult(
      sourceVersion: sourceVersion,
      executedSteps: executedSteps,
      migratedTdfContent: canonicalDoc,
      board: board,
    );
  }

  /// Executes the adjacent `0.2.0 -> 0.3.0` file conversion defined in `TDF_SPEC.md` Section 10.3.
  static String migrate020To030(
    String source020, {
    TdfTimeZoneContext? sourceTimeZone,
  }) {
    final doc = _parseHistoricalDocument(
      source020,
      expectedVersion: '0.2.0',
      targetVersion: '0.3.0',
    );
    if (doc.tasks.isNotEmpty &&
        (sourceTimeZone == null || !sourceTimeZone.isAvailable)) {
      throw TdfContextException(
        kind: TdfContextOutcomeKind.importContextRequired,
        line: doc.tasks.first.createdLine,
        message: 'Migration 0.2.0 -> 0.3.0 requires an explicit source time zone to convert local event timestamps.',
      );
    }

    final convertedTasks = <_HistoricalTask>[];
    for (final task in doc.tasks) {
      final zone = sourceTimeZone ?? TdfTimeZoneContext.utc;
      final createdUtc = _convertLocalTimestampToUtc(
        task.createdAt,
        zone: zone,
        line: task.createdLine,
        sourceVersion: '0.2.0',
        targetVersion: '0.3.0',
      );
      final queuedUtc = task.queuedAt == null
          ? null
          : _convertLocalTimestampToUtc(
              task.queuedAt,
              zone: zone,
              line: task.queuedLine,
              sourceVersion: '0.2.0',
              targetVersion: '0.3.0',
            );
      final finishedUtc = task.completedAt == null
          ? null
          : _convertLocalTimestampToUtc(
              task.completedAt,
              zone: zone,
              line: task.finishedLine,
              sourceVersion: '0.2.0',
              targetVersion: '0.3.0',
            );
      convertedTasks.add(
        task.copyWith(
          createdAt: createdUtc,
          queuedAt: queuedUtc,
          completedAt: finishedUtc,
        ),
      );
    }

    final serialized030 = _serializeHistoricalDocument(
      version: '0.3.0',
      labels: doc.labels,
      tasks: convertedTasks,
    );
    _parseHistoricalDocument(
      serialized030,
      expectedVersion: '0.3.0',
      targetVersion: '0.3.0',
    );
    return serialized030;
  }

  /// Executes the adjacent `0.3.0 -> 0.4.0` file conversion defined in `TDF_SPEC.md` Section 10.4.
  static String migrate030To040(String source030) {
    final doc = _parseHistoricalDocument(
      source030,
      expectedVersion: '0.3.0',
      targetVersion: '0.4.0',
    );
    final rewritten = _rewriteNoncanonicalIds(
      doc,
      sourceVersion: '0.3.0',
      targetVersion: '0.4.0',
    );
    final serialized040 = _serializeHistoricalDocument(
      version: '0.4.0',
      labels: rewritten.labels,
      tasks: rewritten.tasks,
    );
    _parseHistoricalDocument(
      serialized040,
      expectedVersion: '0.4.0',
      targetVersion: '0.4.0',
    );
    return serialized040;
  }

  /// Executes the adjacent `0.4.0 -> 0.5.0` file conversion defined in `TDF_SPEC.md` Section 10.5.
  static String migrate040To050(
    String source040, {
    TdfTimeZoneContext? sourceTimeZone,
  }) {
    final doc = _parseHistoricalDocument(
      source040,
      expectedVersion: '0.4.0',
      targetVersion: '0.5.0',
    );
    final rewritten = _rewriteNoncanonicalIds(
      doc,
      sourceVersion: '0.4.0',
      targetVersion: '0.5.0',
    );

    final labels050 = <TdfLabel>[];
    for (final label in rewritten.labels) {
      _validateTargetLabelBounds(label);
      labels050.add(
        TdfLabel(
          id: label.id,
          name: label.name,
          color: label.color,
          note: label.note,
          modifiedAt: label.modifiedAt,
          conditions: label.conditions,
        ),
      );
    }

    final tasks050 = <TaskItem>[];
    for (final task in rewritten.tasks) {
      tasks050.add(
        _convertHistoricalTaskTo050(task, sourceTimeZone: sourceTimeZone),
      );
    }

    final queueBlock = _buildLegacyQueueBlock(tasks050);
    const service = TdfService();
    final board = TaskBoard.evaluate(
      tasks: tasks050,
      labels: labels050,
      deletedBlock: TdfDeletedBlock.empty,
      queueBlock: queueBlock,
      pruneExpiredCompleted: false,
    );
    final serialized050 = service.serialize(board);
    service.parse(serialized050, pruneExpiredCompleted: false);
    return serialized050;
  }

  /// Builds the shared `0.5.0` [TdfQueueBlock] preserving the `0.4.0` effective queue order per Section 10.5.
  static TdfQueueBlock _buildLegacyQueueBlock(List<TaskItem> tasks) {
    final indexed = <({int index, TaskItem task})>[];
    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      if (task.queuedAt != null &&
          !task.isCompleted &&
          task.completedAt == null) {
        indexed.add((index: i, task: task));
      }
    }
    if (indexed.isEmpty) {
      return TdfQueueBlock.empty;
    }
    indexed.sort((left, right) {
      if (left.task.isPriority != right.task.isPriority) {
        return left.task.isPriority ? -1 : 1;
      }
      final leftQueued = left.task.queuedAt ?? left.task.createdAt;
      final rightQueued = right.task.queuedAt ?? right.task.createdAt;
      final timeCmp = leftQueued.compareTo(rightQueued);
      if (timeCmp != 0) {
        return timeCmp;
      }
      return left.index.compareTo(right.index);
    });
    var maxModified = indexed.first.task.effectiveModifiedAt;
    final orderedIds = <String>[];
    for (final entry in indexed) {
      orderedIds.add(entry.task.id);
      final effective = entry.task.effectiveModifiedAt;
      if (effective.isAfter(maxModified)) {
        maxModified = effective;
      }
    }
    return TdfQueueBlock(modifiedAt: maxModified, taskIds: orderedIds);
  }

  /// Converts a validated `0.4.0` [_HistoricalTask] into a `0.5.0` [TaskItem] per Section 10.5.
  static TaskItem _convertHistoricalTaskTo050(
    _HistoricalTask task, {
    required TdfTimeZoneContext? sourceTimeZone,
  }) {
    _validateTargetTaskBounds(task);

    var isSuspendedForever = false;
    DateTime? suspendedUtc;
    var repeatRule = task.repeatRule;

    if (task.suspendedAt case final rawSuspended?) {
      if (_isIndefiniteSentinel(rawSuspended)) {
        isSuspendedForever = true;
      } else {
        if (sourceTimeZone == null || !sourceTimeZone.isAvailable) {
          throw TdfContextException(
            kind: TdfContextOutcomeKind.importContextRequired,
            line: task.suspendedLine,
            message: 'Migration 0.4.0 -> 0.5.0 requires an explicit source time zone to convert finite local deferral.',
          );
        }
        if (repeatRule != null &&
            (rawSuspended.hour != 0 ||
                rawSuspended.minute != 0 ||
                rawSuspended.second != 0)) {
          repeatRule = TaskRepeatRule(
            count: repeatRule.count,
            unit: repeatRule.unit,
            clock: TdfRepeatClock(
              hour: rawSuspended.hour,
              minute: rawSuspended.minute,
              second: rawSuspended.second,
            ),
          );
        }
        suspendedUtc = _convertLocalTimestampToUtc(
          rawSuspended,
          zone: sourceTimeZone,
          line: task.suspendedLine,
          sourceVersion: '0.4.0',
          targetVersion: '0.5.0',
        );
      }
    }

    final isFinished = task.completedAt != null;
    final dependencies = TdfTaskDependency.normalizeList(<TdfTaskDependency>[
      for (final blockerId in task.blockedByTaskIds)
        TdfTaskDependency(taskId: blockerId, requiredCompletion: 1),
    ]);

    return TaskItem(
      id: task.id,
      title: task.name,
      note: task.note,
      isCompleted: isFinished,
      isPriority: task.isPriority,
      completions: isFinished ? 1 : 0,
      createdAt: task.createdAt,
      queuedAt: task.queuedAt,
      completedAt: task.completedAt,
      modifiedAt: task.modifiedAt,
      suspendedAt: suspendedUtc,
      isSuspendedForever: isSuspendedForever,
      repeatRule: repeatRule,
      labelIds: task.labelIds,
      dependencies: dependencies,
      links: task.links,
      conditions: task.conditions,
      subtasksAutoFinish: task.subtasksAutoFinish,
      subtasks: task.subtasks,
    );
  }

  /// Converts a local calendar [localTimestamp] in [zone] to UTC per Section 6.10.2 and checks calendar bounds.
  static DateTime _convertLocalTimestampToUtc(
    DateTime? localTimestamp, {
    required TdfTimeZoneContext zone,
    required int line,
    required String sourceVersion,
    required String targetVersion,
  }) {
    final resolvedLocal = localTimestamp ?? DateTime.utc(1970, 1, 1);
    final DateTime converted;
    try {
      converted = zone.resolveLocalToUtc(
        resolvedLocal.year,
        resolvedLocal.month,
        resolvedLocal.day,
        resolvedLocal.hour,
        resolvedLocal.minute,
        resolvedLocal.second,
      );
    } on FormatException {
      throw TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: line,
        sourceVersion: sourceVersion,
        targetVersion: targetVersion,
        message: 'Converted UTC timestamp is outside supported 0001-01-01..9999-12-31 range.',
      );
    }
    if (!TdfCalendar.isWithinTimestampBounds(converted)) {
      throw TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: line,
        sourceVersion: sourceVersion,
        targetVersion: targetVersion,
        message: 'Converted UTC timestamp is outside supported 0001-01-01..9999-12-31 range.',
      );
    }
    return converted;
  }

  /// Scans the first statement of [source] and returns its declared version (`0.2.0`, `0.3.0`, `0.4.0`, or `0.5.0`).
  static String _detectDeclaredVersion(String source) {
    if (source.length > TdfService.maxFileBytes ||
        utf8.encode(source).length > TdfService.maxFileBytes) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message: 'TDF document exceeds maximum file size.',
      );
    }
    var offset = 0;
    var lineNumber = 0;
    while (offset < source.length) {
      lineNumber++;
      if (lineNumber > TdfService.maxLineCount) {
        throw TdfException(
          kind: TdfErrorKind.limitExceeded,
          line: lineNumber,
          message: 'TDF document exceeds maximum line count.',
        );
      }
      final span = _findHistoricalLineSpan(source, offset, lineNumber);
      final tokens = _scanHistoricalTokens(
        source,
        span.lineStart,
        span.lineEnd,
        lineNumber,
      );
      offset = span.nextOffset;
      if (tokens.isEmpty) {
        continue;
      }
      if (tokens[0].kind != _HistTokenKind.bareWord ||
          tokens[0].value != 'tdf' ||
          tokens.any(
            (token) =>
                token.kind == _HistTokenKind.openBrace ||
                token.kind == _HistTokenKind.closeBrace,
          )) {
        throw TdfException(
          kind: TdfErrorKind.missingVersionHeader,
          line: lineNumber,
          message: 'Document must start with a "tdf <version>" header.',
        );
      }
      if (tokens.length == 1) {
        throw TdfException(
          kind: TdfErrorKind.missingVersionHeader,
          line: lineNumber,
          message: 'Version header "tdf" requires a version argument.',
        );
      }
      if (tokens.length != 2 || tokens[1].kind != _HistTokenKind.bareWord) {
        throw TdfException(
          kind: TdfErrorKind.unsupportedVersion,
          line: lineNumber,
          message: 'Malformed version header.',
        );
      }
      final version = tokens[1].value;
      if (version != '0.2.0' &&
          version != '0.3.0' &&
          version != '0.4.0' &&
          version != '0.5.0') {
        throw TdfException(
          kind: TdfErrorKind.unsupportedVersion,
          line: lineNumber,
          message: 'Unsupported TDF version "$version" for import.',
        );
      }
      return version;
    }
    throw const TdfException(
      kind: TdfErrorKind.missingVersionHeader,
      line: 1,
      message: 'Empty TDF document is missing version header.',
    );
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

  /// Finds the line span starting at [startOffset] in [source].
  static ({int lineStart, int lineEnd, int nextOffset}) _findHistoricalLineSpan(
    String source,
    int startOffset,
    int lineNumber,
  ) {
    var index = startOffset;
    while (index < source.length) {
      final unit = source.codeUnitAt(index);
      if (unit == 0x0A) {
        return (lineStart: startOffset, lineEnd: index, nextOffset: index + 1);
      }
      if (unit == 0x0D) {
        if (index + 1 >= source.length ||
            source.codeUnitAt(index + 1) != 0x0A) {
          throw TdfException(
            kind: TdfErrorKind.unexpectedToken,
            line: lineNumber,
            message: 'Standalone CR without LF.',
          );
        }
        return (lineStart: startOffset, lineEnd: index, nextOffset: index + 2);
      }
      if ((unit < 0x20 && unit != 0x09) || unit == 0x7F) {
        throw TdfException(
          kind: TdfErrorKind.unexpectedToken,
          line: lineNumber,
          message: 'Disallowed control character in TDF document.',
        );
      }
      index++;
    }
    return (
      lineStart: startOffset,
      lineEnd: source.length,
      nextOffset: source.length,
    );
  }

  /// Checks whether [timestamp] equals the `0.4.0` indefinite sentinel `9999-12-31 23:59:00`.
  static bool _isIndefiniteSentinel(DateTime timestamp) {
    return timestamp.year == 9999 &&
        timestamp.month == 12 &&
        timestamp.day == 31 &&
        timestamp.hour == 23 &&
        timestamp.minute == 59 &&
        timestamp.second == 0;
  }

  /// Checks whether [raw] matches a historical entity ID (`[a-zA-Z0-9_-]+`).
  static bool _isValidHistoricalEntityId(String raw) {
    if (raw.isEmpty) {
      return false;
    }
    for (var i = 0; i < raw.length; i++) {
      final unit = raw.codeUnitAt(i);
      final isAlphaNum =
          (unit >= 0x30 && unit <= 0x39) ||
          (unit >= 0x41 && unit <= 0x5A) ||
          (unit >= 0x61 && unit <= 0x7A) ||
          unit == 0x5F ||
          unit == 0x2D;
      if (!isAlphaNum) {
        return false;
      }
    }
    return true;
  }

  /// Parses and validates [source] against the pinned historical schema for [expectedVersion] (`0.2.0`, `0.3.0`, or `0.4.0`).
  static _HistoricalDocument _parseHistoricalDocument(
    String source, {
    required String expectedVersion,
    required String targetVersion,
  }) {
    final labels = <_HistoricalLabel>[];
    final tasks = <_HistoricalTask>[];
    final seenLabelIds = <String>{};
    final seenTaskIds = <String>{};
    final stack = <Object>[];
    var hasSeenHeader = false;
    var totalBlocks = 0;
    var offset = 0;
    var lineNumber = 0;

    while (offset < source.length) {
      lineNumber++;
      if (lineNumber > TdfService.maxLineCount) {
        throw TdfException(
          kind: TdfErrorKind.limitExceeded,
          line: lineNumber,
          sourceVersion: expectedVersion,
          targetVersion: targetVersion,
          message: 'Historical document exceeds maximum line count.',
        );
      }
      final span = _findHistoricalLineSpan(source, offset, lineNumber);
      final tokens = _scanHistoricalTokens(
        source,
        span.lineStart,
        span.lineEnd,
        lineNumber,
      );
      offset = span.nextOffset;
      if (tokens.isEmpty) {
        continue;
      }
      if (!hasSeenHeader) {
        if (tokens.length != 2 ||
            tokens[0].kind != _HistTokenKind.bareWord ||
            tokens[0].value != 'tdf' ||
            tokens[1].kind != _HistTokenKind.bareWord ||
            tokens[1].value != expectedVersion) {
          throw TdfException(
            kind: TdfErrorKind.unsupportedVersion,
            line: lineNumber,
            sourceVersion: expectedVersion,
            targetVersion: targetVersion,
            message: 'Expected "tdf $expectedVersion" header.',
          );
        }
        hasSeenHeader = true;
        continue;
      }
      _processHistoricalTokens(
        tokens: tokens,
        lineNumber: lineNumber,
        expectedVersion: expectedVersion,
        targetVersion: targetVersion,
        stack: stack,
        labels: labels,
        tasks: tasks,
        seenLabelIds: seenLabelIds,
        seenTaskIds: seenTaskIds,
        incrementBlockCount: () {
          totalBlocks++;
          if (totalBlocks > TdfService.maxBlocksPerDoc) {
            throw TdfException(
              kind: TdfErrorKind.limitExceeded,
              line: lineNumber,
              sourceVersion: expectedVersion,
              targetVersion: targetVersion,
              message: 'Exceeded MAX_BLOCKS_PER_DOC.',
            );
          }
        },
      );
    }

    if (!hasSeenHeader) {
      throw TdfException(
        kind: TdfErrorKind.missingVersionHeader,
        line: 1,
        sourceVersion: expectedVersion,
        targetVersion: targetVersion,
        message: 'Missing version header.',
      );
    }
    if (stack.isNotEmpty) {
      throw TdfException(
        kind: TdfErrorKind.unclosedBlock,
        line: lineNumber,
        sourceVersion: expectedVersion,
        targetVersion: targetVersion,
        message: 'Unclosed block in historical document.',
      );
    }

    _validateHistoricalReferencesAndCycles(
      labels: labels,
      tasks: tasks,
      seenLabelIds: seenLabelIds,
      sourceVersion: expectedVersion,
      targetVersion: targetVersion,
    );

    return _HistoricalDocument(labels: labels, tasks: tasks);
  }

  /// Processes a single tokenized statement line in a historical (`0.2.0`, `0.3.0`, or `0.4.0`) document.
  static void _processHistoricalTokens({
    required List<_HistToken> tokens,
    required int lineNumber,
    required String expectedVersion,
    required String targetVersion,
    required List<Object> stack,
    required List<_HistoricalLabel> labels,
    required List<_HistoricalTask> tasks,
    required Set<String> seenLabelIds,
    required Set<String> seenTaskIds,
    required void Function() incrementBlockCount,
  }) {
    if (tokens.first.kind == _HistTokenKind.closeBrace) {
      if (tokens.length > 1) {
        throw TdfException(
          kind: TdfErrorKind.unexpectedToken,
          line: lineNumber,
          sourceVersion: expectedVersion,
          targetVersion: targetVersion,
          message: 'Trailing tokens after "}".',
        );
      }
      if (stack.isEmpty) {
        throw TdfException(
          kind: TdfErrorKind.unexpectedClosingBrace,
          line: lineNumber,
          sourceVersion: expectedVersion,
          targetVersion: targetVersion,
          message: 'Unexpected "}" at root.',
        );
      }
      final closed = stack.removeLast();
      if (closed is _HistoricalLabelBuilder) {
        labels.add(closed.build(lineNumber, expectedVersion, targetVersion));
      } else if (closed is _HistoricalTaskBuilder) {
        tasks.add(closed.build(lineNumber, expectedVersion, targetVersion));
      } else if (closed is _HistoricalSubtasksBuilder) {
        if (closed.steps.isEmpty) {
          throw TdfException(
            kind: TdfErrorKind.missingRequiredDirective,
            line: lineNumber,
            sourceVersion: expectedVersion,
            targetVersion: targetVersion,
            message: 'Empty subtasks block.',
          );
        }
        final parent = stack.last as _HistoricalTaskBuilder;
        parent.subtasksAutoFinish = closed.autoFinish;
        parent.subtasks = closed.steps;
      } else if (closed is _HistoricalCondBlockBuilder) {
        if (!closed.hasRules) {
          throw TdfException(
            kind: TdfErrorKind.missingRequiredDirective,
            line: lineNumber,
            sourceVersion: expectedVersion,
            targetVersion: targetVersion,
            message: 'Empty condition block.',
          );
        }
      }
      return;
    }

    final hasOpenBrace = tokens.last.kind == _HistTokenKind.openBrace;
    if (hasOpenBrace) {
      incrementBlockCount();
      final blockType = tokens.first.value;
      final headerArgs = tokens.sublist(1, tokens.length - 1);
      if (stack.isEmpty) {
        if (blockType != 'label' && blockType != 'task') {
          throw TdfException(
            kind: TdfErrorKind.unknownBlockType,
            line: lineNumber,
            sourceVersion: expectedVersion,
            targetVersion: targetVersion,
            message: 'Unknown root block "$blockType" in $expectedVersion.',
          );
        }
        if (headerArgs.isEmpty) {
          throw TdfException(
            kind: TdfErrorKind.invalidBlockHeader,
            line: lineNumber,
            sourceVersion: expectedVersion,
            targetVersion: targetVersion,
            message: 'Missing entity ID.',
          );
        }
        final idToken = headerArgs.first;
        if (idToken.kind != _HistTokenKind.bareWord ||
            !_isValidHistoricalEntityId(idToken.value)) {
          throw TdfException(
            kind: TdfErrorKind.invalidIdentifier,
            line: lineNumber,
            sourceVersion: expectedVersion,
            targetVersion: targetVersion,
            message: 'Invalid entity ID "${idToken.value}".',
          );
        }
        if (blockType == 'label') {
          if (headerArgs.length != 1) {
            throw TdfException(
              kind: TdfErrorKind.invalidBlockHeader,
              line: lineNumber,
              sourceVersion: expectedVersion,
              targetVersion: targetVersion,
              message: 'Extra arguments on label block header.',
            );
          }
          if (!seenLabelIds.add(idToken.value)) {
            throw TdfException(
              kind: TdfErrorKind.duplicateIdentifier,
              line: lineNumber,
              sourceVersion: expectedVersion,
              targetVersion: targetVersion,
              message: 'Duplicate label ID "${idToken.value}".',
            );
          }
          stack.add(
            _HistoricalLabelBuilder(id: idToken.value, headerLine: lineNumber),
          );
        } else {
          if (headerArgs.length > 2 ||
              (headerArgs.length == 2 && headerArgs[1].value != 'priority')) {
            throw TdfException(
              kind: TdfErrorKind.invalidBlockHeader,
              line: lineNumber,
              sourceVersion: expectedVersion,
              targetVersion: targetVersion,
              message: 'Invalid task header arguments.',
            );
          }
          if (!seenTaskIds.add(idToken.value)) {
            throw TdfException(
              kind: TdfErrorKind.duplicateIdentifier,
              line: lineNumber,
              sourceVersion: expectedVersion,
              targetVersion: targetVersion,
              message: 'Duplicate task ID "${idToken.value}".',
            );
          }
          stack.add(
            _HistoricalTaskBuilder(
              id: idToken.value,
              isPriority: headerArgs.length == 2,
              headerLine: lineNumber,
            ),
          );
        }
        return;
      }
      final parent = stack.last;
      if (blockType == 'condition' &&
          (parent is _HistoricalLabelBuilder ||
              parent is _HistoricalTaskBuilder)) {
        if (headerArgs.isNotEmpty) {
          throw TdfException(
            kind: TdfErrorKind.invalidBlockHeader,
            line: lineNumber,
            sourceVersion: expectedVersion,
            targetVersion: targetVersion,
            message: 'Condition block takes no arguments.',
          );
        }
        stack.add(_HistoricalCondBlockBuilder(parent: parent));
        return;
      }
      if (blockType == 'subtasks' && parent is _HistoricalTaskBuilder) {
        if (headerArgs.length > 1 ||
            (headerArgs.length == 1 &&
                headerArgs.first.value != 'auto-finish')) {
          throw TdfException(
            kind: TdfErrorKind.invalidBlockHeader,
            line: lineNumber,
            sourceVersion: expectedVersion,
            targetVersion: targetVersion,
            message: 'Invalid subtasks header.',
          );
        }
        stack.add(
          _HistoricalSubtasksBuilder(autoFinish: headerArgs.length == 1),
        );
        return;
      }
      throw TdfException(
        kind: TdfErrorKind.unknownBlockType,
        line: lineNumber,
        sourceVersion: expectedVersion,
        targetVersion: targetVersion,
        message: 'Unknown nested block "$blockType".',
      );
    }

    if (stack.isEmpty) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedRootDirective,
        line: lineNumber,
        sourceVersion: expectedVersion,
        targetVersion: targetVersion,
        message: 'Unexpected root directive "${tokens.first.value}".',
      );
    }
    if (tokens.length < 2) {
      throw TdfException(
        kind: TdfErrorKind.missingDirectiveArgument,
        line: lineNumber,
        sourceVersion: expectedVersion,
        targetVersion: targetVersion,
        message: 'Missing directive arguments.',
      );
    }
    _applyHistoricalDirective(
      active: stack.last,
      directive: tokens.first.value,
      args: tokens.sublist(1),
      lineNumber: lineNumber,
      expectedVersion: expectedVersion,
      targetVersion: targetVersion,
    );
  }

  /// Applies a directive inside an open historical builder according to [expectedVersion].
  static void _applyHistoricalDirective({
    required Object active,
    required String directive,
    required List<_HistToken> args,
    required int lineNumber,
    required String expectedVersion,
    required String targetVersion,
  }) {
    final allow030 = expectedVersion == '0.3.0' || expectedVersion == '0.4.0';
    final allow040 = expectedVersion == '0.4.0';

    if (active is _HistoricalLabelBuilder) {
      switch (directive) {
        case 'name':
          active.name = args.first.value;
          active.nameLine = lineNumber;
        case 'color':
          active.color = args.first.value.toUpperCase();
        case 'note':
          active.note = args.first.value;
          active.noteLine = lineNumber;
        case 'modified':
          if (!allow030) {
            throw TdfException(
              kind: TdfErrorKind.unknownDirective,
              line: lineNumber,
              sourceVersion: expectedVersion,
              targetVersion: targetVersion,
              message: 'Directive "modified" is not part of TDF 0.2.0.',
            );
          }
          active.modifiedAt = _parseHistoricalTimestamp(
            args,
            lineNumber,
            expectedVersion,
            targetVersion,
          );
        case 'condition':
          active.conditions.add(
            _parseHistoricalCondition(
              args.first.value,
              args.sublist(1),
              allowResets: false,
              lineNumber: lineNumber,
              expectedVersion: expectedVersion,
              targetVersion: targetVersion,
            ),
          );
          active.conditionLines.add(lineNumber);
        default:
          throw TdfException(
            kind: TdfErrorKind.unknownDirective,
            line: lineNumber,
            sourceVersion: expectedVersion,
            targetVersion: targetVersion,
            message: 'Unknown label directive "$directive".',
          );
      }
      return;
    }

    if (active is _HistoricalTaskBuilder) {
      switch (directive) {
        case 'name':
          active.name = args.first.value;
          active.nameLine = lineNumber;
        case 'note':
          active.note = args.first.value;
          active.noteLine = lineNumber;
        case 'created':
          active.createdAt = _parseHistoricalTimestamp(
            args,
            lineNumber,
            expectedVersion,
            targetVersion,
          );
          active.createdLine = lineNumber;
        case 'queued':
          active.queuedAt = _parseHistoricalTimestamp(
            args,
            lineNumber,
            expectedVersion,
            targetVersion,
          );
          active.queuedLine = lineNumber;
        case 'finished':
          active.completedAt = _parseHistoricalTimestamp(
            args,
            lineNumber,
            expectedVersion,
            targetVersion,
          );
          active.finishedLine = lineNumber;
        case 'modified':
          if (!allow030) {
            throw TdfException(
              kind: TdfErrorKind.unknownDirective,
              line: lineNumber,
              sourceVersion: expectedVersion,
              targetVersion: targetVersion,
              message: 'Directive "modified" is not part of TDF 0.2.0.',
            );
          }
          active.modifiedAt = _parseHistoricalTimestamp(
            args,
            lineNumber,
            expectedVersion,
            targetVersion,
          );
        case 'suspended':
          active.suspendedAt = _parseHistoricalTimestamp(
            args,
            lineNumber,
            expectedVersion,
            targetVersion,
          );
          active.suspendedLine = lineNumber;
        case 'repeat':
          if (!allow030 || args.length != 2) {
            throw TdfException(
              kind: allow030
                  ? TdfErrorKind.unexpectedToken
                  : TdfErrorKind.unknownDirective,
              line: lineNumber,
              sourceVersion: expectedVersion,
              targetVersion: targetVersion,
              message: 'Invalid or unsupported "repeat" directive.',
            );
          }
          final count = int.tryParse(args[0].value);
          final unit = RepeatUnit.tryParseToken(args[1].value);
          if (count == null || count < 1 || unit == null) {
            throw TdfException(
              kind: count == null || count < 1
                  ? TdfErrorKind.invalidNumber
                  : TdfErrorKind.unexpectedToken,
              line: lineNumber,
              sourceVersion: expectedVersion,
              targetVersion: targetVersion,
              message: 'Invalid repeat arguments.',
            );
          }
          active.repeatRule = TaskRepeatRule(count: count, unit: unit);
        case 'labels':
          for (final arg in args) {
            if (arg.kind != _HistTokenKind.bareWord ||
                !_isValidHistoricalEntityId(arg.value)) {
              throw TdfException(
                kind: TdfErrorKind.invalidIdentifier,
                line: lineNumber,
                sourceVersion: expectedVersion,
                targetVersion: targetVersion,
                message: 'Invalid label reference "${arg.value}".',
              );
            }
            active.labelIds.add(arg.value);
          }
          active.labelsLine = lineNumber;
        case 'blocked':
          for (final arg in args) {
            if (arg.kind != _HistTokenKind.bareWord ||
                !_isValidHistoricalEntityId(arg.value)) {
              throw TdfException(
                kind: TdfErrorKind.invalidIdentifier,
                line: lineNumber,
                sourceVersion: expectedVersion,
                targetVersion: targetVersion,
                message: 'Invalid prerequisite reference "${arg.value}".',
              );
            }
            active.blockedByTaskIds.add(arg.value);
          }
          active.blockedLine = lineNumber;
        case 'link':
          if (!allow040 || args.length != 2) {
            throw TdfException(
              kind: allow040
                  ? TdfErrorKind.unexpectedToken
                  : TdfErrorKind.unknownDirective,
              line: lineNumber,
              sourceVersion: expectedVersion,
              targetVersion: targetVersion,
              message: 'Invalid or unsupported "link" directive.',
            );
          }
          active.links.add(TaskLink(title: args[0].value, uri: args[1].value));
          active.linkLines.add(lineNumber);
        case 'condition':
          active.conditions.add(
            _parseHistoricalCondition(
              args.first.value,
              args.sublist(1),
              allowResets: true,
              lineNumber: lineNumber,
              expectedVersion: expectedVersion,
              targetVersion: targetVersion,
            ),
          );
          active.conditionLines.add(lineNumber);
        default:
          throw TdfException(
            kind: TdfErrorKind.unknownDirective,
            line: lineNumber,
            sourceVersion: expectedVersion,
            targetVersion: targetVersion,
            message: 'Unknown task directive "$directive".',
          );
      }
      return;
    }

    if (active is _HistoricalSubtasksBuilder) {
      if (directive != 'step' || args.length != 2) {
        throw TdfException(
          kind: directive != 'step'
              ? TdfErrorKind.unknownDirective
              : TdfErrorKind.unexpectedToken,
          line: lineNumber,
          sourceVersion: expectedVersion,
          targetVersion: targetVersion,
          message: 'Invalid subtasks directive.',
        );
      }
      active.steps.add(
        SubtaskItem(title: args[1].value, isCompleted: args[0].value == 'true'),
      );
      return;
    }

    if (active is _HistoricalCondBlockBuilder) {
      final parent = active.parent;
      final rule = _parseHistoricalCondition(
        directive,
        args,
        allowResets: parent is _HistoricalTaskBuilder,
        lineNumber: lineNumber,
        expectedVersion: expectedVersion,
        targetVersion: targetVersion,
      );
      active.hasRules = true;
      if (parent is _HistoricalLabelBuilder) {
        parent.conditions.add(rule);
        parent.conditionLines.add(lineNumber);
      } else if (parent is _HistoricalTaskBuilder) {
        parent.conditions.add(rule);
        parent.conditionLines.add(lineNumber);
      }
    }
  }

  /// Parses a condition rule in a historical document.
  static TaskCondition _parseHistoricalCondition(
    String type,
    List<_HistToken> args, {
    required bool allowResets,
    required int lineNumber,
    required String expectedVersion,
    required String targetVersion,
  }) {
    if (type == 'any' && allowResets && args.isEmpty) {
      return const GlobalResetTaskCondition();
    }
    if (args.length == 1 && args.first.value == 'any' && allowResets) {
      return switch (type) {
        'day' => const GroupResetTaskCondition(targetGroup: ConditionGroup.day),
        'time' => const GroupResetTaskCondition(
          targetGroup: ConditionGroup.time,
        ),
        'location' => const GroupResetTaskCondition(
          targetGroup: ConditionGroup.location,
        ),
        _ => throw TdfException(
          kind: TdfErrorKind.invalidCondition,
          line: lineNumber,
          sourceVersion: expectedVersion,
          targetVersion: targetVersion,
          message: 'Invalid group reset "$type any".',
        ),
      };
    }
    switch (type) {
      case 'day':
        final weekdays = <int>[];
        final tokens = <String>[];
        for (final arg in args) {
          final w = DayTaskCondition.parseWeekdayToken(arg.value);
          if (w == null) {
            throw TdfException(
              kind: TdfErrorKind.invalidCondition,
              line: lineNumber,
              sourceVersion: expectedVersion,
              targetVersion: targetVersion,
              message: 'Invalid weekday "${arg.value}".',
            );
          }
          weekdays.add(w);
          tokens.add(arg.value);
        }
        return DayTaskCondition(weekdays: weekdays, dayTokens: tokens);
      case 'time':
        if (args.length != 2) {
          throw TdfException(
            kind: TdfErrorKind.invalidTimestamp,
            line: lineNumber,
            sourceVersion: expectedVersion,
            targetVersion: targetVersion,
            message: 'Invalid time condition.',
          );
        }
        final start = TaskItem.tryParseTimeMinutes(args[0].value);
        final end = TaskItem.tryParseTimeMinutes(args[1].value);
        if (start == null || end == null || start == end) {
          throw TdfException(
            kind: start == null || end == null
                ? TdfErrorKind.invalidTimestamp
                : TdfErrorKind.invalidCondition,
            line: lineNumber,
            sourceVersion: expectedVersion,
            targetVersion: targetVersion,
            message: 'Invalid time window.',
          );
        }
        return TimeWindowTaskCondition(
          startMinutes: start,
          endMinutes: end,
          startToken: args[0].value,
          endToken: args[1].value,
        );
      case 'location':
        if (args.length != 3) {
          throw TdfException(
            kind: TdfErrorKind.invalidCondition,
            line: lineNumber,
            sourceVersion: expectedVersion,
            targetVersion: targetVersion,
            message: 'Invalid location condition.',
          );
        }
        final lat = double.tryParse(args[0].value);
        final lon = double.tryParse(args[1].value);
        final rad = double.tryParse(args[2].value);
        if (lat == null || lon == null || rad == null || rad <= 0) {
          throw TdfException(
            kind: TdfErrorKind.invalidCondition,
            line: lineNumber,
            sourceVersion: expectedVersion,
            targetVersion: targetVersion,
            message: 'Invalid GPS parameters.',
          );
        }
        return LocationTaskCondition(
          latitude: lat,
          longitude: lon,
          radiusMeters: rad,
        );
      default:
        throw TdfException(
          kind: TdfErrorKind.unknownDirective,
          line: lineNumber,
          sourceVersion: expectedVersion,
          targetVersion: targetVersion,
          message: 'Unknown condition rule "$type".',
        );
    }
  }

  /// Parses a timestamp in a historical document.
  static DateTime _parseHistoricalTimestamp(
    List<_HistToken> args,
    int lineNumber,
    String expectedVersion,
    String targetVersion,
  ) {
    if (args.isEmpty ||
        args.length > 2 ||
        args[0].kind != _HistTokenKind.bareWord ||
        (args.length == 2 && args[1].kind != _HistTokenKind.bareWord)) {
      throw TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: lineNumber,
        sourceVersion: expectedVersion,
        targetVersion: targetVersion,
        message: 'Invalid timestamp arguments.',
      );
    }
    final parsed = TaskItem.tryParseTdfTimestamp(
      args[0].value,
      args.length == 2 ? args[1].value : null,
    );
    if (parsed == null) {
      throw TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: lineNumber,
        sourceVersion: expectedVersion,
        targetVersion: targetVersion,
        message: 'Invalid calendar timestamp.',
      );
    }
    return parsed;
  }

  /// Rewrites noncanonical task and label IDs in [doc] using `TdfIdMigration.buildMigrationMap` (Section 10.4).
  static _HistoricalDocument _rewriteNoncanonicalIds(
    _HistoricalDocument doc, {
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

    final mapping = TdfIdMigration.buildMigrationMap(
      existingCanonicalIds: existingCanonicalIds,
      nonCanonicalLabelIds: nonCanonicalLabelIds,
      nonCanonicalTaskIds: nonCanonicalTaskIds,
    );

    final mappedLabels = <_HistoricalLabel>[
      for (final label in doc.labels)
        label.copyWith(id: mapping.resolveLabelId(label.id)),
    ];
    final mappedTasks = <_HistoricalTask>[
      for (final task in doc.tasks)
        task.copyWith(
          id: mapping.resolveTaskId(task.id),
          labelIds: <String>[
            for (final labelId in task.labelIds)
              mapping.resolveLabelId(labelId),
          ],
          blockedByTaskIds: <String>[
            for (final blockerId in task.blockedByTaskIds)
              mapping.resolveTaskId(blockerId),
          ],
        ),
    ];

    return _HistoricalDocument(labels: mappedLabels, tasks: mappedTasks);
  }

  /// Scans tokens on a single historical line `[lineStart, lineEnd)`.
  static List<_HistToken> _scanHistoricalTokens(
    String source,
    int lineStart,
    int lineEnd,
    int lineNumber,
  ) {
    final tokens = <_HistToken>[];
    var cursor = lineStart;
    while (cursor < lineEnd) {
      while (cursor < lineEnd &&
          (source.codeUnitAt(cursor) == 0x20 ||
              source.codeUnitAt(cursor) == 0x09)) {
        cursor++;
      }
      if (cursor >= lineEnd || source.codeUnitAt(cursor) == 0x23) {
        break;
      }
      final unit = source.codeUnitAt(cursor);
      if (unit == 0x7B) {
        tokens.add(
          const _HistToken(value: '{', kind: _HistTokenKind.openBrace),
        );
        cursor++;
      } else if (unit == 0x7D) {
        tokens.add(
          const _HistToken(value: '}', kind: _HistTokenKind.closeBrace),
        );
        cursor++;
      } else if (unit == 0x22) {
        final buf = StringBuffer();
        cursor++;
        var closed = false;
        while (cursor < lineEnd) {
          final c = source.codeUnitAt(cursor);
          if (c == 0x22) {
            cursor++;
            closed = true;
            break;
          }
          if (c == 0x5C && cursor + 1 < lineEnd) {
            final esc = source.codeUnitAt(cursor + 1);
            buf.writeCharCode(switch (esc) {
              0x22 => 0x22,
              0x5C => 0x5C,
              0x6E => 0x0A,
              0x72 => 0x0D,
              0x74 => 0x09,
              _ => throw TdfException(
                kind: TdfErrorKind.invalidEscapeSequence,
                line: lineNumber,
                message: 'Invalid escape in string.',
              ),
            });
            cursor += 2;
          } else {
            buf.writeCharCode(c);
            cursor++;
          }
        }
        if (!closed) {
          throw TdfException(
            kind: TdfErrorKind.unterminatedString,
            line: lineNumber,
            message: 'Unterminated string.',
          );
        }
        tokens.add(
          _HistToken(value: buf.toString(), kind: _HistTokenKind.quotedString),
        );
      } else if (unit == 0x27) {
        final start = cursor + 1;
        cursor = start;
        while (cursor < lineEnd && source.codeUnitAt(cursor) != 0x27) {
          cursor++;
        }
        if (cursor >= lineEnd) {
          throw TdfException(
            kind: TdfErrorKind.unterminatedString,
            line: lineNumber,
            message: 'Unterminated single-quoted string.',
          );
        }
        tokens.add(
          _HistToken(
            value: source.substring(start, cursor),
            kind: _HistTokenKind.quotedString,
          ),
        );
        cursor++;
      } else {
        final start = cursor;
        while (cursor < lineEnd) {
          final c = source.codeUnitAt(cursor);
          if (c == 0x20 || c == 0x09 || c == 0x23) {
            break;
          }
          if (c == 0x7B) {
            throw TdfException(
              kind: TdfErrorKind.invalidBlockHeader,
              line: lineNumber,
              message: 'Missing whitespace before "{".',
            );
          }
          cursor++;
        }
        tokens.add(
          _HistToken(
            value: source.substring(start, cursor),
            kind: _HistTokenKind.bareWord,
          ),
        );
      }
    }
    return tokens;
  }

  /// Serializes an intermediate `0.3.0` or `0.4.0` document in declaration order.
  static String _serializeHistoricalDocument({
    required String version,
    required List<_HistoricalLabel> labels,
    required List<_HistoricalTask> tasks,
  }) {
    if (labels.isEmpty && tasks.isEmpty) {
      return 'tdf $version\n';
    }
    final buffer = StringBuffer('tdf $version\n\n');
    for (final label in labels) {
      buffer.write('label ${label.id} {\n');
      buffer.write('    name ${_escapeQuoted(label.name)}\n');
      if (label.color case final color?) {
        buffer.write('    color ${_escapeQuoted(color)}\n');
      }
      if (label.note case final note?) {
        buffer.write('    note ${_escapeQuoted(note)}\n');
      }
      if (label.modifiedAt case final modifiedAt?) {
        buffer.write(
          '    modified ${TaskItem.formatTdfTimestamp(modifiedAt)}\n',
        );
      }
      _writeHistoricalConditions(buffer, label.conditions);
      buffer.write('}\n\n');
    }
    for (final task in tasks) {
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
        buffer.write(
          '    modified ${TaskItem.formatTdfTimestamp(modifiedAt)}\n',
        );
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
      for (final link in task.links) {
        buffer.write(
          '    link ${_escapeQuoted(link.title)} ${_escapeQuoted(link.uri)}\n',
        );
      }
      _writeHistoricalConditions(buffer, task.conditions);
      if (task.subtasks.isNotEmpty || task.subtasksAutoFinish) {
        buffer.write('    subtasks');
        if (task.subtasksAutoFinish) {
          buffer.write(' auto-finish');
        }
        buffer.write(' {\n');
        for (final step in task.subtasks) {
          buffer.write(
            '        step ${step.isCompleted ? "true" : "false"} ${_escapeQuoted(step.title)}\n',
          );
        }
        buffer.write('    }\n');
      }
      buffer.write('}\n\n');
    }
    return buffer.toString();
  }

  /// Validates label references and dependency cycles in a historical document.
  static void _validateHistoricalReferencesAndCycles({
    required List<_HistoricalLabel> labels,
    required List<_HistoricalTask> tasks,
    required Set<String> seenLabelIds,
    required String sourceVersion,
    required String targetVersion,
  }) {
    final taskById = <String, _HistoricalTask>{
      for (final task in tasks) task.id: task,
    };
    for (final task in tasks) {
      for (final labelId in task.labelIds) {
        if (!seenLabelIds.contains(labelId)) {
          throw TdfException(
            kind: TdfErrorKind.unknownLabelReference,
            line: task.labelsLine,
            sourceVersion: sourceVersion,
            targetVersion: targetVersion,
            message: 'Unknown label reference "$labelId".',
          );
        }
      }
    }
    final visitState = <String, int>{};
    for (final task in tasks) {
      _checkHistoricalCycle(
        task.id,
        taskById,
        visitState,
        task.blockedLine,
        sourceVersion,
        targetVersion,
      );
    }
  }

  /// Checks for dependency cycles in a historical task map.
  static void _checkHistoricalCycle(
    String taskId,
    Map<String, _HistoricalTask> taskById,
    Map<String, int> visitState,
    int fallbackLine,
    String sourceVersion,
    String targetVersion,
  ) {
    final state = visitState[taskId] ?? 0;
    if (state == 2) {
      return;
    }
    if (state == 1) {
      throw TdfException(
        kind: TdfErrorKind.circularDependency,
        line: fallbackLine,
        sourceVersion: sourceVersion,
        targetVersion: targetVersion,
        message: 'Circular dependency involving "$taskId".',
      );
    }
    final entry = taskById[taskId];
    if (entry == null) {
      visitState[taskId] = 2;
      return;
    }
    visitState[taskId] = 1;
    for (final blockerId in entry.blockedByTaskIds) {
      _checkHistoricalCycle(
        blockerId,
        taskById,
        visitState,
        entry.blockedLine,
        sourceVersion,
        targetVersion,
      );
    }
    visitState[taskId] = 2;
  }

  /// Validates target `0.5.0` condition count and text length bounds on [label] per Section 10.5.
  static void _validateTargetLabelBounds(_HistoricalLabel label) {
    final nameScalars = TdfCalendar.countUnicodeScalars(label.name);
    if (nameScalars == null || nameScalars > TdfService.maxTextLength) {
      throw TdfException(
        kind: nameScalars == null
            ? TdfErrorKind.unexpectedToken
            : TdfErrorKind.limitExceeded,
        line: label.nameLine,
        sourceVersion: '0.4.0',
        targetVersion: '0.5.0',
        message: 'Label name exceeds MAX_TEXT_LENGTH.',
      );
    }
    if (label.note case final note?) {
      final noteScalars = TdfCalendar.countUnicodeScalars(note);
      if (noteScalars == null || noteScalars > TdfService.maxNoteLength) {
        throw TdfException(
          kind: noteScalars == null
              ? TdfErrorKind.unexpectedToken
              : TdfErrorKind.limitExceeded,
          line: label.noteLine,
          sourceVersion: '0.4.0',
          targetVersion: '0.5.0',
          message: 'Label note exceeds MAX_NOTE_LENGTH.',
        );
      }
    }
    if (label.conditions.length > TdfService.maxConditionRulesPerEntity) {
      final line =
          label.conditionLines.length > TdfService.maxConditionRulesPerEntity
          ? label.conditionLines[TdfService.maxConditionRulesPerEntity]
          : label.headerLine;
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
  static void _validateTargetTaskBounds(_HistoricalTask task) {
    final nameScalars = TdfCalendar.countUnicodeScalars(task.name);
    if (nameScalars == null || nameScalars > TdfService.maxTextLength) {
      throw TdfException(
        kind: nameScalars == null
            ? TdfErrorKind.unexpectedToken
            : TdfErrorKind.limitExceeded,
        line: task.nameLine,
        sourceVersion: '0.4.0',
        targetVersion: '0.5.0',
        message: 'Task name exceeds MAX_TEXT_LENGTH.',
      );
    }
    if (task.note case final note?) {
      final noteScalars = TdfCalendar.countUnicodeScalars(note);
      if (noteScalars == null || noteScalars > TdfService.maxNoteLength) {
        throw TdfException(
          kind: noteScalars == null
              ? TdfErrorKind.unexpectedToken
              : TdfErrorKind.limitExceeded,
          line: task.noteLine,
          sourceVersion: '0.4.0',
          targetVersion: '0.5.0',
          message: 'Task note exceeds MAX_NOTE_LENGTH.',
        );
      }
    }
    if (task.conditions.length > TdfService.maxConditionRulesPerEntity) {
      final line =
          task.conditionLines.length > TdfService.maxConditionRulesPerEntity
          ? task.conditionLines[TdfService.maxConditionRulesPerEntity]
          : task.headerLine;
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: line,
        sourceVersion: '0.4.0',
        targetVersion: '0.5.0',
        message: 'Task exceeds MAX_CONDITION_RULES_PER_ENTITY (512).',
      );
    }
  }

  /// Writes historical conditions to [buffer] preserving rules even when exceeding 512 in intermediate steps.
  static void _writeHistoricalConditions(
    StringBuffer buffer,
    List<TaskCondition> conditions,
  ) {
    if (conditions.isEmpty) {
      return;
    }
    if (conditions.length == 1) {
      buffer.write('    condition ${conditions.first.toTdfDirectiveArgs()}\n');
      return;
    }
    for (final rule in conditions) {
      buffer.write('    condition ${rule.toTdfDirectiveArgs()}\n');
    }
  }
}

/// Token kinds emitted while scanning historical TDF lines.
enum _HistTokenKind { bareWord, closeBrace, openBrace, quotedString }

/// A single lexical token from a historical TDF line.
@immutable
class _HistToken {
  /// Creates a [_HistToken].
  const _HistToken({required this.value, required this.kind});

  /// Token classification.
  final _HistTokenKind kind;

  /// Unescaped token text.
  final String value;
}

/// Mutable builder for a historical `condition { ... }` nested block.
class _HistoricalCondBlockBuilder {
  /// Creates a [_HistoricalCondBlockBuilder] attached to [parent].
  _HistoricalCondBlockBuilder({required this.parent});

  /// Parent label or task builder.
  final Object parent;

  /// Whether at least one condition rule was parsed inside the block.
  bool hasRules = false;
}

/// Parsed representation of a historical TDF 0.2.0–0.4.0 document.
@immutable
class _HistoricalDocument {
  /// Creates a [_HistoricalDocument].
  const _HistoricalDocument({required this.labels, required this.tasks});

  /// Ordered historical label declarations.
  final List<_HistoricalLabel> labels;

  /// Ordered historical task declarations.
  final List<_HistoricalTask> tasks;
}

/// Immutable representation of a historical `label` block.
@immutable
class _HistoricalLabel {
  /// Creates a [_HistoricalLabel].
  const _HistoricalLabel({
    required this.id,
    required this.name,
    required this.headerLine,
    required this.nameLine,
    this.color,
    this.note,
    this.noteLine = 0,
    this.modifiedAt,
    this.conditions = const <TaskCondition>[],
    this.conditionLines = const <int>[],
  });

  /// Optional 6-digit hex color.
  final String? color;

  /// 1-based line numbers for each parsed condition rule.
  final List<int> conditionLines;

  /// Parsed context condition rules.
  final List<TaskCondition> conditions;

  /// 1-based line number of the block header.
  final int headerLine;

  /// Raw historical label ID.
  final String id;

  /// Optional modification timestamp.
  final DateTime? modifiedAt;

  /// Display name of the label.
  final String name;

  /// 1-based line number of the `name` directive.
  final int nameLine;

  /// Optional multi-line note text.
  final String? note;

  /// 1-based line number of the `note` directive.
  final int noteLine;

  /// Returns a copy of this label with updated fields.
  _HistoricalLabel copyWith({String? id}) {
    return _HistoricalLabel(
      id: id ?? this.id,
      name: name,
      headerLine: headerLine,
      nameLine: nameLine,
      color: color,
      note: note,
      noteLine: noteLine,
      modifiedAt: modifiedAt,
      conditions: conditions,
      conditionLines: conditionLines,
    );
  }
}

/// Mutable builder for a historical `label` block.
class _HistoricalLabelBuilder {
  /// Creates a [_HistoricalLabelBuilder].
  _HistoricalLabelBuilder({required this.id, required this.headerLine});

  /// 1-based line numbers for each parsed condition rule.
  final List<int> conditionLines = <int>[];

  /// Accumulated context condition rules.
  final List<TaskCondition> conditions = <TaskCondition>[];

  /// 1-based line number of the block header.
  final int headerLine;

  /// Raw historical label ID.
  final String id;

  /// Optional 6-digit hex color.
  String? color;

  /// Optional modification timestamp.
  DateTime? modifiedAt;

  /// Display name of the label.
  String? name;

  /// 1-based line number of the `name` directive.
  int nameLine = 0;

  /// Optional multi-line note text.
  String? note;

  /// 1-based line number of the `note` directive.
  int noteLine = 0;

  /// Validates required directives and builds an immutable [_HistoricalLabel].
  _HistoricalLabel build(
    int lineNumber,
    String sourceVersion,
    String targetVersion,
  ) {
    final resolvedName = name;
    if (resolvedName == null) {
      throw TdfException(
        kind: TdfErrorKind.missingRequiredDirective,
        line: lineNumber,
        sourceVersion: sourceVersion,
        targetVersion: targetVersion,
        message: 'Label "$id" is missing "name".',
      );
    }
    return _HistoricalLabel(
      id: id,
      name: resolvedName,
      headerLine: headerLine,
      nameLine: nameLine,
      color: color,
      note: note,
      noteLine: noteLine,
      modifiedAt: modifiedAt,
      conditions: List<TaskCondition>.unmodifiable(conditions),
      conditionLines: List<int>.unmodifiable(conditionLines),
    );
  }
}

/// Mutable builder for a historical `subtasks { ... }` nested block.
class _HistoricalSubtasksBuilder {
  /// Creates a [_HistoricalSubtasksBuilder].
  _HistoricalSubtasksBuilder({required this.autoFinish});

  /// Whether `auto-finish` was specified on the `subtasks` header.
  final bool autoFinish;

  /// Accumulated checklist steps.
  final List<SubtaskItem> steps = <SubtaskItem>[];
}

/// Immutable representation of a historical `task` or `task!` block.
@immutable
class _HistoricalTask {
  /// Creates a [_HistoricalTask].
  const _HistoricalTask({
    required this.id,
    required this.isPriority,
    required this.name,
    required this.createdAt,
    required this.headerLine,
    required this.nameLine,
    required this.createdLine,
    this.note,
    this.noteLine = 0,
    this.queuedAt,
    this.queuedLine = 0,
    this.completedAt,
    this.finishedLine = 0,
    this.modifiedAt,
    this.suspendedAt,
    this.suspendedLine = 0,
    this.repeatRule,
    this.labelIds = const <String>[],
    this.labelsLine = 0,
    this.blockedByTaskIds = const <String>[],
    this.blockedLine = 0,
    this.links = const <TaskLink>[],
    this.linkLines = const <int>[],
    this.conditions = const <TaskCondition>[],
    this.conditionLines = const <int>[],
    this.subtasksAutoFinish = false,
    this.subtasks = const <SubtaskItem>[],
  });

  /// Prerequisite task IDs from a `blocked` directive.
  final List<String> blockedByTaskIds;

  /// 1-based line number of the `blocked` directive.
  final int blockedLine;

  /// Optional completion timestamp.
  final DateTime? completedAt;

  /// 1-based line numbers for each parsed condition rule.
  final List<int> conditionLines;

  /// Parsed context condition rules.
  final List<TaskCondition> conditions;

  /// Creation timestamp.
  final DateTime createdAt;

  /// 1-based line number of the `created` directive.
  final int createdLine;

  /// 1-based line number of the `finished` directive.
  final int finishedLine;

  /// 1-based line number of the block header.
  final int headerLine;

  /// Raw historical task ID.
  final String id;

  /// Whether the task has priority (`task!` or `priority`).
  final bool isPriority;

  /// Attached label IDs.
  final List<String> labelIds;

  /// 1-based line number of the `labels` directive.
  final int labelsLine;

  /// 1-based line numbers for each `link` directive.
  final List<int> linkLines;

  /// Parsed task links.
  final List<TaskLink> links;

  /// Optional modification timestamp.
  final DateTime? modifiedAt;

  /// Task title.
  final String name;

  /// 1-based line number of the `name` directive.
  final int nameLine;

  /// Optional multi-line note text.
  final String? note;

  /// 1-based line number of the `note` directive.
  final int noteLine;

  /// Optional queue entry timestamp.
  final DateTime? queuedAt;

  /// 1-based line number of the `queued` directive.
  final int queuedLine;

  /// Optional recurrence rule.
  final TaskRepeatRule? repeatRule;

  /// Checklist subtasks.
  final List<SubtaskItem> subtasks;

  /// Whether completing all subtasks automatically finishes the task.
  final bool subtasksAutoFinish;

  /// Optional deferral timestamp.
  final DateTime? suspendedAt;

  /// 1-based line number of the `suspended` directive.
  final int suspendedLine;

  /// Returns a copy of this historical task with updated fields.
  _HistoricalTask copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? queuedAt,
    DateTime? completedAt,
    List<String>? labelIds,
    List<String>? blockedByTaskIds,
  }) {
    return _HistoricalTask(
      id: id ?? this.id,
      isPriority: isPriority,
      name: name,
      createdAt: createdAt ?? this.createdAt,
      headerLine: headerLine,
      nameLine: nameLine,
      createdLine: createdLine,
      note: note,
      noteLine: noteLine,
      queuedAt: queuedAt ?? this.queuedAt,
      queuedLine: queuedLine,
      completedAt: completedAt ?? this.completedAt,
      finishedLine: finishedLine,
      modifiedAt: modifiedAt,
      suspendedAt: suspendedAt,
      suspendedLine: suspendedLine,
      repeatRule: repeatRule,
      labelIds: labelIds ?? this.labelIds,
      labelsLine: labelsLine,
      blockedByTaskIds: blockedByTaskIds ?? this.blockedByTaskIds,
      blockedLine: blockedLine,
      links: links,
      linkLines: linkLines,
      conditions: conditions,
      conditionLines: conditionLines,
      subtasksAutoFinish: subtasksAutoFinish,
      subtasks: subtasks,
    );
  }
}

/// Mutable builder for a historical `task` or `task!` block.
class _HistoricalTaskBuilder {
  /// Creates a [_HistoricalTaskBuilder].
  _HistoricalTaskBuilder({
    required this.id,
    required this.isPriority,
    required this.headerLine,
  });

  /// Prerequisite task IDs from a `blocked` directive.
  final List<String> blockedByTaskIds = <String>[];

  /// 1-based line numbers for each parsed condition rule.
  final List<int> conditionLines = <int>[];

  /// Accumulated context condition rules.
  final List<TaskCondition> conditions = <TaskCondition>[];

  /// 1-based line number of the block header.
  final int headerLine;

  /// Raw historical task ID.
  final String id;

  /// Whether the task has priority (`task!` or `priority`).
  final bool isPriority;

  /// Attached label IDs.
  final List<String> labelIds = <String>[];

  /// 1-based line numbers for each `link` directive.
  final List<int> linkLines = <int>[];

  /// Accumulated task links.
  final List<TaskLink> links = <TaskLink>[];

  /// 1-based line number of the `blocked` directive.
  int blockedLine = 0;

  /// Optional completion timestamp.
  DateTime? completedAt;

  /// Creation timestamp.
  DateTime? createdAt;

  /// 1-based line number of the `created` directive.
  int createdLine = 0;

  /// 1-based line number of the `finished` directive.
  int finishedLine = 0;

  /// 1-based line number of the `labels` directive.
  int labelsLine = 0;

  /// Optional modification timestamp.
  DateTime? modifiedAt;

  /// Task title.
  String? name;

  /// 1-based line number of the `name` directive.
  int nameLine = 0;

  /// Optional multi-line note text.
  String? note;

  /// 1-based line number of the `note` directive.
  int noteLine = 0;

  /// Optional queue entry timestamp.
  DateTime? queuedAt;

  /// 1-based line number of the `queued` directive.
  int queuedLine = 0;

  /// Optional recurrence rule.
  TaskRepeatRule? repeatRule;

  /// Checklist subtasks.
  List<SubtaskItem> subtasks = const <SubtaskItem>[];

  /// Whether completing all subtasks automatically finishes the task.
  bool subtasksAutoFinish = false;

  /// Optional deferral timestamp.
  DateTime? suspendedAt;

  /// 1-based line number of the `suspended` directive.
  int suspendedLine = 0;

  /// Validates required directives and builds an immutable [_HistoricalTask].
  _HistoricalTask build(
    int lineNumber,
    String sourceVersion,
    String targetVersion,
  ) {
    final resolvedName = name;
    final resolvedCreated = createdAt;
    if (resolvedName == null || resolvedCreated == null) {
      throw TdfException(
        kind: TdfErrorKind.missingRequiredDirective,
        line: lineNumber,
        sourceVersion: sourceVersion,
        targetVersion: targetVersion,
        message: 'Task "$id" is missing "name" or "created".',
      );
    }
    return _HistoricalTask(
      id: id,
      isPriority: isPriority,
      name: resolvedName,
      createdAt: resolvedCreated,
      headerLine: headerLine,
      nameLine: nameLine,
      createdLine: createdLine,
      note: note,
      noteLine: noteLine,
      queuedAt: queuedAt,
      queuedLine: queuedLine,
      completedAt: completedAt,
      finishedLine: finishedLine,
      modifiedAt: modifiedAt,
      suspendedAt: suspendedAt,
      suspendedLine: suspendedLine,
      repeatRule: repeatRule,
      labelIds: List<String>.unmodifiable(labelIds),
      labelsLine: labelsLine,
      blockedByTaskIds: List<String>.unmodifiable(blockedByTaskIds),
      blockedLine: blockedLine,
      links: List<TaskLink>.unmodifiable(links),
      linkLines: List<int>.unmodifiable(linkLines),
      conditions: List<TaskCondition>.unmodifiable(conditions),
      conditionLines: List<int>.unmodifiable(conditionLines),
      subtasksAutoFinish: subtasksAutoFinish,
      subtasks: subtasks,
    );
  }
}
