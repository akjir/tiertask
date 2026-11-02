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
import '../models/tdf_metadata.dart';
import '../providers/task_providers.dart';
import 'edit_labels_screen.dart';
import 'edit_task_screen.dart';
import 'settings_screen.dart';
import 'widgets/quick_add_bar.dart';
import 'widgets/tier_page_indicator.dart';

const Color _accentBlue = Color(0xFF2196F3);
const Color _accentMagenta = Color(0xFFEB06FF);
const Color _canvasColor = Color(0xFF344FA1);
const Color _cardColor = Color(0xFF071A52);
const Color _mutedLabelColor = Color(0xFF9BA8E5);

/// Primary landing page screen for TierTask across Linux, Android, and Windows.
class HomeScreen extends ConsumerStatefulWidget {
  /// Creates a [HomeScreen] widget.
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
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

/// Footer actions inside [_LandingDrawer] for synchronization, preview, and settings.
class _DrawerFooterSection extends StatelessWidget {
  /// Creates a [_DrawerFooterSection].
  const _DrawerFooterSection({
    required this.onOpenMarkdownPreview,
    required this.onOpenSettings,
    required this.onSyncRemote,
  });

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
        _DrawerActionTile(
          icon: Icons.settings_outlined,
          title: localizations.tooltipSettings,
          onAction: onOpenSettings,
        ),
      ],
    );
  }
}

/// Header title block inside [_LandingDrawer].
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
      child: Text(
        title,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
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
    final resolvedColor = _resolveColor(label.color);
    final leadingColor = isSelected ? _accentBlue : resolvedColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        dense: true,
        selected: isSelected,
        selectedColor: _accentBlue,
        selectedTileColor: _accentBlue.withValues(alpha: 0.18),
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

/// Placeholder card shown when a tier's task list is empty.
class _EmptyTierCard extends StatelessWidget {
  /// Creates an [_EmptyTierCard].
  const _EmptyTierCard({required this.message});

  /// Empty-state message text.
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        message,
        style: const TextStyle(color: _mutedLabelColor, fontSize: 15),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: _accentMagenta,
            ),
            const SizedBox(height: 12),
            Text(
              localizations.syncErrorTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _mutedLabelColor, fontSize: 14),
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

/// State for [HomeScreen].
class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _activeLabelId;
  TaskTier _activeTier = TaskTier.focus;
  bool _isQuickAddOpen = false;
  bool _isSearching = false;
  final PageController _pageController = PageController();
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
    final boardAsync = ref.watch(taskNotifierProvider);
    final board = boardAsync.asData?.value ?? TaskBoard.empty();
    final activeLabel = _resolveActiveLabel(board);
    final evaluationTime = ref.watch(clockProvider)();
    final syncState = ref.watch(syncStateProvider);
    final showSyncAction = ref.watch(
      webDavConfigProvider.select(
        (configAsync) =>
            configAsync.asData?.value.storageMode.usesWebDav ?? false,
      ),
    );

    return Scaffold(
      backgroundColor: _canvasColor,
      drawer: _LandingDrawer(
        activeLabelId: activeLabel?.id,
        board: board,
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
          : FloatingActionButton(
              backgroundColor: _accentMagenta,
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
              onPressed: _openQuickAdd,
              child: const Icon(Icons.add_rounded, size: 28),
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
          evaluationTime: evaluationTime,
          isSearching: _isSearching,
          isSyncing: syncState.isSyncing,
          pageController: _pageController,
          searchController: _searchController,
          searchQuery: _searchQuery,
          showSyncAction: showSyncAction,
          onClearError: () => ref.read(syncStateProvider.notifier).clearError(),
          onOpenSettings: () => _openSettings(context),
          onPageChanged: _handlePageChanged,
          onRetry: () =>
              ref.read(taskNotifierProvider.notifier).syncFromRemote(),
          onSearchChanged: _updateSearchQuery,
          onSelectTier: _selectTierPane,
          onSyncRemote: () =>
              ref.read(taskNotifierProvider.notifier).syncFromRemote(),
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

  /// Pushes [EditLabelsScreen] onto the navigation stack.
  void _openEditLabels(BuildContext context, {required bool autofocusCreate}) {
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
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(tier.index);
    }
  }

  /// Displays a dialog containing the serialized `.tdf` representation of the board.
  void _showMarkdownPreviewDialog(BuildContext context) {
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

/// Switches between loading, error, and the horizontal 6-tier [PageView].
class _LandingContentSwitcher extends StatelessWidget {
  /// Creates a [_LandingContentSwitcher].
  const _LandingContentSwitcher({
    required this.activeLabel,
    required this.boardAsync,
    required this.evaluationTime,
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

  /// Reference evaluation time for active label context derivation.
  final DateTime evaluationTime;

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
  Widget build(BuildContext context) {
    return boardAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: _accentMagenta)),
      error: (error, _) => _ErrorStateView(
        error: error.toString(),
        onRetry: onRetry,
        onOpenSettings: onOpenSettings,
      ),
      data: (board) {
        final label = activeLabel;
        final effectiveBoard = label != null
            ? board.evaluateForContext(
                activeLabelId: label.id,
                evaluationTime: evaluationTime,
              )
            : board;
        return PageView.builder(
          controller: pageController,
          itemCount: TaskTier.values.length,
          onPageChanged: onPageChanged,
          itemBuilder: (context, index) => _TierScrollView(
            board: effectiveBoard,
            searchQuery: searchQuery,
            tier: TaskTier.values[index],
          ),
        );
      },
    );
  }
}

/// Left-side navigation drawer containing the Google Keep style Labels section, sync, preview, and settings.
class _LandingDrawer extends StatelessWidget {
  /// Creates a [_LandingDrawer].
  const _LandingDrawer({
    required this.activeLabelId,
    required this.board,
    required this.onOpenEditLabels,
    required this.onOpenMarkdownPreview,
    required this.onOpenSettings,
    required this.onSelectLabel,
    required this.onSyncRemote,
  });

  /// Currently selected label filter ID, or `null` when all tasks are shown.
  final String? activeLabelId;

  /// Current task board snapshot.
  final TaskBoard board;

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
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _DrawerHeader(title: localizations.appTitle),
            const Divider(height: 8),
            _DrawerLabelsHeader(onEditLabels: () => onOpenEditLabels(false)),
            for (final label in board.labels)
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
            const Divider(height: 8),
            _DrawerFooterSection(
              onOpenMarkdownPreview: onOpenMarkdownPreview,
              onOpenSettings: onOpenSettings,
              onSyncRemote: onSyncRemote,
            ),
          ],
        ),
      ),
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
    required this.isSearching,
    required this.isSyncing,
    required this.pageController,
    required this.searchController,
    required this.searchQuery,
    required this.showSyncAction,
    required this.onClearError,
    required this.onOpenSettings,
    required this.onPageChanged,
    required this.onRetry,
    required this.onSearchChanged,
    required this.onSelectTier,
    required this.onSyncRemote,
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

  /// Reference evaluation time for active label context derivation.
  final DateTime evaluationTime;

  /// Whether the inline search bar is active.
  final bool isSearching;

  /// Whether a synchronization request is in progress.
  final bool isSyncing;

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

  /// Callback to trigger WebDAV synchronization from the top bar.
  final VoidCallback onSyncRemote;

  /// Callback to toggle the search bar.
  final VoidCallback onToggleSearch;

  /// Controller for the horizontal tier [PageView].
  final PageController pageController;

  /// Text controller for the search input.
  final TextEditingController searchController;

  /// Active search query string.
  final String searchQuery;

  /// Whether the top bar should display the WebDAV sync action next to search.
  final bool showSyncAction;

  @override
  Widget build(BuildContext context) {
    final activeError = errorMessage;
    return Column(
      children: [
        _LandingTopBar(
          activeLabelName: activeLabel?.name,
          isSearching: isSearching,
          isSyncing: isSyncing,
          searchController: searchController,
          showSyncAction: showSyncAction,
          onSearchChanged: onSearchChanged,
          onSyncRemote: onSyncRemote,
          onToggleSearch: onToggleSearch,
        ),
        if (activeError != null)
          _SyncErrorBanner(message: activeError, onDismiss: onClearError),
        Expanded(
          child: _LandingContentSwitcher(
            activeLabel: activeLabel,
            boardAsync: boardAsync,
            evaluationTime: evaluationTime,
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
    return Text(
      title,
      style: const TextStyle(
        color: _mutedLabelColor,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.6,
      ),
    );
  }
}

/// Top navigation bar displaying the menu button on the left, the active label name in the center when a label filter is selected (smoothly gliding left next to the menu when searching), and search and optional sync on the right.
class _LandingTopBar extends StatelessWidget {
  /// Creates a [_LandingTopBar].
  const _LandingTopBar({
    required this.activeLabelName,
    required this.isSearching,
    required this.isSyncing,
    required this.searchController,
    required this.showSyncAction,
    required this.onSearchChanged,
    required this.onSyncRemote,
    required this.onToggleSearch,
  });

  /// Active label display name when a label filter is selected, or `null` when unfiltered.
  final String? activeLabelName;

  /// Whether the inline search input is currently expanded.
  final bool isSearching;

  /// Whether a background sync request is currently in progress.
  final bool isSyncing;

  /// Callback invoked when the search input text changes.
  final ValueChanged<String> onSearchChanged;

  /// Callback invoked when the WebDAV sync button is pressed.
  final VoidCallback onSyncRemote;

  /// Callback invoked when the search button or close button is pressed.
  final VoidCallback onToggleSearch;

  /// Controller for the inline search input field.
  final TextEditingController searchController;

  /// Whether to display the sync button next to search (`WebDAV` or `Both` mode).
  final bool showSyncAction;

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
          if (showSyncAction)
            _TopBarSyncAction(isSyncing: isSyncing, onSyncRemote: onSyncRemote),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: _LandingSectionLabel(title: localizations.tierSectionTitle(tier)),
    );
  }
}

/// Scrollable tier pane body rendering the uppercase section label and minimalist task pills.
class _TierScrollView extends StatelessWidget {
  /// Creates a [_TierScrollView].
  const _TierScrollView({
    required this.board,
    required this.searchQuery,
    required this.tier,
  });

  /// Current task board snapshot.
  final TaskBoard board;

  /// Active search query string for filtering tasks.
  final String searchQuery;

  /// [TaskTier] displayed on this pane.
  final TaskTier tier;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tasks = _filterTasks(board.tasksForTier(tier), searchQuery);
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
        return _TierTaskPill(
          key: ValueKey('tier_pill_${tier.name}_${task.id}'),
          task: task,
          canDowngrade:
              tier == TaskTier.focus ||
              tier == TaskTier.ready ||
              tier == TaskTier.planned,
          isCompleted: isCompletedTier,
          ringColor: taskIndex.isEven ? _accentMagenta : _accentBlue,
        );
      },
    );
  }

  /// Filters [tasks] by a case-insensitive substring match against [query].
  List<TaskItem> _filterTasks(List<TaskItem> tasks, String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return tasks;
    }
    return [
      for (final task in tasks)
        if (task.title.toLowerCase().contains(trimmed)) task,
    ];
  }
}

/// Compact icon button rendered on the right side of [_TierTaskPillRow].
class _TierTaskActionButton extends StatelessWidget {
  /// Creates a [_TierTaskActionButton].
  const _TierTaskActionButton({
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  /// Deterministic widget key for the icon button.
  final Key buttonKey;

  /// Icon displayed inside the button.
  final IconData icon;

  /// Callback invoked when the button is tapped, or `null` when disabled.
  final VoidCallback? onPressed;

  /// Localized tooltip message.
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Center(
        child: IconButton(
          key: buttonKey,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: tooltip,
          icon: Icon(icon, size: 20, color: _mutedLabelColor),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// Circular button at the leading edge of [_TierTaskPillRow] to complete or restore a task.
class _TierTaskCompletionCircle extends StatelessWidget {
  /// Creates a [_TierTaskCompletionCircle].
  const _TierTaskCompletionCircle({
    required this.buttonKey,
    required this.isCompleted,
    required this.ringColor,
    required this.onComplete,
  });

  /// Deterministic widget key for the completion circle.
  final Key buttonKey;

  /// Whether the task is already completed.
  final bool isCompleted;

  /// Callback invoked when the circle is tapped.
  final VoidCallback onComplete;

  /// Border and check icon color of the circular indicator.
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: buttonKey,
      customBorder: const CircleBorder(),
      onTap: onComplete,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ringColor, width: 2.2),
        ),
        child: isCompleted
            ? Icon(Icons.check_rounded, size: 16, color: ringColor)
            : null,
      ),
    );
  }
}

/// Minimal pill card representing a single task entry across all 6 [TaskTier] panes.
class _TierTaskPill extends ConsumerWidget {
  /// Creates a [_TierTaskPill].
  const _TierTaskPill({
    super.key,
    required this.canDowngrade,
    required this.isCompleted,
    required this.ringColor,
    required this.task,
  });

  /// Whether the task belongs to a downgradable tier (`Focus`, `Ready`, or `Planned`).
  final bool canDowngrade;

  /// Whether the task belongs to the completed archive tier.
  final bool isCompleted;

  /// Border color of the circular completion indicator.
  final Color ringColor;

  /// Task item to display.
  final TaskItem task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: _cardColor,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(20),
        child: IntrinsicHeight(
          child: _TierTaskPillRow(
            isCompleted: isCompleted,
            ringColor: ringColor,
            task: task,
            onComplete: () => isCompleted
                ? ref.read(taskNotifierProvider.notifier).restoreTask(task.id)
                : ref.read(taskNotifierProvider.notifier).completeTask(task.id),
            onDowngrade: canDowngrade
                ? () => ref
                      .read(taskNotifierProvider.notifier)
                      .downgradeTask(task.id)
                : null,
            onEdit: () => openEditTaskScreen(context, initialTask: task),
          ),
        ),
      ),
    );
  }
}

/// Left-hand content area inside [_TierTaskPillRow] containing the completion circle and task title.
class _TierTaskPillContent extends StatelessWidget {
  /// Creates a [_TierTaskPillContent].
  const _TierTaskPillContent({
    required this.isCompleted,
    required this.ringColor,
    required this.task,
    required this.onComplete,
  });

  /// Whether the task is completed.
  final bool isCompleted;

  /// Callback invoked when the leading completion circle is pressed.
  final VoidCallback onComplete;

  /// Border color of the circular completion indicator.
  final Color ringColor;

  /// Task item displayed in this content section.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 4, 18),
      child: Row(
        children: [
          _TierTaskCompletionCircle(
            buttonKey: ValueKey('complete_task_button_${task.id}'),
            isCompleted: isCompleted,
            ringColor: ringColor,
            onComplete: onComplete,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              task.title,
              style: TextStyle(
                color: isCompleted ? _mutedLabelColor : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                decoration: isCompleted ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Row layout inside [_TierTaskPill] combining the task content area, downgrade arrow button, full-height vertical divider, and right-side edit button.
class _TierTaskPillRow extends StatelessWidget {
  /// Creates a [_TierTaskPillRow].
  const _TierTaskPillRow({
    required this.isCompleted,
    required this.ringColor,
    required this.task,
    required this.onComplete,
    required this.onDowngrade,
    required this.onEdit,
  });

  /// Whether the task is completed.
  final bool isCompleted;

  /// Callback invoked when the leading completion circle is pressed.
  final VoidCallback onComplete;

  /// Callback invoked when the downgrade button is pressed, or `null` when omitted.
  final VoidCallback? onDowngrade;

  /// Callback invoked when the edit button is pressed.
  final VoidCallback onEdit;

  /// Border color of the circular completion indicator.
  final Color ringColor;

  /// Task item displayed in this pill row.
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _TierTaskPillContent(
            isCompleted: isCompleted,
            ringColor: ringColor,
            task: task,
            onComplete: onComplete,
          ),
        ),
        if (onDowngrade != null)
          _TierTaskActionButton(
            buttonKey: ValueKey('downgrade_task_button_${task.id}'),
            icon: Icons.arrow_downward_rounded,
            tooltip: localizations.tooltipDowngradeTask,
            onPressed: onDowngrade,
          ),
        Container(
          key: ValueKey('edit_task_divider_${task.id}'),
          width: 3,
          color: _canvasColor,
        ),
        _TierTaskActionButton(
          buttonKey: ValueKey('edit_task_button_${task.id}'),
          icon: Icons.edit_outlined,
          tooltip: localizations.tooltipEditTask,
          onPressed: onEdit,
        ),
      ],
    );
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
    return IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.menu_rounded, color: _mutedLabelColor, size: 28),
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
    return IconButton(
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
          color: _mutedLabelColor,
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
    return TextField(
      controller: controller,
      autofocus: true,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: localizations.searchHint,
        hintStyle: const TextStyle(color: _mutedLabelColor),
        border: InputBorder.none,
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

/// Sync button or progress spinner rendered next to search when WebDAV is enabled.
class _TopBarSyncAction extends StatelessWidget {
  /// Creates a [_TopBarSyncAction].
  const _TopBarSyncAction({
    required this.isSyncing,
    required this.onSyncRemote,
  });

  /// Whether a synchronization request is currently in flight.
  final bool isSyncing;

  /// Callback invoked when the sync button is pressed.
  final VoidCallback onSyncRemote;

  @override
  Widget build(BuildContext context) {
    if (isSyncing) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _mutedLabelColor,
          ),
        ),
      );
    }
    final localizations = AppLocalizations.of(context);
    return IconButton(
      tooltip: localizations.tooltipSyncWebDav,
      icon: const Icon(Icons.sync_rounded, color: _mutedLabelColor, size: 26),
      onPressed: onSyncRemote,
    );
  }
}

/// Active label title displayed inside [_LandingTopBar].
class _TopBarTitle extends StatelessWidget {
  /// Creates a [_TopBarTitle].
  const _TopBarTitle({super.key, required this.title});

  /// Active label name to display.
  final String title;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: Text(
        title,
        key: ValueKey<String>(title),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
