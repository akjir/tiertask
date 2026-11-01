import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task_board.dart';
import '../models/task_tier.dart';
import '../providers/task_providers.dart';
import 'settings_screen.dart';
import 'widgets/quick_add_bar.dart';
import 'widgets/task_tile.dart';

/// Main Material 3 screen for TierTask (T2).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardAsync = ref.watch(taskNotifierProvider);
    final configAsync = ref.watch(webDavConfigProvider);
    final syncState = ref.watch(syncStateProvider);
    final isConfigured = configAsync.asData?.value.isConfigured ?? false;

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'TierTask (T2)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            if (syncState.isSyncing)
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
                tooltip: 'Mit Nextcloud WebDAV synchronisieren',
                icon: const Icon(Icons.sync_rounded),
                onPressed: () {
                  ref.read(taskNotifierProvider.notifier).syncFromRemote();
                },
              ),
            IconButton(
              tooltip: 'Markdown-Vorschau anzeigen',
              icon: const Icon(Icons.code_rounded),
              onPressed: () => _showMarkdownPreviewDialog(context, ref),
            ),
            IconButton(
              tooltip: 'WebDAV Einstellungen',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              },
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Fokus & Bereit'),
              Tab(text: '# Geplant'),
              Tab(text: '# Blockiert'),
              Tab(text: '# Irgendwann'),
              Tab(text: '# Erledigt'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (!isConfigured)
              _UnconfiguredBanner(
                onConfigure: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  );
                },
              ),
            if (syncState.errorMessage != null)
              _SyncErrorBanner(
                message: syncState.errorMessage!,
                onDismiss: () =>
                    ref.read(syncStateProvider.notifier).clearError(),
              ),
            Expanded(
              child: boardAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _ErrorStateView(
                  error: error.toString(),
                  onRetry: () =>
                      ref.read(taskNotifierProvider.notifier).syncFromRemote(),
                  onOpenSettings: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                  },
                ),
                data: (board) => TabBarView(
                  children: [
                    _MainBoardTab(board: board),
                    _SingleTierListView(
                      board: board,
                      tier: TaskTier.geplant,
                      emptyHint:
                          'Keine Aufgaben im aktiven Backlog (# Geplant).',
                    ),
                    _SingleTierListView(
                      board: board,
                      tier: TaskTier.blockiert,
                      emptyHint: 'Keine blockierten Aufgaben (# Blockiert).',
                    ),
                    _SingleTierListView(
                      board: board,
                      tier: TaskTier.irgendwann,
                      emptyHint: 'Keine Ideen in # Irgendwann gespeichert.',
                    ),
                    _SingleTierListView(
                      board: board,
                      tier: TaskTier.erledigt,
                      emptyHint:
                          'Keine erledigten Aufgaben der letzten 30 Tage.',
                    ),
                  ],
                ),
              ),
            ),
            const QuickAddBar(),
          ],
        ),
      ),
    );
  }

  void _showMarkdownPreviewDialog(BuildContext context, WidgetRef ref) {
    final board =
        ref.read(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    final markdown = ref.read(markdownServiceProvider).serialize(board);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Raw Markdown (Single Source of Truth)'),
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
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }
}

class _MainBoardTab extends StatelessWidget {
  const _MainBoardTab({required this.board});

  final TaskBoard board;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // Hero Section: # Fokus (Soft WIP Limit: 3)
        Container(
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
                tier: TaskTier.fokus,
                count: board.fokus.length,
                softLimit: TaskBoard.fokusSoftLimit,
                icon: Icons.bolt_rounded,
                accentColor: colorScheme.primary,
              ),
              const SizedBox(height: 8),
              if (board.fokus.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Keine Aufgaben im Fokus. Neue Aufgaben aus # Bereit oder # Geplant rücken automatisch hierher nach.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (final task in board.fokus)
                  TaskTile(
                    key: ValueKey('fokus_${task.id}'),
                    task: task,
                    tier: TaskTier.fokus,
                    isProminent: true,
                  ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Quick Access Section: # Bereit (Soft WIP Limit: 5)
        _SectionHeader(
          tier: TaskTier.bereit,
          count: board.bereit.length,
          softLimit: TaskBoard.bereitSoftLimit,
          icon: Icons.playlist_play_rounded,
          accentColor: colorScheme.secondary,
        ),
        const SizedBox(height: 6),
        if (board.bereit.isEmpty)
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Keine Aufgaben in # Bereit.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (final task in board.bereit)
            TaskTile(
              key: ValueKey('bereit_${task.id}'),
              task: task,
              tier: TaskTier.bereit,
            ),
        const SizedBox(height: 20),

        // Expandable Secondary Sections on the Main View
        _ExpandableTierSection(
          tier: TaskTier.geplant,
          tasks: board.geplant,
          icon: Icons.list_alt_rounded,
          initiallyExpanded: board.geplant.isNotEmpty,
        ),
        const SizedBox(height: 8),
        _ExpandableTierSection(
          tier: TaskTier.blockiert,
          tasks: board.blockiert,
          icon: Icons.block_rounded,
          initiallyExpanded: board.blockiert.isNotEmpty,
        ),
        const SizedBox(height: 8),
        _ExpandableTierSection(
          tier: TaskTier.irgendwann,
          tasks: board.irgendwann,
          icon: Icons.lightbulb_outline_rounded,
        ),
        const SizedBox(height: 8),
        _ExpandableTierSection(
          tier: TaskTier.erledigt,
          tasks: board.erledigt,
          icon: Icons.check_circle_outline_rounded,
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.tier,
    required this.count,
    required this.softLimit,
    required this.icon,
    required this.accentColor,
  });

  final TaskTier tier;
  final int count;
  final int? softLimit;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isOverSoftLimit = softLimit != null && count > softLimit!;

    return Row(
      children: [
        Icon(icon, color: accentColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '# ${tier.heading}',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                tier.description,
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
            softLimit != null ? '$count / $softLimit' : '$count',
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

class _ExpandableTierSection extends StatelessWidget {
  const _ExpandableTierSection({
    required this.tier,
    required this.tasks,
    required this.icon,
    this.initiallyExpanded = false,
  });

  final TaskTier tier;
  final List<dynamic> tasks;
  final IconData icon;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
          '# ${tier.heading}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          tier.description,
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
                'Keine Einträge in # ${tier.heading}.',
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

class _SingleTierListView extends StatelessWidget {
  const _SingleTierListView({
    required this.board,
    required this.tier,
    required this.emptyHint,
  });

  final TaskBoard board;
  final TaskTier tier;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final tasks = board.tasksForTier(tier);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _SectionHeader(
          tier: tier,
          count: tasks.length,
          softLimit: tier.softLimit,
          icon: Icons.folder_open_rounded,
          accentColor: colorScheme.primary,
        ),
        const SizedBox(height: 12),
        if (tasks.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Text(
                emptyHint,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          for (final task in tasks)
            TaskTile(
              key: ValueKey('tab_${tier.name}_${task.id}'),
              task: task,
              tier: tier,
            ),
      ],
    );
  }
}

class _UnconfiguredBanner extends StatelessWidget {
  const _UnconfiguredBanner({required this.onConfigure});

  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
                'Lokaler Modus aktiv. Konfiguriere Nextcloud WebDAV für die Synchronisation.',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            TextButton(onPressed: onConfigure, child: const Text('Einrichten')),
          ],
        ),
      ),
    );
  }
}

class _SyncErrorBanner extends StatelessWidget {
  const _SyncErrorBanner({required this.message, required this.onDismiss});

  final String message;
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

class _ErrorStateView extends StatelessWidget {
  const _ErrorStateView({
    required this.error,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final String error;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              'WebDAV Synchronisationsfehler',
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
                  label: const Text('Einstellungen'),
                ),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Erneut versuchen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
