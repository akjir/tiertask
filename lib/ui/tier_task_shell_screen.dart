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

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../l10n/tier_localization_extension.dart';
import '../models/app_workspace.dart';
import '../models/location_state.dart';
import '../models/task_board.dart';
import '../models/task_board_evaluator.dart';
import '../models/task_tier.dart';
import '../models/tdf_location.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_sync_metadata.dart';
import '../models/webdav_config.dart';
import '../providers/board_providers.dart';
import '../providers/config_providers.dart';
import '../providers/entity_actions_provider.dart';
import '../providers/floating_notice_providers.dart';
import '../providers/location_providers.dart';
import '../providers/shell_providers.dart';
import '../providers/sync_providers.dart';
import '../providers/task_providers.dart';
import '../providers/task_schedule_helper.dart';
import '../providers/workspace_providers.dart';
import 'dialogs/location_status_modal.dart';
import 'dialogs/workspaces_modal.dart';
import 'layout/ui_adaptive_app_shell.dart';
import 'layout/ui_sidebar_section.dart';
import 'primitives/ui_app_logo.dart';
import 'primitives/ui_banner.dart';
import 'primitives/ui_button.dart';
import 'primitives/ui_field.dart';
import 'primitives/ui_pill.dart';
import 'tokens/ui_breakpoints.dart';
import 'tokens/ui_theme_tokens.dart';
import 'tokens/ui_typography_tokens.dart';
import 'ui_domain_mappers.dart';
import 'views/labels_view.dart';
import 'views/locations_view.dart';
import 'views/log_viewer_view.dart';
import 'views/raw_tdf_view.dart';
import 'views/resolution_views.dart';
import 'views/settings_view.dart';
import 'views/tasks_view.dart';

/// Root adaptive application shell hosting navigation, chrome, notices, docks, and route views.
class TierTaskShellScreen extends ConsumerStatefulWidget {
  /// Creates the root [TierTaskShellScreen].
  const TierTaskShellScreen({super.key});

  @override
  ConsumerState<TierTaskShellScreen> createState() =>
      _TierTaskShellScreenState();
}

/// Manages scroll offset preservation, global desktop shortcuts, Android `PopScope`,
/// boundary timer subscription, and startup recovery notices for [TierTaskShellScreen].
class _TierTaskShellScreenState extends ConsumerState<TierTaskShellScreen> {
  final ScrollController _labelsScrollController = ScrollController();
  final ScrollController _locationsScrollController = ScrollController();
  final FocusNode _quickAddFocusNode = FocusNode();
  final FocusNode _rootFocusNode = FocusNode(debugLabel: 'TierTaskShellRoot');
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _settingsScrollController = ScrollController();
  final ScrollController _sidebarScrollController = ScrollController();
  final ScrollController _tasksScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref
          .read(floatingNoticeProvider.notifier)
          .showStartupRecoveryNoticeIfPending();
    });
  }

  @override
  void dispose() {
    _labelsScrollController.dispose();
    _locationsScrollController.dispose();
    _quickAddFocusNode.dispose();
    _rootFocusNode.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _settingsScrollController.dispose();
    _sidebarScrollController.dispose();
    _tasksScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep live due, lead-window, suspension, and condition time boundaries ticking.
    ref.watch(boardBoundaryTimerProvider);
    _registerScopeListeners();

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: _handlePopInvoked,
      child: Focus(
        focusNode: _rootFocusNode,
        autofocus: true,
        skipTraversal: true,
        onKeyEvent: _handleRootKeyEvent,
        child: _ShellAdaptiveScaffold(
          controllers: _ShellControllers(
            labelsScroll: _labelsScrollController,
            locationsScroll: _locationsScrollController,
            quickAddFocus: _quickAddFocusNode,
            search: _searchController,
            searchFocus: _searchFocusNode,
            settingsScroll: _settingsScrollController,
            sidebarScroll: _sidebarScrollController,
            tasksScroll: _tasksScrollController,
          ),
          onOpenSearch: _openSearchAndFocus,
        ),
      ),
    );
  }

  /// Expands compact composer if needed and focuses the Task Quick-Add title input.
  void _focusQuickAddComposer() {
    final isCompact = UiBreakpoints.isCompact(MediaQuery.sizeOf(context).width);
    if (isCompact) {
      ref.read(shellProvider.notifier).setCompactComposerOpen(true);
    }
    if (!isCompact &&
        _quickAddFocusNode.context != null &&
        _quickAddFocusNode.canRequestFocus) {
      _quickAddFocusNode.requestFocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _quickAddFocusNode.canRequestFocus) {
        _quickAddFocusNode.requestFocus();
      }
    });
  }

  /// Delegates Android system Back presses when [PopScope] intercepts a route pop.
  void _handlePopInvoked(bool didPop, Object? result) {
    if (didPop) {
      return;
    }
    _handleSystemBack();
  }

  /// Handles global desktop keyboard shortcuts (`U-A11Y-002`).
  KeyEventResult _handleRootKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final primaryPressed =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final shell = ref.read(shellProvider);
    final blockedByLoadOrError = _isTasksViewBlocked(
      ref.read(activeWorkspaceProvider),
      ref.read(taskNotifierProvider),
    );

    if (primaryPressed && key == LogicalKeyboardKey.keyF) {
      if (blockedByLoadOrError) {
        return KeyEventResult.handled;
      }
      _openSearchAndFocus();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape) {
      final outcome = ref.read(shellProvider.notifier).handleEscape();
      return outcome == ShellDismissOutcome.handled
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    if (_isFocusInsideTextInput()) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.slash && !blockedByLoadOrError) {
      _openSearchAndFocus();
      return KeyEventResult.handled;
    }
    if (primaryPressed &&
        key == LogicalKeyboardKey.keyZ &&
        shell.view == ShellView.tasks &&
        ref.read(taskUndoStateProvider).canUndo) {
      unawaited(
        ref
            .read(floatingNoticeProvider.notifier)
            .undoLatest(fromShortcut: true),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN &&
        shell.view == ShellView.tasks &&
        !shell.searchOpen &&
        shell.activeDraft != EntityDraftKind.task &&
        !blockedByLoadOrError) {
      _focusQuickAddComposer();
      return KeyEventResult.handled;
    }
    if (shell.view == ShellView.tasks && !shell.searchOpen) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        ref.read(shellProvider.notifier).stepTier(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        ref.read(shellProvider.notifier).stepTier(1);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Delegates Android system Back presses to `ShellNotifier.handleSystemBack()`.
  void _handleSystemBack() {
    final outcome = ref.read(shellProvider.notifier).handleSystemBack();
    if (outcome == ShellDismissOutcome.allowSystemPop) {
      unawaited(SystemNavigator.pop());
    }
  }

  /// Returns `true` when keyboard focus currently resides inside an editable text field.
  bool _isFocusInsideTextInput() {
    final primaryContext = FocusManager.instance.primaryFocus?.context;
    if (primaryContext == null) {
      return false;
    }
    if (primaryContext.widget is EditableText) {
      return true;
    }
    return primaryContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// Opens Global Search on Tasks view and focuses the search input after layout.
  void _openSearchAndFocus() {
    final wasOpen = ref.read(shellProvider).searchOpen;
    ref.read(shellProvider.notifier).openSearch();
    if (wasOpen &&
        _searchFocusNode.context != null &&
        _searchFocusNode.canRequestFocus) {
      _searchFocusNode.requestFocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchFocusNode.canRequestFocus) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  /// Registers listeners preserving scroll offsets and syncing the search text controller (`U-LAYOUT-007`).
  void _registerScopeListeners() {
    ref.listen<String?>(
      activeWorkspaceProvider.select((workspace) => workspace.asData?.value.id),
      (previous, next) {
        if (previous != null && next != null && previous != next) {
          _resetScrollController(_sidebarScrollController);
          _resetScrollController(_tasksScrollController);
        }
      },
    );
    ref.listen<String>(searchQueryProvider, (_, next) {
      if (_searchController.text != next) {
        _searchController.text = next;
      }
    });
    ref.listen<
      ({ShellView view, TaskTier tier, String? labelId, bool searchOpen})
    >(
      shellProvider.select(
        (shell) => (
          view: shell.view,
          tier: shell.activeTier,
          labelId: shell.activeLabelId,
          searchOpen: shell.searchOpen,
        ),
      ),
      (previous, next) {
        if (previous != null && previous != next) {
          _resetScrollController(_tasksScrollController);
        }
      },
    );
  }

  /// Resets [controller] to offset `0` when currently attached to a scroll position.
  void _resetScrollController(ScrollController controller) {
    if (controller.hasClients) {
      controller.jumpTo(0.0);
    }
  }
}

/// Immutable bundle of scroll, search, and focus controllers owned by [_TierTaskShellScreenState].
@immutable
class _ShellControllers {
  /// Creates a [_ShellControllers].
  const _ShellControllers({
    required this.labelsScroll,
    required this.locationsScroll,
    required this.quickAddFocus,
    required this.search,
    required this.searchFocus,
    required this.settingsScroll,
    required this.sidebarScroll,
    required this.tasksScroll,
  });

  /// Preserved scroll controller for [LabelsView].
  final ScrollController labelsScroll;

  /// Preserved scroll controller for [LocationsView].
  final ScrollController locationsScroll;

  /// Focus node routed to [TasksQuickAddDock] for the global `n` shortcut.
  final FocusNode quickAddFocus;

  /// Global search text editing controller.
  final TextEditingController search;

  /// Global search input focus node.
  final FocusNode searchFocus;

  /// Preserved scroll controller for [SettingsView].
  final ScrollController settingsScroll;

  /// Preserved scroll controller for the sidebar navigation list.
  final ScrollController sidebarScroll;

  /// Preserved scroll controller for [TasksView].
  final ScrollController tasksScroll;
}

/// Watches narrow shell chrome slices so search, sidebar filter, or card-expand edits never rebuild [UiAdaptiveAppShell].
class _ShellAdaptiveScaffold extends ConsumerWidget {
  /// Creates a [_ShellAdaptiveScaffold].
  const _ShellAdaptiveScaffold({
    required this.controllers,
    required this.onOpenSearch,
  });

  /// Preserved scroll, search, and focus controllers.
  final _ShellControllers controllers;

  /// Callback opening Global Search and focusing the search input.
  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shellSlice = ref.watch(
      shellProvider.select(
        (shell) => (
          view: shell.view,
          searchOpen: shell.searchOpen,
          compactDrawerOpen: shell.compactDrawerOpen,
          hasTaskDraft: shell.activeDraft == EntityDraftKind.task,
          activeLabelId: shell.activeLabelId,
        ),
      ),
    );
    final isTasksBlocked =
        shellSlice.view == ShellView.tasks &&
            ref.watch(
              activeWorkspaceProvider.select((workspace) => workspace.hasError),
            ) ||
        (shellSlice.view == ShellView.tasks &&
            ref.watch(
              taskNotifierProvider.select(
                (boardAsync) =>
                    (boardAsync.isLoading || boardAsync.hasError) &&
                    !boardAsync.hasValue,
              ),
            ));
    final isCompact = UiBreakpoints.isCompact(MediaQuery.sizeOf(context).width);
    final mobileFilterName = _watchMobileFilterLabelName(
      ref,
      view: shellSlice.view,
      searchOpen: shellSlice.searchOpen,
      activeLabelId: shellSlice.activeLabelId,
    );
    final showDock = _hasBottomDock(
      view: shellSlice.view,
      searchOpen: shellSlice.searchOpen,
      hasTaskDraft: shellSlice.hasTaskDraft,
      isTasksBlocked: isTasksBlocked,
    );

    return _ShellAdaptiveView(
      view: shellSlice.view,
      isSearchOpen: shellSlice.searchOpen,
      isDrawerOpen: shellSlice.compactDrawerOpen,
      isCompact: isCompact,
      sidebarScrollController: controllers.sidebarScroll,
      mobileActiveFilter: mobileFilterName == null
          ? null
          : _MobileActiveFilterButton(labelName: mobileFilterName),
      searchWidget: _ShellSearchControl(
        isCompact: isCompact,
        controllers: controllers,
        onOpen: onOpenSearch,
      ),
      bottomDock: showDock
          ? _ShellBottomDock(
              view: shellSlice.view,
              quickAddFocusNode: controllers.quickAddFocus,
            )
          : null,
      body: _ShellMainBody(view: shellSlice.view, controllers: controllers),
    );
  }
}

/// Composes [UiAdaptiveAppShell] chrome, sidebar, notices, bottom dock, and route body.
class _ShellAdaptiveView extends ConsumerWidget {
  /// Creates a [_ShellAdaptiveView].
  const _ShellAdaptiveView({
    required this.view,
    required this.isSearchOpen,
    required this.isDrawerOpen,
    required this.isCompact,
    required this.sidebarScrollController,
    required this.mobileActiveFilter,
    required this.searchWidget,
    required this.bottomDock,
    required this.body,
  });

  /// Main pane route body widget.
  final Widget body;

  /// Optional pinned bottom dock widget.
  final Widget? bottomDock;

  /// Whether viewport is in compact mode.
  final bool isCompact;

  /// Whether the compact navigation drawer is open.
  final bool isDrawerOpen;

  /// Whether Global Search is open.
  final bool isSearchOpen;

  /// Optional compact active-label filter chip.
  final Widget? mobileActiveFilter;

  /// Top chrome global search control widget.
  final Widget searchWidget;

  /// Preserved sidebar scroll controller.
  final ScrollController sidebarScrollController;

  /// Active route view.
  final ShellView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final isDevBuild = ref.watch(
      appBuildProfileProvider.select((profile) => profile.isDev),
    );
    final locationEnabled = ref.watch(locationEnabledProvider);
    final showWindow = ref.watch(
      desktopWindowActionsProvider.select((actions) => actions.isSupported),
    );
    final hasNotice = ref.watch(
      floatingNoticeProvider.select((notice) => notice != null),
    );

    return UiAdaptiveAppShell(
      brand: const _ShellBrandButton(),
      mobileActiveFilter: mobileActiveFilter,
      workspaceTrigger: const _WorkspaceChromeTrigger(),
      buildBadge: isDevBuild ? const _ShellDevBadge() : null,
      searchWidget: searchWidget,
      isSearchOpen: isSearchOpen,
      trailingActions: <Widget>[
        if (locationEnabled) const _ChromeLocationButton(),
        _ChromeSyncButton(isCompact: isCompact),
        if (showWindow) const _ChromeCloseWindowButton(),
      ],
      onChromeDragStart: showWindow ? () => _startWindowDrag(ref) : null,
      onChromeDoubleTap: showWindow ? () => _toggleWindowMaximize(ref) : null,
      isDrawerOpen: isDrawerOpen,
      onToggleDrawer: () => _toggleCompactDrawer(ref, isDrawerOpen),
      menuOpenTooltip: localizations.tooltipMenu,
      menuCloseTooltip: localizations.actionClose,
      sidebarHeader: const _CompactDrawerWorkspaceCard(),
      sidebarBody: const _ShellSidebarBody(),
      sidebarFooter: const _ShellSidebarFooter(),
      sidebarScrollController: sidebarScrollController,
      floatingNotice: hasNotice ? const _ShellFloatingNotice() : null,
      bottomDock: bottomDock,
      body: body,
    );
  }
}

/// Exhaustive bottom dock widget switcher for routes displaying a pinned footer dock (`U-LAYOUT-005`).
class _ShellBottomDock extends StatelessWidget {
  /// Creates a [_ShellBottomDock].
  const _ShellBottomDock({required this.view, required this.quickAddFocusNode});

  /// Focus node routed to [TasksQuickAddDock] for the global `n` shortcut.
  final FocusNode quickAddFocusNode;

  /// Active route view.
  final ShellView view;

  @override
  Widget build(BuildContext context) {
    return switch (view) {
      ShellView.tasks => TasksQuickAddDock(titleFocusNode: quickAddFocusNode),
      ShellView.settings => const SettingsActionDock(),
      ShellView.conflict => const ResolutionActionDock(isRecovery: false),
      ShellView.recovery => const ResolutionActionDock(isRecovery: true),
      ShellView.labels ||
      ShellView.locations ||
      ShellView.logs ||
      ShellView.rawTdf => const SizedBox.shrink(),
    };
  }
}

/// Desktop-only top chrome window close button.
class _ChromeCloseWindowButton extends ConsumerWidget {
  /// Creates a [_ChromeCloseWindowButton].
  const _ChromeCloseWindowButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    return UiButton(
      key: const ValueKey<String>('chrome_close_window_button'),
      variant: UiButtonVariant.icon,
      density: UiButtonDensity.standard,
      leadingIcon: Icons.close_rounded,
      isDangerHover: true,
      tooltip: localizations.tooltipCloseApp,
      onPressed: () =>
          unawaited(ref.read(desktopWindowActionsProvider).closeWindow()),
    );
  }
}

/// Top chrome foreground location status trigger opening [showLocationStatusModal].
class _ChromeLocationButton extends ConsumerWidget {
  /// Creates a [_ChromeLocationButton].
  const _ChromeLocationButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final status = ref.watch(
      locationStateProvider.select((state) => state.status),
    );

    return UiButton(
      key: const ValueKey<String>('chrome_location_button'),
      variant: UiButtonVariant.icon,
      density: UiButtonDensity.standard,
      tone: UiDomainMappers.locationButtonTone(status),
      leadingIcon: UiDomainMappers.locationIcon(status),
      isLoading: status == LocationStatus.searching,
      tooltip: localizations.tooltipLocationStatus,
      onPressed: () => unawaited(showLocationStatusModal(context)),
    );
  }
}

/// Top chrome sync status pill triggering conflict routing, Settings fallback, or manual Sync.
class _ChromeSyncButton extends ConsumerWidget {
  /// Creates a [_ChromeSyncButton].
  const _ChromeSyncButton({required this.isCompact});

  /// Whether viewport is in compact mode (omits inline sync text label).
  final bool isCompact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final storageMode = ref.watch(
      webDavConfigProvider.select(
        (configAsync) =>
            configAsync.asData?.value.storageMode ?? StorageMode.local,
      ),
    );
    final syncState = ref.watch(syncStateProvider);
    final statusKind = resolveSyncStatusKind(
      storageMode: storageMode,
      syncState: syncState,
    );
    final statusLabel = UiDomainMappers.syncStatusLabel(
      statusKind,
      localizations,
    );

    return UiButton(
      key: const ValueKey<String>('chrome_sync_button'),
      variant: UiButtonVariant.secondary,
      density: UiButtonDensity.chrome,
      tone: UiDomainMappers.syncButtonTone(statusKind),
      leadingIcon: UiDomainMappers.syncIcon(statusKind),
      label: isCompact ? null : statusLabel,
      isLoading: statusKind == SyncStatusKind.syncing,
      tooltip: statusLabel,
      onPressed: () => unawaited(
        _handleSyncChromeTap(
          ref,
          statusKind: statusKind,
          hasWebDav: storageMode.usesWebDav,
        ),
      ),
    );
  }

  /// Handles top chrome Sync button taps (Conflict routing, Settings fallback, or manual Sync).
  Future<void> _handleSyncChromeTap(
    WidgetRef ref, {
    required SyncStatusKind statusKind,
    required bool hasWebDav,
  }) async {
    final shellNotifier = ref.read(shellProvider.notifier);
    if (statusKind == SyncStatusKind.conflict) {
      final outcome = ref.read(syncStateProvider).syncOutcome;
      if (outcome != null &&
          outcome.kind == TdfSyncOutcomeKind.recoveryRequired) {
        shellNotifier.openView(ShellView.recovery);
        return;
      }
      shellNotifier.openView(ShellView.conflict);
      return;
    }
    if (!hasWebDav) {
      shellNotifier.openView(ShellView.settings);
      return;
    }
    await ref.read(syncActionsProvider.notifier).syncNow();
  }
}

/// Clickable brand button rendering `UiAppLogo` and the `TierTask` wordmark (`U-BRAND-001`).
class _ShellBrandButton extends ConsumerWidget {
  /// Creates a [_ShellBrandButton].
  const _ShellBrandButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = UiThemeTokens.of(context);
    final localizations = AppLocalizations.of(context);
    return InkWell(
      key: const ValueKey<String>('chrome_brand_button'),
      onTap: () => ref.read(shellProvider.notifier).openView(ShellView.tasks),
      borderRadius: BorderRadius.circular(tokens.radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 4.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const UiAppLogo(size: 22.0),
            const SizedBox(width: 9.0),
            Flexible(
              child: Text(
                localizations.appTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.typography.brand.copyWith(
                  color: tokens.colors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline warning-toned `DEV` build profile badge rendered beside the workspace selector (`U-BRAND-002`).
class _ShellDevBadge extends StatelessWidget {
  /// Creates a [_ShellDevBadge].
  const _ShellDevBadge();

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiPill(
      key: const ValueKey<String>('chrome_dev_pill'),
      label: localizations.devBuildBadge,
      variant: UiPillVariant.badge,
      tone: UiPillTone.warning,
      isMono: true,
    );
  }
}

/// Compact top-bar clickable `UiAppLogo` + active label filter clearing button (`U-LAYOUT-004`).
class _MobileActiveFilterButton extends ConsumerWidget {
  /// Creates a [_MobileActiveFilterButton].
  const _MobileActiveFilterButton({required this.labelName});

  /// Active label display name.
  final String labelName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = UiThemeTokens.of(context);
    final localizations = AppLocalizations.of(context);
    return Tooltip(
      message: localizations.activeFilterClearTooltip,
      child: InkWell(
        key: const ValueKey<String>('mobile_active_filter_button'),
        onTap: () => ref.read(shellProvider.notifier).selectLabelFilter(null),
        borderRadius: BorderRadius.circular(tokens.radii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const UiAppLogo(size: 20.0),
              const SizedBox(width: 8.0),
              Flexible(
                child: Text(
                  labelName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.compactBrand.copyWith(
                    color: tokens.colors.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Desktop workspace switcher chrome pill (`U-LAYOUT-003`).
class _WorkspaceChromeTrigger extends ConsumerWidget {
  /// Creates a [_WorkspaceChromeTrigger].
  const _WorkspaceChromeTrigger();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final workspaceName = ref.watch(
      activeWorkspaceProvider.select(
        (workspace) => workspace.asData?.value.name ?? AppWorkspace.defaultName,
      ),
    );
    return UiButton(
      key: const ValueKey<String>('chrome_workspace_button'),
      variant: UiButtonVariant.secondary,
      density: UiButtonDensity.chrome,
      leadingIcon: Icons.grid_view_outlined,
      label: workspaceName,
      trailingIcon: Icons.unfold_more_rounded,
      tooltip: localizations.tooltipManageWorkspaces,
      onPressed: () => unawaited(showWorkspacesModal(context)),
    );
  }
}

/// Compact slide-over drawer header card displaying and switching the active workspace (`U-LAYOUT-003`).
class _CompactDrawerWorkspaceCard extends ConsumerWidget {
  /// Creates a [_CompactDrawerWorkspaceCard].
  const _CompactDrawerWorkspaceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final workspaceName = ref.watch(
      activeWorkspaceProvider.select(
        (workspace) => workspace.asData?.value.name ?? AppWorkspace.defaultName,
      ),
    );
    return UiButton(
      key: const ValueKey<String>('drawer_workspace_button'),
      variant: UiButtonVariant.secondary,
      density: UiButtonDensity.chrome,
      isFullWidth: true,
      leadingIcon: Icons.grid_view_outlined,
      label: workspaceName,
      trailingIcon: Icons.unfold_more_rounded,
      tooltip: localizations.tooltipManageWorkspaces,
      onPressed: () {
        ref.read(shellProvider.notifier).setCompactDrawerOpen(false);
        unawaited(showWorkspacesModal(context));
      },
    );
  }
}

/// Top chrome Global Search toggle button or active search field (`U-LAYOUT-003`).
class _ShellSearchControl extends ConsumerWidget {
  /// Creates a [_ShellSearchControl].
  const _ShellSearchControl({
    required this.isCompact,
    required this.controllers,
    required this.onOpen,
  });

  /// Preserved shell controllers supplying search text and focus nodes.
  final _ShellControllers controllers;

  /// Whether viewport is in compact mode (`100%` top bar search width).
  final bool isCompact;

  /// Callback opening Global Search.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final isOpen = ref.watch(shellProvider.select((shell) => shell.searchOpen));
    if (!isOpen) {
      return UiButton(
        key: const ValueKey<String>('chrome_search_open_button'),
        variant: UiButtonVariant.icon,
        density: UiButtonDensity.standard,
        leadingIcon: Icons.search_rounded,
        tooltip: localizations.tooltipSearch,
        onPressed: onOpen,
      );
    }
    final field = _ShellSearchInputRow(
      controller: controllers.search,
      focusNode: controllers.searchFocus,
    );
    if (isCompact) {
      return field;
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320.0),
      child: field,
    );
  }
}

/// Expanded Global Search input field paired with its dismiss button.
class _ShellSearchInputRow extends ConsumerWidget {
  /// Creates a [_ShellSearchInputRow].
  const _ShellSearchInputRow({
    required this.controller,
    required this.focusNode,
  });

  /// Search input text editing controller.
  final TextEditingController controller;

  /// Search input focus node.
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);

    return Row(
      children: <Widget>[
        Expanded(
          child: UiField(
            key: const ValueKey<String>('chrome_search_field'),
            kind: UiFieldKind.search,
            controller: controller,
            focusNode: focusNode,
            height: 36.0,
            hintText: localizations.searchHint,
            clearTooltip: localizations.tooltipClearSearch,
            onChanged: ref.read(searchQueryProvider.notifier).setQuery,
          ),
        ),
        const SizedBox(width: 6.0),
        UiButton(
          key: const ValueKey<String>('chrome_search_close_button'),
          variant: UiButtonVariant.icon,
          density: UiButtonDensity.chrome,
          leadingIcon: Icons.close_rounded,
          tooltip: localizations.searchCloseTooltip,
          onPressed: ref.read(shellProvider.notifier).closeSearch,
        ),
      ],
    );
  }
}

/// Four-section sidebar navigation tree (`Tasks`, `Labels`, `Locations`, `Tools`) (`U-UX-001`).
class _ShellSidebarBody extends StatelessWidget {
  /// Creates a [_ShellSidebarBody].
  const _ShellSidebarBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SidebarTasksSection(),
        SizedBox(height: 12.0),
        _SidebarLabelsSection(),
        SizedBox(height: 12.0),
        _SidebarLocationsSection(),
        SizedBox(height: 12.0),
        _SidebarToolsSection(),
      ],
    );
  }
}

/// Six-tier Tasks navigation sidebar section watching only tier counts and active tier selection.
class _SidebarTasksSection extends ConsumerWidget {
  /// Creates a [_SidebarTasksSection].
  const _SidebarTasksSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final nav = ref.watch(
      shellProvider.select(
        (shell) => (
          view: shell.view,
          searchOpen: shell.searchOpen,
          activeTier: shell.activeTier,
          activeLabelId: shell.activeLabelId,
        ),
      ),
    );
    final board =
        ref.watch(evaluatedBoardProvider(nav.activeLabelId)).asData?.value ??
        TaskBoard.empty();
    final notifier = ref.read(shellProvider.notifier);

    return UiSidebarSection(
      title: localizations.sectionTasksTitle,
      items: <UiSidebarNavItem>[
        for (final tier in TaskTier.values)
          UiSidebarNavItem(
            id: 'tier_${tier.name}',
            label: localizations.tierName(tier),
            icon: UiDomainMappers.tierIcon(tier),
            countLabel: '${board.tasksForTier(tier).length}',
            isSelected:
                nav.view == ShellView.tasks &&
                !nav.searchOpen &&
                nav.activeTier == tier,
            onTap: () => notifier.selectTier(tier),
          ),
      ],
    );
  }
}

/// Collapsible, filterable Labels sidebar section (`U-UX-001`).
class _SidebarLabelsSection extends ConsumerWidget {
  /// Creates a [_SidebarLabelsSection].
  const _SidebarLabelsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final slice = ref.watch(
      shellProvider.select(
        (shell) => (
          view: shell.view,
          activeLabelId: shell.activeLabelId,
          isCollapsed: shell.sidebarLabelsCollapsed,
          isFilterOpen: shell.sidebarLabelsFilterOpen,
          expandedLabelId: shell.expandedEntity?.kind == EntityKind.label
              ? shell.expandedEntity?.id
              : null,
        ),
      ),
    );
    final filterQuery = slice.isFilterOpen
        ? ref.watch(sidebarLabelsFilterQueryProvider)
        : '';
    final rawBoard =
        ref.watch(taskNotifierProvider.select((a) => a.asData?.value)) ??
        TaskBoard.empty();
    final notifier = ref.read(shellProvider.notifier);
    final sortedLabels = TaskBoardEvaluator.sortLabelsAlphabetically(
      rawBoard.labels,
    );
    final activeColor = _resolveActiveLabelColor(
      sortedLabels,
      slice.activeLabelId,
    );

    return UiSidebarSection(
      title: localizations.drawerLabels,
      isCollapsible: true,
      isCollapsed: slice.isCollapsed,
      onToggleCollapse: notifier.toggleSidebarLabelsCollapsed,
      collapsedCountLabel: '${sortedLabels.length}',
      collapsedActiveColorDot: activeColor,
      isFilterable: true,
      isFilterOpen: slice.isFilterOpen,
      onToggleFilter: notifier.toggleSidebarLabelsFilter,
      filterQuery: filterQuery,
      onFilterChanged: ref
          .read(sidebarLabelsFilterQueryProvider.notifier)
          .setQuery,
      filterPlaceholder: localizations.sidebarFilterLabelsPlaceholder,
      filterClearTooltip: localizations.tooltipClearSearch,
      filterEmptyText: localizations.sidebarFilterLabelsEmpty,
      onManage: () => notifier.openView(ShellView.labels),
      isManageActive: slice.view == ShellView.labels,
      filterTooltip: localizations.sidebarFilterLabelsToggle,
      manageTooltip: localizations.sidebarManageLabels,
      collapseTooltip: localizations.sidebarCollapseLabels,
      expandTooltip: localizations.sidebarExpandLabels,
      items: _buildLabelItems(
        rawBoard: rawBoard,
        sortedLabels: sortedLabels,
        view: slice.view,
        activeLabelId: slice.activeLabelId,
        expandedLabelId: slice.expandedLabelId,
        filterQuery: filterQuery,
        localizations: localizations,
        notifier: notifier,
      ),
    );
  }
}

/// Collapsible, filterable Locations sidebar section (`U-UX-001`).
class _SidebarLocationsSection extends ConsumerWidget {
  /// Creates a [_SidebarLocationsSection].
  const _SidebarLocationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final slice = ref.watch(
      shellProvider.select(
        (shell) => (
          view: shell.view,
          isCollapsed: shell.sidebarLocationsCollapsed,
          isFilterOpen: shell.sidebarLocationsFilterOpen,
          expandedLocationId: shell.expandedEntity?.kind == EntityKind.location
              ? shell.expandedEntity?.id
              : null,
        ),
      ),
    );
    final filterQuery = slice.isFilterOpen
        ? ref.watch(sidebarLocationsFilterQueryProvider)
        : '';
    final rawBoard =
        ref.watch(taskNotifierProvider.select((a) => a.asData?.value)) ??
        TaskBoard.empty();
    final notifier = ref.read(shellProvider.notifier);
    final sortedLocations = TaskBoardEvaluator.sortLocationsAlphabetically(
      rawBoard.locations,
    );

    return UiSidebarSection(
      title: localizations.drawerLocations,
      isCollapsible: true,
      isCollapsed: slice.isCollapsed,
      onToggleCollapse: notifier.toggleSidebarLocationsCollapsed,
      collapsedCountLabel: '${sortedLocations.length}',
      isFilterable: true,
      isFilterOpen: slice.isFilterOpen,
      onToggleFilter: notifier.toggleSidebarLocationsFilter,
      filterQuery: filterQuery,
      onFilterChanged: ref
          .read(sidebarLocationsFilterQueryProvider.notifier)
          .setQuery,
      filterPlaceholder: localizations.sidebarFilterLocationsPlaceholder,
      filterClearTooltip: localizations.tooltipClearSearch,
      filterEmptyText: localizations.sidebarFilterLocationsEmpty,
      onManage: () => notifier.openView(ShellView.locations),
      isManageActive: slice.view == ShellView.locations,
      filterTooltip: localizations.sidebarFilterLocationsToggle,
      manageTooltip: localizations.sidebarManageLocations,
      collapseTooltip: localizations.sidebarCollapseLocations,
      expandTooltip: localizations.sidebarExpandLocations,
      items: _buildLocationItems(
        rawBoard: rawBoard,
        sortedLocations: sortedLocations,
        view: slice.view,
        expandedLocationId: slice.expandedLocationId,
        filterQuery: filterQuery,
        notifier: notifier,
      ),
    );
  }
}

/// Tools sidebar section with conditional WebDAV sync and Diagnostic Log entries (`U-UX-001`).
class _SidebarToolsSection extends ConsumerWidget {
  /// Creates a [_SidebarToolsSection].
  const _SidebarToolsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final view = ref.watch(shellProvider.select((shell) => shell.view));
    final showSyncWebDav = ref.watch(
      webDavConfigProvider.select(
        (config) => config.asData?.value.storageMode.usesWebDav ?? false,
      ),
    );
    final showDiagnosticLog = ref.watch(diagnosticsEnabledProvider);

    return UiSidebarSection(
      title: localizations.sectionToolsTitle,
      showTopDivider: true,
      items: _buildToolItems(
        view: view,
        showSyncWebDav: showSyncWebDav,
        showDiagnosticLog: showDiagnosticLog,
        localizations: localizations,
        ref: ref,
      ),
    );
  }
}

/// Pinned SemVer build string footer at the bottom of the sidebar/drawer (`U-BRAND-002`).
class _ShellSidebarFooter extends ConsumerWidget {
  /// Creates a [_ShellSidebarFooter].
  const _ShellSidebarFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = UiThemeTokens.of(context);
    final version = ref.watch(appVersionDisplayProvider);
    final baseStyle = UiTypographyTokens.mono(
      tokens.typography.eyebrow.copyWith(color: tokens.colors.muted),
    );

    return Row(
      children: <Widget>[
        Text(version.versionLabel, style: baseStyle),
        if (version.buildSuffix.isNotEmpty)
          Flexible(
            child: Opacity(
              opacity: 0.65,
              child: Text(
                version.buildSuffix,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: baseStyle,
              ),
            ),
          ),
      ],
    );
  }
}

/// Floating toast and LIFO Undo overlay positioned inside the scroll viewport above bottom docks (`U-UX-004`).
class _ShellFloatingNotice extends ConsumerWidget {
  /// Creates a [_ShellFloatingNotice].
  const _ShellFloatingNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(floatingNoticeProvider);
    if (notice == null) {
      return const SizedBox.shrink();
    }
    final localizations = AppLocalizations.of(context);
    final controller = ref.read(floatingNoticeProvider.notifier);

    return UiBanner(
      key: ValueKey<String>('floating_notice_${notice.id}'),
      variant: UiBannerVariant.toast,
      tone: UiDomainMappers.noticeTone(notice.tone),
      message: notice.message,
      actionLabel: notice.actionLabel,
      onAction: notice.hasUndoAction
          ? () => unawaited(controller.undoLatest())
          : null,
      kbdHint: notice.shortcutHint,
      onDismiss: controller.dismiss,
      dismissTooltip: localizations.actionDismiss,
    );
  }
}

/// Exhaustive view dispatcher hosting all eight top-level routes inside the main pane.
class _ShellMainBody extends StatelessWidget {
  /// Creates a [_ShellMainBody].
  const _ShellMainBody({required this.view, required this.controllers});

  /// Preserved scroll controllers for scrollable top-level routes.
  final _ShellControllers controllers;

  /// Active route view.
  final ShellView view;

  @override
  Widget build(BuildContext context) {
    return switch (view) {
      ShellView.tasks => TasksView(scrollController: controllers.tasksScroll),
      ShellView.labels => LabelsView(
        scrollController: controllers.labelsScroll,
      ),
      ShellView.locations => LocationsView(
        scrollController: controllers.locationsScroll,
      ),
      ShellView.settings => SettingsView(
        scrollController: controllers.settingsScroll,
      ),
      ShellView.logs => const LogViewerView(),
      ShellView.rawTdf => const RawTdfView(),
      ShellView.conflict => const DeletionConflictView(),
      ShellView.recovery => const GenerationRecoveryView(),
    };
  }
}

/// Builds label filter and manager-navigation items for the Labels sidebar section.
List<UiSidebarNavItem> _buildLabelItems({
  required TaskBoard rawBoard,
  required List<TdfLabel> sortedLabels,
  required ShellView view,
  required String? activeLabelId,
  required String? expandedLabelId,
  required String filterQuery,
  required AppLocalizations localizations,
  required ShellNotifier notifier,
}) {
  final needle = filterQuery.trim().toLowerCase();
  final items = <UiSidebarNavItem>[];
  if (needle.isEmpty) {
    var globalOpenCount = 0;
    for (final task in rawBoard.allTasks) {
      if (!task.isCompleted) {
        globalOpenCount++;
      }
    }
    items.add(
      UiSidebarNavItem(
        id: 'label_all_tasks',
        label: localizations.allTasksLabel,
        icon: Icons.layers_outlined,
        countLabel: '$globalOpenCount',
        isSelected: view == ShellView.tasks && activeLabelId == null,
        onTap: () => notifier.selectLabelFilter(null),
      ),
    );
  }
  for (final label in sortedLabels) {
    if (needle.isNotEmpty && !label.name.toLowerCase().contains(needle)) {
      continue;
    }
    final colorValue = TaskScheduleHelper.parseLabelColorValue(label.color);
    items.add(
      UiSidebarNavItem(
        id: 'label_${label.id}',
        label: label.name,
        colorDot: _colorFromArgb(colorValue),
        subtitle: label.isScoped ? localizations.scopedQueueLabel : null,
        countLabel: '${rawBoard.openTaskCountForLabel(label.id)}',
        isSelected: view == ShellView.tasks && label.id == activeLabelId,
        onTap: () => notifier.selectLabelFilter(label.id),
        trailingIcon: Icons.info_outline_rounded,
        trailingTooltip: localizations.openLabelInManagerTooltip,
        isTrailingActive:
            view == ShellView.labels && expandedLabelId == label.id,
        onTrailingTap: () => notifier.openEntityInManager(
          EntityRef(kind: EntityKind.label, id: label.id),
          preserveReturnContext: view == ShellView.tasks,
        ),
      ),
    );
  }
  return items;
}

/// Builds location manager-navigation items for the Locations sidebar section.
List<UiSidebarNavItem> _buildLocationItems({
  required TaskBoard rawBoard,
  required List<TdfLocation> sortedLocations,
  required ShellView view,
  required String? expandedLocationId,
  required String filterQuery,
  required ShellNotifier notifier,
}) {
  final needle = filterQuery.trim().toLowerCase();
  final items = <UiSidebarNavItem>[];
  for (final location in sortedLocations) {
    if (needle.isNotEmpty && !location.name.toLowerCase().contains(needle)) {
      continue;
    }
    items.add(
      UiSidebarNavItem(
        id: 'location_${location.id}',
        label: location.name,
        icon: Icons.location_on_outlined,
        countLabel: '${rawBoard.openTaskCountForLocation(location.id)}',
        trailingHintIcon: Icons.chevron_right_rounded,
        isSelected:
            view == ShellView.locations && expandedLocationId == location.id,
        onTap: () => notifier.openEntityInManager(
          EntityRef(kind: EntityKind.location, id: location.id),
          preserveReturnContext: view == ShellView.tasks,
        ),
      ),
    );
  }
  return items;
}

/// Builds conditional sync, log, raw TDF, and settings navigation items.
List<UiSidebarNavItem> _buildToolItems({
  required ShellView view,
  required bool showSyncWebDav,
  required bool showDiagnosticLog,
  required AppLocalizations localizations,
  required WidgetRef ref,
}) {
  final notifier = ref.read(shellProvider.notifier);
  return <UiSidebarNavItem>[
    if (showSyncWebDav)
      UiSidebarNavItem(
        id: 'tool_sync_webdav',
        label: localizations.tooltipSyncWebDav,
        icon: Icons.sync_rounded,
        onTap: () {
          notifier.setCompactDrawerOpen(false);
          unawaited(ref.read(syncActionsProvider.notifier).syncNow());
        },
      ),
    if (showDiagnosticLog)
      UiSidebarNavItem(
        id: 'tool_diagnostic_log',
        label: localizations.diagnosticLogTitle,
        icon: Icons.terminal_rounded,
        isSelected: view == ShellView.logs,
        onTap: () => notifier.openView(ShellView.logs),
      ),
    UiSidebarNavItem(
      id: 'tool_raw_tdf',
      label: localizations.rawTdfPreviewTitle,
      icon: Icons.code_rounded,
      isSelected: view == ShellView.rawTdf,
      onTap: () => notifier.openView(ShellView.rawTdf),
    ),
    UiSidebarNavItem(
      id: 'tool_settings',
      label: localizations.settingsTitle,
      icon: Icons.settings_outlined,
      isSelected: view == ShellView.settings,
      onTap: () => notifier.openView(ShellView.settings),
    ),
  ];
}

/// Converts an optional ARGB integer into a Flutter [Color], or returns `null`.
Color? _colorFromArgb(int? argb) => argb != null ? Color(argb) : null;

/// Returns whether the active route displays a pinned bottom dock (`U-LAYOUT-005`).
bool _hasBottomDock({
  required ShellView view,
  required bool searchOpen,
  required bool hasTaskDraft,
  required bool isTasksBlocked,
}) {
  return switch (view) {
    ShellView.tasks => !searchOpen && !hasTaskDraft && !isTasksBlocked,
    ShellView.settings || ShellView.conflict || ShellView.recovery => true,
    ShellView.labels ||
    ShellView.locations ||
    ShellView.logs ||
    ShellView.rawTdf => false,
  };
}

/// Returns whether [TasksView] is currently blocked by initial load or a full-screen read error.
bool _isTasksViewBlocked(
  AsyncValue<AppWorkspace> workspaceAsync,
  AsyncValue<TaskBoard> boardAsync,
) {
  if (workspaceAsync.hasError) {
    return true;
  }
  return (boardAsync.isLoading || boardAsync.hasError) && !boardAsync.hasValue;
}

/// Resolves the color dot for [activeId] when the Labels section is collapsed.
Color? _resolveActiveLabelColor(List<TdfLabel> sortedLabels, String? activeId) {
  if (activeId == null) {
    return null;
  }
  for (final label in sortedLabels) {
    if (label.id == activeId) {
      return _colorFromArgb(
        TaskScheduleHelper.parseLabelColorValue(label.color),
      );
    }
  }
  return null;
}

/// Initiates native desktop window drag from empty top chrome space.
void _startWindowDrag(WidgetRef ref) {
  unawaited(ref.read(desktopWindowActionsProvider).startDragging());
}

/// Toggles the compact slide-over navigation drawer state.
void _toggleCompactDrawer(WidgetRef ref, bool isCurrentlyOpen) {
  ref.read(shellProvider.notifier).setCompactDrawerOpen(!isCurrentlyOpen);
}

/// Toggles native desktop window maximize/restore from top chrome double-tap.
void _toggleWindowMaximize(WidgetRef ref) {
  unawaited(ref.read(desktopWindowActionsProvider).toggleMaximize());
}

/// Watches the active label filter name for compact Tasks view, or returns `null` when hidden (`U-LAYOUT-004`).
String? _watchMobileFilterLabelName(
  WidgetRef ref, {
  required ShellView view,
  required bool searchOpen,
  required String? activeLabelId,
}) {
  if (view != ShellView.tasks || searchOpen || activeLabelId == null) {
    return null;
  }
  return ref.watch(
    taskNotifierProvider.select(
      (boardAsync) => boardAsync.asData?.value.findLabel(activeLabelId)?.name,
    ),
  );
}
