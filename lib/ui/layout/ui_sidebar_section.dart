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

import 'package:material_ui/material_ui.dart';

import '../primitives/ui_button.dart';
import '../primitives/ui_field.dart';
import '../tokens/ui_breakpoints.dart';
import '../tokens/ui_theme_tokens.dart';
import '../tokens/ui_typography_tokens.dart';

/// Immutable navigation row model rendered inside [UiSidebarSection].
@immutable
class UiSidebarNavItem {
  /// Creates a [UiSidebarNavItem].
  const UiSidebarNavItem({
    required this.id,
    required this.label,
    this.subtitle,
    this.icon,
    this.colorDot,
    this.countLabel,
    this.isSelected = false,
    this.onTap,
    this.trailingIcon,
    this.trailingTooltip,
    this.isTrailingActive = false,
    this.onTrailingTap,
    this.trailingHintIcon,
  });

  /// Optional square color indicator dot (used for Labels).
  final Color? colorDot;

  /// Optional right-aligned tabular count string.
  final String? countLabel;

  /// Optional leading outline icon glyph.
  final IconData? icon;

  /// Stable identifier used for deterministic widget keys.
  final String id;

  /// Whether this navigation item represents the active destination.
  final bool isSelected;

  /// Whether the split trailing action icon is highlighted active.
  final bool isTrailingActive;

  /// Caller-supplied display label.
  final String label;

  /// Primary row tap callback.
  final VoidCallback? onTap;

  /// Optional split secondary action callback (e.g. Label info hub trigger).
  final VoidCallback? onTrailingTap;

  /// Optional micro subtitle rendered below [label] (e.g. `Scoped Queue`).
  final String? subtitle;

  /// Decorative trailing hint icon excluded from semantics for single-button rows (e.g. Locations).
  final IconData? trailingHintIcon;

  /// Optional interactive trailing action icon for split rows.
  final IconData? trailingIcon;

  /// Accessible tooltip for [trailingIcon].
  final String? trailingTooltip;
}

/// Static or collapsible/filterable sidebar navigation group (`U-UX-001`).
class UiSidebarSection extends StatefulWidget {
  /// Creates a [UiSidebarSection].
  const UiSidebarSection({
    super.key,
    required this.title,
    required this.items,
    this.isCollapsible = false,
    this.isCollapsed = false,
    this.onToggleCollapse,
    this.collapsedCountLabel,
    this.collapsedActiveColorDot,
    this.isFilterable = false,
    this.isFilterOpen = false,
    this.onToggleFilter,
    this.filterQuery = '',
    this.onFilterChanged,
    this.filterPlaceholder,
    this.filterClearTooltip,
    this.filterEmptyText,
    this.onManage,
    this.isManageActive = false,
    this.filterTooltip,
    this.manageTooltip,
    this.collapseTooltip,
    this.expandTooltip,
    this.showTopDivider = false,
  });

  /// Optional active filter color dot shown beside [title] ONLY while collapsed.
  final Color? collapsedActiveColorDot;

  /// Optional total count shown beside [title] ONLY while collapsed.
  final String? collapsedCountLabel;

  /// Tooltip for the collapse chevron while expanded.
  final String? collapseTooltip;

  /// Tooltip for the expand chevron while collapsed.
  final String? expandTooltip;

  /// Tooltip for the filter search clear button.
  final String? filterClearTooltip;

  /// Muted empty text rendered when [isFilterOpen] is true and [items] is empty.
  final String? filterEmptyText;

  /// Placeholder for the inline sidebar filter input.
  final String? filterPlaceholder;

  /// Current filter query value.
  final String filterQuery;

  /// Tooltip for the filter icon toggle button.
  final String? filterTooltip;

  /// Whether this collapsible section is currently collapsed.
  final bool isCollapsed;

  /// Whether collapse/expand controls are enabled.
  final bool isCollapsible;

  /// Whether the inline filter search box is currently open.
  final bool isFilterOpen;

  /// Whether the section exposes an inline search filter action.
  final bool isFilterable;

  /// Whether the manage icon button is highlighted active.
  final bool isManageActive;

  /// Navigation items rendered inside the section.
  final List<UiSidebarNavItem> items;

  /// Tooltip for the manage icon button.
  final String? manageTooltip;

  /// Callback invoked when the inline filter text changes.
  final ValueChanged<String>? onFilterChanged;

  /// Optional manage manager-view navigation callback.
  final VoidCallback? onManage;

  /// Callback toggling collapsed state.
  final VoidCallback? onToggleCollapse;

  /// Callback toggling inline filter visibility.
  final VoidCallback? onToggleFilter;

  /// Renders a top `1px` `line` divider (used for `Tools` section).
  final bool showTopDivider;

  /// Section eyebrow title (rendered uppercase).
  final String title;

  @override
  State<UiSidebarSection> createState() => _UiSidebarSectionState();
}

/// Manages inline filter controller/focus lifecycle and auto-expand/clear coordination for [UiSidebarSection].
class _UiSidebarSectionState extends State<UiSidebarSection> {
  /// Text controller mirrored with `widget.filterQuery`.
  late final TextEditingController _filterController;

  /// Focus node focused automatically when the filter box opens.
  late final FocusNode _filterFocusNode;

  @override
  void initState() {
    super.initState();
    _filterController = TextEditingController(text: widget.filterQuery);
    _filterFocusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant UiSidebarSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filterQuery != _filterController.text) {
      _filterController.text = widget.filterQuery;
      _filterController.selection = TextSelection.collapsed(
        offset: _filterController.text.length,
      );
    }
    if (!oldWidget.isFilterOpen && widget.isFilterOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isFilterOpen) {
          _filterFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _filterFocusNode.dispose();
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final isCompact = UiBreakpoints.isCompact(MediaQuery.sizeOf(context).width);
    final actionDensity = isCompact
        ? UiButtonDensity.chrome
        : UiButtonDensity.sidebarDesktop;
    final showBody = !widget.isCollapsible || !widget.isCollapsed;

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _UiSidebarSectionHeader(
          title: widget.title,
          isCollapsible: widget.isCollapsible,
          isCollapsed: widget.isCollapsed,
          collapsedCountLabel: widget.collapsedCountLabel,
          collapsedActiveColorDot: widget.collapsedActiveColorDot,
          isFilterable: widget.isFilterable,
          isFilterOpen: widget.isFilterOpen,
          isManageActive: widget.isManageActive,
          actionDensity: actionDensity,
          filterTooltip: widget.filterTooltip,
          manageTooltip: widget.manageTooltip,
          collapseTooltip: widget.collapseTooltip,
          expandTooltip: widget.expandTooltip,
          onFilterTap: _handleFilterToggle,
          onManageTap: widget.onManage,
          onCollapseTap: _handleCollapseToggle,
        ),
        if (showBody) ...<Widget>[
          if (widget.isFilterable && widget.isFilterOpen)
            Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 6.0),
              child: UiField(
                kind: UiFieldKind.search,
                controller: _filterController,
                focusNode: _filterFocusNode,
                height: tokens.spacing.buttonCompactHeight,
                hintText: widget.filterPlaceholder,
                clearTooltip: widget.filterClearTooltip,
                onChanged: widget.onFilterChanged,
              ),
            ),
          if (widget.items.isEmpty &&
              widget.isFilterOpen &&
              widget.filterEmptyText != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                widget.filterEmptyText ?? '',
                style: tokens.typography.meta.copyWith(color: colors.muted),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var i = 0; i < widget.items.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: 2.0),
                  _UiSidebarNavRow(
                    key: ValueKey<String>(widget.items[i].id),
                    item: widget.items[i],
                  ),
                ],
              ],
            ),
        ],
      ],
    );

    if (widget.showTopDivider) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: colors.line,
              width: tokens.radii.borderWidth,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: content,
        ),
      );
    }

    return content;
  }

  /// Collapses/expands the section and clears/closes active filter on collapse (`U-UX-001`).
  void _handleCollapseToggle() {
    if (!widget.isCollapsed) {
      if (_filterController.text.isNotEmpty) {
        _filterController.clear();
        widget.onFilterChanged?.call('');
      }
      if (widget.isFilterOpen) {
        widget.onToggleFilter?.call();
      }
    }
    widget.onToggleCollapse?.call();
  }

  /// Auto-expands collapsed sections when opening filter, and clears query when closing filter (`U-UX-001`).
  void _handleFilterToggle() {
    if (!widget.isFilterOpen) {
      if (widget.isCollapsible && widget.isCollapsed) {
        widget.onToggleCollapse?.call();
      }
      widget.onToggleFilter?.call();
      return;
    }
    if (_filterController.text.isNotEmpty) {
      _filterController.clear();
      widget.onFilterChanged?.call('');
    }
    widget.onToggleFilter?.call();
  }
}

/// Eyebrow heading row with collapsed count/dot summary and up to 3 icon actions.
class _UiSidebarSectionHeader extends StatelessWidget {
  /// Creates a [_UiSidebarSectionHeader].
  const _UiSidebarSectionHeader({
    required this.title,
    required this.isCollapsible,
    required this.isCollapsed,
    required this.collapsedCountLabel,
    required this.collapsedActiveColorDot,
    required this.isFilterable,
    required this.isFilterOpen,
    required this.isManageActive,
    required this.actionDensity,
    required this.filterTooltip,
    required this.manageTooltip,
    required this.collapseTooltip,
    required this.expandTooltip,
    required this.onFilterTap,
    required this.onManageTap,
    required this.onCollapseTap,
  });

  /// Button density (`sidebarDesktop` 26px vs `chrome` 34px on compact).
  final UiButtonDensity actionDensity;

  /// Optional active color dot displayed only while collapsed.
  final Color? collapsedActiveColorDot;

  /// Optional count displayed only while collapsed.
  final String? collapsedCountLabel;

  /// Collapse chevron tooltip.
  final String? collapseTooltip;

  /// Expand chevron tooltip.
  final String? expandTooltip;

  /// Filter icon tooltip.
  final String? filterTooltip;

  /// Whether section is collapsed.
  final bool isCollapsed;

  /// Whether collapse button is shown.
  final bool isCollapsible;

  /// Whether filter icon is active.
  final bool isFilterOpen;

  /// Whether filter button is shown.
  final bool isFilterable;

  /// Whether manage button is highlighted active.
  final bool isManageActive;

  /// Manage icon tooltip.
  final String? manageTooltip;

  /// Collapse button callback.
  final VoidCallback onCollapseTap;

  /// Filter button callback.
  final VoidCallback onFilterTap;

  /// Optional manage button callback.
  final VoidCallback? onManageTap;

  /// Section title.
  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final showCollapsedSummary = isCollapsible && isCollapsed;

    return Padding(
      padding: EdgeInsets.only(
        left: 8.0,
        right: 2.0,
        bottom: showCollapsedSummary ? 0.0 : 5.0,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(
                  child: Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.typography.eyebrow.copyWith(
                      color: colors.muted,
                    ),
                  ),
                ),
                if (showCollapsedSummary &&
                    collapsedActiveColorDot != null) ...<Widget>[
                  const SizedBox(width: 6.0),
                  ExcludeSemantics(
                    child: Container(
                      width: 8.0,
                      height: 8.0,
                      decoration: BoxDecoration(
                        color: collapsedActiveColorDot,
                        borderRadius: BorderRadius.circular(tokens.radii.dotSm),
                      ),
                    ),
                  ),
                ],
                if (showCollapsedSummary &&
                    collapsedCountLabel != null) ...<Widget>[
                  const SizedBox(width: 6.0),
                  Text(
                    collapsedCountLabel ?? '',
                    style: UiTypographyTokens.tabular(
                      tokens.typography.eyebrow.copyWith(
                        color: colors.muted,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.0,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isFilterable)
            UiButton(
              leadingIcon: Icons.search_rounded,
              variant: UiButtonVariant.icon,
              density: actionDensity,
              isActive: isFilterOpen,
              tooltip: filterTooltip,
              onPressed: onFilterTap,
            ),
          if (onManageTap != null)
            UiButton(
              leadingIcon: Icons.edit_outlined,
              variant: UiButtonVariant.icon,
              density: actionDensity,
              isActive: isManageActive,
              tooltip: manageTooltip,
              onPressed: onManageTap,
            ),
          if (isCollapsible)
            UiButton(
              leadingIcon: isCollapsed
                  ? Icons.chevron_right_rounded
                  : Icons.expand_more_rounded,
              variant: UiButtonVariant.icon,
              density: actionDensity,
              tooltip: isCollapsed ? expandTooltip : collapseTooltip,
              onPressed: onCollapseTap,
            ),
        ],
      ),
    );
  }
}

/// Interactive sidebar navigation row supporting single-button and split-action layouts.
class _UiSidebarNavRow extends StatefulWidget {
  /// Creates a [_UiSidebarNavRow].
  const _UiSidebarNavRow({super.key, required this.item});

  /// Row configuration data.
  final UiSidebarNavItem item;

  @override
  State<_UiSidebarNavRow> createState() => _UiSidebarNavRowState();
}

/// Tracks hover and keyboard focus state for [_UiSidebarNavRow].
class _UiSidebarNavRowState extends State<_UiSidebarNavRow> {
  /// Whether the primary row is hovered.
  bool _isHovered = false;

  /// Whether keyboard focus ring is visible.
  bool _showFocusRing = false;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final item = widget.item;
    final hasSplitTrailing =
        item.trailingIcon != null && item.onTrailingTap != null;

    final background = item.isSelected
        ? colors.soft
        : (_isHovered ? colors.bg : Colors.transparent);
    final foreground = item.isSelected
        ? colors.accent
        : (_isHovered ? colors.ink : colors.muted);

    Widget primaryButton = AnimatedContainer(
      duration: tokens.focus.hoverDuration,
      constraints: BoxConstraints(minHeight: tokens.spacing.navRowHeight),
      padding: EdgeInsets.fromLTRB(
        10.0,
        7.0,
        item.trailingHintIcon != null ? 4.0 : 10.0,
        7.0,
      ),
      decoration: BoxDecoration(
        color: hasSplitTrailing ? Colors.transparent : background,
        borderRadius: BorderRadius.circular(tokens.radii.md),
      ),
      child: Row(
        children: <Widget>[
          if (item.colorDot case final dotColor?) ...<Widget>[
            ExcludeSemantics(
              child: Container(
                width: 8.0,
                height: 8.0,
                decoration: BoxDecoration(
                  color: dotColor,
                  borderRadius: BorderRadius.circular(tokens.radii.dotSm),
                ),
              ),
            ),
            const SizedBox(width: 9.0),
          ] else if (item.icon case final glyph?) ...<Widget>[
            ExcludeSemantics(
              child: Icon(
                glyph,
                size: tokens.spacing.iconMd,
                color: foreground,
              ),
            ),
            const SizedBox(width: 9.0),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  item.label,
                  style: tokens.typography.control.copyWith(
                    color: foreground,
                    fontWeight: item.isSelected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
                if (item.subtitle case final sub?) ...<Widget>[
                  const SizedBox(height: 1.0),
                  Text(
                    sub,
                    style: tokens.typography.micro.copyWith(
                      color: colors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (item.countLabel case final count?) ...<Widget>[
            const SizedBox(width: 6.0),
            Text(
              count,
              style: UiTypographyTokens.tabular(
                tokens.typography.eyebrow.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.0,
                ),
              ),
            ),
          ],
          if (item.trailingHintIcon case final hintGlyph?) ...<Widget>[
            const SizedBox(width: 4.0),
            ExcludeSemantics(
              child: SizedBox(
                width: 24.0,
                height: 24.0,
                child: Icon(
                  hintGlyph,
                  size: tokens.spacing.iconXs,
                  color: item.isSelected || _isHovered
                      ? colors.accent
                      : colors.muted,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final ringInset = tokens.focus.ringOffset + tokens.focus.ringWidth;
    primaryButton = Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: <Widget>[
        primaryButton,
        if (_showFocusRing)
          Positioned.fill(
            left: -ringInset,
            top: -ringInset,
            right: -ringInset,
            bottom: -ringInset,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    tokens.radii.md + ringInset,
                  ),
                  border: Border.all(
                    color: colors.accent,
                    width: tokens.focus.ringWidth,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    final clickablePrimary = Semantics(
      button: true,
      selected: item.isSelected,
      label: item.label,
      child: FocusableActionDetector(
        mouseCursor: item.onTap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (hovered) {
          if (_isHovered != hovered) {
            setState(() => _isHovered = hovered);
          }
        },
        onShowFocusHighlight: (focused) {
          if (_showFocusRing != focused) {
            setState(() => _showFocusRing = focused);
          }
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              item.onTap?.call();
              return null;
            },
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) {
              item.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: item.onTap,
          child: primaryButton,
        ),
      ),
    );

    if (!hasSplitTrailing) {
      return clickablePrimary;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(tokens.radii.md),
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: clickablePrimary),
          UiButton(
            leadingIcon: item.trailingIcon,
            variant: UiButtonVariant.icon,
            density: UiButtonDensity.dense,
            isActive: item.isTrailingActive,
            tooltip: item.trailingTooltip,
            onPressed: item.onTrailingTap,
          ),
        ],
      ),
    );
  }
}
