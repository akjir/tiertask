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

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/tier_localization_extension.dart';
import '../../models/task_board.dart';
import '../../models/task_item.dart';
import '../../models/task_tier.dart';
import 'tier_task_pill.dart';

/// Scrollable search view displaying all tasks across tiers `1` to `6`
/// (`Focus` through `Completed`) under `ALL TASKS`.
class AllTasksSearchView extends StatelessWidget {
  /// Creates an [AllTasksSearchView].
  const AllTasksSearchView({
    super.key,
    required this.board,
    required this.searchQuery,
    this.activeFilterLabelId,
  });

  /// Active label filter ID when a label filter is selected.
  final String? activeFilterLabelId;

  /// Current task board snapshot (already evaluated for the active label
  /// context if one is selected).
  final TaskBoard board;

  /// Active search query string for filtering tasks.
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final entries = _collectFilteredEntries(board, searchQuery);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
      itemCount: entries.isEmpty ? 2 : entries.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 36),
            child: LandingSectionLabel(title: localizations.sectionAllTasks),
          );
        }
        if (entries.isEmpty) {
          return EmptyTierCard(
            message: localizations.emptySectionEntries(
              localizations.sectionAllTasks,
            ),
          );
        }
        final entry = entries[index - 1];
        return _TierTaskListTile(
          task: entry.task,
          tier: entry.tier,
          activeFilterLabelId: activeFilterLabelId,
        );
      },
    );
  }

  /// Appends tasks from [tasks] matching [normalizedQuery] to [entries] tagged
  /// with [tier].
  void _appendMatchingTierEntries({
    required List<({TaskItem task, TaskTier tier})> entries,
    required List<TaskItem> tasks,
    required TaskTier tier,
    required String normalizedQuery,
  }) {
    for (final task in tasks) {
      if (normalizedQuery.isEmpty ||
          task.title.toLowerCase().contains(normalizedQuery)) {
        entries.add((task: task, tier: tier));
      }
    }
  }

  /// Collects all tasks across tiers `1` to `6` (`Focus` through `Completed`)
  /// filtered by [query].
  List<({TaskItem task, TaskTier tier})> _collectFilteredEntries(
    TaskBoard board,
    String query,
  ) {
    final trimmed = query.trim().toLowerCase();
    final entries = <({TaskItem task, TaskTier tier})>[];
    for (final tier in TaskTier.values) {
      _appendMatchingTierEntries(
        entries: entries,
        tasks: board.tasksForTier(tier),
        tier: tier,
        normalizedQuery: trimmed,
      );
    }
    return entries;
  }
}

/// Placeholder card shown when a tier's task list is empty.
class EmptyTierCard extends StatelessWidget {
  /// Creates an [EmptyTierCard].
  const EmptyTierCard({super.key, required this.message});

  /// Empty-state message text.
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 15,
        ),
      ),
    );
  }
}

/// Uppercase muted section heading label on the tier panes.
class LandingSectionLabel extends StatelessWidget {
  /// Creates a [LandingSectionLabel].
  const LandingSectionLabel({super.key, required this.title});

  /// Section title text.
  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}

/// Scrollable tier pane body rendering the uppercase section label and
/// minimalist task pills.
class TierScrollView extends StatefulWidget {
  /// Creates a [TierScrollView].
  const TierScrollView({
    super.key,
    required this.board,
    required this.tier,
    this.activeFilterLabelId,
  });

  /// Active label filter ID when a label filter is selected.
  final String? activeFilterLabelId;

  /// Current task board snapshot.
  final TaskBoard board;

  /// [TaskTier] displayed on this pane.
  final TaskTier tier;

  @override
  State<TierScrollView> createState() => _TierScrollViewState();
}

/// Header block inside [TierScrollView] displaying the uppercase tier section
/// label.
class _TierPaneHeader extends StatelessWidget {
  /// Creates a [_TierPaneHeader].
  const _TierPaneHeader({required this.tier});

  /// Active [TaskTier] pane.
  final TaskTier tier;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 36),
      child: LandingSectionLabel(title: localizations.tierSectionTitle(tier)),
    );
  }
}

/// State for [TierScrollView] tracking newly upgraded tasks entering
/// [TierScrollView.tier].
class _TierScrollViewState extends State<TierScrollView> {
  /// Task IDs that entered [TierScrollView.tier] during the most recent board
  /// update.
  Set<String> _enteringTaskIds = const <String>{};

  /// Task IDs currently present on [TierScrollView.tier].
  late Set<String> _knownTaskIds;

  @override
  void initState() {
    super.initState();
    _knownTaskIds = _collectTaskIds(widget.board.tasksForTier(widget.tier));
  }

  @override
  void didUpdateWidget(covariant TierScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentTasks = widget.board.tasksForTier(widget.tier);
    if (oldWidget.tier != widget.tier) {
      _knownTaskIds = _collectTaskIds(currentTasks);
      _enteringTaskIds = const <String>{};
      return;
    }
    if (oldWidget.board == widget.board) {
      return;
    }
    final newlyEntered = <String>{
      for (final task in currentTasks)
        if (!_knownTaskIds.contains(task.id)) task.id,
    };
    _knownTaskIds = _collectTaskIds(currentTasks);
    if (newlyEntered.isNotEmpty) {
      _enteringTaskIds = newlyEntered;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tier = widget.tier;
    final tasks = widget.board.tasksForTier(tier);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
      itemCount: tasks.isEmpty ? 2 : tasks.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _TierPaneHeader(tier: tier);
        }
        if (tasks.isEmpty) {
          return EmptyTierCard(message: localizations.tierEmptyHint(tier));
        }
        final task = tasks[index - 1];
        return _TierTaskListTile(
          animateEntry: _enteringTaskIds.contains(task.id),
          task: task,
          tier: tier,
          activeFilterLabelId: widget.activeFilterLabelId,
        );
      },
    );
  }

  /// Collects the task IDs present in [tasks].
  static Set<String> _collectTaskIds(List<TaskItem> tasks) {
    return <String>{for (final task in tasks) task.id};
  }
}

/// Task row wrapper inside [AllTasksSearchView] and [TierScrollView] that
/// configures [TierTaskPill] for [tier].
class _TierTaskListTile extends StatelessWidget {
  /// Creates a [_TierTaskListTile].
  const _TierTaskListTile({
    required this.task,
    required this.tier,
    this.activeFilterLabelId,
    this.animateEntry = false,
  });

  final String? activeFilterLabelId;
  final bool animateEntry;
  final TaskItem task;
  final TaskTier tier;

  @override
  Widget build(BuildContext context) {
    return TierTaskPill(
      key: ValueKey('tier_pill_${tier.name}_${task.id}'),
      animateEntry: animateEntry,
      task: task,
      canDowngrade:
          tier == TaskTier.focus ||
          tier == TaskTier.ready ||
          tier == TaskTier.planned,
      isCompleted: tier == TaskTier.completed,
      activeFilterLabelId: activeFilterLabelId,
    );
  }
}
