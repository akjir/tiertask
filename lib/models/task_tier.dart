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

/// Represents the six strictly ordered priority and status tiers (`1` to `6`) in TierTask.
enum TaskTier {
  /// Tier 1: Active top-priority focus tasks (soft limit: 3).
  focus(
    number: 1,
    defaultLabel: 'Focus',
    softLimit: 3,
    isAutoPullTarget: true,
    isStatic: false,
  ),

  /// Tier 2: Tasks ready to pull into Focus (soft limit: 5).
  ready(
    number: 2,
    defaultLabel: 'Ready',
    softLimit: 5,
    isAutoPullTarget: true,
    isStatic: false,
  ),

  /// Tier 3: Active backlog feeding Ready automatically.
  planned(
    number: 3,
    defaultLabel: 'Planned',
    softLimit: null,
    isAutoPullTarget: false,
    isStatic: false,
  ),

  /// Tier 4: Static tier for tasks blocked by external events.
  blocked(
    number: 4,
    defaultLabel: 'Blocked',
    softLimit: null,
    isAutoPullTarget: false,
    isStatic: true,
  ),

  /// Tier 5: Static tier for future ideas excluded from auto-pull.
  someday(
    number: 5,
    defaultLabel: 'Someday',
    softLimit: null,
    isAutoPullTarget: false,
    isStatic: true,
  ),

  /// Tier 6: Static archive of completed tasks retained for 30 days.
  completed(
    number: 6,
    defaultLabel: 'Completed',
    softLimit: null,
    isAutoPullTarget: false,
    isStatic: true,
  );

  /// Creates a [TaskTier] definition.
  const TaskTier({
    required this.number,
    required this.defaultLabel,
    required this.softLimit,
    required this.isAutoPullTarget,
    required this.isStatic,
  });

  /// Active (non-completed) tiers (`1` through `5`) where tasks can be added or restored.
  static const List<TaskTier> activeTiers = [
    TaskTier.focus,
    TaskTier.ready,
    TaskTier.planned,
    TaskTier.blocked,
    TaskTier.someday,
  ];

  static final RegExp _tierHeadingPattern = RegExp(
    r'^[\[\(]([1-6])[\]\)](\s+.*)?$',
  );

  /// Numeric tier identifier (`1` through `6`).
  final int number;

  /// Default English label for this tier.
  final String defaultLabel;

  /// Soft WIP limit (`3` for Focus, `5` for Ready, `null` for others).
  final int? softLimit;

  /// Whether this tier automatically pulls tasks from lower active tiers.
  final bool isAutoPullTarget;

  /// Whether this tier is static (excluded from automatic pull operations).
  final bool isStatic;

  /// Default English Markdown H1 line (`# [<number>] <defaultLabel>`).
  String get markdownHeading => formatHeading();

  /// Formats the Markdown H1 heading (`# [<number>] <label>`) using [label] or [defaultLabel].
  String formatHeading([String? label]) {
    final effectiveLabel = (label == null || label.trim().isEmpty)
        ? defaultLabel
        : label.trim();
    return '# [$number] $effectiveLabel';
  }

  /// Resolves a [TaskTier] from a raw H1 heading text (after `#`) by matching
  /// the leading `[1]`–`[6]` or `(1)`–`(6)` tier number and ignoring any label text.
  static TaskTier? fromHeading(String rawHeading) {
    final cleaned = rawHeading.trim();
    final match = _tierHeadingPattern.firstMatch(cleaned);
    if (match == null) {
      return null;
    }
    final rawNumber = match.group(1);
    if (rawNumber == null) {
      return null;
    }
    final parsedNumber = int.tryParse(rawNumber);
    if (parsedNumber == null) {
      return null;
    }
    return fromNumber(parsedNumber);
  }

  /// Resolves a [TaskTier] from its numeric identifier (`1` through `6`).
  static TaskTier? fromNumber(int number) {
    return switch (number) {
      1 => TaskTier.focus,
      2 => TaskTier.ready,
      3 => TaskTier.planned,
      4 => TaskTier.blocked,
      5 => TaskTier.someday,
      6 => TaskTier.completed,
      _ => null,
    };
  }
}
