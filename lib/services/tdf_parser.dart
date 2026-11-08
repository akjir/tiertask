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

import '../models/task_board.dart';
import '../models/task_item.dart';
import '../models/tdf_error.dart';
import '../models/tdf_location.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_sync_metadata.dart';
import '../models/tdf_timezone.dart';
import 'tdf_directive_parser.dart';
import 'tdf_id_migration.dart';
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

  /// Whether the `scoped` header flag was present (`spec/TDF_SPEC_0.6.0.md` Section 4.2).
  final bool isScoped;
}

/// Active root-level `location <id> { ... }` block builder (`spec/TDF_SPEC_0.6.0.md` Section 4.3).
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
  /// Creates a [TdfParserState].
  TdfParserState({this.convertLegacyLocationsTo060 = true});

  /// Active nesting stack of open `{ ... }` blocks.
  final List<TdfBlockBuilder> blockStack = <TdfBlockBuilder>[];

  /// Whether legacy `0.5.x` inline location rules should be converted in memory to `0.6.0` `location` blocks.
  final bool convertLegacyLocationsTo060;

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

  /// Whether the initial `tdf 0.6.0` (or `0.5.1` / `0.5.0`) version header has been seen.
  bool hasSeenVersionHeader = false;

  /// Whether the input document is a `tdf 0.5.0` file undergoing Section 10.6 load-time in-memory conversion.
  bool isLegacy050 = false;

  /// Whether the input document is a `tdf 0.5.1` file undergoing Section 10.7 load-time in-memory conversion.
  bool isLegacy051 = false;

  /// Live `<label-id>` values declared in the document.
  final Set<String> labelIds = <String>{};

  /// Referenced `<label-id>` values across all tasks with their 1-based line numbers.
  final List<({String labelId, int line})> labelReferences =
      <({String labelId, int line})>[];

  /// Parsed `label` definitions.
  final List<TdfLabel> labels = <TdfLabel>[];

  /// Legacy 0.5.x inline location condition tuples collected across labels and tasks.
  final List<TdfLegacyInlineLocationRef> legacyInlineLocations =
      <TdfLegacyInlineLocationRef>[];

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

  /// Parsed tasks together with their declaration line numbers and legacy `0.5.0` `queued` timestamps.
  final List<
    ({TaskItem task, int headerLine, int blockedLine, DateTime? legacyQueuedAt})
  >
  tasksWithMeta =
      <
        ({
          TaskItem task,
          int headerLine,
          int blockedLine,
          DateTime? legacyQueuedAt,
        })
      >[];

  /// Total blocks opened across the entire document (`0..maxTdfBlocksPerDoc`).
  int totalBlockCount = 0;

  /// Whether the document is a `0.5.0` or `0.5.1` file undergoing load-time conversion.
  bool get isLegacy05x => isLegacy050 || isLegacy051;
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

  ///Whether a `subtasks` block has been declared inside this task.
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

/// Structural and cross-entity parser for TDF 0.6.0 (`spec/TDF_SPEC_0.6.0.md` Sections 3, 4, 5, 7, 8, 10.6, and 10.7).
abstract final class TdfBlockParser {
  /// Legacy TDF version (`0.5.0`) accepted during normal loading and converted in memory per Section 10.6.
  static const String legacyLoadableVersion = '0.5.0';

  /// Legacy TDF version (`0.5.1`) accepted during normal loading and converted in memory per Section 10.7.
  static const String legacyLoadableVersion051 = '0.5.1';

  /// Legacy TDF version alias (`0.5.0`).
  static const String legacySupportedVersion = legacyLoadableVersion;

  /// Supported TDF specification version (`0.6.0`).
  static const String supportedVersion = '0.6.0';

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
        final generation = current.fields.generation;
        if (generation == null) {
          TdfDirectiveParser.fail(
            TdfErrorKind.missingRequiredDirective,
            line,
            'Deleted block requires a "generation" directive.',
          );
        }
        for (final id in current.fields.deletedTaskIds) {
          if (state.taskIds.contains(id)) {
            TdfDirectiveParser.fail(
              TdfErrorKind.duplicateIdentifier,
              line,
              'Task ID "$id" appears in both live task block and deleted block.',
            );
          }
          state.deletedTaskIds.add(id);
        }
        for (final id in current.fields.deletedLabelIds) {
          if (state.labelIds.contains(id)) {
            TdfDirectiveParser.fail(
              TdfErrorKind.duplicateIdentifier,
              line,
              'Label ID "$id" appears in both live label block and deleted block.',
            );
          }
          state.deletedLabelIds.add(id);
        }
        for (final id in current.fields.deletedLocationIds) {
          if (state.locationIds.contains(id)) {
            TdfDirectiveParser.fail(
              TdfErrorKind.duplicateIdentifier,
              line,
              'Location ID "$id" appears in both live location block and deleted block.',
            );
          }
          state.deletedLocationIds.add(id);
        }
        state.deletedBlock = TdfDeletedBlock(
          generation: generation,
          tasks: current.fields.tasks,
          labels: current.fields.labels,
          locations: current.fields.locations,
        );
      case TdfQueueBuilder():
        final modifiedAt = current.fields.modifiedAt;
        if (modifiedAt == null) {
          TdfDirectiveParser.fail(
            TdfErrorKind.missingRequiredDirective,
            line,
            'Queue block requires a "modified" directive.',
          );
        }
        state.queueEntries.addAll(current.fields.entries);
        state.queueBlock = TdfQueueBlock(
          modifiedAt: modifiedAt,
          taskIds: [for (final entry in current.fields.entries) entry.taskId],
        );
      case TdfLabelBuilder():
        final name = current.fields.name;
        if (name == null) {
          TdfDirectiveParser.fail(
            TdfErrorKind.missingRequiredDirective,
            current.headerLine,
            'Label block "${current.id}" is missing required "name" directive.',
          );
        }
        state.locationReferences.addAll(current.fields.locationReferences);
        state.legacyInlineLocations.addAll(
          current.fields.legacyInlineLocations,
        );
        state.labels.add(
          TdfLabel(
            id: current.id,
            name: name,
            isScoped: current.isScoped,
            color: current.fields.color,
            note: current.fields.note,
            modifiedAt: current.fields.modifiedAt,
            conditions: state.convertLegacyLocationsTo060
                ? TdfDirectiveParser.coalesceLocationConditions(
                    current.fields.conditions,
                  )
                : current.fields.conditions,
          ),
        );
      case TdfLocationBuilder():
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
      case TdfTaskBuilder():
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
        final explicitCompletions = current.fields.completions;
        final effectiveCompletions = explicitCompletions ?? 0;
        if (finishedAt != null && effectiveCompletions == 0) {
          TdfDirectiveParser.fail(
            TdfErrorKind.invalidCompletionState,
            current.headerLine,
            'Task "${current.id}" has "finished" present with completions 0.',
          );
        }
        final sortedLabelIds =
            current.fields.labelIds.map((ref) => ref.labelId).toSet().toList()
              ..sort();
        state.labelReferences.addAll(current.fields.labelIds);
        state.locationReferences.addAll(current.fields.locationReferences);
        state.legacyInlineLocations.addAll(
          current.fields.legacyInlineLocations,
        );
        final sortedDeps =
            current.fields.blockedByCompletions.entries
                .map(
                  (entry) => TdfTaskDependency(
                    taskId: entry.key,
                    requiredCompletion: entry.value,
                  ),
                )
                .toList()
              ..sort((a, b) => a.taskId.compareTo(b.taskId));
        var resolvedModifiedAt = current.fields.modifiedAt;
        final legacyQueuedAt = current.fields.queuedAt;
        if (state.isLegacy050 &&
            resolvedModifiedAt == null &&
            legacyQueuedAt != null) {
          final baseFallback =
              finishedAt != null && finishedAt.isAfter(createdAt)
              ? finishedAt
              : createdAt;
          if (legacyQueuedAt.isAfter(baseFallback)) {
            resolvedModifiedAt = legacyQueuedAt;
          }
        }
        state.tasksWithMeta.add((
          task: TaskItem(
            id: current.id,
            title: name,
            note: current.fields.note,
            isCompleted: finishedAt != null,
            isPriority: current.isPriority,
            createdAt: createdAt,
            completedAt: finishedAt,
            modifiedAt: resolvedModifiedAt,
            completions: effectiveCompletions,
            suspendedAt: current.fields.suspendedAt,
            isSuspendedForever: current.fields.isSuspendedForever,
            dueAt: current.fields.dueAt,
            origin: current.fields.origin,
            repeatRule: current.fields.repeatRule,
            labelIds: sortedLabelIds,
            dependencies: sortedDeps,
            links: current.fields.links,
            conditions: state.convertLegacyLocationsTo060
                ? TdfDirectiveParser.coalesceLocationConditions(
                    current.fields.conditions,
                  )
                : current.fields.conditions,
            subtasks: current.subtasks,
            subtasksAutoFinish: current.autoFinishSubtasks,
          ),
          headerLine: current.headerLine,
          blockedLine: current.fields.blockedLine ?? current.headerLine,
          legacyQueuedAt: legacyQueuedAt,
        ));
      case TdfSubtasksBuilder():
        if (current.steps.isEmpty) {
          TdfDirectiveParser.fail(
            TdfErrorKind.missingRequiredDirective,
            line,
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

  /// Parses a complete TDF 0.6.0 (or `0.5.1` / `0.5.0`) document [content] and evaluates all 6 tiers at [evaluationTime].
  static TaskBoard parseDocument(
    String content, {
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
    bool pruneExpiredCompleted = false,
    bool convertLegacyLocationsTo060 = true,
  }) {
    if (content.length > maxTdfFileBytes ||
        utf8.encode(content).length > maxTdfFileBytes) {
      TdfDirectiveParser.fail(
        TdfErrorKind.limitExceeded,
        1,
        'Document exceeds maximum of $maxTdfFileBytes bytes.',
      );
    }
    final state = TdfParserState(
      convertLegacyLocationsTo060: convertLegacyLocationsTo060,
    );
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
        'Document contains no statements; missing "tdf 0.6.0" header.',
      );
    }
    if (state.blockStack.isNotEmpty) {
      TdfDirectiveParser.fail(
        TdfErrorKind.unclosedBlock,
        1,
        'Unclosed block at end of file.',
      );
    }
    if (state.isLegacy05x && state.convertLegacyLocationsTo060) {
      _convertLegacyInlineLocations05xTo060(state);
    }
    _validateLabelReferences(state);
    if (state.convertLegacyLocationsTo060) {
      _validateLocationReferences(state);
    }
    _validateDependencies(state);
    _validateQueueMembership(state);

    final tasks = [for (final item in state.tasksWithMeta) item.task];
    return TaskBoard.evaluate(
      tasks: tasks,
      labels: state.labels,
      locations: state.locations,
      deletedBlock: state.deletedBlock,
      queueBlock: state.queueBlock,
      evaluationTime: evaluationTime,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      activeLabelId: activeLabelId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
      pruneExpiredCompleted: pruneExpiredCompleted,
    );
  }

  /// Processes a single non-empty logical line's [tokens] at 1-based [line].
  static void processLineTokens(
    TdfParserState state,
    int line,
    List<TdfScannedToken> tokens,
  ) {
    if (!state.hasSeenVersionHeader) {
      _handleVersionHeader(state, line, tokens);
      return;
    }
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
    final statementTokens = isBlockHeader
        ? tokens.sublist(0, tokens.length - 1)
        : tokens;
    if (statementTokens.isEmpty) {
      TdfDirectiveParser.fail(
        TdfErrorKind.invalidBlockHeader,
        line,
        'Standalone "{" without block type.',
      );
    }
    final nameToken = statementTokens[0];
    if (nameToken.kind != TdfTokenKind.bareWord) {
      TdfDirectiveParser.fail(
        TdfErrorKind.invalidIdentifier,
        line,
        'Block or directive name must not be quoted.',
      );
    }
    final args = statementTokens.sublist(1);
    if (args.length > maxTdfArgsPerStmt) {
      TdfDirectiveParser.fail(
        TdfErrorKind.limitExceeded,
        line,
        'Statement exceeds maximum of $maxTdfArgsPerStmt arguments.',
      );
    }
    if (state.blockStack.isNotEmpty) {
      final parent = state.blockStack.last;
      if (parent is! TdfDeletedBuilder &&
          parent is! TdfQueueBuilder &&
          parent is! TdfConditionBuilder) {
        if (parent.statementCount >= maxTdfStmtsPerBlock) {
          TdfDirectiveParser.fail(
            TdfErrorKind.limitExceeded,
            line,
            'Block exceeds maximum of $maxTdfStmtsPerBlock direct child statements.',
          );
        }
        parent.statementCount++;
      }
    }
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
          isLegacy05x: state.isLegacy05x,
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
          allowLegacyQueued: state.isLegacy050,
          isLegacy05x: state.isLegacy05x,
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
        final parent = state.blockStack[state.blockStack.length - 2];
        if (parent is TdfLabelBuilder) {
          TdfDirectiveParser.addConditionToLabel(
            parent.fields,
            directive,
            args,
            line,
            isLegacy05x: state.isLegacy05x,
          );
        } else if (parent is TdfTaskBuilder) {
          TdfDirectiveParser.addConditionToTask(
            parent.fields,
            directive,
            args,
            line,
            isInlineDirective: false,
            isLegacy05x: state.isLegacy05x,
          );
        }
    }
  }

  /// Adds all dependency `<task-id>` values from [dependencies] into [usedIds].
  static void _collectDependencyTaskIds(
    List<TdfTaskDependency> dependencies,
    Set<String> usedIds,
  ) {
    for (final dep in dependencies) {
      usedIds.add(dep.taskId);
    }
  }

  /// Extracts inline `location <lat> <lon> <radius>` rules from a legacy `0.5.0` or `0.5.1` document into deduplicated `TdfLocation` blocks (`spec/TDF_SPEC_0.6.0.md` Section 10.7).
  static void _convertLegacyInlineLocations05xTo060(TdfParserState state) {
    if (state.legacyInlineLocations.isEmpty) {
      return;
    }
    final distinctByKey = <String, TdfLegacyInlineLocationRef>{};
    for (final ref in state.legacyInlineLocations) {
      distinctByKey.putIfAbsent(ref.sourceId, () => ref);
      if (distinctByKey.length > maxTdfLocations) {
        TdfDirectiveParser.fail(
          TdfErrorKind.limitExceeded,
          ref.line,
          'Migrated document exceeds maximum of $maxTdfLocations distinct locations.',
        );
      }
    }
    final usedIds = <String>{
      ...state.taskIds,
      ...state.labelIds,
      ...state.locationIds,
      ...state.deletedTaskIds,
      ...state.deletedLabelIds,
      ...state.deletedLocationIds,
    };
    for (final entry in state.tasksWithMeta) {
      _collectDependencyTaskIds(entry.task.dependencies, usedIds);
    }
    final sortedKeys = distinctByKey.keys.toList()..sort();
    final keyToLocationId = <String, String>{};
    for (final key in sortedKeys) {
      if (distinctByKey[key] case final ref?) {
        final locationId = TdfIdMigration.assignLocationId(
          canonicalTuple: key,
          usedIds: usedIds,
        );
        keyToLocationId[key] = locationId;
        state.locationIds.add(locationId);
        state.locations.add(
          TdfLocation(
            id: locationId,
            name:
                'Location (${ref.normalizedLatitude}, ${ref.normalizedLongitude}, ${ref.normalizedRadius}m)',
            latitude: ref.latitude,
            longitude: ref.longitude,
            radius: ref.radius,
            rawLatitudeText: ref.normalizedLatitude,
            rawLongitudeText: ref.normalizedLongitude,
            rawRadiusText: ref.normalizedRadius,
          ),
        );
      }
    }

    for (var i = 0; i < state.labels.length; i++) {
      final label = state.labels[i];
      final rewritten = _rewriteEntityLocationConditions(
        label.conditions,
        keyToLocationId,
      );
      if (!identical(rewritten, label.conditions)) {
        state.labels[i] = label.copyWith(conditions: rewritten);
      }
    }
    for (var i = 0; i < state.tasksWithMeta.length; i++) {
      final entry = state.tasksWithMeta[i];
      final rewritten = _rewriteEntityLocationConditions(
        entry.task.conditions,
        keyToLocationId,
      );
      if (!identical(rewritten, entry.task.conditions)) {
        state.tasksWithMeta[i] = (
          task: entry.task.copyWith(conditions: rewritten),
          headerLine: entry.headerLine,
          blockedLine: entry.blockedLine,
          legacyQueuedAt: entry.legacyQueuedAt,
        );
      }
    }
  }

  /// Validates the mandatory initial `tdf 0.6.0` (or load-convertible `tdf 0.5.1` / `tdf 0.5.0`) header on the first non-empty line.
  static void _handleVersionHeader(
    TdfParserState state,
    int line,
    List<TdfScannedToken> tokens,
  ) {
    if (tokens.isEmpty ||
        tokens[0].kind != TdfTokenKind.bareWord ||
        tokens[0].value != 'tdf' ||
        tokens.length < 2 ||
        tokens.any(
          (token) =>
              token.kind == TdfTokenKind.openBrace ||
              token.kind == TdfTokenKind.closeBrace,
        )) {
      TdfDirectiveParser.fail(
        TdfErrorKind.missingVersionHeader,
        line,
        'First statement must be "tdf $supportedVersion".',
      );
    }
    if (tokens.length != 2 || tokens[1].kind != TdfTokenKind.bareWord) {
      TdfDirectiveParser.fail(
        TdfErrorKind.unsupportedVersion,
        line,
        'Unsupported or malformed TDF version header.',
      );
    }
    final version = tokens[1].value;
    if (version == legacyLoadableVersion) {
      state.isLegacy050 = true;
    } else if (version == legacyLoadableVersion051) {
      state.isLegacy051 = true;
    } else if (version != supportedVersion) {
      throw TdfException(
        kind: TdfErrorKind.unsupportedVersion,
        line: line,
        message:
            'Unsupported TDF version "$version" (expected $supportedVersion).',
        sourceVersion: version,
        targetVersion: supportedVersion,
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
    state.totalBlockCount++;

    if (state.blockStack.isEmpty) {
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

  /// Opens a root-level `label <id> [scoped] { ... }` block (`spec/TDF_SPEC_0.6.0.md` Section 4.2).
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
    if (idToken.kind != TdfTokenKind.bareWord ||
        !TdfDirectiveParser.isValidEntityId(idToken.value)) {
      TdfDirectiveParser.fail(
        TdfErrorKind.invalidIdentifier,
        line,
        'Invalid <label-id> "${idToken.value}".',
      );
    }
    var isScoped = false;
    if (args.length == 2) {
      if (args[1].kind != TdfTokenKind.bareWord || args[1].value != 'scoped') {
        TdfDirectiveParser.fail(
          TdfErrorKind.invalidBlockHeader,
          line,
          'Unknown label header argument "${args[1].value}".',
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

  /// Opens a root-level `location <id> { ... }` block (`spec/TDF_SPEC_0.6.0.md` Section 4.3).
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
    if (idToken.kind != TdfTokenKind.bareWord ||
        !TdfDirectiveParser.isValidEntityId(idToken.value)) {
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

  /// Opens a `subtasks [auto-finish] { ... }` sub-block inside [parent].
  static void _openSubtasksBlock(
    TdfParserState state,
    TdfTaskBuilder parent,
    int line,
    List<TdfScannedToken> args,
  ) {
    if (parent.hasSubtasksBlock) {
      TdfDirectiveParser.fail(
        TdfErrorKind.duplicateDirective,
        line,
        'Task "${parent.id}" has multiple "subtasks" blocks.',
      );
    }
    var autoFinish = false;
    if (args.length == 1) {
      if (args[0].kind != TdfTokenKind.bareWord ||
          args[0].value != 'auto-finish') {
        TdfDirectiveParser.fail(
          TdfErrorKind.invalidBlockHeader,
          line,
          'Invalid subtasks header argument "${args[0].value}".',
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
    if (idToken.kind != TdfTokenKind.bareWord ||
        !TdfDirectiveParser.isValidEntityId(idToken.value)) {
      TdfDirectiveParser.fail(
        TdfErrorKind.invalidIdentifier,
        line,
        'Invalid <task-id> "${idToken.value}".',
      );
    }
    var isPriority = false;
    if (args.length == 2) {
      if (args[1].kind != TdfTokenKind.bareWord ||
          args[1].value != 'priority') {
        TdfDirectiveParser.fail(
          TdfErrorKind.invalidBlockHeader,
          line,
          'Unknown task header argument "${args[1].value}".',
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

  /// Rewrites `LocationTaskCondition` rules containing `sourceId` keys into canonical `<location-id>` references.
  static List<TaskCondition> _rewriteEntityLocationConditions(
    List<TaskCondition> conditions,
    Map<String, String> keyToLocationId,
  ) {
    var changed = false;
    final mapped = <TaskCondition>[];
    for (final condition in conditions) {
      if (condition case final LocationTaskCondition loc) {
        changed = true;
        mapped.add(
          LocationTaskCondition(
            locationIds: [
              for (final key in loc.locationIds) keyToLocationId[key] ?? key,
            ],
          ),
        );
      } else {
        mapped.add(condition);
      }
    }
    return changed
        ? TdfDirectiveParser.coalesceLocationConditions(mapped)
        : conditions;
  }

  /// Detects self-dependencies and multi-hop circular dependency cycles across all tasks (`CircularDependency`).
  static void _validateDependencies(TdfParserState state) {
    final tasksById = <String, ({TaskItem task, int headerLine})>{
      for (final item in state.tasksWithMeta)
        item.task.id: (task: item.task, headerLine: item.headerLine),
    };
    final visitState = <String, int>{};

    void dfs(String taskId, int startLine) {
      visitState[taskId] = 1;
      final entry = tasksById[taskId];
      if (entry != null) {
        for (final dep in entry.task.dependencies) {
          final depState = visitState[dep.taskId] ?? 0;
          if (depState == 1) {
            TdfDirectiveParser.fail(
              TdfErrorKind.circularDependency,
              startLine,
              'Circular dependency detected involving task "$taskId" and "${dep.taskId}".',
            );
          }
          if (depState == 0 && tasksById.containsKey(dep.taskId)) {
            dfs(dep.taskId, startLine);
          }
        }
      }
      visitState[taskId] = 2;
    }

    for (final item in state.tasksWithMeta) {
      if ((visitState[item.task.id] ?? 0) == 0) {
        dfs(item.task.id, item.blockedLine);
      }
    }
  }

  /// Validates that every referenced `<label-id>` matches a declared `label` block (`UnknownLabelReference`).
  static void _validateLabelReferences(TdfParserState state) {
    for (final ref in state.labelReferences) {
      if (!state.labelIds.contains(ref.labelId)) {
        TdfDirectiveParser.fail(
          TdfErrorKind.unknownLabelReference,
          ref.line,
          'Task references unknown <label-id> "${ref.labelId}".',
        );
      }
    }
  }

  /// Validates that every referenced `<location-id>` in `condition location` matches a declared root `location` block (`UnknownLocationReference`).
  static void _validateLocationReferences(TdfParserState state) {
    for (final ref in state.locationReferences) {
      if (!state.locationIds.contains(ref.locationId)) {
        TdfDirectiveParser.fail(
          TdfErrorKind.unknownLocationReference,
          ref.line,
          'Condition references unknown or deleted <location-id> "${ref.locationId}".',
        );
      }
    }
  }

  /// Validates `queue` membership against live open tasks (`spec/TDF_SPEC_0.6.0.md` Section 4.6 & 10.6).
  static void _validateQueueMembership(TdfParserState state) {
    if (state.isLegacy050 && !state.hasQueueBlock) {
      _synthesizeOmittedLegacy050Queue(state);
      return;
    }
    final tasksById = <String, ({TaskItem task, int headerLine})>{
      for (final item in state.tasksWithMeta)
        item.task.id: (task: item.task, headerLine: item.headerLine),
    };
    for (final entry in state.queueEntries) {
      final target = tasksById[entry.taskId];
      if (target == null || target.task.isCompleted) {
        TdfDirectiveParser.fail(
          TdfErrorKind.invalidQueueMembership,
          entry.line,
          'Queue entry "${entry.taskId}" must reference a live open task.',
        );
      }
    }
    if (state.isLegacy050) {
      final queuedSet = {for (final entry in state.queueEntries) entry.taskId};
      for (final item in state.tasksWithMeta) {
        if (!item.task.isCompleted) {
          if (item.legacyQueuedAt != null &&
              !queuedSet.contains(item.task.id)) {
            TdfDirectiveParser.fail(
              TdfErrorKind.invalidQueueMembership,
              item.headerLine,
              'Scheduled open 0.5.0 task "${item.task.id}" is missing from the queue block.',
            );
          }
          if (item.legacyQueuedAt == null && queuedSet.contains(item.task.id)) {
            final line = state.queueEntries
                .firstWhere((e) => e.taskId == item.task.id)
                .line;
            TdfDirectiveParser.fail(
              TdfErrorKind.invalidQueueMembership,
              line,
              'Queue entry "${item.task.id}" references an unscheduled Someday 0.5.0 task.',
            );
          }
        }
      }
    }
  }

  /// Synthesizes `state.queueBlock` when a legacy `0.5.0` input omitted an explicit `queue` block (`spec/TDF_SPEC_0.6.0.md` Section 10.6 Step 2).
  static void _synthesizeOmittedLegacy050Queue(TdfParserState state) {
    final priorityOpen =
        <({TaskItem task, DateTime queuedAt, int sourceIndex})>[];
    final regularOpen =
        <({TaskItem task, DateTime queuedAt, int sourceIndex})>[];
    var maxRevision = TdfCalendar.epochUtc;

    for (var i = 0; i < state.tasksWithMeta.length; i++) {
      final item = state.tasksWithMeta[i];
      final queuedAt = item.legacyQueuedAt;
      if (item.task.isCompleted || queuedAt == null) {
        continue;
      }
      final rev = item.task.effectiveModifiedAt;
      if (rev.isAfter(maxRevision)) {
        maxRevision = rev;
      }
      final record = (task: item.task, queuedAt: queuedAt, sourceIndex: i);
      if (item.task.isPriority) {
        priorityOpen.add(record);
      } else {
        regularOpen.add(record);
      }
    }

    int compareLegacyQueued(
      ({TaskItem task, DateTime queuedAt, int sourceIndex}) a,
      ({TaskItem task, DateTime queuedAt, int sourceIndex}) b,
    ) {
      final cmp = a.queuedAt.compareTo(b.queuedAt);
      return cmp != 0 ? cmp : a.sourceIndex.compareTo(b.sourceIndex);
    }

    priorityOpen.sort(compareLegacyQueued);
    regularOpen.sort(compareLegacyQueued);

    final orderedIds = <String>[
      for (final item in priorityOpen) item.task.id,
      for (final item in regularOpen) item.task.id,
    ];
    if (orderedIds.isNotEmpty) {
      state.queueBlock = TdfQueueBlock(
        modifiedAt: maxRevision,
        taskIds: orderedIds,
      );
    }
  }
}
