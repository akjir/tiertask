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
import '../models/app_workspace.dart';
import '../models/location_state.dart';
import '../models/task_board.dart';
import '../models/task_item.dart';
import '../models/task_tier.dart';
import '../models/tdf_metadata.dart';
import '../models/webdav_config.dart';
import '../providers/location_providers.dart';
import '../providers/task_providers.dart';
import '../providers/workspace_providers.dart';
import '../repositories/app_version_repository.dart';
import '../services/app_logger.dart';
import 'edit_labels_screen.dart';
import 'settings_screen.dart';
import 'widgets/app_logo.dart';
import 'widgets/location_status_dialog.dart';
import 'widgets/log_viewer_dialog.dart';
import 'widgets/quick_add_bar.dart';
import 'widgets/tier_page_indicator.dart';
import 'widgets/tier_task_pill.dart';
import 'widgets/workspace_dialog.dart';

/// Primary landing page screen for TierTask across Linux, Android, and Windows.
class HomeScreen extends ConsumerStatefulWidget {
  /// Creates a [HomeScreen] widget.
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

/// Scrollable search view displaying all tasks across tiers `1` to `6` (`Focus` through `Completed`) under `ALL TASKS`.
class _AllTasksSearchView extends StatelessWidget {
  /// Creates an [_AllTasksSearchView].
  const _AllTasksSearchView({required this.board, required this.searchQuery});

  /// Current task board snapshot (already evaluated for the active label context if one is selected).
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
            child: _LandingSectionLabel(title: localizations.sectionAllTasks),
          );
        }
        if (entries.isEmpty) {
          return _EmptyTierCard(
            message: localizations.emptySectionEntries(
              localizations.sectionAllTasks,
            ),
          );
        }
        final entry = entries[index - 1];
        final tier = entry.tier;
        return TierTaskPill(
          key: ValueKey('tier_pill_${tier.name}_${entry.task.id}'),
          task: entry.task,
          canDowngrade:
              tier == TaskTier.focus ||
              tier == TaskTier.ready ||
              tier == TaskTier.planned,
          isCompleted: tier == TaskTier.completed,
        );
      },
    );
  }

  /// Appends tasks from [tasks] matching [normalizedQuery] to [entries] tagged with [tier].
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

  /// Collects all tasks across tiers `1` to `6` (`Focus` through `Completed`) filtered by [query].
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

/// Action tile inside [_LandingDrawer] that closes the drawer before invoking [onAction].
class _DrawerActionTile extends StatelessWidget {
  /// Creates a [_DrawerActionTile].
  const _DrawerActionTile({
    required this.icon,
    required this.title,
    required this.onAction,
    this.tileKey,
  });

  /// Leading icon for the menu item.
  final IconData icon;

  /// Callback invoked after closing the drawer.
  final VoidCallback onAction;

  /// Optional deterministic widget key for the tile.
  final Key? tileKey;

  /// Localized title text.
  final String title;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: tileKey,
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      leading: Icon(icon),
      title: Text(title),
      onTap: () {
        Navigator.of(context).pop();
        onAction();
      },
    );
  }
}

/// Footer actions inside [_LandingDrawer] for synchronization, preview, diagnostic log, and settings.
class _DrawerFooterSection extends StatelessWidget {
  /// Creates a [_DrawerFooterSection].
  const _DrawerFooterSection({
    required this.enableLogging,
    required this.onOpenDiagnosticLog,
    required this.onOpenMarkdownPreview,
    required this.onOpenSettings,
    required this.onSyncRemote,
  });

  /// Whether opt-in diagnostic logging is enabled and the log viewer button should be shown.
  final bool enableLogging;

  /// Callback to open the [LogViewerDialog].
  final VoidCallback onOpenDiagnosticLog;

  /// Callback to open the raw TDF preview dialog.
  final VoidCallback onOpenMarkdownPreview;

  /// Callback to navigate to [SettingsScreen].
  final VoidCallback onOpenSettings;

  /// Callback to trigger remote synchronization.
  final VoidCallback onSyncRemote;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DrawerActionTile(
          icon: Icons.sync_rounded,
          title: localizations.tooltipSyncWebDav,
          onAction: onSyncRemote,
        ),
        _DrawerActionTile(
          icon: Icons.code_rounded,
          title: localizations.tooltipMarkdownPreview,
          onAction: onOpenMarkdownPreview,
        ),
        if (enableLogging)
          _DrawerActionTile(
            tileKey: const ValueKey('drawer_diagnostic_log_tile'),
            icon: Icons.bug_report_outlined,
            title: localizations.diagnosticLogButton,
            onAction: onOpenDiagnosticLog,
          ),
        _DrawerActionTile(
          icon: Icons.settings_outlined,
          title: localizations.tooltipSettings,
          onAction: onOpenSettings,
        ),
      ],
    );
  }
}

/// Header title block inside [_LandingDrawer] displaying [AppLogo] and [title].
class _DrawerHeader extends StatelessWidget {
  /// Creates a [_DrawerHeader].
  const _DrawerHeader({required this.title});

  /// Header title text.
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          const AppLogo(size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Google Keep style label row inside [_LandingDrawer] with rounded selection pill and task count badge.
class _DrawerLabelTile extends StatelessWidget {
  /// Creates a [_DrawerLabelTile].
  const _DrawerLabelTile({
    super.key,
    required this.count,
    required this.isSelected,
    required this.label,
    required this.onTap,
  });

  /// Open task count associated with [label].
  final int count;

  /// Whether [label] is currently the active filter.
  final bool isSelected;

  /// Label definition displayed by this tile.
  final TdfLabel label;

  /// Callback invoked after closing the drawer.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedColor = _resolveColor(label.color);
    final leadingColor = isSelected
        ? colorScheme.onSecondaryContainer
        : resolvedColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        dense: true,
        selected: isSelected,
        selectedColor: colorScheme.onSecondaryContainer,
        selectedTileColor: colorScheme.secondaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        visualDensity: const VisualDensity(vertical: -2),
        leading: Icon(Icons.label_outline_rounded, color: leadingColor),
        title: Text(
          label.name,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        trailing: Badge.count(
          key: ValueKey('drawer_label_badge_${label.id}'),
          count: count,
        ),
        onTap: () {
          Navigator.of(context).pop();
          onTap();
        },
      ),
    );
  }

  /// Resolves an optional `#RRGGBB` color string or returns `null`.
  static Color? _resolveColor(String? rawHex) {
    final parsed = TdfColor.tryParseArgb(rawHex);
    return parsed != null ? Color(parsed) : null;
  }
}

/// Section header row inside [_LandingDrawer] displaying `Labels` on the left and `Edit` on the right.
class _DrawerLabelsHeader extends StatelessWidget {
  /// Creates a [_DrawerLabelsHeader].
  const _DrawerLabelsHeader({required this.onEditLabels});

  /// Callback invoked after closing the drawer when `Edit` is pressed.
  final VoidCallback onEditLabels;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            localizations.drawerLabels,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          TextButton(
            key: const ValueKey('drawer_edit_labels_button'),
            onPressed: () {
              Navigator.of(context).pop();
              onEditLabels();
            },
            child: Text(localizations.actionEdit),
          ),
        ],
      ),
    );
  }
}

/// Labels section inside [_LandingDrawer] rendering the section header, sorted label filter tiles, and the create-label tile.
class _DrawerLabelsSection extends StatelessWidget {
  /// Creates a [_DrawerLabelsSection].
  const _DrawerLabelsSection({
    required this.activeLabelId,
    required this.board,
    required this.onOpenEditLabels,
    required this.onSelectLabel,
  });

  /// Currently selected label filter ID, or `null` when all tasks are shown.
  final String? activeLabelId;

  /// Current task board snapshot.
  final TaskBoard board;

  /// Callback to open [EditLabelsScreen], passing whether the create input should autofocus.
  final ValueChanged<bool> onOpenEditLabels;

  /// Callback to select or clear a label filter.
  final ValueChanged<String?> onSelectLabel;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DrawerLabelsHeader(onEditLabels: () => onOpenEditLabels(false)),
        for (final label in board.sortedLabels)
          _DrawerLabelTile(
            key: ValueKey('drawer_label_tile_${label.id}'),
            count: board.openTaskCountForLabel(label.id),
            isSelected: activeLabelId == label.id,
            label: label,
            onTap: () =>
                onSelectLabel(activeLabelId == label.id ? null : label.id),
          ),
        _DrawerActionTile(
          tileKey: const ValueKey('drawer_create_label_tile'),
          icon: Icons.add_rounded,
          title: localizations.createNewLabel,
          onAction: () => onOpenEditLabels(true),
        ),
      ],
    );
  }
}

/// Muted SemVer 2.0.0 version and Git build metadata footer anchored at the bottom of [_LandingDrawer].
class _DrawerVersionFooter extends ConsumerWidget {
  /// Creates a [_DrawerVersionFooter].
  const _DrawerVersionFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawVersion =
        ref.watch(appVersionProvider).asData?.value ??
        AppVersionRepository.defaultFullVersion;
    final parts = _splitVersionParts(rawVersion);
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.onSurfaceVariant;
    final versionColor =
        Color.lerp(baseColor, theme.cardColor, 0.18) ?? baseColor;
    final buildColor =
        Color.lerp(versionColor, Colors.black, 0.32) ?? versionColor;
    final baseStyle = theme.textTheme.labelSmall?.copyWith(
      fontFamily: 'monospace',
      fontSize: 11.5,
      letterSpacing: 0.3,
    );

    return Padding(
      key: const ValueKey('drawer_version_footer'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: parts.versionLabel,
              style: baseStyle?.copyWith(color: versionColor),
            ),
            if (parts.buildSuffix.isNotEmpty)
              TextSpan(
                text: parts.buildSuffix,
                style: baseStyle?.copyWith(color: buildColor),
              ),
          ],
        ),
        key: const ValueKey('drawer_version_text'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Splits [rawVersion] (`v0.1.0+<build>`) into `Version 0.1.0` and `+<build>`.
  static ({String versionLabel, String buildSuffix}) _splitVersionParts(
    String rawVersion,
  ) {
    final trimmed = rawVersion.trim();
    final withoutLeadingV = (trimmed.startsWith('v') || trimmed.startsWith('V'))
        ? trimmed.substring(1)
        : trimmed;
    final plusIndex = withoutLeadingV.indexOf('+');
    if (plusIndex < 0) {
      return (versionLabel: 'Version $withoutLeadingV', buildSuffix: '');
    }
    return (
      versionLabel: 'Version ${withoutLeadingV.substring(0, plusIndex)}',
      buildSuffix: withoutLeadingV.substring(plusIndex),
    );
  }
}

/// Placeholder card shown when a tier's task list is empty.
class _EmptyTierCard extends StatelessWidget {
  /// Creates an [_EmptyTierCard].
  const _EmptyTierCard({required this.message});

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

/// Action buttons row inside [_ErrorStateView].
class _ErrorActionButtons extends StatelessWidget {
  /// Creates [_ErrorActionButtons].
  const _ErrorActionButtons({
    required this.onOpenSettings,
    required this.onRetry,
  });

  /// Callback to open settings.
  final VoidCallback onOpenSettings;

  /// Callback to retry synchronization.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Wrap(
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
    );
  }
}

/// Full-screen error state view when initial synchronization fails.
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
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              localizations.syncErrorTitle,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            _ErrorActionButtons(
              onOpenSettings: onOpenSettings,
              onRetry: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

/// Smaller circular floating action button for triggering WebDAV synchronization above the task-add button.
class _FloatingSyncButton extends StatelessWidget {
  /// Creates a [_FloatingSyncButton].
  const _FloatingSyncButton({
    required this.isSyncing,
    required this.onSyncRemote,
  });

  /// Whether a synchronization request is currently in progress.
  final bool isSyncing;

  /// Callback invoked when the floating WebDAV sync button is pressed.
  final VoidCallback onSyncRemote;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return FloatingActionButton.small(
      key: const ValueKey('sync_fab'),
      heroTag: null,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: theme.colorScheme.secondaryContainer,
      foregroundColor: theme.colorScheme.onSecondaryContainer,
      shape: const CircleBorder(),
      tooltip: localizations.tooltipSyncWebDav,
      onPressed: isSyncing ? null : onSyncRemote,
      child: isSyncing
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            )
          : const Icon(Icons.sync_rounded, size: 20),
    );
  }
}

/// State for [HomeScreen].
class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _activeLabelId;
  TaskTier _activeTier = TaskTier.focus;
  bool _isQuickAddOpen = false;
  bool _isSearching = false;
  PageController _pageController = PageController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      activeWorkspaceProvider.select((workspace) => workspace.asData?.value.id),
      _handleWorkspaceChanged,
    );
    final theme = Theme.of(context);
    final activeWorkspace =
        ref.watch(activeWorkspaceProvider).asData?.value ??
        AppWorkspace.defaultWorkspace;
    final boardAsync = ref.watch(taskNotifierProvider);
    final board = boardAsync.asData?.value ?? TaskBoard.empty();
    final activeLabel = _resolveActiveLabel(board);
    final config =
        ref.watch(webDavConfigProvider).asData?.value ?? const WebDavConfig();
    final rawEvaluationTime = ref.watch(clockProvider)().toUtc();
    final localEvaluationTime = config.toLocalWallClock(rawEvaluationTime);
    final syncState = ref.watch(syncStateProvider);
    final showSyncAction = config.storageMode.usesWebDav;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: _LandingDrawer(
        activeLabelId: activeLabel?.id,
        activeWorkspace: activeWorkspace,
        board: board,
        onManageWorkspaces: () => showWorkspaceDialog(context),
        onOpenEditLabels: (autofocusCreate) =>
            _openEditLabels(context, autofocusCreate: autofocusCreate),
        onOpenMarkdownPreview: () => _showMarkdownPreviewDialog(context),
        onOpenSettings: () => _openSettings(context),
        onSelectLabel: _selectLabel,
        onSyncRemote: () =>
            ref.read(taskNotifierProvider.notifier).syncFromRemote(),
      ),
      floatingActionButton: _isQuickAddOpen
          ? null
          : _LandingFloatingButtons(
              isSyncing: syncState.isSyncing,
              showSyncAction: showSyncAction,
              onOpenQuickAdd: _openQuickAdd,
              onSyncRemote: () =>
                  ref.read(taskNotifierProvider.notifier).syncFromRemote(),
            ),
      bottomNavigationBar: _isQuickAddOpen
          ? Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: QuickAddBar(
                onCancel: _closeQuickAdd,
                onSubmitted: _closeQuickAdd,
              ),
            )
          : null,
      body: SafeArea(
        child: _LandingScaffoldBody(
          activeLabel: activeLabel,
          activeTier: _activeTier,
          boardAsync: boardAsync,
          errorMessage: syncState.errorMessage,
          evaluationTime: rawEvaluationTime,
          localEvaluationTime: localEvaluationTime,
          isSearching: _isSearching,
          pageController: _pageController,
          searchController: _searchController,
          searchQuery: _searchQuery,
          onClearError: () => ref.read(syncStateProvider.notifier).clearError(),
          onOpenSettings: () => _openSettings(context),
          onPageChanged: _handlePageChanged,
          onRetry: () =>
              ref.read(taskNotifierProvider.notifier).syncFromRemote(),
          onSearchChanged: _updateSearchQuery,
          onSelectTier: _selectTierPane,
          onToggleSearch: _toggleSearch,
        ),
      ),
    );
  }

  /// Closes the inline [QuickAddBar] and restores the add button.
  void _closeQuickAdd() {
    if (!_isQuickAddOpen) {
      return;
    }
    setState(() {
      _isQuickAddOpen = false;
    });
  }

  /// Synchronizes [_activeTier] when the user swipes between tier pages.
  void _handlePageChanged(int index) {
    final tier = TaskTier.values[index];
    if (_activeTier == tier) {
      return;
    }
    setState(() {
      _activeTier = tier;
    });
  }

  /// Resets ephemeral label, search, and quick-add filters when the active workspace changes.
  void _handleWorkspaceChanged(String? previousId, String? nextId) {
    if (previousId == null || nextId == null || previousId == nextId) {
      return;
    }
    setState(() {
      _activeLabelId = null;
      _activeTier = TaskTier.focus;
      _isQuickAddOpen = false;
      _isSearching = false;
      _searchController.clear();
      _searchQuery = '';
      if (_pageController.hasClients) {
        _pageController.jumpToPage(TaskTier.focus.index);
      }
    });
  }

  /// Pushes [EditLabelsScreen] onto the navigation stack.
  void _openEditLabels(BuildContext context, {required bool autofocusCreate}) {
    AppLogger.info(LogTag.ui, 'Opened EditLabelsScreen');
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditLabelsScreen(autofocusCreate: autofocusCreate),
      ),
    );
  }

  /// Opens the inline [QuickAddBar] in place of the add button.
  void _openQuickAdd() {
    setState(() {
      _isQuickAddOpen = true;
    });
  }

  /// Pushes [SettingsScreen] onto the navigation stack.
  void _openSettings(BuildContext context) {
    AppLogger.info(LogTag.ui, 'Opened SettingsScreen');
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  /// Returns the selected [TdfLabel] when [_activeLabelId] still exists in [board.labels], or `null` otherwise.
  TdfLabel? _resolveActiveLabel(TaskBoard board) {
    final currentId = _activeLabelId;
    if (currentId == null) {
      return null;
    }
    for (final label in board.labels) {
      if (label.id == currentId) {
        return label;
      }
    }
    return null;
  }

  /// Updates the active label filter on the board.
  void _selectLabel(String? labelId) {
    setState(() {
      _activeLabelId = labelId;
    });
  }

  /// Jumps directly to the [PageView] pane for [tier].
  void _selectTierPane(TaskTier tier) {
    setState(() {
      _activeTier = tier;
      if (_isSearching) {
        _isSearching = false;
        _searchController.clear();
        _searchQuery = '';
        _pageController.dispose();
        _pageController = PageController(initialPage: tier.index);
      }
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(tier.index);
    }
  }

  /// Displays a dialog containing the serialized `.tdf` representation of the board.
  void _showMarkdownPreviewDialog(BuildContext context) {
    AppLogger.info(LogTag.ui, 'Opened Raw TDF preview dialog');
    final board =
        ref.read(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    final localizations = AppLocalizations.of(context);
    final tdfText = ref.read(tdfServiceProvider).serialize(board);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.markdownPreviewTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              tdfText,
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

  /// Toggles the top-right search bar and resets the query when closing.
  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _searchQuery = '';
        _pageController.dispose();
        _pageController = PageController(initialPage: _activeTier.index);
      }
    });
  }

  /// Updates the active search filter query.
  void _updateSearchQuery(String value) {
    setState(() {
      _searchQuery = value;
    });
  }
}

/// Switches between loading, error, the all-tasks search view, and the horizontal 6-tier [PageView].
class _LandingContentSwitcher extends ConsumerWidget {
  /// Creates a [_LandingContentSwitcher].
  const _LandingContentSwitcher({
    required this.activeLabel,
    required this.boardAsync,
    required this.evaluationTime,
    required this.isSearching,
    required this.localEvaluationTime,
    required this.pageController,
    required this.searchQuery,
    required this.onOpenSettings,
    required this.onPageChanged,
    required this.onRetry,
  });

  /// Currently selected label filter, or `null` when unfiltered.
  final TdfLabel? activeLabel;

  /// Asynchronous board state.
  final AsyncValue<TaskBoard> boardAsync;

  /// Reference UTC evaluation time for active label context derivation.
  final DateTime evaluationTime;

  /// Whether the all-tasks search view is active.
  final bool isSearching;

  /// Reference local wall-clock evaluation time for recurring conditions and `suspended`.
  final DateTime localEvaluationTime;

  /// Callback to open settings.
  final VoidCallback onOpenSettings;

  /// Callback invoked when the active [PageView] page index changes.
  final ValueChanged<int> onPageChanged;

  /// Callback to retry remote synchronization.
  final VoidCallback onRetry;

  /// Controller managing the horizontal tier panes.
  final PageController pageController;

  /// Current search filter query.
  final String searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeFix = ref.watch(
      locationStateProvider.select(
        (state) => state.status == LocationStatus.found ? state.fix : null,
      ),
    );
    return boardAsync.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: colorScheme.primary)),
      error: (error, _) => _ErrorStateView(
        error: error.toString(),
        onRetry: onRetry,
        onOpenSettings: onOpenSettings,
      ),
      data: (board) {
        final label = activeLabel;
        final currentLatitude = activeFix?.latitude;
        final currentLongitude = activeFix?.longitude;
        final hasCoordinates =
            currentLatitude != null && currentLongitude != null;
        final effectiveBoard = (label != null || hasCoordinates)
            ? board.evaluateForContext(
                activeLabelId: label?.id,
                currentLatitude: currentLatitude,
                currentLongitude: currentLongitude,
                evaluationTime: evaluationTime,
                localEvaluationTime: localEvaluationTime,
              )
            : board;
        if (isSearching) {
          return _AllTasksSearchView(
            board: effectiveBoard,
            searchQuery: searchQuery,
          );
        }
        return PageView.builder(
          controller: pageController,
          itemCount: TaskTier.values.length,
          onPageChanged: onPageChanged,
          itemBuilder: (context, index) => _TierScrollView(
            board: effectiveBoard,
            tier: TaskTier.values[index],
          ),
        );
      },
    );
  }
}

/// Left-side navigation drawer containing the workspace switcher card, Google Keep style Labels section, sync, preview, and settings.
class _LandingDrawer extends StatelessWidget {
  /// Creates a [_LandingDrawer].
  const _LandingDrawer({
    required this.activeLabelId,
    required this.activeWorkspace,
    required this.board,
    required this.onManageWorkspaces,
    required this.onOpenEditLabels,
    required this.onOpenMarkdownPreview,
    required this.onOpenSettings,
    required this.onSelectLabel,
    required this.onSyncRemote,
  });

  /// Currently selected label filter ID, or `null` when all tasks are shown.
  final String? activeLabelId;

  /// Currently active [AppWorkspace] displayed beneath `TierTask`.
  final AppWorkspace activeWorkspace;

  /// Current task board snapshot.
  final TaskBoard board;

  /// Callback to open [WorkspaceDialog] for switching or managing workspaces.
  final VoidCallback onManageWorkspaces;

  /// Callback to open [EditLabelsScreen], passing whether the create input should autofocus.
  final ValueChanged<bool> onOpenEditLabels;

  /// Callback to open the raw TDF preview dialog.
  final VoidCallback onOpenMarkdownPreview;

  /// Callback to navigate to [SettingsScreen].
  final VoidCallback onOpenSettings;

  /// Callback to select or clear a label filter.
  final ValueChanged<String?> onSelectLabel;

  /// Callback to trigger remote synchronization.
  final VoidCallback onSyncRemote;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _DrawerHeader(title: localizations.appTitle),
                  const Divider(height: 8),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: DrawerWorkspaceCard(
                      workspace: activeWorkspace,
                      onTap: () {
                        Navigator.of(context).pop();
                        onManageWorkspaces();
                      },
                    ),
                  ),
                  const Divider(height: 8),
                  _DrawerLabelsSection(
                    activeLabelId: activeLabelId,
                    board: board,
                    onOpenEditLabels: onOpenEditLabels,
                    onSelectLabel: onSelectLabel,
                  ),
                  const Divider(height: 8),
                  _DrawerFooterSection(
                    enableLogging: activeWorkspace.config.enableLogging,
                    onOpenDiagnosticLog: () => showLogViewerDialog(context),
                    onOpenMarkdownPreview: onOpenMarkdownPreview,
                    onOpenSettings: onOpenSettings,
                    onSyncRemote: onSyncRemote,
                  ),
                ],
              ),
            ),
            const _DrawerVersionFooter(),
          ],
        ),
      ),
    );
  }
}

/// Floating action buttons column displaying the smaller WebDAV sync button above the task-add button.
class _LandingFloatingButtons extends StatelessWidget {
  /// Creates [_LandingFloatingButtons].
  const _LandingFloatingButtons({
    required this.isSyncing,
    required this.showSyncAction,
    required this.onOpenQuickAdd,
    required this.onSyncRemote,
  });

  /// Whether a synchronization request is currently in progress.
  final bool isSyncing;

  /// Callback invoked when the primary add task button is pressed.
  final VoidCallback onOpenQuickAdd;

  /// Callback invoked when the floating WebDAV sync button is pressed.
  final VoidCallback onSyncRemote;

  /// Whether WebDAV synchronization is enabled (`WebDAV` or `Both` mode).
  final bool showSyncAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (showSyncAction) ...[
          _FloatingSyncButton(isSyncing: isSyncing, onSyncRemote: onSyncRemote),
          const SizedBox(height: 12),
        ],
        FloatingActionButton(
          key: const ValueKey('add_task_fab'),
          heroTag: null,
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.onPrimaryContainer,
          shape: const CircleBorder(),
          onPressed: onOpenQuickAdd,
          child: const Icon(Icons.add_rounded, size: 28),
        ),
      ],
    );
  }
}

/// Column layout inside [HomeScreen] combining the top bar, error banner, content switcher, and bottom tier indicator.
class _LandingScaffoldBody extends StatelessWidget {
  /// Creates a [_LandingScaffoldBody].
  const _LandingScaffoldBody({
    required this.activeLabel,
    required this.activeTier,
    required this.boardAsync,
    required this.errorMessage,
    required this.evaluationTime,
    required this.localEvaluationTime,
    required this.isSearching,
    required this.pageController,
    required this.searchController,
    required this.searchQuery,
    required this.onClearError,
    required this.onOpenSettings,
    required this.onPageChanged,
    required this.onRetry,
    required this.onSearchChanged,
    required this.onSelectTier,
    required this.onToggleSearch,
  });

  /// Currently selected label filter, or `null` when unfiltered.
  final TdfLabel? activeLabel;

  /// Currently selected [TaskTier] pane.
  final TaskTier activeTier;

  /// Asynchronous board state.
  final AsyncValue<TaskBoard> boardAsync;

  /// Optional synchronization error message.
  final String? errorMessage;

  /// Reference UTC evaluation time for active label context derivation.
  final DateTime evaluationTime;

  /// Whether the inline search bar is active.
  final bool isSearching;

  /// Reference local wall-clock evaluation time for recurring conditions and `suspended`.
  final DateTime localEvaluationTime;

  /// Callback to dismiss the error banner.
  final VoidCallback onClearError;

  /// Callback to open settings.
  final VoidCallback onOpenSettings;

  /// Callback invoked when the active [PageView] page index changes.
  final ValueChanged<int> onPageChanged;

  /// Callback to retry synchronization.
  final VoidCallback onRetry;

  /// Callback invoked when the search query changes.
  final ValueChanged<String> onSearchChanged;

  /// Callback invoked when a tier is selected in [TierPageIndicator].
  final ValueChanged<TaskTier> onSelectTier;

  /// Callback to toggle the search bar.
  final VoidCallback onToggleSearch;

  /// Controller for the horizontal tier [PageView].
  final PageController pageController;

  /// Text controller for the search input.
  final TextEditingController searchController;

  /// Active search query string.
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    final activeError = errorMessage;
    return Column(
      children: [
        _LandingTopBar(
          activeLabelName: activeLabel?.name,
          isSearching: isSearching,
          searchController: searchController,
          onSearchChanged: onSearchChanged,
          onToggleSearch: onToggleSearch,
        ),
        if (activeError != null)
          _SyncErrorBanner(message: activeError, onDismiss: onClearError),
        Expanded(
          child: _LandingContentSwitcher(
            activeLabel: activeLabel,
            boardAsync: boardAsync,
            evaluationTime: evaluationTime,
            isSearching: isSearching,
            localEvaluationTime: localEvaluationTime,
            pageController: pageController,
            searchQuery: searchQuery,
            onOpenSettings: onOpenSettings,
            onPageChanged: onPageChanged,
            onRetry: onRetry,
          ),
        ),
        TierPageIndicator(activeTier: activeTier, onTierSelected: onSelectTier),
      ],
    );
  }
}

/// Uppercase muted section heading label on the tier panes.
class _LandingSectionLabel extends StatelessWidget {
  /// Creates a [_LandingSectionLabel].
  const _LandingSectionLabel({required this.title});

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

/// Top navigation bar displaying the menu button on the left, the active label name in the center when a label filter is selected (smoothly gliding left next to the menu when searching), and the search toggle on the right.
class _LandingTopBar extends StatelessWidget {
  /// Creates a [_LandingTopBar].
  const _LandingTopBar({
    required this.activeLabelName,
    required this.isSearching,
    required this.searchController,
    required this.onSearchChanged,
    required this.onToggleSearch,
  });

  /// Active label display name when a label filter is selected, or `null` when unfiltered.
  final String? activeLabelName;

  /// Whether the inline search input is currently expanded.
  final bool isSearching;

  /// Callback invoked when the search input text changes.
  final ValueChanged<String> onSearchChanged;

  /// Callback invoked when the search button or close button is pressed.
  final VoidCallback onToggleSearch;

  /// Controller for the inline search input field.
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          _TopBarMenuButton(tooltip: localizations.tooltipMenu),
          Expanded(
            child: _TopBarCenterArea(
              activeLabelName: activeLabelName,
              isSearching: isSearching,
              searchController: searchController,
              onSearchChanged: onSearchChanged,
            ),
          ),
          _TopBarSearchButton(
            isSearching: isSearching,
            onPressed: onToggleSearch,
          ),
          const TopBarLocationButton(),
        ],
      ),
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

/// Header block inside [_TierScrollView] displaying the uppercase tier section label.
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
      child: _LandingSectionLabel(title: localizations.tierSectionTitle(tier)),
    );
  }
}

/// Scrollable tier pane body rendering the uppercase section label and minimalist task pills.
class _TierScrollView extends StatefulWidget {
  /// Creates a [_TierScrollView].
  const _TierScrollView({required this.board, required this.tier});

  /// Current task board snapshot.
  final TaskBoard board;

  /// [TaskTier] displayed on this pane.
  final TaskTier tier;

  @override
  State<_TierScrollView> createState() => _TierScrollViewState();
}

/// State for [_TierScrollView] tracking newly upgraded tasks entering [ _TierScrollView.tier].
class _TierScrollViewState extends State<_TierScrollView> {
  Set<String> _enteringTaskIds = const <String>{};
  late Set<String> _knownTaskIds;

  @override
  void initState() {
    super.initState();
    _knownTaskIds = _collectTaskIds(widget.board.tasksForTier(widget.tier));
  }

  @override
  void didUpdateWidget(covariant _TierScrollView oldWidget) {
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
    final isCompletedTier = tier == TaskTier.completed;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
      itemCount: tasks.isEmpty ? 2 : tasks.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _TierPaneHeader(tier: tier);
        }
        if (tasks.isEmpty) {
          return _EmptyTierCard(message: localizations.tierEmptyHint(tier));
        }
        final taskIndex = index - 1;
        final task = tasks[taskIndex];
        return TierTaskPill(
          key: ValueKey('tier_pill_${tier.name}_${task.id}'),
          animateEntry: _enteringTaskIds.contains(task.id),
          task: task,
          canDowngrade:
              tier == TaskTier.focus ||
              tier == TaskTier.ready ||
              tier == TaskTier.planned,
          isCompleted: isCompletedTier,
        );
      },
    );
  }

  /// Collects the task IDs present in [tasks].
  static Set<String> _collectTaskIds(List<TaskItem> tasks) {
    return <String>{for (final task in tasks) task.id};
  }
}

/// Animated middle region of [_LandingTopBar] that smoothly glides the active label name from the center to the left edge next to the menu button and expands the search input when search is toggled.
class _TopBarCenterArea extends StatelessWidget {
  /// Creates a [_TopBarCenterArea].
  const _TopBarCenterArea({
    required this.activeLabelName,
    required this.isSearching,
    required this.searchController,
    required this.onSearchChanged,
  });

  /// Active label display name when a label filter is selected, or `null` when unfiltered.
  final String? activeLabelName;

  /// Whether the inline search bar is currently expanded.
  final bool isSearching;

  /// Callback invoked when the search input text changes.
  final ValueChanged<String> onSearchChanged;

  /// Controller for the inline search input field.
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    final labelName = activeLabelName;

    return SizedBox(
      height: 48,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: isSearching ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOutCubic,
        builder: (context, searchProgress, _) {
          final showSearch = isSearching || searchProgress > 0.0;
          return CustomMultiChildLayout(
            delegate: _TopBarLayoutDelegate(searchProgress: searchProgress),
            children: [
              if (labelName != null)
                LayoutId(
                  id: _TopBarSlot.title,
                  child: _TopBarTitle(
                    key: const ValueKey('top_bar_title'),
                    title: labelName,
                  ),
                ),
              if (showSearch)
                LayoutId(
                  id: _TopBarSlot.search,
                  child: Opacity(
                    opacity: searchProgress.clamp(0.0, 1.0),
                    child: IgnorePointer(
                      ignoring: !isSearching,
                      child: _TopBarSearchField(
                        controller: searchController,
                        onChanged: onSearchChanged,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Layout delegate positioning the optional active label title and inline search field according to [searchProgress].
class _TopBarLayoutDelegate extends MultiChildLayoutDelegate {
  /// Creates a [_TopBarLayoutDelegate].
  _TopBarLayoutDelegate({required this.searchProgress});

  /// Interpolation progress between centered label (`0.0`) and expanded search (`1.0`).
  final double searchProgress;

  @override
  void performLayout(Size size) {
    var titleRightEdge = 0.0;
    final hasTitle = hasChild(_TopBarSlot.title);

    if (hasTitle) {
      final maxTitleWidth = size.width * (1.0 - (0.45 * searchProgress));
      final titleSize = layoutChild(
        _TopBarSlot.title,
        BoxConstraints(
          maxWidth: maxTitleWidth.clamp(0.0, size.width),
          maxHeight: size.height,
        ),
      );
      final centeredX = (size.width - titleSize.width) / 2.0;
      final titleX = centeredX * (1.0 - searchProgress);
      final titleY = (size.height - titleSize.height) / 2.0;
      positionChild(_TopBarSlot.title, Offset(titleX, titleY));
      titleRightEdge = titleX + titleSize.width + 12.0;
    }

    if (hasChild(_TopBarSlot.search)) {
      final availableWidth = (size.width - titleRightEdge).clamp(
        0.0,
        size.width,
      );
      final searchWidth = hasTitle
          ? availableWidth
          : size.width * searchProgress;
      final searchX = hasTitle ? titleRightEdge : size.width - searchWidth;
      final searchSize = layoutChild(
        _TopBarSlot.search,
        BoxConstraints(
          minWidth: searchWidth,
          maxWidth: searchWidth,
          maxHeight: size.height,
        ),
      );
      final searchY = (size.height - searchSize.height) / 2.0;
      positionChild(_TopBarSlot.search, Offset(searchX, searchY));
    }
  }

  @override
  bool shouldRelayout(_TopBarLayoutDelegate oldDelegate) {
    return oldDelegate.searchProgress != searchProgress;
  }
}

/// Leading drawer menu button inside [_LandingTopBar].
class _TopBarMenuButton extends StatelessWidget {
  /// Creates a [_TopBarMenuButton].
  const _TopBarMenuButton({required this.tooltip});

  /// Localized tooltip message for opening the drawer.
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(Icons.menu_rounded, color: mutedColor, size: 28),
      onPressed: () => Scaffold.of(context).openDrawer(),
    );
  }
}

/// Search toggle button inside [_LandingTopBar] with animated icon transition.
class _TopBarSearchButton extends StatelessWidget {
  /// Creates a [_TopBarSearchButton].
  const _TopBarSearchButton({
    required this.isSearching,
    required this.onPressed,
  });

  /// Whether the inline search bar is currently active.
  final bool isSearching;

  /// Callback invoked when the button is tapped.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return IconButton(
      key: const ValueKey('top_bar_search_button'),
      tooltip: isSearching
          ? localizations.actionClose
          : localizations.tooltipSearch,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: Icon(
          isSearching ? Icons.close_rounded : Icons.search_rounded,
          key: ValueKey<bool>(isSearching),
          color: mutedColor,
          size: 26,
        ),
      ),
      onPressed: onPressed,
    );
  }
}

/// Inline search [TextField] displayed inside [_LandingTopBar].
class _TopBarSearchField extends StatelessWidget {
  /// Creates a [_TopBarSearchField].
  const _TopBarSearchField({required this.controller, required this.onChanged});

  /// Text controller for the search query.
  final TextEditingController controller;

  /// Callback invoked when the query changes.
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      autofocus: true,
      onChanged: onChanged,
      style: TextStyle(color: colorScheme.onSurface),
      decoration: InputDecoration(
        filled: false,
        hintText: localizations.searchHint,
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isDense: true,
      ),
    );
  }
}

/// Layout slot identifiers for [_TopBarLayoutDelegate].
enum _TopBarSlot {
  /// Active label title slot.
  title,

  /// Inline search input slot.
  search,
}

/// Active label title displayed inside [_LandingTopBar].
class _TopBarTitle extends StatelessWidget {
  /// Creates a [_TopBarTitle].
  const _TopBarTitle({super.key, required this.title});

  /// Active label name to display.
  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: Text(
        title,
        key: ValueKey<String>(title),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
