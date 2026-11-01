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
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../l10n/tier_localization_extension.dart';
import '../models/task_board.dart';
import '../models/task_item.dart';
import '../models/task_tier.dart';
import '../providers/task_providers.dart';
import 'settings_screen.dart';
import 'widgets/quick_add_bar.dart';
import 'widgets/task_tile.dart';

/// Primary Material 3 board screen for TierTask across Linux, Android, and Windows.
class HomeScreen extends ConsumerWidget {
  /// Creates a [HomeScreen] widget.
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardAsync = ref.watch(taskNotifierProvider);
    final isConfigured = ref.watch(
      webDavConfigProvider.select(
        (configAsync) => configAsync.asData?.value.isConfigured ?? false,
      ),
    );
    final syncState = ref.watch(syncStateProvider);
    final errorMessage = syncState.errorMessage;

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: _buildAppBar(context, ref, syncState.isSyncing),
        body: Column(
          children: [
            if (!isConfigured)
              _UnconfiguredBanner(onConfigure: () => _openSettings(context)),
            if (errorMessage != null)
              _SyncErrorBanner(
                message: errorMessage,
                onDismiss: () =>
                    ref.read(syncStateProvider.notifier).clearError(),
              ),
            Expanded(
              child: _BoardContentView(
                boardAsync: boardAsync,
                onOpenSettings: () => _openSettings(context),
                onRetry: () =>
                    ref.read(taskNotifierProvider.notifier).syncFromRemote(),
              ),
            ),
            const QuickAddBar(),
          ],
        ),
      ),
    );
  }

  /// Builds the localized [AppBar] with sync, Markdown preview, settings, and tier tabs.
  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    bool isSyncing,
  ) {
    final localizations = AppLocalizations.of(context);
    return AppBar(
      title: Text(
        localizations.appTitle,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      actions: [
        if (isSyncing)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          IconButton(
            tooltip: localizations.tooltipSyncWebDav,
            icon: const Icon(Icons.sync_rounded),
            onPressed: () =>
                ref.read(taskNotifierProvider.notifier).syncFromRemote(),
          ),
        IconButton(
          tooltip: localizations.tooltipMarkdownPreview,
          icon: const Icon(Icons.code_rounded),
          onPressed: () => _showMarkdownPreviewDialog(context, ref),
        ),
        IconButton(
          tooltip: localizations.tooltipSettings,
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => _openSettings(context),
        ),
      ],
      bottom: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: [
          Tab(text: localizations.tabFocusAndReady),
          Tab(text: localizations.tierName(TaskTier.planned)),
          Tab(text: localizations.tierName(TaskTier.blocked)),
          Tab(text: localizations.tierName(TaskTier.someday)),
          Tab(text: localizations.tierName(TaskTier.completed)),
        ],
      ),
    );
  }

  /// Pushes [SettingsScreen] onto the navigation stack.
  void _openSettings(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  /// Displays a dialog containing the serialized Markdown representation of the board.
  void _showMarkdownPreviewDialog(BuildContext context, WidgetRef ref) {
    final board =
        ref.read(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    final localizations = AppLocalizations.of(context);
    final markdown = ref
        .read(markdownServiceProvider)
        .serialize(board, tierLabelBuilder: localizations.tierName);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.markdownPreviewTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              markdown,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(localizations.actionClose),
          ),
        ],
      ),
    );
  }
}

/// Switches between loading, error, and tabbed board content views.
class _BoardContentView extends StatelessWidget {
  /// Creates a [_BoardContentView].
  const _BoardContentView({
    required this.boardAsync,
    required this.onRetry,
    required this.onOpenSettings,
  });

  /// Asynchronous board state.
  final AsyncValue<TaskBoard> boardAsync;

  /// Callback to open settings.
  final VoidCallback onOpenSettings;

  /// Callback to retry remote synchronization.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return boardAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorStateView(
        error: error.toString(),
        onRetry: onRetry,
        onOpenSettings: onOpenSettings,
      ),
      data: (board) => TabBarView(
        children: [
          _MainBoardTab(board: board),
          _SingleTierListView(board: board, tier: TaskTier.planned),
          _SingleTierListView(board: board, tier: TaskTier.blocked),
          _SingleTierListView(board: board, tier: TaskTier.someday),
          _SingleTierListView(board: board, tier: TaskTier.completed),
        ],
      ),
    );
  }
}

/// Full-screen error state view when initial WebDAV synchronization fails.
class _ErrorStateView extends StatelessWidget {
  /// Creates an [_ErrorStateView].
  const _ErrorStateView({
    required this.error,
    required this.onRetry,
    required this.onOpenSettings,
  });

  /// Error description string.
  final String error;

  /// Callback to open settings.
  final VoidCallback onOpenSettings;

  /// Callback to retry synchronization.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              localizations.syncErrorTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(localizations.actionSettings),
                ),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(localizations.actionRetry),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Collapsible card section for secondary tiers (`3` through `6`) on the main board tab.
class _ExpandableTierSection extends StatelessWidget {
  /// Creates an [_ExpandableTierSection].
  const _ExpandableTierSection({
    required this.tier,
    required this.tasks,
    required this.icon,
    this.initiallyExpanded = false,
  });

  /// Leading icon for the tier header.
  final IconData icon;

  /// Whether the expansion tile starts expanded.
  final bool initiallyExpanded;

  /// Tasks belonging to [tier].
  final List<TaskItem> tasks;

  /// Tier represented by this section.
  final TaskTier tier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final localizations = AppLocalizations.of(context);
    final heading = localizations.tierName(tier);

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(icon),
        title: Text(
          heading,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          localizations.tierDescription(tier),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Badge.count(
          count: tasks.length,
          backgroundColor: colorScheme.secondaryContainer,
          textColor: colorScheme.onSecondaryContainer,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                localizations.emptySectionEntries(heading),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final task in tasks)
              TaskTile(
                key: ValueKey('${tier.name}_${task.id}'),
                task: task,
                tier: tier,
              ),
        ],
      ),
    );
  }
}

/// Highlighted container displaying Tier 1 (`# [1] Focus`) tasks.
class _FocusHeroSection extends StatelessWidget {
  /// Creates a [_FocusHeroSection].
  const _FocusHeroSection({required this.tasks});

  /// Tasks currently in Tier 1 (`focus`).
  final List<TaskItem> tasks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final localizations = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            tier: TaskTier.focus,
            count: tasks.length,
            softLimit: TaskBoard.focusSoftLimit,
            icon: Icons.bolt_rounded,
            accentColor: colorScheme.primary,
          ),
          const SizedBox(height: 8),
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                localizations.emptyFocusHint,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final task in tasks)
              TaskTile(
                key: ValueKey('focus_${task.id}'),
                task: task,
                tier: TaskTier.focus,
                isProminent: true,
              ),
        ],
      ),
    );
  }
}

/// Primary board tab showing Tier 1 (`Focus`), Tier 2 (`Ready`), and expandable Tiers `3`–`6`.
class _MainBoardTab extends StatelessWidget {
  /// Creates a [_MainBoardTab] for [board].
  const _MainBoardTab({required this.board});

  /// Current task board snapshot.
  final TaskBoard board;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _FocusHeroSection(tasks: board.focus),
        const SizedBox(height: 20),
        _ReadySection(tasks: board.ready),
        const SizedBox(height: 20),
        _ExpandableTierSection(
          tier: TaskTier.planned,
          tasks: board.planned,
          icon: Icons.list_alt_rounded,
          initiallyExpanded: board.planned.isNotEmpty,
        ),
        const SizedBox(height: 8),
        _ExpandableTierSection(
          tier: TaskTier.blocked,
          tasks: board.blocked,
          icon: Icons.block_rounded,
          initiallyExpanded: board.blocked.isNotEmpty,
        ),
        const SizedBox(height: 8),
        _ExpandableTierSection(
          tier: TaskTier.someday,
          tasks: board.someday,
          icon: Icons.lightbulb_outline_rounded,
        ),
        const SizedBox(height: 8),
        _ExpandableTierSection(
          tier: TaskTier.completed,
          tasks: board.completed,
          icon: Icons.check_circle_outline_rounded,
        ),
      ],
    );
  }
}

/// Section displaying Tier 2 (`# [2] Ready`) tasks on the main board tab.
class _ReadySection extends StatelessWidget {
  /// Creates a [_ReadySection].
  const _ReadySection({required this.tasks});

  /// Tasks currently in Tier 2 (`ready`).
  final List<TaskItem> tasks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final localizations = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          tier: TaskTier.ready,
          count: tasks.length,
          softLimit: TaskBoard.readySoftLimit,
          icon: Icons.playlist_play_rounded,
          accentColor: colorScheme.secondary,
        ),
        const SizedBox(height: 6),
        if (tasks.isEmpty)
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                localizations.emptyReadyHint,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (final task in tasks)
            TaskTile(
              key: ValueKey('ready_${task.id}'),
              task: task,
              tier: TaskTier.ready,
            ),
      ],
    );
  }
}

/// Section header displaying the localized tier name, description, and WIP counter pill.
class _SectionHeader extends StatelessWidget {
  /// Creates a [_SectionHeader].
  const _SectionHeader({
    required this.tier,
    required this.count,
    required this.softLimit,
    required this.icon,
    required this.accentColor,
  });

  /// Icon accent color.
  final Color accentColor;

  /// Number of tasks currently in [tier].
  final int count;

  /// Leading section icon.
  final IconData icon;

  /// Optional soft WIP limit for [tier].
  final int? softLimit;

  /// Target tier displayed by this header.
  final TaskTier tier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final localizations = AppLocalizations.of(context);
    final limit = softLimit;
    final isOverSoftLimit = limit != null && count > limit;

    return Row(
      children: [
        Icon(icon, color: accentColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizations.tierName(tier),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                localizations.tierDescription(tier),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isOverSoftLimit
                ? colorScheme.tertiaryContainer
                : colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            limit != null ? '$count / $limit' : '$count',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isOverSoftLimit
                  ? colorScheme.onTertiaryContainer
                  : colorScheme.onSecondaryContainer,
            ),
          ),
        ),
      ],
    );
  }
}

/// Dedicated list view for a single secondary tier tab (`3` through `6`).
class _SingleTierListView extends StatelessWidget {
  /// Creates a [_SingleTierListView] for [tier].
  const _SingleTierListView({required this.board, required this.tier});

  /// Current task board.
  final TaskBoard board;

  /// Tier displayed on this tab.
  final TaskTier tier;

  @override
  Widget build(BuildContext context) {
    final tasks = board.tasksForTier(tier);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final localizations = AppLocalizations.of(context);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: tasks.isEmpty ? 2 : tasks.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SectionHeader(
              tier: tier,
              count: tasks.length,
              softLimit: tier.softLimit,
              icon: Icons.folder_open_rounded,
              accentColor: colorScheme.primary,
            ),
          );
        }
        if (tasks.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Text(
                localizations.tierEmptyHint(tier),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final task = tasks[index - 1];
        return TaskTile(
          key: ValueKey('tab_${tier.name}_${task.id}'),
          task: task,
          tier: tier,
        );
      },
    );
  }
}

/// Dismissible error banner shown when a background WebDAV sync operation fails.
class _SyncErrorBanner extends StatelessWidget {
  /// Creates a [_SyncErrorBanner].
  const _SyncErrorBanner({required this.message, required this.onDismiss});

  /// Error message to display.
  final String message;

  /// Callback invoked when the dismiss icon is pressed.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 20,
              color: colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onErrorContainer,
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: colorScheme.onErrorContainer,
              ),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner shown when WebDAV synchronization has not yet been configured.
class _UnconfiguredBanner extends StatelessWidget {
  /// Creates an [_UnconfiguredBanner].
  const _UnconfiguredBanner({required this.onConfigure});

  /// Callback to navigate to [SettingsScreen].
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);

    return Material(
      color: colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 20,
              color: colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                localizations.unconfiguredBannerText,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: onConfigure,
              child: Text(localizations.actionConfigure),
            ),
          ],
        ),
      ),
    );
  }
}
