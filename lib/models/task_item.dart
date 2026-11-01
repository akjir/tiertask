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

/// Immutable representation of a single subtask step belonging to a [TaskItem].
@immutable
class SubtaskItem {
  /// Creates a [SubtaskItem] with [title] and optional [isCompleted] state.
  const SubtaskItem({required this.title, this.isCompleted = false});

  /// Whether the subtask step is marked as completed (`[x]`).
  final bool isCompleted;

  /// Plain-text subtask description.
  final String title;

  /// Serializes this subtask into an indented Markdown checklist line.
  String toMarkdownLine() {
    final cleanTitle = title.trim();
    return isCompleted ? '  - [x] $cleanTitle' : '  - [ ] $cleanTitle';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SubtaskItem &&
        other.title == title &&
        other.isCompleted == isCompleted;
  }

  @override
  int get hashCode => Object.hash(title, isCompleted);

  @override
  String toString() => toMarkdownLine();
}

/// Immutable representation of a single task item in TierTask.
@immutable
class TaskItem {
  /// Creates a [TaskItem] with optional [id], [isPriority], [subtasks], and [completedAt].
  TaskItem({
    String? id,
    required this.title,
    this.isCompleted = false,
    this.isPriority = false,
    this.completedAt,
    List<SubtaskItem> subtasks = const [],
  }) : id = id ?? _nextId(),
       subtasks = List<SubtaskItem>.unmodifiable(subtasks);

  static int _idCounter = 0;

  /// Completion date (`YYYY-MM-DD`) when located in Tier 6 (`# [6] Completed`).
  final DateTime? completedAt;

  /// Internal runtime identifier (never persisted to the Markdown file).
  final String id;

  /// Whether the task is marked as completed (`[x]`).
  final bool isCompleted;

  /// Whether the task was created with high priority.
  final bool isPriority;

  /// Ordered checklist subtasks belonging to this task.
  final List<SubtaskItem> subtasks;

  /// Plain-text task description.
  final String title;

  /// Returns a copy of this task with the provided fields updated.
  TaskItem copyWith({
    String? id,
    String? title,
    bool? isCompleted,
    bool? isPriority,
    DateTime? completedAt,
    List<SubtaskItem>? subtasks,
    bool clearCompletedAt = false,
  }) {
    return TaskItem(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      isPriority: isPriority ?? this.isPriority,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      subtasks: subtasks ?? this.subtasks,
    );
  }

  /// Formats [date] as an ISO-8601 date string (`YYYY-MM-DD`).
  static String formatIsoDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// Creates an active (incomplete) task with no completion timestamp.
  TaskItem toActive() {
    return TaskItem(
      id: id,
      title: title,
      isCompleted: false,
      isPriority: isPriority,
      completedAt: null,
      subtasks: subtasks,
    );
  }

  /// Creates a completed task stamped with [completionDate] (normalized to UTC date).
  TaskItem toCompleted(DateTime completionDate) {
    final normalized = DateTime.utc(
      completionDate.year,
      completionDate.month,
      completionDate.day,
    );
    return TaskItem(
      id: id,
      title: title,
      isCompleted: true,
      isPriority: isPriority,
      completedAt: normalized,
      subtasks: subtasks,
    );
  }

  /// Serializes this task into a single Markdown list item line.
  String toMarkdownLine({required bool inCompleted}) {
    final cleanTitle = title.trim();
    if (inCompleted || isCompleted) {
      if (completedAt case final completionDate?) {
        return '- [x] ${formatIsoDate(completionDate)} $cleanTitle';
      }
      return '- [x] $cleanTitle';
    }
    return '- [ ] $cleanTitle';
  }

  /// Parses a strict ISO-8601 date string (`YYYY-MM-DD`) into a UTC [DateTime],
  /// returning `null` if the format or calendar date is invalid.
  static DateTime? tryParseIsoDate(String rawDate) {
    if (rawDate.length != 10 ||
        rawDate.codeUnitAt(4) != 0x2D ||
        rawDate.codeUnitAt(7) != 0x2D) {
      return null;
    }
    final year = int.tryParse(rawDate.substring(0, 4));
    final month = int.tryParse(rawDate.substring(5, 7));
    final day = int.tryParse(rawDate.substring(8, 10));
    if (year == null || month == null || day == null) {
      return null;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    final candidate = DateTime.utc(year, month, day);
    if (candidate.year != year ||
        candidate.month != month ||
        candidate.day != day) {
      return null;
    }
    return candidate;
  }

  /// Generates a unique runtime task identifier.
  static String _nextId() {
    _idCounter++;
    return 'task_${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  /// Compares two optional dates by UTC calendar year, month, and day.
  static bool _sameDate(DateTime? first, DateTime? second) {
    if (first == null && second == null) return true;
    if (first == null || second == null) return false;
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskItem &&
        other.id == id &&
        other.title == title &&
        other.isCompleted == isCompleted &&
        other.isPriority == isPriority &&
        _sameDate(other.completedAt, completedAt) &&
        listEquals(other.subtasks, subtasks);
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    isCompleted,
    isPriority,
    completedAt?.year,
    completedAt?.month,
    completedAt?.day,
    Object.hashAll(subtasks),
  );

  @override
  String toString() => toMarkdownLine(inCompleted: isCompleted);
}
