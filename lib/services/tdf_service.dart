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
import 'tdf_importer.dart';

/// Mandatory lexical, structural, and semantic error categories defined in `TDF_SPEC.md` Section 8.
enum TdfErrorKind {
  /// A task's `blocked` dependency chain forms a cycle or self-dependency.
  circularDependency,

  /// A single-valued directive or sub-block appears more than once in the same block.
  duplicateDirective,

  /// Two blocks, deletion records, or queue entries in the same namespace share an identical `<id>`.
  duplicateIdentifier,

  /// A required text argument (`name`, `step` `<text>`, or `link` `<title>` / `<uri>`) is empty or whitespace-only after unescaping.
  emptyText,

  /// A block header is malformed or missing whitespace before `{`.
  invalidBlockHeader,

  /// A boolean literal is neither `true` nor `false`.
  invalidBoolean,

  /// A `color` argument is unquoted or fails `#RRGGBB` hexadecimal validation.
  invalidColor,

  /// A task has `finished` present while its effective `completions` counter is `0`.
  invalidCompletionState,

  /// A condition rule has an invalid weekday, equal time window, out-of-range GPS coordinate/radius, or invalid reset.
  invalidCondition,

  /// A double-quoted string contains an unsupported backslash escape sequence.
  invalidEscapeSequence,

  /// A block/directive identifier or entity ID is quoted or fails canonical format validation.
  invalidIdentifier,

  /// A numeric argument, generation counter, completion count, or prerequisite count fails decimal validation.
  invalidNumber,

  /// Queue entries do not match the exact set of live scheduled open tasks.
  invalidQueueMembership,

  /// A repeat clock (`<repeat-time>`) is quoted or outside `00:00:00..23:59:59`.
  invalidTime,

  /// A timestamp or time-window argument fails ISO-8601 calendar or 24-hour clock validation.
  invalidTimestamp,

  /// A `link` `<uri>` argument does not start with a valid scheme (`[a-zA-Z][a-zA-Z0-9+.-]*:`) or contains control characters.
  invalidUri,

  /// A resource bound defined in `TDF_SPEC.md` Section 7 was exceeded.
  limitExceeded,

  /// A standalone directive identifier appears without arguments and without `{`.
  missingDirectiveArgument,

  /// A required directive (`name`, `created`, `generation`, `modified`, `step`, or condition rule) is missing from a block.
  missingRequiredDirective,

  /// The document contains no statements or does not begin with `tdf <version>`.
  missingVersionHeader,

  /// End-of-file was reached while one or more `{ ... }` blocks remained open.
  unclosedBlock,

  /// A closing brace `}` was encountered at nesting depth `0`.
  unexpectedClosingBrace,

  /// A directive appears at nesting depth `0` outside of any `{ ... }` block.
  unexpectedRootDirective,

  /// An unexpected token, control character, trailing token after a brace, or adjacent quote was encountered.
  unexpectedToken,

  /// A root or nested block identifier is not part of the TDF schema.
  unknownBlockType,

  /// A directive identifier is not valid for its enclosing block.
  unknownDirective,

  /// A task's `labels` directive references an `<id>` that does not match any `label` block in the document.
  unknownLabelReference,

  /// The initial `tdf <version>` header specifies an unsupported or malformed version.
  unsupportedVersion,

  /// A double-quoted or single-quoted string reached end-of-line or EOF before its closing quote.
  unterminatedString,
}

/// Structured exception thrown when scanning, parsing, validating, or serializing a `.tdf` document fails.
@immutable
class TdfException implements Exception {
  /// Creates a [TdfException] for [kind] at 1-based [line] with [message].
  const TdfException({
    required this.kind,
    required this.line,
    required this.message,
    this.sourceVersion,
    this.targetVersion,
  });

  /// Normative error category from `TDF_SPEC.md` Section 8.
  final TdfErrorKind kind;

  /// 1-based line number where the error occurred.
  final int line;

  /// Human-readable diagnostic description.
  final String message;

  /// Optional historical source version when thrown during explicit import migration.
  final String? sourceVersion;

  /// Optional target version when thrown during explicit import migration.
  final String? targetVersion;

  @override
  String toString() {
    if (sourceVersion != null && targetVersion != null) {
      return 'TdfException(${kind.name}, $sourceVersion->$targetVersion, line $line): $message';
    }
    return 'TdfException(${kind.name}, line $line): $message';
  }
}

/// Stateless service that scans, parses, validates, and serializes TierTask Data Format (`.tdf`) `0.5.1` documents
/// in a single $O(N)$ linear pass without regular expressions.
class TdfService {
  /// Creates a const [TdfService].
  const TdfService();

  /// Legacy TDF specification version string (`tdf 0.5.0`) converted in memory at load time per Section 10.6.
  static const String legacySupportedVersion = '0.5.0';

  /// Maximum arguments allowed on a single block header or directive (`MAX_ARGS_PER_STMT`).
  static const int maxArgsPerStmt = 64;

  /// Maximum total blocks per `.tdf` document (`MAX_BLOCKS_PER_DOC`).
  static const int maxBlocksPerDoc = 4096;

  /// Maximum completion counter, deletion checkpoint, and prerequisite completion number (`MAX_COMPLETIONS`).
  static const int maxCompletions = TdfTaskDependency.maxCompletions;

  /// Maximum stored condition rules across all inline directives and condition blocks on one entity (`MAX_CONDITION_RULES_PER_ENTITY`).
  static const int maxConditionRulesPerEntity = 512;

  /// Maximum task and label deletion records in the shared `deleted` block (`MAX_DELETED_RECORDS`).
  static const int maxDeletedRecords = TdfDeletedBlock.maxDeletedRecords;

  /// Maximum input or serialized output size in UTF-8 bytes (`MAX_FILE_BYTES`, 1 MiB).
  static const int maxFileBytes = 1048576;

  /// Maximum logical lines per `.tdf` document (`MAX_LINE_COUNT`).
  static const int maxLineCount = 16384;

  /// Maximum `link` directives per `task` block (`MAX_LINKS_PER_TASK`).
  static const int maxLinksPerTask = TaskLink.maxLinksPerTask;

  /// Maximum `{ ... }` block nesting depth (`MAX_NESTING_DEPTH`).
  static const int maxNestingDepth = 2;

  /// Maximum decoded Unicode scalar values in a `note` text value (`MAX_NOTE_LENGTH`).
  static const int maxNoteLength = 2000;

  /// Maximum `task` entries in the shared `queue` block (`MAX_QUEUE_ENTRIES`).
  static const int maxQueueEntries = TdfQueueBlock.maxQueueEntries;

  /// Maximum recurrence interval count `<count>` in `repeat <count> <unit>` (`MAX_REPEAT_COUNT`).
  static const int maxRepeatCount = TaskRepeatRule.maxRepeatCount;

  /// Maximum direct child statements per ordinary block (`MAX_STMTS_PER_BLOCK`).
  static const int maxStmtsPerBlock = 512;

  /// Maximum deletion history generation (`MAX_SYNC_GENERATION`).
  static const int maxSyncGeneration = TdfDeletedBlock.maxGeneration;

  /// Maximum decoded Unicode scalar values in a `name`, `step`, or link `<title>` (`MAX_TEXT_LENGTH`).
  static const int maxTextLength = 500;

  /// Maximum decoded Unicode scalar values in a `link` `<uri>` (`MAX_URI_LENGTH`).
  static const int maxUriLength = TaskLink.maxUriLength;

  /// Canonical TDF specification version string (`tdf 0.5.1`).
  static const String supportedVersion = '0.5.1';

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

  /// Serializes [board] into a canonical `LF`-terminated `tdf 0.5.0` document string
  /// and validates canonical output against Section 7.1 bounds.
  String serialize(TaskBoard board) {
    final stopwatch = Stopwatch()..start();
    final hasDeleted = !board.deletedBlock.isDefaultEmpty;
    final hasQueue = !board.queueBlock.isDefaultEmpty;
    if (!hasDeleted &&
        !hasQueue &&
        board.labels.isEmpty &&
        board.allTasks.isEmpty) {
      AppLogger.info(
        LogTag.tdf,
        'TdfService.serialize v$supportedVersion tasks=0 labels=0 elapsed=${stopwatch.elapsedMilliseconds}ms',
      );
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
    AppLogger.info(
      LogTag.tdf,
      'TdfService.serialize v$supportedVersion tasks=${board.allTasks.length} labels=${board.labels.length} bytes=${output.length} elapsed=${stopwatch.elapsedMilliseconds}ms',
    );
    return output;
  }

  /// Adds [rule] to [builder] after verifying `MAX_CONDITION_RULES_PER_ENTITY` and Section 4.3 reset constraints.
  static void _addConditionToLabel(
    _LabelBuilder builder,
    TaskCondition rule,
    int lineNumber,
  ) {
    if (builder.conditions.length + 1 > maxConditionRulesPerEntity) {
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: lineNumber,
        message:
            'Label exceeds maximum of $maxConditionRulesPerEntity condition rules.',
      );
    }
    builder.conditions.add(rule);
  }

  /// Adds [rule] to [builder] after verifying `MAX_CONDITION_RULES_PER_ENTITY` and Section 4.3 reset conflict constraints.
  static void _addConditionToTask(
    _TaskBuilder builder,
    TaskCondition rule,
    int lineNumber,
  ) {
    if (builder.conditions.length + 1 > maxConditionRulesPerEntity) {
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: lineNumber,
        message:
            'Task exceeds maximum of $maxConditionRulesPerEntity condition rules.',
      );
    }
    if (rule is GlobalResetTaskCondition) {
      if (builder.conditions.isNotEmpty) {
        throw TdfException(
          kind: TdfErrorKind.invalidCondition,
          line: lineNumber,
          message:
              'Task cannot combine "condition any" with other condition rules.',
        );
      }
      builder.conditions.add(rule);
      return;
    }

    final hasGlobalReset = builder.conditions.any(
      (existing) => existing is GlobalResetTaskCondition,
    );
    if (hasGlobalReset) {
      throw TdfException(
        kind: TdfErrorKind.invalidCondition,
        line: lineNumber,
        message:
            'Task cannot combine "condition any" with other condition rules.',
      );
    }

    final targetGroup = rule.group;
    if (rule is GroupResetTaskCondition) {
      final hasSameGroupRule = builder.conditions.any(
        (existing) => existing.group == targetGroup,
      );
      if (hasSameGroupRule) {
        throw TdfException(
          kind: TdfErrorKind.invalidCondition,
          line: lineNumber,
          message:
              'Task cannot combine "${rule.targetGroup.name} any" with other "${rule.targetGroup.name}" rules.',
        );
      }
    } else {
      final hasGroupReset = builder.conditions.any(
        (existing) =>
            existing is GroupResetTaskCondition &&
            existing.targetGroup == targetGroup,
      );
      if (hasGroupReset) {
        throw TdfException(
          kind: TdfErrorKind.invalidCondition,
          line: lineNumber,
          message:
              'Task cannot combine "${targetGroup?.name} any" with other "${targetGroup?.name}" rules.',
        );
      }
    }

    builder.conditions.add(rule);
  }

  /// Applies a directive inside a `condition { ... }` sub-block.
  static void _applyConditionBlockDirective(
    _ConditionBlockBuilder builder,
    String directive,
    List<_ScannedToken> args,
    int lineNumber,
  ) {
    if (directive == 'any') {
      throw TdfException(
        kind: TdfErrorKind.invalidCondition,
        line: lineNumber,
        message:
            'Global reset "any" is not allowed inside a condition sub-block.',
      );
    }
    if (directive != 'day' && directive != 'time' && directive != 'location') {
      throw TdfException(
        kind: TdfErrorKind.unknownDirective,
        line: lineNumber,
        message: 'Unknown directive "$directive" in condition block.',
      );
    }
    final rule = _parseConditionGroupRule(
      directive,
      args,
      allowResets: builder.allowResets,
      lineNumber: lineNumber,
    );
    builder.hasAnyRule = true;
    final parent = builder.parent;
    if (parent is _LabelBuilder) {
      _addConditionToLabel(parent, rule, lineNumber);
    } else if (parent is _TaskBuilder) {
      _addConditionToTask(parent, rule, lineNumber);
    }
  }

  /// Applies a directive inside the root `deleted` block (`generation`, `task`, or `label`).
  static void _applyDeletedDirective(
    _ParserState state,
    _DeletedBlockBuilder builder,
    String directive,
    List<_ScannedToken> args,
    int lineNumber,
  ) {
    switch (directive) {
      case 'generation':
        if (builder.generation != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.generation = _requireUnsignedCountArg(
          args,
          lineNumber,
          maxAllowed: maxSyncGeneration,
          allowZero: true,
        );
      case 'task':
        if (builder.totalRecords >= maxDeletedRecords) {
          throw TdfException(
            kind: TdfErrorKind.limitExceeded,
            line: lineNumber,
            message:
                'Deleted block exceeds maximum of $maxDeletedRecords records.',
          );
        }
        final record = _parseDeletedTaskRecord(args, lineNumber);
        if (state.taskIds.contains(record.taskId) ||
            !state.deletedTaskIds.add(record.taskId)) {
          _throwDuplicateId(record.taskId, lineNumber);
        }
        builder.tasks.add(record);
      case 'label':
        if (builder.totalRecords >= maxDeletedRecords) {
          throw TdfException(
            kind: TdfErrorKind.limitExceeded,
            line: lineNumber,
            message:
                'Deleted block exceeds maximum of $maxDeletedRecords records.',
          );
        }
        final record = _parseDeletedLabelRecord(args, lineNumber);
        if (state.labelIds.contains(record.labelId) ||
            !state.deletedLabelIds.add(record.labelId)) {
          _throwDuplicateId(record.labelId, lineNumber);
        }
        builder.labels.add(record);
      default:
        throw TdfException(
          kind: TdfErrorKind.unknownDirective,
          line: lineNumber,
          message: 'Unknown directive "$directive" in deleted block.',
        );
    }
  }

  /// Applies a directive inside a `label` block.
  static void _applyLabelDirective(
    _LabelBuilder builder,
    String directive,
    List<_ScannedToken> args,
    int lineNumber,
  ) {
    switch (directive) {
      case 'name':
        if (builder.name != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.name = _requireNameOrStepArg(args, lineNumber);
      case 'color':
        if (builder.color != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.color = _requireColorArg(args, lineNumber);
      case 'note':
        if (builder.note != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.note = _requireNoteArg(args, lineNumber);
      case 'modified':
        if (builder.modifiedAt != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.modifiedAt = _requireTimestampArgs(args, lineNumber);
      case 'condition':
        final rule = _parseInlineConditionArgs(
          args,
          allowResets: false,
          lineNumber: lineNumber,
        );
        _addConditionToLabel(builder, rule, lineNumber);
      default:
        throw TdfException(
          kind: TdfErrorKind.unknownDirective,
          line: lineNumber,
          message: 'Unknown directive "$directive" in label block.',
        );
    }
  }

  /// Validates and appends a `link "<title>" "<uri>"` directive to [builder].
  static void _applyLinkDirective(
    _TaskBuilder builder,
    List<_ScannedToken> args,
    int lineNumber,
  ) {
    if (args.length != 2 ||
        args[0].kind != _TokenKind.quotedString ||
        args[1].kind != _TokenKind.quotedString) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: lineNumber,
        message: 'Directive "link" requires two quoted arguments: "<title>" and "<uri>".',
      );
    }
    if (builder.links.length >= maxLinksPerTask) {
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: lineNumber,
        message: 'Task exceeds maximum of $maxLinksPerTask links.',
      );
    }
    final title = args[0].value;
    final uri = args[1].value;
    if (title.trim().isEmpty || uri.trim().isEmpty) {
      throw TdfException(
        kind: TdfErrorKind.emptyText,
        line: lineNumber,
        message: 'Link title and URI must not be empty or whitespace-only.',
      );
    }
    _requireScalarLength(title, maxTextLength, lineNumber);
    _requireScalarLength(uri, maxUriLength, lineNumber);
    if (!TaskLink.isValidUri(uri)) {
      throw TdfException(
        kind: TdfErrorKind.invalidUri,
        line: lineNumber,
        message: 'Invalid link URI "$uri".',
      );
    }
    builder.links.add(TaskLink(title: title, uri: uri));
  }

  /// Applies a directive inside the root `queue` block (`modified` or `task`).
  static void _applyQueueDirective(
    _QueueBlockBuilder builder,
    String directive,
    List<_ScannedToken> args,
    int lineNumber,
  ) {
    switch (directive) {
      case 'modified':
        if (builder.modifiedAt != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.modifiedAt = _requireTimestampArgs(args, lineNumber);
      case 'task':
        if (builder.entries.length >= maxQueueEntries) {
          throw TdfException(
            kind: TdfErrorKind.limitExceeded,
            line: lineNumber,
            message:
                'Queue block exceeds maximum of $maxQueueEntries task entries.',
          );
        }
        if (args.length != 1) {
          throw TdfException(
            kind: TdfErrorKind.unexpectedToken,
            line: lineNumber,
            message: 'Directive "task" in queue requires a single <task-id>.',
          );
        }
        final token = args[0];
        if (token.kind != _TokenKind.bareWord || !isValidTaskId(token.value)) {
          throw TdfException(
            kind: TdfErrorKind.invalidIdentifier,
            line: lineNumber,
            message: 'Invalid task identifier "${token.value}" in queue.',
          );
        }
        if (!builder.seenTaskIds.add(token.value)) {
          _throwDuplicateId(token.value, lineNumber);
        }
        builder.entries.add(
          _QueueEntryLine(taskId: token.value, line: lineNumber),
        );
      default:
        throw TdfException(
          kind: TdfErrorKind.unknownDirective,
          line: lineNumber,
          message: 'Unknown directive "$directive" in queue block.',
        );
    }
  }

  /// Applies a directive inside a `subtasks` sub-block.
  static void _applySubtasksDirective(
    _SubtasksBuilder builder,
    String directive,
    List<_ScannedToken> args,
    int lineNumber,
  ) {
    if (directive != 'step') {
      throw TdfException(
        kind: TdfErrorKind.unknownDirective,
        line: lineNumber,
        message: 'Unknown directive "$directive" in subtasks block.',
      );
    }
    if (args.length != 2) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: lineNumber,
        message: 'Directive "step" requires <bool> and "<text>" arguments.',
      );
    }
    final boolToken = args[0];
    if (boolToken.kind != _TokenKind.bareWord ||
        (boolToken.value != 'true' && boolToken.value != 'false')) {
      throw TdfException(
        kind: TdfErrorKind.invalidBoolean,
        line: lineNumber,
        message: 'Invalid boolean literal "${boolToken.value}" in step.',
      );
    }
    final textValue = args[1].value;
    if (textValue.trim().isEmpty) {
      throw TdfException(
        kind: TdfErrorKind.emptyText,
        line: lineNumber,
        message: 'Step text must not be empty or whitespace-only.',
      );
    }
    _requireScalarLength(textValue, maxTextLength, lineNumber);
    builder.steps.add(
      SubtaskItem(title: textValue, isCompleted: boolToken.value == 'true'),
    );
  }

  /// Applies a directive inside a `task` block.
  static void _applyTaskDirective(
    _TaskBuilder builder,
    String directive,
    List<_ScannedToken> args,
    int lineNumber, {
    required bool isLegacy050,
  }) {
    switch (directive) {
      case 'name':
        if (builder.name != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.name = _requireNameOrStepArg(args, lineNumber);
      case 'note':
        if (builder.note != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.note = _requireNoteArg(args, lineNumber);
      case 'created':
        if (builder.createdAt != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.createdAt = _requireTimestampArgs(args, lineNumber);
      case 'queued':
        if (!isLegacy050) {
          throw TdfException(
            kind: TdfErrorKind.unknownDirective,
            line: lineNumber,
            message: 'Unknown directive "$directive" in TDF 0.5.1 task block.',
          );
        }
        if (builder.legacyQueuedAt != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.legacyQueuedAt = _requireTimestampArgs(args, lineNumber);
      case 'finished':
        if (builder.completedAt != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.completedAt = _requireTimestampArgs(args, lineNumber);
        builder.finishedLine = lineNumber;
      case 'modified':
        if (builder.modifiedAt != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.modifiedAt = _requireTimestampArgs(args, lineNumber);
      case 'completions':
        if (builder.completions != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.completions = _requireUnsignedCountArg(
          args,
          lineNumber,
          maxAllowed: maxCompletions,
          allowZero: true,
        );
        builder.completionsLine = lineNumber;
      case 'suspended':
        if (builder.hasSuspendedDirective) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.hasSuspendedDirective = true;
        if (args.length == 1 &&
            args[0].kind == _TokenKind.bareWord &&
            args[0].value == 'forever') {
          builder.isSuspendedForever = true;
        } else {
          builder.suspendedAt = _requireTimestampArgs(args, lineNumber);
        }
      case 'repeat':
        if (builder.repeatRule != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.repeatRule = _requireRepeatRuleArgs(args, lineNumber);
      case 'labels':
        if (builder.canonicalLabelIds != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.canonicalLabelIds = _requireLabelIdListArgs(args, lineNumber);
        builder.labelsLine = lineNumber;
      case 'blocked':
        if (builder.dependencies != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.dependencies = _requireDependencyListArgs(args, lineNumber);
        builder.blockedLine = lineNumber;
      case 'link':
        _applyLinkDirective(builder, args, lineNumber);
      case 'condition':
        final rule = _parseInlineConditionArgs(
          args,
          allowResets: true,
          lineNumber: lineNumber,
        );
        _addConditionToTask(builder, rule, lineNumber);
      default:
        throw TdfException(
          kind: TdfErrorKind.unknownDirective,
          line: lineNumber,
          message: 'Unknown directive "$directive" in task block.',
        );
    }
  }

  /// Checks whether [taskId] participates in a dependency cycle using 3-color DFS.
  static void _checkTaskCycle(
    String taskId,
    Map<String, _ParsedTaskEntry> taskById,
    Map<String, int> visitState,
    int fallbackLine,
  ) {
    final currentState = visitState[taskId] ?? 0;
    if (currentState == 2) {
      return;
    }
    final entry = taskById[taskId];
    final reportLine = entry != null && entry.blockedLine > 0
        ? entry.blockedLine
        : fallbackLine;
    if (currentState == 1) {
      throw TdfException(
        kind: TdfErrorKind.circularDependency,
        line: reportLine,
        message: 'Circular dependency detected involving task "$taskId".',
      );
    }
    if (entry == null) {
      visitState[taskId] = 2;
      return;
    }

    visitState[taskId] = 1;
    for (final blockerId in entry.task.blockedByTaskIds) {
      _checkTaskCycle(blockerId, taskById, visitState, reportLine);
    }
    visitState[taskId] = 2;
  }

  /// Closes the currently active block on [state] and validates required directives.
  static void _closeCurrentBlock(_ParserState state, int lineNumber) {
    if (state.blockStack.isEmpty) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedClosingBrace,
        line: lineNumber,
        message: 'Unexpected closing brace at root level.',
      );
    }
    final active = state.blockStack.removeLast();
    switch (active) {
      case final _TaskBuilder taskBuilder:
        state.taskEntries.add(
          taskBuilder.build(lineNumber, isLegacy050: state.isLegacy050),
        );
      case final _LabelBuilder labelBuilder:
        state.labels.add(labelBuilder.build(lineNumber));
      case final _DeletedBlockBuilder deletedBuilder:
        state.deletedBlock = deletedBuilder.build(lineNumber);
      case final _QueueBlockBuilder queueBuilder:
        state.queueBlock = queueBuilder.build(lineNumber);
        state.queueEntries.addAll(queueBuilder.entries);
        state.queueTaskIds.addAll(queueBuilder.seenTaskIds);
      case final _SubtasksBuilder subtasksBuilder:
        if (subtasksBuilder.steps.isEmpty) {
          throw TdfException(
            kind: TdfErrorKind.missingRequiredDirective,
            line: lineNumber,
            message: 'Subtasks block requires at least one "step" directive.',
          );
        }
        final parent = state.blockStack.last;
        if (parent is _TaskBuilder) {
          parent.subtasksAutoFinish = subtasksBuilder.autoFinish;
          parent.subtasks = subtasksBuilder.steps;
        }
      case final _ConditionBlockBuilder conditionBuilder:
        if (!conditionBuilder.hasAnyRule) {
          throw TdfException(
            kind: TdfErrorKind.missingRequiredDirective,
            line: lineNumber,
            message: 'Condition block requires at least one condition rule.',
          );
        }
    }
  }

  /// Creates a nested block builder (`subtasks` inside `task`, or `condition` inside `task`/`label`).
  static _BlockBuilder _createNestedBlockBuilder(
    _BlockBuilder parent,
    String blockName,
    List<_ScannedToken> headerArgs,
    int lineNumber,
  ) {
    if (blockName == 'condition') {
      return _initConditionBlockBuilder(parent, headerArgs, lineNumber);
    }
    if (parent is! _TaskBuilder || blockName != 'subtasks') {
      throw TdfException(
        kind: TdfErrorKind.unknownBlockType,
        line: lineNumber,
        message: 'Unknown nested block type "$blockName".',
      );
    }
    if (parent.hasSubtasksBlock) {
      _throwDuplicateDirective('subtasks', lineNumber);
    }
    if (headerArgs.length > 1) {
      throw TdfException(
        kind: TdfErrorKind.invalidBlockHeader,
        line: lineNumber,
        message: 'Subtasks block accepts at most one "auto-finish" flag.',
      );
    }
    var autoFinish = false;
    if (headerArgs.length == 1) {
      final flag = headerArgs[0];
      if (flag.kind != _TokenKind.bareWord || flag.value != 'auto-finish') {
        throw TdfException(
          kind: TdfErrorKind.invalidBlockHeader,
          line: lineNumber,
          message: 'Invalid subtasks header flag "${flag.value}".',
        );
      }
      autoFinish = true;
    }
    parent.hasSubtasksBlock = true;
    return _SubtasksBuilder(autoFinish: autoFinish);
  }

  /// Creates a root block builder (`deleted`, `queue`, `label`, or `task`).
  static _BlockBuilder _createRootBlockBuilder(
    _ParserState state,
    String blockName,
    List<_ScannedToken> headerArgs,
    int lineNumber,
  ) {
    if (blockName == 'deleted') {
      if (state.hasDeletedBlock) {
        _throwDuplicateDirective('deleted', lineNumber);
      }
      if (headerArgs.isNotEmpty) {
        throw TdfException(
          kind: TdfErrorKind.invalidBlockHeader,
          line: lineNumber,
          message: 'Block "deleted" does not accept header arguments.',
        );
      }
      state.hasDeletedBlock = true;
      return _DeletedBlockBuilder();
    }
    if (blockName == 'queue') {
      if (state.hasQueueBlock) {
        _throwDuplicateDirective('queue', lineNumber);
      }
      if (headerArgs.isNotEmpty) {
        throw TdfException(
          kind: TdfErrorKind.invalidBlockHeader,
          line: lineNumber,
          message: 'Block "queue" does not accept header arguments.',
        );
      }
      state.hasQueueBlock = true;
      return _QueueBlockBuilder();
    }
    if (blockName != 'label' && blockName != 'task') {
      throw TdfException(
        kind: TdfErrorKind.unknownBlockType,
        line: lineNumber,
        message: 'Unknown root block type "$blockName".',
      );
    }
    if (headerArgs.isEmpty) {
      throw TdfException(
        kind: TdfErrorKind.invalidBlockHeader,
        line: lineNumber,
        message: 'Root block "$blockName" requires an <id> argument.',
      );
    }
    final idToken = headerArgs[0];
    if (idToken.kind != _TokenKind.bareWord || !isValidTaskId(idToken.value)) {
      throw TdfException(
        kind: TdfErrorKind.invalidIdentifier,
        line: lineNumber,
        message: 'Invalid block identifier "${idToken.value}".',
      );
    }
    if (blockName == 'task') {
      return _initTaskBuilder(state, idToken.value, headerArgs, lineNumber);
    }
    if (headerArgs.length > 1) {
      throw TdfException(
        kind: TdfErrorKind.invalidBlockHeader,
        line: lineNumber,
        message: 'Block "label" accepts only a single <id> argument.',
      );
    }
    if (state.deletedLabelIds.contains(idToken.value) ||
        !state.labelIds.add(idToken.value)) {
      _throwDuplicateId(idToken.value, lineNumber);
    }
    return _LabelBuilder(id: idToken.value);
  }

  /// Escapes a string value for canonical double-quoted TDF serialization.
  static String _escapeQuotedString(String input) {
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

  /// Finds the end of the line starting at [startOffset] and validates line terminators, control chars, and UTF-16 surrogates.
  static _LineSpan _findLineSpan(
    String source,
    int startOffset,
    int lineNumber,
  ) {
    var index = startOffset;
    while (index < source.length) {
      final unit = source.codeUnitAt(index);
      if (unit == 0x0A) {
        return _LineSpan(
          lineStart: startOffset,
          lineEnd: index,
          nextOffset: index + 1,
        );
      }
      if (unit == 0x0D) {
        if (index + 1 >= source.length ||
            source.codeUnitAt(index + 1) != 0x0A) {
          throw TdfException(
            kind: TdfErrorKind.unexpectedToken,
            line: lineNumber,
            message: 'Standalone CR without LF is not permitted.',
          );
        }
        return _LineSpan(
          lineStart: startOffset,
          lineEnd: index,
          nextOffset: index + 2,
        );
      }
      if ((unit < 0x20 && unit != 0x09) || unit == 0x7F) {
        throw TdfException(
          kind: TdfErrorKind.unexpectedToken,
          line: lineNumber,
          message:
              'ASCII control character is not permitted in a TDF document.',
        );
      }
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (index + 1 >= source.length) {
          throw TdfException(
            kind: TdfErrorKind.unexpectedToken,
            line: lineNumber,
            message: 'Unpaired high surrogate in TDF document.',
          );
        }
        final low = source.codeUnitAt(index + 1);
        if (low < 0xDC00 || low > 0xDFFF) {
          throw TdfException(
            kind: TdfErrorKind.unexpectedToken,
            line: lineNumber,
            message: 'Unpaired high surrogate in TDF document.',
          );
        }
        index += 2;
        continue;
      }
      if (unit >= 0xDC00 && unit <= 0xDFFF) {
        throw TdfException(
          kind: TdfErrorKind.unexpectedToken,
          line: lineNumber,
          message: 'Unpaired low surrogate in TDF document.',
        );
      }
      index++;
    }
    return _LineSpan(
      lineStart: startOffset,
      lineEnd: source.length,
      nextOffset: source.length,
    );
  }

  /// Finds the first index of [kind] in [tokens], or `-1` if absent.
  static int _findTokenKindIndex(List<_ScannedToken> tokens, _TokenKind kind) {
    for (var i = 0; i < tokens.length; i++) {
      if (tokens[i].kind == kind) {
        return i;
      }
    }
    return -1;
  }

  /// Validates and initializes a `_ConditionBlockBuilder` for `condition {`.
  static _ConditionBlockBuilder _initConditionBlockBuilder(
    _BlockBuilder parent,
    List<_ScannedToken> headerArgs,
    int lineNumber,
  ) {
    if (parent is! _TaskBuilder && parent is! _LabelBuilder) {
      throw TdfException(
        kind: TdfErrorKind.unknownBlockType,
        line: lineNumber,
        message:
            'Condition sub-block is only allowed inside label or task blocks.',
      );
    }
    if (headerArgs.isNotEmpty) {
      throw TdfException(
        kind: TdfErrorKind.invalidBlockHeader,
        line: lineNumber,
        message: 'Condition block header does not accept arguments.',
      );
    }
    return _ConditionBlockBuilder(
      parent: parent,
      allowResets: parent is _TaskBuilder,
    );
  }

  /// Validates and initializes a `_TaskBuilder` for `task <id> [priority]`.
  static _TaskBuilder _initTaskBuilder(
    _ParserState state,
    String id,
    List<_ScannedToken> headerArgs,
    int lineNumber,
  ) {
    if (headerArgs.length > 2) {
      throw TdfException(
        kind: TdfErrorKind.invalidBlockHeader,
        line: lineNumber,
        message: 'Task block header accepts <id> and optional "priority".',
      );
    }
    var isPriority = false;
    if (headerArgs.length == 2) {
      final flagToken = headerArgs[1];
      if (flagToken.kind != _TokenKind.bareWord ||
          flagToken.value != 'priority') {
        throw TdfException(
          kind: TdfErrorKind.invalidBlockHeader,
          line: lineNumber,
          message: 'Unknown task header flag "${flagToken.value}".',
        );
      }
      isPriority = true;
    }
    if (state.deletedTaskIds.contains(id) || !state.taskIds.add(id)) {
      _throwDuplicateId(id, lineNumber);
    }
    return _TaskBuilder(id: id, isPriority: isPriority, headerLine: lineNumber);
  }

  /// Checks whether [codeUnit] is an ASCII alphanumeric, underscore, or hyphen (`[a-zA-Z0-9_-]`).
  static bool _isIdContinueChar(int codeUnit) {
    return _isIdStartChar(codeUnit) ||
        (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        codeUnit == 0x2D;
  }

  /// Checks whether [codeUnit] is an ASCII alphabetic character or underscore (`[a-zA-Z_]`).
  static bool _isIdStartChar(int codeUnit) {
    return (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7A) ||
        codeUnit == 0x5F;
  }

  /// Checks whether [codeUnit] is a disallowed control or non-ASCII whitespace character outside quotes and comments.
  static bool _isInvalidBareChar(int codeUnit) {
    if (codeUnit < 0x20 || codeUnit == 0x7F) {
      return true;
    }
    return codeUnit == 0x0085 ||
        codeUnit == 0x00A0 ||
        codeUnit == 0x1680 ||
        (codeUnit >= 0x2000 && codeUnit <= 0x200A) ||
        codeUnit == 0x2028 ||
        codeUnit == 0x2029 ||
        codeUnit == 0x202F ||
        codeUnit == 0x205F ||
        codeUnit == 0x3000 ||
        codeUnit == 0xFEFF;
  }

  /// Checks whether [raw] matches `0` (when [allowZero] is `true`) or `[1-9][0-9]*`.
  static bool _isValidCanonicalUnsignedInt(
    String raw, {
    required bool allowZero,
  }) {
    if (raw.isEmpty) {
      return false;
    }
    if (raw == '0') {
      return allowZero;
    }
    final first = raw.codeUnitAt(0);
    if (first < 0x31 || first > 0x39) {
      return false;
    }
    for (var i = 1; i < raw.length; i++) {
      final unit = raw.codeUnitAt(i);
      if (unit < 0x30 || unit > 0x39) {
        return false;
      }
    }
    return true;
  }

  /// Checks whether [raw] matches `-?[0-9]+(\.[0-9]+)?` without using regular expressions.
  static bool _isValidDecimalLiteral(String raw) {
    if (raw.isEmpty) {
      return false;
    }
    var index = 0;
    if (raw.codeUnitAt(0) == 0x2D) {
      if (raw.length == 1) {
        return false;
      }
      index = 1;
    }
    var hasLeadingDigits = false;
    while (index < raw.length) {
      final unit = raw.codeUnitAt(index);
      if (unit >= 0x30 && unit <= 0x39) {
        hasLeadingDigits = true;
        index++;
      } else {
        break;
      }
    }
    if (!hasLeadingDigits) {
      return false;
    }
    if (index == raw.length) {
      return true;
    }
    if (raw.codeUnitAt(index) != 0x2E || index == raw.length - 1) {
      return false;
    }
    index++;
    while (index < raw.length) {
      final unit = raw.codeUnitAt(index);
      if (unit < 0x30 || unit > 0x39) {
        return false;
      }
      index++;
    }
    return true;
  }

  /// Validates that [value] matches the TDF identifier rule (`[a-zA-Z_][a-zA-Z0-9_-]*`).
  static bool _isValidIdentifier(String value) {
    if (value.isEmpty || !_isIdStartChar(value.codeUnitAt(0))) {
      return false;
    }
    for (var i = 1; i < value.length; i++) {
      if (!_isIdContinueChar(value.codeUnitAt(i))) {
        return false;
      }
    }
    return true;
  }

  /// Opens a new root or nested block on [state] after checking Section 7 bounds.
  static void _openBlock(
    _ParserState state,
    String blockName,
    List<_ScannedToken> headerArgs,
    int lineNumber,
  ) {
    final nextDepth = state.blockStack.length + 1;
    if (nextDepth > maxNestingDepth) {
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: lineNumber,
        message: 'Block nesting exceeds maximum depth of $maxNestingDepth.',
      );
    }
    if (state.totalBlocks + 1 > maxBlocksPerDoc) {
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: lineNumber,
        message: 'Document exceeds maximum block count of $maxBlocksPerDoc.',
      );
    }
    if (state.blockStack.isNotEmpty) {
      final parent = state.blockStack.last;
      if (parent is _DeletedBlockBuilder || parent is _QueueBlockBuilder) {
        throw TdfException(
          kind: TdfErrorKind.unknownBlockType,
          line: lineNumber,
          message:
              'Nested blocks are forbidden inside deleted or queue blocks.',
        );
      }
      if (parent.statementCount + 1 > maxStmtsPerBlock) {
        throw TdfException(
          kind: TdfErrorKind.limitExceeded,
          line: lineNumber,
          message: 'Block exceeds maximum statements of $maxStmtsPerBlock.',
        );
      }
      parent.statementCount++;
    }
    state.totalBlocks++;

    final builder = state.blockStack.isEmpty
        ? _createRootBlockBuilder(state, blockName, headerArgs, lineNumber)
        : _createNestedBlockBuilder(
            state.blockStack.last,
            blockName,
            headerArgs,
            lineNumber,
          );

    state.blockStack.add(builder);
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

  /// Parses a group condition rule (`day`, `time`, or `location`).
  static TaskCondition _parseConditionGroupRule(
    String conditionType,
    List<_ScannedToken> ruleArgs, {
    required bool allowResets,
    required int lineNumber,
  }) {
    if (ruleArgs.isEmpty) {
      throw TdfException(
        kind: TdfErrorKind.invalidCondition,
        line: lineNumber,
        message: 'Condition "$conditionType" requires arguments.',
      );
    }
    if (ruleArgs.length == 1 &&
        ruleArgs[0].kind == _TokenKind.bareWord &&
        ruleArgs[0].value == 'any') {
      if (!allowResets) {
        throw TdfException(
          kind: TdfErrorKind.invalidCondition,
          line: lineNumber,
          message:
              'Condition reset "$conditionType any" is forbidden on labels.',
        );
      }
      return switch (conditionType) {
        'day' => const GroupResetTaskCondition(targetGroup: ConditionGroup.day),
        'time' => const GroupResetTaskCondition(
          targetGroup: ConditionGroup.time,
        ),
        'location' => const GroupResetTaskCondition(
          targetGroup: ConditionGroup.location,
        ),
        _ => throw TdfException(
          kind: TdfErrorKind.unknownDirective,
          line: lineNumber,
          message: 'Unknown condition type "$conditionType".',
        ),
      };
    }

    return switch (conditionType) {
      'day' => _parseDayRuleArgs(ruleArgs, lineNumber),
      'time' => _parseTimeRuleArgs(ruleArgs, lineNumber),
      'location' => _parseLocationRuleArgs(ruleArgs, lineNumber),
      _ => throw TdfException(
        kind: TdfErrorKind.unknownDirective,
        line: lineNumber,
        message: 'Unknown condition type "$conditionType".',
      ),
    };
  }

  /// Parses `day <mon|tue|wed|thu|fri|sat|sun ...>` arguments.
  static DayTaskCondition _parseDayRuleArgs(
    List<_ScannedToken> ruleArgs,
    int lineNumber,
  ) {
    final weekdays = <int>[];
    final dayTokens = <String>[];
    for (final token in ruleArgs) {
      final weekday = token.kind == _TokenKind.bareWord
          ? DayTaskCondition.parseWeekdayToken(token.value)
          : null;
      if (weekday == null) {
        throw TdfException(
          kind: TdfErrorKind.invalidCondition,
          line: lineNumber,
          message: 'Invalid weekday token "${token.value}" in condition day.',
        );
      }
      weekdays.add(weekday);
      dayTokens.add(token.value);
    }
    return DayTaskCondition(weekdays: weekdays, dayTokens: dayTokens);
  }

  /// Parses `label <label-id> <timestamp>` inside a `deleted` block.
  static TdfDeletedLabelRecord _parseDeletedLabelRecord(
    List<_ScannedToken> args,
    int lineNumber,
  ) {
    if (args.length < 2 || args.length > 3) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: lineNumber,
        message: 'Deleted label record requires <label-id> and <timestamp> arguments.',
      );
    }
    final idToken = args[0];
    if (idToken.kind != _TokenKind.bareWord || !isValidLabelId(idToken.value)) {
      throw TdfException(
        kind: TdfErrorKind.invalidIdentifier,
        line: lineNumber,
        message: 'Invalid deleted label identifier "${idToken.value}".',
      );
    }
    final deletedAt = _requireTimestampArgs(args.sublist(1), lineNumber);
    return TdfDeletedLabelRecord(labelId: idToken.value, deletedAt: deletedAt);
  }

  /// Parses `task <task-id> <timestamp> [<completion-count>]` inside a `deleted` block per Section 4.4.
  static TdfDeletedTaskRecord _parseDeletedTaskRecord(
    List<_ScannedToken> args,
    int lineNumber,
  ) {
    if (args.length < 2 || args.length > 4) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: lineNumber,
        message: 'Deleted task record requires <task-id>, <timestamp>, and optional <completion-count>.',
      );
    }
    final idToken = args[0];
    if (idToken.kind != _TokenKind.bareWord || !isValidTaskId(idToken.value)) {
      throw TdfException(
        kind: TdfErrorKind.invalidIdentifier,
        line: lineNumber,
        message: 'Invalid deleted task identifier "${idToken.value}".',
      );
    }
    if (args.length == 2) {
      final deletedAt = _requireTimestampArgs([args[1]], lineNumber);
      return TdfDeletedTaskRecord(taskId: idToken.value, deletedAt: deletedAt);
    }
    if (args.length == 3) {
      final third = args[2];
      if (third.kind == _TokenKind.bareWord && third.value.contains(':')) {
        final deletedAt = _requireTimestampArgs([args[1], third], lineNumber);
        return TdfDeletedTaskRecord(
          taskId: idToken.value,
          deletedAt: deletedAt,
        );
      }
      final deletedAt = _requireTimestampArgs([args[1]], lineNumber);
      final checkpoint = _requireUnsignedCountArg(
        [third],
        lineNumber,
        maxAllowed: maxCompletions,
        allowZero: true,
      );
      return TdfDeletedTaskRecord(
        taskId: idToken.value,
        deletedAt: deletedAt,
        completionsCheckpoint: checkpoint,
      );
    }
    final deletedAt = _requireTimestampArgs([args[1], args[2]], lineNumber);
    final checkpoint = _requireUnsignedCountArg(
      [args[3]],
      lineNumber,
      maxAllowed: maxCompletions,
      allowZero: true,
    );
    return TdfDeletedTaskRecord(
      taskId: idToken.value,
      deletedAt: deletedAt,
      completionsCheckpoint: checkpoint,
    );
  }

  /// Parses an inline `condition ...` directive on a `label` or `task` block.
  static TaskCondition _parseInlineConditionArgs(
    List<_ScannedToken> args, {
    required bool allowResets,
    required int lineNumber,
  }) {
    if (args.isEmpty || args[0].kind != _TokenKind.bareWord) {
      throw TdfException(
        kind: TdfErrorKind.invalidCondition,
        line: lineNumber,
        message: 'Directive "condition" requires a condition type.',
      );
    }
    final first = args[0].value;
    if (first == 'any') {
      if (!allowResets || args.length != 1) {
        throw TdfException(
          kind: TdfErrorKind.invalidCondition,
          line: lineNumber,
          message: 'Invalid "condition any" directive.',
        );
      }
      return const GlobalResetTaskCondition();
    }
    return _parseConditionGroupRule(
      first,
      args.sublist(1),
      allowResets: allowResets,
      lineNumber: lineNumber,
    );
  }

  /// Internal single-pass TDF 0.5.0 scanner and parser implementation called by [parse].
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
    _validateByteLimit(tdfContent);
    final state = _ParserState();
    var offset = 0;
    var lineNumber = 0;

    while (offset < tdfContent.length) {
      lineNumber++;
      if (lineNumber > maxLineCount) {
        throw TdfException(
          kind: TdfErrorKind.limitExceeded,
          line: lineNumber,
          message: 'TDF document exceeds maximum line count of $maxLineCount.',
        );
      }
      final span = _findLineSpan(tdfContent, offset, lineNumber);
      _processLogicalLine(
        tdfContent,
        span.lineStart,
        span.lineEnd,
        lineNumber,
        state,
      );
      offset = span.nextOffset;
    }

    if (!state.hasSeenFirstStatement) {
      throw const TdfException(
        kind: TdfErrorKind.missingVersionHeader,
        line: 1,
        message: 'TDF document is missing required "tdf 0.5.0" version header.',
      );
    }

    if (state.blockStack.isNotEmpty) {
      throw TdfException(
        kind: TdfErrorKind.unclosedBlock,
        line: lineNumber == 0 ? 1 : lineNumber,
        message: 'Reached end of file with unclosed block.',
      );
    }

    _validateLabelReferences(state);
    _validateDependencyCycles(state.taskEntries);
    _validateQueueMembership(state);

    final tasks = <TaskItem>[for (final entry in state.taskEntries) entry.task];

    return TaskBoard.evaluate(
      tasks: tasks,
      evaluationTime: evaluationTime,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      labels: state.labels,
      deletedBlock: state.deletedBlock,
      queueBlock: state.queueBlock,
      activeLabelId: activeLabelId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
      pruneExpiredCompleted: pruneExpiredCompleted,
    );
  }

  /// Parses `location <lat> <lon> <radius>` arguments.
  static LocationTaskCondition _parseLocationRuleArgs(
    List<_ScannedToken> ruleArgs,
    int lineNumber,
  ) {
    if (ruleArgs.length != 3) {
      throw TdfException(
        kind: TdfErrorKind.invalidCondition,
        line: lineNumber,
        message: 'Condition "location" requires <lat>, <lon>, and <radius> arguments.',
      );
    }
    final latitude = _requireNumberToken(ruleArgs[0], lineNumber);
    final longitude = _requireNumberToken(ruleArgs[1], lineNumber);
    final radiusMeters = _requireNumberToken(ruleArgs[2], lineNumber);
    _validateGpsBounds(latitude, longitude, radiusMeters, lineNumber);
    return LocationTaskCondition(
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );
  }

  /// Parses `time <start_HH:MM> <end_HH:MM>` arguments.
  static TimeWindowTaskCondition _parseTimeRuleArgs(
    List<_ScannedToken> ruleArgs,
    int lineNumber,
  ) {
    if (ruleArgs.length != 2 ||
        ruleArgs[0].kind != _TokenKind.bareWord ||
        ruleArgs[1].kind != _TokenKind.bareWord) {
      throw TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: lineNumber,
        message: 'Condition "time" requires two <HH:MM> arguments.',
      );
    }
    final startMinutes = TaskItem.tryParseTimeMinutes(ruleArgs[0].value);
    final endMinutes = TaskItem.tryParseTimeMinutes(ruleArgs[1].value);
    if (startMinutes == null || endMinutes == null) {
      throw TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: lineNumber,
        message: 'Invalid <HH:MM> time window in condition time.',
      );
    }
    if (startMinutes == endMinutes) {
      throw TdfException(
        kind: TdfErrorKind.invalidCondition,
        line: lineNumber,
        message: 'Condition "time" start and end times must not be identical.',
      );
    }
    return TimeWindowTaskCondition(
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      startToken: ruleArgs[0].value,
      endToken: ruleArgs[1].value,
    );
  }

  /// Processes a line containing an opening brace `{` as a block header.
  static void _processBlockHeaderLine(
    _ParserState state,
    List<_ScannedToken> tokens,
    int openBraceIndex,
    int lineNumber,
  ) {
    if (openBraceIndex != tokens.length - 1) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: lineNumber,
        message: 'Trailing tokens after "{" are not permitted.',
      );
    }

    final argCount = openBraceIndex - 1;
    if (argCount > maxArgsPerStmt) {
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: lineNumber,
        message: 'Block header exceeds maximum of $maxArgsPerStmt arguments.',
      );
    }

    final headerArgs = tokens.sublist(1, openBraceIndex);
    for (final arg in headerArgs) {
      if (arg.kind == _TokenKind.closeBrace) {
        throw TdfException(
          kind: TdfErrorKind.unexpectedToken,
          line: lineNumber,
          message: 'Unexpected "}" in block header.',
        );
      }
    }

    _openBlock(state, tokens[0].value, headerArgs, lineNumber);
  }

  /// Processes a directive line inside the currently open block.
  static void _processDirectiveLine(
    _ParserState state,
    List<_ScannedToken> tokens,
    int lineNumber,
  ) {
    if (tokens.length == 1) {
      throw TdfException(
        kind: TdfErrorKind.missingDirectiveArgument,
        line: lineNumber,
        message: 'Directive "${tokens[0].value}" is missing arguments.',
      );
    }
    if (state.blockStack.isEmpty) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedRootDirective,
        line: lineNumber,
        message: 'Directive "${tokens[0].value}" is not allowed at root level.',
      );
    }

    final argCount = tokens.length - 1;
    if (argCount > maxArgsPerStmt) {
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: lineNumber,
        message: 'Directive exceeds maximum of $maxArgsPerStmt arguments.',
      );
    }

    final activeBlock = state.blockStack.last;
    if (activeBlock is! _DeletedBlockBuilder &&
        activeBlock is! _QueueBlockBuilder) {
      if (activeBlock.statementCount + 1 > maxStmtsPerBlock) {
        throw TdfException(
          kind: TdfErrorKind.limitExceeded,
          line: lineNumber,
          message: 'Block exceeds maximum statements of $maxStmtsPerBlock.',
        );
      }
    }
    activeBlock.statementCount++;

    final directiveName = tokens[0].value;
    final args = tokens.sublist(1);
    switch (activeBlock) {
      case final _TaskBuilder taskBuilder:
        _applyTaskDirective(
          taskBuilder,
          directiveName,
          args,
          lineNumber,
          isLegacy050: state.isLegacy050,
        );
      case final _LabelBuilder labelBuilder:
        _applyLabelDirective(labelBuilder, directiveName, args, lineNumber);
      case final _DeletedBlockBuilder deletedBuilder:
        _applyDeletedDirective(
          state,
          deletedBuilder,
          directiveName,
          args,
          lineNumber,
        );
      case final _QueueBlockBuilder queueBuilder:
        _applyQueueDirective(queueBuilder, directiveName, args, lineNumber);
      case final _SubtasksBuilder subtasksBuilder:
        _applySubtasksDirective(
          subtasksBuilder,
          directiveName,
          args,
          lineNumber,
        );
      case final _ConditionBlockBuilder conditionBuilder:
        _applyConditionBlockDirective(
          conditionBuilder,
          directiveName,
          args,
          lineNumber,
        );
    }
  }

  /// Validates the first non-empty statement (`tdf 0.5.1` or legacy `tdf 0.5.0`) per Section 4.0 and Section 10.6.
  static bool _processInitialStatement(
    _ParserState state,
    List<_ScannedToken> tokens,
    int lineNumber,
  ) {
    final firstToken = tokens[0];
    if (firstToken.kind == _TokenKind.bareWord &&
        firstToken.value == 'tdf' &&
        _findTokenKindIndex(tokens, _TokenKind.openBrace) == -1 &&
        _findTokenKindIndex(tokens, _TokenKind.closeBrace) == -1) {
      if (tokens.length == 1) {
        throw TdfException(
          kind: TdfErrorKind.missingVersionHeader,
          line: lineNumber,
          message: 'Version header "tdf" requires a version argument.',
        );
      }
      if (tokens.length != 2 ||
          tokens[1].kind != _TokenKind.bareWord ||
          (tokens[1].value != supportedVersion &&
              tokens[1].value != legacySupportedVersion)) {
        throw TdfException(
          kind: TdfErrorKind.unsupportedVersion,
          line: lineNumber,
          message: 'Unsupported or malformed TDF version "${tokens[1].value}".',
        );
      }
      state.isLegacy050 = tokens[1].value == legacySupportedVersion;
      state.hasSeenFirstStatement = true;
      return true;
    }

    throw TdfException(
      kind: TdfErrorKind.missingVersionHeader,
      line: lineNumber,
      message:
          'TDF document must start with "tdf $supportedVersion" version header.',
    );
  }

  /// Tokenizes and executes a single logical line `[lineStart, lineEnd)`.
  static void _processLogicalLine(
    String source,
    int lineStart,
    int lineEnd,
    int lineNumber,
    _ParserState state,
  ) {
    final tokens = _scanLineTokens(source, lineStart, lineEnd, lineNumber);
    if (tokens.isEmpty) {
      return;
    }

    if (!state.hasSeenFirstStatement) {
      if (_processInitialStatement(state, tokens, lineNumber)) {
        return;
      }
    }

    if (tokens[0].kind == _TokenKind.closeBrace) {
      if (tokens.length > 1) {
        throw TdfException(
          kind: TdfErrorKind.unexpectedToken,
          line: lineNumber,
          message: 'Trailing tokens after "}" are not permitted.',
        );
      }
      _closeCurrentBlock(state, lineNumber);
      return;
    }

    final firstToken = tokens[0];
    if (firstToken.kind != _TokenKind.bareWord ||
        !_isValidIdentifier(firstToken.value)) {
      throw TdfException(
        kind: TdfErrorKind.invalidIdentifier,
        line: lineNumber,
        message: 'Invalid identifier "${firstToken.value}".',
      );
    }

    final openBraceIndex = _findTokenKindIndex(tokens, _TokenKind.openBrace);
    if (openBraceIndex != -1) {
      _processBlockHeaderLine(state, tokens, openBraceIndex, lineNumber);
      return;
    }

    if (_findTokenKindIndex(tokens, _TokenKind.closeBrace) != -1) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: lineNumber,
        message: 'Unexpected "}" on directive line.',
      );
    }

    _processDirectiveLine(state, tokens, lineNumber);
  }

  /// Validates that [args] contains a single quoted `#RRGGBB` hexadecimal color string.
  static String _requireColorArg(List<_ScannedToken> args, int lineNumber) {
    if (args.length != 1) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: lineNumber,
        message: 'Directive "color" requires a single "#RRGGBB" argument.',
      );
    }
    final token = args[0];
    if (token.kind != _TokenKind.quotedString ||
        !TdfColor.isStrictHexColor(token.value)) {
      throw TdfException(
        kind: TdfErrorKind.invalidColor,
        line: lineNumber,
        message: 'Invalid color literal "${token.value}".',
      );
    }
    return token.value.toUpperCase();
  }

  /// Validates and parses `blocked <dependency> [<dependency> ...]` arguments.
  static List<TdfTaskDependency> _requireDependencyListArgs(
    List<_ScannedToken> args,
    int lineNumber,
  ) {
    final parsed = <TdfTaskDependency>[];
    for (final token in args) {
      if (token.kind != _TokenKind.bareWord) {
        throw TdfException(
          kind: TdfErrorKind.invalidIdentifier,
          line: lineNumber,
          message: 'Quoted prerequisite token "${token.value}" is forbidden.',
        );
      }
      final raw = token.value;
      final colonIndex = raw.indexOf(':');
      final idPart = colonIndex < 0 ? raw : raw.substring(0, colonIndex);
      if (!isValidTaskId(idPart)) {
        throw TdfException(
          kind: TdfErrorKind.invalidIdentifier,
          line: lineNumber,
          message: 'Invalid prerequisite task identifier "$idPart".',
        );
      }
      if (colonIndex < 0) {
        parsed.add(TdfTaskDependency(taskId: idPart));
        continue;
      }
      final countPart = raw.substring(colonIndex + 1);
      if (!_isValidCanonicalUnsignedInt(countPart, allowZero: false)) {
        throw TdfException(
          kind: TdfErrorKind.invalidNumber,
          line: lineNumber,
          message: 'Invalid prerequisite completion count "$countPart".',
        );
      }
      final bigCount = BigInt.tryParse(countPart);
      if (bigCount == null) {
        throw TdfException(
          kind: TdfErrorKind.invalidNumber,
          line: lineNumber,
          message: 'Invalid prerequisite completion count "$countPart".',
        );
      }
      if (bigCount > BigInt.from(maxCompletions)) {
        throw TdfException(
          kind: TdfErrorKind.limitExceeded,
          line: lineNumber,
          message:
              'Prerequisite completion count exceeds maximum of $maxCompletions.',
        );
      }
      parsed.add(
        TdfTaskDependency(taskId: idPart, requiredCompletion: bigCount.toInt()),
      );
    }
    return TdfTaskDependency.normalizeList(parsed);
  }

  /// Validates and extracts a list of canonical 10-character Base62 `<label-id>` bare words.
  static List<String> _requireLabelIdListArgs(
    List<_ScannedToken> args,
    int lineNumber,
  ) {
    final ids = <String>[];
    for (final token in args) {
      if (token.kind != _TokenKind.bareWord || !isValidLabelId(token.value)) {
        throw TdfException(
          kind: TdfErrorKind.invalidIdentifier,
          line: lineNumber,
          message: 'Invalid label identifier "${token.value}".',
        );
      }
      ids.add(token.value);
    }
    return ids;
  }

  /// Validates that [args] contains a single non-empty text argument within [maxTextLength] Unicode scalars.
  static String _requireNameOrStepArg(
    List<_ScannedToken> args,
    int lineNumber,
  ) {
    if (args.length != 1) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: lineNumber,
        message: 'Expected exactly 1 argument, found ${args.length}.',
      );
    }
    final value = args[0].value;
    if (value.trim().isEmpty) {
      throw TdfException(
        kind: TdfErrorKind.emptyText,
        line: lineNumber,
        message: 'Text argument must not be empty or whitespace-only.',
      );
    }
    _requireScalarLength(value, maxTextLength, lineNumber);
    return value;
  }

  /// Validates that [args] contains a single non-empty `note` argument (`1..maxNoteLength` Unicode scalars).
  static String _requireNoteArg(List<_ScannedToken> args, int lineNumber) {
    if (args.length != 1) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: lineNumber,
        message: 'Directive "note" requires a single text argument.',
      );
    }
    final value = args[0].value;
    if (value.isEmpty) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: lineNumber,
        message: 'Directive "note" must not be empty.',
      );
    }
    _requireScalarLength(value, maxNoteLength, lineNumber);
    return value;
  }

  /// Validates and parses a decimal `<number>` token (`-?[0-9]+(\.[0-9]+)?`).
  static double _requireNumberToken(_ScannedToken token, int lineNumber) {
    if (token.kind != _TokenKind.bareWord ||
        !_isValidDecimalLiteral(token.value)) {
      throw TdfException(
        kind: TdfErrorKind.invalidNumber,
        line: lineNumber,
        message: 'Invalid numeric literal "${token.value}".',
      );
    }
    final parsed = double.tryParse(token.value);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      throw TdfException(
        kind: TdfErrorKind.invalidNumber,
        line: lineNumber,
        message: 'Invalid numeric literal "${token.value}".',
      );
    }
    return parsed;
  }

  /// Validates and parses `repeat <count> <days|weeks|months> [<repeat-time>]` arguments (`1..maxRepeatCount`).
  static TaskRepeatRule _requireRepeatRuleArgs(
    List<_ScannedToken> args,
    int lineNumber,
  ) {
    if (args.length < 2 || args.length > 3) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: lineNumber,
        message: 'Directive "repeat" requires <count>, <days|weeks|months>, and optional <repeat-time>.',
      );
    }
    final countToken = args[0];
    final unitToken = args[1];
    if (countToken.kind != _TokenKind.bareWord) {
      throw TdfException(
        kind: TdfErrorKind.invalidNumber,
        line: lineNumber,
        message: 'Invalid repeat count "${countToken.value}".',
      );
    }
    final parsedCount = int.tryParse(countToken.value);
    if (parsedCount == null || parsedCount < 1) {
      throw TdfException(
        kind: TdfErrorKind.invalidNumber,
        line: lineNumber,
        message: 'Repeat count must be a positive integer >= 1.',
      );
    }
    if (parsedCount > maxRepeatCount) {
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: lineNumber,
        message: 'Repeat count exceeds maximum of $maxRepeatCount.',
      );
    }
    final parsedUnit = unitToken.kind == _TokenKind.bareWord
        ? RepeatUnit.tryParseToken(unitToken.value)
        : null;
    if (parsedUnit == null) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: lineNumber,
        message:
            'Unknown repeat unit "${unitToken.value}" (expected days, weeks, or months).',
      );
    }
    var clock = TdfRepeatClock.midnight;
    if (args.length == 3) {
      final clockToken = args[2];
      final parsedClock = clockToken.kind == _TokenKind.bareWord
          ? TdfRepeatClock.tryParse(clockToken.value)
          : null;
      if (parsedClock == null) {
        throw TdfException(
          kind: TdfErrorKind.invalidTime,
          line: lineNumber,
          message: 'Invalid repeat clock "${clockToken.value}".',
        );
      }
      clock = parsedClock;
    }
    return TaskRepeatRule(count: parsedCount, unit: parsedUnit, clock: clock);
  }

  /// Validates that [text] contains at most [maxScalars] Unicode scalar values.
  static void _requireScalarLength(
    String text,
    int maxScalars,
    int lineNumber,
  ) {
    final scalarCount = TdfCalendar.countUnicodeScalars(text);
    if (scalarCount == null) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: lineNumber,
        message: 'Invalid unpaired UTF-16 surrogate in text value.',
      );
    }
    if (scalarCount > maxScalars) {
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: lineNumber,
        message:
            'Text argument exceeds maximum length of $maxScalars Unicode scalar values.',
      );
    }
  }

  /// Validates and parses `<YYYY-MM-DD> [<HH:MM[:SS]>]` timestamp arguments.
  static DateTime _requireTimestampArgs(
    List<_ScannedToken> args,
    int lineNumber,
  ) {
    if (args.isEmpty ||
        args.length > 2 ||
        args[0].kind != _TokenKind.bareWord ||
        (args.length == 2 && args[1].kind != _TokenKind.bareWord)) {
      throw TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: lineNumber,
        message: 'Expected <YYYY-MM-DD> [<HH:MM[:SS]>] timestamp arguments.',
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
        message: 'Invalid calendar date or 24-hour time in timestamp.',
      );
    }
    return parsed;
  }

  /// Validates a single unsigned integer bare word (`0..maxAllowed` or `1..maxAllowed`).
  static int _requireUnsignedCountArg(
    List<_ScannedToken> args,
    int lineNumber, {
    required int maxAllowed,
    required bool allowZero,
  }) {
    if (args.length != 1) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: lineNumber,
        message: 'Expected a single integer argument.',
      );
    }
    final token = args[0];
    if (token.kind != _TokenKind.bareWord ||
        !_isValidCanonicalUnsignedInt(token.value, allowZero: allowZero)) {
      throw TdfException(
        kind: TdfErrorKind.invalidNumber,
        line: lineNumber,
        message: 'Invalid integer literal "${token.value}".',
      );
    }
    final bigVal = BigInt.tryParse(token.value);
    if (bigVal == null) {
      throw TdfException(
        kind: TdfErrorKind.invalidNumber,
        line: lineNumber,
        message: 'Invalid integer literal "${token.value}".',
      );
    }
    if (bigVal > BigInt.from(maxAllowed)) {
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: lineNumber,
        message: 'Integer value exceeds maximum of $maxAllowed.',
      );
    }
    return bigVal.toInt();
  }

  /// Scans an unquoted bare word token starting at [start].
  static int _scanBareWordToken(
    String source,
    int start,
    int lineEnd,
    int lineNumber,
    List<_ScannedToken> tokens,
  ) {
    var cursor = start;
    while (cursor < lineEnd) {
      final unit = source.codeUnitAt(cursor);
      if (unit == 0x20 || unit == 0x09 || unit == 0x23) {
        break;
      }
      if (unit == 0x7B) {
        throw TdfException(
          kind: TdfErrorKind.invalidBlockHeader,
          line: lineNumber,
          message: 'Opening brace "{" must be preceded by whitespace.',
        );
      }
      if (unit == 0x7D ||
          unit == 0x22 ||
          unit == 0x27 ||
          _isInvalidBareChar(unit)) {
        throw TdfException(
          kind: TdfErrorKind.unexpectedToken,
          line: lineNumber,
          message: 'Invalid or adjacent delimiter inside bare word.',
        );
      }
      cursor++;
    }
    tokens.add(
      _ScannedToken(
        value: source.substring(start, cursor),
        kind: _TokenKind.bareWord,
      ),
    );
    return cursor;
  }

  /// Scans a double-quoted string token (`"..."`) starting at [start].
  static int _scanDoubleQuotedToken(
    String source,
    int start,
    int lineEnd,
    int lineNumber,
    List<_ScannedToken> tokens,
  ) {
    final buffer = StringBuffer();
    var cursor = start + 1;

    while (cursor < lineEnd) {
      final unit = source.codeUnitAt(cursor);
      if (unit == 0x22) {
        final nextCursor = cursor + 1;
        _validatePostQuoteDelimiter(source, nextCursor, lineEnd, lineNumber);
        tokens.add(
          _ScannedToken(
            value: buffer.toString(),
            kind: _TokenKind.quotedString,
          ),
        );
        return nextCursor;
      }
      if (unit == 0x5C) {
        if (cursor + 1 >= lineEnd) {
          throw TdfException(
            kind: TdfErrorKind.unterminatedString,
            line: lineNumber,
            message: 'Unterminated escape sequence at end of line.',
          );
        }
        buffer.writeCharCode(
          _unescapeChar(source.codeUnitAt(cursor + 1), lineNumber),
        );
        cursor += 2;
      } else {
        buffer.writeCharCode(unit);
        cursor++;
      }
    }

    throw TdfException(
      kind: TdfErrorKind.unterminatedString,
      line: lineNumber,
      message: 'Unterminated double-quoted string.',
    );
  }

  /// Scans all tokens on `[lineStart, lineEnd)` in a single pass.
  static List<_ScannedToken> _scanLineTokens(
    String source,
    int lineStart,
    int lineEnd,
    int lineNumber,
  ) {
    final tokens = <_ScannedToken>[];
    var cursor = lineStart;

    while (cursor < lineEnd) {
      cursor = _skipHorizontalWhitespace(source, cursor, lineEnd);
      if (cursor >= lineEnd || source.codeUnitAt(cursor) == 0x23) {
        break;
      }
      if (tokens.length >= maxArgsPerStmt + 3) {
        throw TdfException(
          kind: TdfErrorKind.limitExceeded,
          line: lineNumber,
          message: 'Statement exceeds maximum of $maxArgsPerStmt arguments.',
        );
      }
      cursor = _scanNextToken(source, cursor, lineEnd, lineNumber, tokens);
    }

    return tokens;
  }

  /// Scans a single token starting at [cursor] and appends it to [tokens].
  static int _scanNextToken(
    String source,
    int cursor,
    int lineEnd,
    int lineNumber,
    List<_ScannedToken> tokens,
  ) {
    final unit = source.codeUnitAt(cursor);
    if (unit == 0x7B) {
      tokens.add(const _ScannedToken(value: '{', kind: _TokenKind.openBrace));
      return cursor + 1;
    }
    if (unit == 0x7D) {
      tokens.add(const _ScannedToken(value: '}', kind: _TokenKind.closeBrace));
      return cursor + 1;
    }
    if (unit == 0x22) {
      return _scanDoubleQuotedToken(
        source,
        cursor,
        lineEnd,
        lineNumber,
        tokens,
      );
    }
    if (unit == 0x27) {
      return _scanSingleQuotedToken(
        source,
        cursor,
        lineEnd,
        lineNumber,
        tokens,
      );
    }
    return _scanBareWordToken(source, cursor, lineEnd, lineNumber, tokens);
  }

  /// Scans a single-quoted literal string token (`'...'`) starting at [start].
  static int _scanSingleQuotedToken(
    String source,
    int start,
    int lineEnd,
    int lineNumber,
    List<_ScannedToken> tokens,
  ) {
    var cursor = start + 1;
    while (cursor < lineEnd) {
      if (source.codeUnitAt(cursor) == 0x27) {
        final nextCursor = cursor + 1;
        _validatePostQuoteDelimiter(source, nextCursor, lineEnd, lineNumber);
        tokens.add(
          _ScannedToken(
            value: source.substring(start + 1, cursor),
            kind: _TokenKind.quotedString,
          ),
        );
        return nextCursor;
      }
      cursor++;
    }
    throw TdfException(
      kind: TdfErrorKind.unterminatedString,
      line: lineNumber,
      message: 'Unterminated single-quoted string.',
    );
  }

  /// Advances [cursor] past horizontal whitespace (`' '` and `'\t'`).
  static int _skipHorizontalWhitespace(String source, int cursor, int lineEnd) {
    var index = cursor;
    while (index < lineEnd) {
      final unit = source.codeUnitAt(index);
      if (unit != 0x20 && unit != 0x09) {
        break;
      }
      index++;
    }
    return index;
  }

  /// Throws a [TdfErrorKind.duplicateDirective] exception at [lineNumber].
  static Never _throwDuplicateDirective(String directive, int lineNumber) {
    throw TdfException(
      kind: TdfErrorKind.duplicateDirective,
      line: lineNumber,
      message: 'Duplicate "$directive" directive in block.',
    );
  }

  /// Throws a [TdfErrorKind.duplicateIdentifier] exception at [lineNumber].
  static Never _throwDuplicateId(String id, int lineNumber) {
    throw TdfException(
      kind: TdfErrorKind.duplicateIdentifier,
      line: lineNumber,
      message: 'Duplicate entity identifier "$id".',
    );
  }

  /// Resolves a double-quoted escape character (`\"`, `\\`, `\n`, `\r`, `\t`).
  static int _unescapeChar(int escapedUnit, int lineNumber) {
    return switch (escapedUnit) {
      0x22 => 0x22,
      0x5C => 0x5C,
      0x6E => 0x0A,
      0x72 => 0x0D,
      0x74 => 0x09,
      _ => throw TdfException(
        kind: TdfErrorKind.invalidEscapeSequence,
        line: lineNumber,
        message:
            'Invalid escape sequence "\\${String.fromCharCode(escapedUnit)}".',
      ),
    };
  }

  /// Validates that [tdfContent] does not exceed [maxFileBytes].
  static void _validateByteLimit(String tdfContent) {
    if (tdfContent.length > maxFileBytes ||
        utf8.encode(tdfContent).length > maxFileBytes) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message:
            'TDF document exceeds maximum file size of $maxFileBytes bytes.',
      );
    }
  }

  /// Validates that serialized [output] obeys [maxFileBytes] and [maxLineCount] per Section 7.1.
  static void _validateCanonicalOutputBounds(String output) {
    _validateByteLimit(output);
    var lineCount = 0;
    for (var i = 0; i < output.length; i++) {
      if (output.codeUnitAt(i) == 0x0A) {
        lineCount++;
        if (lineCount > maxLineCount) {
          throw TdfException(
            kind: TdfErrorKind.limitExceeded,
            line: lineCount,
            message:
                'Canonical TDF output exceeds maximum line count of $maxLineCount.',
          );
        }
      }
    }
  }

  /// Validates that the `blocked` task dependency graph is acyclic across [entries].
  static void _validateDependencyCycles(List<_ParsedTaskEntry> entries) {
    final taskById = <String, _ParsedTaskEntry>{
      for (final entry in entries) entry.task.id: entry,
    };
    final visitState = <String, int>{};
    for (final entry in entries) {
      if (entry.task.blockedByTaskIds.isNotEmpty) {
        _checkTaskCycle(entry.task.id, taskById, visitState, entry.blockedLine);
      }
    }
  }

  /// Validates WGS-84 coordinate and radius bounds (`lat` in `[-90, 90]`, `lon` in `[-180, 180]`, `radius > 0`).
  static void _validateGpsBounds(
    double latitude,
    double longitude,
    double radiusMeters,
    int lineNumber,
  ) {
    if (latitude < -90.0 ||
        latitude > 90.0 ||
        longitude < -180.0 ||
        longitude > 180.0 ||
        radiusMeters <= 0.0) {
      throw TdfException(
        kind: TdfErrorKind.invalidCondition,
        line: lineNumber,
        message:
            'Invalid GPS coordinates or radius ($latitude, $longitude, $radiusMeters).',
      );
    }
  }

  /// Validates canonical `labels` references across all parsed tasks.
  static void _validateLabelReferences(_ParserState state) {
    for (final entry in state.taskEntries) {
      for (final labelId in entry.canonicalLabelIds) {
        if (!state.labelIds.contains(labelId)) {
          throw TdfException(
            kind: TdfErrorKind.unknownLabelReference,
            line: entry.labelsLine,
            message:
                'Task "${entry.task.id}" references unknown label "$labelId".',
          );
        }
      }
    }
  }

  /// Validates the character immediately following a closing quote.
  static void _validatePostQuoteDelimiter(
    String source,
    int nextCursor,
    int lineEnd,
    int lineNumber,
  ) {
    if (nextCursor >= lineEnd) {
      return;
    }
    final nextUnit = source.codeUnitAt(nextCursor);
    if (nextUnit == 0x20 || nextUnit == 0x09 || nextUnit == 0x23) {
      return;
    }
    if (nextUnit == 0x7B) {
      throw TdfException(
        kind: TdfErrorKind.invalidBlockHeader,
        line: lineNumber,
        message: 'Opening brace "{" must be preceded by whitespace.',
      );
    }
    throw TdfException(
      kind: TdfErrorKind.unexpectedToken,
      line: lineNumber,
      message: 'Adjacent token after closing quote is not permitted.',
    );
  }

  /// Compares two legacy `0.5.0` queued open task entries for Section 10.6 step 2 queue synthesis.
  static int _compareLegacy050QueueEntries(
    ({int index, _ParsedTaskEntry entry}) first,
    ({int index, _ParsedTaskEntry entry}) second,
  ) {
    if (first.entry.task.isPriority != second.entry.task.isPriority) {
      return first.entry.task.isPriority ? -1 : 1;
    }
    final firstQueued =
        first.entry.legacyQueuedAt ?? first.entry.task.createdAt;
    final secondQueued =
        second.entry.legacyQueuedAt ?? second.entry.task.createdAt;
    final timeCompare = firstQueued.compareTo(secondQueued);
    if (timeCompare != 0) {
      return timeCompare;
    }
    return first.index.compareTo(second.index);
  }

  /// Synthesizes the root `queue` block from legacy `0.5.0` queued open tasks when omitted per Section 10.6 step 2.
  static TdfQueueBlock _synthesizeLegacy050Queue(
    List<_ParsedTaskEntry> entries,
  ) {
    final scheduledOpen = <({int index, _ParsedTaskEntry entry})>[];
    DateTime? latestModified;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final task = entry.task;
      if (entry.legacyQueuedAt != null &&
          !task.isCompleted &&
          task.completedAt == null) {
        scheduledOpen.add((index: i, entry: entry));
        final effectiveMod = task.effectiveModifiedAt;
        if (latestModified == null || effectiveMod.isAfter(latestModified)) {
          latestModified = effectiveMod;
        }
      }
    }
    scheduledOpen.sort(_compareLegacy050QueueEntries);
    return TdfQueueBlock(
      modifiedAt: latestModified ?? TdfQueueBlock.epochModifiedAt,
      taskIds: <String>[for (final item in scheduledOpen) item.entry.task.id],
    );
  }

  /// Validates `queue` entries per Section 4.5 (or converts legacy `0.5.0` queue membership per Section 10.6).
  static void _validateQueueMembership(_ParserState state) {
    if (state.isLegacy050) {
      if (!state.hasQueueBlock) {
        state.queueBlock = _synthesizeLegacy050Queue(state.taskEntries);
      } else {
        final scheduledOpenIds = <String>{
          for (final entry in state.taskEntries)
            if (entry.legacyQueuedAt != null &&
                !entry.task.isCompleted &&
                entry.task.completedAt == null)
              entry.task.id,
        };
        for (final queueEntry in state.queueEntries) {
          if (!scheduledOpenIds.contains(queueEntry.taskId)) {
            throw TdfException(
              kind: TdfErrorKind.invalidQueueMembership,
              line: queueEntry.line,
              message:
                  'Queue entry "${queueEntry.taskId}" does not reference a live scheduled open task.',
            );
          }
        }
        for (final entry in state.taskEntries) {
          if (scheduledOpenIds.contains(entry.task.id) &&
              !state.queueTaskIds.contains(entry.task.id)) {
            throw TdfException(
              kind: TdfErrorKind.invalidQueueMembership,
              line: entry.headerLine,
              message:
                  'Scheduled open task "${entry.task.id}" is missing from the shared queue block.',
            );
          }
        }
      }
      AppLogger.info(
        LogTag.tdf,
        'Converted legacy TDF 0.5.0 document in memory to TDF 0.5.1 (tasks=${state.taskEntries.length}, queued=${state.queueBlock.taskIds.length})',
      );
      return;
    }

    final openTaskIds = <String>{
      for (final entry in state.taskEntries)
        if (!entry.task.isCompleted && entry.task.completedAt == null)
          entry.task.id,
    };

    for (final queueEntry in state.queueEntries) {
      if (!openTaskIds.contains(queueEntry.taskId)) {
        throw TdfException(
          kind: TdfErrorKind.invalidQueueMembership,
          line: queueEntry.line,
          message:
              'Queue entry "${queueEntry.taskId}" does not reference a live open task.',
        );
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
    buffer.write(_escapeQuotedString(label.name));
    buffer.write('\n');
    if (label.color case final color?) {
      buffer.write('    color ');
      buffer.write(_escapeQuotedString(color));
      buffer.write('\n');
    }
    if (label.note case final note?) {
      buffer.write('    note ');
      buffer.write(_escapeQuotedString(note));
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
    buffer.write(_escapeQuotedString(task.title));
    buffer.write('\n');
    if (task.note case final note?) {
      buffer.write('    note ');
      buffer.write(_escapeQuotedString(note));
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
      buffer.write(_escapeQuotedString(link.title));
      buffer.write(' ');
      buffer.write(_escapeQuotedString(link.uri));
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
        buffer.write(_escapeQuotedString(step.title));
        buffer.write('\n');
      }
      buffer.write('    }\n');
    }
    buffer.write('}\n\n');
  }
}

/// Base class for open block builders on the parser stack.
sealed class _BlockBuilder {
  /// Number of direct child statements (directives or nested blocks) parsed so far.
  int statementCount = 0;
}

/// Mutable builder for a `condition { ... }` sub-block during single-pass parsing.
final class _ConditionBlockBuilder extends _BlockBuilder {
  /// Creates a [_ConditionBlockBuilder].
  _ConditionBlockBuilder({required this.parent, required this.allowResets});

  /// Whether `<type> any` reset directives are permitted in this sub-block.
  final bool allowResets;

  /// Enclosing `_TaskBuilder` or `_LabelBuilder`.
  final _BlockBuilder parent;

  /// Whether at least one condition rule directive was parsed inside this block.
  bool hasAnyRule = false;
}

/// Mutable builder for the root `deleted` block during single-pass parsing.
final class _DeletedBlockBuilder extends _BlockBuilder {
  /// Deleted label records in declaration order.
  final List<TdfDeletedLabelRecord> labels = <TdfDeletedLabelRecord>[];

  /// Deleted task records in declaration order.
  final List<TdfDeletedTaskRecord> tasks = <TdfDeletedTaskRecord>[];

  /// Parsed `generation` counter.
  int? generation;

  /// Total deletion records parsed in this block.
  int get totalRecords => tasks.length + labels.length;

  /// Validates required `generation` directive and builds a [TdfDeletedBlock].
  TdfDeletedBlock build(int lineNumber) {
    final resolvedGen = generation;
    if (resolvedGen == null) {
      throw TdfException(
        kind: TdfErrorKind.missingRequiredDirective,
        line: lineNumber,
        message: 'Deleted block is missing required "generation" directive.',
      );
    }
    return TdfDeletedBlock(
      generation: resolvedGen,
      tasks: tasks,
      labels: labels,
    );
  }
}

/// Mutable builder for a `label` block during single-pass parsing.
final class _LabelBuilder extends _BlockBuilder {
  /// Creates a [_LabelBuilder] for [id].
  _LabelBuilder({required this.id});

  /// Accumulated `condition` rules in declaration order.
  final List<TaskCondition> conditions = <TaskCondition>[];

  /// Label `<id>`.
  final String id;

  /// Optional `color` value.
  String? color;

  /// Optional `modified` timestamp.
  DateTime? modifiedAt;

  /// Required `name` value.
  String? name;

  /// Optional `note` value.
  String? note;

  /// Validates required directives and builds an immutable [TdfLabel].
  TdfLabel build(int lineNumber) {
    final resolvedName = name;
    if (resolvedName == null) {
      throw TdfException(
        kind: TdfErrorKind.missingRequiredDirective,
        line: lineNumber,
        message: 'Label "$id" is missing required "name" directive.',
      );
    }
    return TdfLabel(
      id: id,
      name: resolvedName,
      color: color,
      note: note,
      modifiedAt: modifiedAt,
      conditions: List<TaskCondition>.unmodifiable(conditions),
    );
  }
}

/// Represents the start, end, and next offset of a single logical line.
@immutable
class _LineSpan {
  /// Creates a [_LineSpan].
  const _LineSpan({
    required this.lineStart,
    required this.lineEnd,
    required this.nextOffset,
  });

  /// Exclusive end index of the line content (before `\r` or `\n`).
  final int lineEnd;

  /// Inclusive start index of the line content.
  final int lineStart;

  /// Offset of the first character of the following line.
  final int nextOffset;
}

/// Pairs a built [TaskItem] with source line numbers and label reference lists for post-parse validation.
@immutable
class _ParsedTaskEntry {
  /// Creates a [_ParsedTaskEntry].
  const _ParsedTaskEntry({
    required this.task,
    required this.canonicalLabelIds,
    required this.headerLine,
    required this.labelsLine,
    required this.blockedLine,
    this.legacyQueuedAt,
  });

  /// 1-based line number of the `blocked` directive, or `0` if absent.
  final int blockedLine;

  /// Label IDs declared via the canonical `labels` directive.
  final List<String> canonicalLabelIds;

  /// 1-based line number of the `task <id>` block header.
  final int headerLine;

  /// 1-based line number of the `labels` directive, or `0` if absent.
  final int labelsLine;

  /// Optional `queued` timestamp parsed from a legacy `tdf 0.5.0` document.
  final DateTime? legacyQueuedAt;

  /// Built immutable task item.
  final TaskItem task;
}

/// Accumulates root blocks, identifier sets, and the active nesting stack during parsing.
class _ParserState {
  /// Active block nesting stack (maximum depth [TdfService.maxNestingDepth]).
  final List<_BlockBuilder> blockStack = <_BlockBuilder>[];

  /// Set of seen `deleted` label IDs to enforce uniqueness and disallow live+deleted collisions.
  final Set<String> deletedLabelIds = <String>{};

  /// Set of seen `deleted` task IDs to enforce uniqueness and disallow live+deleted collisions.
  final Set<String> deletedTaskIds = <String>{};

  /// Set of seen live `label` IDs to enforce uniqueness.
  final Set<String> labelIds = <String>{};

  /// Parsed `label` blocks in declaration order.
  final List<TdfLabel> labels = <TdfLabel>[];

  /// Parsed `queue` entries with their 1-based line numbers.
  final List<_QueueEntryLine> queueEntries = <_QueueEntryLine>[];

  /// Set of task IDs referenced in the `queue` block.
  final Set<String> queueTaskIds = <String>{};

  /// Parsed `task` entries in declaration order.
  final List<_ParsedTaskEntry> taskEntries = <_ParsedTaskEntry>[];

  /// Set of seen live `task` IDs to enforce uniqueness.
  final Set<String> taskIds = <String>{};

  /// Parsed `deleted` block (defaults to [TdfDeletedBlock.empty]).
  TdfDeletedBlock deletedBlock = TdfDeletedBlock.empty;

  /// Whether a `deleted` block has been opened.
  bool hasDeletedBlock = false;

  /// Whether a `queue` block has been opened.
  bool hasQueueBlock = false;

  /// Whether the initial `tdf 0.5.1` (or legacy `tdf 0.5.0`) header has been processed.
  bool hasSeenFirstStatement = false;

  /// Whether the input document declared the legacy `tdf 0.5.0` header.
  bool isLegacy050 = false;

  /// Parsed `queue` block (defaults to [TdfQueueBlock.empty]).
  TdfQueueBlock queueBlock = TdfQueueBlock.empty;

  /// Total blocks opened across the document.
  int totalBlocks = 0;
}

/// Mutable builder for the root `queue` block during single-pass parsing.
final class _QueueBlockBuilder extends _BlockBuilder {
  /// Ordered `task <id>` entries with their 1-based line numbers.
  final List<_QueueEntryLine> entries = <_QueueEntryLine>[];

  /// Seen task IDs inside this `queue` block to detect duplicates.
  final Set<String> seenTaskIds = <String>{};

  /// Parsed `modified` timestamp.
  DateTime? modifiedAt;

  /// Validates required `modified` directive and builds a [TdfQueueBlock].
  TdfQueueBlock build(int lineNumber) {
    final resolvedModified = modifiedAt;
    if (resolvedModified == null) {
      throw TdfException(
        kind: TdfErrorKind.missingRequiredDirective,
        line: lineNumber,
        message: 'Queue block is missing required "modified" directive.',
      );
    }
    return TdfQueueBlock(
      modifiedAt: resolvedModified,
      taskIds: <String>[for (final entry in entries) entry.taskId],
    );
  }
}

/// Pairs a `task <id>` entry inside `queue` with its 1-based line number.
@immutable
class _QueueEntryLine {
  /// Creates a [_QueueEntryLine].
  const _QueueEntryLine({required this.taskId, required this.line});

  /// 1-based line number of the `task <id>` directive in `queue`.
  final int line;

  /// Referenced `<task-id>`.
  final String taskId;
}

/// Lexical token scanned from a single TDF line.
@immutable
class _ScannedToken {
  /// Creates a [_ScannedToken].
  const _ScannedToken({required this.value, required this.kind});

  /// Lexical kind of the token.
  final _TokenKind kind;

  /// Unescaped string value of the token.
  final String value;
}

/// Mutable builder for a `subtasks` sub-block during single-pass parsing.
final class _SubtasksBuilder extends _BlockBuilder {
  /// Creates a [_SubtasksBuilder].
  _SubtasksBuilder({required this.autoFinish});

  /// Whether the `auto-finish` header flag was specified.
  final bool autoFinish;

  /// Accumulated checklist steps in declaration order.
  final List<SubtaskItem> steps = <SubtaskItem>[];
}

/// Mutable builder for a `task` block during single-pass parsing.
final class _TaskBuilder extends _BlockBuilder {
  /// Creates a [_TaskBuilder] for [id], [isPriority], and [headerLine].
  _TaskBuilder({
    required this.id,
    required this.isPriority,
    required this.headerLine,
  });

  /// Repeatable `condition` directives in declaration order.
  final List<TaskCondition> conditions = <TaskCondition>[];

  /// 1-based line number of the `task <id>` block header.
  final int headerLine;

  /// Task `<id>`.
  final String id;

  /// Whether the `priority` flag was present in the block header.
  final bool isPriority;

  /// Repeatable `link` directives in declaration order.
  final List<TaskLink> links = <TaskLink>[];

  /// 1-based line number of the `blocked` directive.
  int blockedLine = 0;

  /// Optional canonical `labels` IDs.
  List<String>? canonicalLabelIds;

  /// Optional `finished` timestamp.
  DateTime? completedAt;

  /// Optional `completions` counter.
  int? completions;

  /// 1-based line number of the `completions` directive.
  int completionsLine = 0;

  /// Required `created` timestamp.
  DateTime? createdAt;

  /// Optional `blocked` dependencies.
  List<TdfTaskDependency>? dependencies;

  /// 1-based line number of the `finished` directive.
  int finishedLine = 0;

  /// Whether a `subtasks` sub-block was already encountered.
  bool hasSubtasksBlock = false;

  /// Whether a `suspended` directive was already encountered.
  bool hasSuspendedDirective = false;

  /// Whether `suspended forever` was specified.
  bool isSuspendedForever = false;

  /// 1-based line number of the `labels` directive.
  int labelsLine = 0;

  /// Optional `queued` timestamp parsed from a legacy `tdf 0.5.0` document.
  DateTime? legacyQueuedAt;

  /// Optional `modified` timestamp.
  DateTime? modifiedAt;

  /// Required `name` string.
  String? name;

  /// Optional `note` string.
  String? note;

  /// Optional `repeat` rule.
  TaskRepeatRule? repeatRule;

  /// Parsed checklist steps from `subtasks`.
  List<SubtaskItem> subtasks = const <SubtaskItem>[];

  /// Whether `subtasks` carried `auto-finish`.
  bool subtasksAutoFinish = false;

  /// Optional finite `suspended` timestamp.
  DateTime? suspendedAt;

  /// Validates required directives (`name`, `created`, and completion state) and builds a [_ParsedTaskEntry].
  _ParsedTaskEntry build(int lineNumber, {required bool isLegacy050}) {
    final resolvedName = name;
    final resolvedCreated = createdAt;
    if (resolvedName == null || resolvedCreated == null) {
      throw TdfException(
        kind: TdfErrorKind.missingRequiredDirective,
        line: lineNumber,
        message:
            'Task "$id" is missing required "name" or "created" directive.',
      );
    }

    final effectiveCompletions = completions ?? 0;
    if (completedAt != null && effectiveCompletions <= 0) {
      final reportLine = completionsLine > 0
          ? completionsLine
          : (finishedLine > 0 ? finishedLine : lineNumber);
      throw TdfException(
        kind: TdfErrorKind.invalidCompletionState,
        line: reportLine,
        message:
            'Task "$id" has "finished" set but effective "completions" is 0.',
      );
    }

    final dedupedLabels = <String>[];
    final canonical = canonicalLabelIds ?? const <String>[];
    for (final labelId in canonical) {
      if (!dedupedLabels.contains(labelId)) {
        dedupedLabels.add(labelId);
      }
    }

    var resolvedModified = modifiedAt;
    if (isLegacy050 && resolvedModified == null && legacyQueuedAt != null) {
      final maxCreatedFinished =
          completedAt != null && completedAt!.isAfter(resolvedCreated)
          ? completedAt!
          : resolvedCreated;
      if (legacyQueuedAt!.isAfter(maxCreatedFinished)) {
        resolvedModified = legacyQueuedAt;
      }
    }

    final resolvedDeps = dependencies ?? const <TdfTaskDependency>[];
    final task = TaskItem(
      id: id,
      title: resolvedName,
      note: note,
      isCompleted: completedAt != null,
      isPriority: isPriority,
      completions: effectiveCompletions,
      createdAt: resolvedCreated,
      completedAt: completedAt,
      modifiedAt: resolvedModified,
      suspendedAt: suspendedAt,
      isSuspendedForever: isSuspendedForever,
      repeatRule: repeatRule,
      labelIds: dedupedLabels,
      dependencies: resolvedDeps,
      links: links,
      conditions: conditions,
      subtasksAutoFinish: subtasksAutoFinish,
      subtasks: subtasks,
    );

    return _ParsedTaskEntry(
      task: task,
      canonicalLabelIds: canonical,
      headerLine: headerLine,
      labelsLine: labelsLine,
      blockedLine: blockedLine,
      legacyQueuedAt: legacyQueuedAt,
    );
  }
}

/// Lexical category of a scanned token.
enum _TokenKind {
  /// Unquoted bare word (`[a-zA-Z0-9_-]`, numbers, dates, etc.).
  bareWord,

  /// Closing block brace `}`.
  closeBrace,

  /// Opening block brace `{`.
  openBrace,

  /// Double-quoted or single-quoted string literal.
  quotedString,
}
