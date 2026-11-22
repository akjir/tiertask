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

import '../tokens/ui_breakpoints.dart';
import '../tokens/ui_theme_tokens.dart';
import 'ui_button.dart';

/// Structural surface role for [UiCard] (`U-COMP-002`, `U-CARD-001`..`006`).
enum UiCardVariant {
  /// Flat `panel` static card (`Settings`, `Conflict`, `Console`, `Raw TDF`).
  standard,

  /// Nested `bg` section well unconditionally wrapping descendants in `UiSurfaceScope.insetWell`.
  inset,

  /// Accent-bordered uncommitted draft card (`U-CARD-006`).
  draft,

  /// Unified expandable entity card shared by Tasks, Labels, and Locations (`U-CARD-001`).
  expandable,
}

/// Unified flat border-delimited card primitive supporting standard, inset, draft, and expandable roles.
class UiCard extends StatelessWidget {
  /// Creates a static `panel` [UiCard] (`standard` variant).
  const UiCard.standard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16.0),
    this.isHighlighted = false,
    this.headerIcon,
    this.headerTitle,
    this.headerBadge,
    this.headerTrailing,
  }) : variant = UiCardVariant.standard,
       isEditing = false,
       footer = null,
       subtitle = null,
       errorText = null,
       onClose = null,
       closeTooltip = null,
       title = null,
       leading = null,
       titleEditor = null,
       isEditingTitle = false,
       trailingActions = const <Widget>[],
       collapsedMetadata = null,
       expandedChild = null,
       isExpanded = false,
       isCompleted = false,
       onToggleExpand = null,
       toggleSemanticLabel = null;

  /// Creates a nested `bg` inset well [UiCard] wrapping its subtree in `UiSurfaceScope.insetWell`.
  const UiCard.inset({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 13.0, vertical: 11.0),
    this.isEditing = false,
    this.headerIcon,
    this.headerTitle,
    this.headerBadge,
    this.headerTrailing,
    this.footer,
  }) : variant = UiCardVariant.inset,
       isHighlighted = false,
       subtitle = null,
       errorText = null,
       onClose = null,
       closeTooltip = null,
       title = null,
       leading = null,
       titleEditor = null,
       isEditingTitle = false,
       trailingActions = const <Widget>[],
       collapsedMetadata = null,
       expandedChild = null,
       isExpanded = false,
       isCompleted = false,
       onToggleExpand = null,
       toggleSemanticLabel = null;

  /// Creates an accent-bordered uncommitted draft [UiCard] (`U-CARD-006`).
  const UiCard.draft({
    super.key,
    required String this.title,
    required this.child,
    this.subtitle,
    this.errorText,
    this.footer,
    this.onClose,
    this.closeTooltip,
    this.padding = const EdgeInsets.all(16.0),
  }) : variant = UiCardVariant.draft,
       isHighlighted = false,
       isEditing = false,
       headerIcon = null,
       headerTitle = null,
       headerBadge = null,
       headerTrailing = null,
       leading = null,
       titleEditor = null,
       isEditingTitle = false,
       trailingActions = const <Widget>[],
       collapsedMetadata = null,
       expandedChild = null,
       isExpanded = false,
       isCompleted = false,
       onToggleExpand = null,
       toggleSemanticLabel = null;

  /// Creates a unified expandable entity [UiCard] (`U-CARD-001`).
  const UiCard.expandable({
    super.key,
    required String this.title,
    required this.isExpanded,
    required VoidCallback this.onToggleExpand,
    this.leading,
    this.titleEditor,
    this.isEditingTitle = false,
    this.trailingActions = const <Widget>[],
    this.collapsedMetadata,
    this.expandedChild,
    this.isCompleted = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 14.0, vertical: 11.0),
    this.toggleSemanticLabel,
  }) : variant = UiCardVariant.expandable,
       child = null,
       isHighlighted = false,
       isEditing = false,
       headerIcon = null,
       headerTitle = null,
       headerBadge = null,
       headerTrailing = null,
       footer = null,
       subtitle = null,
       errorText = null,
       onClose = null,
       closeTooltip = null;

  /// Primary body widget for `standard`, `inset`, and `draft` variants.
  final Widget? child;

  /// Accessible tooltip for the close button on `draft` cards.
  final String? closeTooltip;

  /// Metadata badge strip shown below the header only while collapsed (`expandable`).
  final Widget? collapsedMetadata;

  /// Inline validation error shown with live-region semantics on `draft` cards.
  final String? errorText;

  /// Revealable body rendered while `isExpanded` is true (`expandable`).
  final Widget? expandedChild;

  /// Optional bottom footer slot (`inset`, `draft`).
  final Widget? footer;

  /// Optional status badge shown beside [headerTitle] (`standard`, `inset`).
  final Widget? headerBadge;

  /// Optional leading icon in the card header (`standard`, `inset`).
  final IconData? headerIcon;

  /// Optional heading title (`standard`, `inset`).
  final String? headerTitle;

  /// Optional trailing action widget in the header (`standard`, `inset`).
  final Widget? headerTrailing;

  /// Marks an `expandable` task card completed (struck-through muted title).
  final bool isCompleted;

  /// Highlights an `inset` card border with `accent` while editing (`U-CARD-003`).
  final bool isEditing;

  /// Swaps the `expandable` title text to [titleEditor] while editing inline.
  final bool isEditingTitle;

  /// Whether an `expandable` card is currently expanded.
  final bool isExpanded;

  /// Renders a `standard` card with `soft` fill and `accent` border (e.g. active workspace).
  final bool isHighlighted;

  /// Optional `34x34px` leading slot (`expandable`).
  final Widget? leading;

  /// Close callback for `draft` cards.
  final VoidCallback? onClose;

  /// Expand/collapse toggle callback for `expandable` cards.
  final VoidCallback? onToggleExpand;

  /// Internal card padding.
  final EdgeInsetsGeometry padding;

  /// Optional muted subtitle in `draft` card header.
  final String? subtitle;

  /// Primary title (`draft` and `expandable`).
  final String? title;

  /// Inline title editor widget swapped in when `isEditingTitle` is true (`expandable`).
  final Widget? titleEditor;

  /// Explicit accessible toggle label for `expandable` cards.
  final String? toggleSemanticLabel;

  /// Right-aligned action widgets in `expandable` card headers.
  final List<Widget> trailingActions;

  /// Card variant selected via named constructor.
  final UiCardVariant variant;

  @override
  Widget build(BuildContext context) {
    return switch (variant) {
      UiCardVariant.standard => _UiStandardCard(
        padding: padding,
        isHighlighted: isHighlighted,
        headerIcon: headerIcon,
        headerTitle: headerTitle,
        headerBadge: headerBadge,
        headerTrailing: headerTrailing,
        child: child ?? const SizedBox.shrink(),
      ),
      UiCardVariant.inset => _UiInsetCard(
        padding: padding,
        isEditing: isEditing,
        headerIcon: headerIcon,
        headerTitle: headerTitle,
        headerBadge: headerBadge,
        headerTrailing: headerTrailing,
        footer: footer,
        child: child ?? const SizedBox.shrink(),
      ),
      UiCardVariant.draft => _UiDraftCard(
        title: title ?? '',
        subtitle: subtitle,
        errorText: errorText,
        footer: footer,
        onClose: onClose,
        closeTooltip: closeTooltip,
        padding: padding,
        child: child ?? const SizedBox.shrink(),
      ),
      UiCardVariant.expandable => _UiExpandableCard(
        title: title ?? '',
        isExpanded: isExpanded,
        onToggleExpand: onToggleExpand,
        leading: leading,
        titleEditor: titleEditor,
        isEditingTitle: isEditingTitle,
        trailingActions: trailingActions,
        collapsedMetadata: collapsedMetadata,
        expandedChild: expandedChild,
        isCompleted: isCompleted,
        padding: padding,
        toggleSemanticLabel: toggleSemanticLabel,
      ),
    };
  }
}

/// Optional shared header row rendered inside `standard` and `inset` cards.
class _UiCardHeaderRow extends StatelessWidget {
  /// Creates a [_UiCardHeaderRow].
  const _UiCardHeaderRow({
    required this.icon,
    required this.title,
    required this.badge,
    required this.trailing,
    required this.isInset,
  });

  /// Optional badge beside [title].
  final Widget? badge;

  /// Optional leading icon glyph.
  final IconData? icon;

  /// Whether this header belongs to an `inset` card (`12px` uppercase-like section heading).
  final bool isInset;

  /// Optional heading text.
  final String? title;

  /// Optional trailing control.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final titleStyle = isInset
        ? tokens.typography.meta.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.w600,
          )
        : tokens.typography.body.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.w600,
          );

    return Row(
      children: <Widget>[
        if (icon case final glyph?) ...<Widget>[
          ExcludeSemantics(
            child: Icon(
              glyph,
              size: tokens.spacing.iconSm,
              color: colors.accent,
            ),
          ),
          const SizedBox(width: 8.0),
        ],
        if (title case final heading?)
          Flexible(
            child: Text(
              heading,
              style: titleStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (badge case final badgeWidget?) ...<Widget>[
          const SizedBox(width: 8.0),
          badgeWidget,
        ],
        if (trailing != null) const Spacer(),
        ?trailing,
      ],
    );
  }
}

/// Flat `panel` (or highlighted `soft`) static card (`UiCardVariant.standard`).
class _UiStandardCard extends StatelessWidget {
  /// Creates a [_UiStandardCard].
  const _UiStandardCard({
    required this.padding,
    required this.isHighlighted,
    required this.headerIcon,
    required this.headerTitle,
    required this.headerBadge,
    required this.headerTrailing,
    required this.child,
  });

  /// Card body.
  final Widget child;

  /// Optional header badge.
  final Widget? headerBadge;

  /// Optional header icon.
  final IconData? headerIcon;

  /// Optional header title.
  final String? headerTitle;

  /// Optional header trailing widget.
  final Widget? headerTrailing;

  /// Whether to render highlighted in `soft`/`accent`.
  final bool isHighlighted;

  /// Internal card padding.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final hasHeader =
        headerIcon != null ||
        headerTitle != null ||
        headerBadge != null ||
        headerTrailing != null;

    return AnimatedContainer(
      duration: tokens.focus.hoverDuration,
      padding: padding,
      decoration: BoxDecoration(
        color: isHighlighted ? colors.soft : colors.panel,
        borderRadius: BorderRadius.circular(tokens.radii.card),
        border: Border.all(
          color: isHighlighted ? colors.accent : colors.line,
          width: tokens.radii.borderWidth,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (hasHeader) ...<Widget>[
            _UiCardHeaderRow(
              icon: headerIcon,
              title: headerTitle,
              badge: headerBadge,
              trailing: headerTrailing,
              isInset: false,
            ),
            SizedBox(height: tokens.spacing.space3),
          ],
          child,
        ],
      ),
    );
  }
}

/// Nested `bg` section well unconditionally wrapping descendants in `UiSurfaceScope.insetWell`.
class _UiInsetCard extends StatelessWidget {
  /// Creates a [_UiInsetCard].
  const _UiInsetCard({
    required this.padding,
    required this.isEditing,
    required this.headerIcon,
    required this.headerTitle,
    required this.headerBadge,
    required this.headerTrailing,
    required this.footer,
    required this.child,
  });

  /// Well content.
  final Widget child;

  /// Optional bottom footer row.
  final Widget? footer;

  /// Optional header badge.
  final Widget? headerBadge;

  /// Optional header icon.
  final IconData? headerIcon;

  /// Optional header title.
  final String? headerTitle;

  /// Optional header trailing action.
  final Widget? headerTrailing;

  /// Switches hairline border from `line` to `accent` while editing.
  final bool isEditing;

  /// Internal well padding.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final hasHeader =
        headerIcon != null ||
        headerTitle != null ||
        headerBadge != null ||
        headerTrailing != null;

    return UiSurfaceScope(
      level: UiSurfaceLevel.insetWell,
      child: AnimatedContainer(
        duration: tokens.focus.hoverDuration,
        padding: padding,
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(tokens.radii.row),
          border: Border.all(
            color: isEditing ? colors.accent : colors.line,
            width: tokens.radii.borderWidth,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (hasHeader) ...<Widget>[
              _UiCardHeaderRow(
                icon: headerIcon,
                title: headerTitle,
                badge: headerBadge,
                trailing: headerTrailing,
                isInset: true,
              ),
              SizedBox(height: tokens.spacing.space2),
            ],
            child,
            if (footer case final footerWidget?) ...<Widget>[
              SizedBox(height: tokens.spacing.space3),
              footerWidget,
            ],
          ],
        ),
      ),
    );
  }
}

/// Persistent `accent`-bordered uncommitted draft card (`UiCardVariant.draft`).
class _UiDraftCard extends StatelessWidget {
  /// Creates a [_UiDraftCard].
  const _UiDraftCard({
    required this.title,
    required this.subtitle,
    required this.errorText,
    required this.footer,
    required this.onClose,
    required this.closeTooltip,
    required this.padding,
    required this.child,
  });

  /// Draft form body.
  final Widget child;

  /// Accessible tooltip for close button.
  final String? closeTooltip;

  /// Optional inline validation error text.
  final String? errorText;

  /// Optional draft action footer.
  final Widget? footer;

  /// Optional close button callback.
  final VoidCallback? onClose;

  /// Internal padding.
  final EdgeInsetsGeometry padding;

  /// Optional muted draft status subtitle.
  final String? subtitle;

  /// Draft heading title.
  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return AnimatedContainer(
      duration: tokens.focus.hoverDuration,
      padding: padding,
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(tokens.radii.card),
        border: Border.all(
          color: colors.accent,
          width: tokens.radii.borderWidth,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: tokens.typography.cardTitle.copyWith(
                        color: colors.ink,
                      ),
                    ),
                    if (subtitle case final sub?) ...<Widget>[
                      const SizedBox(height: 2.0),
                      Text(
                        sub,
                        style: tokens.typography.meta.copyWith(
                          color: colors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onClose != null)
                UiButton(
                  leadingIcon: Icons.close_rounded,
                  variant: UiButtonVariant.icon,
                  density: UiButtonDensity.dense,
                  tooltip: closeTooltip,
                  onPressed: onClose,
                ),
            ],
          ),
          SizedBox(height: tokens.spacing.space3),
          child,
          if (errorText case final error?) ...<Widget>[
            SizedBox(height: tokens.spacing.space2),
            Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: tokens.typography.meta.copyWith(
                  color: colors.danger,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          if (footer case final footerWidget?) ...<Widget>[
            SizedBox(height: tokens.spacing.space3),
            footerWidget,
          ],
        ],
      ),
    );
  }
}

/// Unified expandable entity card with single-expand reveal and hover border discipline (`U-CARD-001`).
class _UiExpandableCard extends StatefulWidget {
  /// Creates a [_UiExpandableCard].
  const _UiExpandableCard({
    required this.title,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.leading,
    required this.titleEditor,
    required this.isEditingTitle,
    required this.trailingActions,
    required this.collapsedMetadata,
    required this.expandedChild,
    required this.isCompleted,
    required this.padding,
    required this.toggleSemanticLabel,
  });

  /// Metadata strip displayed when collapsed.
  final Widget? collapsedMetadata;

  /// Panel shown when expanded.
  final Widget? expandedChild;

  /// Renders struck-through muted title when true.
  final bool isCompleted;

  /// Swaps title text to [titleEditor] when true.
  final bool isEditingTitle;

  /// Whether the accordion panel is expanded.
  final bool isExpanded;

  /// Optional `34x34px` leading slot.
  final Widget? leading;

  /// Header toggle callback.
  final VoidCallback? onToggleExpand;

  /// Internal padding.
  final EdgeInsetsGeometry padding;

  /// Entity title text.
  final String title;

  /// Inline title editor widget.
  final Widget? titleEditor;

  /// Explicit accessible header toggle label.
  final String? toggleSemanticLabel;

  /// Trailing header action widgets.
  final List<Widget> trailingActions;

  @override
  State<_UiExpandableCard> createState() => _UiExpandableCardState();
}

/// Tracks collapsed hover highlight and keyboard focus ring for [_UiExpandableCard].
class _UiExpandableCardState extends State<_UiExpandableCard> {
  /// Whether the pointer is hovering over the card.
  bool _isHovered = false;

  /// Whether keyboard focus ring is visible on the header toggle.
  bool _showFocusRing = false;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isCompact = UiBreakpoints.isCompact(viewportWidth);
    final borderColor = !widget.isExpanded && _isHovered
        ? colors.accent
        : colors.line;

    return MouseRegion(
      onEnter: (_) {
        if (!widget.isExpanded && !_isHovered) {
          setState(() => _isHovered = true);
        } else {
          _isHovered = true;
        }
      },
      onExit: (_) {
        if (!widget.isExpanded && _isHovered) {
          setState(() => _isHovered = false);
        } else {
          _isHovered = false;
        }
      },
      child: AnimatedContainer(
        duration: tokens.focus.hoverDuration,
        padding: widget.padding,
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(tokens.radii.card),
          border: Border.all(
            color: borderColor,
            width: tokens.radii.borderWidth,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _UiExpandableHeader(
              title: widget.title,
              leading: widget.leading,
              titleEditor: widget.titleEditor,
              isEditingTitle: widget.isEditingTitle,
              isExpanded: widget.isExpanded,
              isCompleted: widget.isCompleted,
              trailingActions: widget.trailingActions,
              onToggleExpand: widget.onToggleExpand,
              showFocusRing: _showFocusRing,
              toggleSemanticLabel: widget.toggleSemanticLabel,
              onFocusHighlightChanged: (focused) {
                if (_showFocusRing != focused) {
                  setState(() => _showFocusRing = focused);
                }
              },
            ),
            if (!widget.isExpanded && widget.collapsedMetadata != null)
              Padding(
                padding: EdgeInsets.only(
                  left: isCompact ? 0.0 : 36.0,
                  top: 6.0,
                ),
                child: widget.collapsedMetadata,
              ),
            AnimatedSize(
              duration: tokens.focus.expandDuration,
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: widget.isExpanded && widget.expandedChild != null
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10.0),
                      child: widget.expandedChild,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Header row inside [_UiExpandableCard] with `34x34px` leading slot, title/editor, and trailing actions.
class _UiExpandableHeader extends StatelessWidget {
  /// Creates a [_UiExpandableHeader].
  const _UiExpandableHeader({
    required this.title,
    required this.leading,
    required this.titleEditor,
    required this.isEditingTitle,
    required this.isExpanded,
    required this.isCompleted,
    required this.trailingActions,
    required this.onToggleExpand,
    required this.showFocusRing,
    required this.toggleSemanticLabel,
    required this.onFocusHighlightChanged,
  });

  /// Whether the entity is marked completed.
  final bool isCompleted;

  /// Whether [titleEditor] replaces the header toggle text.
  final bool isEditingTitle;

  /// Whether the card is currently expanded.
  final bool isExpanded;

  /// Optional `34x34px` leading widget.
  final Widget? leading;

  /// Focus-visible callback for the header toggle button.
  final ValueChanged<bool> onFocusHighlightChanged;

  /// Expand/collapse toggle callback.
  final VoidCallback? onToggleExpand;

  /// Whether to paint the `1px` `accent` focus ring around the title button.
  final bool showFocusRing;

  /// Entity title text.
  final String title;

  /// Optional inline title editor.
  final Widget? titleEditor;

  /// Explicit accessible label for header toggle.
  final String? toggleSemanticLabel;

  /// Right-aligned trailing actions.
  final List<Widget> trailingActions;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final titleStyle = tokens.typography.cardTitle.copyWith(
      color: isCompleted ? colors.muted : colors.ink,
      decoration: isCompleted ? TextDecoration.lineThrough : null,
      decorationColor: colors.muted,
    );

    Widget titleRegion;
    if (isEditingTitle && titleEditor != null) {
      titleRegion = titleEditor ?? const SizedBox.shrink();
    } else {
      final ringInset = tokens.focus.ringOffset + tokens.focus.ringWidth;
      final titleBox = Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: <Widget>[
          Container(
            constraints: const BoxConstraints(minHeight: 28.0),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Text(title, style: titleStyle),
          ),
          if (showFocusRing)
            Positioned.fill(
              left: -ringInset,
              top: -ringInset,
              right: -ringInset,
              bottom: -ringInset,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(tokens.radii.tag),
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
      titleRegion = Semantics(
        button: true,
        expanded: isExpanded,
        label: toggleSemanticLabel ?? title,
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowFocusHighlight: onFocusHighlightChanged,
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                onToggleExpand?.call();
                return null;
              },
            ),
            ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
              onInvoke: (_) {
                onToggleExpand?.call();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggleExpand,
            child: titleBox,
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (leading case final leadingWidget?) ...<Widget>[
          SizedBox(
            width: tokens.spacing.chromeControlHeight,
            height: tokens.spacing.chromeControlHeight,
            child: Center(child: leadingWidget),
          ),
          const SizedBox(width: 2.0),
        ],
        Expanded(child: titleRegion),
        if (trailingActions.isNotEmpty) ...<Widget>[
          const SizedBox(width: 6.0),
          Row(mainAxisSize: MainAxisSize.min, children: trailingActions),
        ],
      ],
    );
  }
}
