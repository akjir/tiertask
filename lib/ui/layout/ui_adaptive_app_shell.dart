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

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../primitives/ui_button.dart';
import '../tokens/ui_breakpoints.dart';
import '../tokens/ui_theme_tokens.dart';

/// Adaptive single-frame application shell coordinating chrome, sidebar/drawer, body + floating notice, and pinned bottom dock (`U-LAYOUT-001`..`005`).
class UiAdaptiveAppShell extends StatelessWidget {
  /// Creates a [UiAdaptiveAppShell].
  const UiAdaptiveAppShell({
    super.key,
    required this.brand,
    required this.sidebarBody,
    required this.body,
    this.mobileActiveFilter,
    this.workspaceTrigger,
    this.buildBadge,
    this.searchWidget,
    this.isSearchOpen = false,
    this.trailingActions = const <Widget>[],
    this.isDrawerOpen = false,
    this.onChromeDragStart,
    this.onChromeDoubleTap,
    this.onToggleDrawer,
    this.menuOpenTooltip,
    this.menuCloseTooltip,
    this.sidebarHeader,
    this.sidebarFooter,
    this.sidebarScrollController,
    this.floatingNotice,
    this.bottomDock,
  });

  /// Primary main pane body (compatible with `CustomScrollView`, `ListView.builder`, or flex `Column`).
  final Widget body;

  /// Optional pinned bottom dock anchored strictly below the viewport and [floatingNotice].
  final Widget? bottomDock;

  /// Brand mark and wordmark rendered at the leading edge of the top chrome bar.
  final Widget brand;

  /// Optional inline build profile badge (e.g. `DEV` pill) rendered after [workspaceTrigger] on desktop and beside [brand] on compact.
  final Widget? buildBadge;

  /// Optional floating notice / Undo toast anchored inside the viewport stack above [bottomDock].
  final Widget? floatingNotice;

  /// Whether the compact slide-over navigation drawer is currently open.
  final bool isDrawerOpen;

  /// Whether global search mode is active (expands search to 100% width on `compact`).
  final bool isSearchOpen;

  /// Accessible tooltip for the compact menu toggle while the drawer is open.
  final String? menuCloseTooltip;

  /// Accessible tooltip for the compact menu toggle while the drawer is closed.
  final String? menuOpenTooltip;

  /// Optional compact-only clickable active-label chip replacing [brand] when `!isSearchOpen`.
  final Widget? mobileActiveFilter;

  /// Optional callback invoked when the user double-taps empty top chrome space (e.g. desktop maximize/restore).
  final VoidCallback? onChromeDoubleTap;

  /// Optional callback invoked when the user begins dragging empty top chrome space (e.g. desktop window move).
  final VoidCallback? onChromeDragStart;

  /// Callback toggling the compact slide-over drawer.
  final VoidCallback? onToggleDrawer;

  /// Optional global search trigger or active search box rendered in top chrome.
  final Widget? searchWidget;

  /// Scrollable sidebar navigation content.
  final Widget sidebarBody;

  /// Optional top-bordered scrollable sidebar footer (e.g. SemVer build string).
  final Widget? sidebarFooter;

  /// Optional compact-only header placed at the top of the slide-over drawer (e.g. Workspace card).
  final Widget? sidebarHeader;

  /// Optional caller-owned [ScrollController] preserving sidebar scroll offset (`U-LAYOUT-007`).
  final ScrollController? sidebarScrollController;

  /// Trailing top chrome actions (location status, sync button).
  final List<Widget> trailingActions;

  /// Optional desktop workspace switcher pill hidden on `compact` viewports.
  final Widget? workspaceTrigger;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final safePadding = MediaQuery.paddingOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _resolveSystemUiOverlayStyle(tokens),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final viewport = UiBreakpoints.classify(width);
          final isCompact = viewport == UiViewportClass.compact;

          return Material(
            color: colors.bg,
            child: Column(
              children: <Widget>[
                _UiTopChromeBar(
                  viewport: viewport,
                  safePadding: safePadding,
                  brand: brand,
                  buildBadge: buildBadge,
                  mobileActiveFilter: mobileActiveFilter,
                  workspaceTrigger: workspaceTrigger,
                  searchWidget: searchWidget,
                  isSearchOpen: isSearchOpen,
                  trailingActions: trailingActions,
                  isDrawerOpen: isDrawerOpen,
                  onChromeDragStart: onChromeDragStart,
                  onChromeDoubleTap: onChromeDoubleTap,
                  onToggleDrawer: onToggleDrawer,
                  menuOpenTooltip: menuOpenTooltip,
                  menuCloseTooltip: menuCloseTooltip,
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: viewInsets.bottom),
                    child: _UiZeroPaddingScope(
                      child: _UiShellBodyStack(
                        viewport: viewport,
                        availableWidth: width,
                        isCompact: isCompact,
                        isDrawerOpen: isDrawerOpen,
                        safePadding: safePadding,
                        onToggleDrawer: onToggleDrawer,
                        sidebarHeader: sidebarHeader,
                        sidebarBody: sidebarBody,
                        sidebarFooter: sidebarFooter,
                        sidebarScrollController: sidebarScrollController,
                        body: body,
                        floatingNotice: floatingNotice,
                        bottomDock: bottomDock,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Top `62px` chrome bar with responsive compact search collapse and active-label brand swap (`U-LAYOUT-003`..`004`).
class _UiTopChromeBar extends StatelessWidget {
  /// Creates a [_UiTopChromeBar].
  const _UiTopChromeBar({
    required this.viewport,
    required this.safePadding,
    required this.brand,
    required this.buildBadge,
    required this.mobileActiveFilter,
    required this.workspaceTrigger,
    required this.searchWidget,
    required this.isSearchOpen,
    required this.trailingActions,
    required this.isDrawerOpen,
    required this.onChromeDragStart,
    required this.onChromeDoubleTap,
    required this.onToggleDrawer,
    required this.menuOpenTooltip,
    required this.menuCloseTooltip,
  });

  /// Desktop/default brand widget.
  final Widget brand;

  /// Optional inline build badge rendered after [workspaceTrigger] on desktop and beside [brand] on compact.
  final Widget? buildBadge;

  /// Whether compact drawer is open.
  final bool isDrawerOpen;

  /// Whether global search is open.
  final bool isSearchOpen;

  /// Tooltip when drawer is open.
  final String? menuCloseTooltip;

  /// Tooltip when drawer is closed.
  final String? menuOpenTooltip;

  /// Compact active-label replacement for [brand].
  final Widget? mobileActiveFilter;

  /// Optional callback invoked when double-tapping empty top chrome space.
  final VoidCallback? onChromeDoubleTap;

  /// Optional callback invoked when dragging empty top chrome space.
  final VoidCallback? onChromeDragStart;

  /// Drawer toggle callback.
  final VoidCallback? onToggleDrawer;

  /// System bar and display cutout safe-area insets applied to top and horizontal chrome edges.
  final EdgeInsets safePadding;

  /// Search toggle or active search input.
  final Widget? searchWidget;

  /// Trailing actions row.
  final List<Widget> trailingActions;

  /// Current viewport breakpoint class.
  final UiViewportClass viewport;

  /// Desktop workspace pill.
  final Widget? workspaceTrigger;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final isCompact = viewport == UiViewportClass.compact;
    final hasWindowGestures =
        onChromeDragStart != null || onChromeDoubleTap != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(
          bottom: BorderSide(
            color: colors.line,
            width: tokens.radii.borderWidth,
          ),
        ),
      ),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: <Widget>[
          if (hasWindowGestures)
            Positioned.fill(
              child: _UiChromeDragLayer(
                onDragStart: onChromeDragStart,
                onDoubleTap: onChromeDoubleTap,
              ),
            ),
          Padding(
            padding: EdgeInsets.only(
              top: safePadding.top,
              left: safePadding.left,
              right: safePadding.right,
            ),
            child: _UiZeroPaddingScope(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: tokens.spacing.chromeHeight,
                ),
                child: Padding(
                  padding: tokens.spacing.chromePadding(viewport),
                  child: isCompact
                      ? _buildCompactRow(tokens)
                      : _buildDesktopRow(tokens),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds compact (`<= 720px`) chrome bar layout.
  Widget _buildCompactRow(UiThemeTokens tokens) {
    if (isSearchOpen && searchWidget != null) {
      return Row(
        children: <Widget>[
          Expanded(child: searchWidget ?? const SizedBox.shrink()),
        ],
      );
    }

    return Row(
      children: <Widget>[
        UiButton(
          leadingIcon: isDrawerOpen ? Icons.close_rounded : Icons.menu_rounded,
          variant: UiButtonVariant.icon,
          density: UiButtonDensity.mobileTouch,
          tooltip: isDrawerOpen ? menuCloseTooltip : menuOpenTooltip,
          onPressed: onToggleDrawer,
        ),
        const SizedBox(width: 6.0),
        if (mobileActiveFilter case final activeFilter?)
          Expanded(child: activeFilter)
        else
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(child: brand),
                  if (buildBadge case final badge?) ...<Widget>[
                    const SizedBox(width: 6.0),
                    badge,
                  ],
                ],
              ),
            ),
          ),
        if (searchWidget case final search?) ...<Widget>[
          const SizedBox(width: 6.0),
          search,
        ],
        for (final action in trailingActions) ...<Widget>[
          const SizedBox(width: 6.0),
          action,
        ],
      ],
    );
  }

  /// Builds desktop (`> 720px`) chrome bar layout.
  Widget _buildDesktopRow(UiThemeTokens tokens) {
    return Row(
      children: <Widget>[
        brand,
        if (workspaceTrigger case final workspace?) ...<Widget>[
          const SizedBox(width: 18.0),
          workspace,
        ],
        if (buildBadge case final badge?) ...<Widget>[
          const SizedBox(width: 10.0),
          badge,
        ],
        if (isSearchOpen && searchWidget != null) ...<Widget>[
          const SizedBox(width: 10.0),
          Expanded(child: searchWidget ?? const SizedBox.shrink()),
        ] else ...<Widget>[const Spacer(), ?searchWidget],
        for (final action in trailingActions) ...<Widget>[
          const SizedBox(width: 10.0),
          action,
        ],
      ],
    );
  }
}

/// Full-bleed background gesture surface capturing empty-bar drags and double-taps behind interactive controls.
class _UiChromeDragLayer extends StatelessWidget {
  /// Creates a [_UiChromeDragLayer].
  const _UiChromeDragLayer({
    required this.onDragStart,
    required this.onDoubleTap,
  });

  /// Callback invoked on double-tap of empty top chrome space.
  final VoidCallback? onDoubleTap;

  /// Callback invoked when dragging starts on empty top chrome space.
  final VoidCallback? onDragStart;

  @override
  Widget build(BuildContext context) {
    final startDrag = onDragStart;
    return GestureDetector(
      key: const ValueKey<String>('ui_top_chrome_drag_region'),
      behavior: HitTestBehavior.opaque,
      onPanStart: startDrag == null ? null : (_) => startDrag(),
      onDoubleTap: onDoubleTap,
    );
  }
}

/// Below-chrome stack hosting persistent desktop sidebar or compact slide-over drawer + main column.
class _UiShellBodyStack extends StatelessWidget {
  /// Creates a [_UiShellBodyStack].
  const _UiShellBodyStack({
    required this.viewport,
    required this.availableWidth,
    required this.isCompact,
    required this.isDrawerOpen,
    required this.safePadding,
    required this.onToggleDrawer,
    required this.sidebarHeader,
    required this.sidebarBody,
    required this.sidebarFooter,
    required this.sidebarScrollController,
    required this.body,
    required this.floatingNotice,
    required this.bottomDock,
  });

  /// Available shell width for computing compact drawer cap (`min(300, 92%)`).
  final double availableWidth;

  /// Main pane body.
  final Widget body;

  /// Optional pinned bottom dock.
  final Widget? bottomDock;

  /// Optional floating notice anchored above [bottomDock].
  final Widget? floatingNotice;

  /// Whether viewport is compact (`<= 720px`).
  final bool isCompact;

  /// Whether compact drawer is open.
  final bool isDrawerOpen;

  /// Drawer toggle callback (invoked on scrim tap).
  final VoidCallback? onToggleDrawer;

  /// System bar and display cutout safe-area insets for sidebar, body, notices, and bottom dock.
  final EdgeInsets safePadding;

  /// Scrollable sidebar navigation body.
  final Widget sidebarBody;

  /// Optional scrollable sidebar footer.
  final Widget? sidebarFooter;

  /// Compact-only sidebar top header.
  final Widget? sidebarHeader;

  /// Preserved sidebar scroll controller.
  final ScrollController? sidebarScrollController;

  /// Viewport class.
  final UiViewportClass viewport;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final mainColumn = _UiMainColumn(
      viewport: viewport,
      isCompact: isCompact,
      safePadding: safePadding,
      body: body,
      floatingNotice: floatingNotice,
      bottomDock: bottomDock,
    );

    if (!isCompact) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: tokens.spacing.sidebarWidth + safePadding.left,
            child: _UiSidebarContainer(
              header: null,
              body: sidebarBody,
              footer: sidebarFooter,
              scrollController: sidebarScrollController,
              leftInset: safePadding.left,
              bottomInset: safePadding.bottom,
            ),
          ),
          Expanded(child: mainColumn),
        ],
      );
    }

    final drawerWidth = math.min(
      tokens.spacing.drawerMaxWidth + safePadding.left,
      availableWidth * 0.92,
    );

    return Stack(
      children: <Widget>[
        Positioned.fill(child: mainColumn),
        if (isDrawerOpen) ...<Widget>[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggleDrawer,
              child: ColoredBox(color: colors.scrim),
            ),
          ),
          Positioned(
            left: 0.0,
            top: 0.0,
            bottom: 0.0,
            width: drawerWidth,
            child: Semantics(
              scopesRoute: true,
              explicitChildNodes: true,
              child: _UiSidebarContainer(
                header: sidebarHeader,
                body: sidebarBody,
                footer: sidebarFooter,
                scrollController: sidebarScrollController,
                leftInset: safePadding.left,
                bottomInset: safePadding.bottom,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Independent scrollable sidebar surface with optional compact header and scrollable bottom footer (`U-LAYOUT-002`).
class _UiSidebarContainer extends StatelessWidget {
  /// Creates a [_UiSidebarContainer].
  const _UiSidebarContainer({
    required this.header,
    required this.body,
    required this.footer,
    required this.scrollController,
    required this.leftInset,
    required this.bottomInset,
  });

  /// Scrollable navigation sections.
  final Widget body;

  /// Bottom system navigation bar safe inset added below sidebar scroll content.
  final double bottomInset;

  /// Optional scrollable footer aligned to the bottom when navigation content fits.
  final Widget? footer;

  /// Optional compact header.
  final Widget? header;

  /// Left display cutout or system bar safe inset added to sidebar leading padding.
  final double leftInset;

  /// Optional scroll controller.
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.panel,
          border: Border(
            right: BorderSide(
              color: colors.line,
              width: tokens.radii.borderWidth,
            ),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final minContentHeight = constraints.maxHeight.isFinite
                ? math.max(0.0, constraints.maxHeight - 28.0 - bottomInset)
                : 0.0;
            return SingleChildScrollView(
              controller: scrollController,
              padding: EdgeInsets.fromLTRB(
                10.0 + leftInset,
                14.0,
                10.0,
                14.0 + bottomInset,
              ),
              child: _UiSidebarScrollContent(
                header: header,
                body: body,
                footer: footer,
                minContentHeight: minContentHeight,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Flex column inside the sidebar scroll view pushing [footer] to the bottom when space permits (`margin-top: auto`).
class _UiSidebarScrollContent extends StatelessWidget {
  /// Creates a [_UiSidebarScrollContent].
  const _UiSidebarScrollContent({
    required this.header,
    required this.body,
    required this.footer,
    required this.minContentHeight,
  });

  /// Scrollable navigation sections.
  final Widget body;

  /// Optional scrollable bottom footer.
  final Widget? footer;

  /// Optional compact header.
  final Widget? header;

  /// Minimum viewport height excluding vertical scroll padding.
  final double minContentHeight;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minContentHeight),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (header case final topHeader?) ...<Widget>[
                topHeader,
                SizedBox(height: tokens.spacing.space3),
              ],
              body,
            ],
          ),
          if (footer case final scrollFooter?)
            _UiSidebarFooterBox(child: scrollFooter),
        ],
      ),
    );
  }
}

/// Top-bordered scrollable sidebar footer matching `.sidebar-footer` spacing (`16px` top gap, `10px 8px 0` padding).
class _UiSidebarFooterBox extends StatelessWidget {
  /// Creates a [_UiSidebarFooterBox].
  const _UiSidebarFooterBox({required this.child});

  /// Footer content widget.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.space4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: colors.line,
              width: tokens.radii.borderWidth,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8.0, 10.0, 8.0, 0.0),
          child: child,
        ),
      ),
    );
  }
}

/// Main viewport stack decoupled strictly from the conditional pinned bottom dock (`U-LAYOUT-005`).
class _UiMainColumn extends StatelessWidget {
  /// Creates a [_UiMainColumn].
  const _UiMainColumn({
    required this.viewport,
    required this.isCompact,
    required this.safePadding,
    required this.body,
    required this.floatingNotice,
    required this.bottomDock,
  });

  /// Main content body.
  final Widget body;

  /// Optional pinned bottom dock.
  final Widget? bottomDock;

  /// Optional floating bottom toast anchored inside the viewport region.
  final Widget? floatingNotice;

  /// Whether viewport is compact (determining whether left safe inset applies here vs persistent sidebar).
  final bool isCompact;

  /// System bar and display cutout safe-area insets.
  final EdgeInsets safePadding;

  /// Active viewport class.
  final UiViewportClass viewport;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final noticeBottom = isCompact
        ? tokens.spacing.floatingNoticeInsetCompact
        : tokens.spacing.floatingNoticeInsetDesktop;
    final noticeHorizontal = isCompact ? 14.0 : 26.0;
    final mainLeftInset = isCompact ? safePadding.left : 0.0;
    final mainRightInset = safePadding.right;
    final mainBottomInset = bottomDock == null ? safePadding.bottom : 0.0;
    final dockPadding = tokens.spacing.dockPadding(viewport);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    mainLeftInset,
                    0.0,
                    mainRightInset,
                    mainBottomInset,
                  ),
                  child: body,
                ),
              ),
              if (floatingNotice case final notice?)
                Positioned(
                  left: noticeHorizontal + mainLeftInset,
                  right: noticeHorizontal + mainRightInset,
                  bottom: noticeBottom + mainBottomInset,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    heightFactor: 1.0,
                    child: notice,
                  ),
                ),
            ],
          ),
        ),
        if (bottomDock case final dock?)
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.bg,
              border: Border(
                top: BorderSide(
                  color: colors.line,
                  width: tokens.radii.borderWidth,
                ),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                dockPadding.left + mainLeftInset,
                dockPadding.top,
                dockPadding.right + mainRightInset,
                dockPadding.bottom + safePadding.bottom,
              ),
              child: dock,
            ),
          ),
      ],
    );
  }
}

/// Clears consumed `MediaQuery.padding` for shell descendants while preserving `viewPadding` and `viewInsets`.
class _UiZeroPaddingScope extends StatelessWidget {
  /// Creates a [_UiZeroPaddingScope] wrapping [child].
  const _UiZeroPaddingScope({required this.child});

  /// Descendant subtree shielded from duplicate `MediaQuery.padding`.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(padding: EdgeInsets.zero),
      child: child,
    );
  }
}

/// Resolves theme-contrasting edge-to-edge system bar overlay styling for [tokens].
SystemUiOverlayStyle _resolveSystemUiOverlayStyle(UiThemeTokens tokens) {
  final iconBrightness = tokens.brightness == Brightness.dark
      ? Brightness.light
      : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: iconBrightness,
    statusBarBrightness: tokens.brightness,
    systemNavigationBarColor: tokens.colors.bg,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: iconBrightness,
    systemNavigationBarContrastEnforced: false,
  );
}
