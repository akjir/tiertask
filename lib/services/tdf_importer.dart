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
import '../models/tdf_timezone.dart';
import 'app_logger.dart';
import 'tdf_historical_parser.dart';
import 'tdf_historical_serializer.dart';
import 'tdf_parser.dart';
import 'tdf_serializer.dart';

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

  /// Evaluated target `0.6.0` [TaskBoard].
  final TaskBoard board;

  /// Ordered sequence of schema versions traversed during import (for example `['0.2.0', '0.3.0', '0.4.0', '0.5.0', '0.5.1', '0.6.0']`).
  final List<String> executedSteps;

  /// Canonical `tdf 0.6.0` document string produced by the migration chain.
  final String migratedTdfContent;

  /// Declared version of the input document (`0.2.0`, `0.3.0`, `0.4.0`, `0.5.0`, `0.5.1`, or `0.6.0`).
  final String sourceVersion;
}

/// Stateless service implementing the explicit `0.2.0 -> 0.3.0 -> 0.4.0 -> 0.5.0 -> 0.5.1 -> 0.6.0`
/// version import and adjacent migration chain defined in `spec/TDF_SPEC_0.6.0.md` Section 10.
@immutable
class TdfImporter {
  /// Prevents instantiation of this stateless service.
  const TdfImporter._();

  /// Ordered list of all pinned historical TDF schema snapshot references (`0.2.0` through `0.5.1`).
  static const List<({String version, String commit, String blob})>
  historicalSchemaReferences = <({String version, String commit, String blob})>[
    schemaRef020,
    schemaRef030,
    schemaRef040,
    schemaRef050,
    schemaRef051,
  ];

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

  /// Historical schema snapshot reference for `0.5.0` (`TDF_SPEC.md` Section 10.1.1).
  static const ({String version, String commit, String blob}) schemaRef050 = (
    version: '0.5.0',
    commit: 'e64e6a554bdbc2f6d5d76eacb900ae36d8c9b25b',
    blob: '8b492e7dfedea819ddeb9a2f0663d28fa8b08dfc',
  );

  /// Historical schema snapshot reference for `0.5.1` (`spec/TDF_SPEC_0.6.0.md` Section 10.1.1).
  static const ({String version, String commit, String blob}) schemaRef051 = (
    version: '0.5.1',
    commit: '8580e166417811432b11303f8c26d544c9819284',
    blob: 'f0059d292dc2b82124e8228718ca0b08d6c2c886',
  );

  /// Validates and migrates [sourceContent] through the adjacent migration chain (`0.2.0 -> 0.3.0 -> 0.4.0 -> 0.5.0 -> 0.5.1 -> 0.6.0`).
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
    if (executedSteps.last == '0.5.0') {
      currentDoc = migrate050To051(currentDoc);
      executedSteps.add('0.5.1');
    }
    if (executedSteps.last == '0.5.1') {
      currentDoc = migrate051To060(currentDoc);
      executedSteps.add('0.6.0');
    }

    final board = TdfBlockParser.parseDocument(
      currentDoc,
      evaluationTime: evaluationTime,
      localEvaluationTime: localEvaluationTime,
      timeZone: evaluationTimeZone,
      activeLabelId: activeLabelId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
      pruneExpiredCompleted: false,
    );
    final canonicalDoc = TdfSerializer.serialize(board);
    AppLogger.info(
      LogTag.tdf,
      'TdfImporter.importDocument steps=${executedSteps.join("->")} tasks=${board.allTasks.length} labels=${board.labels.length} locations=${board.locations.length} elapsed=${stopwatch.elapsedMilliseconds}ms',
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
    final doc = TdfHistoricalParser.parseDocument(
      source020,
      expectedVersion: '0.2.0',
      targetVersion: '0.3.0',
    );
    if (doc.tasks.isNotEmpty &&
        (sourceTimeZone == null || !sourceTimeZone.isAvailable)) {
      throw TdfContextException(
        kind: TdfContextOutcomeKind.importContextRequired,
        line: doc.tasks.first.lineOf('created'),
        message: 'Migration 0.2.0 -> 0.3.0 requires an explicit source time zone to convert local event timestamps.',
      );
    }

    final convertedTasks = <TdfHistoricalTask>[];
    for (final task in doc.tasks) {
      final zone = sourceTimeZone ?? TdfTimeZoneContext.utc;
      final createdUtc = _convertLocalTimestampToUtc(
        task.createdAt,
        zone: zone,
        line: task.lineOf('created'),
        sourceVersion: '0.2.0',
        targetVersion: '0.3.0',
      );
      final queuedUtc = task.queuedAt == null
          ? null
          : _convertLocalTimestampToUtc(
              task.queuedAt,
              zone: zone,
              line: task.lineOf('queued'),
              sourceVersion: '0.2.0',
              targetVersion: '0.3.0',
            );
      final finishedUtc = task.completedAt == null
          ? null
          : _convertLocalTimestampToUtc(
              task.completedAt,
              zone: zone,
              line: task.lineOf('finished'),
              sourceVersion: '0.2.0',
              targetVersion: '0.3.0',
            );
      convertedTasks.add(
        task.copyWith(dates: <DateTime?>[createdUtc, queuedUtc, finishedUtc]),
      );
    }

    final serialized030 = TdfHistoricalSerializer.serializeHistoricalDocument(
      version: '0.3.0',
      labels: doc.labels,
      tasks: convertedTasks,
    );
    TdfHistoricalParser.parseDocument(
      serialized030,
      expectedVersion: '0.3.0',
      targetVersion: '0.3.0',
    );
    return serialized030;
  }

  /// Executes the adjacent `0.3.0 -> 0.4.0` file conversion defined in `TDF_SPEC.md` Section 10.4.
  static String migrate030To040(String source030) {
    final doc = TdfHistoricalParser.parseDocument(
      source030,
      expectedVersion: '0.3.0',
      targetVersion: '0.4.0',
    );
    final rewritten = TdfHistoricalSerializer.rewriteNoncanonicalIds(
      doc,
      sourceVersion: '0.3.0',
      targetVersion: '0.4.0',
    );
    final serialized040 = TdfHistoricalSerializer.serializeHistoricalDocument(
      version: '0.4.0',
      labels: rewritten.labels,
      tasks: rewritten.tasks,
    );
    TdfHistoricalParser.parseDocument(
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
    final doc = TdfHistoricalParser.parseDocument(
      source040,
      expectedVersion: '0.4.0',
      targetVersion: '0.5.0',
    );
    final rewritten = TdfHistoricalSerializer.rewriteNoncanonicalIds(
      doc,
      sourceVersion: '0.4.0',
      targetVersion: '0.5.0',
    );

    final labels050 = <TdfLabel>[];
    for (final label in rewritten.labels) {
      TdfHistoricalSerializer.validateTargetLabelBounds(label);
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

    final tasks050 = <({TaskItem task, DateTime? queuedAt})>[];
    for (final task in rewritten.tasks) {
      tasks050.add(
        _convertHistoricalTaskTo050(task, sourceTimeZone: sourceTimeZone),
      );
    }

    final queueBlock = _buildLegacyQueueBlock(tasks050);
    final serialized050 = TdfHistoricalSerializer.serializeDocument050(
      labels: labels050,
      tasks: tasks050,
      queueBlock: queueBlock,
    );
    TdfBlockParser.parseDocument(
      serialized050,
      pruneExpiredCompleted: false,
      convertLegacyLocationsTo060: false,
    );
    return serialized050;
  }

  /// Executes the adjacent `0.5.0 -> 0.5.1` file conversion defined in `spec/TDF_SPEC_0.6.0.md` Section 10.6.
  static String migrate050To051(String source050) {
    final version = _detectDeclaredVersion(source050);
    if (version != '0.5.0') {
      throw TdfException(
        kind: TdfErrorKind.unsupportedVersion,
        line: 1,
        sourceVersion: '0.5.0',
        targetVersion: '0.5.1',
        message:
            'Expected source version "0.5.0" for 0.5.0 -> 0.5.1 migration, found "$version".',
      );
    }
    try {
      final board = TdfBlockParser.parseDocument(
        source050,
        pruneExpiredCompleted: false,
        convertLegacyLocationsTo060: false,
      );
      final serialized051 = TdfHistoricalSerializer.serializeDocument051(board);
      TdfBlockParser.parseDocument(
        serialized051,
        pruneExpiredCompleted: false,
        convertLegacyLocationsTo060: false,
      );
      return serialized051;
    } on TdfException catch (error) {
      throw TdfException(
        kind: error.kind,
        line: error.line,
        sourceVersion: '0.5.0',
        targetVersion: '0.5.1',
        message: error.message,
      );
    }
  }

  /// Executes the adjacent `0.5.1 -> 0.6.0` file conversion defined in `spec/TDF_SPEC_0.6.0.md` Section 10.7.
  static String migrate051To060(String source051) {
    final version = _detectDeclaredVersion(source051);
    if (version != '0.5.1') {
      throw TdfException(
        kind: TdfErrorKind.unsupportedVersion,
        line: 1,
        sourceVersion: '0.5.1',
        targetVersion: '0.6.0',
        message:
            'Expected source version "0.5.1" for 0.5.1 -> 0.6.0 migration, found "$version".',
      );
    }
    try {
      final board = TdfBlockParser.parseDocument(
        source051,
        pruneExpiredCompleted: false,
        convertLegacyLocationsTo060: true,
      );
      final serialized060 = TdfSerializer.serialize(board);
      TdfBlockParser.parseDocument(serialized060, pruneExpiredCompleted: false);
      return serialized060;
    } on TdfException catch (error) {
      throw TdfException(
        kind: error.kind,
        line: error.line,
        sourceVersion: '0.5.1',
        targetVersion: '0.6.0',
        message: error.message,
      );
    }
  }

  /// Builds the shared `0.5.0` [TdfQueueBlock] preserving the `0.4.0` effective queue order per Section 10.5.
  static TdfQueueBlock _buildLegacyQueueBlock(
    List<({TaskItem task, DateTime? queuedAt})> tasks,
  ) {
    final indexed = <({int index, TaskItem task, DateTime queuedAt})>[];
    for (var i = 0; i < tasks.length; i++) {
      final entry = tasks[i];
      if (entry.queuedAt case final queuedAt?
          when !entry.task.isCompleted && entry.task.completedAt == null) {
        indexed.add((index: i, task: entry.task, queuedAt: queuedAt));
      }
    }
    if (indexed.isEmpty) {
      return TdfQueueBlock.empty;
    }
    indexed.sort((left, right) {
      if (left.task.isPriority != right.task.isPriority) {
        return left.task.isPriority ? -1 : 1;
      }
      final timeComparison = left.queuedAt.compareTo(right.queuedAt);
      if (timeComparison != 0) {
        return timeComparison;
      }
      return left.index.compareTo(right.index);
    });
    DateTime? maxModified;
    final orderedIds = <String>[];
    for (final entry in indexed) {
      orderedIds.add(entry.task.id);
      var effective = entry.task.effectiveModifiedAt;
      if (entry.task.modifiedAt == null && entry.queuedAt.isAfter(effective)) {
        effective = entry.queuedAt;
      }
      if (maxModified == null || effective.isAfter(maxModified)) {
        maxModified = effective;
      }
    }
    return TdfQueueBlock(
      modifiedAt: maxModified ?? TdfQueueBlock.epochModifiedAt,
      taskIds: orderedIds,
    );
  }

  /// Converts a validated `0.4.0` [TdfHistoricalTask] into a `0.5.0` [TaskItem] and optional `queuedAt` timestamp per Section 10.5.
  static ({TaskItem task, DateTime? queuedAt}) _convertHistoricalTaskTo050(
    TdfHistoricalTask task, {
    required TdfTimeZoneContext? sourceTimeZone,
  }) {
    TdfHistoricalSerializer.validateTargetTaskBounds(task);

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
            line: task.lineOf('suspended'),
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
          line: task.lineOf('suspended'),
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

    return (
      task: TaskItem(
        id: task.id,
        title: task.name,
        note: task.note,
        isCompleted: isFinished,
        isPriority: task.isPriority,
        completions: isFinished ? 1 : 0,
        createdAt: task.createdAt,
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
      ),
      queuedAt: task.queuedAt,
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

  /// Scans the first statement of [source] and returns its declared version (`0.2.0`..`0.5.1`).
  static String _detectDeclaredVersion(String source) {
    if (source.length > maxTdfFileBytes ||
        utf8.encode(source).length > maxTdfFileBytes) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message: 'TDF document exceeds maximum file size.',
      );
    }
    final firstStatement = TdfHistoricalParser.scanFirstStatement(source);
    if (firstStatement == null) {
      throw const TdfException(
        kind: TdfErrorKind.missingVersionHeader,
        line: 1,
        message: 'Empty TDF document is missing version header.',
      );
    }
    final bareWords = firstStatement.bareWords;
    if (bareWords.isEmpty || bareWords.first != 'tdf') {
      throw TdfException(
        kind: TdfErrorKind.missingVersionHeader,
        line: firstStatement.line,
        message: 'Document must start with a "tdf <version>" header.',
      );
    }
    if (!firstStatement.hasNonBareWords && bareWords.length == 1) {
      throw TdfException(
        kind: TdfErrorKind.missingVersionHeader,
        line: firstStatement.line,
        message: 'Version header "tdf" requires a version argument.',
      );
    }
    if (firstStatement.hasNonBareWords || bareWords.length != 2) {
      throw TdfException(
        kind: TdfErrorKind.unsupportedVersion,
        line: firstStatement.line,
        message: 'Malformed version header.',
      );
    }
    final version = bareWords[1];
    if (version != '0.2.0' &&
        version != '0.3.0' &&
        version != '0.4.0' &&
        version != '0.5.0' &&
        version != '0.5.1' &&
        version != '0.6.0') {
      throw TdfException(
        kind: TdfErrorKind.unsupportedVersion,
        line: firstStatement.line,
        message: 'Unsupported TDF version "$version" for import.',
      );
    }
    return version;
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
}
