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

import 'package:material_ui/material_ui.dart';

import '../primitives/ui_button.dart';
import '../tokens/ui_breakpoints.dart';
import '../tokens/ui_theme_tokens.dart';

/// Docked Task Quick-Add (collapsible on compact + upward desktop `TapRegion` popover) and inline Quick-Create composer (`U-CARD-006`, `U-COMP-004`).
class UiQuickComposer extends StatefulWidget {
  /// Creates a [UiQuickComposer].
  const UiQuickComposer({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.submitLabel,
    required this.onSubmit,
    this.focusNode,
    this.maxLength = 300,
    this.expandDraftLabel,
    this.onExpandDraft,
    this.isCollapsibleOnCompact = true,
    this.isCompactExpanded,
    this.onCompactExpandedChanged,
    this.compactTriggerLabel,
    this.compactCloseTooltip,
    this.modeWidget,
    this.modeHint,
    this.draftChips,
    this.popoverContent,
    this.isPopoverOpen = false,
    this.onDismissPopover,
    this.enabled = true,
  });

  /// Tooltip for the compact expanded composer close `x` button.
  final String? compactCloseTooltip;

  /// Label for the compact collapsed full-width primary button (e.g. `+ New task`).
  final String? compactTriggerLabel;

  /// Caller-owned title text editing controller.
  final TextEditingController controller;

  /// Optional draft label chips + picker trigger bar rendered below the title input.
  final Widget? draftChips;

  /// Whether inputs and actions are enabled.
  final bool enabled;

  /// Optional secondary action copy (e.g. `Open as draft`).
  final String? expandDraftLabel;

  /// Optional caller-owned focus node for the title input.
  final FocusNode? focusNode;

  /// Whether compact (`<= 720px`) viewports collapse this composer to [compactTriggerLabel].
  final bool isCollapsibleOnCompact;

  /// Optional controlled expanded state on compact viewports; falls back to internal state when `null`.
  final bool? isCompactExpanded;

  /// Whether the desktop upward popover is currently open.
  final bool isPopoverOpen;

  /// Maximum character limit (`300` tasks, `120` labels/locations).
  final int maxLength;

  /// Optional subtle helper caption describing the active placement mode.
  final String? modeHint;

  /// Optional placement mode selector widget (`Queue` / `Priority` / `Someday`).
  final Widget? modeWidget;

  /// Callback notifying compact collapse/expand state changes.
  final ValueChanged<bool>? onCompactExpandedChanged;

  /// Callback dismissing the upward desktop popover on outside pointer clicks.
  final VoidCallback? onDismissPopover;

  /// Callback opening the uncommitted draft card.
  final VoidCallback? onExpandDraft;

  /// Primary submission callback (`+ Add` or `Enter`).
  final VoidCallback? onSubmit;

  /// Title input placeholder copy.
  final String placeholder;

  /// Optional desktop popover content anchored `8px` above the composer.
  final Widget? popoverContent;

  /// Primary submission button copy (e.g. `+ Add`).
  final String submitLabel;

  @override
  State<UiQuickComposer> createState() => _UiQuickComposerState();
}

/// Manages focus-within border highlighting, compact collapse toggle, and `OverlayPortal` popover anchoring for [UiQuickComposer].
class _UiQuickComposerState extends State<UiQuickComposer> {
  /// Layer link connecting the composer frame to the upward popover follower.
  final LayerLink _layerLink = LayerLink();

  /// Overlay controller synchronized with `widget.isPopoverOpen`.
  final OverlayPortalController _overlayController = OverlayPortalController();

  /// Shared `TapRegion` group ID keeping clicks inside composer and popover from dismissing.
  final Object _tapRegionGroupId = Object();

  /// Internal focus node created only when `widget.focusNode == null`.
  FocusNode? _ownedFocusNode;

  /// Internal compact expanded flag used when `widget.isCompactExpanded == null`.
  bool _internalCompactExpanded = false;

  /// Whether any control inside the composer form holds focus.
  bool _hasFocusWithin = false;

  /// Active title focus node.
  FocusNode get _focusNode {
    if (widget.focusNode case final external?) {
      return external;
    }
    return _ownedFocusNode ??= FocusNode();
  }

  /// Effective compact expanded state.
  bool get _isCompactExpanded =>
      widget.isCompactExpanded ?? _internalCompactExpanded;

  @override
  void initState() {
    super.initState();
    _syncOverlayVisibility();
  }

  @override
  void didUpdateWidget(covariant UiQuickComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode &&
        widget.focusNode != null &&
        _ownedFocusNode != null) {
      _ownedFocusNode?.dispose();
      _ownedFocusNode = null;
    }
    if (oldWidget.isPopoverOpen != widget.isPopoverOpen ||
        oldWidget.popoverContent != widget.popoverContent) {
      _syncOverlayVisibility();
    }
  }

  @override
  void dispose() {
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isCompact = UiBreakpoints.isCompact(viewportWidth);

    if (isCompact && widget.isCollapsibleOnCompact && !_isCompactExpanded) {
      return UiButton(
        label: widget.compactTriggerLabel ?? widget.submitLabel,
        leadingIcon: Icons.add_rounded,
        variant: UiButtonVariant.primary,
        isFullWidth: true,
        onPressed: widget.enabled ? () => _setCompactExpanded(true) : null,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : viewportWidth;
        final popoverWidth = math.min(460.0, availableWidth);
        final card = _buildComposerCard(tokens, isCompact: isCompact);

        return TapRegion(
          groupId: _tapRegionGroupId,
          child: CompositedTransformTarget(
            link: _layerLink,
            child: OverlayPortal(
              controller: _overlayController,
              overlayChildBuilder: (overlayContext) {
                return _UiComposerPopoverOverlay(
                  layerLink: _layerLink,
                  tapRegionGroupId: _tapRegionGroupId,
                  width: popoverWidth,
                  onDismiss: widget.onDismissPopover,
                  child: widget.popoverContent ?? const SizedBox.shrink(),
                );
              },
              child: card,
            ),
          ),
        );
      },
    );
  }

  /// Builds the flat bordered composer card adapting between desktop horizontal and compact stacked layouts.
  Widget _buildComposerCard(UiThemeTokens tokens, {required bool isCompact}) {
    final colors = tokens.colors;
    final hasFooter =
        widget.draftChips != null || (widget.modeHint != null && !isCompact);

    return Focus(
      canRequestFocus: false,
      onFocusChange: (focused) {
        if (_hasFocusWithin != focused) {
          setState(() => _hasFocusWithin = focused);
        }
      },
      child: AnimatedContainer(
        duration: tokens.focus.hoverDuration,
        padding: EdgeInsets.symmetric(
          horizontal: 12.0,
          vertical: isCompact ? 10.0 : 8.0,
        ),
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(tokens.radii.card),
          border: Border.all(
            color: _hasFocusWithin ? colors.accent : colors.line,
            width: tokens.radii.borderWidth,
          ),
        ),
        child: isCompact
            ? _buildCompactBody(tokens)
            : _buildDesktopBody(tokens, hasFooter: hasFooter),
      ),
    );
  }

  /// Builds compact stacked composer layout with `16px` title field and close button.
  Widget _buildCompactBody(UiThemeTokens tokens) {
    final colors = tokens.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _buildTitleTextField(
                tokens,
                style: tokens.typography.compactBrand.copyWith(
                  color: colors.ink,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            if (widget.isCollapsibleOnCompact)
              UiButton(
                leadingIcon: Icons.close_rounded,
                variant: UiButtonVariant.icon,
                density: UiButtonDensity.dense,
                tooltip: widget.compactCloseTooltip,
                onPressed: () => _setCompactExpanded(false),
              ),
          ],
        ),
        if (widget.modeWidget case final mode?) ...<Widget>[
          const SizedBox(height: 8.0),
          mode,
        ],
        if (widget.modeHint case final hint?) ...<Widget>[
          const SizedBox(height: 4.0),
          Text(
            hint,
            style: tokens.typography.eyebrow.copyWith(
              color: colors.muted,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.0,
            ),
          ),
        ],
        if (widget.draftChips case final chips?) ...<Widget>[
          const SizedBox(height: 8.0),
          chips,
        ],
        const SizedBox(height: 8.0),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            if (widget.expandDraftLabel case final draftLabel?) ...<Widget>[
              UiButton(
                label: draftLabel,
                variant: UiButtonVariant.secondary,
                density: UiButtonDensity.compact,
                onPressed: widget.enabled ? widget.onExpandDraft : null,
              ),
              const SizedBox(width: 8.0),
            ],
            UiButton(
              label: widget.submitLabel,
              variant: UiButtonVariant.primary,
              density: UiButtonDensity.compact,
              onPressed: widget.enabled ? widget.onSubmit : null,
            ),
          ],
        ),
      ],
    );
  }

  /// Builds desktop single-line composer row plus optional draft-chips and mode-hint footer.
  Widget _buildDesktopBody(UiThemeTokens tokens, {required bool hasFooter}) {
    final colors = tokens.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _buildTitleTextField(
                tokens,
                style: tokens.typography.body.copyWith(color: colors.ink),
              ),
            ),
            if (widget.modeWidget case final mode?) ...<Widget>[
              const SizedBox(width: 8.0),
              mode,
            ],
            if (widget.expandDraftLabel case final draftLabel?) ...<Widget>[
              const SizedBox(width: 8.0),
              UiButton(
                label: draftLabel,
                variant: UiButtonVariant.secondary,
                density: UiButtonDensity.compact,
                onPressed: widget.enabled ? widget.onExpandDraft : null,
              ),
            ],
            const SizedBox(width: 8.0),
            UiButton(
              label: widget.submitLabel,
              variant: UiButtonVariant.primary,
              density: UiButtonDensity.compact,
              onPressed: widget.enabled ? widget.onSubmit : null,
            ),
          ],
        ),
        if (hasFooter) ...<Widget>[
          const SizedBox(height: 8.0),
          Row(
            children: <Widget>[
              if (widget.draftChips case final chips?)
                Expanded(child: chips)
              else
                const Spacer(),
              if (widget.modeHint case final hint?) ...<Widget>[
                const SizedBox(width: 10.0),
                Text(
                  hint,
                  style: tokens.typography.eyebrow.copyWith(
                    color: colors.muted,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.0,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  /// Builds the borderless inner [TextField] submitting on `Enter`.
  Widget _buildTitleTextField(
    UiThemeTokens tokens, {
    required TextStyle style,
  }) {
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      maxLength: widget.maxLength,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) {
        if (widget.enabled) {
          widget.onSubmit?.call();
        }
      },
      style: style,
      decoration: InputDecoration(
        filled: false,
        isDense: true,
        counterText: '',
        hintText: widget.placeholder,
        hintStyle: style.copyWith(color: tokens.colors.muted),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 4.0,
          vertical: 6.0,
        ),
      ),
    );
  }

  /// Updates compact expanded state and focuses title input when opening.
  void _setCompactExpanded(bool expanded) {
    if (widget.isCompactExpanded == null) {
      setState(() => _internalCompactExpanded = expanded);
    }
    widget.onCompactExpandedChanged?.call(expanded);
    if (expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  /// Synchronizes [OverlayPortalController] after frame build so overlay toggles safely.
  void _syncOverlayVisibility() {
    final shouldShow = widget.isPopoverOpen && widget.popoverContent != null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (shouldShow && !_overlayController.isShowing) {
        _overlayController.show();
      } else if (!shouldShow && _overlayController.isShowing) {
        _overlayController.hide();
      }
    });
  }
}

/// Upward-anchored desktop popover card using non-swallowing `TapRegion` outside-tap dismissal (`U-COMP-004`).
class _UiComposerPopoverOverlay extends StatelessWidget {
  /// Creates a [_UiComposerPopoverOverlay].
  const _UiComposerPopoverOverlay({
    required this.layerLink,
    required this.tapRegionGroupId,
    required this.width,
    required this.onDismiss,
    required this.child,
  });

  /// Popover interior content (e.g. `UiSearchablePicker`).
  final Widget child;

  /// Link anchored to the composer box.
  final LayerLink layerLink;

  /// Outside-tap dismissal callback.
  final VoidCallback? onDismiss;

  /// Shared `TapRegion` group identifier.
  final Object tapRegionGroupId;

  /// Clamped popover width (`min(460px, availableWidth)`).
  final double width;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return Positioned(
      width: width,
      child: CompositedTransformFollower(
        link: layerLink,
        showWhenUnlinked: false,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        offset: const Offset(0.0, -8.0),
        child: TapRegion(
          groupId: tapRegionGroupId,
          onTapOutside: (_) => onDismiss?.call(),
          child: Material(
            type: MaterialType.transparency,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.panel,
                borderRadius: BorderRadius.circular(tokens.radii.card),
                border: Border.all(
                  color: colors.line,
                  width: tokens.radii.borderWidth,
                ),
                boxShadow: tokens.focus.popoverShadow,
              ),
              child: Padding(padding: const EdgeInsets.all(12.0), child: child),
            ),
          ),
        ),
      ),
    );
  }
}
