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
  /// A single-valued directive appears more than once in the same block.
  duplicateDirective,

  /// Two blocks in the same namespace share an identical `<id>`.
  duplicateIdentifier,

  /// A block header is malformed or missing whitespace before `{`.
  invalidBlockHeader,

  /// A boolean literal is neither `true` nor `false`.
  invalidBoolean,

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

  /// A required directive (`name` or `created`) is missing from a block.
  missingRequiredDirective,

  /// End-of-file was reached while one or more `{ ... }` blocks remained open.
  unclosedBlock,

  /// A closing brace `}` was encountered at nesting depth `0`.
  unexpectedClosingBrace,

  /// A directive appears at nesting depth `0` outside of any `{ ... }` block.
  unexpectedRootDirective,

  /// An unexpected token, trailing token after a brace, or adjacent quote was encountered.
  unexpectedToken,

  /// A root or nested block identifier is not part of the TDF schema.
  unknownBlockType,

  /// A directive identifier is not valid for its enclosing block.
  unknownDirective,

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

  /// Maximum directives or sub-blocks inside a single block (`MAX_STMTS_PER_BLOCK`).
  static const int maxStmtsPerBlock = 512;

  /// Maximum character length of a `name` or `step` text value (`MAX_TEXT_LENGTH`).
  static const int maxTextLength = 500;

  /// Scans and parses [tdfContent] into a [TaskBoard] evaluated at [evaluationTime].
  TaskBoard parse(
    String tdfContent, {
    DateTime? evaluationTime,
    String? activeCategoryId,
    String? activeLocationId,
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

    if (state.blockStack.isNotEmpty) {
      throw TdfException(
        kind: TdfErrorKind.unclosedBlock,
        line: lineNumber == 0 ? 1 : lineNumber,
        message: 'Reached end of file with unclosed block.',
      );
    }

    return TaskBoard.evaluate(
      tasks: state.tasks,
      evaluationTime: evaluationTime,
      locations: state.locations,
      categories: state.categories,
      activeCategoryId: activeCategoryId,
      activeLocationId: activeLocationId,
      pruneExpiredCompleted: pruneExpiredCompleted,
    );
  }

  /// Serializes [board] into a canonical `LF`-terminated (`.tdf`) document string.
  String serialize(TaskBoard board) {
    final buffer = StringBuffer();
    for (final location in board.locations) {
      _writeLocationBlock(buffer, location);
    }
    for (final category in board.categories) {
      _writeCategoryBlock(buffer, category);
    }
    for (final task in board.allTasks) {
      _writeTaskBlock(buffer, task);
    }
    return buffer.toString();
  }

  /// Applies a directive inside a `category` block.
  static void _applyCategoryDirective(
    _CategoryBuilder builder,
    String directive,
    List<_ScannedToken> args,
    int lineNumber,
  ) {
    switch (directive) {
      case 'name':
        if (builder.name != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        final value = _requireSingleTextArg(
          args,
          lineNumber,
          enforceMaxLength: true,
        );
        builder.name = value;
      case 'color':
        if (builder.color != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.color = _requireSingleTextArg(
          args,
          lineNumber,
          enforceMaxLength: false,
        );
      case 'note':
        if (builder.note != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.note = _requireSingleTextArg(
          args,
          lineNumber,
          enforceMaxLength: false,
        );
      default:
        throw TdfException(
          kind: TdfErrorKind.unknownDirective,
          line: lineNumber,
          message: 'Unknown directive "$directive" in category block.',
        );
    }
  }

  /// Applies a directive inside a `location` block.
  static void _applyLocationDirective(
    _LocationBuilder builder,
    String directive,
    List<_ScannedToken> args,
    int lineNumber,
  ) {
    switch (directive) {
      case 'name':
        if (builder.name != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.name = _requireSingleTextArg(
          args,
          lineNumber,
          enforceMaxLength: true,
        );
      case 'note':
        if (builder.note != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.note = _requireSingleTextArg(
          args,
          lineNumber,
          enforceMaxLength: false,
        );
      case 'gps':
        if (builder.hasGps) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        _parseGpsArgs(builder, args, lineNumber);
      default:
        throw TdfException(
          kind: TdfErrorKind.unknownDirective,
          line: lineNumber,
          message: 'Unknown directive "$directive" in location block.',
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
        builder.name = _requireSingleTextArg(
          args,
          lineNumber,
          enforceMaxLength: true,
        );
      case 'note':
        if (builder.note != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.note = _requireSingleTextArg(
          args,
          lineNumber,
          enforceMaxLength: false,
        );
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
      case 'suspended':
        if (builder.suspendedAt != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.suspendedAt = _requireTimestampArgs(args, lineNumber);
      case 'locations':
        if (builder.locationIds != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.locationIds = _requireIdListArgs(args, lineNumber);
      case 'categories':
        if (builder.categoryIds != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.categoryIds = _requireIdListArgs(args, lineNumber);
      case 'blocked':
        if (builder.blockedByTaskIds != null) {
          _throwDuplicateDirective(directive, lineNumber);
        }
        builder.blockedByTaskIds = _requireIdListArgs(args, lineNumber);
      case 'condition':
        builder.conditions.add(_parseConditionArgs(args, lineNumber));
      default:
        throw TdfException(
          kind: TdfErrorKind.unknownDirective,
          line: lineNumber,
          message: 'Unknown directive "$directive" in task block.',
        );
    }
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
        state.tasks.add(taskBuilder.build(lineNumber));
      case final _LocationBuilder locationBuilder:
        state.locations.add(locationBuilder.build(lineNumber));
      case final _CategoryBuilder categoryBuilder:
        state.categories.add(categoryBuilder.build(lineNumber));
      case final _SubtasksBuilder subtasksBuilder:
        final parent = state.blockStack.last;
        if (parent is _TaskBuilder) {
          parent.subtasksAutoFinish = subtasksBuilder.autoFinish;
          parent.subtasks = subtasksBuilder.steps;
        }
    }
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

  /// Finds the end of the line starting at [startOffset] and validates line terminators.
  static _LineSpan _findLineSpan(
    String source,
    int startOffset,
    int lineNumber,
  ) {
    var index = startOffset;
    while (index < source.length) {
      final unit = source.codeUnitAt(index);
      if (unit == 0x00) {
        throw TdfException(
          kind: TdfErrorKind.unexpectedToken,
          line: lineNumber,
          message: 'Null byte is not permitted in a TDF document.',
        );
      }
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
      index++;
    }
    return _LineSpan(
      lineStart: startOffset,
      lineEnd: source.length,
      nextOffset: source.length,
    );
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

  /// Opens a new root or nested block on [state] after checking Section 7 bounds.
  static void _openBlock(
    _ParserState state,
    String blockName,
    List<_ScannedToken> headerArgs,
    bool closeImmediately,
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
    if (closeImmediately) {
      _closeCurrentBlock(state, lineNumber);
    }
  }

  /// Creates a nested block builder (only `subtasks` inside `task` is allowed at depth 1).
  static _BlockBuilder _createNestedBlockBuilder(
    _BlockBuilder parent,
    String blockName,
    List<_ScannedToken> headerArgs,
    int lineNumber,
  ) {
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

  /// Creates a root block builder (`task`, `location`, or `category`) and registers its `<id>`.
  static _BlockBuilder _createRootBlockBuilder(
    _ParserState state,
    String blockName,
    List<_ScannedToken> headerArgs,
    int lineNumber,
  ) {
    if (blockName != 'task' &&
        blockName != 'location' &&
        blockName != 'category') {
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
    if (blockName == 'location') {
      if (!state.locationIds.add(idToken.value)) {
        _throwDuplicateId(idToken.value, lineNumber);
      }
      return _LocationBuilder(id: idToken.value);
    }
    if (!state.categoryIds.add(idToken.value)) {
      _throwDuplicateId(idToken.value, lineNumber);
    }
    return _CategoryBuilder(id: idToken.value);
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

  /// Parses `condition` arguments (`day ...` or `time <HH:MM> <HH:MM>`).
  static TaskCondition _parseConditionArgs(
    List<_ScannedToken> args,
    int lineNumber,
  ) {
    if (args.length < 2 || args[0].kind != _TokenKind.bareWord) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: lineNumber,
        message: 'Directive "condition" requires a type and arguments.',
      );
    }
    final conditionType = args[0].value;
    if (conditionType == 'day') {
      return _parseDayCondition(args, lineNumber);
    }
    if (conditionType == 'time') {
      return _parseTimeCondition(args, lineNumber);
    }
    throw TdfException(
      kind: TdfErrorKind.unknownDirective,
      line: lineNumber,
      message: 'Unknown condition type "$conditionType".',
    );
  }

  /// Parses `condition day <mon|tue|wed|thu|fri|sat|sun ...>`.
  static DayTaskCondition _parseDayCondition(
    List<_ScannedToken> args,
    int lineNumber,
  ) {
    final weekdays = <int>[];
    final dayTokens = <String>[];
    for (var i = 1; i < args.length; i++) {
      final token = args[i];
      final weekday = token.kind == _TokenKind.bareWord
          ? DayTaskCondition.parseWeekdayToken(token.value)
          : null;
      if (weekday == null) {
        throw TdfException(
          kind: TdfErrorKind.unexpectedToken,
          line: lineNumber,
          message: 'Invalid weekday token "${token.value}" in condition day.',
        );
      }
      weekdays.add(weekday);
      dayTokens.add(token.value);
    }
    return DayTaskCondition(weekdays: weekdays, dayTokens: dayTokens);
  }

  /// Parses `gps <lat> <lon> [<radius>]` arguments on a `location` block.
  static void _parseGpsArgs(
    _LocationBuilder builder,
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
    final radius = args.length == 3
        ? _requireNumberToken(args[2], lineNumber)
        : null;
    builder.hasGps = true;
    builder.latitude = latitude;
    builder.longitude = longitude;
    builder.radiusMeters = radius;
  }

  /// Parses `condition time <HH:MM> <HH:MM>`.
  static TimeWindowTaskCondition _parseTimeCondition(
    List<_ScannedToken> args,
    int lineNumber,
  ) {
    if (args.length != 3 ||
        args[1].kind != _TokenKind.bareWord ||
        args[2].kind != _TokenKind.bareWord) {
      throw TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: lineNumber,
        message: 'Directive "condition time" requires two <HH:MM> arguments.',
      );
    }
    final startMinutes = TaskItem.tryParseTimeMinutes(args[1].value);
    final endMinutes = TaskItem.tryParseTimeMinutes(args[2].value);
    if (startMinutes == null || endMinutes == null) {
      throw TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: lineNumber,
        message: 'Invalid <HH:MM> time window in condition time.',
      );
    }
    return TimeWindowTaskCondition(
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      startToken: args[1].value,
      endToken: args[2].value,
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

  /// Processes a line containing an opening brace `{` as a block header.
  static void _processBlockHeaderLine(
    _ParserState state,
    List<_ScannedToken> tokens,
    int openBraceIndex,
    int lineNumber,
  ) {
    var closeImmediately = false;
    if (openBraceIndex == tokens.length - 2 &&
        tokens.last.kind == _TokenKind.closeBrace) {
      closeImmediately = true;
    } else if (openBraceIndex != tokens.length - 1) {
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

    _openBlock(
      state,
      tokens[0].value,
      headerArgs,
      closeImmediately,
      lineNumber,
    );
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
      case final _SubtasksBuilder subtasksBuilder:
        _applySubtasksDirective(
          subtasksBuilder,
          directiveName,
          args,
          lineNumber,
        );
      case final _LocationBuilder locationBuilder:
        _applyLocationDirective(
          locationBuilder,
          directiveName,
          args,
          lineNumber,
        );
      case final _CategoryBuilder categoryBuilder:
        _applyCategoryDirective(
          categoryBuilder,
          directiveName,
          args,
          lineNumber,
        );
    }
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

  /// Validates that [args] contains a single text argument, enforcing [maxTextLength] when requested.
  static String _requireSingleTextArg(
    List<_ScannedToken> args,
    int lineNumber, {
    required bool enforceMaxLength,
  }) {
    if (args.length != 1) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: lineNumber,
        message: 'Expected exactly 1 argument, found ${args.length}.',
      );
    }
    final value = args[0].value;
    if (enforceMaxLength && value.length > maxTextLength) {
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: lineNumber,
        message: 'Text argument exceeds maximum length of $maxTextLength.',
      );
    }
    return value;
  }

  /// Validates and parses `<YYYY-MM-DD> [<HH:MM>]` timestamp arguments.
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
        message: 'Expected <YYYY-MM-DD> [<HH:MM>] timestamp arguments.',
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

  /// Writes a canonical `category` block to [buffer].
  static void _writeCategoryBlock(StringBuffer buffer, TdfCategory category) {
    buffer.write('category ');
    buffer.write(category.id);
    buffer.write(' {\n    name ');
    buffer.write(_escapeQuotedString(category.name));
    buffer.write('\n');
    if (category.color case final color?) {
      buffer.write('    color ');
      buffer.write(_escapeQuotedString(color));
      buffer.write('\n');
    }
    if (category.note case final note?) {
      buffer.write('    note ');
      buffer.write(_escapeQuotedString(note));
      buffer.write('\n');
    }
    buffer.write('}\n\n');
  }

  /// Writes a canonical `location` block to [buffer].
  static void _writeLocationBlock(StringBuffer buffer, TdfLocation location) {
    buffer.write('location ');
    buffer.write(location.id);
    buffer.write(' {\n    name ');
    buffer.write(_escapeQuotedString(location.name));
    buffer.write('\n');
    if (location.note case final note?) {
      buffer.write('    note ');
      buffer.write(_escapeQuotedString(note));
      buffer.write('\n');
    }
    if (location.latitude case final lat?) {
      if (location.longitude case final lon?) {
        buffer.write('    gps ');
        buffer.write(lat);
        buffer.write(' ');
        buffer.write(lon);
        if (location.radiusMeters case final radius?) {
          buffer.write(' ');
          buffer.write(radius);
        }
        buffer.write('\n');
      }
    }
    buffer.write('}\n\n');
  }

  /// Writes a canonical `task` block (including optional `subtasks`) to [buffer].
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
    if (task.locationIds.isNotEmpty) {
      buffer.write('    locations ');
      buffer.write(task.locationIds.join(' '));
      buffer.write('\n');
    }
    if (task.categoryIds.isNotEmpty) {
      buffer.write('    categories ');
      buffer.write(task.categoryIds.join(' '));
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
    for (final condition in task.conditions) {
      buffer.write('    condition ');
      buffer.write(condition.toTdfDirectiveArgs());
      buffer.write('\n');
    }
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

/// Mutable builder for a `category` block during single-pass parsing.
final class _CategoryBuilder extends _BlockBuilder {
  /// Creates a [_CategoryBuilder] for [id].
  _CategoryBuilder({required this.id});

  /// Category `<id>`.
  final String id;

  /// Optional `color` value.
  String? color;

  /// Required `name` value.
  String? name;

  /// Optional `note` value.
  String? note;

  /// Validates required directives and builds an immutable [TdfCategory].
  TdfCategory build(int lineNumber) {
    final resolvedName = name;
    if (resolvedName == null) {
      throw TdfException(
        kind: TdfErrorKind.missingRequiredDirective,
        line: lineNumber,
        message: 'Category "$id" is missing required "name" directive.',
      );
    }
    return TdfCategory(id: id, name: resolvedName, color: color, note: note);
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

/// Mutable builder for a `location` block during single-pass parsing.
final class _LocationBuilder extends _BlockBuilder {
  /// Creates a [_LocationBuilder] for [id].
  _LocationBuilder({required this.id});

  /// Location `<id>`.
  final String id;

  /// Whether a `gps` directive has been parsed.
  bool hasGps = false;

  /// Optional latitude from `gps`.
  double? latitude;

  /// Optional longitude from `gps`.
  double? longitude;

  /// Required `name` value.
  String? name;

  /// Optional `note` value.
  String? note;

  /// Optional radius in meters from `gps`.
  double? radiusMeters;

  /// Validates required directives and builds an immutable [TdfLocation].
  TdfLocation build(int lineNumber) {
    final resolvedName = name;
    if (resolvedName == null) {
      throw TdfException(
        kind: TdfErrorKind.missingRequiredDirective,
        line: lineNumber,
        message: 'Location "$id" is missing required "name" directive.',
      );
    }
    return TdfLocation(
      id: id,
      name: resolvedName,
      note: note,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );
  }
}

/// Accumulates root blocks, identifier sets, and the active nesting stack during parsing.
class _ParserState {
  /// Active block nesting stack (maximum depth [TdfService.maxNestingDepth]).
  final List<_BlockBuilder> blockStack = <_BlockBuilder>[];

  /// Parsed `category` blocks in declaration order.
  final List<TdfCategory> categories = <TdfCategory>[];

  /// Set of seen `category` IDs to enforce uniqueness.
  final Set<String> categoryIds = <String>{};

  /// Set of seen `location` IDs to enforce uniqueness.
  final Set<String> locationIds = <String>{};

  /// Parsed `location` blocks in declaration order.
  final List<TdfLocation> locations = <TdfLocation>[];

  /// Set of seen `task` IDs to enforce uniqueness.
  final Set<String> taskIds = <String>{};

  /// Parsed `task` blocks in declaration order.
  final List<TaskItem> tasks = <TaskItem>[];

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

  /// Task `<id>`.
  final String id;

  /// Whether the `priority` flag was present in the block header.
  final bool isPriority;

  /// Optional `blocked` task IDs.
  List<String>? blockedByTaskIds;

  /// Optional `categories` IDs.
  List<String>? categoryIds;

  /// Optional `finished` timestamp.
  DateTime? completedAt;

  /// Repeatable `condition` directives in declaration order.
  final List<TaskCondition> conditions = <TaskCondition>[];

  /// Required `created` timestamp.
  DateTime? createdAt;

  /// Whether a `subtasks` sub-block was already encountered.
  bool hasSubtasksBlock = false;

  /// Optional `locations` IDs.
  List<String>? locationIds;

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

  /// Validates required directives (`name` and `created`) and builds an immutable [TaskItem].
  TaskItem build(int lineNumber) {
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
    return TaskItem(
      id: id,
      title: resolvedName,
      note: note,
      isCompleted: completedAt != null,
      isPriority: isPriority,
      createdAt: resolvedCreated,
      queuedAt: queuedAt,
      completedAt: completedAt,
      suspendedAt: suspendedAt,
      locationIds: locationIds ?? const <String>[],
      categoryIds: categoryIds ?? const <String>[],
      blockedByTaskIds: blockedByTaskIds ?? const <String>[],
      conditions: conditions,
      subtasksAutoFinish: subtasksAutoFinish,
      subtasks: subtasks,
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
