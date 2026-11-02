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

/// Mandatory lexical, structural, and semantic error categories defined in `TDF_SPEC.md` Section 8.
enum TdfErrorKind {
  /// A task's `blocked` dependency chain forms a cycle or self-dependency.
  circularDependency,

  /// A single-valued directive or sub-block appears more than once in the same block.
  duplicateDirective,

  /// Two blocks in the same namespace share an identical `<id>`.
  duplicateIdentifier,

  /// A block header is malformed or missing whitespace before `{`.
  invalidBlockHeader,

  /// A boolean literal is neither `true` nor `false`.
  invalidBoolean,

  /// A `color` argument is unquoted or fails `#RRGGBB` hexadecimal validation.
  invalidColor,

  /// A condition rule has an invalid weekday, equal time window, out-of-range GPS coordinate/radius, or invalid reset.
  invalidCondition,

  /// A double-quoted string contains an unsupported backslash escape sequence.
  invalidEscapeSequence,

  /// A block/directive identifier or entity ID is quoted or contains invalid characters.
  invalidIdentifier,

  /// A numeric argument fails decimal format validation.
  invalidNumber,

  /// A timestamp or time-window argument fails ISO-8601 calendar or 24-hour clock validation.
  invalidTimestamp,

  /// A resource bound defined in `TDF_SPEC.md` Section 7 was exceeded.
  limitExceeded,

  /// A standalone directive identifier appears without arguments and without `{`.
  missingDirectiveArgument,

  /// A required directive (`name`, `created`, `step`, or condition rule) is missing from a block.
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

/// Structured exception thrown when scanning, parsing, or validating a `.tdf` document fails.
@immutable
class TdfException implements Exception {
  /// Creates a [TdfException] for [kind] at 1-based [line] with [message].
  const TdfException({
    required this.kind,
    required this.line,
    required this.message,
  });

  /// Normative error category from `TDF_SPEC.md` Section 8.
  final TdfErrorKind kind;

  /// 1-based line number where the error occurred.
  final int line;

  /// Human-readable diagnostic description.
  final String message;

  @override
  String toString() => 'TdfException(${kind.name}, line $line): $message';
}

/// Stateless service that scans, parses, and serializes TierTask Data Format (`.tdf`) documents
/// in a single $O(N)$ linear pass without regular expressions.
class TdfService {
  /// Creates a const [TdfService].
  const TdfService();

  /// Legacy TDF specification version string (`tdf 0.2.0`) accepted for backward-compatible parsing.
  static const String legacyVersion = '0.2.0';

  /// Maximum arguments allowed on a single block header or directive (`MAX_ARGS_PER_STMT`).
  static const int maxArgsPerStmt = 64;

  /// Maximum total blocks per `.tdf` document (`MAX_BLOCKS_PER_DOC`).
  static const int maxBlocksPerDoc = 4096;

  /// Maximum input size in bytes (`MAX_FILE_BYTES`, 1 MiB).
  static const int maxFileBytes = 1048576;

  /// Maximum logical lines per `.tdf` document (`MAX_LINE_COUNT`).
  static const int maxLineCount = 16384;

  /// Maximum `{ ... }` block nesting depth (`MAX_NESTING_DEPTH`).
  static const int maxNestingDepth = 2;

  /// Maximum character length of a `note` text value (`MAX_NOTE_LENGTH`).
  static const int maxNoteLength = 2000;

  /// Maximum directives or sub-blocks inside a single block (`MAX_STMTS_PER_BLOCK`).
  static const int maxStmtsPerBlock = 512;

  /// Maximum character length of a `name` or `step` text value (`MAX_TEXT_LENGTH`).
  static const int maxTextLength = 500;

  /// Canonical TDF specification version string (`tdf 0.3.0`).
  static const String supportedVersion = '0.3.0';

  /// Scans and parses [tdfContent] into a [TaskBoard] evaluated at [evaluationTime].
  TaskBoard parse(
    String tdfContent, {
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
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
        message: 'TDF document is missing required "tdf 0.3.0" version header.',
      );
    }

    if (state.blockStack.isNotEmpty) {
      throw TdfException(
        kind: TdfErrorKind.unclosedBlock,
        line: lineNumber == 0 ? 1 : lineNumber,
        message: 'Reached end of file with unclosed block.',
      );
    }

    _validateAndResolveLabelReferences(state);
    _validateDependencyCycles(state.taskEntries);

    final tasks = <TaskItem>[for (final entry in state.taskEntries) entry.task];

    return TaskBoard.evaluate(
      tasks: tasks,
      evaluationTime: evaluationTime,
      localEvaluationTime: localEvaluationTime,
      labels: state.labels,
      activeLabelId: activeLabelId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
      pruneExpiredCompleted: pruneExpiredCompleted,
    );
  }

  /// Serializes [board] into a canonical `LF`-terminated (`.tdf`) document string.
  String serialize(TaskBoard board) {
    if (board.labels.isEmpty && board.allTasks.isEmpty) {
      return 'tdf $supportedVersion\n';
    }
    final buffer = StringBuffer('tdf $supportedVersion\n\n');
    for (final label in board.labels) {
      _writeLabelBlock(buffer, label);
    }
    for (final task in board.allTasks) {
      _writeTaskBlock(buffer, task);
    }
    return buffer.toString();
  }

  /// Adds [rule] to [builder] after verifying Section 4.3 reset conflict constraints.
  static void _addConditionToTask(
    _TaskBuilder builder,
    TaskCondition rule,
    int lineNumber,
  ) {
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
    builder.rules.add(_LineConditionRule(rule: rule, line: lineNumber));
  }

  /// Applies a directive inside a `label` (or legacy `category` / `location`) block.
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
        builder.conditions.add(rule);
      case 'gps':
        if (!builder.isLegacyLocation) {
          throw TdfException(
            kind: TdfErrorKind.unknownDirective,
            line: lineNumber,
            message: 'Unknown directive "gps" in label block.',
          );
        }
        if (builder.hasLegacyGps) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        _parseLegacyGpsArgs(builder, args, lineNumber);
      default:
        throw TdfException(
          kind: TdfErrorKind.unknownDirective,
          line: lineNumber,
          message: 'Unknown directive "$directive" in label block.',
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
    if (textValue.isEmpty) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: lineNumber,
        message: 'Step text must not be empty.',
      );
    }
    if (textValue.length > maxTextLength) {
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: lineNumber,
        message: 'Step text exceeds maximum length of $maxTextLength.',
      );
    }
    builder.steps.add(
      SubtaskItem(title: textValue, isCompleted: boolToken.value == 'true'),
    );
  }

  /// Applies a directive inside a `task` block.
  static void _applyTaskDirective(
    _TaskBuilder builder,
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
        if (builder.queuedAt != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.queuedAt = _requireTimestampArgs(args, lineNumber);
      case 'finished':
        if (builder.completedAt != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.completedAt = _requireTimestampArgs(args, lineNumber);
      case 'modified':
        if (builder.modifiedAt != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.modifiedAt = _requireTimestampArgs(args, lineNumber);
      case 'suspended':
        if (builder.suspendedAt != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.suspendedAt = _requireTimestampArgs(args, lineNumber);
      case 'labels':
        if (builder.canonicalLabelIds != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.canonicalLabelIds = _requireIdListArgs(args, lineNumber);
        builder.labelsLine = lineNumber;
      case 'categories':
        if (builder.hasLegacyCategories) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.hasLegacyCategories = true;
        builder.legacyLabelIds.addAll(_requireIdListArgs(args, lineNumber));
      case 'locations':
        if (builder.hasLegacyLocations) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.hasLegacyLocations = true;
        builder.legacyLabelIds.addAll(_requireIdListArgs(args, lineNumber));
      case 'blocked':
        if (builder.blockedByTaskIds != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.blockedByTaskIds = _requireIdListArgs(args, lineNumber);
        builder.blockedLine = lineNumber;
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
        state.taskEntries.add(taskBuilder.build(lineNumber));
      case final _LabelBuilder labelBuilder:
        state.labels.add(labelBuilder.build(lineNumber));
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
        if (conditionBuilder.rules.isEmpty) {
          throw TdfException(
            kind: TdfErrorKind.missingRequiredDirective,
            line: lineNumber,
            message: 'Condition block requires at least one condition rule.',
          );
        }
        final parent = state.blockStack.last;
        _mergeConditionBlockRules(parent, conditionBuilder.rules);
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

  /// Creates a root block builder (`label`, `task`, or legacy `category`/`location`) and registers its `<id>`.
  static _BlockBuilder _createRootBlockBuilder(
    _ParserState state,
    String blockName,
    List<_ScannedToken> headerArgs,
    int lineNumber,
  ) {
    if (blockName != 'label' &&
        blockName != 'task' &&
        blockName != 'category' &&
        blockName != 'location') {
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
    if (idToken.kind != _TokenKind.bareWord ||
        !_isValidEntityId(idToken.value)) {
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
        message: 'Block "$blockName" accepts only a single <id> argument.',
      );
    }
    if (!state.labelIds.add(idToken.value)) {
      _throwDuplicateId(idToken.value, lineNumber);
    }
    return _LabelBuilder(
      id: idToken.value,
      isLegacyLocation: blockName == 'location',
    );
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

  /// Finds the end of the line starting at [startOffset] and validates line terminators and control chars.
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
    if (parent is _TaskBuilder) {
      if (parent.hasConditionBlock) {
        _throwDuplicateDirective('condition', lineNumber);
      }
      parent.hasConditionBlock = true;
      return _ConditionBlockBuilder(allowResets: true);
    }
    final labelParent = parent as _LabelBuilder;
    if (labelParent.hasConditionBlock) {
      _throwDuplicateDirective('condition', lineNumber);
    }
    labelParent.hasConditionBlock = true;
    return _ConditionBlockBuilder(allowResets: false);
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
    if (!state.taskIds.add(id)) {
      _throwDuplicateId(id, lineNumber);
    }
    return _TaskBuilder(id: id, isPriority: isPriority);
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

  /// Checks whether [codeUnit] is a disallowed control or non-ASCII whitespace character outside quotes.
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
        codeUnit == 0x3000;
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

  /// Validates that [value] matches `<id>` (`[a-zA-Z0-9_-]+`).
  static bool _isValidEntityId(String value) {
    if (value.isEmpty) {
      return false;
    }
    for (var i = 0; i < value.length; i++) {
      if (!_isIdContinueChar(value.codeUnitAt(i))) {
        return false;
      }
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

  /// Merges validated [rules] from a `condition { ... }` sub-block into [parent].
  static void _mergeConditionBlockRules(
    _BlockBuilder parent,
    List<_LineConditionRule> rules,
  ) {
    if (parent is _LabelBuilder) {
      for (final entry in rules) {
        parent.conditions.add(entry.rule);
      }
      return;
    }
    if (parent is _TaskBuilder) {
      for (final entry in rules) {
        _addConditionToTask(parent, entry.rule, entry.line);
      }
    }
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

  /// Orders [conditions] into canonical `day`, `time`, and `location` groups per Section 3.4.
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

  /// Parses legacy `gps <lat> <lon> [<radius>]` arguments on a legacy `location` block.
  static void _parseLegacyGpsArgs(
    _LabelBuilder builder,
    List<_ScannedToken> args,
    int lineNumber,
  ) {
    if (args.length < 2 || args.length > 3) {
      throw TdfException(
        kind: TdfErrorKind.invalidNumber,
        line: lineNumber,
        message: 'Directive "gps" requires 2 or 3 numeric arguments.',
      );
    }
    final latitude = _requireNumberToken(args[0], lineNumber);
    final longitude = _requireNumberToken(args[1], lineNumber);
    final radiusMeters = args.length == 3
        ? _requireNumberToken(args[2], lineNumber)
        : 150.0;
    _validateGpsBounds(latitude, longitude, radiusMeters, lineNumber);
    builder.hasLegacyGps = true;
    builder.conditions.add(
      LocationTaskCondition(
        latitude: latitude,
        longitude: longitude,
        radiusMeters: radiusMeters,
      ),
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
    if (activeBlock.statementCount + 1 > maxStmtsPerBlock) {
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: lineNumber,
        message: 'Block exceeds maximum statements of $maxStmtsPerBlock.',
      );
    }
    activeBlock.statementCount++;

    final directiveName = tokens[0].value;
    final args = tokens.sublist(1);
    switch (activeBlock) {
      case final _TaskBuilder taskBuilder:
        _applyTaskDirective(taskBuilder, directiveName, args, lineNumber);
      case final _LabelBuilder labelBuilder:
        _applyLabelDirective(labelBuilder, directiveName, args, lineNumber);
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

  /// Validates the first non-empty statement (`tdf 0.2.0` or legacy `category`/`location` root block).
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
              tokens[1].value != legacyVersion)) {
        throw TdfException(
          kind: TdfErrorKind.unsupportedVersion,
          line: lineNumber,
          message: 'Unsupported or malformed TDF version "${tokens[1].value}".',
        );
      }
      state.hasSeenFirstStatement = true;
      return true;
    }

    if (firstToken.kind == _TokenKind.bareWord &&
        (firstToken.value == 'category' || firstToken.value == 'location') &&
        _findTokenKindIndex(tokens, _TokenKind.openBrace) != -1) {
      state.hasSeenFirstStatement = true;
      return false;
    }

    throw TdfException(
      kind: TdfErrorKind.missingVersionHeader,
      line: lineNumber,
      message:
          'TDF document must start with "tdf $supportedVersion" version header.',
    );
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

  /// Validates and extracts a list of entity `<id>` bare words.
  static List<String> _requireIdListArgs(
    List<_ScannedToken> args,
    int lineNumber,
  ) {
    final ids = <String>[];
    for (final token in args) {
      if (token.kind != _TokenKind.bareWord || !_isValidEntityId(token.value)) {
        throw TdfException(
          kind: TdfErrorKind.invalidIdentifier,
          line: lineNumber,
          message: 'Invalid entity identifier "${token.value}".',
        );
      }
      ids.add(token.value);
    }
    return ids;
  }

  /// Validates that [args] contains a single non-empty text argument within [maxTextLength].
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
    if (value.isEmpty) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: lineNumber,
        message: 'Text argument must not be empty.',
      );
    }
    if (value.length > maxTextLength) {
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: lineNumber,
        message: 'Text argument exceeds maximum length of $maxTextLength.',
      );
    }
    return value;
  }

  /// Validates that [args] contains a single non-empty `note` argument (`1..maxNoteLength`).
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
    if (value.length > maxNoteLength) {
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: lineNumber,
        message: 'Note exceeds maximum length of $maxNoteLength.',
      );
    }
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
      message: 'Duplicate block identifier "$id".',
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

  /// Validates canonical `labels` references and synthesizes missing labels for legacy `categories`/`locations`.
  static void _validateAndResolveLabelReferences(_ParserState state) {
    for (final entry in state.taskEntries) {
      _validateTaskLabelEntry(entry, state);
    }
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

  /// Validates canonical `labels` and legacy `categories`/`locations` for a single [entry].
  static void _validateTaskLabelEntry(
    _ParsedTaskEntry entry,
    _ParserState state,
  ) {
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
    for (final legacyId in entry.legacyLabelIds) {
      if (state.labelIds.add(legacyId)) {
        state.labels.add(TdfLabel(id: legacyId, name: legacyId));
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

  /// Writes a canonical `task` block (including optional `condition` and `subtasks`) to [buffer].
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
    if (task.queuedAt case final queuedAt?) {
      buffer.write('    queued ');
      buffer.write(TaskItem.formatTdfTimestamp(queuedAt));
      buffer.write('\n');
    }
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
    if (task.labelIds.isNotEmpty) {
      buffer.write('    labels ');
      buffer.write(task.labelIds.join(' '));
      buffer.write('\n');
    }
    if (task.blockedByTaskIds.isNotEmpty) {
      buffer.write('    blocked ');
      buffer.write(task.blockedByTaskIds.join(' '));
      buffer.write('\n');
    }
    if (task.suspendedAt case final suspendedAt?) {
      buffer.write('    suspended ');
      buffer.write(TaskItem.formatTdfTimestamp(suspendedAt));
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
  _ConditionBlockBuilder({required this.allowResets});

  /// Whether `<type> any` reset directives are permitted in this sub-block.
  final bool allowResets;

  /// Accumulated condition rules and their source line numbers.
  final List<_LineConditionRule> rules = <_LineConditionRule>[];
}

/// Mutable builder for a `label` (or legacy `category` / `location`) block during single-pass parsing.
final class _LabelBuilder extends _BlockBuilder {
  /// Creates a [_LabelBuilder] for [id].
  _LabelBuilder({required this.id, required this.isLegacyLocation});

  /// Accumulated `condition` rules in declaration order.
  final List<TaskCondition> conditions = <TaskCondition>[];

  /// Label `<id>`.
  final String id;

  /// Whether this block was opened via a legacy `location <id> {` header.
  final bool isLegacyLocation;

  /// Optional `color` value.
  String? color;

  /// Whether a `condition { ... }` sub-block was already encountered.
  bool hasConditionBlock = false;

  /// Whether a legacy `gps` directive has been parsed.
  bool hasLegacyGps = false;

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

/// Associates a parsed [TaskCondition] inside a `condition { ... }` sub-block with its 1-based line number.
@immutable
class _LineConditionRule {
  /// Creates a [_LineConditionRule].
  const _LineConditionRule({required this.rule, required this.line});

  /// 1-based line number where the rule was declared.
  final int line;

  /// Parsed condition rule.
  final TaskCondition rule;
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
    required this.legacyLabelIds,
    required this.labelsLine,
    required this.blockedLine,
  });

  /// 1-based line number of the `blocked` directive, or `0` if absent.
  final int blockedLine;

  /// Label IDs declared via the canonical `labels` directive.
  final List<String> canonicalLabelIds;

  /// 1-based line number of the `labels` directive, or `0` if absent.
  final int labelsLine;

  /// Label IDs declared via legacy `categories` or `locations` directives.
  final List<String> legacyLabelIds;

  /// Built immutable task item.
  final TaskItem task;
}

/// Accumulates root blocks, identifier sets, and the active nesting stack during parsing.
class _ParserState {
  /// Active block nesting stack (maximum depth [TdfService.maxNestingDepth]).
  final List<_BlockBuilder> blockStack = <_BlockBuilder>[];

  /// Set of seen `label` IDs to enforce uniqueness across `label` and legacy `category`/`location` blocks.
  final Set<String> labelIds = <String>{};

  /// Parsed `label` blocks in declaration order.
  final List<TdfLabel> labels = <TdfLabel>[];

  /// Parsed `task` entries in declaration order.
  final List<_ParsedTaskEntry> taskEntries = <_ParsedTaskEntry>[];

  /// Set of seen `task` IDs to enforce uniqueness.
  final Set<String> taskIds = <String>{};

  /// Whether the initial `tdf 0.2.0` header (or legacy root block) has been processed.
  bool hasSeenFirstStatement = false;

  /// Total blocks opened across the document.
  int totalBlocks = 0;
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
  /// Creates a [_TaskBuilder] for [id] and [isPriority].
  _TaskBuilder({required this.id, required this.isPriority});

  /// Repeatable `condition` directives in declaration order.
  final List<TaskCondition> conditions = <TaskCondition>[];

  /// Task `<id>`.
  final String id;

  /// Whether the `priority` flag was present in the block header.
  final bool isPriority;

  /// Legacy `categories` and `locations` IDs in declaration order.
  final List<String> legacyLabelIds = <String>[];

  /// Optional `blocked` task IDs.
  List<String>? blockedByTaskIds;

  /// 1-based line number of the `blocked` directive.
  int blockedLine = 0;

  /// Optional canonical `labels` IDs.
  List<String>? canonicalLabelIds;

  /// Optional `finished` timestamp.
  DateTime? completedAt;

  /// Required `created` timestamp.
  DateTime? createdAt;

  /// Whether a `condition { ... }` sub-block was already encountered.
  bool hasConditionBlock = false;

  /// Whether a legacy `categories` directive was already encountered.
  bool hasLegacyCategories = false;

  /// Whether a legacy `locations` directive was already encountered.
  bool hasLegacyLocations = false;

  /// Whether a `subtasks` sub-block was already encountered.
  bool hasSubtasksBlock = false;

  /// 1-based line number of the `labels` directive.
  int labelsLine = 0;

  /// Optional `modified` timestamp.
  DateTime? modifiedAt;

  /// Required `name` string.
  String? name;

  /// Optional `note` string.
  String? note;

  /// Optional `queued` timestamp.
  DateTime? queuedAt;

  /// Parsed checklist steps from `subtasks`.
  List<SubtaskItem> subtasks = const <SubtaskItem>[];

  /// Whether `subtasks` carried `auto-finish`.
  bool subtasksAutoFinish = false;

  /// Optional `suspended` timestamp.
  DateTime? suspendedAt;

  /// Validates required directives (`name` and `created`) and builds a [_ParsedTaskEntry].
  _ParsedTaskEntry build(int lineNumber) {
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

    final mergedLabelIds = <String>[];
    final canonical = canonicalLabelIds ?? const <String>[];
    for (final labelId in canonical) {
      if (!mergedLabelIds.contains(labelId)) {
        mergedLabelIds.add(labelId);
      }
    }
    for (final labelId in legacyLabelIds) {
      if (!mergedLabelIds.contains(labelId)) {
        mergedLabelIds.add(labelId);
      }
    }

    final task = TaskItem(
      id: id,
      title: resolvedName,
      note: note,
      isCompleted: completedAt != null,
      isPriority: isPriority,
      createdAt: resolvedCreated,
      queuedAt: queuedAt,
      completedAt: completedAt,
      modifiedAt: modifiedAt,
      suspendedAt: suspendedAt,
      labelIds: mergedLabelIds,
      blockedByTaskIds: blockedByTaskIds ?? const <String>[],
      conditions: conditions,
      subtasksAutoFinish: subtasksAutoFinish,
      subtasks: subtasks,
    );

    return _ParsedTaskEntry(
      task: task,
      canonicalLabelIds: canonical,
      legacyLabelIds: List<String>.unmodifiable(legacyLabelIds),
      labelsLine: labelsLine,
      blockedLine: blockedLine,
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
