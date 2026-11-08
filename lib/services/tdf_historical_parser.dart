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

import '../models/task_item.dart';
import '../models/tdf_error.dart';
import '../models/tdf_metadata.dart';

/// Parsed representation of a historical TDF `0.2.0`–`0.4.0` document.
@immutable
class TdfHistoricalDocument {
  /// Creates a [TdfHistoricalDocument].
  const TdfHistoricalDocument({required this.labels, required this.tasks});

  final List<TdfHistoricalLabel> labels;
  final List<TdfHistoricalTask> tasks;
}

/// Immutable representation of a historical `label` block.
@immutable
class TdfHistoricalLabel {
  /// Creates a [TdfHistoricalLabel] from a validated builder.
  TdfHistoricalLabel._(this._builder, [String? id])
    : color = _builder.texts['color'],
      conditionLines = List.unmodifiable(_builder.conditionLines),
      conditions = List.unmodifiable(_builder.conditions),
      id = id ?? _builder.id,
      modifiedAt = _builder.dates['modified'],
      name = _builder.texts['name'] ?? '',
      note = _builder.texts['note'];

  final String? color, note;
  final List<int> conditionLines;
  final List<TaskCondition> conditions;
  final String id, name;
  final DateTime? modifiedAt;
  final _HistoricalTaskBuilder _builder;

  /// Returns the 1-based line number of [directive], or `0` if absent.
  int lineOf(String directive) => _builder.lines[directive] ?? 0;

  /// Returns a copy of this historical label with an updated [id].
  TdfHistoricalLabel withId(String id) => TdfHistoricalLabel._(_builder, id);
}

/// Stateless lexical scanner and block parser for historical TDF `0.2.0`–`0.4.0` documents.
@immutable
class TdfHistoricalParser {
  /// Private constructor for static-only parser utility.
  const TdfHistoricalParser._();

  /// Parses and validates [source] against the pinned historical schema for [expectedVersion] (`0.2.0`, `0.3.0`, or `0.4.0`).
  static TdfHistoricalDocument parseDocument(
    String source, {
    required String expectedVersion,
    required String targetVersion,
  }) {
    final state = _ParseState(source, expectedVersion, targetVersion);
    final header =
        _nextStatementTokens(state) ??
        state.fail(TdfErrorKind.missingVersionHeader, 1);
    final validHeader =
        header.length == 2 &&
        header[0].kind == _HistTokenKind.bareWord &&
        header[0].value == 'tdf' &&
        header[1].kind == _HistTokenKind.bareWord &&
        header[1].value == expectedVersion;
    state.check(validHeader, TdfErrorKind.unsupportedVersion);
    while (state.offset < state.source.length) {
      final tokens = _nextStatementTokens(state);
      if (tokens != null) {
        _processTokens(tokens, state);
      }
    }
    state.check(state.stack.isEmpty, TdfErrorKind.unclosedBlock);
    final tasks = state.taskById.values.toList();
    for (final task in tasks) {
      if (!task.labelIds.every(state.seenLabels.contains)) {
        state.fail(TdfErrorKind.unknownLabelReference, task.lineOf('labels'));
      }
      _checkCycle(task.id, task.lineOf('blocked'), state);
    }
    return TdfHistoricalDocument(labels: state.labels, tasks: tasks);
  }

  /// Scans [source] and returns the first non-empty statement line for version header detection.
  static ({int line, List<String> bareWords, bool hasNonBareWords})?
  scanFirstStatement(String source) {
    final state = _ParseState(source);
    final tokens = _nextStatementTokens(state);
    if (tokens == null) {
      return null;
    }
    final validStart =
        tokens.first.kind == _HistTokenKind.bareWord &&
        !tokens.contains(_HistToken.openBrace) &&
        !tokens.contains(_HistToken.closeBrace);
    final bareWords = <String>[
      if (validStart)
        for (final token in tokens)
          if (token.kind == _HistTokenKind.bareWord) token.value,
    ];
    return (
      line: state.line,
      bareWords: bareWords,
      hasNonBareWords: bareWords.length != tokens.length,
    );
  }

  /// Parses and appends a condition rule and its line number to [builder].
  static void _addCondition(_HistoricalTaskBuilder builder, _ParseState state) {
    final type = state.directive;
    final arguments = state.arguments;
    final allowResets = !builder.isLabel;
    builder.conditionLines.add(state.line);
    if (type == 'any' && allowResets && arguments.isEmpty) {
      return builder.conditions.add(const GlobalResetTaskCondition());
    }
    if (arguments.length == 1 &&
        arguments.first.value == 'any' &&
        allowResets) {
      final group = switch (type) {
        'day' => ConditionGroup.day,
        'time' => ConditionGroup.time,
        'location' => ConditionGroup.location,
        _ => state.fail(TdfErrorKind.invalidCondition),
      };
      final reset = GroupResetTaskCondition(targetGroup: group);
      return builder.conditions.add(reset);
    }
    final TaskCondition rule;
    switch (type) {
      case 'day':
        final tokens = <String>[for (final arg in arguments) arg.value];
        final weekdays = <int>[
          for (final token in tokens)
            DayTaskCondition.parseWeekdayToken(token) ??
                state.fail(TdfErrorKind.invalidCondition),
        ];
        rule = DayTaskCondition(weekdays: weekdays, dayTokens: tokens);
      case 'time':
        state.check(arguments.length == 2, TdfErrorKind.invalidTimestamp);
        final start =
            TaskItem.tryParseTimeMinutes(arguments[0].value) ??
            state.fail(TdfErrorKind.invalidTimestamp);
        final end =
            TaskItem.tryParseTimeMinutes(arguments[1].value) ??
            state.fail(TdfErrorKind.invalidTimestamp);
        state.check(start != end, TdfErrorKind.invalidCondition);
        rule = TimeWindowTaskCondition(
          startMinutes: start,
          endMinutes: end,
          startToken: arguments[0].value,
          endToken: arguments[1].value,
        );
      case 'location':
        final values = <double>[
          for (final argument in arguments) ?double.tryParse(argument.value),
        ];
        final validLocation =
            arguments.length == 3 &&
            values.length == 3 &&
            values[0] >= -90.0 &&
            values[0] <= 90.0 &&
            values[1] >= -180.0 &&
            values[1] <= 180.0 &&
            values[2] > 0;
        state.check(validLocation, TdfErrorKind.invalidCondition);
        rule = LocationTaskCondition(
          locationIds: <String>[
            arguments[0].value,
            arguments[1].value,
            arguments[2].value,
          ],
        );
      default:
        state.fail(TdfErrorKind.unknownDirective);
    }
    builder.conditions.add(rule);
  }

  /// Applies a directive inside a label or task [active] builder.
  static void _applyEntityDirective(
    _HistoricalTaskBuilder active,
    _ParseState state,
  ) {
    final directive = state.directive;
    final arguments = state.arguments;
    final isLabel = active.isLabel;
    const labelDirectives = {'name', 'color', 'note', 'modified', 'condition'};
    final validOnLabel = !isLabel || labelDirectives.contains(directive);
    state.check(validOnLabel, TdfErrorKind.unknownDirective);
    active.lines[directive] = state.line;
    switch (directive) {
      case 'name' || 'note':
        active.texts[directive] = arguments.first.value;
      case 'color':
        state.check(isLabel, TdfErrorKind.unknownDirective);
        active.texts['color'] = arguments.first.value.toUpperCase();
      case 'created' || 'queued' || 'finished' || 'modified' || 'suspended':
        final allowedDate = directive != 'modified' || state.allow030;
        state.check(allowedDate, TdfErrorKind.unknownDirective);
        active.dates[directive] = _parseTimestamp(state);
      case 'repeat':
        final repeatKind = state.allow030
            ? TdfErrorKind.unexpectedToken
            : TdfErrorKind.unknownDirective;
        state.check(state.allow030 && arguments.length == 2, repeatKind);
        final count = int.tryParse(arguments[0].value) ?? 0;
        state.check(count >= 1, TdfErrorKind.invalidNumber);
        final unit =
            RepeatUnit.tryParseToken(arguments[1].value) ??
            state.fail(TdfErrorKind.unexpectedToken);
        active.repeatRule = TaskRepeatRule(count: count, unit: unit);
      case 'labels' || 'blocked':
        final target = directive == 'labels'
            ? active.labelIds
            : active.blockedByTaskIds;
        for (final argument in arguments) {
          final valid =
              argument.kind == _HistTokenKind.bareWord &&
              _isValidEntityId(argument.value);
          state.check(valid, TdfErrorKind.invalidIdentifier);
          target.add(argument.value);
        }
      case 'link':
        final linkKind = state.allow040
            ? TdfErrorKind.unexpectedToken
            : TdfErrorKind.unknownDirective;
        state.check(state.allow040 && arguments.length == 2, linkKind);
        final title = arguments[0].value, uri = arguments[1].value;
        active.links.add(TaskLink(title: title, uri: uri));
      case 'condition':
        state.directive = arguments.first.value;
        state.arguments = arguments.sublist(1);
        _addCondition(active, state);
      default:
        state.fail(TdfErrorKind.unknownDirective);
    }
  }

  /// Checks for dependency cycles in [state] task map.
  static void _checkCycle(String taskId, int fallbackLine, _ParseState state) {
    final visit = state.visitState[taskId] ?? 0;
    state.check(visit != 1, TdfErrorKind.circularDependency, fallbackLine);
    final entry = state.taskById[taskId];
    if (visit == 2 || entry == null) {
      state.visitState[taskId] = 2;
      return;
    }
    state.visitState[taskId] = 1;
    final blockedLine = entry.lineOf('blocked');
    for (final blockerId in entry.blockedByTaskIds) {
      _checkCycle(blockerId, blockedLine, state);
    }
    state.visitState[taskId] = 2;
  }

  /// Closes the topmost block on [state] stack.
  static void _closeBlock(List<_HistToken> tokens, _ParseState state) {
    state.check(tokens.length == 1, TdfErrorKind.unexpectedToken);
    state.check(state.stack.isNotEmpty, TdfErrorKind.unexpectedClosingBrace);
    final closed = state.stack.removeLast();
    if (closed is _HistoricalTaskBuilder && closed.isLabel) {
      final hasName = closed.texts['name'] != null;
      state.check(hasName, TdfErrorKind.missingRequiredDirective);
      state.labels.add(TdfHistoricalLabel._(closed));
    } else if (closed is _HistoricalTaskBuilder) {
      final hasReq =
          closed.texts['name'] != null && closed.dates['created'] != null;
      state.check(hasReq, TdfErrorKind.missingRequiredDirective);
      state.taskById[closed.id] = TdfHistoricalTask._(closed);
    } else if (closed is _HistoricalSubtasksBuilder) {
      final hasSteps = closed.steps.isNotEmpty;
      state.check(hasSteps, TdfErrorKind.missingRequiredDirective);
      final parent = state.stack.last as _HistoricalTaskBuilder;
      parent.subtasksAutoFinish = closed.autoFinish;
      parent.subtasks = closed.steps;
    } else if (closed is _HistoricalCondBlockBuilder) {
      state.check(closed.hasRules, TdfErrorKind.missingRequiredDirective);
    }
  }

  /// Advances [state] offset past the current line and returns the line end index.
  static int _findLineEnd(_ParseState state) {
    final source = state.source;
    var index = state.offset;
    while (index < source.length) {
      final unit = source.codeUnitAt(index);
      if (unit == 0x0A) {
        state.offset = index + 1;
        return index;
      }
      if (unit == 0x0D) {
        final hasLf =
            index + 1 < source.length && source.codeUnitAt(index + 1) == 0x0A;
        state.check(hasLf, TdfErrorKind.unexpectedToken);
        state.offset = index + 2;
        return index;
      }
      final validUnit = (unit >= 0x20 || unit == 0x09) && unit != 0x7F;
      state.check(validUnit, TdfErrorKind.unexpectedToken);
      index++;
    }
    return state.offset = source.length;
  }

  /// Checks whether [raw] matches a historical entity ID (`[a-zA-Z0-9_-]+`).
  static bool _isValidEntityId(String raw) {
    for (var i = 0; i < raw.length; i++) {
      final unit = raw.codeUnitAt(i);
      final valid =
          (unit >= 0x30 && unit <= 0x39) ||
          (unit >= 0x41 && unit <= 0x5A) ||
          (unit >= 0x61 && unit <= 0x7A) ||
          unit == 0x5F ||
          unit == 0x2D;
      if (!valid) {
        return false;
      }
    }
    return raw.isNotEmpty;
  }

  /// Advances [state] to the next non-empty tokenized statement line, or `null` at EOF.
  static List<_HistToken>? _nextStatementTokens(_ParseState state) {
    while (state.offset < state.source.length) {
      state.check(++state.line <= maxTdfLineCount, TdfErrorKind.limitExceeded);
      if (_scanTokens(state).isNotEmpty) {
        return state.tokens;
      }
    }
    return null;
  }

  /// Opens a root or nested block and pushes its builder onto [state] stack.
  static void _openBlock(List<_HistToken> tokens, _ParseState state) {
    final underMax = ++state.totalBlocks <= maxTdfBlocksPerDoc;
    state.check(underMax, TdfErrorKind.limitExceeded);
    final blockType = tokens.first.value;
    final arguments = tokens.sublist(1, tokens.length - 1);
    if (state.stack.isEmpty) {
      final isRoot = blockType == 'label' || blockType == 'task';
      state.check(isRoot, TdfErrorKind.unknownBlockType);
      state.check(arguments.isNotEmpty, TdfErrorKind.invalidBlockHeader);
      final id = arguments.first.value;
      final validId =
          arguments.first.kind == _HistTokenKind.bareWord &&
          _isValidEntityId(id);
      state.check(validId, TdfErrorKind.invalidIdentifier);
      final isLabel = blockType == 'label';
      final validHeader = isLabel
          ? arguments.length == 1
          : arguments.length <= 2 &&
                (arguments.length == 1 || arguments[1].value == 'priority');
      state.check(validHeader, TdfErrorKind.invalidBlockHeader);
      final isUnique = isLabel
          ? state.seenLabels.add(id)
          : !state.taskById.containsKey(id);
      state.check(isUnique, TdfErrorKind.duplicateIdentifier);
      final isPrio = arguments.length == 2;
      state.stack.add(_HistoricalTaskBuilder(id, isPrio, state.line, isLabel));
      return;
    }
    final parent = state.stack.last;
    if (blockType == 'condition' && parent is _HistoricalTaskBuilder) {
      state.check(arguments.isEmpty, TdfErrorKind.invalidBlockHeader);
      state.stack.add(_HistoricalCondBlockBuilder(parent));
    } else if (blockType == 'subtasks' &&
        parent is _HistoricalTaskBuilder &&
        !parent.isLabel) {
      final validSubtasks =
          arguments.isEmpty ||
          (arguments.length == 1 && arguments.first.value == 'auto-finish');
      state.check(validSubtasks, TdfErrorKind.invalidBlockHeader);
      state.stack.add(_HistoricalSubtasksBuilder(arguments.length == 1));
    } else {
      state.fail(TdfErrorKind.unknownBlockType);
    }
  }

  /// Parses a timestamp from [state] arguments.
  static DateTime _parseTimestamp(_ParseState state) {
    final arguments = state.arguments;
    final validArgs =
        arguments.isNotEmpty &&
        arguments.length <= 2 &&
        arguments[0].kind == _HistTokenKind.bareWord &&
        (arguments.length == 1 || arguments[1].kind == _HistTokenKind.bareWord);
    state.check(validArgs, TdfErrorKind.invalidTimestamp);
    final parsed = TaskItem.tryParseTdfTimestamp(
      arguments[0].value,
      arguments.length == 2 ? arguments[1].value : null,
    );
    return parsed ?? state.fail(TdfErrorKind.invalidTimestamp);
  }

  /// Processes a single tokenized statement line.
  static void _processTokens(List<_HistToken> tokens, _ParseState state) {
    if (tokens.first.kind == _HistTokenKind.closeBrace) {
      return _closeBlock(tokens, state);
    }
    if (tokens.last.kind == _HistTokenKind.openBrace) {
      return _openBlock(tokens, state);
    }
    state.check(state.stack.isNotEmpty, TdfErrorKind.unexpectedRootDirective);
    state.check(tokens.length >= 2, TdfErrorKind.missingDirectiveArgument);
    final directive = state.directive = tokens.first.value;
    final arguments = state.arguments = tokens.sublist(1);
    final active = state.stack.last;
    if (active is _HistoricalTaskBuilder) {
      _applyEntityDirective(active, state);
    } else if (active is _HistoricalSubtasksBuilder) {
      final kind = directive != 'step'
          ? TdfErrorKind.unknownDirective
          : TdfErrorKind.unexpectedToken;
      state.check(directive == 'step' && arguments.length == 2, kind);
      final title = arguments[1].value, done = arguments[0].value == 'true';
      active.steps.add(SubtaskItem(title: title, isCompleted: done));
    } else if (active is _HistoricalCondBlockBuilder) {
      _addCondition(active.parent, state);
      active.hasRules = true;
    }
  }

  /// Scans a double-quoted string token starting at [quoteIndex].
  static int _scanDoubleQuoted(int quoteIndex, _ParseState state) {
    final source = state.source;
    final lineEnd = state.lineEnd;
    final buffer = StringBuffer();
    var cursor = quoteIndex + 1;
    while (cursor < lineEnd) {
      final unit = source.codeUnitAt(cursor);
      if (unit == 0x22) {
        final text = buffer.toString();
        state.tokens.add(_HistToken(text, _HistTokenKind.quotedString));
        return cursor + 1;
      }
      if (unit == 0x5C && cursor + 1 < lineEnd) {
        final escaped = source.codeUnitAt(cursor + 1);
        final decoded =
            const {
              0x22: 0x22,
              0x5C: 0x5C,
              0x6E: 0x0A,
              0x72: 0x0D,
              0x74: 0x09,
            }[escaped] ??
            state.fail(TdfErrorKind.invalidEscapeSequence);
        buffer.writeCharCode(decoded);
        cursor += 2;
      } else {
        buffer.writeCharCode(unit);
        cursor++;
      }
    }
    state.fail(TdfErrorKind.unterminatedString);
  }

  /// Scans a single token starting at [cursor] and returns the next offset.
  static int _scanNextToken(int cursor, _ParseState state) {
    final source = state.source;
    final lineEnd = state.lineEnd;
    final unit = source.codeUnitAt(cursor);
    if (unit <= 0x20) {
      return cursor + 1;
    }
    if (unit == 0x23) {
      return lineEnd;
    }
    if (unit == 0x7B || unit == 0x7D) {
      final brace = unit == 0x7B ? _HistToken.openBrace : _HistToken.closeBrace;
      state.tokens.add(brace);
      return cursor + 1;
    }
    if (unit == 0x22) {
      return _scanDoubleQuoted(cursor, state);
    }
    if (unit == 0x27) {
      final end = source.indexOf("'", cursor + 1);
      final validQuote = end > cursor && end < lineEnd;
      state.check(validQuote, TdfErrorKind.unterminatedString);
      final text = source.substring(cursor + 1, end);
      state.tokens.add(_HistToken(text, _HistTokenKind.quotedString));
      return end + 1;
    }
    var end = cursor;
    while (end < lineEnd) {
      final charUnit = source.codeUnitAt(end);
      if (charUnit <= 0x20 || charUnit == 0x23) {
        break;
      }
      state.check(charUnit != 0x7B, TdfErrorKind.invalidBlockHeader);
      end++;
    }
    final word = source.substring(cursor, end);
    state.tokens.add(_HistToken(word, _HistTokenKind.bareWord));
    return end;
  }

  /// Scans tokens on the next historical line in [state].
  static List<_HistToken> _scanTokens(_ParseState state) {
    var cursor = state.offset;
    final end = state.lineEnd = _findLineEnd(state);
    state.tokens = <_HistToken>[];
    while (cursor < end) {
      cursor = _scanNextToken(cursor, state);
    }
    return state.tokens;
  }
}

/// Immutable representation of a historical `task` or `task!` block.
@immutable
class TdfHistoricalTask extends TdfHistoricalLabel {
  /// Creates a [TdfHistoricalTask] from a validated builder.
  TdfHistoricalTask._(super._builder, [super.id])
    : blockedByTaskIds = List.unmodifiable(_builder.blockedByTaskIds),
      completedAt = _builder.dates['finished'],
      createdAt = _builder.dates['created'] ?? DateTime.utc(1970),
      isPriority = _builder.isPriority,
      labelIds = List.unmodifiable(_builder.labelIds),
      links = List.unmodifiable(_builder.links),
      queuedAt = _builder.dates['queued'],
      repeatRule = _builder.repeatRule,
      subtasks = List.unmodifiable(_builder.subtasks),
      subtasksAutoFinish = _builder.subtasksAutoFinish,
      suspendedAt = _builder.dates['suspended'],
      super._();

  final List<String> blockedByTaskIds, labelIds;
  final DateTime? completedAt, queuedAt, suspendedAt;
  final DateTime createdAt;
  final bool isPriority, subtasksAutoFinish;
  final List<TaskLink> links;
  final TaskRepeatRule? repeatRule;
  final List<SubtaskItem> subtasks;

  /// Returns a copy of this historical task with updated fields.
  TdfHistoricalTask copyWith({
    String? id,
    List<String>? labels,
    List<String>? blockers,
    List<DateTime?>? dates,
  }) => TdfHistoricalTask._(
    _builder
      ..dates['created'] = dates != null ? dates[0] : createdAt
      ..dates['queued'] = dates != null ? dates[1] : queuedAt
      ..dates['finished'] = dates != null ? dates[2] : completedAt
      ..labelIds = labels ?? labelIds
      ..blockedByTaskIds = blockers ?? blockedByTaskIds,
    id ?? this.id,
  );
}

/// A single lexical token from a historical TDF line.
@immutable
class _HistToken {
  /// Creates a [_HistToken].
  const _HistToken(this.value, this.kind);

  static const _HistToken closeBrace = _HistToken(
    '}',
    _HistTokenKind.closeBrace,
  );
  static const _HistToken openBrace = _HistToken('{', _HistTokenKind.openBrace);

  final _HistTokenKind kind;
  final String value;
}

/// Token kinds emitted while scanning historical TDF lines.
enum _HistTokenKind { bareWord, closeBrace, openBrace, quotedString }

/// Mutable builder for a historical `condition { ... }` nested block.
class _HistoricalCondBlockBuilder {
  /// Creates a [_HistoricalCondBlockBuilder] attached to [parent].
  _HistoricalCondBlockBuilder(this.parent);

  final _HistoricalTaskBuilder parent;
  bool hasRules = false;
}

/// Mutable builder for a historical `subtasks { ... }` nested block.
class _HistoricalSubtasksBuilder {
  /// Creates a [_HistoricalSubtasksBuilder].
  _HistoricalSubtasksBuilder(this.autoFinish);

  final bool autoFinish;
  final List<SubtaskItem> steps = <SubtaskItem>[];
}

/// Mutable builder for a historical `label`, `task`, or `task!` block.
class _HistoricalTaskBuilder {
  /// Creates a [_HistoricalTaskBuilder].
  _HistoricalTaskBuilder(this.id, this.isPriority, int headerLine, this.isLabel)
    : lines = <String, int>{'header': headerLine};

  final List<int> conditionLines = <int>[];
  final List<TaskCondition> conditions = <TaskCondition>[];
  final Map<String, DateTime?> dates = <String, DateTime?>{};
  final String id;
  final bool isLabel;
  final Map<String, int> lines;
  final List<TaskLink> links = <TaskLink>[];
  final Map<String, String> texts = <String, String>{};
  List<String> blockedByTaskIds = <String>[], labelIds = <String>[];
  bool isPriority, subtasksAutoFinish = false;
  TaskRepeatRule? repeatRule;
  List<SubtaskItem> subtasks = const <SubtaskItem>[];
}

/// Mutable state and version context for a single historical parse pass.
class _ParseState {
  /// Creates a [_ParseState].
  _ParseState(this.source, [this.sourceVersion, this.targetVersion])
    : allow030 = sourceVersion == '0.3.0' || sourceVersion == '0.4.0',
      allow040 = sourceVersion == '0.4.0';

  final bool allow030, allow040;
  final List<TdfHistoricalLabel> labels = <TdfHistoricalLabel>[];
  final Set<String> seenLabels = <String>{};
  final String source;
  final String? sourceVersion, targetVersion;
  final List<Object> stack = <Object>[];
  final Map<String, TdfHistoricalTask> taskById = <String, TdfHistoricalTask>{};
  final Map<String, int> visitState = <String, int>{};
  List<_HistToken> arguments = const <_HistToken>[], tokens = <_HistToken>[];
  String directive = '';
  int line = 0, lineEnd = 0, offset = 0, totalBlocks = 0;

  /// Throws a [TdfException] with [kind] when [condition] is `false`.
  void check(bool condition, TdfErrorKind kind, [int? atLine]) =>
      condition ? null : fail(kind, atLine);

  /// Throws a [TdfException] scoped to this parse state.
  Never fail(TdfErrorKind kind, [int? atLine]) => throw TdfException(
    kind: kind,
    line: atLine ?? line,
    sourceVersion: sourceVersion,
    targetVersion: targetVersion,
    message: kind.name,
  );
}
