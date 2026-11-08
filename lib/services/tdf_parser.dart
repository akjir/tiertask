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
import 'tdf_directive_parser.dart';
import 'tdf_scanner.dart';

/// Base class for open block builders on the single-pass parser stack.
sealed class TdfBlockBuilder {
  int statementCount = 0;
}

/// Stateless structural block parser and semantic validator for `TDF_SPEC.md` Sections 3–8.
@immutable
class TdfBlockParser {
  /// Private constructor to prevent instantiation.
  const TdfBlockParser._();

  /// Legacy TDF specification version string (`tdf 0.5.0`) converted in memory at load time per Section 10.6.
  static const String legacySupportedVersion = '0.5.0';

  /// Canonical TDF specification version string (`tdf 0.5.1`).
  static const String supportedVersion = '0.5.1';

  /// Closes the currently active block on [state] and validates required directives.
  static void closeCurrentBlock(TdfParserState state, int line) {
    final hasOpen = state.blockStack.isNotEmpty;
    _check(hasOpen, TdfErrorKind.unexpectedClosingBrace, line);
    switch (state.blockStack.removeLast()) {
      case final TdfConditionBlockBuilder block:
        _check(block.hasAnyRule, TdfErrorKind.missingRequiredDirective, line);
      case final TdfDeletedBlockBuilder block:
        state.deletedBlock = block.build(line);
      case final TdfLabelBuilder block:
        state.labels.add(block.build(line));
      case final TdfQueueBlockBuilder block:
        state.queueBlock = block.build(line);
        state.queueEntries.addAll(block.entries);
        state.queueTaskIds.addAll(block.seenTaskIds);
      case final TdfSubtasksBuilder block:
        final hasSteps = block.steps.isNotEmpty;
        _check(hasSteps, TdfErrorKind.missingRequiredDirective, line);
        if (state.blockStack.lastOrNull case final TdfTaskBuilder parent) {
          parent.subtasksAutoFinish = block.autoFinish;
          parent.subtasks = block.steps;
        }
      case final TdfTaskBuilder block:
        state.taskEntries.add(block.build(line));
    }
  }

  /// Scans, parses, and validates a `tdf 0.5.1` (or legacy `tdf 0.5.0`) [tdfContent] string into an evaluated [TaskBoard].
  static TaskBoard parseDocument(
    String tdfContent, {
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
    bool pruneExpiredCompleted = false,
  }) {
    validateByteLimit(tdfContent);
    final state = TdfParserState();
    var offset = 0;
    var line = 0;
    while (offset < tdfContent.length) {
      line++;
      _check(line <= maxTdfLineCount, TdfErrorKind.limitExceeded, line);
      final span = TdfScanner.findLineSpan(tdfContent, offset, line);
      processLogicalLine(tdfContent, span.lineStart, span.lineEnd, line, state);
      offset = span.nextOffset;
    }
    _check(state.hasSeenFirstStatement, TdfErrorKind.missingVersionHeader, 1);
    final closed = state.blockStack.isEmpty;
    _check(closed, TdfErrorKind.unclosedBlock, line == 0 ? 1 : line);
    _validateLabelReferences(state);
    _validateDependencyCycles(state.taskEntries);
    _validateQueueMembership(state);
    return TaskBoard.evaluate(
      tasks: <TaskItem>[for (final entry in state.taskEntries) entry.task],
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

  /// Tokenizes and executes a single logical line `[lineStart, lineEnd)`.
  static void processLogicalLine(
    String source,
    int lineStart,
    int lineEnd,
    int line,
    TdfParserState state,
  ) {
    final tokens = TdfScanner.scanLineTokens(source, lineStart, lineEnd, line);
    if (tokens.isEmpty) {
      return;
    }
    if (!state.hasSeenFirstStatement) {
      _processInitialStatement(state, tokens, line);
      return;
    }
    if (tokens[0].kind == TdfTokenKind.closeBrace) {
      _check(tokens.length == 1, TdfErrorKind.unexpectedToken, line);
      closeCurrentBlock(state, line);
      return;
    }
    final first = tokens[0];
    final validId = first.isBare && TdfScanner.isValidIdentifier(first.value);
    _check(validId, TdfErrorKind.invalidIdentifier, line);
    const openKind = TdfTokenKind.openBrace;
    const closeKind = TdfTokenKind.closeBrace;
    final openIndex = TdfScanner.findTokenKindIndex(tokens, openKind);
    if (openIndex != -1) {
      _processBlockHeaderLine(state, tokens, openIndex, line);
      return;
    }
    final closeIndex = TdfScanner.findTokenKindIndex(tokens, closeKind);
    _check(closeIndex == -1, TdfErrorKind.unexpectedToken, line);
    _processDirectiveLine(state, tokens, line);
  }

  /// Validates that [tdfContent] does not exceed [maxTdfFileBytes].
  static void validateByteLimit(String tdfContent) {
    final withinLimit =
        tdfContent.length <= maxTdfFileBytes &&
        utf8.encode(tdfContent).length <= maxTdfFileBytes;
    _check(withinLimit, TdfErrorKind.limitExceeded, 1);
  }

  /// Checks whether [taskId] participates in a dependency cycle using 3-color DFS.
  static void _checkTaskCycle(
    String taskId,
    Map<String, TdfParsedTaskEntry> taskById,
    Map<String, int> visitState,
    int fallbackLine,
  ) {
    final currentState = visitState[taskId] ?? 0;
    if (currentState == 2) {
      return;
    }
    final entry = taskById[taskId];
    final line = entry != null && entry.blockedLine > 0
        ? entry.blockedLine
        : fallbackLine;
    _check(currentState != 1, TdfErrorKind.circularDependency, line);
    if (entry == null) {
      visitState[taskId] = 2;
      return;
    }
    visitState[taskId] = 1;
    for (final blockerId in entry.task.blockedByTaskIds) {
      _checkTaskCycle(blockerId, taskById, visitState, line);
    }
    visitState[taskId] = 2;
  }

  /// Compares two legacy `0.5.0` queued open task entries for Section 10.6 step 2 queue synthesis.
  static int _compareLegacy050QueueEntries(
    ({int index, DateTime queuedAt, bool isPriority, String id}) first,
    ({int index, DateTime queuedAt, bool isPriority, String id}) second,
  ) {
    if (first.isPriority != second.isPriority) {
      return first.isPriority ? -1 : 1;
    }
    final order = first.queuedAt.compareTo(second.queuedAt);
    return order != 0 ? order : first.index.compareTo(second.index);
  }

  /// Creates a nested block builder (`subtasks` inside `task`, or `condition` inside `task`/`label`).
  static TdfBlockBuilder _createNestedBlockBuilder(
    TdfBlockBuilder parent,
    String blockName,
    List<TdfScannedToken> headerArgs,
    int line,
  ) {
    if (blockName == 'condition') {
      final validParent = parent is TdfTaskBuilder || parent is TdfLabelBuilder;
      _check(validParent, TdfErrorKind.unknownBlockType, line);
      _check(headerArgs.isEmpty, TdfErrorKind.invalidBlockHeader, line);
      return TdfConditionBlockBuilder(parent, parent is TdfTaskBuilder);
    }
    if (parent is! TdfTaskBuilder || blockName != 'subtasks') {
      _fail(TdfErrorKind.unknownBlockType, line);
    }
    _check(!parent.hasSubtasksBlock, TdfErrorKind.duplicateDirective, line);
    _check(headerArgs.length <= 1, TdfErrorKind.invalidBlockHeader, line);
    var autoFinish = false;
    if (headerArgs.length == 1) {
      final validFlag =
          headerArgs[0].isBare && headerArgs[0].value == 'auto-finish';
      _check(validFlag, TdfErrorKind.invalidBlockHeader, line);
      autoFinish = true;
    }
    parent.hasSubtasksBlock = true;
    return TdfSubtasksBuilder(autoFinish);
  }

  /// Creates a root block builder (`deleted`, `queue`, `label`, or `task`).
  static TdfBlockBuilder _createRootBlockBuilder(
    TdfParserState state,
    String blockName,
    List<TdfScannedToken> headerArgs,
    int line,
  ) {
    if (blockName == 'deleted' || blockName == 'queue') {
      final isDeleted = blockName == 'deleted';
      final seen = isDeleted ? state.hasDeletedBlock : state.hasQueueBlock;
      _check(!seen, TdfErrorKind.duplicateDirective, line);
      _check(headerArgs.isEmpty, TdfErrorKind.invalidBlockHeader, line);
      if (isDeleted) {
        state.hasDeletedBlock = true;
        return TdfDeletedBlockBuilder(state);
      }
      state.hasQueueBlock = true;
      return TdfQueueBlockBuilder();
    }
    final isTask = blockName == 'task';
    _check(isTask || blockName == 'label', TdfErrorKind.unknownBlockType, line);
    final maxArgs = isTask ? 2 : 1;
    final okArity = headerArgs.isNotEmpty && headerArgs.length <= maxArgs;
    _check(okArity, TdfErrorKind.invalidBlockHeader, line);
    final id = TdfDirectiveParser.requireIdentifierArg(headerArgs[0], line);
    if (!isTask) {
      final isDuplicate =
          state.deletedLabelIds.contains(id) || !state.labelIds.add(id);
      _check(!isDuplicate, TdfErrorKind.duplicateIdentifier, line);
      return TdfLabelBuilder(id);
    }
    if (headerArgs.length == 2) {
      final okFlag = headerArgs[1].isBare && headerArgs[1].value == 'priority';
      _check(okFlag, TdfErrorKind.invalidBlockHeader, line);
    }
    final isDuplicate =
        state.deletedTaskIds.contains(id) || !state.taskIds.add(id);
    _check(!isDuplicate, TdfErrorKind.duplicateIdentifier, line);
    return TdfTaskBuilder(id, headerArgs.length == 2, line, state.isLegacy050);
  }

  /// Opens a new root or nested block on [state] after checking Section 7 bounds.
  static void _openBlock(
    TdfParserState state,
    String blockName,
    List<TdfScannedToken> headerArgs,
    int line,
  ) {
    final withinDepth = state.blockStack.length < maxTdfNestingDepth;
    _check(withinDepth, TdfErrorKind.limitExceeded, line);
    final withinBlocks = state.totalBlocks < maxTdfBlocksPerDoc;
    _check(withinBlocks, TdfErrorKind.limitExceeded, line);
    if (state.blockStack.isNotEmpty) {
      final parent = state.blockStack.last;
      final allowNested =
          parent is! TdfDeletedBlockBuilder && parent is! TdfQueueBlockBuilder;
      _check(allowNested, TdfErrorKind.unknownBlockType, line);
      final withinStmts = parent.statementCount < maxTdfStmtsPerBlock;
      _check(withinStmts, TdfErrorKind.limitExceeded, line);
      parent.statementCount++;
    }
    state.totalBlocks++;
    final builder = state.blockStack.isEmpty
        ? _createRootBlockBuilder(state, blockName, headerArgs, line)
        : _createNestedBlockBuilder(
            state.blockStack.last,
            blockName,
            headerArgs,
            line,
          );
    state.blockStack.add(builder);
  }

  /// Processes a line containing an opening brace `{` as a block header.
  static void _processBlockHeaderLine(
    TdfParserState state,
    List<TdfScannedToken> tokens,
    int openBraceIndex,
    int line,
  ) {
    final atEnd = openBraceIndex == tokens.length - 1;
    _check(atEnd, TdfErrorKind.unexpectedToken, line);
    final withinArgs = openBraceIndex - 1 <= maxTdfArgsPerStmt;
    _check(withinArgs, TdfErrorKind.limitExceeded, line);
    final headerArgs = tokens.sublist(1, openBraceIndex);
    for (final argument in headerArgs) {
      final notClose = argument.kind != TdfTokenKind.closeBrace;
      _check(notClose, TdfErrorKind.unexpectedToken, line);
    }
    _openBlock(state, tokens[0].value, headerArgs, line);
  }

  /// Processes a directive line inside the currently open block.
  static void _processDirectiveLine(
    TdfParserState state,
    List<TdfScannedToken> tokens,
    int line,
  ) {
    _check(tokens.length > 1, TdfErrorKind.missingDirectiveArgument, line);
    final inBlock = state.blockStack.isNotEmpty;
    _check(inBlock, TdfErrorKind.unexpectedRootDirective, line);
    final withinArgs = tokens.length - 1 <= maxTdfArgsPerStmt;
    _check(withinArgs, TdfErrorKind.limitExceeded, line);
    final active = state.blockStack.last;
    if (active is! TdfDeletedBlockBuilder && active is! TdfQueueBlockBuilder) {
      final withinStmts = active.statementCount < maxTdfStmtsPerBlock;
      _check(withinStmts, TdfErrorKind.limitExceeded, line);
    }
    active.statementCount++;
    final name = tokens[0].value;
    final args = tokens.sublist(1);
    switch (active) {
      case final TdfConditionBlockBuilder block:
        TdfDirectiveParser.applyConditionDirective(block, name, args, line);
      case final TdfDeletedBlockBuilder block:
        TdfDirectiveParser.applyDeletedDirective(block, name, args, line);
      case final TdfLabelBuilder block:
        TdfDirectiveParser.applyLabelDirective(block, name, args, line);
      case final TdfQueueBlockBuilder block:
        TdfDirectiveParser.applyQueueDirective(block, name, args, line);
      case final TdfSubtasksBuilder block:
        TdfDirectiveParser.applySubtasks(block.steps, name, args, line);
      case final TdfTaskBuilder block:
        TdfDirectiveParser.applyTaskDirective(block, name, args, line);
    }
  }

  /// Validates the first non-empty statement (`tdf 0.5.1` or legacy `tdf 0.5.0`) per Section 4.0 and Section 10.6.
  static void _processInitialStatement(
    TdfParserState state,
    List<TdfScannedToken> tokens,
    int line,
  ) {
    const openKind = TdfTokenKind.openBrace;
    const closeKind = TdfTokenKind.closeBrace;
    final first = tokens[0];
    if (first.isBare &&
        first.value == 'tdf' &&
        TdfScanner.findTokenKindIndex(tokens, openKind) == -1 &&
        TdfScanner.findTokenKindIndex(tokens, closeKind) == -1) {
      _check(tokens.length > 1, TdfErrorKind.missingVersionHeader, line);
      if (tokens.length != 2 ||
          !tokens[1].isBare ||
          (tokens[1].value != supportedVersion &&
              tokens[1].value != legacySupportedVersion)) {
        final found = tokens[1].value;
        throw TdfException(
          kind: TdfErrorKind.unsupportedVersion,
          line: line,
          message: 'Unsupported TDF version "$found".',
          sourceVersion: found,
          targetVersion: supportedVersion,
        );
      }
      state.isLegacy050 = tokens[1].value == legacySupportedVersion;
      state.hasSeenFirstStatement = true;
      return;
    }
    _fail(TdfErrorKind.missingVersionHeader, line);
  }

  /// Synthesizes the root `queue` block from legacy `0.5.0` queued open tasks when omitted per Section 10.6 step 2.
  static TdfQueueBlock _synthesizeLegacy050Queue(
    List<TdfParsedTaskEntry> entries,
  ) {
    final scheduledOpen =
        <({int index, DateTime queuedAt, bool isPriority, String id})>[];
    DateTime? latestModified;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final task = entry.task;
      final queuedAt = entry.legacyQueuedAt;
      if (queuedAt != null && !task.isCompleted && task.completedAt == null) {
        scheduledOpen.add((
          index: i,
          queuedAt: queuedAt,
          isPriority: task.isPriority,
          id: task.id,
        ));
        final effectiveModifiedAt = task.effectiveModifiedAt;
        if (latestModified == null ||
            effectiveModifiedAt.isAfter(latestModified)) {
          latestModified = effectiveModifiedAt;
        }
      }
    }
    scheduledOpen.sort(_compareLegacy050QueueEntries);
    return TdfQueueBlock(
      modifiedAt: latestModified ?? TdfQueueBlock.epochModifiedAt,
      taskIds: <String>[for (final item in scheduledOpen) item.id],
    );
  }

  /// Validates that the `blocked` task dependency graph is acyclic across [entries].
  static void _validateDependencyCycles(List<TdfParsedTaskEntry> entries) {
    final taskById = <String, TdfParsedTaskEntry>{
      for (final entry in entries) entry.task.id: entry,
    };
    final visitState = <String, int>{};
    for (final entry in entries) {
      if (entry.task.blockedByTaskIds.isNotEmpty) {
        _checkTaskCycle(entry.task.id, taskById, visitState, entry.blockedLine);
      }
    }
  }

  /// Validates canonical `labels` references across all parsed tasks.
  static void _validateLabelReferences(TdfParserState state) {
    for (final entry in state.taskEntries) {
      final allExist = entry.task.labelIds.every(state.labelIds.contains);
      _check(allExist, TdfErrorKind.unknownLabelReference, entry.labelsLine);
    }
  }

  /// Validates `queue` entries per Section 4.5 (or converts legacy `0.5.0` queue membership per Section 10.6).
  static void _validateQueueMembership(TdfParserState state) {
    if (state.isLegacy050 && !state.hasQueueBlock) {
      state.queueBlock = _synthesizeLegacy050Queue(state.taskEntries);
      AppLogger.info(LogTag.tdf, 'Synthesized TDF 0.5.1 queue from 0.5.0.');
      return;
    }
    final allowedIds = <String>{
      for (final entry in state.taskEntries)
        if (!entry.task.isCompleted &&
            entry.task.completedAt == null &&
            (!state.isLegacy050 || entry.legacyQueuedAt != null))
          entry.task.id,
    };
    for (final queueItem in state.queueEntries) {
      final valid = allowedIds.contains(queueItem.taskId);
      _check(valid, TdfErrorKind.invalidQueueMembership, queueItem.line);
    }
    if (state.isLegacy050) {
      for (final entry in state.taskEntries) {
        final ok =
            !allowedIds.contains(entry.task.id) ||
            state.queueTaskIds.contains(entry.task.id);
        _check(ok, TdfErrorKind.invalidQueueMembership, entry.headerLine);
      }
    }
  }
}

/// Mutable builder for a `condition { ... }` sub-block during single-pass parsing.
final class TdfConditionBlockBuilder extends TdfBlockBuilder
    with TdfConditionDirectiveFields {
  /// Creates a [TdfConditionBlockBuilder].
  TdfConditionBlockBuilder(TdfBlockBuilder parent, bool allowResets) {
    parentBuilder = parent;
    this.allowResets = allowResets;
  }
}

/// Mutable builder for the root `deleted` block during single-pass parsing.
final class TdfDeletedBlockBuilder extends TdfBlockBuilder
    with TdfDeletedDirectiveFields {
  /// Creates a [TdfDeletedBlockBuilder].
  TdfDeletedBlockBuilder(TdfEntityIdRegistry registry) {
    idRegistry = registry;
  }

  /// Validates required `generation` directive and builds a [TdfDeletedBlock].
  TdfDeletedBlock build(int line) => TdfDeletedBlock(
    generation:
        generation ?? _fail(TdfErrorKind.missingRequiredDirective, line),
    tasks: tasks,
    labels: labels,
  );
}

/// Mutable builder for a `label` block during single-pass parsing.
final class TdfLabelBuilder extends TdfBlockBuilder
    with TdfLabelDirectiveFields {
  /// Creates a [TdfLabelBuilder] for [id].
  TdfLabelBuilder(this.id);

  final String id;

  /// Validates required directives and builds an immutable [TdfLabel].
  TdfLabel build(int line) => TdfLabel(
    id: id,
    name: name ?? _fail(TdfErrorKind.missingRequiredDirective, line),
    color: color,
    note: note,
    modifiedAt: modifiedAt,
    conditions: List<TaskCondition>.unmodifiable(conditions),
  );
}

/// Pairs a built [TaskItem] with source line numbers for post-parse validation.
typedef TdfParsedTaskEntry = ({
  TaskItem task,
  int headerLine,
  int labelsLine,
  int blockedLine,
  DateTime? legacyQueuedAt,
});

/// Accumulates root blocks, identifier sets, and the active nesting stack during parsing.
class TdfParserState with TdfEntityIdRegistry {
  final List<TdfBlockBuilder> blockStack = <TdfBlockBuilder>[];
  final List<TdfLabel> labels = <TdfLabel>[];
  final List<({String taskId, int line})> queueEntries =
      <({String taskId, int line})>[];
  final Set<String> queueTaskIds = <String>{};
  final List<TdfParsedTaskEntry> taskEntries = <TdfParsedTaskEntry>[];
  TdfDeletedBlock deletedBlock = TdfDeletedBlock.empty;
  bool hasDeletedBlock = false;
  bool hasQueueBlock = false;
  bool hasSeenFirstStatement = false;
  bool isLegacy050 = false;
  TdfQueueBlock queueBlock = TdfQueueBlock.empty;
  int totalBlocks = 0;
}

/// Mutable builder for the root `queue` block during single-pass parsing.
final class TdfQueueBlockBuilder extends TdfBlockBuilder
    with TdfQueueDirectiveFields {
  /// Validates required `modified` directive and builds a [TdfQueueBlock].
  TdfQueueBlock build(int line) => TdfQueueBlock(
    modifiedAt:
        modifiedAt ?? _fail(TdfErrorKind.missingRequiredDirective, line),
    taskIds: <String>[for (final entry in entries) entry.taskId],
  );
}

/// Mutable builder for a `subtasks` sub-block during single-pass parsing.
final class TdfSubtasksBuilder extends TdfBlockBuilder {
  /// Creates a [TdfSubtasksBuilder].
  TdfSubtasksBuilder(this.autoFinish);

  final bool autoFinish;
  final List<SubtaskItem> steps = <SubtaskItem>[];
}

/// Mutable builder for a `task` block during single-pass parsing.
final class TdfTaskBuilder extends TdfBlockBuilder with TdfTaskDirectiveFields {
  /// Creates a [TdfTaskBuilder] for [id], [isPriority], and [headerLine].
  TdfTaskBuilder(this.id, this.isPriority, this.headerLine, bool isLegacy050) {
    this.isLegacy050 = isLegacy050;
  }

  final int headerLine;
  final String id;
  final bool isPriority;

  /// Validates required directives (`name`, `created`, and completion state) and builds a [TdfParsedTaskEntry].
  TdfParsedTaskEntry build(int line) {
    final resolvedName =
        name ?? _fail(TdfErrorKind.missingRequiredDirective, line);
    final resolvedCreated =
        createdAt ?? _fail(TdfErrorKind.missingRequiredDirective, line);
    final effectiveCompletions = completions ?? 0;
    if (completedAt != null && effectiveCompletions <= 0) {
      final errorLine = completionsLine > 0
          ? completionsLine
          : (finishedLine > 0 ? finishedLine : line);
      _fail(TdfErrorKind.invalidCompletionState, errorLine);
    }
    final canonical = canonicalLabelIds ?? const <String>[];
    var resolvedModified = modifiedAt;
    final queuedAt = isLegacy050 && resolvedModified == null
        ? legacyQueuedAt
        : null;
    if (queuedAt != null &&
        queuedAt.isAfter(completedAt ?? resolvedCreated) &&
        queuedAt.isAfter(resolvedCreated)) {
      resolvedModified = queuedAt;
    }
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
      labelIds: canonical.toSet().toList(),
      dependencies: dependencies ?? const <TdfTaskDependency>[],
      links: links,
      conditions: conditions,
      subtasksAutoFinish: subtasksAutoFinish,
      subtasks: subtasks,
    );
    return (
      task: task,
      headerLine: headerLine,
      labelsLine: labelsLine,
      blockedLine: blockedLine,
      legacyQueuedAt: legacyQueuedAt,
    );
  }
}

/// Throws a [TdfException] with [kind] and 1-based [line] when [ok] is `false`.
void _check(bool ok, TdfErrorKind kind, int line) {
  if (!ok) {
    _fail(kind, line);
  }
}

/// Throws a [TdfException] with [kind] and 1-based [line].
Never _fail(TdfErrorKind kind, int line) =>
    TdfScanner.fail(kind, line, 'Invalid TDF (${kind.name}) at line $line.');
