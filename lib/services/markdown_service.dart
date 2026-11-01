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
    final focusTasks = <TaskItem>[];
    final readyTasks = <TaskItem>[];
    final plannedTasks = <TaskItem>[];
    final blockedTasks = <TaskItem>[];
    final somedayTasks = <TaskItem>[];
    final completedTasks = <TaskItem>[];

    TaskTier? currentTier;
    final lines = markdown.split('\n');

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      if (line.startsWith('#')) {
        final headingText = line.replaceFirst(_headingPrefixPattern, '').trim();
        currentTier = TaskTier.fromHeading(headingText);
        continue;
      }

      if (currentTier == null || !line.startsWith('-')) {
        continue;
      }

      if (_parseTaskLine(line, currentTier) case final parsedTask?) {
        _appendToBucket(
          currentTier,
          parsedTask,
          focusTasks: focusTasks,
          readyTasks: readyTasks,
          plannedTasks: plannedTasks,
          blockedTasks: blockedTasks,
          somedayTasks: somedayTasks,
          completedTasks: completedTasks,
        );
      }
    }

    return TaskBoard(
      focus: focusTasks,
      ready: readyTasks,
      planned: plannedTasks,
      blocked: blockedTasks,
      someday: somedayTasks,
      completed: completedTasks,
    );
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

  /// Appends [task] to the list matching [tier].
  void _appendToBucket(
    TaskTier tier,
    TaskItem task, {
    required List<TaskItem> focusTasks,
    required List<TaskItem> readyTasks,
    required List<TaskItem> plannedTasks,
    required List<TaskItem> blockedTasks,
    required List<TaskItem> somedayTasks,
    required List<TaskItem> completedTasks,
  }) {
    switch (tier) {
      case TaskTier.focus:
        focusTasks.add(task);
      case TaskTier.ready:
        readyTasks.add(task);
      case TaskTier.planned:
        plannedTasks.add(task);
      case TaskTier.blocked:
        blockedTasks.add(task);
      case TaskTier.someday:
        somedayTasks.add(task);
      case TaskTier.completed:
        completedTasks.add(task);
    }
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

  /// Writes all [tasks] for [tier] to [buffer].
  static void _writeTierTasks(
    StringBuffer buffer,
    List<TaskItem> tasks,
    TaskTier tier,
  ) {
    final isCompletedTier = tier == TaskTier.completed;
    for (final task in tasks) {
      buffer.writeln(task.toMarkdownLine(inCompleted: isCompletedTier));
    }
  }
}
