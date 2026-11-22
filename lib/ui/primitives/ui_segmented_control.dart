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
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../tokens/ui_breakpoints.dart';
import '../tokens/ui_theme_tokens.dart';

/// Animation duration for opening and closing the vertical combobox popup menu.
const Duration _menuAnimationDuration = Duration(milliseconds: 160);

/// Vertical offset gap between the vertical trigger and its anchored popup menu.
const double _popupGap = 6.0;

/// Inner padding around option rows inside the vertical popup surface.
const double _popupInnerPadding = 4.0;

/// Safe margin separating the vertical popup from viewport edges.
const double _popupViewportMargin = 8.0;

/// Presentation mode for [UiSegmentedControl] (`U-COMP-002`).
enum UiSegmentedControlMode {
  /// Equal-width horizontal segments inside a flat bordered `bg` trough.
  horizontal,

  /// Compact combobox trigger expanding an animated direction-aware vertical menu.
  vertical,
}

/// Immutable option definition for a segment in [UiSegmentedControl].
@immutable
class UiSegment<T> {
  /// Creates a [UiSegment].
  const UiSegment({
    required this.value,
    required this.label,
    this.icon,
    this.enabled = true,
  });

  /// Whether this individual segment can be selected.
  final bool enabled;

  /// Optional leading outline icon glyph.
  final IconData? icon;

  /// Caller-supplied segment label.
  final String label;

  /// Strongly typed option value.
  final T value;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is UiSegment<T> &&
        other.value == value &&
        other.label == label &&
        other.icon == icon &&
        other.enabled == enabled;
  }

  @override
  int get hashCode => Object.hash(value, label, icon, enabled);
}

/// Segmented selector supporting horizontal trough and vertical combobox dropdown modes (`U-COMP-002`).
class UiSegmentedControl<T> extends StatelessWidget {
  /// Creates a [UiSegmentedControl].
  const UiSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.mode = UiSegmentedControlMode.horizontal,
    this.enabled = true,
    this.semanticLabel,
    this.focusNode,
    this.hintText,
    this.leadingIcon,
    this.hasError = false,
    this.minHeight,
    this.borderRadius,
    this.textStyle,
    this.applyDisabledOpacity = true,
  });

  /// Applies `disabledOpacity` internally when disabled (set false if an ancestor wraps opacity).
  final bool applyDisabledOpacity;

  /// Optional explicit corner radius for the vertical trigger overriding `tokens.radii.md`.
  final double? borderRadius;

  /// Whether the entire segmented control is interactive.
  final bool enabled;

  /// Optional caller-owned [FocusNode] for the vertical combobox trigger.
  final FocusNode? focusNode;

  /// Renders `danger` border color on the vertical trigger when true.
  final bool hasError;

  /// Optional placeholder text rendered in `muted` when no segment matches [value].
  final String? hintText;

  /// Optional leading outline icon rendered in the vertical trigger when the active segment has no icon.
  final IconData? leadingIcon;

  /// Optional explicit minimum height for the vertical trigger overriding `tokens.spacing.touchTarget`.
  final double? minHeight;

  /// Visual presentation mode (`horizontal` trough or `vertical` combobox popup).
  final UiSegmentedControlMode mode;

  /// Selection callback invoked when a segment is chosen by pointer or keyboard.
  final ValueChanged<T>? onChanged;

  /// Optional accessible group label.
  final String? semanticLabel;

  /// Ordered segment definitions.
  final List<UiSegment<T>> segments;

  /// Optional trigger typography override for the vertical combobox mode.
  final TextStyle? textStyle;

  /// Currently selected segment value.
  final T value;

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      UiSegmentedControlMode.horizontal => _UiHorizontalSegmentedControl<T>(
        segments: segments,
        value: value,
        onChanged: onChanged,
        enabled: enabled,
        semanticLabel: semanticLabel,
      ),
      UiSegmentedControlMode.vertical => _UiVerticalSegmentedControl<T>(
        segments: segments,
        value: value,
        onChanged: onChanged,
        enabled: enabled,
        semanticLabel: semanticLabel,
        focusNode: focusNode,
        hintText: hintText,
        leadingIcon: leadingIcon,
        hasError: hasError,
        minHeight: minHeight,
        borderRadius: borderRadius,
        textStyle: textStyle,
        applyDisabledOpacity: applyDisabledOpacity,
      ),
    };
  }
}

/// Private intent triggered by `ArrowRight` inside horizontal [UiSegmentedControl].
class _StepNextSegmentIntent extends Intent {
  /// Creates a [_StepNextSegmentIntent].
  const _StepNextSegmentIntent();
}

/// Private intent triggered by `ArrowLeft` inside horizontal [UiSegmentedControl].
class _StepPreviousSegmentIntent extends Intent {
  /// Creates a [_StepPreviousSegmentIntent].
  const _StepPreviousSegmentIntent();
}

/// Horizontal equal-width segmented control backing [UiSegmentedControlMode.horizontal].
class _UiHorizontalSegmentedControl<T> extends StatefulWidget {
  /// Creates a [_UiHorizontalSegmentedControl].
  const _UiHorizontalSegmentedControl({
    required this.segments,
    required this.value,
    required this.onChanged,
    required this.enabled,
    required this.semanticLabel,
  });

  /// Whether the entire control is interactive.
  final bool enabled;

  /// Selection callback invoked on tap or arrow-key step.
  final ValueChanged<T>? onChanged;

  /// Optional accessible group label.
  final String? semanticLabel;

  /// Ordered segments displayed horizontally.
  final List<UiSegment<T>> segments;

  /// Currently selected value.
  final T value;

  @override
  State<_UiHorizontalSegmentedControl<T>> createState() =>
      _UiHorizontalSegmentedControlState<T>();
}

/// Manages per-segment [FocusNode]s and horizontal stepping for [_UiHorizontalSegmentedControl].
class _UiHorizontalSegmentedControlState<T>
    extends State<_UiHorizontalSegmentedControl<T>> {
  final List<FocusNode> _focusNodes = <FocusNode>[];
  final List<FocusNode> _pendingDisposals = <FocusNode>[];
  bool _isDisposalScheduled = false;

  @override
  void initState() {
    super.initState();
    _syncFocusNodes();
  }

  @override
  void didUpdateWidget(covariant _UiHorizontalSegmentedControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segments.length != widget.segments.length) {
      _syncFocusNodes();
    }
  }

  @override
  void dispose() {
    _flushPendingDisposals();
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final controlEnabled = widget.enabled && widget.onChanged != null;

    return Semantics(
      container: true,
      label: widget.semanticLabel,
      child: Opacity(
        opacity: controlEnabled ? 1.0 : tokens.focus.disabledOpacity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.bg,
            borderRadius: BorderRadius.circular(tokens.radii.md),
            border: Border.all(
              color: colors.line,
              width: tokens.radii.borderWidth,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3.0),
            child: _UiHorizontalSegmentRow<T>(
              segments: widget.segments,
              value: widget.value,
              focusNodes: _focusNodes,
              controlEnabled: controlEnabled,
              onSelect: _selectSegment,
              onStep: _stepSelection,
            ),
          ),
        ),
      ),
    );
  }

  /// Queues a removed segment [node] for post-frame disposal after its tab unmounts.
  void _enqueueDisposal(FocusNode node) {
    _pendingDisposals.add(node);
    if (_isDisposalScheduled) {
      return;
    }
    _isDisposalScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushPendingDisposals();
    });
  }

  /// Disposes all queued segment focus nodes after the frame or during unmount.
  void _flushPendingDisposals() {
    _isDisposalScheduled = false;
    if (_pendingDisposals.isEmpty) {
      return;
    }
    final nodes = List<FocusNode>.of(_pendingDisposals);
    _pendingDisposals.clear();
    for (final node in nodes) {
      node.dispose();
    }
  }

  /// Focuses and selects segment at [index], skipping redundant notifications for the active value.
  void _selectSegment(int index) {
    _focusNodes[index].requestFocus();
    final nextValue = widget.segments[index].value;
    if (nextValue != widget.value) {
      widget.onChanged?.call(nextValue);
    }
  }

  /// Steps selection and focus by [delta] (`-1` or `+1`) to the next enabled segment.
  void _stepSelection(int currentIndex, int delta) {
    final nextIndex = _findNextEnabledSegmentIndex(
      widget.segments,
      currentIndex,
      delta,
    );
    if (nextIndex == null) {
      return;
    }
    _focusNodes[nextIndex].requestFocus();
    final nextValue = widget.segments[nextIndex].value;
    if (nextValue != widget.value) {
      widget.onChanged?.call(nextValue);
    }
  }

  /// Keeps [_focusNodes] length matched to `widget.segments.length` without leaking nodes.
  void _syncFocusNodes() {
    while (_focusNodes.length < widget.segments.length) {
      _focusNodes.add(FocusNode());
    }
    while (_focusNodes.length > widget.segments.length) {
      _enqueueDisposal(_focusNodes.removeLast());
    }
  }
}

/// Equal-width horizontal row of [_UiSegmentTab] items inside [_UiHorizontalSegmentedControl].
class _UiHorizontalSegmentRow<T> extends StatelessWidget {
  /// Creates a [_UiHorizontalSegmentRow].
  const _UiHorizontalSegmentRow({
    required this.segments,
    required this.value,
    required this.focusNodes,
    required this.controlEnabled,
    required this.onSelect,
    required this.onStep,
  });

  /// Whether the overall control accepts interaction.
  final bool controlEnabled;

  /// Per-segment focus nodes.
  final List<FocusNode> focusNodes;

  /// Callback selecting a segment by index.
  final ValueChanged<int> onSelect;

  /// Callback stepping selection by `delta` from an index.
  final void Function(int currentIndex, int delta) onStep;

  /// Ordered horizontal segments.
  final List<UiSegment<T>> segments;

  /// Currently selected segment value.
  final T value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (var i = 0; i < segments.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 4.0),
          Expanded(
            child: _UiSegmentTab(
              label: segments[i].label,
              icon: segments[i].icon,
              isSelected: segments[i].value == value,
              enabled: controlEnabled && segments[i].enabled,
              isIndividuallyDisabled: controlEnabled && !segments[i].enabled,
              focusNode: focusNodes[i],
              onTap: controlEnabled && segments[i].enabled
                  ? () => onSelect(i)
                  : null,
              onStepPrevious: controlEnabled && segments[i].enabled
                  ? () => onStep(i, -1)
                  : null,
              onStepNext: controlEnabled && segments[i].enabled
                  ? () => onStep(i, 1)
                  : null,
            ),
          ),
        ],
      ],
    );
  }
}

/// Paints the `1px` `accent` outer focus ring at `1px` offset around [child] (`U-A11Y-001`).
class _UiSegmentFocusRing extends StatelessWidget {
  /// Creates a [_UiSegmentFocusRing].
  const _UiSegmentFocusRing({
    required this.visible,
    required this.radius,
    required this.child,
  });

  /// Control surface wrapped by the optional focus ring.
  final Widget child;

  /// Corner radius of [child] in logical pixels.
  final double radius;

  /// Whether the outer focus ring is currently visible.
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final ringInset = tokens.focus.ringOffset + tokens.focus.ringWidth;
    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: <Widget>[
        child,
        if (visible)
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

/// Individual focusable tab cell inside [_UiHorizontalSegmentRow].
class _UiSegmentTab extends StatefulWidget {
  /// Creates a [_UiSegmentTab].
  const _UiSegmentTab({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.enabled,
    required this.isIndividuallyDisabled,
    required this.focusNode,
    required this.onTap,
    required this.onStepPrevious,
    required this.onStepNext,
  });

  /// Whether this segment can be interacted with.
  final bool enabled;

  /// Focus node owned by parent [_UiHorizontalSegmentedControl].
  final FocusNode focusNode;

  /// Optional leading icon glyph.
  final IconData? icon;

  /// Whether only this segment is disabled while the outer control stays enabled.
  final bool isIndividuallyDisabled;

  /// Whether this segment is active.
  final bool isSelected;

  /// Visible segment label.
  final String label;

  /// Callback for `ArrowRight` stepping.
  final VoidCallback? onStepNext;

  /// Callback for `ArrowLeft` stepping.
  final VoidCallback? onStepPrevious;

  /// Tap/activation callback.
  final VoidCallback? onTap;

  @override
  State<_UiSegmentTab> createState() => _UiSegmentTabState();
}

/// Manages hover and keyboard focus highlight for [_UiSegmentTab].
class _UiSegmentTabState extends State<_UiSegmentTab> {
  bool _isHovered = false;
  bool _showFocusRing = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: widget.isSelected,
      enabled: widget.enabled,
      label: widget.label,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        enabled: widget.enabled,
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowLeft):
              _StepPreviousSegmentIntent(),
          SingleActivator(LogicalKeyboardKey.arrowRight):
              _StepNextSegmentIntent(),
        },
        actions: _buildActions(),
        onShowHoverHighlight: _handleHoverChanged,
        onShowFocusHighlight: _handleFocusHighlightChanged,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: _UiSegmentTabSurface(
            label: widget.label,
            icon: widget.icon,
            isSelected: widget.isSelected,
            isHovered: _isHovered,
            enabled: widget.enabled,
            isIndividuallyDisabled: widget.isIndividuallyDisabled,
            showFocusRing: _showFocusRing,
          ),
        ),
      ),
    );
  }

  /// Builds keyboard activation and horizontal arrow stepping actions.
  Map<Type, Action<Intent>> _buildActions() {
    return <Type, Action<Intent>>{
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          widget.onTap?.call();
          return null;
        },
      ),
      ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
        onInvoke: (_) {
          widget.onTap?.call();
          return null;
        },
      ),
      _StepPreviousSegmentIntent: CallbackAction<_StepPreviousSegmentIntent>(
        onInvoke: (_) {
          widget.onStepPrevious?.call();
          return null;
        },
      ),
      _StepNextSegmentIntent: CallbackAction<_StepNextSegmentIntent>(
        onInvoke: (_) {
          widget.onStepNext?.call();
          return null;
        },
      ),
    };
  }

  /// Updates keyboard focus ring visibility.
  void _handleFocusHighlightChanged(bool focused) {
    if (_showFocusRing != focused) {
      setState(() => _showFocusRing = focused);
    }
  }

  /// Updates pointer hover highlight state.
  void _handleHoverChanged(bool hovered) {
    if (_isHovered != hovered) {
      setState(() => _isHovered = hovered);
    }
  }
}

/// Visual tab surface and centered label rendered inside [_UiSegmentTab].
class _UiSegmentTabSurface extends StatelessWidget {
  /// Creates a [_UiSegmentTabSurface].
  const _UiSegmentTabSurface({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.isHovered,
    required this.enabled,
    required this.isIndividuallyDisabled,
    required this.showFocusRing,
  });

  /// Whether this tab is enabled.
  final bool enabled;

  /// Optional leading icon glyph.
  final IconData? icon;

  /// Whether pointer hover is active.
  final bool isHovered;

  /// Whether only this segment should dim (outer trough already dims when control is disabled).
  final bool isIndividuallyDisabled;

  /// Whether this tab is active.
  final bool isSelected;

  /// Visible label text.
  final String label;

  /// Whether keyboard focus ring is visible.
  final bool showFocusRing;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final foreground = isSelected
        ? colors.accent
        : (isHovered && enabled ? colors.ink : colors.muted);
    final radius = tokens.radii.tag;

    return Opacity(
      opacity: isIndividuallyDisabled ? tokens.focus.disabledOpacity : 1.0,
      child: _UiSegmentFocusRing(
        visible: showFocusRing && enabled,
        radius: radius,
        child: AnimatedContainer(
          duration: tokens.focus.hoverDuration,
          width: double.infinity,
          constraints: BoxConstraints(
            minHeight: tokens.spacing.chromeControlHeight,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
          decoration: BoxDecoration(
            color: isSelected
                ? colors.panel
                : colors.panel.withValues(alpha: 0.0),
            borderRadius: BorderRadius.circular(radius),
            boxShadow: isSelected ? tokens.focus.segmentedShadow : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon case final glyph?) ...<Widget>[
                ExcludeSemantics(
                  child: Icon(
                    glyph,
                    size: tokens.spacing.iconXs,
                    color: foreground,
                  ),
                ),
                const SizedBox(width: 5.0),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.meta.copyWith(
                    color: foreground,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
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

/// Interactive option row inside [_UiVerticalPopupSurface] tracking hover without stealing trigger focus.
class _UiVerticalOptionRow extends StatefulWidget {
  /// Creates a [_UiVerticalOptionRow].
  const _UiVerticalOptionRow({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.isKeyboardHighlighted,
    required this.enabled,
    required this.minHeight,
    required this.onTap,
  });

  /// Whether this option can be selected.
  final bool enabled;

  /// Optional leading outline icon glyph.
  final IconData? icon;

  /// Whether keyboard highlight inset border is shown.
  final bool isKeyboardHighlighted;

  /// Whether this option is currently active.
  final bool isSelected;

  /// Visible option label.
  final String label;

  /// Minimum touch-target row height (`34px` desktop, `44px` compact).
  final double minHeight;

  /// Selection callback invoked on tap when [enabled] is true.
  final VoidCallback? onTap;

  @override
  State<_UiVerticalOptionRow> createState() => _UiVerticalOptionRowState();
}

/// Manages pointer hover state for [_UiVerticalOptionRow].
class _UiVerticalOptionRowState extends State<_UiVerticalOptionRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: widget.isSelected,
      enabled: widget.enabled,
      label: widget.label,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onTap : null,
          child: _UiVerticalOptionSurface(
            label: widget.label,
            icon: widget.icon,
            isSelected: widget.isSelected,
            isHovered: _isHovered,
            isKeyboardHighlighted: widget.isKeyboardHighlighted,
            enabled: widget.enabled,
            minHeight: widget.minHeight,
          ),
        ),
      ),
    );
  }

  /// Updates hover state when pointer enters or leaves this row.
  void _setHovered(bool hovered) {
    if (_isHovered != hovered) {
      setState(() => _isHovered = hovered);
    }
  }
}

/// Visual surface for one option row inside [_UiVerticalOptionRow].
class _UiVerticalOptionSurface extends StatelessWidget {
  /// Creates a [_UiVerticalOptionSurface].
  const _UiVerticalOptionSurface({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.isHovered,
    required this.isKeyboardHighlighted,
    required this.enabled,
    required this.minHeight,
  });

  /// Whether this option can be selected.
  final bool enabled;

  /// Optional leading outline icon glyph.
  final IconData? icon;

  /// Whether pointer hover is active on this option.
  final bool isHovered;

  /// Whether keyboard highlight border is active on this option.
  final bool isKeyboardHighlighted;

  /// Whether this option matches the active value.
  final bool isSelected;

  /// Visible option label.
  final String label;

  /// Minimum row height (`34px` desktop, `44px` compact).
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final background = isSelected
        ? colors.soft
        : (isHovered && enabled ? colors.bg : Colors.transparent);
    final foreground = isSelected
        ? colors.accent
        : ((isHovered || isKeyboardHighlighted) && enabled
              ? colors.ink
              : colors.muted);
    final borderColor = isKeyboardHighlighted && enabled
        ? colors.accent
        : Colors.transparent;

    return Opacity(
      opacity: enabled ? 1.0 : tokens.focus.disabledOpacity,
      child: AnimatedContainer(
        duration: tokens.focus.hoverDuration,
        constraints: BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(tokens.radii.tag),
          border: Border.all(
            color: borderColor,
            width: tokens.radii.borderWidth,
          ),
        ),
        child: Row(
          children: <Widget>[
            if (icon case final glyph?) ...<Widget>[
              ExcludeSemantics(
                child: Icon(
                  glyph,
                  size: tokens.spacing.iconXs,
                  color: foreground,
                ),
              ),
              const SizedBox(width: 6.0),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.typography.meta.copyWith(
                  color: foreground,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (isSelected) ...<Widget>[
              const SizedBox(width: 8.0),
              ExcludeSemantics(
                child: Icon(
                  Icons.check_rounded,
                  size: tokens.spacing.iconXs,
                  color: colors.accent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Measured viewport geometry and direction for the vertical combobox popup menu.
@immutable
class _UiVerticalPopupMetrics {
  /// Creates a [_UiVerticalPopupMetrics].
  const _UiVerticalPopupMetrics({
    required this.width,
    required this.maxHeight,
    required this.offsetX,
    required this.openUpward,
    required this.rowMinHeight,
  });

  /// Safe default metrics used prior to first trigger layout measurement.
  static const _UiVerticalPopupMetrics initial = _UiVerticalPopupMetrics(
    width: 140.0,
    maxHeight: 240.0,
    offsetX: 0.0,
    openUpward: false,
    rowMinHeight: 34.0,
  );

  /// Maximum vertical height clamped to available viewport space.
  final double maxHeight;

  /// Horizontal follower offset preventing viewport edge clipping.
  final double offsetX;

  /// Whether the popup expands upward above the trigger instead of downward.
  final bool openUpward;

  /// Minimum height per option row (`34px` desktop, `44px` compact).
  final double rowMinHeight;

  /// Resolved popup width (`>= triggerWidth`, wide enough for labels, clamped to viewport).
  final double width;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _UiVerticalPopupMetrics &&
        (other.width - width).abs() < 0.5 &&
        (other.maxHeight - maxHeight).abs() < 0.5 &&
        (other.offsetX - offsetX).abs() < 0.5 &&
        other.openUpward == openUpward &&
        other.rowMinHeight == rowMinHeight;
  }

  @override
  int get hashCode => Object.hash(
    width.round(),
    maxHeight.round(),
    offsetX.round(),
    openUpward,
    rowMinHeight,
  );
}

/// Anchored, direction-aware overlay positioning [child] (`U-SURFACE-002`).
class _UiVerticalPopupOverlay extends StatelessWidget {
  /// Creates a [_UiVerticalPopupOverlay].
  const _UiVerticalPopupOverlay({
    required this.layerLink,
    required this.tapRegionGroupId,
    required this.metrics,
    required this.isInteractive,
    required this.onDismissOutside,
    required this.child,
  });

  /// Animated popup surface anchored to the trigger.
  final Widget child;

  /// Whether option rows currently accept pointer hits (false while closing).
  final bool isInteractive;

  /// Layer link connected to the vertical combobox trigger.
  final LayerLink layerLink;

  /// Measured popup width, max height, row density, and opening direction.
  final _UiVerticalPopupMetrics metrics;

  /// Callback dismissing the popup when tapping outside [tapRegionGroupId].
  final VoidCallback onDismissOutside;

  /// Shared `TapRegion` group identifier linking trigger and popup.
  final Object tapRegionGroupId;

  @override
  Widget build(BuildContext context) {
    final openUpward = metrics.openUpward;
    return Positioned(
      width: metrics.width,
      child: CompositedTransformFollower(
        link: layerLink,
        showWhenUnlinked: false,
        targetAnchor: openUpward ? Alignment.topLeft : Alignment.bottomLeft,
        followerAnchor: openUpward ? Alignment.bottomLeft : Alignment.topLeft,
        offset: Offset(metrics.offsetX, openUpward ? -_popupGap : _popupGap),
        child: TapRegion(
          groupId: tapRegionGroupId,
          onTapOutside: (_) => onDismissOutside(),
          child: IgnorePointer(
            ignoring: !isInteractive,
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ),
    );
  }
}

/// Shadowed animated `panel` popup surface hosting scrollable vertical option rows.
class _UiVerticalPopupSurface<T> extends StatelessWidget {
  /// Creates a [_UiVerticalPopupSurface].
  const _UiVerticalPopupSurface({
    required this.animation,
    required this.scrollController,
    required this.metrics,
    required this.segments,
    required this.value,
    required this.highlightedIndex,
    required this.hasKeyboardHighlight,
    required this.onSelectIndex,
  });

  /// Curved open/close animation driving opacity and vertical size factor.
  final Animation<double> animation;

  /// Whether keyboard highlight border is currently visible.
  final bool hasKeyboardHighlight;

  /// Index of the keyboard-highlighted option row.
  final int highlightedIndex;

  /// Measured popup geometry and direction.
  final _UiVerticalPopupMetrics metrics;

  /// Callback selecting the option at the given index.
  final ValueChanged<int> onSelectIndex;

  /// Scroll controller for bringing active options into view.
  final ScrollController scrollController;

  /// Ordered vertical options.
  final List<UiSegment<T>> segments;

  /// Currently selected value.
  final T value;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final radius = BorderRadius.circular(tokens.radii.md);

    return FadeTransition(
      opacity: animation,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: radius,
          border: Border.all(
            color: colors.line,
            width: tokens.radii.borderWidth,
          ),
          boxShadow: tokens.focus.popoverShadow,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: SizeTransition(
            sizeFactor: animation,
            alignment: metrics.openUpward
                ? Alignment.bottomCenter
                : Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: metrics.maxHeight),
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(_popupInnerPadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (var i = 0; i < segments.length; i++)
                      _UiVerticalOptionRow(
                        label: segments[i].label,
                        icon: segments[i].icon,
                        isSelected: segments[i].value == value,
                        isKeyboardHighlighted:
                            hasKeyboardHighlight && i == highlightedIndex,
                        enabled: segments[i].enabled,
                        minHeight: metrics.rowMinHeight,
                        onTap: segments[i].enabled
                            ? () => onSelectIndex(i)
                            : null,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vertical combobox implementation backing [UiSegmentedControlMode.vertical] and `UiFieldKind.select`.
class _UiVerticalSegmentedControl<T> extends StatefulWidget {
  /// Creates a [_UiVerticalSegmentedControl].
  const _UiVerticalSegmentedControl({
    required this.segments,
    required this.value,
    required this.onChanged,
    required this.enabled,
    required this.semanticLabel,
    required this.focusNode,
    required this.hintText,
    required this.leadingIcon,
    required this.hasError,
    required this.minHeight,
    required this.borderRadius,
    required this.textStyle,
    required this.applyDisabledOpacity,
  });

  /// Applies `disabledOpacity` internally when disabled.
  final bool applyDisabledOpacity;

  /// Optional trigger corner radius override.
  final double? borderRadius;

  /// Whether the control accepts pointer and keyboard interaction.
  final bool enabled;

  /// Optional caller-owned focus node (not disposed here).
  final FocusNode? focusNode;

  /// Renders `danger` border color when true.
  final bool hasError;

  /// Placeholder label shown in `muted` when no segment matches [value].
  final String? hintText;

  /// Optional leading icon used when the active segment has no icon.
  final IconData? leadingIcon;

  /// Optional trigger minimum height override.
  final double? minHeight;

  /// Selection callback invoked when an option is chosen.
  final ValueChanged<T>? onChanged;

  /// Optional accessible group label.
  final String? semanticLabel;

  /// Ordered segments shown in the vertical popup menu.
  final List<UiSegment<T>> segments;

  /// Optional trigger typography override.
  final TextStyle? textStyle;

  /// Currently selected segment value.
  final T value;

  @override
  State<_UiVerticalSegmentedControl<T>> createState() =>
      _UiVerticalSegmentedControlState<T>();
}

/// Manages popup animation, dynamic viewport metrics, `TapRegion` dismissal, and keyboard navigation.
class _UiVerticalSegmentedControlState<T>
    extends State<_UiVerticalSegmentedControl<T>>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final List<ScrollPosition> _attachedScrollPositions = <ScrollPosition>[];
  final LayerLink _layerLink = LayerLink();
  final ScrollController _menuScrollController = ScrollController();
  final OverlayPortalController _overlayController = OverlayPortalController();
  final List<FocusNode> _pendingDisposals = <FocusNode>[];
  final Object _tapRegionGroupId = Object();
  final GlobalKey _triggerKey = GlobalKey();

  late final AnimationController _animationController;
  late final Animation<double> _chevronTurns;
  late final CurvedAnimation _curvedAnimation;

  FocusNode? _ownedFocusNode;
  bool _hasKeyboardHighlight = false;
  int _highlightedIndex = 0;
  bool _isDisposalScheduled = false;
  bool _isFocused = false;
  bool _isHovered = false;
  bool _isMenuOpen = false;
  bool _metricsRefreshScheduled = false;
  _UiVerticalPopupMetrics _popupMetrics = _UiVerticalPopupMetrics.initial;
  bool _showFocusRing = false;

  /// Whether the vertical combobox can open and select options.
  bool get _controlEnabled =>
      widget.enabled && widget.onChanged != null && widget.segments.isNotEmpty;

  /// Active focus node (caller-owned or internal).
  FocusNode get _focusNode {
    if (widget.focusNode case final external?) {
      return external;
    }
    return _ownedFocusNode ??= FocusNode();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animationController = AnimationController(
      vsync: this,
      duration: _menuAnimationDuration,
    );
    _curvedAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _chevronTurns = Tween<double>(
      begin: 0.0,
      end: 0.5,
    ).animate(_curvedAnimation);
    _animationController.addStatusListener(_handleAnimationStatusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    MediaQuery.maybeSizeOf(context);
    MediaQuery.maybePaddingOf(context);
    MediaQuery.maybeViewPaddingOf(context);
    MediaQuery.maybeViewInsetsOf(context);
    if (_isMenuOpen || _overlayController.isShowing) {
      _scheduleMetricsRefresh();
    }
  }

  @override
  void didChangeMetrics() {
    if (_isMenuOpen || _overlayController.isShowing) {
      _scheduleMetricsRefresh();
    }
  }

  @override
  void didUpdateWidget(covariant _UiVerticalSegmentedControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode && widget.focusNode != null) {
      if (_ownedFocusNode case final previousOwned?) {
        _ownedFocusNode = null;
        _enqueueDisposal(previousOwned);
      }
    }
    if (!_controlEnabled && _isMenuOpen) {
      _detachScrollListeners();
      _isMenuOpen = false;
      _hasKeyboardHighlight = false;
      unawaited(_animationController.reverse());
      return;
    }
    if (_isMenuOpen) {
      if (_highlightedIndex >= widget.segments.length) {
        _highlightedIndex = _resolveInitialHighlightIndex();
      }
      _scheduleMetricsRefresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detachScrollListeners();
    _animationController.removeStatusListener(_handleAnimationStatusChanged);
    _curvedAnimation.dispose();
    _animationController.dispose();
    _menuScrollController.dispose();
    _flushPendingDisposals();
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolveTriggerDisplay();
    return TapRegion(
      groupId: _tapRegionGroupId,
      child: CompositedTransformTarget(
        link: _layerLink,
        child: OverlayPortal(
          controller: _overlayController,
          overlayChildBuilder: _buildPopupOverlay,
          child: NotificationListener<SizeChangedLayoutNotification>(
            onNotification: _handleTriggerSizeChanged,
            child: SizeChangedLayoutNotifier(
              child: _UiVerticalTrigger(
                semanticLabel: widget.semanticLabel,
                valueLabel: resolved.label,
                enabled: _controlEnabled,
                focusNode: _focusNode,
                onKeyEvent: _handleKeyEvent,
                onFocusChange: _handleFocusChange,
                onShowFocusHighlight: _handleFocusHighlightChanged,
                onShowHoverHighlight: _handleHoverChanged,
                onActivateAction: _handleSemanticActivate,
                onTap: _controlEnabled
                    ? () => _toggleMenu(viaKeyboard: false)
                    : null,
                child: _UiVerticalTriggerBox(
                  triggerKey: _triggerKey,
                  enabled: _controlEnabled,
                  applyDisabledOpacity: widget.applyDisabledOpacity,
                  hasError: widget.hasError,
                  isHighlighted:
                      _controlEnabled &&
                      (_isHovered || _isFocused || _isMenuOpen),
                  showFocusRing: _showFocusRing && _controlEnabled,
                  minHeight: widget.minHeight,
                  borderRadius: widget.borderRadius,
                  child: _UiVerticalTriggerContent(
                    label: resolved.label,
                    hasSelectedValue: resolved.hasSelection,
                    icon: resolved.icon,
                    iconUsesMutedTint: resolved.iconUsesMutedTint,
                    isMenuOpen: _isMenuOpen,
                    textStyle: widget.textStyle,
                    chevronTurns: _chevronTurns,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Selects the keyboard-highlighted option if enabled and restores trigger focus.
  void _activateKeyboardSelection() {
    if (_highlightedIndex < 0 || _highlightedIndex >= widget.segments.length) {
      _closeMenu(restoreFocus: true);
      return;
    }
    if (!widget.segments[_highlightedIndex].enabled) {
      return;
    }
    _selectIndex(_highlightedIndex);
  }

  /// Subscribes to all ancestor [ScrollPosition]s so scrolling refreshes popup geometry.
  void _attachScrollListeners() {
    _detachScrollListeners();
    context.visitAncestorElements((element) {
      if (element.widget is Scrollable && element is StatefulElement) {
        final state = element.state;
        if (state is ScrollableState) {
          final position = state.position;
          if (!_attachedScrollPositions.contains(position)) {
            position.addListener(_scheduleMetricsRefresh);
            _attachedScrollPositions.add(position);
          }
        }
      }
      return true;
    });
  }

  /// Builds the anchored vertical popup menu inside [OverlayPortal].
  Widget _buildPopupOverlay(BuildContext context) {
    return _UiVerticalPopupOverlay(
      layerLink: _layerLink,
      tapRegionGroupId: _tapRegionGroupId,
      metrics: _popupMetrics,
      isInteractive: _isMenuOpen,
      onDismissOutside: () => _closeMenu(restoreFocus: false),
      child: _UiVerticalPopupSurface<T>(
        animation: _curvedAnimation,
        scrollController: _menuScrollController,
        metrics: _popupMetrics,
        segments: widget.segments,
        value: widget.value,
        highlightedIndex: _highlightedIndex,
        hasKeyboardHighlight: _hasKeyboardHighlight,
        onSelectIndex: _selectIndex,
      ),
    );
  }

  /// Reverses the popup animation and hides the overlay upon dismissal completion.
  void _closeMenu({required bool restoreFocus}) {
    if (!_isMenuOpen) {
      return;
    }
    _detachScrollListeners();
    setState(() {
      _isMenuOpen = false;
      _hasKeyboardHighlight = false;
    });
    if (restoreFocus && mounted) {
      _focusNode.requestFocus();
    }
    unawaited(_animationController.reverse());
  }

  /// Measures trigger bounds against viewport padding to determine opening direction and popup width.
  _UiVerticalPopupMetrics _computePopupMetrics() {
    final tokens = UiThemeTokens.of(context);
    final mediaSize = MediaQuery.sizeOf(context);
    final localPadding = MediaQuery.paddingOf(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final flutterView = View.maybeOf(context);
    final hardwareViewPadding = flutterView == null
        ? EdgeInsets.zero
        : EdgeInsets.fromViewPadding(
            flutterView.viewPadding,
            flutterView.devicePixelRatio,
          );
    final mediaPadding = EdgeInsets.fromLTRB(
      math.max(
        math.max(localPadding.left, viewPadding.left),
        hardwareViewPadding.left,
      ),
      math.max(
        math.max(localPadding.top, viewPadding.top),
        hardwareViewPadding.top,
      ),
      math.max(
        math.max(localPadding.right, viewPadding.right),
        hardwareViewPadding.right,
      ),
      math.max(
        math.max(localPadding.bottom, viewPadding.bottom),
        hardwareViewPadding.bottom,
      ),
    );
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final rowMinHeight = UiBreakpoints.isCompact(mediaSize.width)
        ? tokens.spacing.touchTargetMobile
        : tokens.spacing.chromeControlHeight;

    final renderObject = _triggerKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return _UiVerticalPopupMetrics(
        width: _measurePopupWidth(tokens, 0.0, mediaSize, mediaPadding),
        maxHeight: math.max(rowMinHeight + 10.0, mediaSize.height * 0.4),
        offsetX: 0.0,
        openUpward: false,
        rowMinHeight: rowMinHeight,
      );
    }

    final topLeft = renderObject.localToGlobal(Offset.zero);
    final triggerSize = renderObject.size;
    final bottomInset = math.max(mediaPadding.bottom, viewInsets.bottom);
    final safeTop = mediaPadding.top + _popupViewportMargin;
    final safeBottom = mediaSize.height - bottomInset - _popupViewportMargin;
    final availableAbove = math.max(0.0, topLeft.dy - safeTop - _popupGap);
    final availableBelow = math.max(
      0.0,
      safeBottom - (topLeft.dy + triggerSize.height) - _popupGap,
    );
    final estimatedHeight =
        widget.segments.length * rowMinHeight +
        (_popupInnerPadding * 2.0) +
        (tokens.radii.borderWidth * 2.0);
    final openUpward =
        estimatedHeight > availableBelow && availableAbove > availableBelow;
    final maxHeight = math.max(
      rowMinHeight + (_popupInnerPadding * 2.0) + 2.0,
      openUpward ? availableAbove : availableBelow,
    );
    final popupWidth = _measurePopupWidth(
      tokens,
      triggerSize.width,
      mediaSize,
      mediaPadding,
    );
    final offsetX = _resolveHorizontalOffset(
      triggerLeft: topLeft.dx,
      popupWidth: popupWidth,
      viewportWidth: mediaSize.width,
      mediaPadding: mediaPadding,
    );

    return _UiVerticalPopupMetrics(
      width: popupWidth,
      maxHeight: maxHeight,
      offsetX: offsetX,
      openUpward: openUpward,
      rowMinHeight: rowMinHeight,
    );
  }

  /// Removes all ancestor scroll listeners attached while the popup was open.
  void _detachScrollListeners() {
    for (final position in _attachedScrollPositions) {
      position.removeListener(_scheduleMetricsRefresh);
    }
    _attachedScrollPositions.clear();
  }

  /// Queues a replaced internal [node] for post-frame disposal after children detach.
  void _enqueueDisposal(FocusNode node) {
    _pendingDisposals.add(node);
    if (_isDisposalScheduled) {
      return;
    }
    _isDisposalScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushPendingDisposals();
    });
  }

  /// Disposes all queued internal focus nodes after the frame or during unmount.
  void _flushPendingDisposals() {
    _isDisposalScheduled = false;
    if (_pendingDisposals.isEmpty) {
      return;
    }
    final nodes = List<FocusNode>.of(_pendingDisposals);
    _pendingDisposals.clear();
    for (final node in nodes) {
      node.dispose();
    }
  }

  /// Opens the popup or commits the keyboard-highlighted option on `Enter`/`Space`.
  void _handleActivationKey() {
    if (_isMenuOpen) {
      _activateKeyboardSelection();
      return;
    }
    _openMenu(viaKeyboard: true);
  }

  /// Hides the overlay portal once the reverse collapse animation reaches `dismissed`.
  void _handleAnimationStatusChanged(AnimationStatus status) {
    if (!mounted) {
      return;
    }
    if (status == AnimationStatus.dismissed &&
        !_isMenuOpen &&
        _overlayController.isShowing) {
      _overlayController.hide();
    }
  }

  /// Opens the popup or steps highlight by [delta] on `ArrowDown`/`ArrowUp`.
  void _handleArrowKey(int delta) {
    if (!_isMenuOpen) {
      _openMenu(viaKeyboard: true);
      return;
    }
    _stepHighlight(delta);
  }

  /// Tracks trigger focus and closes an open menu if focus moves outside the combobox.
  void _handleFocusChange(bool focused) {
    if (_isFocused != focused) {
      setState(() => _isFocused = focused);
    }
    if (!focused && _isMenuOpen) {
      _closeMenu(restoreFocus: false);
    }
  }

  /// Updates keyboard focus ring visibility on the trigger.
  void _handleFocusHighlightChanged(bool focused) {
    if (_showFocusRing != focused) {
      setState(() => _showFocusRing = focused);
    }
  }

  /// Updates pointer hover border highlight on the trigger.
  void _handleHoverChanged(bool hovered) {
    if (_isHovered != hovered) {
      setState(() => _isHovered = hovered);
    }
  }

  /// Handles `Enter`, `Space`, `ArrowDown`, `ArrowUp`, `Home`, `End`, and `Escape`.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_controlEnabled ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (!_isMenuOpen) {
        return KeyEventResult.ignored;
      }
      _closeMenu(restoreFocus: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _handleArrowKey(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _handleArrowKey(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home && _isMenuOpen) {
      _jumpHighlight(toEnd: false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end && _isMenuOpen) {
      _jumpHighlight(toEnd: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      if (event is KeyRepeatEvent) {
        return KeyEventResult.handled;
      }
      _handleActivationKey();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Handles semantic accessibility activation intents when keyboard events did not intercept them.
  void _handleSemanticActivate() {
    if (!_controlEnabled) {
      return;
    }
    _toggleMenu(viaKeyboard: true);
  }

  /// Refreshes popup geometry when the trigger changes size while the popup is visible.
  bool _handleTriggerSizeChanged(SizeChangedLayoutNotification notification) {
    if (_isMenuOpen || _overlayController.isShowing) {
      _scheduleMetricsRefresh();
    }
    return false;
  }

  /// Moves keyboard highlight to the first or last enabled option and scrolls it into view.
  void _jumpHighlight({required bool toEnd}) {
    final nextIndex = _findBoundaryEnabledSegmentIndex(
      widget.segments,
      fromEnd: toEnd,
    );
    if (nextIndex == null) {
      return;
    }
    setState(() {
      _highlightedIndex = nextIndex;
      _hasKeyboardHighlight = true;
    });
    _scrollIndexIntoView(nextIndex, center: false);
  }

  /// Measures the maximum intrinsic option width so labels render cleanly without clipping.
  double _measurePopupWidth(
    UiThemeTokens tokens,
    double triggerWidth,
    Size mediaSize,
    EdgeInsets mediaPadding,
  ) {
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final labelStyle = tokens.typography.meta.copyWith(
      fontWeight: FontWeight.w600,
    );
    var widestOption = triggerWidth;
    for (final segment in widget.segments) {
      final candidateWidth = _measureSegmentOptionWidth(
        segment: segment,
        tokens: tokens,
        labelStyle: labelStyle,
        textDirection: textDirection,
        textScaler: textScaler,
      );
      if (candidateWidth > widestOption) {
        widestOption = candidateWidth;
      }
    }
    final viewportMax = math.max(
      0.0,
      mediaSize.width -
          mediaPadding.left -
          mediaPadding.right -
          (_popupViewportMargin * 2.0),
    );
    return math.min(widestOption, viewportMax);
  }

  /// Measures direction, attaches scroll listeners, reveals the overlay portal, and runs open animation.
  void _openMenu({required bool viaKeyboard}) {
    if (!_controlEnabled) {
      return;
    }
    final metrics = _computePopupMetrics();
    final initialHighlight = _resolveInitialHighlightIndex();
    _attachScrollListeners();
    _focusNode.requestFocus();
    setState(() {
      _popupMetrics = metrics;
      _highlightedIndex = initialHighlight;
      _hasKeyboardHighlight = viaKeyboard;
      _isMenuOpen = true;
    });
    if (!_overlayController.isShowing) {
      _overlayController.show();
    }
    unawaited(_animationController.forward());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isMenuOpen) {
        _scrollIndexIntoView(initialHighlight, center: true);
      }
    });
  }

  /// Resolves the initial highlighted index to the selected enabled segment or first enabled segment.
  int _resolveInitialHighlightIndex() {
    var firstEnabled = 0;
    var foundEnabled = false;
    for (var i = 0; i < widget.segments.length; i++) {
      final segment = widget.segments[i];
      if (!segment.enabled) {
        continue;
      }
      if (!foundEnabled) {
        firstEnabled = i;
        foundEnabled = true;
      }
      if (segment.value == widget.value) {
        return i;
      }
    }
    return firstEnabled;
  }

  /// Resolves the trigger label, icon, and selection presence honoring optional [widget.hintText].
  ({String label, bool hasSelection, IconData? icon, bool iconUsesMutedTint})
  _resolveTriggerDisplay() {
    for (final segment in widget.segments) {
      if (segment.value == widget.value) {
        return (
          label: segment.label,
          hasSelection: true,
          icon: segment.icon ?? widget.leadingIcon,
          iconUsesMutedTint: segment.icon == null && widget.leadingIcon != null,
        );
      }
    }
    if (widget.hintText case final hint?) {
      return (
        label: hint,
        hasSelection: false,
        icon: widget.leadingIcon,
        iconUsesMutedTint: true,
      );
    }
    if (widget.segments.isNotEmpty) {
      final fallback = widget.segments.first;
      return (
        label: fallback.label,
        hasSelection: true,
        icon: fallback.icon ?? widget.leadingIcon,
        iconUsesMutedTint: fallback.icon == null && widget.leadingIcon != null,
      );
    }
    return (
      label: '',
      hasSelection: false,
      icon: widget.leadingIcon,
      iconUsesMutedTint: true,
    );
  }

  /// Queues a single post-frame geometry refresh while the popup is visible.
  void _scheduleMetricsRefresh() {
    if (_metricsRefreshScheduled || !mounted) {
      return;
    }
    _metricsRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _metricsRefreshScheduled = false;
      if (!mounted || (!_isMenuOpen && !_overlayController.isShowing)) {
        return;
      }
      final nextMetrics = _computePopupMetrics();
      if (nextMetrics != _popupMetrics) {
        setState(() => _popupMetrics = nextMetrics);
      }
    });
  }

  /// Scrolls [_menuScrollController] so option at [index] is visible inside the popup viewport.
  void _scrollIndexIntoView(int index, {required bool center}) {
    if (!_menuScrollController.hasClients) {
      return;
    }
    final position = _menuScrollController.position;
    if (position.maxScrollExtent <= 0.0) {
      return;
    }
    final rowHeight = _popupMetrics.rowMinHeight;
    final rowTop = index * rowHeight;
    final rowBottom = rowTop + rowHeight;
    final viewportExtent = position.viewportDimension;
    final double targetOffset;
    if (center) {
      targetOffset = rowTop - (viewportExtent - rowHeight) / 2.0;
    } else if (rowTop < position.pixels) {
      targetOffset = rowTop;
    } else if (rowBottom > position.pixels + viewportExtent) {
      targetOffset = rowBottom - viewportExtent;
    } else {
      return;
    }
    _menuScrollController.jumpTo(
      targetOffset.clamp(0.0, position.maxScrollExtent),
    );
  }

  /// Invokes `onChanged` for enabled segment at [index] when value changes and closes restoring focus.
  void _selectIndex(int index) {
    if (index < 0 || index >= widget.segments.length) {
      return;
    }
    final segment = widget.segments[index];
    if (!segment.enabled) {
      return;
    }
    if (segment.value != widget.value) {
      widget.onChanged?.call(segment.value);
    }
    _closeMenu(restoreFocus: true);
  }

  /// Steps [_highlightedIndex] by [delta] (`+1` or `-1`) across enabled options.
  void _stepHighlight(int delta) {
    final nextIndex = _findNextEnabledSegmentIndex(
      widget.segments,
      _highlightedIndex,
      delta,
    );
    if (nextIndex == null) {
      return;
    }
    setState(() {
      _highlightedIndex = nextIndex;
      _hasKeyboardHighlight = true;
    });
    _scrollIndexIntoView(nextIndex, center: false);
  }

  /// Toggles the vertical popup menu open or closed.
  void _toggleMenu({required bool viaKeyboard}) {
    if (_isMenuOpen) {
      _closeMenu(restoreFocus: true);
      return;
    }
    _openMenu(viaKeyboard: viaKeyboard);
  }
}

/// Interactive flat combobox trigger wiring focus, keyboard shortcuts, and pointer taps.
class _UiVerticalTrigger extends StatelessWidget {
  /// Creates a [_UiVerticalTrigger].
  const _UiVerticalTrigger({
    required this.semanticLabel,
    required this.valueLabel,
    required this.enabled,
    required this.focusNode,
    required this.onKeyEvent,
    required this.onFocusChange,
    required this.onShowFocusHighlight,
    required this.onShowHoverHighlight,
    required this.onActivateAction,
    required this.onTap,
    required this.child,
  });

  /// Visual trigger box wrapped by focus and gesture detectors.
  final Widget child;

  /// Whether the trigger is enabled.
  final bool enabled;

  /// Trigger focus node.
  final FocusNode focusNode;

  /// Semantic activation handler for accessibility actions.
  final VoidCallback onActivateAction;

  /// Callback notified when focus changes.
  final ValueChanged<bool> onFocusChange;

  /// Keyboard handler intercepting `Enter`, `Space`, arrows, `Home`, `End`, and `Escape`.
  final FocusOnKeyEventCallback onKeyEvent;

  /// Callback notified when focus ring highlight changes.
  final ValueChanged<bool> onShowFocusHighlight;

  /// Callback notified when hover highlight changes.
  final ValueChanged<bool> onShowHoverHighlight;

  /// Tap callback toggling the vertical popup.
  final VoidCallback? onTap;

  /// Optional accessible group label.
  final String? semanticLabel;

  /// Current selected or hint label announced as semantic value.
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      value: valueLabel,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: onKeyEvent,
        child: FocusableActionDetector(
          focusNode: focusNode,
          enabled: enabled,
          mouseCursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.forbidden,
          onFocusChange: onFocusChange,
          onShowFocusHighlight: onShowFocusHighlight,
          onShowHoverHighlight: onShowHoverHighlight,
          actions: _buildActions(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: child,
          ),
        ),
      ),
    );
  }

  /// Builds semantic activation actions without intercepting custom keyboard shortcuts.
  Map<Type, Action<Intent>> _buildActions() {
    return <Type, Action<Intent>>{
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          onActivateAction();
          return null;
        },
      ),
      ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
        onInvoke: (_) {
          onActivateAction();
          return null;
        },
      ),
    };
  }
}

/// Visual bordered trigger container applying surface alternation (`U-SURFACE-003`) and focus ring (`U-A11Y-001`).
class _UiVerticalTriggerBox extends StatelessWidget {
  /// Creates a [_UiVerticalTriggerBox].
  const _UiVerticalTriggerBox({
    required this.triggerKey,
    required this.enabled,
    required this.applyDisabledOpacity,
    required this.hasError,
    required this.isHighlighted,
    required this.showFocusRing,
    required this.minHeight,
    required this.borderRadius,
    required this.child,
  });

  /// Applies `disabledOpacity` internally when disabled.
  final bool applyDisabledOpacity;

  /// Optional corner radius overriding `tokens.radii.md`.
  final double? borderRadius;

  /// Interior trigger label and chevron row.
  final Widget child;

  /// Whether the trigger is enabled.
  final bool enabled;

  /// Renders `danger` border color when true.
  final bool hasError;

  /// Whether border uses `accent` (hover, focus, or open menu).
  final bool isHighlighted;

  /// Optional minimum height overriding `tokens.spacing.touchTarget`.
  final double? minHeight;

  /// Whether the outer keyboard focus ring is visible.
  final bool showFocusRing;

  /// Key used by parent state to measure trigger screen coordinates.
  final GlobalKey triggerKey;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final fillColor = UiSurfaceScope.of(context) == UiSurfaceLevel.insetWell
        ? colors.panel
        : colors.bg;
    final resolvedRadius = borderRadius ?? tokens.radii.md;
    final borderColor = hasError
        ? colors.danger
        : (isHighlighted ? colors.accent : colors.line);

    return Opacity(
      opacity: (!applyDisabledOpacity || enabled)
          ? 1.0
          : tokens.focus.disabledOpacity,
      child: _UiSegmentFocusRing(
        visible: showFocusRing,
        radius: resolvedRadius,
        child: AnimatedContainer(
          key: triggerKey,
          duration: tokens.focus.hoverDuration,
          constraints: BoxConstraints(
            minHeight: minHeight ?? tokens.spacing.touchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(resolvedRadius),
            border: Border.all(
              color: borderColor,
              width: tokens.radii.borderWidth,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Adapts vertical trigger interior layout between unbounded desktop rows and tight full-width containers.
class _UiVerticalTriggerContent extends StatelessWidget {
  /// Creates a [_UiVerticalTriggerContent].
  const _UiVerticalTriggerContent({
    required this.label,
    required this.hasSelectedValue,
    required this.icon,
    required this.iconUsesMutedTint,
    required this.isMenuOpen,
    required this.textStyle,
    required this.chevronTurns,
  });

  /// Animation rotating the trailing chevron (`0.0 -> 0.5`).
  final Animation<double> chevronTurns;

  /// Distinguishes active selection (`ink`) from placeholder hint (`muted`).
  final bool hasSelectedValue;

  /// Optional leading icon glyph.
  final IconData? icon;

  /// Tints [icon] in `muted` when displaying a field-level icon.
  final bool iconUsesMutedTint;

  /// Whether the popup menu is currently open.
  final bool isMenuOpen;

  /// Currently selected label or placeholder hint text.
  final String label;

  /// Optional explicit trigger typography override.
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final resolvedStyle =
        (textStyle ??
                tokens.typography.meta.copyWith(fontWeight: FontWeight.w500))
            .copyWith(color: hasSelectedValue ? colors.ink : colors.muted);
    final chevron = ExcludeSemantics(
      child: RotationTransition(
        turns: chevronTurns,
        child: Icon(
          Icons.keyboard_arrow_down_rounded,
          size: tokens.spacing.iconSm,
          color: isMenuOpen ? colors.accent : colors.muted,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedWidth = constraints.hasBoundedWidth;
        final labelText = Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: resolvedStyle,
        );
        final leading = Padding(
          padding: const EdgeInsets.only(right: 6.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon case final glyph?) ...<Widget>[
                ExcludeSemantics(
                  child: Icon(
                    glyph,
                    size: iconUsesMutedTint
                        ? tokens.spacing.iconSm
                        : tokens.spacing.iconXs,
                    color: iconUsesMutedTint ? colors.muted : colors.ink,
                  ),
                ),
                const SizedBox(width: 6.0),
              ],
              if (hasBoundedWidth) Flexible(child: labelText) else labelText,
            ],
          ),
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: hasBoundedWidth
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.start,
          children: <Widget>[
            if (hasBoundedWidth) Flexible(child: leading) else leading,
            chevron,
          ],
        );
      },
    );
  }
}

/// Finds the first or last enabled segment index in [segments] for `Home` and `End` navigation.
int? _findBoundaryEnabledSegmentIndex<T>(
  List<UiSegment<T>> segments, {
  required bool fromEnd,
}) {
  if (segments.isEmpty) {
    return null;
  }
  if (fromEnd) {
    for (var i = segments.length - 1; i >= 0; i--) {
      if (segments[i].enabled) {
        return i;
      }
    }
    return null;
  }
  for (var i = 0; i < segments.length; i++) {
    if (segments[i].enabled) {
      return i;
    }
  }
  return null;
}

/// Finds the next enabled segment index stepping cyclically by [delta] (`+1` or `-1`) from [currentIndex].
int? _findNextEnabledSegmentIndex<T>(
  List<UiSegment<T>> segments,
  int currentIndex,
  int delta,
) {
  final count = segments.length;
  if (count == 0) {
    return null;
  }
  for (var offset = 1; offset <= count; offset++) {
    final candidateIndex = (currentIndex + delta * offset) % count;
    final normalizedIndex = candidateIndex < 0
        ? candidateIndex + count
        : candidateIndex;
    if (segments[normalizedIndex].enabled) {
      return normalizedIndex;
    }
  }
  return null;
}

/// Computes the intrinsic width needed to display [segment] cleanly inside a popup option row.
double _measureSegmentOptionWidth<T>({
  required UiSegment<T> segment,
  required UiThemeTokens tokens,
  required TextStyle labelStyle,
  required TextDirection textDirection,
  required TextScaler textScaler,
}) {
  final painter = TextPainter(
    text: TextSpan(text: segment.label, style: labelStyle),
    maxLines: 1,
    textDirection: textDirection,
    textScaler: textScaler,
  )..layout();
  final labelWidth = painter.width.ceilToDouble();
  painter.dispose();

  final iconWidth = segment.icon != null ? tokens.spacing.iconXs + 6.0 : 0.0;
  final checkWidth = tokens.spacing.iconXs + 8.0;
  final rowChromeWidth =
      20.0 + (_popupInnerPadding * 2.0) + (tokens.radii.borderWidth * 4.0);
  return labelWidth + iconWidth + checkWidth + rowChromeWidth;
}

/// Clamps horizontal follower offset so the vertical popup stays within viewport safe margins.
double _resolveHorizontalOffset({
  required double triggerLeft,
  required double popupWidth,
  required double viewportWidth,
  required EdgeInsets mediaPadding,
}) {
  final leftLimit = mediaPadding.left + _popupViewportMargin;
  final rightLimit = viewportWidth - mediaPadding.right - _popupViewportMargin;
  var offsetX = 0.0;
  if (triggerLeft + popupWidth > rightLimit) {
    offsetX = rightLimit - (triggerLeft + popupWidth);
  }
  if (triggerLeft + offsetX < leftLimit) {
    offsetX = leftLimit - triggerLeft;
  }
  return offsetX;
}
