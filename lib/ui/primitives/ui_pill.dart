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
import '../tokens/ui_typography_tokens.dart';

/// Semantic presentation variant for [UiPill] (`U-COMP-002`).
enum UiPillVariant {
  /// Compact status or `DEV` pill badge.
  badge,

  /// Tabular-figures count capsule (e.g. `2 / 3`, `14`).
  count,

  /// Color-dotted or icon tag chip.
  tag,

  /// Compact metadata badge (e.g. due date, repeat, subtasks).
  meta,

  /// Split navigable label chip with optional trailing remove `x` target.
  splitChip,

  /// Section `+ Add` dashed chip or solid direct toggle chip (`isDirect: true`).
  addField,

  /// Toggleable selectable chip (weekdays, scopes, color presets, locations).
  selectable,
}

/// Semantic surface tone for [UiPill] (`U-SURFACE-004`).
enum UiPillTone {
  /// Neutral resting surface respecting [UiSurfaceScope].
  neutral,

  /// Soft accent tint with borderless edge.
  soft,

  /// Accent-tinted surface (`1px` `accent` border on badges; borderless at rest on `meta` pills).
  accent,

  /// Warning surface triple (`warningBg` / `warningBorder` / `warning`).
  warning,

  /// Danger surface triple (`dangerBg` / `dangerBorder` / `danger`).
  danger,

  /// Success surface triple (`successBg` / `successBorder` / `success`).
  success,
}

/// Unified pill, badge, count capsule, split chip, add-field chip, and selectable chip primitive.
class UiPill extends StatefulWidget {
  /// Creates a [UiPill].
  const UiPill({
    super.key,
    required this.label,
    this.variant = UiPillVariant.badge,
    this.tone = UiPillTone.neutral,
    this.colorDot,
    this.dotSize,
    this.icon,
    this.onPressed,
    this.onRemove,
    this.removeTooltip,
    this.tooltip,
    this.semanticLabel,
    this.isSelected = false,
    this.isDirect = false,
    this.isMono = false,
    this.enabled = true,
    this.focusNode,
  });

  /// Optional leading square-rounded color dot.
  final Color? colorDot;

  /// Optional dot size override (`8.0` default with `3px` radius; `>= 12.0` uses `4px` radius).
  final double? dotSize;

  /// Whether interactive callbacks are enabled.
  final bool enabled;

  /// Optional caller-managed [FocusNode].
  final FocusNode? focusNode;

  /// Optional leading outline icon glyph.
  final IconData? icon;

  /// Draws a solid border instead of a dashed border on [UiPillVariant.addField].
  final bool isDirect;

  /// Uses monospace styling (`DEV` badge, hex preset chips).
  final bool isMono;

  /// Active toggled state for [UiPillVariant.selectable] and [UiPillVariant.addField].
  final bool isSelected;

  /// Caller-supplied text content.
  final String label;

  /// Optional primary tap callback.
  final VoidCallback? onPressed;

  /// Optional secondary remove callback for [UiPillVariant.splitChip].
  final VoidCallback? onRemove;

  /// Accessible tooltip for the trailing remove button on [UiPillVariant.splitChip].
  final String? removeTooltip;

  /// Explicit accessible label overriding [tooltip] and [label].
  final String? semanticLabel;

  /// Semantic surface tone.
  final UiPillTone tone;

  /// Optional pointer tooltip for the primary pill body.
  final String? tooltip;

  /// Structural pill variant.
  final UiPillVariant variant;

  @override
  State<UiPill> createState() => _UiPillState();
}

/// Manages hover and keyboard focus-ring visual state for [UiPill].
class _UiPillState extends State<UiPill> {
  /// Whether pointer hover is active on the primary body.
  bool _isHovered = false;

  /// Whether keyboard focus ring is currently visible.
  bool _showFocusRing = false;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final surfaceLevel = UiSurfaceScope.of(context);
    final isInteractive = widget.enabled && widget.onPressed != null;
    final palette = _resolvePalette(
      tokens,
      surfaceLevel: surfaceLevel,
      hovered: _isHovered && isInteractive,
    );
    final radius = _resolveRadius(tokens);
    final useDashedBorder =
        widget.variant == UiPillVariant.addField && !widget.isDirect;

    final bodyContent = _UiPillBody(
      label: widget.label,
      colorDot: widget.colorDot,
      dotSize: widget.dotSize ?? 8.0,
      icon: widget.icon,
      foregroundColor: palette.foreground,
      textStyle: _resolveTextStyle(tokens, palette.foreground),
      padding: _resolvePadding(),
      hasRemoveButton:
          widget.variant == UiPillVariant.splitChip && widget.onRemove != null,
      onRemove: widget.enabled ? widget.onRemove : null,
      removeTooltip: widget.removeTooltip,
      onPrimaryTap: isInteractive ? widget.onPressed : null,
    );

    final boxDecoration = BoxDecoration(
      color: palette.background,
      borderRadius: BorderRadius.circular(radius),
      border: useDashedBorder
          ? null
          : Border.all(color: palette.border, width: tokens.radii.borderWidth),
    );
    final minHeightConstraints = BoxConstraints(
      minHeight: _resolveMinHeight(tokens),
    );

    Widget decorated = isInteractive
        ? AnimatedContainer(
            duration: tokens.focus.hoverDuration,
            constraints: minHeightConstraints,
            decoration: boxDecoration,
            child: bodyContent,
          )
        : ConstrainedBox(
            constraints: minHeightConstraints,
            child: DecoratedBox(decoration: boxDecoration, child: bodyContent),
          );

    if (useDashedBorder) {
      decorated = CustomPaint(
        foregroundPainter: _DashedRoundedBorderPainter(
          color: palette.border,
          radius: radius,
          strokeWidth: tokens.radii.borderWidth,
        ),
        child: decorated,
      );
    }

    Widget result = decorated;
    if (isInteractive) {
      final ringInset = tokens.focus.ringOffset + tokens.focus.ringWidth;
      final focusableContent = Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: <Widget>[
          decorated,
          if (_showFocusRing)
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
      result = FocusableActionDetector(
        focusNode: widget.focusNode,
        enabled: widget.enabled,
        mouseCursor: SystemMouseCursors.click,
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
        child:
            widget.variant == UiPillVariant.splitChip && widget.onRemove != null
            ? focusableContent
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onPressed,
                child: focusableContent,
              ),
      );
    }

    if (!widget.enabled) {
      result = Opacity(opacity: tokens.focus.disabledOpacity, child: result);
    }

    final accessible = Semantics(
      button: isInteractive,
      toggled: widget.variant == UiPillVariant.selectable
          ? widget.isSelected
          : null,
      enabled: widget.enabled,
      label: widget.semanticLabel ?? widget.tooltip ?? widget.label,
      child: result,
    );

    if (widget.tooltip case final tip?) {
      return Tooltip(message: tip, child: accessible);
    }
    return accessible;
  }

  /// Resolves font weight honoring selected state and semantic `.meta-pill` emphasis.
  FontWeight? _resolveFontWeight(FontWeight? baseWeight) {
    if (widget.isSelected) {
      return FontWeight.w600;
    }
    if (widget.variant != UiPillVariant.meta) {
      return baseWeight;
    }
    return switch (widget.tone) {
      UiPillTone.accent ||
      UiPillTone.warning ||
      UiPillTone.danger ||
      UiPillTone.success => FontWeight.w600,
      UiPillTone.neutral || UiPillTone.soft => FontWeight.w400,
    };
  }

  /// Resolves minimum vertical height for the pill variant.
  double _resolveMinHeight(UiThemeTokens tokens) {
    return switch (widget.variant) {
      UiPillVariant.selectable => tokens.spacing.fieldCompactHeight,
      UiPillVariant.addField => 30.0,
      UiPillVariant.splitChip => 28.0,
      UiPillVariant.count => 26.0,
      UiPillVariant.tag || UiPillVariant.meta => 24.0,
      UiPillVariant.badge => 22.0,
    };
  }

  /// Resolves neutral fill and border with automatic `UiSurfaceScope` re-elevation (`U-SURFACE-003`).
  _UiPillPalette _resolveNeutralPalette(
    UiThemeTokens tokens, {
    required UiSurfaceLevel surfaceLevel,
    required bool hovered,
  }) {
    final colors = tokens.colors;
    final restingFill = widget.variant == UiPillVariant.count
        ? colors.panel
        : (surfaceLevel == UiSurfaceLevel.insetWell ? colors.panel : colors.bg);
    if (widget.variant == UiPillVariant.meta) {
      return _UiPillPalette(
        background: restingFill,
        border: hovered ? colors.accent : Colors.transparent,
        foreground: hovered ? colors.ink : colors.muted,
      );
    }
    if (hovered) {
      return _UiPillPalette(
        background: colors.soft,
        border: colors.accent,
        foreground: colors.accent,
      );
    }
    final restingForeground = switch (widget.variant) {
      UiPillVariant.count ||
      UiPillVariant.tag ||
      UiPillVariant.splitChip ||
      UiPillVariant.selectable => colors.ink,
      UiPillVariant.badge ||
      UiPillVariant.meta ||
      UiPillVariant.addField => colors.muted,
    };
    return _UiPillPalette(
      background: restingFill,
      border: colors.line,
      foreground: restingForeground,
    );
  }

  /// Resolves internal padding by variant.
  EdgeInsets _resolvePadding() {
    return switch (widget.variant) {
      UiPillVariant.count => const EdgeInsets.symmetric(
        horizontal: 11.0,
        vertical: 4.0,
      ),
      UiPillVariant.selectable => const EdgeInsets.symmetric(
        horizontal: 11.0,
        vertical: 6.0,
      ),
      UiPillVariant.addField => const EdgeInsets.symmetric(
        horizontal: 10.0,
        vertical: 4.0,
      ),
      UiPillVariant.splitChip => const EdgeInsets.only(
        left: 8.0,
        right: 4.0,
        top: 3.0,
        bottom: 3.0,
      ),
      UiPillVariant.badge || UiPillVariant.tag || UiPillVariant.meta =>
        const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
    };
  }

  /// Resolves background, border, and foreground colors honoring [UiSurfaceScope].
  _UiPillPalette _resolvePalette(
    UiThemeTokens tokens, {
    required UiSurfaceLevel surfaceLevel,
    required bool hovered,
  }) {
    final colors = tokens.colors;
    if (widget.isSelected) {
      return _UiPillPalette(
        background: colors.soft,
        border: colors.accent,
        foreground: colors.accent,
      );
    }
    final isMeta = widget.variant == UiPillVariant.meta;
    return switch (widget.tone) {
      UiPillTone.soft => _UiPillPalette(
        background: colors.soft,
        border: isMeta && hovered ? colors.accent : Colors.transparent,
        foreground: colors.accent,
      ),
      UiPillTone.accent => _UiPillPalette(
        background: colors.soft,
        border: isMeta
            ? (hovered ? colors.accent : Colors.transparent)
            : colors.accent,
        foreground: colors.accent,
      ),
      UiPillTone.warning => _UiPillPalette(
        background: colors.warningBg,
        border: colors.warningBorder,
        foreground: colors.warning,
      ),
      UiPillTone.danger => _UiPillPalette(
        background: colors.dangerBg,
        border: colors.dangerBorder,
        foreground: colors.danger,
      ),
      UiPillTone.success => _UiPillPalette(
        background: colors.successBg,
        border: colors.successBorder,
        foreground: colors.success,
      ),
      UiPillTone.neutral => _resolveNeutralPalette(
        tokens,
        surfaceLevel: surfaceLevel,
        hovered: hovered,
      ),
    };
  }

  /// Resolves canonical corner radius per variant (`U-TOKEN-004`).
  double _resolveRadius(UiThemeTokens tokens) {
    final radii = tokens.radii;
    return switch (widget.variant) {
      UiPillVariant.count => radii.pill,
      UiPillVariant.badge => widget.isMono ? radii.tag : radii.pill,
      UiPillVariant.selectable => radii.sm,
      UiPillVariant.tag ||
      UiPillVariant.meta ||
      UiPillVariant.splitChip ||
      UiPillVariant.addField => radii.tag,
    };
  }

  /// Resolves pill typography with tabular figures on count pills and mono override.
  TextStyle _resolveTextStyle(UiThemeTokens tokens, Color foreground) {
    final typography = tokens.typography;
    if (widget.variant == UiPillVariant.count) {
      return UiTypographyTokens.tabular(
        typography.meta.copyWith(color: foreground),
      );
    }
    if (widget.variant == UiPillVariant.badge && widget.isMono) {
      return typography.devBadge.copyWith(color: foreground);
    }
    final base = switch (widget.variant) {
      UiPillVariant.badge => typography.eyebrow.copyWith(letterSpacing: 0.0),
      UiPillVariant.tag ||
      UiPillVariant.meta ||
      UiPillVariant.splitChip ||
      UiPillVariant.addField ||
      UiPillVariant.selectable => typography.chip,
      UiPillVariant.count => typography.meta,
    };
    final fontWeight = _resolveFontWeight(base.fontWeight);
    final styled = base.copyWith(color: foreground, fontWeight: fontWeight);
    return widget.isMono ? UiTypographyTokens.mono(styled) : styled;
  }
}

/// Resolved color triple for [UiPill].
@immutable
class _UiPillPalette {
  /// Creates a [_UiPillPalette].
  const _UiPillPalette({
    required this.background,
    required this.border,
    required this.foreground,
  });

  /// Fill color.
  final Color background;

  /// Border color.
  final Color border;

  /// Foreground text/icon color.
  final Color foreground;
}

/// Renders the interior dot, icon, label, and optional split-chip remove trigger.
class _UiPillBody extends StatelessWidget {
  /// Creates a [_UiPillBody].
  const _UiPillBody({
    required this.label,
    required this.colorDot,
    required this.dotSize,
    required this.icon,
    required this.foregroundColor,
    required this.textStyle,
    required this.padding,
    required this.hasRemoveButton,
    required this.onRemove,
    required this.removeTooltip,
    required this.onPrimaryTap,
  });

  /// Optional leading color dot.
  final Color? colorDot;

  /// Square color dot dimension.
  final double dotSize;

  /// Text and icon foreground color.
  final Color foregroundColor;

  /// Whether a trailing split-chip remove target is displayed.
  final bool hasRemoveButton;

  /// Optional leading icon glyph.
  final IconData? icon;

  /// Visible pill text.
  final String label;

  /// Primary half tap callback used for split chips.
  final VoidCallback? onPrimaryTap;

  /// Trailing remove callback.
  final VoidCallback? onRemove;

  /// Internal padding.
  final EdgeInsets padding;

  /// Tooltip for trailing remove button.
  final String? removeTooltip;

  /// Resolved label text style.
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final dotRadius = dotSize >= 12.0 ? tokens.radii.dotLg : tokens.radii.dotSm;

    Widget primary = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (colorDot case final dotColor?) ...<Widget>[
          ExcludeSemantics(
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: dotColor,
                borderRadius: BorderRadius.circular(dotRadius),
              ),
            ),
          ),
          const SizedBox(width: 6.0),
        ],
        if (icon case final glyph?) ...<Widget>[
          ExcludeSemantics(
            child: Icon(
              glyph,
              size: tokens.spacing.iconXs,
              color: foregroundColor,
            ),
          ),
          const SizedBox(width: 4.0),
        ],
        Flexible(
          child: Text(
            label,
            style: textStyle,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    if (hasRemoveButton && onPrimaryTap != null) {
      primary = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPrimaryTap,
        child: primary,
      );
    }

    return Padding(
      padding: padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(child: primary),
          if (onRemove case final removeCallback?
              when hasRemoveButton) ...<Widget>[
            const SizedBox(width: 4.0),
            _UiPillRemoveButton(
              onPressed: removeCallback,
              tooltip: removeTooltip,
            ),
          ],
        ],
      ),
    );
  }
}

/// Small trailing `x` remove button with danger hover tint for split label chips.
class _UiPillRemoveButton extends StatefulWidget {
  /// Creates a [_UiPillRemoveButton].
  const _UiPillRemoveButton({required this.onPressed, required this.tooltip});

  /// Removal callback.
  final VoidCallback onPressed;

  /// Accessible tooltip label.
  final String? tooltip;

  @override
  State<_UiPillRemoveButton> createState() => _UiPillRemoveButtonState();
}

/// Manages danger hover state for [_UiPillRemoveButton].
class _UiPillRemoveButtonState extends State<_UiPillRemoveButton> {
  /// Whether the remove control is currently hovered.
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Semantics(
          button: true,
          label: widget.tooltip,
          child: AnimatedContainer(
            duration: tokens.focus.hoverDuration,
            width: 18.0,
            height: 18.0,
            decoration: BoxDecoration(
              color: _hovered ? colors.dangerBg : Colors.transparent,
              borderRadius: BorderRadius.circular(tokens.radii.dotLg),
            ),
            child: Icon(
              Icons.close_rounded,
              size: tokens.spacing.iconXs,
              color: _hovered ? colors.danger : colors.muted,
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip case final tip?) {
      return Tooltip(message: tip, child: button);
    }
    return button;
  }
}

/// Custom painter drawing a `1px` dashed rounded-rectangle border for `UiPillVariant.addField`.
class _DashedRoundedBorderPainter extends CustomPainter {
  /// Creates a [_DashedRoundedBorderPainter].
  const _DashedRoundedBorderPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
  });

  /// Dash stroke segment length.
  static const double _dashLength = 4.0;

  /// Gap length between dash segments.
  static const double _gapLength = 3.0;

  /// Border stroke color.
  final Color color;

  /// Corner radius matching the decorated container.
  final double radius;

  /// Hairline stroke width (`1.0px`).
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final inset = strokeWidth / 2.0;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        inset,
        inset,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final dashedPath = Path();
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final nextEnd = (distance + _dashLength).clamp(0.0, metric.length);
        dashedPath.addPath(metric.extractPath(distance, nextEnd), Offset.zero);
        distance += _dashLength + _gapLength;
      }
    }
    canvas.drawPath(dashedPath, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.radius != radius ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
