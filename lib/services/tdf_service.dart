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
import 'dart:isolate';

import '../models/task_board.dart';
import '../models/task_board_evaluator.dart';
import '../models/tdf_error.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_timezone.dart';
import 'app_logger.dart';
import 'tdf_parser.dart';
import 'tdf_scanner.dart';
import 'tdf_serializer.dart';

/// Stateless service that scans, parses, validates, and serializes TierTask Data Format (`.tdf`) `0.8.0` documents
/// in a single $O(N)$ linear pass without regular expressions.
class TdfService {
  /// Creates a const [TdfService].
  const TdfService();

  /// Minimum UTF-8 payload byte length (`32 KiB`) at which async helpers offload parsing and serialization to a worker isolate.
  static const int isolateOffloadThresholdBytes = 32768;

  /// Maximum arguments allowed on a single block header or directive (`MAX_ARGS_PER_STMT`).
  static const int maxArgsPerStmt = maxTdfArgsPerStmt;

  /// Maximum total blocks per `.tdf` document (`MAX_BLOCKS_PER_DOC`).
  static const int maxBlocksPerDoc = maxTdfBlocksPerDoc;

  /// Maximum completion counter, deletion checkpoint, and prerequisite completion number (`MAX_COMPLETIONS`).
  static const int maxCompletions = maxTdfCompletions;

  /// Maximum stored condition rules across all inline directives and condition blocks on one entity (`MAX_CONDITION_RULES_PER_ENTITY`).
  static const int maxConditionRulesPerEntity = maxTdfConditionRulesPerEntity;

  /// Maximum task, label, and location deletion records in the shared `deleted` block (`MAX_DELETED_RECORDS`).
  static const int maxDeletedRecords = maxTdfDeletedRecords;

  /// Maximum input or serialized output size in UTF-8 bytes (`MAX_FILE_BYTES`, 1 MiB).
  static const int maxFileBytes = maxTdfFileBytes;

  /// Maximum `history` directives per `task` block before deduplication (`MAX_HISTORY_PER_TASK`).
  static const int maxHistoryPerTask = maxTdfHistoryPerTask;

  /// Maximum logical lines per `.tdf` document (`MAX_LINE_COUNT`).
  static const int maxLineCount = maxTdfLineCount;

  /// Maximum `link` directives per `label` block (`MAX_LINKS_PER_LABEL`).
  static const int maxLinksPerLabel = maxTdfLinksPerLabel;

  /// Maximum `link` directives per `task` block (`MAX_LINKS_PER_TASK`).
  static const int maxLinksPerTask = maxTdfLinksPerTask;

  /// Maximum `radius` in meters (`100 km`) for a `location` block (`MAX_LOCATION_RADIUS`).
  static const int maxLocationRadius = maxTdfLocationRadius;

  /// Maximum `<location-id>` references across all `location` condition rules on one entity (`MAX_LOCATION_REFS_PER_ENTITY`).
  static const int maxLocationRefsPerEntity = maxTdfLocationRefsPerEntity;

  /// Maximum root-level `location` blocks per `.tdf` document (`MAX_LOCATIONS`).
  static const int maxLocations = maxTdfLocations;

  /// Maximum `{ ... }` block nesting depth (`MAX_NESTING_DEPTH`).
  static const int maxNestingDepth = maxTdfNestingDepth;

  /// Maximum decoded Unicode scalar values in a `note` text value (`MAX_NOTE_LENGTH`).
  static const int maxNoteLength = maxTdfNoteLength;

  /// Maximum raw ASCII characters in a `<number>` token (`MAX_NUMBER_LENGTH`).
  static const int maxNumberLength = maxTdfNumberLength;

  /// Maximum `task` entries in the shared `queue` block (`MAX_QUEUE_ENTRIES`).
  static const int maxQueueEntries = maxTdfQueueEntries;

  /// Maximum recurrence interval or lead count in `repeat` (`MAX_REPEAT_COUNT`).
  static const int maxRepeatCount = maxTdfRepeatCount;

  /// Maximum direct child statements per ordinary block (`MAX_STMTS_PER_BLOCK`).
  static const int maxStmtsPerBlock = maxTdfStmtsPerBlock;

  /// Maximum deletion history generation (`MAX_SYNC_GENERATION`).
  static const int maxSyncGeneration = maxTdfSyncGeneration;

  /// Maximum decoded Unicode scalar values in a `name`, `step`, `origin`, `history`, or link `<title>` (`MAX_TEXT_LENGTH`).
  static const int maxTextLength = maxTdfTextLength;

  /// Maximum decoded Unicode scalar values in a `link` `<uri>` (`MAX_URI_LENGTH`).
  static const int maxUriLength = maxTdfUriLength;

  /// Canonical TDF specification version string (`0.8.0`).
  static const String supportedVersion = tdfSupportedVersion;

  /// Strict UTF-8 decoder rejecting malformed byte sequences (`TDF-LEX-001`).
  static const Utf8Decoder _strictUtf8Decoder = Utf8Decoder();

  /// Scans and parses a `tdf 0.8.0` [tdfContent] string into a [TaskBoard] evaluated at [evaluationTime] unless [evaluateTiers] is `false`.
  TaskBoard parse(
    String tdfContent, {
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
    bool pruneExpiredCompleted = false,
    bool evaluateTiers = true,
  }) {
    final stopwatch = Stopwatch()..start();
    try {
      if (!TdfScanner.isUtf8ByteLengthWithinBound(
        tdfContent,
        maxTdfFileBytes,
      )) {
        throw const TdfException(
          kind: TdfErrorKind.limitExceeded,
          line: 1,
          message: 'Document exceeds maximum of $maxTdfFileBytes bytes.',
        );
      }
      return _parseVerifiedContent(
        tdfContent,
        stopwatch: stopwatch,
        evaluationTime: evaluationTime,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
        dueLeadWindow: dueLeadWindow,
        activeLabelId: activeLabelId,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
        pruneExpiredCompleted: pruneExpiredCompleted,
        evaluateTiers: evaluateTiers,
      );
    } on TdfException catch (error) {
      _logParseError(error);
      rethrow;
    }
  }

  /// Asynchronously scans and parses [tdfContent], offloading to a worker isolate when the payload meets [isolateOffloadThresholdBytes] and parameters are isolate-sendable.
  Future<TaskBoard> parseAsync(
    String tdfContent, {
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
    bool pruneExpiredCompleted = false,
    bool evaluateTiers = true,
  }) async {
    final canOffload =
        (timeZone == null || timeZone.isIsolateSendable) &&
        tdfContent.length <= maxTdfFileBytes &&
        _exceedsStringOffloadThreshold(tdfContent);
    if (!canOffload) {
      return parse(
        tdfContent,
        evaluationTime: evaluationTime,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
        dueLeadWindow: dueLeadWindow,
        activeLabelId: activeLabelId,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
        pruneExpiredCompleted: pruneExpiredCompleted,
        evaluateTiers: evaluateTiers,
      );
    }
    final stopwatch = Stopwatch()..start();
    try {
      final board = await _runParseStringIsolate(
        tdfContent,
        evaluationTime: evaluationTime,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
        dueLeadWindow: dueLeadWindow,
        activeLabelId: activeLabelId,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
        pruneExpiredCompleted: pruneExpiredCompleted,
        evaluateTiers: evaluateTiers,
      );
      _logParseSuccess(board, stopwatch);
      return board;
    } on TdfException catch (error) {
      _logParseError(error);
      rethrow;
    }
  }

  /// Validates UTF-8 byte length and encoding of [utf8Bytes] before scanning and parsing a `tdf 0.8.0` document (`TDF-LEX-001`, `TDF-VAL-001`).
  TaskBoard parseBytes(
    List<int> utf8Bytes, {
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
    bool pruneExpiredCompleted = false,
    bool evaluateTiers = true,
  }) {
    final stopwatch = Stopwatch()..start();
    try {
      final decoded = _decodeValidatedUtf8Bytes(utf8Bytes);
      return _parseVerifiedContent(
        decoded,
        stopwatch: stopwatch,
        evaluationTime: evaluationTime,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
        dueLeadWindow: dueLeadWindow,
        activeLabelId: activeLabelId,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
        pruneExpiredCompleted: pruneExpiredCompleted,
        evaluateTiers: evaluateTiers,
      );
    } on TdfException catch (error) {
      _logParseError(error);
      rethrow;
    }
  }

  /// Asynchronously validates and parses [utf8Bytes], offloading to a worker isolate when payload length meets [isolateOffloadThresholdBytes] and parameters are isolate-sendable.
  Future<TaskBoard> parseBytesAsync(
    List<int> utf8Bytes, {
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
    bool pruneExpiredCompleted = false,
    bool evaluateTiers = true,
  }) async {
    final canOffload =
        (timeZone == null || timeZone.isIsolateSendable) &&
        utf8Bytes.length >= isolateOffloadThresholdBytes &&
        utf8Bytes.length <= maxTdfFileBytes;
    if (!canOffload) {
      return parseBytes(
        utf8Bytes,
        evaluationTime: evaluationTime,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
        dueLeadWindow: dueLeadWindow,
        activeLabelId: activeLabelId,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
        pruneExpiredCompleted: pruneExpiredCompleted,
        evaluateTiers: evaluateTiers,
      );
    }
    final stopwatch = Stopwatch()..start();
    try {
      final board = await _runParseBytesIsolate(
        utf8Bytes,
        evaluationTime: evaluationTime,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
        dueLeadWindow: dueLeadWindow,
        activeLabelId: activeLabelId,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
        pruneExpiredCompleted: pruneExpiredCompleted,
        evaluateTiers: evaluateTiers,
      );
      _logParseSuccess(board, stopwatch);
      return board;
    } on TdfException catch (error) {
      _logParseError(error);
      rethrow;
    }
  }

  /// Serializes [board] into a canonical `LF`-terminated `tdf 0.8.0` document string and validates output bounds (`TDF-SER-001`–`TDF-SER-005`).
  String serialize(TaskBoard board) => _serializeInternal(board);

  /// Asynchronously serializes [board], offloading to a worker isolate when estimated output reaches [isolateOffloadThresholdBytes].
  Future<String> serializeAsync(TaskBoard board) async {
    if (_estimateSerializedBytes(board) < isolateOffloadThresholdBytes) {
      return _serializeInternal(board);
    }
    final stopwatch = Stopwatch()..start();
    try {
      final result = await _runSerializeIsolate(board);
      _logSerializeSuccess(board, result.utf8ByteLength, stopwatch);
      return result.output;
    } on TdfException catch (error) {
      _logParseError(error);
      rethrow;
    }
  }

  /// Computes the 1-based physical line number of the first lexical/UTF-8 failure at or before [failureOffset].
  static int _computeUtf8FailureLine(List<int> utf8Bytes, int? failureOffset) {
    final rawOffset = failureOffset ?? 0;
    final clampedOffset = rawOffset < 0
        ? 0
        : (rawOffset > utf8Bytes.length ? utf8Bytes.length : rawOffset);
    var line = 1;
    for (var i = 0; i < clampedOffset; i++) {
      final byte = utf8Bytes[i];
      if (byte == 0x0A) {
        line++;
      } else if (byte == 0x0D) {
        if (i + 1 >= utf8Bytes.length || utf8Bytes[i + 1] != 0x0A) {
          return line;
        }
      } else if ((byte < 0x20 && byte != 0x09) || byte == 0x7F) {
        return line;
      }
    }
    return line;
  }

  /// Enforces `MAX_FILE_BYTES` before decoding [utf8Bytes] strictly as UTF-8.
  static String _decodeValidatedUtf8Bytes(List<int> utf8Bytes) {
    if (utf8Bytes.length > maxTdfFileBytes) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message: 'Document exceeds maximum of $maxTdfFileBytes bytes.',
      );
    }
    try {
      return _strictUtf8Decoder.convert(utf8Bytes);
    } on FormatException catch (error) {
      final line = _computeUtf8FailureLine(utf8Bytes, error.offset);
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: line,
        message: 'Invalid UTF-8 byte sequence.',
      );
    }
  }

  /// Estimates serialized byte size for [board] with early exit at [isolateOffloadThresholdBytes].
  static int _estimateSerializedBytes(TaskBoard board) {
    var estimate =
        16 +
        board.deletedBlock.totalRecords * 36 +
        board.queueBlock.taskIds.length * 16;
    if (estimate >= isolateOffloadThresholdBytes) {
      return estimate;
    }
    for (final task in board.allTasks) {
      estimate +=
          120 +
          task.title.length +
          (task.note?.length ?? 0) +
          task.history.length * 60 +
          task.subtasks.length * 32 +
          task.links.length * 48;
      if (estimate >= isolateOffloadThresholdBytes) {
        return estimate;
      }
    }
    for (final label in board.labels) {
      estimate += 80 + label.name.length + (label.note?.length ?? 0);
      if (estimate >= isolateOffloadThresholdBytes) {
        return estimate;
      }
    }
    for (final location in board.locations) {
      estimate += 120 + location.name.length + (location.note?.length ?? 0);
      if (estimate >= isolateOffloadThresholdBytes) {
        return estimate;
      }
    }
    return estimate;
  }

  /// Returns whether the UTF-8 byte length of [content] meets or exceeds [isolateOffloadThresholdBytes].
  static bool _exceedsStringOffloadThreshold(String content) {
    if (content.length >= isolateOffloadThresholdBytes) {
      return true;
    }
    if (content.length * 3 < isolateOffloadThresholdBytes) {
      return false;
    }
    return !TdfScanner.isUtf8ByteLengthWithinBound(
      content,
      isolateOffloadThresholdBytes - 1,
    );
  }

  /// Emits a redacted structured `tdf.error` log event for [error].
  static void _logParseError(TdfException error) {
    AppLogger.event(
      LogLevel.error,
      LogTag.tdf,
      'tdf.error',
      fields: <String, Object?>{
        'kind': error.kind.name,
        'line': error.line,
        'message': error.message,
      },
    );
  }

  /// Emits a redacted structured `tdf.parse` log event for [board] and [stopwatch].
  static void _logParseSuccess(TaskBoard board, Stopwatch stopwatch) {
    AppLogger.event(
      LogLevel.info,
      LogTag.tdf,
      'tdf.parse',
      fields: <String, Object?>{
        'version': supportedVersion,
        'tasks': board.allTasks.length,
        'labels': board.labels.length,
        'locations': board.locations.length,
        'elapsed_ms': stopwatch.elapsedMilliseconds,
      },
    );
  }

  /// Emits a redacted structured `tdf.serialize` log event with exact [utf8ByteLength].
  static void _logSerializeSuccess(
    TaskBoard board,
    int utf8ByteLength,
    Stopwatch stopwatch,
  ) {
    AppLogger.event(
      LogLevel.info,
      LogTag.tdf,
      'tdf.serialize',
      fields: <String, Object?>{
        'version': supportedVersion,
        'tasks': board.allTasks.length,
        'labels': board.labels.length,
        'locations': board.locations.length,
        'bytes': utf8ByteLength,
        'elapsed_ms': stopwatch.elapsedMilliseconds,
      },
    );
  }

  /// Parses [tdfContent] whose byte bound has already been verified and emits a redacted `tdf.parse` log event.
  TaskBoard _parseVerifiedContent(
    String tdfContent, {
    required Stopwatch stopwatch,
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow,
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
    required bool pruneExpiredCompleted,
    required bool evaluateTiers,
  }) {
    final board = TdfBlockParser.parseDocument(
      tdfContent,
      evaluationTime: evaluationTime,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      activeLabelId: activeLabelId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
      pruneExpiredCompleted: pruneExpiredCompleted,
      byteLengthVerified: true,
      evaluateTiers: evaluateTiers,
    );
    _logParseSuccess(board, stopwatch);
    return board;
  }

  /// Runs strict UTF-8 decoding and TDF parsing on a background worker isolate.
  static Future<TaskBoard> _runParseBytesIsolate(
    List<int> utf8Bytes, {
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow,
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
    required bool pruneExpiredCompleted,
    required bool evaluateTiers,
  }) => Isolate.run(() {
    final decoded = _decodeValidatedUtf8Bytes(utf8Bytes);
    return TdfBlockParser.parseDocument(
      decoded,
      evaluationTime: evaluationTime,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      activeLabelId: activeLabelId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
      pruneExpiredCompleted: pruneExpiredCompleted,
      byteLengthVerified: true,
      evaluateTiers: evaluateTiers,
    );
  });

  /// Runs UTF-8 byte-bound validation and TDF parsing on a background worker isolate.
  static Future<TaskBoard> _runParseStringIsolate(
    String tdfContent, {
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow,
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
    required bool pruneExpiredCompleted,
    required bool evaluateTiers,
  }) => Isolate.run(() {
    if (!TdfScanner.isUtf8ByteLengthWithinBound(tdfContent, maxTdfFileBytes)) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message: 'Document exceeds maximum of $maxTdfFileBytes bytes.',
      );
    }
    return TdfBlockParser.parseDocument(
      tdfContent,
      evaluationTime: evaluationTime,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      activeLabelId: activeLabelId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
      pruneExpiredCompleted: pruneExpiredCompleted,
      byteLengthVerified: true,
      evaluateTiers: evaluateTiers,
    );
  });

  /// Runs canonical `tdf 0.8.0` serialization on a background worker isolate.
  static Future<({String output, int utf8ByteLength})> _runSerializeIsolate(
    TaskBoard board,
  ) => Isolate.run(() => TdfSerializer.serializeWithByteCount(board));

  /// Delegates canonical `tdf 0.8.0` serialization and bounds validation to [TdfSerializer.serializeWithByteCount].
  String _serializeInternal(TaskBoard board) {
    final stopwatch = Stopwatch()..start();
    try {
      final result = TdfSerializer.serializeWithByteCount(board);
      _logSerializeSuccess(board, result.utf8ByteLength, stopwatch);
      return result.output;
    } on TdfException catch (error) {
      _logParseError(error);
      rethrow;
    }
  }
}
