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

/// Dependency-free, line-by-line Markdown parser and serializer for TierTask (`tiertask.md` / `t2.md`).
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
  /// Preserves task order within each of the 6 German H1 sections and gracefully
  /// handles empty sections, CRLF line endings, or trailing whitespace.
  TaskBoard parse(String markdown) {
    final fokusTasks = <TaskItem>[];
    final bereitTasks = <TaskItem>[];
    final irgendwannTasks = <TaskItem>[];
    final blockiertTasks = <TaskItem>[];
    final geplantTasks = <TaskItem>[];
    final erledigtTasks = <TaskItem>[];

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
          fokusTasks: fokusTasks,
          bereitTasks: bereitTasks,
          irgendwannTasks: irgendwannTasks,
          blockiertTasks: blockiertTasks,
          geplantTasks: geplantTasks,
          erledigtTasks: erledigtTasks,
        );
      }
    }

    return TaskBoard(
      fokus: fokusTasks,
      bereit: bereitTasks,
      irgendwann: irgendwannTasks,
      blockiert: blockiertTasks,
      geplant: geplantTasks,
      erledigt: erledigtTasks,
    );
  }

  /// Serializes an immutable [TaskBoard] into the canonical 6-section Markdown format.
  String serialize(TaskBoard board) {
    final buffer = StringBuffer();
    const tiers = TaskTier.values;

    for (var i = 0; i < tiers.length; i++) {
      final tier = tiers[i];
      buffer.writeln(tier.markdownHeading);

      final tasks = board.tasksForTier(tier);
      for (final task in tasks) {
        buffer.writeln(
          task.toMarkdownLine(inErledigt: tier == TaskTier.erledigt),
        );
      }

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
    required List<TaskItem> fokusTasks,
    required List<TaskItem> bereitTasks,
    required List<TaskItem> irgendwannTasks,
    required List<TaskItem> blockiertTasks,
    required List<TaskItem> geplantTasks,
    required List<TaskItem> erledigtTasks,
  }) {
    switch (tier) {
      case TaskTier.fokus:
        fokusTasks.add(task);
      case TaskTier.bereit:
        bereitTasks.add(task);
      case TaskTier.irgendwann:
        irgendwannTasks.add(task);
      case TaskTier.blockiert:
        blockiertTasks.add(task);
      case TaskTier.geplant:
        geplantTasks.add(task);
      case TaskTier.erledigt:
        erledigtTasks.add(task);
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
      return TaskItem(title: title, isCompleted: tier == TaskTier.erledigt);
    }

    if (line.startsWith('- ')) {
      final title = line.substring(2).trim();
      if (title.isEmpty) return null;
      return TaskItem(title: title, isCompleted: tier == TaskTier.erledigt);
    }

    return null;
  }
}
