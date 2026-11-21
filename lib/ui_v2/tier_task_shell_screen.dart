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
import 'package:tiertask_ui/tiertask_ui.dart';

import '../l10n/app_localizations.dart';
import '../presentation/app_shell_controller.dart';
import '../presentation/board_boundary_timer.dart';
import '../presentation/board_v2_view_models.dart';
import '../presentation/floating_notice_controller.dart';
import '../presentation/sync_v2_controller.dart';
import '../presentation/ui_v2_shell_models.dart';
import 'dialogs/app_modals.dart';
import 'ui_v2_icon_mapper.dart';
import 'views/labels_view.dart';
import 'views/locations_view.dart';
import 'views/log_viewer_view.dart';
import 'views/raw_tdf_view.dart';
import 'views/resolution_views.dart';
import 'views/settings_view.dart';
import 'views/tasks_view.dart';

/// Root adaptive desktop and mobile feature shell (`spec/UI_DESIGN_SYSTEM.md`).
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
          .read(floatingNoticeControllerProvider.notifier)
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

    final localizations = AppLocalizations.of(context);
    final shell = ref.watch(appShellControllerProvider);
    final chrome = ref.watch(boardChromeViewModelProvider);
    final hasFloatingNotice = ref.watch(
      floatingNoticeControllerProvider.select((notice) => notice != null),
    );
    final isTasksBlocked = ref.watch(
      tasksViewModelProvider.select(
        (vm) => vm.isLoading || vm.fullScreenFileReadError != null,
      ),
    );
    final isCompact = UiBreakpoints.isCompact(MediaQuery.sizeOf(context).width);

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        _handleSystemBack();
      },
      child: Focus(
        focusNode: _rootFocusNode,
        autofocus: true,
        skipTraversal: true,
        onKeyEvent: _handleRootKeyEvent,
        child: UiAdaptiveAppShell(
          brand: _ShellBrandButton(
            isDevBuild: chrome.isDevBuild,
            onPressed: () => ref
                .read(appShellControllerProvider.notifier)
                .openView(ShellView.tasks),
          ),
          mobileActiveFilter: _resolveMobileActiveFilter(shell, chrome),
          workspaceTrigger: _WorkspaceChromeTrigger(
            workspaceName: chrome.activeWorkspaceName,
            onPressed: () => unawaited(showWorkspacesModal(context)),
          ),
          searchWidget: _ShellSearchControl(
            isOpen: shell.searchOpen,
            isCompact: isCompact,
            controller: _searchController,
            focusNode: _searchFocusNode,
            onOpen: _openSearchAndFocus,
            onChanged: (value) => ref
                .read(appShellControllerProvider.notifier)
                .updateSearchQuery(value),
            onClose: () =>
                ref.read(appShellControllerProvider.notifier).closeSearch(),
          ),
          isSearchOpen: shell.searchOpen,
          trailingActions: _buildTrailingActions(chrome, isCompact),
          isDrawerOpen: shell.compactDrawerOpen,
          onToggleDrawer: () => ref
              .read(appShellControllerProvider.notifier)
              .setCompactDrawerOpen(!shell.compactDrawerOpen),
          menuOpenTooltip: localizations.tooltipMenu,
          menuCloseTooltip: localizations.actionClose,
          sidebarHeader: _CompactDrawerWorkspaceCard(
            workspaceName: chrome.activeWorkspaceName,
            onPressed: _openWorkspacesFromDrawer,
          ),
          sidebarBody: const _ShellSidebarBody(),
          sidebarFooter: const _ShellSidebarFooter(),
          sidebarScrollController: _sidebarScrollController,
          floatingNotice: hasFloatingNotice
              ? const _ShellFloatingNotice()
              : null,
          bottomDock: _resolveBottomDock(shell, isTasksBlocked: isTasksBlocked),
          body: _ShellMainBody(
            view: shell.view,
            tasksScrollController: _tasksScrollController,
            labelsScrollController: _labelsScrollController,
            locationsScrollController: _locationsScrollController,
            settingsScrollController: _settingsScrollController,
          ),
        ),
      ),
    );
  }

  /// Builds trailing chrome controls (conditional Location Status + Sync status).
  List<Widget> _buildTrailingActions(
    BoardChromeViewModel chrome,
    bool isCompact,
  ) {
    return <Widget>[
      if (chrome.locationEnabled)
        UiButton(
          key: const ValueKey<String>('chrome_location_button'),
          variant: UiButtonVariant.icon,
          density: UiButtonDensity.chrome,
          leadingIcon: UiV2IconMapper.locationIcon(chrome.locationStatusKind),
          isLoading:
              chrome.locationStatusKind == ShellLocationStatusKind.searching,
          tooltip: chrome.locationTooltip,
          onPressed: () => unawaited(showLocationStatusModal(context)),
        ),
      UiButton(
        key: const ValueKey<String>('chrome_sync_button'),
        variant: isCompact ? UiButtonVariant.icon : UiButtonVariant.secondary,
        density: UiButtonDensity.chrome,
        tone: UiV2IconMapper.syncButtonTone(chrome.syncStatusKind),
        leadingIcon: UiV2IconMapper.syncIcon(chrome.syncStatusKind),
        label: isCompact ? null : chrome.syncStatusLabel,
        isLoading: chrome.syncStatusKind == ShellSyncStatusKind.syncing,
        tooltip: chrome.syncStatusLabel,
        onPressed: () => unawaited(_handleSyncChromeTap(chrome)),
      ),
    ];
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
    final shell = ref.read(appShellControllerProvider);
    final tasksVm = ref.read(tasksViewModelProvider);
    final blockedByLoadOrError =
        tasksVm.isLoading || tasksVm.fullScreenFileReadError != null;

    if (primaryPressed && key == LogicalKeyboardKey.keyF) {
      if (blockedByLoadOrError) {
        return KeyEventResult.handled;
      }
      _openSearchAndFocus();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape) {
      final outcome = ref
          .read(appShellControllerProvider.notifier)
          .handleEscape();
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
        shell.view == ShellView.tasks) {
      final chrome = ref.read(boardChromeViewModelProvider);
      if (chrome.canUndo) {
        unawaited(
          ref
              .read(floatingNoticeControllerProvider.notifier)
              .undoLatest(fromShortcut: true),
        );
        return KeyEventResult.handled;
      }
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
        ref.read(appShellControllerProvider.notifier).stepTier(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        ref.read(appShellControllerProvider.notifier).stepTier(1);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Handles top chrome Sync button taps (Conflict routing, Settings fallback, or manual Sync).
  Future<void> _handleSyncChromeTap(BoardChromeViewModel chrome) async {
    final shellNotifier = ref.read(appShellControllerProvider.notifier);
    if (chrome.syncStatusKind == ShellSyncStatusKind.conflict) {
      final recoveryVm = ref.read(recoveryResolutionViewModelProvider);
      if (recoveryVm.hasItems) {
        shellNotifier.openView(ShellView.recovery);
        return;
      }
      shellNotifier.openView(ShellView.conflict);
      return;
    }
    if (!chrome.hasWebDav) {
      shellNotifier.openView(ShellView.settings);
      return;
    }
    await ref.read(syncV2ControllerProvider.notifier).syncNow();
  }

  /// Delegates Android system Back presses to `AppShellController.handleSystemBack()`.
  void _handleSystemBack() {
    final outcome = ref
        .read(appShellControllerProvider.notifier)
        .handleSystemBack();
    if (outcome == ShellDismissOutcome.allowSystemPop) {
      unawaited(SystemNavigator.pop());
    }
  }

  /// Expands compact composer if needed and focuses the Task Quick-Add title input.
  void _focusQuickAddComposer() {
    final isCompact = UiBreakpoints.isCompact(MediaQuery.sizeOf(context).width);
    if (isCompact) {
      ref
          .read(appShellControllerProvider.notifier)
          .setCompactComposerOpen(true);
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
    final wasOpen = ref.read(appShellControllerProvider).searchOpen;
    ref.read(appShellControllerProvider.notifier).openSearch();
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

  /// Closes the compact navigation drawer and presents the Workspaces modal.
  void _openWorkspacesFromDrawer() {
    ref.read(appShellControllerProvider.notifier).setCompactDrawerOpen(false);
    unawaited(showWorkspacesModal(context));
  }

  /// Registers listeners preserving scroll offsets and syncing the search text controller (`U-LAYOUT-007`).
  void _registerScopeListeners() {
    ref.listen<String>(
      boardChromeViewModelProvider.select((chrome) => chrome.activeWorkspaceId),
      (previous, next) {
        if (previous != null && previous != next) {
          _resetScrollController(_sidebarScrollController);
          _resetScrollController(_tasksScrollController);
        }
      },
    );
    ref.listen<AppShellState>(appShellControllerProvider, (previous, next) {
      if (_searchController.text != next.searchQuery) {
        _searchController.text = next.searchQuery;
      }
      if (previous == null) {
        return;
      }
      final scopeChanged =
          previous.view != next.view ||
          previous.activeTier != next.activeTier ||
          previous.activeLabelId != next.activeLabelId ||
          previous.searchOpen != next.searchOpen;
      if (scopeChanged) {
        _resetScrollController(_tasksScrollController);
      }
    });
  }

  /// Resets [controller] to offset `0` when currently attached to a scroll position.
  void _resetScrollController(ScrollController controller) {
    if (controller.hasClients) {
      controller.jumpTo(0.0);
    }
  }

  /// Returns the conditional bottom dock widget, or `null` when no dock applies (`U-LAYOUT-005`).
  Widget? _resolveBottomDock(
    AppShellState shell, {
    required bool isTasksBlocked,
  }) {
    return switch (shell.view) {
      ShellView.tasks =>
        (shell.searchOpen ||
                shell.activeDraft == EntityDraftKind.task ||
                isTasksBlocked)
            ? null
            : TasksQuickAddDock(titleFocusNode: _quickAddFocusNode),
      ShellView.settings => const SettingsActionDock(),
      ShellView.conflict => const ResolutionActionDock(isRecovery: false),
      ShellView.recovery => const ResolutionActionDock(isRecovery: true),
      ShellView.labels ||
      ShellView.locations ||
      ShellView.logs ||
      ShellView.rawTdf => null,
    };
  }

  /// Returns the compact active-label top chrome button on compact Tasks view (`U-LAYOUT-004`).
  Widget? _resolveMobileActiveFilter(
    AppShellState shell,
    BoardChromeViewModel chrome,
  ) {
    final activeLabelName = chrome.activeFilterLabelName;
    if (shell.view != ShellView.tasks ||
        shell.searchOpen ||
        activeLabelName == null) {
      return null;
    }
    return _MobileActiveFilterButton(
      labelName: activeLabelName,
      onClear: () =>
          ref.read(appShellControllerProvider.notifier).selectLabelFilter(null),
    );
  }
}

/// Clickable brand button rendering `UiAppLogo`, `TierTask`, and optional inline `DEV` pill (`U-BRAND-001`..`002`).
class _ShellBrandButton extends StatelessWidget {
  /// Creates a [_ShellBrandButton].
  const _ShellBrandButton({required this.isDevBuild, required this.onPressed});

  /// Whether the inline `DEV` pill is shown beside the wordmark.
  final bool isDevBuild;

  /// Callback returning to the primary Tasks view.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final localizations = AppLocalizations.of(context);
    return InkWell(
      key: const ValueKey<String>('chrome_brand_button'),
      onTap: onPressed,
      borderRadius: BorderRadius.circular(tokens.radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const UiAppLogo(size: 22.0),
            const SizedBox(width: 9.0),
            Text(
              localizations.appTitle,
              style: tokens.typography.brand.copyWith(color: tokens.colors.ink),
            ),
            if (isDevBuild) ...<Widget>[
              const SizedBox(width: 7.0),
              UiPill(
                key: const ValueKey<String>('chrome_dev_pill'),
                label: localizations.devBuildBadge,
                variant: UiPillVariant.badge,
                tone: UiPillTone.warning,
                isMono: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact top-bar clickable `UiAppLogo` + active label filter clearing button (`U-LAYOUT-004`).
class _MobileActiveFilterButton extends StatelessWidget {
  /// Creates a [_MobileActiveFilterButton].
  const _MobileActiveFilterButton({
    required this.labelName,
    required this.onClear,
  });

  /// Active label display name.
  final String labelName;

  /// Callback clearing the active label filter.
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final localizations = AppLocalizations.of(context);
    return Tooltip(
      message: localizations.activeFilterClearTooltip,
      child: InkWell(
        key: const ValueKey<String>('mobile_active_filter_button'),
        onTap: onClear,
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
class _WorkspaceChromeTrigger extends StatelessWidget {
  /// Creates a [_WorkspaceChromeTrigger].
  const _WorkspaceChromeTrigger({
    required this.workspaceName,
    required this.onPressed,
  });

  /// Callback opening the Workspaces modal.
  final VoidCallback onPressed;

  /// Active workspace display name.
  final String workspaceName;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiButton(
      key: const ValueKey<String>('chrome_workspace_button'),
      variant: UiButtonVariant.secondary,
      density: UiButtonDensity.chrome,
      leadingIcon: Icons.folder_outlined,
      label: workspaceName,
      trailingIcon: Icons.keyboard_arrow_down_rounded,
      tooltip: localizations.tooltipManageWorkspaces,
      onPressed: onPressed,
    );
  }
}

/// Compact slide-over drawer header card displaying and switching the active workspace (`U-LAYOUT-003`).
class _CompactDrawerWorkspaceCard extends StatelessWidget {
  /// Creates a [_CompactDrawerWorkspaceCard].
  const _CompactDrawerWorkspaceCard({
    required this.workspaceName,
    required this.onPressed,
  });

  /// Callback closing the drawer and opening the Workspaces modal.
  final VoidCallback onPressed;

  /// Active workspace display name.
  final String workspaceName;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiButton(
      key: const ValueKey<String>('drawer_workspace_button'),
      variant: UiButtonVariant.secondary,
      density: UiButtonDensity.chrome,
      isFullWidth: true,
      leadingIcon: Icons.folder_outlined,
      label: workspaceName,
      trailingIcon: Icons.keyboard_arrow_down_rounded,
      tooltip: localizations.tooltipManageWorkspaces,
      onPressed: onPressed,
    );
  }
}

/// Top chrome Global Search toggle button or active search field (`U-LAYOUT-003`).
class _ShellSearchControl extends StatelessWidget {
  /// Creates a [_ShellSearchControl].
  const _ShellSearchControl({
    required this.isOpen,
    required this.isCompact,
    required this.controller,
    required this.focusNode,
    required this.onOpen,
    required this.onChanged,
    required this.onClose,
  });

  /// Search input text editing controller.
  final TextEditingController controller;

  /// Search input focus node.
  final FocusNode focusNode;

  /// Whether viewport is in compact mode (`100%` top bar search width).
  final bool isCompact;

  /// Whether Global Search mode is active.
  final bool isOpen;

  /// Callback updating the live search query.
  final ValueChanged<String> onChanged;

  /// Callback closing Global Search and clearing query.
  final VoidCallback onClose;

  /// Callback opening Global Search.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    if (!isOpen) {
      return UiButton(
        key: const ValueKey<String>('chrome_search_open_button'),
        variant: UiButtonVariant.icon,
        density: UiButtonDensity.chrome,
        leadingIcon: Icons.search_rounded,
        tooltip: localizations.tooltipSearch,
        onPressed: onOpen,
      );
    }
    final field = Row(
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
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 6.0),
        UiButton(
          key: const ValueKey<String>('chrome_search_close_button'),
          variant: UiButtonVariant.icon,
          density: UiButtonDensity.chrome,
          leadingIcon: Icons.close_rounded,
          tooltip: localizations.searchCloseTooltip,
          onPressed: onClose,
        ),
      ],
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

/// Four-section sidebar navigation tree (`Tasks`, `Labels`, `Locations`, `Tools`) (`U-UX-001`).
class _ShellSidebarBody extends ConsumerWidget {
  /// Creates a [_ShellSidebarBody].
  const _ShellSidebarBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final sidebar = ref.watch(sidebarViewModelProvider);
    final shell = ref.watch(appShellControllerProvider);
    final notifier = ref.read(appShellControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UiSidebarSection(
          title: localizations.sectionTasksTitle,
          items: <UiSidebarNavItem>[
            for (final item in sidebar.tierItems)
              UiSidebarNavItem(
                id: 'tier_${item.tier.name}',
                label: item.label,
                icon: UiV2IconMapper.tierIcon(item.tier),
                countLabel: '${item.count}',
                isSelected:
                    shell.view == ShellView.tasks &&
                    !shell.searchOpen &&
                    shell.activeTier == item.tier,
                onTap: () => notifier.selectTier(item.tier),
              ),
          ],
        ),
        const SizedBox(height: 12.0),
        _SidebarLabelsSection(sidebar: sidebar, shell: shell),
        const SizedBox(height: 12.0),
        _SidebarLocationsSection(sidebar: sidebar, shell: shell),
        const SizedBox(height: 12.0),
        _SidebarToolsSection(sidebar: sidebar, shell: shell),
      ],
    );
  }
}

/// Collapsible, filterable Labels sidebar section (`U-UX-001`).
class _SidebarLabelsSection extends ConsumerWidget {
  /// Creates a [_SidebarLabelsSection].
  const _SidebarLabelsSection({required this.sidebar, required this.shell});

  /// Current shell navigation state.
  final AppShellState shell;

  /// Current sidebar view model.
  final SidebarViewModel sidebar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final notifier = ref.read(appShellControllerProvider.notifier);
    final hasFilterQuery =
        shell.sidebarLabelsFilterOpen &&
        shell.sidebarLabelsFilterQuery.trim().isNotEmpty;
    final activeDotColor = _colorFromArgb(sidebar.activeLabelColorValue);

    return UiSidebarSection(
      title: localizations.drawerLabels,
      isCollapsible: true,
      isCollapsed: shell.sidebarLabelsCollapsed,
      onToggleCollapse: notifier.toggleSidebarLabelsCollapsed,
      collapsedCountLabel: '${sidebar.totalLabelCount}',
      collapsedActiveColorDot: activeDotColor,
      isFilterable: true,
      isFilterOpen: shell.sidebarLabelsFilterOpen,
      onToggleFilter: notifier.toggleSidebarLabelsFilter,
      filterQuery: shell.sidebarLabelsFilterQuery,
      onFilterChanged: notifier.setSidebarLabelsFilterQuery,
      filterPlaceholder: localizations.sidebarFilterLabelsPlaceholder,
      filterClearTooltip: localizations.tooltipClearSearch,
      filterEmptyText: localizations.sidebarFilterLabelsEmpty,
      onManage: () => notifier.openView(ShellView.labels),
      isManageActive: shell.view == ShellView.labels,
      filterTooltip: localizations.sidebarFilterLabelsToggle,
      manageTooltip: localizations.sidebarManageLabels,
      collapseTooltip: localizations.sidebarCollapseLabels,
      expandTooltip: localizations.sidebarExpandLabels,
      items: <UiSidebarNavItem>[
        if (!hasFilterQuery)
          UiSidebarNavItem(
            id: 'label_all_tasks',
            label: localizations.allTasksLabel,
            icon: Icons.layers_outlined,
            countLabel: '${sidebar.allTasksCount}',
            isSelected:
                shell.view == ShellView.tasks && shell.activeLabelId == null,
            onTap: () => notifier.selectLabelFilter(null),
          ),
        for (final label in sidebar.labels)
          UiSidebarNavItem(
            id: 'label_${label.id}',
            label: label.name,
            colorDot: _colorFromArgb(label.colorValue),
            subtitle: label.isScoped ? localizations.scopedQueueLabel : null,
            countLabel: '${label.openCount}',
            isSelected: shell.view == ShellView.tasks && label.isSelected,
            onTap: () => notifier.selectLabelFilter(label.id),
            trailingIcon: Icons.info_outline_rounded,
            trailingTooltip: localizations.openLabelInManagerTooltip,
            isTrailingActive:
                shell.view == ShellView.labels &&
                shell.expandedEntity ==
                    EntityRef(kind: EntityKind.label, id: label.id),
            onTrailingTap: () => notifier.openEntityInManager(
              EntityRef(kind: EntityKind.label, id: label.id),
              preserveReturnContext: shell.view == ShellView.tasks,
            ),
          ),
      ],
    );
  }
}

/// Collapsible, filterable Locations sidebar section (`U-UX-001`).
class _SidebarLocationsSection extends ConsumerWidget {
  /// Creates a [_SidebarLocationsSection].
  const _SidebarLocationsSection({required this.sidebar, required this.shell});

  /// Current shell navigation state.
  final AppShellState shell;

  /// Current sidebar view model.
  final SidebarViewModel sidebar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final notifier = ref.read(appShellControllerProvider.notifier);

    return UiSidebarSection(
      title: localizations.drawerLocations,
      isCollapsible: true,
      isCollapsed: shell.sidebarLocationsCollapsed,
      onToggleCollapse: notifier.toggleSidebarLocationsCollapsed,
      collapsedCountLabel: '${sidebar.totalLocationCount}',
      isFilterable: true,
      isFilterOpen: shell.sidebarLocationsFilterOpen,
      onToggleFilter: notifier.toggleSidebarLocationsFilter,
      filterQuery: shell.sidebarLocationsFilterQuery,
      onFilterChanged: notifier.setSidebarLocationsFilterQuery,
      filterPlaceholder: localizations.sidebarFilterLocationsPlaceholder,
      filterClearTooltip: localizations.tooltipClearSearch,
      filterEmptyText: localizations.sidebarFilterLocationsEmpty,
      onManage: () => notifier.openView(ShellView.locations),
      isManageActive: shell.view == ShellView.locations,
      filterTooltip: localizations.sidebarFilterLocationsToggle,
      manageTooltip: localizations.sidebarManageLocations,
      collapseTooltip: localizations.sidebarCollapseLocations,
      expandTooltip: localizations.sidebarExpandLocations,
      items: <UiSidebarNavItem>[
        for (final location in sidebar.locations)
          UiSidebarNavItem(
            id: 'location_${location.id}',
            label: location.name,
            icon: Icons.location_on_outlined,
            countLabel: '${location.openCount}',
            trailingHintIcon: Icons.chevron_right_rounded,
            isSelected:
                shell.view == ShellView.locations &&
                shell.expandedEntity ==
                    EntityRef(kind: EntityKind.location, id: location.id),
            onTap: () => notifier.openEntityInManager(
              EntityRef(kind: EntityKind.location, id: location.id),
              preserveReturnContext: shell.view == ShellView.tasks,
            ),
          ),
      ],
    );
  }
}

/// Tools sidebar section with conditional WebDAV sync and Diagnostic Log entries (`U-UX-001`).
class _SidebarToolsSection extends ConsumerWidget {
  /// Creates a [_SidebarToolsSection].
  const _SidebarToolsSection({required this.sidebar, required this.shell});

  /// Current shell navigation state.
  final AppShellState shell;

  /// Current sidebar view model.
  final SidebarViewModel sidebar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final notifier = ref.read(appShellControllerProvider.notifier);

    return UiSidebarSection(
      title: localizations.sectionToolsTitle,
      showTopDivider: true,
      items: <UiSidebarNavItem>[
        if (sidebar.showSyncWebDav)
          UiSidebarNavItem(
            id: 'tool_sync_webdav',
            label: localizations.tooltipSyncWebDav,
            icon: Icons.sync_rounded,
            onTap: () {
              notifier.setCompactDrawerOpen(false);
              unawaited(ref.read(syncV2ControllerProvider.notifier).syncNow());
            },
          ),
        if (sidebar.showDiagnosticLog)
          UiSidebarNavItem(
            id: 'tool_diagnostic_log',
            label: localizations.diagnosticLogTitle,
            icon: Icons.terminal_rounded,
            isSelected: shell.view == ShellView.logs,
            onTap: () => notifier.openView(ShellView.logs),
          ),
        UiSidebarNavItem(
          id: 'tool_raw_tdf',
          label: localizations.rawTdfPreviewTitle,
          icon: Icons.code_rounded,
          isSelected: shell.view == ShellView.rawTdf,
          onTap: () => notifier.openView(ShellView.rawTdf),
        ),
        UiSidebarNavItem(
          id: 'tool_settings',
          label: localizations.settingsTitle,
          icon: Icons.settings_outlined,
          isSelected: shell.view == ShellView.settings,
          onTap: () => notifier.openView(ShellView.settings),
        ),
      ],
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
    final versionLabel = ref.watch(
      sidebarViewModelProvider.select((sidebar) => sidebar.versionLabel),
    );
    final buildSuffix = ref.watch(
      sidebarViewModelProvider.select((sidebar) => sidebar.buildSuffix),
    );
    final baseStyle = UiTypographyTokens.mono(
      tokens.typography.eyebrow.copyWith(color: tokens.colors.muted),
    );

    return Row(
      children: <Widget>[
        Text(versionLabel, style: baseStyle),
        if (buildSuffix.isNotEmpty)
          Flexible(
            child: Opacity(
              opacity: 0.65,
              child: Text(
                buildSuffix,
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
    final notice = ref.watch(floatingNoticeControllerProvider);
    if (notice == null) {
      return const SizedBox.shrink();
    }
    final localizations = AppLocalizations.of(context);
    final controller = ref.read(floatingNoticeControllerProvider.notifier);

    return UiBanner(
      key: ValueKey<String>('floating_notice_${notice.id}'),
      variant: UiBannerVariant.toast,
      tone: UiV2IconMapper.noticeTone(notice.tone),
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
  const _ShellMainBody({
    required this.view,
    required this.tasksScrollController,
    required this.labelsScrollController,
    required this.locationsScrollController,
    required this.settingsScrollController,
  });

  /// Preserved scroll controller for [LabelsView].
  final ScrollController labelsScrollController;

  /// Preserved scroll controller for [LocationsView].
  final ScrollController locationsScrollController;

  /// Preserved scroll controller for [SettingsView].
  final ScrollController settingsScrollController;

  /// Preserved scroll controller for [TasksView].
  final ScrollController tasksScrollController;

  /// Active route view.
  final ShellView view;

  @override
  Widget build(BuildContext context) {
    return switch (view) {
      ShellView.tasks => TasksView(scrollController: tasksScrollController),
      ShellView.labels => LabelsView(scrollController: labelsScrollController),
      ShellView.locations => LocationsView(
        scrollController: locationsScrollController,
      ),
      ShellView.settings => SettingsView(
        scrollController: settingsScrollController,
      ),
      ShellView.logs => const LogViewerView(),
      ShellView.rawTdf => const RawTdfView(),
      ShellView.conflict => const DeletionConflictView(),
      ShellView.recovery => const GenerationRecoveryView(),
    };
  }
}

/// Converts an optional ARGB integer into a Flutter [Color], or returns `null`.
Color? _colorFromArgb(int? argb) => argb != null ? Color(argb) : null;
