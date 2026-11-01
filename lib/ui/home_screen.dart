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
import 'category_screen.dart';
import 'settings_screen.dart';
import 'widgets/bottom_nav_bar.dart';
import 'widgets/context_management_sheet.dart';
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

/// Immutable display model for a category or location card on the landing page.
@immutable
class _ContextCardData {
  /// Creates a [_ContextCardData] instance.
  const _ContextCardData({
    required this.id,
    required this.name,
    required this.taskCount,
    required this.accentColor,
    this.onTap,
  });

  /// Color of the solid bottom accent bar.
  final Color accentColor;

  /// Deterministic identifier used for widget keys.
  final String id;

  /// Display name of the category or location.
  final String name;

  /// Optional callback invoked when the card is tapped.
  final VoidCallback? onTap;

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
    return Container(
      width: 190,
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('card_${item.id}'),
          borderRadius: BorderRadius.circular(20),
          onTap: item.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: _ContextSummaryCardColumn(
              item: item,
              showOpenTaskCount: showOpenTaskCount,
            ),
          ),
        ),
      ),
    );
  }
}

/// Inner column layout for [_ContextSummaryCard].
class _ContextSummaryCardColumn extends StatelessWidget {
  /// Creates a [_ContextSummaryCardColumn].
  const _ContextSummaryCardColumn({
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

    return Column(
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
    );
  }
}

/// Action tile inside [_LandingDrawer] that closes the drawer before invoking [onAction].
class _DrawerActionTile extends StatelessWidget {
  /// Creates a [_DrawerActionTile].
  const _DrawerActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onAction,
    this.count,
  });

  /// Optional item counter badge displayed at the trailing edge.
  final int? count;

  /// Leading icon for the menu item.
  final IconData icon;

  /// Callback invoked after closing the drawer.
  final VoidCallback onAction;

  /// Localized title text.
  final String title;

  @override
  Widget build(BuildContext context) {
    final badgeCount = count;
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      leading: Icon(icon),
      title: Text(title),
      trailing: badgeCount != null ? Badge.count(count: badgeCount) : null,
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
  bool _isTierMenuOpen = false;
  String _searchQuery = '';
  TaskTier _selectedTier = TaskTier.focus;

  /// Active bottom navigation button index (`0` for Focus, `1` for secondary tiers).
  int get _activeBottomNavIndex => _selectedTier == TaskTier.focus ? 0 : 1;

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
        onOpenContextSheet: (kind) => _showContextSheet(context, kind),
        onOpenMarkdownPreview: () => _showMarkdownPreviewDialog(context),
        onOpenSettings: () => _openSettings(context),
        onOpenTierSheet: _selectSecondaryTier,
        onSyncRemote: () =>
            ref.read(taskNotifierProvider.notifier).syncFromRemote(),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: BottomNavBar(
          activeButtonIndex: _activeBottomNavIndex,
          isTierMenuOpen: _isTierMenuOpen,
          selectedTier: _selectedTier,
          onSelectFocus: _selectFocusOverview,
          onToggleTierMenu: _toggleTierMenu,
          onQuickAdd: () => _showQuickAddSheet(context),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: _LandingScaffoldBody(
          boardAsync: boardAsync,
          errorMessage: syncState.errorMessage,
          isSearching: _isSearching,
          isSyncing: syncState.isSyncing,
          isTierMenuOpen: _isTierMenuOpen,
          searchController: _searchController,
          searchQuery: _searchQuery,
          selectedTier: _selectedTier,
          showOpenTaskCount: showOpenTaskCount,
          showSyncAction: showSyncAction,
          onClearError: () => ref.read(syncStateProvider.notifier).clearError(),
          onDismissTierMenu: _dismissTierMenu,
          onOpenSettings: () => _openSettings(context),
          onRetry: () =>
              ref.read(taskNotifierProvider.notifier).syncFromRemote(),
          onSearchChanged: _updateSearchQuery,
          onSelectTier: _selectSecondaryTier,
          onSyncRemote: () =>
              ref.read(taskNotifierProvider.notifier).syncFromRemote(),
          onToggleSearch: _toggleSearch,
        ),
      ),
    );
  }

  /// Closes the upward secondary-tier selection menu.
  void _dismissTierMenu() {
    if (!_isTierMenuOpen) {
      return;
    }
    setState(() {
      _isTierMenuOpen = false;
    });
  }

  /// Pushes [SettingsScreen] onto the navigation stack.
  void _openSettings(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  /// Switches the landing view back to the `Focus` overview (`TaskTier.focus`).
  void _selectFocusOverview() {
    setState(() {
      _selectedTier = TaskTier.focus;
      _isTierMenuOpen = false;
    });
  }

  /// Switches the landing view to the selected secondary [tier] and closes the upward menu.
  void _selectSecondaryTier(TaskTier tier) {
    setState(() {
      _selectedTier = tier;
      _isTierMenuOpen = false;
    });
  }

  /// Opens a modal bottom sheet for managing categories or locations ([kind]).
  void _showContextSheet(BuildContext context, ContextPanelKind kind) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ContextManagementSheet(kind: kind),
    );
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

  /// Toggles the upward secondary-tier selection menu.
  void _toggleTierMenu() {
    setState(() {
      _isTierMenuOpen = !_isTierMenuOpen;
    });
  }

  /// Updates the active search filter query.
  void _updateSearchQuery(String value) {
    setState(() {
      _searchQuery = value;
    });
  }
}

/// Stack inside [_LandingScaffoldBody] layering the content switcher and upward tier selection menu.
class _LandingBodyStack extends StatelessWidget {
  /// Creates a [_LandingBodyStack].
  const _LandingBodyStack({
    required this.boardAsync,
    required this.isTierMenuOpen,
    required this.searchQuery,
    required this.selectedTier,
    required this.showOpenTaskCount,
    required this.onDismissTierMenu,
    required this.onOpenSettings,
    required this.onRetry,
    required this.onSelectTier,
  });

  /// Asynchronous board state.
  final AsyncValue<TaskBoard> boardAsync;

  /// Whether the upward secondary-tier selection menu is open.
  final bool isTierMenuOpen;

  /// Callback to dismiss the upward tier selection menu.
  final VoidCallback onDismissTierMenu;

  /// Callback to open settings.
  final VoidCallback onOpenSettings;

  /// Callback to retry remote synchronization.
  final VoidCallback onRetry;

  /// Callback invoked when a secondary [TaskTier] is selected.
  final ValueChanged<TaskTier> onSelectTier;

  /// Active search query string.
  final String searchQuery;

  /// Currently selected [TaskTier] view.
  final TaskTier selectedTier;

  /// Whether to render the total open task count on category and location cards.
  final bool showOpenTaskCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: _LandingContentSwitcher(
            boardAsync: boardAsync,
            searchQuery: searchQuery,
            selectedTier: selectedTier,
            showOpenTaskCount: showOpenTaskCount,
            onOpenSettings: onOpenSettings,
            onRetry: onRetry,
          ),
        ),
        if (isTierMenuOpen) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismissTierMenu,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Positioned(
            bottom: 8,
            left: 24,
            right: 24,
            child: Center(
              child: UpwardTierSelectionMenu(
                board: boardAsync.asData?.value ?? TaskBoard.empty(),
                selectedTier: selectedTier,
                onSelectTier: onSelectTier,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Switches between loading, error, Focus overview, and secondary tier views.
class _LandingContentSwitcher extends StatelessWidget {
  /// Creates a [_LandingContentSwitcher].
  const _LandingContentSwitcher({
    required this.boardAsync,
    required this.searchQuery,
    required this.selectedTier,
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

  /// Currently selected [TaskTier] view.
  final TaskTier selectedTier;

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
      data: (board) => selectedTier == TaskTier.focus
          ? _LandingScrollView(
              board: board,
              searchQuery: searchQuery,
              showOpenTaskCount: showOpenTaskCount,
            )
          : _SecondaryTierView(
              board: board,
              searchQuery: searchQuery,
              tier: selectedTier,
            ),
    );
  }
}

/// Left-side navigation drawer containing secondary tiers, categories, locations, sync, preview, and settings.
class _LandingDrawer extends StatelessWidget {
  /// Creates a [_LandingDrawer].
  const _LandingDrawer({
    required this.board,
    required this.onOpenContextSheet,
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

  /// Callback to open the Categories or Locations management sheet.
  final ValueChanged<ContextPanelKind> onOpenContextSheet;

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

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _DrawerHeader(title: localizations.appTitle),
            const Divider(height: 8),
            for (final tier in _secondaryTiers)
              _DrawerActionTile(
                icon: Icons.folder_outlined,
                title: localizations.tierName(tier),
                count: board.tasksForTier(tier).length,
                onAction: () => onOpenTierSheet(tier),
              ),
            const Divider(height: 8),
            _DrawerActionTile(
              key: const ValueKey('drawer_categories_tile'),
              icon: Icons.label_outline_rounded,
              title: localizations.drawerCategories,
              count: board.categories.length,
              onAction: () => onOpenContextSheet(ContextPanelKind.categories),
            ),
            _DrawerActionTile(
              key: const ValueKey('drawer_locations_tile'),
              icon: Icons.location_on_outlined,
              title: localizations.drawerLocations,
              count: board.locations.length,
              onAction: () => onOpenContextSheet(ContextPanelKind.locations),
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

/// Column layout inside [HomeScreen] combining the top bar, error banner, content switcher, and upward tier menu.
class _LandingScaffoldBody extends StatelessWidget {
  /// Creates a [_LandingScaffoldBody].
  const _LandingScaffoldBody({
    required this.boardAsync,
    required this.errorMessage,
    required this.isSearching,
    required this.isSyncing,
    required this.isTierMenuOpen,
    required this.searchController,
    required this.searchQuery,
    required this.selectedTier,
    required this.showOpenTaskCount,
    required this.showSyncAction,
    required this.onClearError,
    required this.onDismissTierMenu,
    required this.onOpenSettings,
    required this.onRetry,
    required this.onSearchChanged,
    required this.onSelectTier,
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

  /// Whether the upward secondary-tier selection menu is open.
  final bool isTierMenuOpen;

  /// Callback to dismiss the error banner.
  final VoidCallback onClearError;

  /// Callback to dismiss the upward tier selection menu.
  final VoidCallback onDismissTierMenu;

  /// Callback to open settings.
  final VoidCallback onOpenSettings;

  /// Callback to retry synchronization.
  final VoidCallback onRetry;

  /// Callback invoked when the search query changes.
  final ValueChanged<String> onSearchChanged;

  /// Callback invoked when a secondary [TaskTier] is selected from the upward menu.
  final ValueChanged<TaskTier> onSelectTier;

  /// Callback to trigger WebDAV synchronization from the top bar.
  final VoidCallback onSyncRemote;

  /// Callback to toggle the search bar.
  final VoidCallback onToggleSearch;

  /// Text controller for the search input.
  final TextEditingController searchController;

  /// Active search query string.
  final String searchQuery;

  /// Currently active [TaskTier] view.
  final TaskTier selectedTier;

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
          child: _LandingBodyStack(
            boardAsync: boardAsync,
            isTierMenuOpen: isTierMenuOpen,
            searchQuery: searchQuery,
            selectedTier: selectedTier,
            showOpenTaskCount: showOpenTaskCount,
            onDismissTierMenu: onDismissTierMenu,
            onOpenSettings: onOpenSettings,
            onRetry: onRetry,
            onSelectTier: onSelectTier,
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
    final openTasks = _collectOpenTasks(board);
    final categories = _buildCategoryCards(
      context,
      board.categories,
      openTasks,
    );
    final locations = _buildLocationCards(board.locations, openTasks);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 28),
            _ContextCardCarousel(
              sectionTitle: localizations.sectionCategories,
              items: categories,
              showOpenTaskCount: showOpenTaskCount,
            ),
          ],
          if (locations.isNotEmpty) ...[
            const SizedBox(height: 28),
            _ContextCardCarousel(
              sectionTitle: localizations.sectionLocations,
              items: locations,
              showOpenTaskCount: showOpenTaskCount,
            ),
          ],
        ],
      ),
    );
  }

  /// Builds category summary cards from [categories] and counts matching [openTasks].
  List<_ContextCardData> _buildCategoryCards(
    BuildContext context,
    List<TdfCategory> categories,
    List<TaskItem> openTasks,
  ) {
    return [
      for (var i = 0; i < categories.length; i++)
        _ContextCardData(
          id: 'category_${categories[i].id}',
          name: categories[i].name,
          taskCount: _countCategoryTasks(openTasks, categories[i].id),
          accentColor: _resolveCategoryColor(categories[i].color, i),
          onTap: () => _openCategoryScreen(
            context,
            categories[i],
            _resolveCategoryColor(categories[i].color, i),
          ),
        ),
    ];
  }

  /// Builds location summary cards from [locations] and counts matching [openTasks].
  List<_ContextCardData> _buildLocationCards(
    List<TdfLocation> locations,
    List<TaskItem> openTasks,
  ) {
    return [
      for (var i = 0; i < locations.length; i++)
        _ContextCardData(
          id: 'location_${locations[i].id}',
          name: locations[i].name,
          taskCount: _countLocationTasks(openTasks, locations[i].id),
          accentColor: _resolveLocationColor(locations[i].color, i),
        ),
    ];
  }

  /// Returns all open (uncompleted) tasks across active and backlog tiers on [board].
  List<TaskItem> _collectOpenTasks(TaskBoard board) {
    return [
      ...board.focus,
      ...board.ready,
      ...board.planned,
      ...board.blocked,
      ...board.someday,
    ];
  }

  /// Counts how many tasks in [openTasks] reference [categoryId].
  int _countCategoryTasks(List<TaskItem> openTasks, String categoryId) {
    var count = 0;
    for (final task in openTasks) {
      if (task.categoryIds.contains(categoryId)) {
        count++;
      }
    }
    return count;
  }

  /// Counts how many tasks in [openTasks] reference [locationId].
  int _countLocationTasks(List<TaskItem> openTasks, String locationId) {
    var count = 0;
    for (final task in openTasks) {
      if (task.locationIds.contains(locationId)) {
        count++;
      }
    }
    return count;
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

  /// Pushes [CategoryScreen] for [category] onto the navigation stack.
  void _openCategoryScreen(
    BuildContext context,
    TdfCategory category,
    Color accentColor,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CategoryScreen(
          category: category,
          accentColor: accentColor,
          initialSearchQuery: searchQuery,
        ),
      ),
    );
  }

  /// Parses a `#RRGGBB` hex color string or falls back to the default category accent palette.
  Color _resolveCategoryColor(String? rawHexColor, int index) {
    final fallback = index.isEven ? _accentMagenta : _accentBlue;
    final parsedArgb = TdfColor.tryParseArgb(rawHexColor);
    return parsedArgb != null ? Color(parsedArgb) : fallback;
  }

  /// Parses a `#RRGGBB` hex color string or falls back to the default location accent palette.
  Color _resolveLocationColor(String? rawHexColor, int index) {
    final fallback = index.isEven ? _accentCyan : _accentOrange;
    final parsedArgb = TdfColor.tryParseArgb(rawHexColor);
    return parsedArgb != null ? Color(parsedArgb) : fallback;
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

/// Task list or empty-state message inside [_SecondaryTierView].
class _SecondaryTierTaskList extends StatelessWidget {
  /// Creates a [_SecondaryTierTaskList].
  const _SecondaryTierTaskList({required this.tier, required this.tasks});

  /// Tier being displayed.
  final TaskTier tier;

  /// Tasks belonging to [tier].
  final List<TaskItem> tasks;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    if (tasks.isEmpty) {
      return _EmptyFocusCard(message: localizations.tierEmptyHint(tier));
    }
    return Expanded(
      child: ListView.builder(
        itemCount: tasks.length,
        itemBuilder: (context, index) => TaskTile(
          key: ValueKey('tier_${tier.name}_${tasks[index].id}'),
          task: tasks[index],
          tier: tier,
        ),
      ),
    );
  }
}

/// Main content view displaying the tasks of a selected secondary [TaskTier].
class _SecondaryTierView extends StatelessWidget {
  /// Creates a [_SecondaryTierView].
  const _SecondaryTierView({
    required this.board,
    required this.searchQuery,
    required this.tier,
  });

  /// Current task board snapshot.
  final TaskBoard board;

  /// Active search query string for filtering tasks.
  final String searchQuery;

  /// Secondary [TaskTier] being displayed.
  final TaskTier tier;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tasks = _filterTasks(board.tasksForTier(tier), searchQuery);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localizations.tierName(tier),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            localizations.tierDescription(tier),
            style: const TextStyle(color: _mutedLabelColor, fontSize: 14),
          ),
          const SizedBox(height: 20),
          _SecondaryTierTaskList(tier: tier, tasks: tasks),
        ],
      ),
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
