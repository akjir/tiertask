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
import '../models/tdf_sync_metadata.dart';
import '../models/tdf_timezone.dart';
import 'app_logger.dart';
import 'tdf_importer.dart';
import 'tdf_parser.dart';
import 'tdf_serializer.dart';

/// Stateless service that scans, parses, validates, and serializes TierTask Data Format (`.tdf`) `0.5.1` documents
/// in a single $O(N)$ linear pass without regular expressions.
class TdfService {
  /// Creates a const [TdfService].
  const TdfService();

  /// Legacy TDF specification version string (`tdf 0.5.0`) converted in memory at load time per Section 10.6.
  static const String legacySupportedVersion =
      TdfBlockParser.legacySupportedVersion;

  /// Maximum arguments allowed on a single block header or directive (`MAX_ARGS_PER_STMT`).
  static const int maxArgsPerStmt = maxTdfArgsPerStmt;

  /// Maximum total blocks per `.tdf` document (`MAX_BLOCKS_PER_DOC`).
  static const int maxBlocksPerDoc = maxTdfBlocksPerDoc;

  /// Maximum completion counter, deletion checkpoint, and prerequisite completion number (`MAX_COMPLETIONS`).
  static const int maxCompletions = TdfTaskDependency.maxCompletions;

  /// Maximum stored condition rules across all inline directives and condition blocks on one entity (`MAX_CONDITION_RULES_PER_ENTITY`).
  static const int maxConditionRulesPerEntity = maxTdfConditionRulesPerEntity;

  /// Maximum task and label deletion records in the shared `deleted` block (`MAX_DELETED_RECORDS`).
  static const int maxDeletedRecords = TdfDeletedBlock.maxDeletedRecords;

  /// Maximum input or serialized output size in UTF-8 bytes (`MAX_FILE_BYTES`, 1 MiB).
  static const int maxFileBytes = maxTdfFileBytes;

  /// Maximum logical lines per `.tdf` document (`MAX_LINE_COUNT`).
  static const int maxLineCount = maxTdfLineCount;

  /// Maximum `link` directives per `task` block (`MAX_LINKS_PER_TASK`).
  static const int maxLinksPerTask = TaskLink.maxLinksPerTask;

  /// Maximum `{ ... }` block nesting depth (`MAX_NESTING_DEPTH`).
  static const int maxNestingDepth = maxTdfNestingDepth;

  /// Maximum decoded Unicode scalar values in a `note` text value (`MAX_NOTE_LENGTH`).
  static const int maxNoteLength = maxTdfNoteLength;

  /// Maximum `task` entries in the shared `queue` block (`MAX_QUEUE_ENTRIES`).
  static const int maxQueueEntries = TdfQueueBlock.maxQueueEntries;

  /// Maximum recurrence interval count `<count>` in `repeat <count> <unit>` (`MAX_REPEAT_COUNT`).
  static const int maxRepeatCount = TaskRepeatRule.maxRepeatCount;

  /// Maximum direct child statements per ordinary block (`MAX_STMTS_PER_BLOCK`).
  static const int maxStmtsPerBlock = maxTdfStmtsPerBlock;

  /// Maximum deletion history generation (`MAX_SYNC_GENERATION`).
  static const int maxSyncGeneration = TdfDeletedBlock.maxGeneration;

  /// Maximum decoded Unicode scalar values in a `name`, `step`, or link `<title>` (`MAX_TEXT_LENGTH`).
  static const int maxTextLength = maxTdfTextLength;

  /// Maximum decoded Unicode scalar values in a `link` `<uri>` (`MAX_URI_LENGTH`).
  static const int maxUriLength = TaskLink.maxUriLength;

  /// Canonical TDF specification version string (`tdf 0.5.1`).
  static const String supportedVersion = TdfBlockParser.supportedVersion;

  /// Explicitly imports and migrates [sourceContent] (`0.2.0`, `0.3.0`, `0.4.0`, `0.5.0`, or `0.5.1`)
  /// through the adjacent Section 10 migration chain (`0.2.0 -> 0.3.0 -> 0.4.0 -> 0.5.0 -> 0.5.1`) into a [TaskBoard].
  TaskBoard importDocument(
    String sourceContent, {
    TdfTimeZoneContext? sourceTimeZone,
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? evaluationTimeZone,
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
  }) => _importInternal(
    sourceContent,
    sourceTimeZone: sourceTimeZone,
    evaluationTime: evaluationTime,
    localEvaluationTime: localEvaluationTime,
    evaluationTimeZone: evaluationTimeZone,
    activeLabelId: activeLabelId,
    currentLatitude: currentLatitude,
    currentLongitude: currentLongitude,
  );

  /// Scans and parses a `tdf 0.5.1` (or legacy `tdf 0.5.0`) [tdfContent] string into a [TaskBoard] evaluated at [evaluationTime].
  TaskBoard parse(
    String tdfContent, {
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
    bool pruneExpiredCompleted = false,
  }) {
    final stopwatch = Stopwatch()..start();
    try {
      final board = _parseInternal(
        tdfContent,
        evaluationTime: evaluationTime,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
        activeLabelId: activeLabelId,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
        pruneExpiredCompleted: pruneExpiredCompleted,
      );
      AppLogger.info(
        LogTag.tdf,
        'TdfService.parse v$supportedVersion tasks=${board.allTasks.length} labels=${board.labels.length} elapsed=${stopwatch.elapsedMilliseconds}ms',
      );
      return board;
    } on TdfException catch (error) {
      AppLogger.error(
        LogTag.tdf,
        'TdfService.parse failed (${error.kind.name} at line ${error.line}): ${error.message}',
      );
      rethrow;
    }
  }

  /// Serializes [board] into a canonical `LF`-terminated `tdf 0.5.1` document string
  /// and validates canonical output against Section 7.1 bounds.
  String serialize(TaskBoard board) => _serializeInternal(board);

  /// Executes the adjacent Section 10 migration chain via [TdfImporter.importDocument].
  TaskBoard _importInternal(
    String sourceContent, {
    TdfTimeZoneContext? sourceTimeZone,
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? evaluationTimeZone,
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
  }) {
    final result = TdfImporter.importDocument(
      sourceContent,
      sourceTimeZone: sourceTimeZone,
      evaluationTime: evaluationTime,
      localEvaluationTime: localEvaluationTime,
      evaluationTimeZone: evaluationTimeZone,
      activeLabelId: activeLabelId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
    );
    return result.board;
  }

  /// Delegates single-pass TDF 0.5.1 (and legacy 0.5.0) scanning and parsing to [TdfBlockParser.parseDocument].
  TaskBoard _parseInternal(
    String tdfContent, {
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
    bool pruneExpiredCompleted = false,
  }) {
    return TdfBlockParser.parseDocument(
      tdfContent,
      evaluationTime: evaluationTime,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      activeLabelId: activeLabelId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
      pruneExpiredCompleted: pruneExpiredCompleted,
    );
  }

  /// Delegates canonical TDF 0.5.1 serialization and bounds validation to [TdfSerializer.serialize].
  String _serializeInternal(TaskBoard board) {
    final stopwatch = Stopwatch()..start();
    final output = TdfSerializer.serialize(board);
    if (board.deletedBlock.isDefaultEmpty &&
        board.queueBlock.isDefaultEmpty &&
        board.labels.isEmpty &&
        board.allTasks.isEmpty) {
      AppLogger.info(
        LogTag.tdf,
        'TdfService.serialize v$supportedVersion tasks=0 labels=0 elapsed=${stopwatch.elapsedMilliseconds}ms',
      );
      return output;
    }
    AppLogger.info(
      LogTag.tdf,
      'TdfService.serialize v$supportedVersion tasks=${board.allTasks.length} labels=${board.labels.length} bytes=${output.length} elapsed=${stopwatch.elapsedMilliseconds}ms',
    );
    return output;
  }
}
