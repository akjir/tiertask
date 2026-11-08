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
import '../models/app_workspace.dart';
import '../models/location_state.dart';
import '../models/task_board.dart';
import '../models/task_tier.dart';
import '../models/tdf_metadata.dart';
import '../models/webdav_config.dart';
import '../providers/config_providers.dart';
import '../providers/location_providers.dart';
import '../providers/sync_providers.dart';
import '../providers/task_providers.dart';
import '../providers/workspace_providers.dart';
import '../services/app_logger.dart';
import 'edit_labels_screen.dart';
import 'edit_locations_screen.dart';
import 'settings_screen.dart';
import 'widgets/home_drawer.dart';
import 'widgets/home_tier_pane.dart';
import 'widgets/home_top_bar.dart';
import 'widgets/quick_add_bar.dart';
import 'widgets/tier_page_indicator.dart';
import 'widgets/workspace_dialog.dart';

/// Primary landing page screen for TierTask across Linux, Android, and Windows.
class HomeScreen extends ConsumerStatefulWidget {
  /// Creates a [HomeScreen] widget.
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

/// Action buttons row inside [_ErrorStateView].
class _ErrorActionButtons extends StatelessWidget {
  /// Creates [_ErrorActionButtons].
  const _ErrorActionButtons({
    required this.onOpenSettings,
    required this.onRetry,
  });

  final VoidCallback onOpenSettings;
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

  final String error;
  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final titleStyle = TextStyle(
      color: colorScheme.onSurface,
      fontSize: 18,
      fontWeight: FontWeight.bold,
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: colorScheme.primary),
            const SizedBox(height: 12),
            Text(localizations.syncErrorTitle, style: titleStyle),
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

/// Smaller circular floating action button for triggering WebDAV sync.
class _FloatingSyncButton extends ConsumerWidget {
  /// Creates a [_FloatingSyncButton].
  const _FloatingSyncButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isSyncing = ref.watch(
      syncStateProvider.select((state) => state.isSyncing),
    );
    return FloatingActionButton.small(
      key: const ValueKey('sync_fab'),
      heroTag: null,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: theme.colorScheme.secondaryContainer,
      foregroundColor: theme.colorScheme.onSecondaryContainer,
      shape: const CircleBorder(),
      tooltip: localizations.tooltipSyncWebDav,
      onPressed: isSyncing
          ? null
          : () => ref.read(taskNotifierProvider.notifier).syncFromRemote(),
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
    final state = _watchScaffoldState();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: HomeDrawer(
        activeLabelId: state.activeLabel?.id,
        activeWorkspace: state.workspace,
        board: state.board,
        onManageWorkspaces: () => showWorkspaceDialog(context),
        onOpenEditLabels: _openEditLabels,
        onOpenEditLocations: _openEditLocations,
        onOpenSettings: _openSettings,
        onSelectLabel: _selectLabel,
        onSyncRemote: () =>
            ref.read(taskNotifierProvider.notifier).syncFromRemote(),
      ),
      floatingActionButton: _isQuickAddOpen
          ? null
          : _LandingFloatingButtons(onOpenQuickAdd: _openQuickAdd),
      bottomNavigationBar: _isQuickAddOpen
          ? _QuickAddBottomBar(onClose: _closeQuickAdd)
          : null,
      body: _LandingScaffoldBody(
        activeLabel: state.activeLabel,
        activeTier: _activeTier,
        isSearching: _isSearching,
        pageController: _pageController,
        searchController: _searchController,
        searchQuery: _searchQuery,
        onOpenSettings: _openSettings,
        onPageChanged: _handlePageChanged,
        onSearchChanged: _updateSearchQuery,
        onSelectTier: _selectTierPane,
        onToggleSearch: _toggleSearch,
      ),
    );
  }

  /// Closes the inline [QuickAddBar] and restores the add button.
  void _closeQuickAdd() => setState(() => _isQuickAddOpen = false);

  /// Clears search state and recreates [_pageController] at [_activeTier].
  void _closeSearchToActiveTier() {
    _isSearching = false;
    _searchController.clear();
    _searchQuery = '';
    _pageController.dispose();
    _pageController = PageController(initialPage: _activeTier.index);
  }

  /// Synchronizes [_activeTier] when the user swipes between tier pages.
  void _handlePageChanged(int index) {
    if (_activeTier.index != index) {
      setState(() => _activeTier = TaskTier.values[index]);
    }
  }

  /// Resets ephemeral filters when the active workspace changes.
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
  void _openEditLabels(bool autofocusCreate) {
    AppLogger.info(LogTag.ui, 'Opened EditLabelsScreen');
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditLabelsScreen(autofocusCreate: autofocusCreate),
      ),
    );
  }

  /// Pushes [EditLocationsScreen] onto the navigation stack.
  void _openEditLocations(bool autofocusCreate) {
    AppLogger.info(LogTag.ui, 'Opened EditLocationsScreen');
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditLocationsScreen(autofocusCreate: autofocusCreate),
      ),
    );
  }

  /// Opens the inline [QuickAddBar] in place of the add button.
  void _openQuickAdd() => setState(() => _isQuickAddOpen = true);

  /// Pushes [SettingsScreen] onto the navigation stack.
  void _openSettings() {
    AppLogger.info(LogTag.ui, 'Opened SettingsScreen');
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  /// Returns the selected [TdfLabel] when [_activeLabelId] exists in [board].
  TdfLabel? _resolveActiveLabel(TaskBoard board) {
    for (final label in board.labels) {
      if (label.id == _activeLabelId) {
        return label;
      }
    }
    return null;
  }

  /// Updates the active label filter on the board.
  void _selectLabel(String? labelId) =>
      setState(() => _activeLabelId = labelId);

  /// Jumps directly to the [PageView] pane for [tier].
  void _selectTierPane(TaskTier tier) {
    setState(() {
      _activeTier = tier;
      if (_isSearching) {
        _closeSearchToActiveTier();
      }
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(tier.index);
    }
  }

  /// Toggles the top-right search bar and resets the query when closing.
  void _toggleSearch() => setState(
    () => _isSearching ? _closeSearchToActiveTier() : _isSearching = true,
  );

  /// Updates the active search filter query.
  void _updateSearchQuery(String value) => setState(() => _searchQuery = value);

  /// Watches the active workspace and task board snapshot for [HomeScreen].
  ({AppWorkspace workspace, TaskBoard board, TdfLabel? activeLabel})
  _watchScaffoldState() {
    ref.listen<String?>(
      activeWorkspaceProvider.select((workspace) => workspace.asData?.value.id),
      _handleWorkspaceChanged,
    );
    final workspace =
        ref.watch(activeWorkspaceProvider).asData?.value ??
        AppWorkspace.defaultWorkspace;
    final board =
        ref.watch(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    return (
      workspace: workspace,
      board: board,
      activeLabel: _resolveActiveLabel(board),
    );
  }
}

/// Switches between loading, error, [AllTasksSearchView], and the 6-tier
/// [PageView].
class _LandingContentSwitcher extends ConsumerWidget {
  /// Creates a [_LandingContentSwitcher].
  const _LandingContentSwitcher({
    required this.activeLabel,
    required this.isSearching,
    required this.pageController,
    required this.searchQuery,
    required this.onOpenSettings,
    required this.onPageChanged,
  });

  final TdfLabel? activeLabel;
  final bool isSearching;
  final VoidCallback onOpenSettings;
  final ValueChanged<int> onPageChanged;
  final PageController pageController;
  final String searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final boardAsync = ref.watch(taskNotifierProvider);
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
        onRetry: () => ref.read(taskNotifierProvider.notifier).syncFromRemote(),
        onOpenSettings: onOpenSettings,
      ),
      data: (board) {
        final effectiveBoard = _evaluateBoard(ref, board, activeFix);
        if (isSearching) {
          return AllTasksSearchView(
            board: effectiveBoard,
            searchQuery: searchQuery,
            activeFilterLabelId: activeLabel?.id,
          );
        }
        return PageView.builder(
          controller: pageController,
          itemCount: TaskTier.values.length,
          onPageChanged: onPageChanged,
          itemBuilder: (context, index) => TierScrollView(
            board: effectiveBoard,
            tier: TaskTier.values[index],
            activeFilterLabelId: activeLabel?.id,
          ),
        );
      },
    );
  }

  /// Evaluates [board] against [activeLabel] and [activeFix] when active.
  TaskBoard _evaluateBoard(
    WidgetRef ref,
    TaskBoard board,
    LocationFix? activeFix,
  ) {
    final configuration =
        ref.watch(webDavConfigProvider).asData?.value ?? const WebDavConfig();
    final evaluationTime = ref.watch(clockProvider)().toUtc();
    final hasCoordinates =
        activeFix?.latitude != null && activeFix?.longitude != null;
    if (activeLabel == null && !hasCoordinates) {
      return board;
    }
    return board.evaluateForContext(
      activeLabelId: activeLabel?.id,
      currentLatitude: activeFix?.latitude,
      currentLongitude: activeFix?.longitude,
      evaluationTime: evaluationTime,
      localEvaluationTime: configuration.toLocalWallClock(evaluationTime),
    );
  }
}

/// Floating action buttons column displaying the WebDAV sync button above the
/// task-add button.
class _LandingFloatingButtons extends ConsumerWidget {
  /// Creates [_LandingFloatingButtons].
  const _LandingFloatingButtons({required this.onOpenQuickAdd});

  final VoidCallback onOpenQuickAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final configuration =
        ref.watch(webDavConfigProvider).asData?.value ?? const WebDavConfig();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (configuration.storageMode.usesWebDav) ...[
          const _FloatingSyncButton(),
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

/// Column layout inside [HomeScreen] combining [HomeTopBar], error banner,
/// content switcher, and bottom [TierPageIndicator].
class _LandingScaffoldBody extends StatelessWidget {
  /// Creates a [_LandingScaffoldBody].
  const _LandingScaffoldBody({
    required this.activeLabel,
    required this.activeTier,
    required this.isSearching,
    required this.pageController,
    required this.searchController,
    required this.searchQuery,
    required this.onOpenSettings,
    required this.onPageChanged,
    required this.onSearchChanged,
    required this.onSelectTier,
    required this.onToggleSearch,
  });

  final TdfLabel? activeLabel;
  final TaskTier activeTier;
  final bool isSearching;
  final VoidCallback onOpenSettings;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<TaskTier> onSelectTier;
  final VoidCallback onToggleSearch;
  final PageController pageController;
  final TextEditingController searchController;
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          HomeTopBar(
            activeLabelName: activeLabel?.name,
            isSearching: isSearching,
            searchController: searchController,
            onSearchChanged: onSearchChanged,
            onToggleSearch: onToggleSearch,
          ),
          const _SyncErrorBanner(),
          Expanded(
            child: _LandingContentSwitcher(
              activeLabel: activeLabel,
              isSearching: isSearching,
              pageController: pageController,
              searchQuery: searchQuery,
              onOpenSettings: onOpenSettings,
              onPageChanged: onPageChanged,
            ),
          ),
          TierPageIndicator(
            activeTier: activeTier,
            onTierSelected: onSelectTier,
          ),
        ],
      ),
    );
  }
}

/// Bottom bar hosting [QuickAddBar] padded by the keyboard view insets.
class _QuickAddBottomBar extends StatelessWidget {
  /// Creates a [_QuickAddBottomBar].
  const _QuickAddBottomBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: QuickAddBar(onCancel: onClose, onSubmitted: onClose),
    );
  }
}

/// Dismissible error banner shown when a background WebDAV sync fails.
class _SyncErrorBanner extends ConsumerWidget {
  /// Creates a [_SyncErrorBanner].
  const _SyncErrorBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasBoardError = ref.watch(
      taskNotifierProvider.select((board) => board.hasError),
    );
    final message = ref.watch(
      syncStateProvider.select((state) => state.errorMessage),
    );
    if (message == null || hasBoardError) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = colorScheme.onErrorContainer;
    return Material(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 20, color: foregroundColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 13, color: foregroundColor),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 18, color: foregroundColor),
              onPressed: () =>
                  ref.read(syncStateProvider.notifier).clearError(),
            ),
          ],
        ),
      ),
    );
  }
}
