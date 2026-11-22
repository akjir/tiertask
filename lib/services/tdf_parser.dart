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
import '../models/task_board_evaluator.dart';
import '../models/task_item.dart';
import '../models/tdf_error.dart';
import '../models/tdf_location.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_sync_metadata.dart';
import '../models/tdf_timezone.dart';
import 'tdf_directive_parser.dart';
import 'tdf_scanner.dart';

/// Base sealed class for active `{ ... }` block builders on the parser stack.
sealed class TdfBlockBuilder {
  /// Creates a [TdfBlockBuilder].
  TdfBlockBuilder();

  /// Number of direct child statements seen inside this block (`0..maxTdfStmtsPerBlock`).
  int statementCount = 0;
}

/// Active `condition { ... }` sub-block builder inside a `label` or `task` block.
final class TdfConditionBuilder extends TdfBlockBuilder {
  /// Creates a [TdfConditionBuilder] opened at [headerLine].
  TdfConditionBuilder(this.headerLine);

  /// 1-based line number of the opening `condition {` statement.
  final int headerLine;

  /// Number of condition rule statements inside this sub-block.
  int ruleCount = 0;
}

/// Active root-level `deleted { ... }` block builder.
final class TdfDeletedBuilder extends TdfBlockBuilder {
  /// Creates a [TdfDeletedBuilder] opened at [headerLine].
  TdfDeletedBuilder(this.headerLine);

  /// Accumulated `deleted` directives.
  final TdfDeletedDirectiveFields fields = TdfDeletedDirectiveFields();

  /// 1-based line number of the opening `deleted {` statement.
  final int headerLine;
}

/// Active root-level `label <id> [scoped] { ... }` block builder.
final class TdfLabelBuilder extends TdfBlockBuilder {
  /// Creates a [TdfLabelBuilder] for [id] and [isScoped] opened at [headerLine].
  TdfLabelBuilder(this.id, this.isScoped, this.headerLine);

  /// Accumulated `label` directives and conditions.
  final TdfLabelDirectiveFields fields = TdfLabelDirectiveFields();

  /// 1-based line number of the opening `label` block header.
  final int headerLine;

  /// Canonical 10-character Base62 `<label-id>`.
  final String id;

  /// Whether the `scoped` header flag was present (`TDF-ENT-003`).
  final bool isScoped;
}

/// Active root-level `location <id> { ... }` block builder (`TDF-ENT-004`).
final class TdfLocationBuilder extends TdfBlockBuilder {
  /// Creates a [TdfLocationBuilder] for [id] opened at [headerLine].
  TdfLocationBuilder(this.id, this.headerLine);

  /// Accumulated `location` directives.
  final TdfLocationDirectiveFields fields = TdfLocationDirectiveFields();

  /// 1-based line number of the opening `location` block header.
  final int headerLine;

  /// Canonical 10-character Base62 `<location-id>`.
  final String id;
}

/// Mutable document-wide state accumulated by [TdfBlockParser].
class TdfParserState {
  /// Creates an empty [TdfParserState].
  TdfParserState();

  /// Active nesting stack of open `{ ... }` blocks.
  final List<TdfBlockBuilder> blockStack = <TdfBlockBuilder>[];

  /// Parsed root-level `deleted` block (defaults to [TdfDeletedBlock.empty]).
  TdfDeletedBlock deletedBlock = TdfDeletedBlock.empty;

  /// Deleted `<label-id>` values from `deleted`.
  final Set<String> deletedLabelIds = <String>{};

  /// Deleted `<location-id>` values from `deleted`.
  final Set<String> deletedLocationIds = <String>{};

  /// Deleted `<task-id>` values from `deleted`.
  final Set<String> deletedTaskIds = <String>{};

  /// Whether a `deleted` block has already been seen.
  bool hasDeletedBlock = false;

  /// Whether a `queue` block has already been seen.
  bool hasQueueBlock = false;

  /// Whether the mandatory initial `tdf 0.8.0` version header has been seen.
  bool hasSeenVersionHeader = false;

  /// Live `<label-id>` values declared in the document.
  final Set<String> labelIds = <String>{};

  /// Referenced `<label-id>` values across all tasks with their 1-based line numbers.
  final List<({String labelId, int line})> labelReferences =
      <({String labelId, int line})>[];

  /// Parsed `label` definitions.
  final List<TdfLabel> labels = <TdfLabel>[];

  /// Live `<location-id>` values declared in the document.
  final Set<String> locationIds = <String>{};

  /// Referenced `<location-id>` values across all labels and tasks with their 1-based line numbers.
  final List<({String locationId, int line})> locationReferences =
      <({String locationId, int line})>[];

  /// Parsed `location` definitions.
  final List<TdfLocation> locations = <TdfLocation>[];

  /// Parsed root-level `queue` block (defaults to [TdfQueueBlock.empty]).
  TdfQueueBlock queueBlock = TdfQueueBlock.empty;

  /// Ordered `<task-id>` entries from `queue` with their 1-based line numbers.
  final List<({String taskId, int line})> queueEntries =
      <({String taskId, int line})>[];

  /// Live `<task-id>` values declared in the document.
  final Set<String> taskIds = <String>{};

  /// Parsed tasks together with their declaration and `blocked` line numbers.
  final List<({TaskItem task, int headerLine, int blockedLine})> tasksWithMeta =
      <({TaskItem task, int headerLine, int blockedLine})>[];

  /// Total blocks opened across the entire document (`0..maxTdfBlocksPerDoc`).
  int totalBlockCount = 0;
}

/// Active root-level `queue { ... }` block builder.
final class TdfQueueBuilder extends TdfBlockBuilder {
  /// Creates a [TdfQueueBuilder] opened at [headerLine].
  TdfQueueBuilder(this.headerLine);

  /// Accumulated `queue` directives.
  final TdfQueueDirectiveFields fields = TdfQueueDirectiveFields();

  /// 1-based line number of the opening `queue {` statement.
  final int headerLine;
}

/// Active `subtasks [auto-finish] { ... }` sub-block builder inside a `task` block.
final class TdfSubtasksBuilder extends TdfBlockBuilder {
  /// Creates a [TdfSubtasksBuilder] with [autoFinish].
  TdfSubtasksBuilder(this.autoFinish);

  /// Whether `auto-finish` was specified on the `subtasks` header.
  final bool autoFinish;

  /// Ordered checklist steps inside this sub-block.
  final List<SubtaskItem> steps = <SubtaskItem>[];
}

/// Active root-level `task <id> [priority] { ... }` block builder.
final class TdfTaskBuilder extends TdfBlockBuilder {
  /// Creates a [TdfTaskBuilder] for [id] and [isPriority] opened at [headerLine].
  TdfTaskBuilder(this.id, this.isPriority, this.headerLine);

  /// Whether `auto-finish` was set on the task's `subtasks` block.
  bool autoFinishSubtasks = false;

  /// Accumulated `task` directives and conditions.
  final TdfTaskDirectiveFields fields = TdfTaskDirectiveFields();

  /// Whether a `subtasks` sub-block has already been seen.
  bool hasSubtasksBlock = false;

  /// 1-based line number of the opening `task` block header.
  final int headerLine;

  /// Canonical 10-character Base62 `<task-id>`.
  final String id;

  /// Whether `priority` was specified on the `task` header.
  final bool isPriority;

  /// Checklist steps populated when `subtasks` closes.
  final List<SubtaskItem> subtasks = <SubtaskItem>[];
}

/// Structural and cross-entity parser for `spec/TDF_SPEC_0.8.0.md` Sections 1–6.
abstract final class TdfBlockParser {
  /// Sole normative TDF specification version supported by this parser (`0.8.0`).
  static const String supportedVersion = tdfSupportedVersion;

  /// Closes the innermost open block on [state.blockStack] at [line].
  static void closeCurrentBlock(TdfParserState state, int line) {
    if (state.blockStack.isEmpty) {
      TdfDirectiveParser.fail(
        TdfErrorKind.unexpectedClosingBrace,
        line,
        'Unexpected "}" at root depth 0.',
      );
    }
    final current = state.blockStack.removeLast();
    switch (current) {
      case TdfDeletedBuilder():
        _closeDeletedBuilder(state, current, line);
      case TdfQueueBuilder():
        _closeQueueBuilder(state, current, line);
      case TdfLabelBuilder():
        _closeLabelBuilder(state, current);
      case TdfLocationBuilder():
        _closeLocationBuilder(state, current);
      case TdfTaskBuilder():
        _closeTaskBuilder(state, current);
      case TdfSubtasksBuilder():
        _closeSubtasksBuilder(state, current, line);
      case TdfConditionBuilder():
        if (current.ruleCount == 0) {
          TdfDirectiveParser.fail(
            TdfErrorKind.missingRequiredDirective,
            line,
            'Condition block must contain at least one condition rule.',
          );
        }
    }
  }

  /// Parses a complete `tdf 0.8.0` document [content] and optionally evaluates all 6 tiers at [evaluationTime].
  static TaskBoard parseDocument(
    String content, {
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
    bool pruneExpiredCompleted = false,
    bool byteLengthVerified = false,
    bool evaluateTiers = true,
  }) {
    final state = _scanAndValidateState(
      content,
      byteLengthVerified: byteLengthVerified,
    );
    final tasks = <TaskItem>[for (final item in state.tasksWithMeta) item.task];
    if (!evaluateTiers) {
      return TaskBoard.unevaluated(
        tasks: tasks,
        labels: state.labels,
        locations: state.locations,
        deletedBlock: state.deletedBlock,
        queueBlock: state.queueBlock,
      );
    }
    return TaskBoard.evaluate(
      tasks: tasks,
      labels: state.labels,
      locations: state.locations,
      deletedBlock: state.deletedBlock,
      queueBlock: state.queueBlock,
      evaluationTime: evaluationTime,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      activeLabelId: activeLabelId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
      pruneExpiredCompleted: pruneExpiredCompleted,
    );
  }

  /// Processes a single non-empty logical line's [tokens] at 1-based [line] (`TDF-VAL-001`).
  static void processLineTokens(
    TdfParserState state,
    int line,
    List<TdfScannedToken> tokens,
  ) {
    if (tokens.length == 1 && tokens[0].kind == TdfTokenKind.closeBrace) {
      closeCurrentBlock(state, line);
      return;
    }
    if (tokens.any((token) => token.kind == TdfTokenKind.closeBrace)) {
      TdfDirectiveParser.fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Closing brace "}" must stand alone on its line.',
      );
    }
    var openBraceCount = 0;
    for (final token in tokens) {
      if (token.kind == TdfTokenKind.openBrace) {
        openBraceCount++;
      }
    }
    if (openBraceCount > 1 ||
        (openBraceCount == 1 && tokens.last.kind != TdfTokenKind.openBrace)) {
      TdfDirectiveParser.fail(
        TdfErrorKind.unexpectedToken,
        line,
        'Non-comment tokens after opening brace "{".',
      );
    }
    final isBlockHeader = openBraceCount == 1;
    final statementTokenCount = isBlockHeader
        ? tokens.length - 1
        : tokens.length;
    if (statementTokenCount > maxTdfArgsPerStmt + 1) {
      TdfDirectiveParser.fail(
        TdfErrorKind.limitExceeded,
        line,
        'Statement exceeds maximum of $maxTdfArgsPerStmt arguments.',
      );
    }
    if (!state.hasSeenVersionHeader) {
      _handleVersionHeader(state, line, tokens, isBlockHeader: isBlockHeader);
      return;
    }
    if (statementTokenCount == 0) {
      TdfDirectiveParser.fail(
        TdfErrorKind.invalidBlockHeader,
        line,
        'Standalone "{" without block type.',
      );
    }
    _ensureStructuralBounds(state, line, isBlockHeader: isBlockHeader);
    final nameToken = tokens[0];
    if (!nameToken.isBare || !TdfScanner.isValidIdentifier(nameToken.value)) {
      TdfDirectiveParser.fail(
        TdfErrorKind.invalidIdentifier,
        line,
        'Invalid block or directive identifier.',
      );
    }
    final args = tokens.sublist(1, statementTokenCount);
    _recordOrdinaryChildStatement(state);
    if (isBlockHeader) {
      _openBlock(state, line, nameToken.value, args);
    } else {
      _applyDirective(state, line, nameToken.value, args);
    }
  }

  /// Applies a directive statement at [line] inside the active block on [state.blockStack].
  static void _applyDirective(
    TdfParserState state,
    int line,
    String directive,
    List<TdfScannedToken> args,
  ) {
    if (state.blockStack.isEmpty) {
      TdfDirectiveParser.fail(
        TdfErrorKind.unexpectedRootDirective,
        line,
        'Unexpected directive "$directive" at root depth 0.',
      );
    }
    if (args.isEmpty) {
      TdfDirectiveParser.fail(
        TdfErrorKind.missingDirectiveArgument,
        line,
        'Directive "$directive" requires at least one argument.',
      );
    }
    final current = state.blockStack.last;
    switch (current) {
      case TdfDeletedBuilder():
        TdfDirectiveParser.applyDeletedDirective(
          current.fields,
          directive,
          args,
          line,
        );
      case TdfQueueBuilder():
        TdfDirectiveParser.applyQueueDirective(
          current.fields,
          directive,
          args,
          line,
        );
      case TdfLabelBuilder():
        TdfDirectiveParser.applyLabelDirective(
          current.fields,
          directive,
          args,
          line,
        );
      case TdfLocationBuilder():
        TdfDirectiveParser.applyLocationDirective(
          current.fields,
          directive,
          args,
          line,
        );
      case TdfTaskBuilder():
        TdfDirectiveParser.applyTaskDirective(
          current.fields,
          directive,
          args,
          line,
        );
      case TdfSubtasksBuilder():
        if (directive != 'step') {
          TdfDirectiveParser.fail(
            TdfErrorKind.unknownDirective,
            line,
            'Unknown subtasks directive "$directive".',
          );
        }
        current.steps.add(TdfDirectiveParser.parseStepDirective(args, line));
      case TdfConditionBuilder():
        current.ruleCount++;
        _applyNestedConditionStatement(state, line, directive, args);
    }
  }

  /// Dispatches a depth-`2` statement inside `condition { ... }` to its enclosing `label` or `task` builder.
  static void _applyNestedConditionStatement(
    TdfParserState state,
    int line,
    String directive,
    List<TdfScannedToken> args,
  ) {
    final parent = state.blockStack[state.blockStack.length - 2];
    if (parent is TdfLabelBuilder) {
      TdfDirectiveParser.addConditionToLabel(
        parent.fields,
        directive,
        args,
        line,
        isInlineDirective: false,
      );
    } else if (parent is TdfTaskBuilder) {
      TdfDirectiveParser.addConditionToTask(
        parent.fields,
        directive,
        args,
        line,
        isInlineDirective: false,
      );
    }
  }

  /// Validates and finalizes a closed [TdfDeletedBuilder] into [state].
  static void _closeDeletedBuilder(
    TdfParserState state,
    TdfDeletedBuilder current,
    int closeLine,
  ) {
    final generation = current.fields.generation;
    if (generation == null) {
      TdfDirectiveParser.fail(
        TdfErrorKind.missingRequiredDirective,
        closeLine,
        'Deleted block requires a "generation" directive.',
      );
    }
    for (final entry in current.fields.taskEntries) {
      if (state.taskIds.contains(entry.record.taskId)) {
        TdfDirectiveParser.fail(
          TdfErrorKind.duplicateIdentifier,
          entry.line,
          'Task ID "${entry.record.taskId}" appears in both live task and deleted block.',
        );
      }
      state.deletedTaskIds.add(entry.record.taskId);
    }
    for (final entry in current.fields.labelEntries) {
      if (state.labelIds.contains(entry.record.labelId)) {
        TdfDirectiveParser.fail(
          TdfErrorKind.duplicateIdentifier,
          entry.line,
          'Label ID "${entry.record.labelId}" appears in both live label and deleted block.',
        );
      }
      state.deletedLabelIds.add(entry.record.labelId);
    }
    for (final entry in current.fields.locationEntries) {
      if (state.locationIds.contains(entry.record.locationId)) {
        TdfDirectiveParser.fail(
          TdfErrorKind.duplicateIdentifier,
          entry.line,
          'Location ID "${entry.record.locationId}" appears in both live location and deleted block.',
        );
      }
      state.deletedLocationIds.add(entry.record.locationId);
    }
    state.deletedBlock = TdfDeletedBlock(
      generation: generation,
      tasks: <TdfDeletedTaskRecord>[
        for (final entry in current.fields.taskEntries) entry.record,
      ],
      labels: <TdfDeletedLabelRecord>[
        for (final entry in current.fields.labelEntries) entry.record,
      ],
      locations: <TdfDeletedLocationRecord>[
        for (final entry in current.fields.locationEntries) entry.record,
      ],
    );
  }

  /// Validates and finalizes a closed [TdfLabelBuilder] into [state].
  static void _closeLabelBuilder(
    TdfParserState state,
    TdfLabelBuilder current,
  ) {
    final name = current.fields.name;
    if (name == null) {
      TdfDirectiveParser.fail(
        TdfErrorKind.missingRequiredDirective,
        current.headerLine,
        'Label block "${current.id}" is missing required "name" directive.',
      );
    }
    state.locationReferences.addAll(current.fields.locationReferences);
    state.labels.add(
      TdfLabel(
        id: current.id,
        name: name,
        isScoped: current.isScoped,
        color: current.fields.color,
        note: current.fields.note,
        modifiedAt: current.fields.modifiedAt,
        links: current.fields.links,
        conditions: TdfMetadata.coalesceLocationConditions(
          current.fields.conditions,
        ),
      ),
    );
  }

  /// Validates and finalizes a closed [TdfLocationBuilder] into [state].
  static void _closeLocationBuilder(
    TdfParserState state,
    TdfLocationBuilder current,
  ) {
    final name = current.fields.name;
    final latitude = current.fields.latitude;
    final longitude = current.fields.longitude;
    final radius = current.fields.radius;
    if (name == null ||
        latitude == null ||
        longitude == null ||
        radius == null) {
      TdfDirectiveParser.fail(
        TdfErrorKind.missingRequiredDirective,
        current.headerLine,
        'Location block "${current.id}" is missing required "name", "coordinates", or "radius" directive.',
      );
    }
    state.locations.add(
      TdfLocation(
        id: current.id,
        name: name,
        note: current.fields.note,
        source: current.fields.source,
        latitude: latitude,
        longitude: longitude,
        radius: radius,
        modifiedAt: current.fields.modifiedAt,
        rawLatitudeText: current.fields.latitudeText,
        rawLongitudeText: current.fields.longitudeText,
        rawRadiusText: current.fields.radiusText,
      ),
    );
  }

  /// Validates and finalizes a closed [TdfQueueBuilder] into [state].
  static void _closeQueueBuilder(
    TdfParserState state,
    TdfQueueBuilder current,
    int closeLine,
  ) {
    final modifiedAt = current.fields.modifiedAt;
    if (modifiedAt == null) {
      TdfDirectiveParser.fail(
        TdfErrorKind.missingRequiredDirective,
        closeLine,
        'Queue block requires a "modified" directive.',
      );
    }
    state.queueEntries.addAll(current.fields.entries);
    state.queueBlock = TdfQueueBlock(
      modifiedAt: modifiedAt,
      taskIds: <String>[
        for (final entry in current.fields.entries) entry.taskId,
      ],
    );
  }

  /// Validates and finalizes a closed [TdfSubtasksBuilder] into [state].
  static void _closeSubtasksBuilder(
    TdfParserState state,
    TdfSubtasksBuilder current,
    int closeLine,
  ) {
    if (current.steps.isEmpty) {
      TdfDirectiveParser.fail(
        TdfErrorKind.missingRequiredDirective,
        closeLine,
        'Subtasks block must contain at least one "step" directive.',
      );
    }
    if (state.blockStack.isNotEmpty) {
      final parent = state.blockStack.last;
      if (parent is TdfTaskBuilder) {
        parent.subtasks.addAll(current.steps);
        parent.autoFinishSubtasks = current.autoFinish;
      }
    }
  }

  /// Validates and finalizes a closed [TdfTaskBuilder] into [state].
  static void _closeTaskBuilder(TdfParserState state, TdfTaskBuilder current) {
    final name = current.fields.name;
    final createdAt = current.fields.createdAt;
    if (name == null || createdAt == null) {
      TdfDirectiveParser.fail(
        TdfErrorKind.missingRequiredDirective,
        current.headerLine,
        'Task block "${current.id}" is missing required "name" or "created" directive.',
      );
    }
    final finishedAt = current.fields.finishedAt;
    final effectiveCompletions = current.fields.completions ?? 0;
    if (finishedAt != null && effectiveCompletions == 0) {
      TdfDirectiveParser.fail(
        TdfErrorKind.invalidCompletionState,
        current.headerLine,
        'Task "${current.id}" has "finished" present with completions 0.',
      );
    }
    final sortedLabelIds = <String>{
      for (final reference in current.fields.labelIds) reference.labelId,
    }.toList()..sort();
    state.labelReferences.addAll(current.fields.labelIds);
    state.locationReferences.addAll(current.fields.locationReferences);
    final sortedDependencies = <TdfTaskDependency>[
      for (final entry in current.fields.blockedByCompletions.entries)
        TdfTaskDependency(taskId: entry.key, requiredCompletion: entry.value),
    ]..sort((a, b) => a.taskId.compareTo(b.taskId));
    state.tasksWithMeta.add((
      task: TaskItem(
        id: current.id,
        title: name,
        note: current.fields.note,
        isCompleted: finishedAt != null,
        isPriority: current.isPriority,
        createdAt: createdAt,
        completedAt: finishedAt,
        modifiedAt: current.fields.modifiedAt,
        completions: effectiveCompletions,
        suspendedAt: current.fields.suspendedAt,
        isSuspendedForever: current.fields.isSuspendedForever,
        suspendedNote: current.fields.suspendedNote,
        dueAt: current.fields.dueAt,
        dueAnchor: current.fields.dueAnchor,
        isDuePassive: current.fields.isDuePassive,
        dueNote: current.fields.dueNote,
        origin: current.fields.origin,
        repeatRule: current.fields.repeatRule,
        labelIds: sortedLabelIds,
        dependencies: sortedDependencies,
        links: current.fields.links,
        history: current.fields.history,
        conditions: TdfMetadata.coalesceLocationConditions(
          current.fields.conditions,
        ),
        subtasks: current.subtasks,
        subtasksAutoFinish: current.autoFinishSubtasks,
      ),
      headerLine: current.headerLine,
      blockedLine: current.fields.blockedLine ?? current.headerLine,
    ));
  }

  /// Enforces `MAX_STMTS_PER_BLOCK`, `MAX_NESTING_DEPTH`, and `MAX_BLOCKS_PER_DOC` before identifier validation and argument slicing (`TDF-VAL-001`, `TDF-VAL-002`).
  static void _ensureStructuralBounds(
    TdfParserState state,
    int line, {
    required bool isBlockHeader,
  }) {
    if (state.blockStack.isNotEmpty) {
      final parent = state.blockStack.last;
      if (parent is! TdfDeletedBuilder &&
          parent is! TdfQueueBuilder &&
          parent is! TdfConditionBuilder &&
          parent.statementCount >= maxTdfStmtsPerBlock) {
        TdfDirectiveParser.fail(
          TdfErrorKind.limitExceeded,
          line,
          'Block exceeds maximum of $maxTdfStmtsPerBlock direct child statements.',
        );
      }
    }
    if (!isBlockHeader) {
      return;
    }
    if (state.blockStack.length >= maxTdfNestingDepth) {
      TdfDirectiveParser.fail(
        TdfErrorKind.limitExceeded,
        line,
        'Block nesting exceeds maximum depth of $maxTdfNestingDepth.',
      );
    }
    if (state.totalBlockCount >= maxTdfBlocksPerDoc) {
      TdfDirectiveParser.fail(
        TdfErrorKind.limitExceeded,
        line,
        'Document exceeds maximum of $maxTdfBlocksPerDoc blocks.',
      );
    }
  }

  /// Validates the mandatory initial `tdf 0.8.0` header (`TDF-COMPAT-001`, `TDF-ENT-001`).
  static void _handleVersionHeader(
    TdfParserState state,
    int line,
    List<TdfScannedToken> tokens, {
    required bool isBlockHeader,
  }) {
    if (isBlockHeader ||
        tokens.length < 2 ||
        !tokens[0].isBare ||
        tokens[0].value != 'tdf') {
      TdfDirectiveParser.fail(
        TdfErrorKind.missingVersionHeader,
        line,
        'First statement must be "tdf $supportedVersion".',
      );
    }
    final versionToken = tokens[1];
    if (tokens.length != 2 ||
        !versionToken.isBare ||
        versionToken.value != supportedVersion) {
      throw TdfException(
        kind: TdfErrorKind.unsupportedVersion,
        line: line,
        message:
            'Unsupported TDF version "${versionToken.value}" (expected $supportedVersion).',
        sourceVersion: versionToken.value,
      );
    }
    state.hasSeenVersionHeader = true;
  }

  /// Opens a new `{ ... }` block on [state.blockStack] at [line].
  static void _openBlock(
    TdfParserState state,
    int line,
    String blockType,
    List<TdfScannedToken> args,
  ) {
    state.totalBlockCount++;

    if (state.blockStack.isEmpty) {
      _openRootBlock(state, line, blockType, args);
      return;
    }

    final parent = state.blockStack.last;
    switch (parent) {
      case TdfLabelBuilder():
        if (blockType != 'condition') {
          TdfDirectiveParser.fail(
            TdfErrorKind.unknownBlockType,
            line,
            'Unknown block "$blockType" inside label block.',
          );
        }
        if (args.isNotEmpty) {
          TdfDirectiveParser.fail(
            TdfErrorKind.invalidBlockHeader,
            line,
            '"condition" block header takes zero arguments.',
          );
        }
        state.blockStack.add(TdfConditionBuilder(line));
      case TdfTaskBuilder():
        if (blockType == 'condition') {
          if (args.isNotEmpty) {
            TdfDirectiveParser.fail(
              TdfErrorKind.invalidBlockHeader,
              line,
              '"condition" block header takes zero arguments.',
            );
          }
          state.blockStack.add(TdfConditionBuilder(line));
        } else if (blockType == 'subtasks') {
          _openSubtasksBlock(state, parent, line, args);
        } else {
          TdfDirectiveParser.fail(
            TdfErrorKind.unknownBlockType,
            line,
            'Unknown block "$blockType" inside task block.',
          );
        }
      case TdfDeletedBuilder() ||
          TdfQueueBuilder() ||
          TdfLocationBuilder() ||
          TdfSubtasksBuilder() ||
          TdfConditionBuilder():
        TdfDirectiveParser.fail(
          TdfErrorKind.unknownBlockType,
          line,
          'Nested blocks are forbidden inside this block.',
        );
    }
  }

  /// Opens the root-level `deleted { ... }` block.
  static void _openDeletedBlock(
    TdfParserState state,
    int line,
    List<TdfScannedToken> args,
  ) {
    if (args.isNotEmpty) {
      TdfDirectiveParser.fail(
        TdfErrorKind.invalidBlockHeader,
        line,
        '"deleted" block header takes zero arguments.',
      );
    }
    if (state.hasDeletedBlock) {
      TdfDirectiveParser.fail(
        TdfErrorKind.duplicateDirective,
        line,
        'Duplicate root "deleted" block.',
      );
    }
    state.hasDeletedBlock = true;
    state.blockStack.add(TdfDeletedBuilder(line));
  }

  /// Opens a root-level `label <id> [scoped] { ... }` block (`TDF-ENT-003`).
  static void _openLabelBlock(
    TdfParserState state,
    int line,
    List<TdfScannedToken> args,
  ) {
    if (args.isEmpty || args.length > 2) {
      TdfDirectiveParser.fail(
        TdfErrorKind.invalidBlockHeader,
        line,
        'Label block header requires <label-id> and optional "scoped".',
      );
    }
    final idToken = args[0];
    if (!idToken.isBare || !TdfDirectiveParser.isValidEntityId(idToken.value)) {
      TdfDirectiveParser.fail(
        TdfErrorKind.invalidIdentifier,
        line,
        'Invalid <label-id> "${idToken.value}".',
      );
    }
    var isScoped = false;
    if (args.length == 2) {
      if (!args[1].isBare || args[1].value != 'scoped') {
        TdfDirectiveParser.fail(
          TdfErrorKind.invalidBlockHeader,
          line,
          'Unknown label header argument.',
        );
      }
      isScoped = true;
    }
    if (!state.labelIds.add(idToken.value) ||
        state.deletedLabelIds.contains(idToken.value)) {
      TdfDirectiveParser.fail(
        TdfErrorKind.duplicateIdentifier,
        line,
        'Duplicate label ID "${idToken.value}".',
      );
    }
    state.blockStack.add(TdfLabelBuilder(idToken.value, isScoped, line));
  }

  /// Opens a root-level `location <id> { ... }` block (`TDF-ENT-004`).
  static void _openLocationBlock(
    TdfParserState state,
    int line,
    List<TdfScannedToken> args,
  ) {
    if (args.length != 1) {
      TdfDirectiveParser.fail(
        TdfErrorKind.invalidBlockHeader,
        line,
        'Location block header requires exactly 1 <location-id> argument.',
      );
    }
    final idToken = args[0];
    if (!idToken.isBare || !TdfDirectiveParser.isValidEntityId(idToken.value)) {
      TdfDirectiveParser.fail(
        TdfErrorKind.invalidIdentifier,
        line,
        'Invalid <location-id> "${idToken.value}".',
      );
    }
    if (state.locations.length >= maxTdfLocations) {
      TdfDirectiveParser.fail(
        TdfErrorKind.limitExceeded,
        line,
        'Document exceeds maximum of $maxTdfLocations location blocks.',
      );
    }
    if (!state.locationIds.add(idToken.value) ||
        state.deletedLocationIds.contains(idToken.value)) {
      TdfDirectiveParser.fail(
        TdfErrorKind.duplicateIdentifier,
        line,
        'Duplicate location ID "${idToken.value}".',
      );
    }
    state.blockStack.add(TdfLocationBuilder(idToken.value, line));
  }

  /// Opens the root-level `queue { ... }` block.
  static void _openQueueBlock(
    TdfParserState state,
    int line,
    List<TdfScannedToken> args,
  ) {
    if (args.isNotEmpty) {
      TdfDirectiveParser.fail(
        TdfErrorKind.invalidBlockHeader,
        line,
        '"queue" block header takes zero arguments.',
      );
    }
    if (state.hasQueueBlock) {
      TdfDirectiveParser.fail(
        TdfErrorKind.duplicateDirective,
        line,
        'Duplicate root "queue" block.',
      );
    }
    state.hasQueueBlock = true;
    state.blockStack.add(TdfQueueBuilder(line));
  }

  /// Dispatches a root-level block header at depth `0`.
  static void _openRootBlock(
    TdfParserState state,
    int line,
    String blockType,
    List<TdfScannedToken> args,
  ) {
    switch (blockType) {
      case 'deleted':
        _openDeletedBlock(state, line, args);
      case 'queue':
        _openQueueBlock(state, line, args);
      case 'label':
        _openLabelBlock(state, line, args);
      case 'location':
        _openLocationBlock(state, line, args);
      case 'task':
        _openTaskBlock(state, line, args);
      case _:
        TdfDirectiveParser.fail(
          TdfErrorKind.unknownBlockType,
          line,
          'Unknown root block type "$blockType".',
        );
    }
  }

  /// Opens a `subtasks [auto-finish] { ... }` sub-block inside [parent].
  static void _openSubtasksBlock(
    TdfParserState state,
    TdfTaskBuilder parent,
    int line,
    List<TdfScannedToken> args,
  ) {
    var autoFinish = false;
    if (args.length == 1) {
      if (!args[0].isBare || args[0].value != 'auto-finish') {
        TdfDirectiveParser.fail(
          TdfErrorKind.invalidBlockHeader,
          line,
          'Invalid subtasks header argument.',
        );
      }
      autoFinish = true;
    } else if (args.length > 1) {
      TdfDirectiveParser.fail(
        TdfErrorKind.invalidBlockHeader,
        line,
        'Too many arguments in subtasks block header.',
      );
    }
    if (parent.hasSubtasksBlock) {
      TdfDirectiveParser.fail(
        TdfErrorKind.duplicateDirective,
        line,
        'Task "${parent.id}" has multiple "subtasks" blocks.',
      );
    }
    parent.hasSubtasksBlock = true;
    state.blockStack.add(TdfSubtasksBuilder(autoFinish));
  }

  /// Opens a root-level `task <id> [priority] { ... }` block.
  static void _openTaskBlock(
    TdfParserState state,
    int line,
    List<TdfScannedToken> args,
  ) {
    if (args.isEmpty || args.length > 2) {
      TdfDirectiveParser.fail(
        TdfErrorKind.invalidBlockHeader,
        line,
        'Task block header requires <task-id> and optional "priority".',
      );
    }
    final idToken = args[0];
    if (!idToken.isBare || !TdfDirectiveParser.isValidEntityId(idToken.value)) {
      TdfDirectiveParser.fail(
        TdfErrorKind.invalidIdentifier,
        line,
        'Invalid <task-id> "${idToken.value}".',
      );
    }
    var isPriority = false;
    if (args.length == 2) {
      if (!args[1].isBare || args[1].value != 'priority') {
        TdfDirectiveParser.fail(
          TdfErrorKind.invalidBlockHeader,
          line,
          'Unknown task header argument.',
        );
      }
      isPriority = true;
    }
    if (!state.taskIds.add(idToken.value) ||
        state.deletedTaskIds.contains(idToken.value)) {
      TdfDirectiveParser.fail(
        TdfErrorKind.duplicateIdentifier,
        line,
        'Duplicate task ID "${idToken.value}".',
      );
    }
    state.blockStack.add(TdfTaskBuilder(idToken.value, isPriority, line));
  }

  /// Records one direct child statement on ordinary enclosing blocks (`task`, `label`, `location`, `subtasks`).
  static void _recordOrdinaryChildStatement(TdfParserState state) {
    if (state.blockStack.isEmpty) {
      return;
    }
    final parent = state.blockStack.last;
    if (parent is TdfDeletedBuilder ||
        parent is TdfQueueBuilder ||
        parent is TdfConditionBuilder) {
      return;
    }
    parent.statementCount++;
  }

  /// Scans [content] into a validated [TdfParserState].
  static TdfParserState _scanAndValidateState(
    String content, {
    required bool byteLengthVerified,
  }) {
    if (!byteLengthVerified &&
        !TdfScanner.isUtf8ByteLengthWithinBound(content, maxTdfFileBytes)) {
      TdfDirectiveParser.fail(
        TdfErrorKind.limitExceeded,
        1,
        'Document exceeds maximum of $maxTdfFileBytes bytes.',
      );
    }
    final state = TdfParserState();
    var offset = 0;
    var lineNumber = 1;
    while (offset < content.length) {
      if (lineNumber > maxTdfLineCount) {
        TdfDirectiveParser.fail(
          TdfErrorKind.limitExceeded,
          lineNumber,
          'Document exceeds maximum of $maxTdfLineCount lines.',
        );
      }
      final span = TdfScanner.findLineSpan(content, offset, lineNumber);
      final tokens = TdfScanner.scanLineTokens(
        content,
        span.lineStart,
        span.lineEnd,
        lineNumber,
      );
      if (tokens.isNotEmpty) {
        processLineTokens(state, lineNumber, tokens);
      }
      offset = span.nextOffset;
      lineNumber++;
    }
    if (!state.hasSeenVersionHeader) {
      TdfDirectiveParser.fail(
        TdfErrorKind.missingVersionHeader,
        1,
        'Document contains no statements; missing "tdf $supportedVersion" header.',
      );
    }
    if (state.blockStack.isNotEmpty) {
      final eofLine = lineNumber > 1 ? lineNumber - 1 : 1;
      TdfDirectiveParser.fail(
        TdfErrorKind.unclosedBlock,
        eofLine,
        'Unclosed block at end of file.',
      );
    }
    _validateLabelReferences(state);
    _validateLocationReferences(state);
    _validateQueueMembership(state);
    _validateDependencies(state);
    return state;
  }

  /// Detects self-dependencies and multi-hop circular dependency cycles across all tasks (`CircularDependency`).
  static void _validateDependencies(TdfParserState state) {
    final tasksById = <String, TaskItem>{
      for (final item in state.tasksWithMeta) item.task.id: item.task,
    };
    final blockedLineById = <String, int>{
      for (final item in state.tasksWithMeta) item.task.id: item.blockedLine,
    };
    final cycle = TaskBoardEvaluator.findDependencyCycle(
      tasksById,
      traversalOrder: state.tasksWithMeta.map((item) => item.task.id),
    );
    if (cycle != null) {
      TdfDirectiveParser.fail(
        TdfErrorKind.circularDependency,
        blockedLineById[cycle.startTaskId] ?? 1,
        'Circular dependency detected involving task "${cycle.taskId}" and "${cycle.dependencyTaskId}".',
      );
    }
  }

  /// Validates that every referenced `<label-id>` matches a declared live `label` block (`UnknownLabelReference`).
  static void _validateLabelReferences(TdfParserState state) {
    for (final reference in state.labelReferences) {
      if (!state.labelIds.contains(reference.labelId)) {
        TdfDirectiveParser.fail(
          TdfErrorKind.unknownLabelReference,
          reference.line,
          'Task references unknown <label-id> "${reference.labelId}".',
        );
      }
    }
  }

  /// Validates that every referenced `<location-id>` in `condition location` matches a declared live `location` block (`UnknownLocationReference`).
  static void _validateLocationReferences(TdfParserState state) {
    for (final reference in state.locationReferences) {
      if (!state.locationIds.contains(reference.locationId)) {
        TdfDirectiveParser.fail(
          TdfErrorKind.unknownLocationReference,
          reference.line,
          'Condition references unknown or deleted <location-id> "${reference.locationId}".',
        );
      }
    }
  }

  /// Validates `queue` membership against live open tasks (`TDF-ENT-006`, `TDF-VAL-003`).
  static void _validateQueueMembership(TdfParserState state) {
    final tasksById = <String, TaskItem>{
      for (final item in state.tasksWithMeta) item.task.id: item.task,
    };
    for (final entry in state.queueEntries) {
      final target = tasksById[entry.taskId];
      if (target == null || target.isCompleted || target.completedAt != null) {
        TdfDirectiveParser.fail(
          TdfErrorKind.invalidQueueMembership,
          entry.line,
          'Queue entry "${entry.taskId}" must reference a live open task.',
        );
      }
    }
  }
}
