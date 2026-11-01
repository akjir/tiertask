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
import '../models/task_tier.dart';

/// Dependency-free, line-by-line Markdown parser and serializer for TierTask (`tiertask.md`).
class MarkdownService {
  /// Creates a stateless [MarkdownService].
  const MarkdownService();

  static final RegExp _completedWithDatePattern = RegExp(
    r'^-\s*\[[xX]\]\s*(\d{4}-\d{2}-\d{2})\s+(.*)$',
  );

  static final RegExp _completedWithoutDatePattern = RegExp(
    r'^-\s*\[[xX]\]\s*(.*)$',
  );

  static final RegExp _headingPrefixPattern = RegExp(r'^#+\s*');

  static final RegExp _incompleteTaskPattern = RegExp(r'^-\s*\[\s?\]\s*(.*)$');

  /// Parses a raw Markdown string into an immutable [TaskBoard] instance.
  ///
  /// Matches sections strictly by their tier number (`[1]` through `[6]` or `(1)` through `(6)`),
  /// ignores the trailing heading label text, and initializes any missing tiers as empty lists.
  TaskBoard parse(String markdown) {
    final buckets = _TierBuckets();
    TaskTier? currentTier;
    final lines = markdown.split('\n');

    for (final rawLine in lines) {
      currentTier = _processMarkdownLine(rawLine, currentTier, buckets);
    }

    return buckets.toBoard();
  }

  /// Serializes an immutable [TaskBoard] into the canonical 6-section Markdown format (`1` to `6`).
  ///
  /// Uses [tierLabelBuilder] when provided to localize the heading labels (`# [1] Focus` / `# [1] Fokus`),
  /// and guarantees that all 6 tiers are written even if absent in the original file.
  String serialize(
    TaskBoard board, {
    String Function(TaskTier tier)? tierLabelBuilder,
  }) {
    final buffer = StringBuffer();
    const tiers = TaskTier.values;

    for (var i = 0; i < tiers.length; i++) {
      final tier = tiers[i];
      buffer.writeln(tier.formatHeading(tierLabelBuilder?.call(tier)));
      _writeTierTasks(buffer, board.tasksForTier(tier), tier);

      if (i < tiers.length - 1) {
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  /// Parses an indented Markdown line into a [SubtaskItem], or `null` if invalid.
  SubtaskItem? _parseSubtaskLine(String line) {
    final parsed = _parseTaskLine(line, TaskTier.planned);
    if (parsed == null) {
      return null;
    }
    return SubtaskItem(title: parsed.title, isCompleted: parsed.isCompleted);
  }

  /// Parses a single Markdown task line under [tier] into a [TaskItem].
  TaskItem? _parseTaskLine(String line, TaskTier tier) {
    final completedWithDateMatch = _completedWithDatePattern.firstMatch(line);
    if (completedWithDateMatch != null) {
      final rawDate = completedWithDateMatch.group(1);
      final rawTitle = completedWithDateMatch.group(2);
      if (rawDate == null || rawTitle == null) return null;
      final title = rawTitle.trim();
      if (title.isEmpty) return null;

      final parsedDate = TaskItem.tryParseIsoDate(rawDate);
      return TaskItem(title: title, isCompleted: true, completedAt: parsedDate);
    }

    final completedNoDateMatch = _completedWithoutDatePattern.firstMatch(line);
    if (completedNoDateMatch != null) {
      final rawTitle = completedNoDateMatch.group(1);
      if (rawTitle == null) return null;
      final title = rawTitle.trim();
      if (title.isEmpty) return null;
      return TaskItem(title: title, isCompleted: true);
    }

    final incompleteMatch = _incompleteTaskPattern.firstMatch(line);
    if (incompleteMatch != null) {
      final rawTitle = incompleteMatch.group(1);
      if (rawTitle == null) return null;
      final title = rawTitle.trim();
      if (title.isEmpty) return null;
      return TaskItem(title: title, isCompleted: tier == TaskTier.completed);
    }

    if (line.startsWith('- ')) {
      final title = line.substring(2).trim();
      if (title.isEmpty) return null;
      return TaskItem(title: title, isCompleted: tier == TaskTier.completed);
    }

    return null;
  }

  /// Processes a single [rawLine] during Markdown parsing and returns the active [TaskTier].
  TaskTier? _processMarkdownLine(
    String rawLine,
    TaskTier? currentTier,
    _TierBuckets buckets,
  ) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      return currentTier;
    }

    if (line.startsWith('#')) {
      final headingText = line.replaceFirst(_headingPrefixPattern, '').trim();
      return TaskTier.fromHeading(headingText);
    }

    if (currentTier == null || !line.startsWith('-')) {
      return currentTier;
    }

    final isIndented = rawLine.startsWith('  ') || rawLine.startsWith('\t');
    if (isIndented && buckets.hasTasksIn(currentTier)) {
      if (_parseSubtaskLine(line) case final subtask?) {
        buckets.appendSubtask(currentTier, subtask);
      }
      return currentTier;
    }

    if (_parseTaskLine(line, currentTier) case final parsedTask?) {
      buckets.appendTask(currentTier, parsedTask);
    }
    return currentTier;
  }

  /// Writes all [subtasks] of a task to [buffer].
  static void _writeSubtasks(StringBuffer buffer, List<SubtaskItem> subtasks) {
    for (final subtask in subtasks) {
      buffer.writeln(subtask.toMarkdownLine());
    }
  }

  /// Writes all [tasks] for [tier] to [buffer].
  static void _writeTierTasks(
    StringBuffer buffer,
    List<TaskItem> tasks,
    TaskTier tier,
  ) {
    final isCompletedTier = tier == TaskTier.completed;
    for (final task in tasks) {
      buffer.writeln(task.toMarkdownLine(inCompleted: isCompletedTier));
      _writeSubtasks(buffer, task.subtasks);
    }
  }
}

/// Mutable accumulator lists used while parsing a Markdown document into a [TaskBoard].
class _TierBuckets {
  /// Creates empty [_TierBuckets].
  _TierBuckets();

  final List<TaskItem> _blocked = <TaskItem>[];
  final List<TaskItem> _completed = <TaskItem>[];
  final List<TaskItem> _focus = <TaskItem>[];
  final List<TaskItem> _planned = <TaskItem>[];
  final List<TaskItem> _ready = <TaskItem>[];
  final List<TaskItem> _someday = <TaskItem>[];

  /// Appends [subtask] to the most recently added task in [tier].
  void appendSubtask(TaskTier tier, SubtaskItem subtask) {
    final list = _listForTier(tier);
    if (list.isEmpty) {
      return;
    }
    final lastTask = list.last;
    list[list.length - 1] = lastTask.copyWith(
      subtasks: [...lastTask.subtasks, subtask],
    );
  }

  /// Appends [task] to [tier].
  void appendTask(TaskTier tier, TaskItem task) {
    _listForTier(tier).add(task);
  }

  /// Returns whether [tier] already contains at least one parsed task.
  bool hasTasksIn(TaskTier tier) => _listForTier(tier).isNotEmpty;

  /// Builds an immutable [TaskBoard] from the accumulated tier lists.
  TaskBoard toBoard() {
    return TaskBoard(
      focus: _focus,
      ready: _ready,
      planned: _planned,
      blocked: _blocked,
      someday: _someday,
      completed: _completed,
    );
  }

  /// Returns the mutable list for [tier].
  List<TaskItem> _listForTier(TaskTier tier) {
    return switch (tier) {
      TaskTier.focus => _focus,
      TaskTier.ready => _ready,
      TaskTier.planned => _planned,
      TaskTier.blocked => _blocked,
      TaskTier.someday => _someday,
      TaskTier.completed => _completed,
    };
  }
}
