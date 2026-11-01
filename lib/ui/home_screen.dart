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

const Color _accentBlue = Color(0xFF2196F3);
const Color _accentCyan = Color(0xFF00E5FF);
const Color _accentMagenta = Color(0xFFEB06FF);
const Color _accentOrange = Color(0xFFFF9100);
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

/// Horizontal scrollable section displaying [_ContextCardData] summary cards.
class _ContextCardCarousel extends StatelessWidget {
  /// Creates a [_ContextCardCarousel].
  const _ContextCardCarousel({
    required this.items,
    required this.sectionTitle,
    required this.showOpenTaskCount,
  });

  /// Cards to render in the horizontal list.
  final List<_ContextCardData> items;

  /// Uppercase section heading above the carousel.
  final String sectionTitle;

  /// Whether to render the total open task count on each card.
  final bool showOpenTaskCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LandingSectionLabel(title: sectionTitle),
        const SizedBox(height: 12),
        SizedBox(
          height: 116,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) => _ContextSummaryCard(
              item: items[index],
              showOpenTaskCount: showOpenTaskCount,
            ),
          ),
        ),
      ],
    );
  }
}

/// Immutable display model for a draft category or location card on the landing page.
@immutable
class _ContextCardData {
  /// Creates a [_ContextCardData] instance.
  const _ContextCardData({
    required this.id,
    required this.name,
    required this.taskCount,
    required this.accentColor,
  });

  /// Color of the solid bottom accent bar.
  final Color accentColor;

  /// Deterministic identifier used for widget keys.
  final String id;

  /// Display name of the category or location.
  final String name;

  /// Total number of tasks associated with this context.
  final int taskCount;
}

/// Dark-navy card displaying optional total task count, context name, and a solid colored line.
class _ContextSummaryCard extends StatelessWidget {
  /// Creates a [_ContextSummaryCard].
  const _ContextSummaryCard({
    required this.item,
    required this.showOpenTaskCount,
  });

  /// Card data to render.
  final _ContextCardData item;

  /// Whether to display the total open task count label at the top of the card.
  final bool showOpenTaskCount;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Container(
      width: 190,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (showOpenTaskCount)
            Text(
              localizations.taskCountLabel(item.taskCount),
              style: const TextStyle(
                color: _mutedLabelColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          _SolidAccentBar(
            barKey: ValueKey('accent_bar_${item.id}'),
            color: item.accentColor,
          ),
        ],
      ),
    );
  }
}

/// Action tile inside [_LandingDrawer] that closes the drawer before invoking [onAction].
class _DrawerActionTile extends StatelessWidget {
  /// Creates a [_DrawerActionTile].
  const _DrawerActionTile({
    required this.icon,
    required this.title,
    required this.onAction,
  });

  /// Leading icon for the menu item.
  final IconData icon;

  /// Callback invoked after closing the drawer.
  final VoidCallback onAction;

  /// Localized title text.
  final String title;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: () {
        Navigator.of(context).pop();
        onAction();
      },
    );
  }
}

/// Placeholder card shown when the Focus tasks list is empty.
class _EmptyFocusCard extends StatelessWidget {
  /// Creates an [_EmptyFocusCard].
  const _EmptyFocusCard({required this.message});

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

/// Minimal pill card representing a single Tier 1 (`Focus`) task on the landing page.
class _FocusTaskPill extends ConsumerWidget {
  /// Creates a [_FocusTaskPill].
  const _FocusTaskPill({
    super.key,
    required this.task,
    required this.ringColor,
  });

  /// Border color of the circular completion indicator.
  final Color ringColor;

  /// Focus task item to display.
  final TaskItem task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () =>
              ref.read(taskNotifierProvider.notifier).completeTask(task.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: ringColor, width: 2.2),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    task.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Section displaying only the Tier 1 (`Focus`) tasks in minimalist pill cards.
class _FocusTasksSection extends StatelessWidget {
  /// Creates a [_FocusTasksSection].
  const _FocusTasksSection({required this.tasks});

  /// Filtered Focus tasks to render.
  final List<TaskItem> tasks;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LandingSectionLabel(title: localizations.sectionFocusTasks),
        const SizedBox(height: 12),
        if (tasks.isEmpty)
          _EmptyFocusCard(message: localizations.emptyFocusHint)
        else
          for (var i = 0; i < tasks.length; i++)
            _FocusTaskPill(
              key: ValueKey('focus_pill_${tasks[i].id}'),
              task: tasks[i],
              ringColor: i.isEven ? _accentMagenta : _accentBlue,
            ),
      ],
    );
  }
}

/// State for [HomeScreen].
class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boardAsync = ref.watch(taskNotifierProvider);
    final syncState = ref.watch(syncStateProvider);
    final showOpenTaskCount = ref.watch(
      webDavConfigProvider.select(
        (configAsync) => configAsync.asData?.value.showOpenTaskCount ?? false,
      ),
    );
    final showSyncAction = ref.watch(
      webDavConfigProvider.select(
        (configAsync) =>
            configAsync.asData?.value.storageMode.usesWebDav ?? false,
      ),
    );

    return Scaffold(
      backgroundColor: _canvasColor,
      drawer: _LandingDrawer(
        board: boardAsync.asData?.value ?? TaskBoard.empty(),
        onOpenMarkdownPreview: () => _showMarkdownPreviewDialog(context),
        onOpenSettings: () => _openSettings(context),
        onOpenTierSheet: (tier) => _showTierSheet(context, tier),
        onSyncRemote: () =>
            ref.read(taskNotifierProvider.notifier).syncFromRemote(),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _accentMagenta,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        onPressed: () => _showQuickAddSheet(context),
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      body: SafeArea(
        child: _LandingScaffoldBody(
          boardAsync: boardAsync,
          errorMessage: syncState.errorMessage,
          isSearching: _isSearching,
          isSyncing: syncState.isSyncing,
          searchController: _searchController,
          searchQuery: _searchQuery,
          showOpenTaskCount: showOpenTaskCount,
          showSyncAction: showSyncAction,
          onClearError: () => ref.read(syncStateProvider.notifier).clearError(),
          onOpenSettings: () => _openSettings(context),
          onRetry: () =>
              ref.read(taskNotifierProvider.notifier).syncFromRemote(),
          onSearchChanged: _updateSearchQuery,
          onSyncRemote: () =>
              ref.read(taskNotifierProvider.notifier).syncFromRemote(),
          onToggleSearch: _toggleSearch,
        ),
      ),
    );
  }

  /// Pushes [SettingsScreen] onto the navigation stack.
  void _openSettings(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
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

  /// Opens a modal bottom sheet containing [QuickAddBar] for adding a task.
  void _showQuickAddSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _cardColor,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: QuickAddBar(onSubmitted: () => Navigator.of(sheetContext).pop()),
      ),
    );
  }

  /// Opens a modal bottom sheet displaying all tasks in [tier].
  void _showTierSheet(BuildContext context, TaskTier tier) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TierDetailSheet(tier: tier),
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

/// Switches between loading, error, and the main landing page scroll view.
class _LandingContentSwitcher extends StatelessWidget {
  /// Creates a [_LandingContentSwitcher].
  const _LandingContentSwitcher({
    required this.boardAsync,
    required this.searchQuery,
    required this.showOpenTaskCount,
    required this.onOpenSettings,
    required this.onRetry,
  });

  /// Asynchronous board state.
  final AsyncValue<TaskBoard> boardAsync;

  /// Callback to open settings.
  final VoidCallback onOpenSettings;

  /// Callback to retry remote synchronization.
  final VoidCallback onRetry;

  /// Current search filter query.
  final String searchQuery;

  /// Whether to render the total open task count on category and location cards.
  final bool showOpenTaskCount;

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
      data: (board) => _LandingScrollView(
        board: board,
        searchQuery: searchQuery,
        showOpenTaskCount: showOpenTaskCount,
      ),
    );
  }
}

/// Left-side navigation drawer containing secondary tiers, sync, Markdown preview, and settings.
class _LandingDrawer extends StatelessWidget {
  /// Creates a [_LandingDrawer].
  const _LandingDrawer({
    required this.board,
    required this.onOpenMarkdownPreview,
    required this.onOpenSettings,
    required this.onOpenTierSheet,
    required this.onSyncRemote,
  });

  static const List<TaskTier> _secondaryTiers = [
    TaskTier.ready,
    TaskTier.planned,
    TaskTier.blocked,
    TaskTier.someday,
    TaskTier.completed,
  ];

  /// Current task board snapshot.
  final TaskBoard board;

  /// Callback to open the raw Markdown preview dialog.
  final VoidCallback onOpenMarkdownPreview;

  /// Callback to navigate to [SettingsScreen].
  final VoidCallback onOpenSettings;

  /// Callback to open the task sheet for a specific [TaskTier].
  final ValueChanged<TaskTier> onOpenTierSheet;

  /// Callback to trigger remote synchronization.
  final VoidCallback onSyncRemote;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text(
                localizations.appTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(),
            for (final tier in _secondaryTiers)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(localizations.tierName(tier)),
                trailing: Badge.count(count: board.tasksForTier(tier).length),
                onTap: () {
                  Navigator.of(context).pop();
                  onOpenTierSheet(tier);
                },
              ),
            const Divider(),
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
        ),
      ),
    );
  }
}

/// Column layout inside [HomeScreen] combining the top bar, error banner, and content switcher.
class _LandingScaffoldBody extends StatelessWidget {
  /// Creates a [_LandingScaffoldBody].
  const _LandingScaffoldBody({
    required this.boardAsync,
    required this.errorMessage,
    required this.isSearching,
    required this.isSyncing,
    required this.searchController,
    required this.searchQuery,
    required this.showOpenTaskCount,
    required this.showSyncAction,
    required this.onClearError,
    required this.onOpenSettings,
    required this.onRetry,
    required this.onSearchChanged,
    required this.onSyncRemote,
    required this.onToggleSearch,
  });

  /// Asynchronous board state.
  final AsyncValue<TaskBoard> boardAsync;

  /// Optional synchronization error message.
  final String? errorMessage;

  /// Whether the inline search bar is active.
  final bool isSearching;

  /// Whether a synchronization request is in progress.
  final bool isSyncing;

  /// Callback to dismiss the error banner.
  final VoidCallback onClearError;

  /// Callback to open settings.
  final VoidCallback onOpenSettings;

  /// Callback to retry synchronization.
  final VoidCallback onRetry;

  /// Callback invoked when the search query changes.
  final ValueChanged<String> onSearchChanged;

  /// Callback to trigger WebDAV synchronization from the top bar.
  final VoidCallback onSyncRemote;

  /// Callback to toggle the search bar.
  final VoidCallback onToggleSearch;

  /// Text controller for the search input.
  final TextEditingController searchController;

  /// Active search query string.
  final String searchQuery;

  /// Whether to render the total open task count on category and location cards.
  final bool showOpenTaskCount;

  /// Whether the top bar should display the WebDAV sync action next to search.
  final bool showSyncAction;

  @override
  Widget build(BuildContext context) {
    final activeError = errorMessage;
    return Column(
      children: [
        _LandingTopBar(
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
            boardAsync: boardAsync,
            searchQuery: searchQuery,
            showOpenTaskCount: showOpenTaskCount,
            onOpenSettings: onOpenSettings,
            onRetry: onRetry,
          ),
        ),
      ],
    );
  }
}

/// Scrollable landing page body ordering greeting, Focus tasks, categories, and locations.
class _LandingScrollView extends StatelessWidget {
  /// Creates a [_LandingScrollView].
  const _LandingScrollView({
    required this.board,
    required this.searchQuery,
    required this.showOpenTaskCount,
  });

  /// Current task board snapshot.
  final TaskBoard board;

  /// Active search query string for filtering Focus tasks.
  final String searchQuery;

  /// Whether to render the total open task count on category and location cards.
  final bool showOpenTaskCount;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final filteredFocus = _filterFocusTasks(board.focus, searchQuery);
    final categories = _buildDraftCategories(localizations);
    final locations = _buildDraftLocations(localizations);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
      children: [
        Text(
          localizations.landingGreeting,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 28),
        _FocusTasksSection(tasks: filteredFocus),
        const SizedBox(height: 28),
        _ContextCardCarousel(
          sectionTitle: localizations.sectionCategories,
          items: categories,
          showOpenTaskCount: showOpenTaskCount,
        ),
        const SizedBox(height: 28),
        _ContextCardCarousel(
          sectionTitle: localizations.sectionLocations,
          items: locations,
          showOpenTaskCount: showOpenTaskCount,
        ),
      ],
    );
  }

  /// Builds the draft category cards with configurable accent line colors.
  List<_ContextCardData> _buildDraftCategories(AppLocalizations localizations) {
    return [
      _ContextCardData(
        id: 'category_business',
        name: localizations.categoryBusiness,
        taskCount: 40,
        accentColor: _accentMagenta,
      ),
      _ContextCardData(
        id: 'category_personal',
        name: localizations.categoryPersonal,
        taskCount: 18,
        accentColor: _accentBlue,
      ),
    ];
  }

  /// Builds the draft location cards with configurable accent line colors.
  List<_ContextCardData> _buildDraftLocations(AppLocalizations localizations) {
    return [
      _ContextCardData(
        id: 'location_home',
        name: localizations.locationHome,
        taskCount: 12,
        accentColor: _accentCyan,
      ),
      _ContextCardData(
        id: 'location_office',
        name: localizations.locationOffice,
        taskCount: 24,
        accentColor: _accentOrange,
      ),
    ];
  }

  /// Filters [tasks] by a case-insensitive substring match against [query].
  List<TaskItem> _filterFocusTasks(List<TaskItem> tasks, String query) {
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

/// Uppercase muted section heading label on the landing page.
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

/// Top navigation bar with the menu button on the left and search and optional sync on the right.
class _LandingTopBar extends StatelessWidget {
  /// Creates a [_LandingTopBar].
  const _LandingTopBar({
    required this.isSearching,
    required this.isSyncing,
    required this.searchController,
    required this.showSyncAction,
    required this.onSearchChanged,
    required this.onSyncRemote,
    required this.onToggleSearch,
  });

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
          Builder(
            builder: (drawerContext) => IconButton(
              tooltip: localizations.tooltipMenu,
              icon: const Icon(
                Icons.menu_rounded,
                color: _mutedLabelColor,
                size: 28,
              ),
              onPressed: () => Scaffold.of(drawerContext).openDrawer(),
            ),
          ),
          if (isSearching)
            Expanded(
              child: _TopBarSearchField(
                controller: searchController,
                onChanged: onSearchChanged,
              ),
            )
          else
            const Spacer(),
          IconButton(
            tooltip: isSearching
                ? localizations.actionClose
                : localizations.tooltipSearch,
            icon: Icon(
              isSearching ? Icons.close_rounded : Icons.search_rounded,
              color: _mutedLabelColor,
              size: 26,
            ),
            onPressed: onToggleSearch,
          ),
          if (showSyncAction)
            _TopBarSyncAction(isSyncing: isSyncing, onSyncRemote: onSyncRemote),
        ],
      ),
    );
  }
}

/// Full-width solid colored line rendered at the bottom of a category or location card.
class _SolidAccentBar extends StatelessWidget {
  /// Creates a [_SolidAccentBar].
  const _SolidAccentBar({required this.barKey, required this.color});

  /// Deterministic widget key for the colored bar.
  final Key barKey;

  /// Solid bar color defined for the category or location.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: barKey,
      height: 4,
      width: double.infinity,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.55),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
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

/// Modal sheet displaying the tasks of a single secondary [TaskTier] selected from the menu.
class _TierDetailSheet extends ConsumerWidget {
  /// Creates a [_TierDetailSheet].
  const _TierDetailSheet({required this.tier});

  /// Tier displayed inside this sheet.
  final TaskTier tier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board =
        ref.watch(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    final tasks = board.tasksForTier(tier);
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                localizations.tierName(tier),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                localizations.tierDescription(tier),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              _TierSheetTaskList(tier: tier, tasks: tasks),
            ],
          ),
        ),
      ),
    );
  }
}

/// Task list or empty-state message inside [_TierDetailSheet].
class _TierSheetTaskList extends StatelessWidget {
  /// Creates a [_TierSheetTaskList].
  const _TierSheetTaskList({required this.tier, required this.tasks});

  /// Tier being displayed.
  final TaskTier tier;

  /// Tasks belonging to [tier].
  final List<TaskItem> tasks;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    if (tasks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(localizations.tierEmptyHint(tier)),
      );
    }
    return Flexible(
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: tasks.length,
        itemBuilder: (context, index) => TaskTile(
          key: ValueKey('sheet_${tier.name}_${tasks[index].id}'),
          task: tasks[index],
          tier: tier,
        ),
      ),
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
