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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../l10n/tier_localization_extension.dart';
import '../models/app_workspace.dart';
import '../models/storage_file_read_status.dart';
import '../models/task_board.dart';
import '../models/task_board_undo.dart';
import '../models/task_tier.dart';
import '../models/tdf_metadata.dart';
import '../models/webdav_config.dart';
import '../presentation/board_boundary_timer.dart';
import '../presentation/board_presentation_providers.dart';
import '../presentation/settings_controller.dart';
import '../presentation/ui_telemetry.dart';
import '../providers/config_providers.dart';
import '../providers/sync_providers.dart';
import '../providers/task_providers.dart';
import '../providers/workspace_providers.dart';
import 'edit_labels_screen.dart';
import 'edit_locations_screen.dart';
import 'settings_screen.dart';
import 'widgets/file_read_status_info.dart';
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

/// Renders either the structured [FileReadStatusCard] or fallback error text inside [_ErrorStateView].
class _ErrorStateBody extends StatelessWidget {
  /// Creates an [_ErrorStateBody].
  const _ErrorStateBody({required this.error, required this.report});

  final Object error;
  final StorageFileReadReport? report;

  @override
  Widget build(BuildContext context) {
    if (report case final activeReport?) {
      return FileReadStatusCard(report: activeReport);
    }
    final localizations = AppLocalizations.of(context);
    final message = switch (error) {
      final WorkspaceException workspaceError =>
        localizations.localizeWorkspaceError(workspaceError),
      _ => error.toString(),
    };
    return Text(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 14,
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

  final Object error;
  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final report = switch (error) {
      final StorageFileReadException readError => readError.report,
      _ => null,
    };
    final icon = report?.failureScope == StorageReadFailureScope.localOnly
        ? Icons.description_outlined
        : Icons.cloud_off_rounded;
    final title = report != null
        ? localizations.fileReadErrorTitle
        : localizations.syncErrorTitle;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _ErrorStateBody(error: error, report: report),
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

/// Primary [Scaffold] subtree for [HomeScreen].
class _HomeScaffold extends StatelessWidget {
  /// Creates a [_HomeScaffold].
  const _HomeScaffold({
    required this.activeLabel,
    required this.activeTier,
    required this.activeWorkspace,
    required this.board,
    required this.isQuickAddOpen,
    required this.isSearching,
    required this.pageController,
    required this.searchController,
    required this.searchQuery,
    required this.onCloseQuickAdd,
    required this.onOpenEditLabels,
    required this.onOpenEditLocations,
    required this.onOpenQuickAdd,
    required this.onOpenSettings,
    required this.onPageChanged,
    required this.onSearchChanged,
    required this.onSelectLabel,
    required this.onSelectTier,
    required this.onSyncRemote,
    required this.onToggleSearch,
  });

  final TdfLabel? activeLabel;
  final TaskTier activeTier;
  final AppWorkspace activeWorkspace;
  final TaskBoard board;
  final bool isQuickAddOpen;
  final bool isSearching;
  final VoidCallback onCloseQuickAdd;
  final ValueChanged<bool> onOpenEditLabels;
  final ValueChanged<bool> onOpenEditLocations;
  final VoidCallback onOpenQuickAdd;
  final VoidCallback onOpenSettings;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onSelectLabel;
  final ValueChanged<TaskTier> onSelectTier;
  final VoidCallback onSyncRemote;
  final VoidCallback onToggleSearch;
  final PageController pageController;
  final TextEditingController searchController;
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: HomeDrawer(
        activeLabelId: activeLabel?.id,
        activeWorkspace: activeWorkspace,
        board: board,
        onManageWorkspaces: () => showWorkspaceDialog(context),
        onOpenEditLabels: onOpenEditLabels,
        onOpenEditLocations: onOpenEditLocations,
        onOpenSettings: onOpenSettings,
        onSelectLabel: onSelectLabel,
        onSyncRemote: onSyncRemote,
      ),
      floatingActionButton: isQuickAddOpen
          ? null
          : _LandingFloatingButtons(onOpenQuickAdd: onOpenQuickAdd),
      bottomNavigationBar: isQuickAddOpen
          ? _QuickAddBottomBar(
              initialLabelId: activeLabel?.id,
              onClose: onCloseQuickAdd,
            )
          : null,
      body: _LandingScaffoldBody(
        activeLabel: activeLabel,
        activeTier: activeTier,
        isSearching: isSearching,
        pageController: pageController,
        searchController: searchController,
        searchQuery: searchQuery,
        onOpenSettings: onOpenSettings,
        onPageChanged: onPageChanged,
        onSearchChanged: onSearchChanged,
        onSelectTier: onSelectTier,
        onToggleSearch: onToggleSearch,
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
  PageController _pageController = PageController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleUndoKeyEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _consumeSettingsRecoveryNotice();
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleUndoKeyEvent);
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _watchScaffoldState();
    return _HomeScaffold(
      activeLabel: state.activeLabel,
      activeTier: _activeTier,
      activeWorkspace: state.workspace,
      board: state.board,
      isQuickAddOpen: _isQuickAddOpen,
      isSearching: _isSearching,
      pageController: _pageController,
      searchController: _searchController,
      searchQuery: _searchQuery,
      onCloseQuickAdd: _closeQuickAdd,
      onOpenEditLabels: _openEditLabels,
      onOpenEditLocations: _openEditLocations,
      onOpenQuickAdd: _openQuickAdd,
      onOpenSettings: _openSettings,
      onPageChanged: _handlePageChanged,
      onSearchChanged: _updateSearchQuery,
      onSelectLabel: _selectLabel,
      onSelectTier: _selectTierPane,
      onSyncRemote: () =>
          ref.read(taskNotifierProvider.notifier).syncFromRemote(),
      onToggleSearch: _toggleSearch,
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

  /// Consumes and displays a one-shot settings recovery [SnackBar] when startup recovery occurred.
  void _consumeSettingsRecoveryNotice() {
    if (!mounted) {
      return;
    }
    final message = ref
        .read(settingsControllerProvider)
        .consumeStartupRecoveryNotice(locale: Localizations.localeOf(context));
    if (message == null) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  /// Formats the localized undo [SnackBar] message for [notice].
  String _formatUndoMessage(
    AppLocalizations localizations,
    TaskUndoNotice notice,
  ) {
    return switch (notice.kind) {
      TaskUndoActionKind.complete => localizations.taskCompletedUndoSnackBar(
        notice.taskTitle,
      ),
      TaskUndoActionKind.downgrade => localizations.taskDowngradedUndoSnackBar(
        notice.taskTitle,
      ),
      TaskUndoActionKind.delete => localizations.taskDeletedUndoSnackBar(
        notice.taskTitle,
      ),
    };
  }

  /// Displays a one-shot recovery notice once [activeWorkspaceProvider] resolves asynchronously.
  void _handleActiveWorkspaceAsyncChanged(
    AsyncValue<AppWorkspace>? previous,
    AsyncValue<AppWorkspace> next,
  ) {
    if (next.hasValue) {
      _consumeSettingsRecoveryNotice();
    }
  }

  /// Synchronizes [_activeTier] when the user swipes between tier pages.
  void _handlePageChanged(int index) {
    if (_activeTier.index != index) {
      setState(() => _activeTier = TaskTier.values[index]);
    }
  }

  /// Handles desktop `Ctrl+Z` key-down events when [HomeScreen] is active and no text input is focused.
  bool _handleUndoKeyEvent(KeyEvent event) {
    final platform = defaultTargetPlatform;
    if (platform != TargetPlatform.linux &&
        platform != TargetPlatform.windows) {
      return false;
    }
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyZ) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed ||
        keyboard.isShiftPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return false;
    }
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return false;
    }
    if (_isEditableTextFocused()) {
      return false;
    }
    final undoState = ref.read(taskUndoStateProvider);
    if (!undoState.canUndo) {
      return false;
    }
    UiTelemetry.logUndoShortcut(stackDepth: undoState.stackDepth);
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    unawaited(ref.read(taskNotifierProvider.notifier).undoLastAction());
    return true;
  }

  /// Displays or hides the floating Undo [SnackBar] when [taskUndoStateProvider] changes.
  void _handleUndoNoticeChanged(
    TaskUndoNotice? previous,
    TaskUndoNotice? next,
  ) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }
    if (next == null) {
      messenger.hideCurrentSnackBar();
      return;
    }
    if (previous?.sequence == next.sequence) {
      return;
    }
    final localizations = AppLocalizations.of(context);
    final message = _formatUndoMessage(localizations, next);
    UiTelemetry.logUndoSnackBarShown(
      taskId: next.taskId,
      kind: next.kind,
      sequence: next.sequence,
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: ValueKey('task_undo_snackbar_${next.sequence}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          persist: false,
          margin: _isQuickAddOpen
              ? const EdgeInsets.fromLTRB(16, 0, 16, 60)
              : null,
          content: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
          action: SnackBarAction(
            label: localizations.actionUndo,
            onPressed: () => _triggerSnackBarUndo(next),
          ),
        ),
      );
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

  /// Returns `true` when the primary keyboard focus resides inside an [EditableText].
  bool _isEditableTextFocused() {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) {
      return false;
    }
    return focusedContext.widget is EditableText ||
        focusedContext.findAncestorStateOfType<EditableTextState>() != null;
  }

  /// Pushes [EditLabelsScreen] onto the navigation stack.
  void _openEditLabels(bool autofocusCreate) {
    UiTelemetry.logScreenOpened('EditLabelsScreen');
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditLabelsScreen(autofocusCreate: autofocusCreate),
      ),
    );
  }

  /// Pushes [EditLocationsScreen] onto the navigation stack.
  void _openEditLocations(bool autofocusCreate) {
    UiTelemetry.logScreenOpened('EditLocationsScreen');
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
    UiTelemetry.logScreenOpened('SettingsScreen');
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

  /// Dispatches [TaskNotifier.undoLastAction] for [notice] when the SnackBar action is pressed.
  void _triggerSnackBarUndo(TaskUndoNotice notice) {
    if (!mounted) {
      return;
    }
    UiTelemetry.logUndoSnackBarAction(
      taskId: notice.taskId,
      kind: notice.kind,
      sequence: notice.sequence,
    );
    unawaited(
      ref
          .read(taskNotifierProvider.notifier)
          .undoLastAction(expectedSequence: notice.sequence),
    );
  }

  /// Updates the active search filter query.
  void _updateSearchQuery(String value) => setState(() => _searchQuery = value);

  /// Watches the active workspace, live boundary timer, and task board snapshot for [HomeScreen].
  ({AppWorkspace workspace, TaskBoard board, TdfLabel? activeLabel})
  _watchScaffoldState() {
    ref.watch(boardBoundaryTimerProvider);
    ref.listen<AsyncValue<AppWorkspace>>(
      activeWorkspaceProvider,
      _handleActiveWorkspaceAsyncChanged,
    );
    ref.listen<String?>(
      activeWorkspaceProvider.select((workspace) => workspace.asData?.value.id),
      _handleWorkspaceChanged,
    );
    ref.listen<TaskUndoNotice?>(
      taskUndoStateProvider.select((state) => state.latestNotice),
      _handleUndoNoticeChanged,
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
    final workspaceAsync = ref.watch(activeWorkspaceProvider);
    if (workspaceAsync.hasError) {
      return _ErrorStateView(
        error: workspaceAsync.error ?? StateError('Settings load failed.'),
        onRetry: () => ref.invalidate(activeWorkspaceProvider),
        onOpenSettings: onOpenSettings,
      );
    }
    final evaluatedBoardAsync = ref.watch(
      evaluatedBoardProvider(activeLabel?.id),
    );
    return evaluatedBoardAsync.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: colorScheme.primary)),
      error: (error, _) => _ErrorStateView(
        error: error,
        onRetry: () {
          if (ref.read(activeWorkspaceProvider).hasError) {
            ref.invalidate(activeWorkspaceProvider);
            return;
          }
          ref.read(taskNotifierProvider.notifier).syncFromRemote();
        },
        onOpenSettings: onOpenSettings,
      ),
      data: (effectiveBoard) {
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
            activeLabelId: activeLabel?.id,
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
  const _QuickAddBottomBar({
    required this.initialLabelId,
    required this.onClose,
  });

  final String? initialLabelId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: QuickAddBar(
        initialLabelId: initialLabelId,
        onCancel: onClose,
        onSubmitted: onClose,
      ),
    );
  }
}

/// Dismissible error banner shown when a background WebDAV or local sync fails.
class _SyncErrorBanner extends ConsumerWidget {
  /// Creates a [_SyncErrorBanner].
  const _SyncErrorBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasBoardError = ref.watch(
      taskNotifierProvider.select((board) => board.hasError),
    );
    final syncError = ref.watch(
      syncStateProvider.select(
        (state) => (message: state.errorMessage, report: state.fileReadReport),
      ),
    );
    final message = syncError.message;
    if (message == null || hasBoardError) {
      return const SizedBox.shrink();
    }
    return _SyncErrorBannerCard(
      message: message,
      report: syncError.report,
      onDismiss: () => ref.read(syncStateProvider.notifier).clearError(),
    );
  }
}

/// Visual banner strip inside [_SyncErrorBanner].
class _SyncErrorBannerCard extends StatelessWidget {
  /// Creates a [_SyncErrorBannerCard].
  const _SyncErrorBannerCard({
    required this.message,
    required this.report,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;
  final StorageFileReadReport? report;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = colorScheme.onErrorContainer;
    final activeReport = report;
    return Material(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: activeReport != null
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 20, color: foregroundColor),
            const SizedBox(width: 10),
            Expanded(
              child: activeReport != null
                  ? FileReadStatusBannerContent(
                      report: activeReport,
                      foregroundColor: foregroundColor,
                    )
                  : Text(
                      message,
                      style: TextStyle(fontSize: 13, color: foregroundColor),
                    ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 18, color: foregroundColor),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}
