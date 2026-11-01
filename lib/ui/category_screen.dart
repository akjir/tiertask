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
import '../models/task_board.dart';
import '../models/task_item.dart';
import '../models/tdf_metadata.dart';
import '../providers/task_providers.dart';
import 'widgets/quick_add_bar.dart';

const Color _accentBlue = Color(0xFF2196F3);
const Color _accentMagenta = Color(0xFFEB06FF);
const Color _canvasColor = Color(0xFF344FA1);
const Color _cardColor = Color(0xFF071A52);
const Color _mutedLabelColor = Color(0xFF9BA8E5);

/// Screen displaying the 3 derived Tier 1 (`Focus`) tasks filtered by [category].
class CategoryScreen extends ConsumerStatefulWidget {
  /// Creates a [CategoryScreen] for [category].
  const CategoryScreen({
    super.key,
    required this.category,
    required this.accentColor,
    this.initialSearchQuery = '',
  });

  /// Resolved accent color for the category header bar.
  final Color accentColor;

  /// Category used to filter the active task pipeline.
  final TdfCategory category;

  /// Initial search query inherited from the landing page.
  final String initialSearchQuery;

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

/// Switches between loading, error, and the category task scroll view.
class _CategoryContentSwitcher extends StatelessWidget {
  /// Creates a [_CategoryContentSwitcher].
  const _CategoryContentSwitcher({
    required this.accentColor,
    required this.boardAsync,
    required this.category,
    required this.evaluationTime,
    required this.searchQuery,
    required this.onRetry,
  });

  /// Resolved accent color for the category header bar.
  final Color accentColor;

  /// Asynchronous board state.
  final AsyncValue<TaskBoard> boardAsync;

  /// Category used to filter tasks.
  final TdfCategory category;

  /// Reference UTC timestamp for evaluating blocking and condition rules.
  final DateTime evaluationTime;

  /// Callback to retry remote synchronization.
  final VoidCallback onRetry;

  /// Current search filter query.
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    return boardAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: _accentMagenta)),
      error: (error, _) =>
          _CategoryErrorView(error: error.toString(), onRetry: onRetry),
      data: (board) => _CategoryScrollView(
        accentColor: accentColor,
        board: board,
        category: _resolveLatestCategory(board),
        evaluationTime: evaluationTime,
        searchQuery: searchQuery,
      ),
    );
  }

  /// Resolves the up-to-date [TdfCategory] from [board] or falls back to [category].
  TdfCategory _resolveLatestCategory(TaskBoard board) {
    for (final item in board.categories) {
      if (item.id == category.id) {
        return item;
      }
    }
    return category;
  }
}

/// Error state view displayed when board synchronization fails on [CategoryScreen].
class _CategoryErrorView extends StatelessWidget {
  /// Creates a [_CategoryErrorView].
  const _CategoryErrorView({required this.error, required this.onRetry});

  /// Error description string.
  final String error;

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
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(localizations.actionRetry),
            ),
          ],
        ),
      ),
    );
  }
}

/// Minimal pill card representing a single Tier 1 (`Focus`) task on [CategoryScreen].
class _CategoryFocusTaskPill extends ConsumerWidget {
  /// Creates a [_CategoryFocusTaskPill].
  const _CategoryFocusTaskPill({
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

/// Section displaying the 3 derived Tier 1 (`Focus`) tasks for the selected category.
class _CategoryFocusTasksSection extends StatelessWidget {
  /// Creates a [_CategoryFocusTasksSection].
  const _CategoryFocusTasksSection({required this.tasks});

  /// Filtered Focus tasks to render.
  final List<TaskItem> tasks;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.sectionFocusTasks,
          style: const TextStyle(
            color: _mutedLabelColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 12),
        if (tasks.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              localizations.emptyFocusHint,
              style: const TextStyle(color: _mutedLabelColor, fontSize: 15),
            ),
          )
        else
          for (var i = 0; i < tasks.length; i++)
            _CategoryFocusTaskPill(
              key: ValueKey('focus_pill_${tasks[i].id}'),
              task: tasks[i],
              ringColor: i.isEven ? _accentMagenta : _accentBlue,
            ),
      ],
    );
  }
}

/// Column layout inside [CategoryScreen] combining the top bar, error banner, and content switcher.
class _CategoryScaffoldBody extends StatelessWidget {
  /// Creates a [_CategoryScaffoldBody].
  const _CategoryScaffoldBody({
    required this.accentColor,
    required this.boardAsync,
    required this.category,
    required this.errorMessage,
    required this.evaluationTime,
    required this.isSearching,
    required this.isSyncing,
    required this.searchController,
    required this.searchQuery,
    required this.showSyncAction,
    required this.onClearError,
    required this.onRetry,
    required this.onSearchChanged,
    required this.onSyncRemote,
    required this.onToggleSearch,
  });

  /// Resolved accent color for the category header bar.
  final Color accentColor;

  /// Asynchronous board state.
  final AsyncValue<TaskBoard> boardAsync;

  /// Category used to filter tasks.
  final TdfCategory category;

  /// Optional synchronization error message.
  final String? errorMessage;

  /// Reference UTC timestamp for evaluating blocking and condition rules.
  final DateTime evaluationTime;

  /// Whether the inline search bar is active.
  final bool isSearching;

  /// Whether a synchronization request is in progress.
  final bool isSyncing;

  /// Callback to dismiss the error banner.
  final VoidCallback onClearError;

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

  /// Whether the top bar should display the WebDAV sync action next to search.
  final bool showSyncAction;

  @override
  Widget build(BuildContext context) {
    final activeError = errorMessage;
    return Column(
      children: [
        _CategoryTopBar(
          isSearching: isSearching,
          isSyncing: isSyncing,
          searchController: searchController,
          showSyncAction: showSyncAction,
          onSearchChanged: onSearchChanged,
          onSyncRemote: onSyncRemote,
          onToggleSearch: onToggleSearch,
        ),
        if (activeError != null)
          _CategorySyncErrorBanner(
            message: activeError,
            onDismiss: onClearError,
          ),
        Expanded(
          child: _CategoryContentSwitcher(
            accentColor: accentColor,
            boardAsync: boardAsync,
            category: category,
            evaluationTime: evaluationTime,
            searchQuery: searchQuery,
            onRetry: onRetry,
          ),
        ),
      ],
    );
  }
}

/// State for [CategoryScreen].
class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  late final TextEditingController _searchController;
  late bool _isSearching;
  late String _searchQuery;

  @override
  void initState() {
    super.initState();
    _searchQuery = widget.initialSearchQuery;
    _isSearching = widget.initialSearchQuery.trim().isNotEmpty;
    _searchController = TextEditingController(text: widget.initialSearchQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boardAsync = ref.watch(taskNotifierProvider);
    final syncState = ref.watch(syncStateProvider);
    final evaluationTime = ref.watch(clockProvider)();
    final showSyncAction = ref.watch(
      webDavConfigProvider.select(
        (configAsync) =>
            configAsync.asData?.value.storageMode.usesWebDav ?? false,
      ),
    );

    return Scaffold(
      backgroundColor: _canvasColor,
      floatingActionButton: FloatingActionButton(
        backgroundColor: _accentMagenta,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        onPressed: () => _showQuickAddSheet(context),
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      body: SafeArea(
        child: _CategoryScaffoldBody(
          accentColor: widget.accentColor,
          boardAsync: boardAsync,
          category: widget.category,
          errorMessage: syncState.errorMessage,
          evaluationTime: evaluationTime,
          isSearching: _isSearching,
          isSyncing: syncState.isSyncing,
          searchController: _searchController,
          searchQuery: _searchQuery,
          showSyncAction: showSyncAction,
          onClearError: () => ref.read(syncStateProvider.notifier).clearError(),
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

  /// Opens a modal bottom sheet containing [QuickAddBar] pre-selecting [CategoryScreen.category].
  void _showQuickAddSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _cardColor,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: QuickAddBar(
          initialCategoryIds: {widget.category.id},
          onSubmitted: () => Navigator.of(sheetContext).pop(),
        ),
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

/// Scrollable body inside [CategoryScreen] displaying the category title, accent bar, and 3 Focus tasks.
class _CategoryScrollView extends StatelessWidget {
  /// Creates a [_CategoryScrollView].
  const _CategoryScrollView({
    required this.accentColor,
    required this.board,
    required this.category,
    required this.evaluationTime,
    required this.searchQuery,
  });

  /// Resolved accent color for the category header bar.
  final Color accentColor;

  /// Full task board snapshot.
  final TaskBoard board;

  /// Active category definition.
  final TdfCategory category;

  /// Reference UTC timestamp for evaluating blocking and condition rules.
  final DateTime evaluationTime;

  /// Active search query string for filtering tasks.
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    final categoryBoard = board.evaluateForContext(
      activeCategoryId: category.id,
      evaluationTime: evaluationTime,
    );
    final filteredFocus = _filterFocusTasks(categoryBoard.focus, searchQuery);
    final resolvedColor = _resolveColor(category.color, accentColor);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
      children: [
        Text(
          category.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          key: ValueKey('category_header_accent_${category.id}'),
          height: 4,
          width: 72,
          decoration: BoxDecoration(
            color: resolvedColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 28),
        _CategoryFocusTasksSection(tasks: filteredFocus),
      ],
    );
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

  /// Resolves a `#RRGGBB` hex color string or falls back to [fallback].
  Color _resolveColor(String? rawHexColor, Color fallback) {
    final parsedArgb = TdfColor.tryParseArgb(rawHexColor);
    return parsedArgb != null ? Color(parsedArgb) : fallback;
  }
}

/// Dismissible error banner shown on [CategoryScreen] when a background WebDAV sync fails.
class _CategorySyncErrorBanner extends StatelessWidget {
  /// Creates a [_CategorySyncErrorBanner].
  const _CategorySyncErrorBanner({
    required this.message,
    required this.onDismiss,
  });

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

/// Top navigation bar on [CategoryScreen] with a back button, inline search, and optional sync action.
class _CategoryTopBar extends StatelessWidget {
  /// Creates a [_CategoryTopBar].
  const _CategoryTopBar({
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
          const BackButton(color: _mutedLabelColor),
          if (isSearching)
            Expanded(
              child: TextField(
                controller: searchController,
                autofocus: true,
                onChanged: onSearchChanged,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: localizations.searchHint,
                  hintStyle: const TextStyle(color: _mutedLabelColor),
                  border: InputBorder.none,
                  isDense: true,
                ),
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
            _CategoryTopBarSyncAction(
              isSyncing: isSyncing,
              onSyncRemote: onSyncRemote,
            ),
        ],
      ),
    );
  }
}

/// Sync button or progress spinner rendered next to search on [CategoryScreen].
class _CategoryTopBarSyncAction extends StatelessWidget {
  /// Creates a [_CategoryTopBarSyncAction].
  const _CategoryTopBarSyncAction({
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
