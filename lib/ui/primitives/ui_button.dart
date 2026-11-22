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

import '../tokens/ui_theme_tokens.dart';

/// Semantic button presentation style (`U-COMP-002`).
enum UiButtonVariant {
  /// High-emphasis accent filled action button.
  primary,

  /// Flat `panel` bordered secondary action or chrome pill button.
  secondary,

  /// Borderless accent text link button.
  text,

  /// Danger-bordered destructive action button.
  danger,

  /// Square borderless icon-only action button.
  icon,
}

/// Canonical height density ladder mapped directly from `UiSpacingTokens` (`U-TOKEN-003`).
enum UiButtonDensity {
  /// Desktop primary hit target (`40px`).
  standard,

  /// Top chrome workspace and sync controls (`34px`).
  chrome,

  /// Compact card and dialog footer buttons (`32px`).
  compact,

  /// Dense text buttons and inline icon triggers (`30px`).
  dense,

  /// Compact/mobile primary hit target (`44px`).
  mobileTouch,

  /// Desktop sidebar section header icon target (`26px`).
  sidebarDesktop,
}

/// Optional semantic accent or status tint for [UiButton].
enum UiButtonTone {
  /// Default variant tinting.
  neutral,

  /// Muted low-emphasis foreground on bordered secondary or chrome buttons.
  muted,

  /// Accent-tinted foreground and active border.
  accent,

  /// Warning-tinted surface and foreground (e.g. conflict sync status).
  warning,

  /// Danger-tinted surface and foreground (e.g. error sync status).
  danger,
}

/// Flat border-delimited interactive button primitive supporting all TierTask densities and states.
class UiButton extends StatefulWidget {
  /// Creates a [UiButton].
  const UiButton({
    super.key,
    this.label,
    this.leadingIcon,
    this.trailingIcon,
    required this.onPressed,
    this.variant = UiButtonVariant.secondary,
    this.density = UiButtonDensity.standard,
    this.tone = UiButtonTone.neutral,
    this.tooltip,
    this.semanticLabel,
    this.isLoading = false,
    this.isActive = false,
    this.isDangerHover = false,
    this.isFullWidth = false,
    this.focusNode,
    this.autofocus = false,
    this.borderRadius,
  });

  /// Whether this button requests initial keyboard focus.
  final bool autofocus;

  /// Optional explicit corner radius overriding the variant default.
  final double? borderRadius;

  /// Control height density.
  final UiButtonDensity density;

  /// Optional caller-managed [FocusNode].
  final FocusNode? focusNode;

  /// Renders the button in active `soft`/`accent` state (e.g. toggled filter/manage icons).
  final bool isActive;

  /// Applies danger hover tinting (`dangerBg`/`danger`) on icon buttons.
  final bool isDangerHover;

  /// Expands the button horizontally to fill parent width.
  final bool isFullWidth;

  /// Rotates the leading/primary icon continuously at `tokens.focus.spinDuration`.
  final bool isLoading;

  /// Optional caller-supplied visible text label.
  final String? label;

  /// Optional leading (or primary icon-button) glyph.
  final IconData? leadingIcon;

  /// Tap/activation callback; `null` renders disabled at `0.48` opacity.
  final VoidCallback? onPressed;

  /// Explicit accessible name overriding [tooltip] and [label].
  final String? semanticLabel;

  /// Optional semantic status tint.
  final UiButtonTone tone;

  /// Optional tooltip displayed on pointer hover or long-press.
  final String? tooltip;

  /// Optional trailing glyph (e.g. workspace switcher chevron).
  final IconData? trailingIcon;

  /// Visual button variant.
  final UiButtonVariant variant;

  @override
  State<UiButton> createState() => _UiButtonState();
}

/// Manages pointer hover and keyboard focus-ring state for [UiButton] without holding an idle ticker.
class _UiButtonState extends State<UiButton> {
  /// Whether pointer hover highlight is currently active.
  bool _isHovered = false;

  /// Whether keyboard focus ring is currently visible.
  bool _showFocusRing = false;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final surfaceLevel = UiSurfaceScope.of(context);
    final enabled = widget.onPressed != null;
    final height = _resolveHeight(tokens);
    final radius = widget.borderRadius ?? _resolveRadius(tokens);
    final style = _resolveColors(
      tokens,
      surfaceLevel: surfaceLevel,
      enabled: enabled,
    );
    final content = _UiButtonSurface(
      enabled: enabled,
      height: height,
      minWidth: widget.variant == UiButtonVariant.icon ? height : 0.0,
      padding: _resolvePadding(tokens),
      radius: radius,
      backgroundColor: style.background,
      borderColor: style.border,
      showFocusRing: _showFocusRing && enabled,
      isFullWidth: widget.isFullWidth,
      child: _UiButtonContent(
        label: widget.label,
        leadingIcon: widget.leadingIcon,
        trailingIcon: widget.trailingIcon,
        foregroundColor: style.foreground,
        iconSize: _resolveIconSize(tokens),
        textStyle: _resolveTextStyle(tokens, style.foreground),
        isLoading: widget.isLoading,
      ),
    );

    final interactive = FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: enabled,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.forbidden,
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
            widget.onPressed?.call();
            return null;
          },
        ),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: !enabled,
        onTap: enabled ? widget.onPressed : _ignoreDisabledButtonTap,
        child: Opacity(
          opacity: enabled ? 1.0 : tokens.focus.disabledOpacity,
          child: content,
        ),
      ),
    );

    final accessible = Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.tooltip ?? widget.label,
      child: interactive,
    );
    if (widget.tooltip case final tip?) {
      return Tooltip(message: tip, child: accessible);
    }
    return accessible;
  }

  /// Resolves foreground, background, and border colors for the current state.
  _UiButtonPalette _resolveColors(
    UiThemeTokens tokens, {
    required UiSurfaceLevel surfaceLevel,
    required bool enabled,
  }) {
    final colors = tokens.colors;
    final hovered = _isHovered && enabled;
    if (widget.isActive) {
      return _UiButtonPalette(
        background: colors.soft,
        border: colors.accent,
        foreground: colors.accent,
      );
    }
    if (widget.tone == UiButtonTone.warning) {
      return _UiButtonPalette(
        background: colors.warningBg,
        border: colors.warningBorder,
        foreground: colors.warning,
      );
    }
    if (widget.tone == UiButtonTone.danger) {
      return _UiButtonPalette(
        background: colors.dangerBg,
        border: hovered ? colors.danger : colors.dangerBorder,
        foreground: colors.danger,
      );
    }
    final usesChromeInsetFill =
        widget.density == UiButtonDensity.chrome &&
        surfaceLevel != UiSurfaceLevel.insetWell;
    return switch (widget.variant) {
      UiButtonVariant.primary => _UiButtonPalette(
        background: colors.accent,
        border: Colors.transparent,
        foreground: colors.onAccent,
      ),
      UiButtonVariant.secondary => _UiButtonPalette(
        background: hovered
            ? colors.soft
            : (usesChromeInsetFill ? colors.bg : colors.panel),
        border: hovered
            ? colors.accent
            : (widget.tone == UiButtonTone.accent
                  ? colors.accent
                  : colors.line),
        foreground: hovered || widget.tone == UiButtonTone.accent
            ? colors.accent
            : (widget.tone == UiButtonTone.muted ? colors.muted : colors.ink),
      ),
      UiButtonVariant.text => _UiButtonPalette(
        background: hovered ? colors.soft : Colors.transparent,
        border: Colors.transparent,
        foreground: colors.accent,
      ),
      UiButtonVariant.danger => _UiButtonPalette(
        background: hovered ? colors.dangerBg : Colors.transparent,
        border: colors.dangerBorder,
        foreground: colors.danger,
      ),
      UiButtonVariant.icon => _UiButtonPalette(
        background: hovered
            ? (widget.isDangerHover ? colors.dangerBg : colors.soft)
            : Colors.transparent,
        border: Colors.transparent,
        foreground: hovered
            ? (widget.isDangerHover ? colors.danger : colors.accent)
            : (widget.tone == UiButtonTone.accent
                  ? colors.accent
                  : colors.muted),
      ),
    };
  }

  /// Resolves label font weight matching variant and semantic tone.
  FontWeight _resolveFontWeight() {
    if (widget.variant == UiButtonVariant.primary ||
        widget.tone == UiButtonTone.warning ||
        widget.tone == UiButtonTone.danger) {
      return FontWeight.w600;
    }
    if (widget.tone == UiButtonTone.muted) {
      return FontWeight.w400;
    }
    return FontWeight.w500;
  }

  /// Resolves minimum button height from [UiButtonDensity].
  double _resolveHeight(UiThemeTokens tokens) {
    final spacing = tokens.spacing;
    return switch (widget.density) {
      UiButtonDensity.standard => spacing.touchTarget,
      UiButtonDensity.chrome => spacing.chromeControlHeight,
      UiButtonDensity.compact => spacing.buttonCompactHeight,
      UiButtonDensity.dense => spacing.buttonDenseHeight,
      UiButtonDensity.mobileTouch => spacing.touchTargetMobile,
      UiButtonDensity.sidebarDesktop => spacing.sidebarActionDesktop,
    };
  }

  /// Resolves icon glyph dimension matching `U-BRAND-003`.
  double _resolveIconSize(UiThemeTokens tokens) {
    final spacing = tokens.spacing;
    if (widget.variant == UiButtonVariant.icon) {
      return switch (widget.density) {
        UiButtonDensity.compact ||
        UiButtonDensity.dense ||
        UiButtonDensity.sidebarDesktop => spacing.iconXs,
        UiButtonDensity.chrome => spacing.iconSm,
        UiButtonDensity.standard ||
        UiButtonDensity.mobileTouch => spacing.iconMd,
      };
    }
    return switch (widget.density) {
      UiButtonDensity.compact ||
      UiButtonDensity.dense ||
      UiButtonDensity.sidebarDesktop => spacing.iconXs,
      UiButtonDensity.chrome || UiButtonDensity.standard => spacing.iconSm,
      UiButtonDensity.mobileTouch => spacing.iconMd,
    };
  }

  /// Resolves horizontal and vertical internal padding.
  EdgeInsets _resolvePadding(UiThemeTokens tokens) {
    if (widget.variant == UiButtonVariant.icon) {
      return EdgeInsets.all(
        widget.density == UiButtonDensity.sidebarDesktop ? 2.0 : 4.0,
      );
    }
    if (widget.variant == UiButtonVariant.text) {
      return const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0);
    }
    return switch (widget.density) {
      UiButtonDensity.compact ||
      UiButtonDensity.dense ||
      UiButtonDensity.sidebarDesktop => const EdgeInsets.symmetric(
        horizontal: 10.0,
        vertical: 5.0,
      ),
      UiButtonDensity.chrome => const EdgeInsets.symmetric(
        horizontal: 10.0,
        vertical: 6.0,
      ),
      UiButtonDensity.standard || UiButtonDensity.mobileTouch =>
        const EdgeInsets.symmetric(horizontal: 13.0, vertical: 8.0),
    };
  }

  /// Resolves default corner radius from variant and density.
  double _resolveRadius(UiThemeTokens tokens) {
    if (widget.density == UiButtonDensity.sidebarDesktop) {
      return tokens.radii.sm;
    }
    return tokens.radii.md;
  }

  /// Resolves text style matching variant and density.
  TextStyle _resolveTextStyle(UiThemeTokens tokens, Color foreground) {
    final base = switch (widget.density) {
      UiButtonDensity.compact ||
      UiButtonDensity.dense ||
      UiButtonDensity.chrome ||
      UiButtonDensity.sidebarDesktop => tokens.typography.meta,
      UiButtonDensity.standard ||
      UiButtonDensity.mobileTouch => tokens.typography.control,
    };
    return base.copyWith(color: foreground, fontWeight: _resolveFontWeight());
  }
}

/// Isolated spinning leading icon mounted ONLY while [UiButton.isLoading] is `true`.
class _UiButtonLoadingSpinner extends StatefulWidget {
  /// Creates a [_UiButtonLoadingSpinner].
  const _UiButtonLoadingSpinner({required this.child});

  /// Icon glyph rotated continuously while mounted.
  final Widget child;

  @override
  State<_UiButtonLoadingSpinner> createState() =>
      _UiButtonLoadingSpinnerState();
}

/// Owns the single rotation [AnimationController] for [_UiButtonLoadingSpinner].
class _UiButtonLoadingSpinnerState extends State<_UiButtonLoadingSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final targetDuration = UiThemeTokens.of(context).focus.spinDuration;
    if (_controller.duration != targetDuration) {
      _controller.duration = targetDuration;
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: RotationTransition(turns: _controller, child: widget.child),
    );
  }
}

/// Resolved color triple for a rendered [UiButton].
@immutable
class _UiButtonPalette {
  /// Creates a [_UiButtonPalette].
  const _UiButtonPalette({
    required this.background,
    required this.border,
    required this.foreground,
  });

  /// Surface background color.
  final Color background;

  /// Hairline `1px` border color.
  final Color border;

  /// Text and icon foreground color.
  final Color foreground;
}

/// Renders the flat bordered button box and optional `1px` offset focus ring.
class _UiButtonSurface extends StatelessWidget {
  /// Creates a [_UiButtonSurface].
  const _UiButtonSurface({
    required this.enabled,
    required this.height,
    required this.minWidth,
    required this.padding,
    required this.radius,
    required this.backgroundColor,
    required this.borderColor,
    required this.showFocusRing,
    required this.isFullWidth,
    required this.child,
  });

  /// Background surface color.
  final Color backgroundColor;

  /// Hairline border color.
  final Color borderColor;

  /// Button interior content.
  final Widget child;

  /// Whether hover transitions and focus ring overlays can occur.
  final bool enabled;

  /// Minimum height in logical pixels.
  final double height;

  /// Whether the box expands to fill available horizontal width.
  final bool isFullWidth;

  /// Minimum width in logical pixels.
  final double minWidth;

  /// Internal content padding.
  final EdgeInsets padding;

  /// Corner radius in logical pixels.
  final double radius;

  /// Whether to paint the outer `1px` `accent` keyboard focus ring.
  final bool showFocusRing;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final decoration = BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor, width: tokens.radii.borderWidth),
    );
    final constraints = BoxConstraints(
      minHeight: height,
      minWidth: isFullWidth ? double.infinity : minWidth,
    );
    final centeredChild = Center(
      widthFactor: 1.0,
      heightFactor: 1.0,
      child: child,
    );
    if (!enabled) {
      return ConstrainedBox(
        constraints: constraints,
        child: Container(
          padding: padding,
          decoration: decoration,
          child: centeredChild,
        ),
      );
    }

    final ringInset = tokens.focus.ringOffset + tokens.focus.ringWidth;
    final box = ConstrainedBox(
      constraints: constraints,
      child: AnimatedContainer(
        duration: tokens.focus.hoverDuration,
        padding: padding,
        decoration: decoration,
        child: centeredChild,
      ),
    );

    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: <Widget>[
        box,
        if (showFocusRing)
          Positioned.fill(
            left: -ringInset,
            top: -ringInset,
            right: -ringInset,
            bottom: -ringInset,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius + ringInset),
                  border: Border.all(
                    color: tokens.colors.accent,
                    width: tokens.focus.ringWidth,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Renders leading icon, optional label, and trailing icon inside [UiButton].
class _UiButtonContent extends StatelessWidget {
  /// Creates a [_UiButtonContent].
  const _UiButtonContent({
    required this.label,
    required this.leadingIcon,
    required this.trailingIcon,
    required this.foregroundColor,
    required this.iconSize,
    required this.textStyle,
    required this.isLoading,
  });

  /// Active foreground icon and text color.
  final Color foregroundColor;

  /// Icon glyph dimension.
  final double iconSize;

  /// Whether [leadingIcon] should mount [_UiButtonLoadingSpinner].
  final bool isLoading;

  /// Optional text label.
  final String? label;

  /// Optional leading icon glyph.
  final IconData? leadingIcon;

  /// Resolved label text style.
  final TextStyle textStyle;

  /// Optional trailing icon glyph.
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    Widget? leadingWidget;
    if (leadingIcon case final icon?) {
      final glyph = ExcludeSemantics(
        child: Icon(icon, size: iconSize, color: foregroundColor),
      );
      leadingWidget = isLoading ? _UiButtonLoadingSpinner(child: glyph) : glyph;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        ?leadingWidget,
        if (leadingWidget != null && label != null) const SizedBox(width: 6.0),
        if (label case final text?)
          Flexible(
            child: Text(
              text,
              style: textStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (trailingIcon case final trailing?) ...<Widget>[
          const SizedBox(width: 6.0),
          ExcludeSemantics(
            child: Icon(trailing, size: iconSize, color: foregroundColor),
          ),
        ],
      ],
    );
  }
}

/// Absorbs pointer taps on disabled [UiButton] instances so they do not bubble to clickable ancestors.
void _ignoreDisabledButtonTap() {}
