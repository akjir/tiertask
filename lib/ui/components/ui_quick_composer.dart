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
    this.submitLeadingIcon = Icons.add_rounded,
    this.expandDraftIcon = Icons.tune_rounded,
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
    this.stackModeWidget = false,
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

  /// Optional draft label chips + picker trigger bar rendered below the divider.
  final Widget? draftChips;

  /// Whether inputs and actions are enabled.
  final bool enabled;

  /// Optional leading outline icon for the borderless `Open as draft` text button.
  final IconData? expandDraftIcon;

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

  /// Maximum character limit (`500` canonical `maxTdfTextLength`).
  final int maxLength;

  /// Optional subtle helper caption rendered outside and below the bordered composer card.
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

  /// Optional desktop popover content anchored `8px` above the composer card.
  final Widget? popoverContent;

  /// Places [modeWidget] on a full-width row inside the desktop card above the footer divider.
  final bool stackModeWidget;

  /// Primary submission button copy (e.g. `Add`).
  final String submitLabel;

  /// Optional leading outline icon for the primary submission button (`Icons.add_rounded` default).
  final IconData? submitLeadingIcon;

  @override
  State<UiQuickComposer> createState() => _UiQuickComposerState();
}

/// Manages focus-within border highlighting, compact collapse toggle, and `OverlayPortal` popover anchoring for [UiQuickComposer].
class _UiQuickComposerState extends State<UiQuickComposer> {
  /// Layer link connecting the bordered composer card to the upward popover follower.
  final LayerLink _layerLink = LayerLink();

  /// Overlay controller synchronized with `widget.isPopoverOpen`.
  final OverlayPortalController _overlayController = OverlayPortalController();

  /// Shared `TapRegion` group ID keeping clicks inside composer and popover from dismissing.
  final Object _tapRegionGroupId = Object();

  /// Whether any control inside the composer form holds focus.
  bool _hasFocusWithin = false;

  /// Internal compact expanded flag used when `widget.isCompactExpanded == null`.
  bool _internalCompactExpanded = false;

  /// Internal focus node created only when `widget.focusNode == null`.
  FocusNode? _ownedFocusNode;

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
    final wasShowing =
        oldWidget.isPopoverOpen && oldWidget.popoverContent != null;
    final shouldShow = widget.isPopoverOpen && widget.popoverContent != null;
    if (wasShowing != shouldShow) {
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
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isCompact = UiBreakpoints.isCompact(viewportWidth);

    if (isCompact && widget.isCollapsibleOnCompact && !_isCompactExpanded) {
      return UiButton(
        label: widget.compactTriggerLabel ?? widget.submitLabel,
        leadingIcon: widget.submitLeadingIcon,
        variant: UiButtonVariant.primary,
        isFullWidth: true,
        onPressed: widget.enabled ? () => _setCompactExpanded(true) : null,
      );
    }

    final config = _buildConfig();
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : viewportWidth;
        return _UiQuickComposerRegion(
          layerLink: _layerLink,
          overlayController: _overlayController,
          tapRegionGroupId: _tapRegionGroupId,
          popoverWidth: math.min(460.0, availableWidth),
          popoverContent: widget.popoverContent,
          onDismissPopover: widget.onDismissPopover,
          modeHint: widget.modeHint,
          card: _UiQuickComposerCard(
            key: const ValueKey<String>('ui_quick_composer_card'),
            hasFocusWithin: _hasFocusWithin,
            isCompact: isCompact,
            onFocusWithinChanged: _handleFocusWithinChanged,
            child: isCompact
                ? _UiQuickComposerCompactBody(
                    config: config,
                    isCollapsibleOnCompact: widget.isCollapsibleOnCompact,
                    compactCloseTooltip: widget.compactCloseTooltip,
                    onCloseCompact: () => _setCompactExpanded(false),
                  )
                : _UiQuickComposerDesktopBody(config: config),
          ),
        );
      },
    );
  }

  /// Packages immutable widget parameters into a shared [_UiComposerConfig].
  _UiComposerConfig _buildConfig() {
    return _UiComposerConfig(
      controller: widget.controller,
      focusNode: _focusNode,
      placeholder: widget.placeholder,
      maxLength: widget.maxLength,
      enabled: widget.enabled,
      modeWidget: widget.modeWidget,
      stackModeWidget: widget.stackModeWidget,
      draftChips: widget.draftChips,
      expandDraftLabel: widget.expandDraftLabel,
      expandDraftIcon: widget.expandDraftIcon,
      submitLabel: widget.submitLabel,
      submitLeadingIcon: widget.submitLeadingIcon,
      onExpandDraft: widget.onExpandDraft,
      onSubmit: widget.onSubmit,
    );
  }

  /// Updates focus-within border highlight state when descendant focus changes.
  void _handleFocusWithinChanged(bool focused) {
    if (_hasFocusWithin != focused) {
      setState(() => _hasFocusWithin = focused);
    }
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final shouldShow = widget.isPopoverOpen && widget.popoverContent != null;
      if (shouldShow && !_overlayController.isShowing) {
        _overlayController.show();
      } else if (!shouldShow && _overlayController.isShowing) {
        _overlayController.hide();
      }
    });
  }
}

/// Immutable bundle of composer inputs, optional slots, and submission callbacks.
@immutable
class _UiComposerConfig {
  /// Creates a [_UiComposerConfig].
  const _UiComposerConfig({
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    required this.maxLength,
    required this.enabled,
    required this.modeWidget,
    required this.stackModeWidget,
    required this.draftChips,
    required this.expandDraftLabel,
    required this.expandDraftIcon,
    required this.submitLabel,
    required this.submitLeadingIcon,
    required this.onExpandDraft,
    required this.onSubmit,
  });

  /// Title text controller.
  final TextEditingController controller;

  /// Optional draft label chips bar.
  final Widget? draftChips;

  /// Whether controls accept input.
  final bool enabled;

  /// Leading icon for `Open as draft`.
  final IconData? expandDraftIcon;

  /// Optional copy for `Open as draft`.
  final String? expandDraftLabel;

  /// Focus node for title input.
  final FocusNode focusNode;

  /// Maximum character limit.
  final int maxLength;

  /// Optional placement selector widget.
  final Widget? modeWidget;

  /// Callback opening uncommitted draft card.
  final VoidCallback? onExpandDraft;

  /// Submission callback.
  final VoidCallback? onSubmit;

  /// Title input hint copy.
  final String placeholder;

  /// Whether desktop stacks [modeWidget] onto a full-width row above the divider.
  final bool stackModeWidget;

  /// Primary submit button copy.
  final String submitLabel;

  /// Leading icon for primary submit button.
  final IconData? submitLeadingIcon;
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

  /// Link anchored to the bordered composer card.
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

/// Flat bordered composer card highlighting its `1px` border to `accent` on focus-within (`U-A11Y-001`).
class _UiQuickComposerCard extends StatelessWidget {
  /// Creates a [_UiQuickComposerCard].
  const _UiQuickComposerCard({
    super.key,
    required this.hasFocusWithin,
    required this.isCompact,
    required this.onFocusWithinChanged,
    required this.child,
  });

  /// Card interior content.
  final Widget child;

  /// Whether any focusable child inside the card currently holds focus.
  final bool hasFocusWithin;

  /// Whether viewport is in compact breakpoint class (`<= 720`).
  final bool isCompact;

  /// Callback notified when focus-within state transitions.
  final ValueChanged<bool> onFocusWithinChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return Focus(
      canRequestFocus: false,
      onFocusChange: onFocusWithinChanged,
      child: AnimatedContainer(
        duration: tokens.focus.hoverDuration,
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 12.0 : 13.0,
          vertical: isCompact ? 10.0 : 12.0,
        ),
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(tokens.radii.card),
          border: Border.all(
            color: hasFocusWithin ? colors.accent : colors.line,
            width: tokens.radii.borderWidth,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Compact composer action bar pairing borderless `Open as draft` with the `40px` primary submit button.
class _UiQuickComposerCompactActions extends StatelessWidget {
  /// Creates a [_UiQuickComposerCompactActions].
  const _UiQuickComposerCompactActions({required this.config});

  /// Composer configuration bundle.
  final _UiComposerConfig config;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        if (config.expandDraftLabel case final draftLabel?)
          UiButton(
            label: draftLabel,
            leadingIcon: config.expandDraftIcon,
            variant: UiButtonVariant.text,
            density: UiButtonDensity.dense,
            onPressed: config.enabled ? config.onExpandDraft : null,
          ),
        const Spacer(),
        UiButton(
          label: config.submitLabel,
          leadingIcon: config.submitLeadingIcon,
          variant: UiButtonVariant.primary,
          density: UiButtonDensity.standard,
          onPressed: config.enabled ? config.onSubmit : null,
        ),
      ],
    );
  }
}

/// Compact stacked composer body with `16px` title field, divider-separated chips, and `40px` primary submit button.
class _UiQuickComposerCompactBody extends StatelessWidget {
  /// Creates a [_UiQuickComposerCompactBody].
  const _UiQuickComposerCompactBody({
    required this.config,
    required this.isCollapsibleOnCompact,
    required this.compactCloseTooltip,
    required this.onCloseCompact,
  });

  /// Tooltip for the compact close button.
  final String? compactCloseTooltip;

  /// Composer configuration bundle.
  final _UiComposerConfig config;

  /// Whether compact close button is rendered.
  final bool isCollapsibleOnCompact;

  /// Callback collapsing compact composer.
  final VoidCallback onCloseCompact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _UiQuickComposerCompactTopRow(
          config: config,
          isCollapsibleOnCompact: isCollapsibleOnCompact,
          compactCloseTooltip: compactCloseTooltip,
          onCloseCompact: onCloseCompact,
        ),
        if (config.modeWidget case final mode?) ...<Widget>[
          const SizedBox(height: 8.0),
          mode,
        ],
        if (config.draftChips case final chips?)
          _UiQuickComposerFooterDivider(child: chips),
        const SizedBox(height: 8.0),
        _UiQuickComposerCompactActions(config: config),
      ],
    );
  }
}

/// Compact top input row pairing the `16px` title field with an optional close button.
class _UiQuickComposerCompactTopRow extends StatelessWidget {
  /// Creates a [_UiQuickComposerCompactTopRow].
  const _UiQuickComposerCompactTopRow({
    required this.config,
    required this.isCollapsibleOnCompact,
    required this.compactCloseTooltip,
    required this.onCloseCompact,
  });

  /// Tooltip for the compact close button.
  final String? compactCloseTooltip;

  /// Composer configuration bundle.
  final _UiComposerConfig config;

  /// Whether compact close button is rendered.
  final bool isCollapsibleOnCompact;

  /// Callback collapsing compact composer.
  final VoidCallback onCloseCompact;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: _UiQuickComposerTitleField(
            config: config,
            style: tokens.typography.compactBrand.copyWith(
              color: tokens.colors.ink,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        if (isCollapsibleOnCompact)
          UiButton(
            leadingIcon: Icons.close_rounded,
            variant: UiButtonVariant.icon,
            density: UiButtonDensity.dense,
            tooltip: compactCloseTooltip,
            onPressed: onCloseCompact,
          ),
      ],
    );
  }
}

/// Desktop composer body pairing the top input row, optional stacked mode row, and divider footer bar.
class _UiQuickComposerDesktopBody extends StatelessWidget {
  /// Creates a [_UiQuickComposerDesktopBody].
  const _UiQuickComposerDesktopBody({required this.config});

  /// Composer configuration bundle.
  final _UiComposerConfig config;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _UiQuickComposerDesktopTopRow(config: config),
        if (config.modeWidget case final mode?
            when config.stackModeWidget) ...<Widget>[
          const SizedBox(height: 8.0),
          mode,
        ],
        if (config.draftChips case final chips?)
          _UiQuickComposerFooterDivider(
            child: _UiQuickComposerDesktopFooterRow(
              chips: chips,
              config: config,
            ),
          ),
      ],
    );
  }
}

/// Desktop footer bar pairing draft label chips on the left with borderless `Open as draft` on the right.
class _UiQuickComposerDesktopFooterRow extends StatelessWidget {
  /// Creates a [_UiQuickComposerDesktopFooterRow].
  const _UiQuickComposerDesktopFooterRow({
    required this.chips,
    required this.config,
  });

  /// Draft label chips and `+ Labels` trigger bar.
  final Widget chips;

  /// Composer configuration bundle.
  final _UiComposerConfig config;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(child: chips),
        if (config.expandDraftLabel case final draftLabel?) ...<Widget>[
          const SizedBox(width: 12.0),
          UiButton(
            label: draftLabel,
            leadingIcon: config.expandDraftIcon,
            variant: UiButtonVariant.text,
            density: UiButtonDensity.dense,
            onPressed: config.enabled ? config.onExpandDraft : null,
          ),
        ],
      ],
    );
  }
}

/// Desktop top input row pairing the `15px` title field, optional inline mode control, and `40px` primary submit button.
class _UiQuickComposerDesktopTopRow extends StatelessWidget {
  /// Creates a [_UiQuickComposerDesktopTopRow].
  const _UiQuickComposerDesktopTopRow({required this.config});

  /// Composer configuration bundle.
  final _UiComposerConfig config;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final showInlineDraftAction =
        config.draftChips == null && config.expandDraftLabel != null;

    return Row(
      children: <Widget>[
        Expanded(
          child: _UiQuickComposerTitleField(
            config: config,
            style: tokens.typography.cardTitle.copyWith(
              color: tokens.colors.ink,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        if (config.modeWidget case final mode?
            when !config.stackModeWidget) ...<Widget>[
          const SizedBox(width: 10.0),
          mode,
        ],
        if (showInlineDraftAction) ...<Widget>[
          const SizedBox(width: 8.0),
          UiButton(
            label: config.expandDraftLabel,
            leadingIcon: config.expandDraftIcon,
            variant: UiButtonVariant.text,
            density: UiButtonDensity.dense,
            onPressed: config.enabled ? config.onExpandDraft : null,
          ),
        ],
        const SizedBox(width: 8.0),
        UiButton(
          label: config.submitLabel,
          leadingIcon: config.submitLeadingIcon,
          variant: UiButtonVariant.primary,
          density: UiButtonDensity.standard,
          onPressed: config.enabled ? config.onSubmit : null,
        ),
      ],
    );
  }
}

/// Top hairline divider container separating the composer input row from the footer bar.
class _UiQuickComposerFooterDivider extends StatelessWidget {
  /// Creates a [_UiQuickComposerFooterDivider].
  const _UiQuickComposerFooterDivider({required this.child});

  /// Footer bar content rendered beneath the hairline divider.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8.0),
      padding: const EdgeInsets.only(top: 8.0),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: tokens.colors.line,
            width: tokens.radii.borderWidth,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Muted helper caption rendered strictly outside and below the bordered composer card (`.composer-hint`).
class _UiQuickComposerModeHint extends StatelessWidget {
  /// Creates a [_UiQuickComposerModeHint].
  const _UiQuickComposerModeHint({required this.hint});

  /// Localized helper text describing active placement.
  final String hint;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 7.0, left: 3.0, right: 3.0),
      child: Text(
        hint,
        style: tokens.typography.eyebrow.copyWith(
          color: tokens.colors.muted,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.0,
        ),
      ),
    );
  }
}

/// Anchors the bordered composer card to the upward popover portal and renders optional [modeHint] beneath it.
class _UiQuickComposerRegion extends StatelessWidget {
  /// Creates a [_UiQuickComposerRegion].
  const _UiQuickComposerRegion({
    required this.layerLink,
    required this.overlayController,
    required this.tapRegionGroupId,
    required this.popoverWidth,
    required this.popoverContent,
    required this.onDismissPopover,
    required this.card,
    required this.modeHint,
  });

  /// Bordered composer card surface.
  final Widget card;

  /// Link anchoring the popover to [card].
  final LayerLink layerLink;

  /// Optional helper caption displayed strictly below [card].
  final String? modeHint;

  /// Callback dismissing the popover on outside taps.
  final VoidCallback? onDismissPopover;

  /// Overlay portal controller managing popover visibility.
  final OverlayPortalController overlayController;

  /// Optional upward desktop popover body.
  final Widget? popoverContent;

  /// Clamped popover width.
  final double popoverWidth;

  /// Shared `TapRegion` group identifier.
  final Object tapRegionGroupId;

  @override
  Widget build(BuildContext context) {
    final anchoredCard = TapRegion(
      groupId: tapRegionGroupId,
      child: CompositedTransformTarget(
        link: layerLink,
        child: OverlayPortal(
          controller: overlayController,
          overlayChildBuilder: (overlayContext) {
            return _UiComposerPopoverOverlay(
              layerLink: layerLink,
              tapRegionGroupId: tapRegionGroupId,
              width: popoverWidth,
              onDismiss: onDismissPopover,
              child: popoverContent ?? const SizedBox.shrink(),
            );
          },
          child: card,
        ),
      ),
    );

    if (modeHint case final hint?) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          anchoredCard,
          _UiQuickComposerModeHint(hint: hint),
        ],
      );
    }
    return anchoredCard;
  }
}

/// Borderless inner [TextField] inside [UiQuickComposer] submitting on `Enter`.
class _UiQuickComposerTitleField extends StatelessWidget {
  /// Creates a [_UiQuickComposerTitleField].
  const _UiQuickComposerTitleField({required this.config, required this.style});

  /// Composer configuration bundle.
  final _UiComposerConfig config;

  /// Input text style.
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    return TextField(
      controller: config.controller,
      focusNode: config.focusNode,
      enabled: config.enabled,
      maxLength: config.maxLength,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) {
        if (config.enabled) {
          config.onSubmit?.call();
        }
      },
      style: style,
      decoration: InputDecoration(
        filled: false,
        isDense: true,
        counterText: '',
        hintText: config.placeholder,
        hintStyle: style.copyWith(color: tokens.colors.muted),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 4.0,
          vertical: 8.0,
        ),
      ),
    );
  }
}
