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

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../tokens/ui_theme_tokens.dart';

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

/// Equal-width horizontal segmented control in a `bg` trough (`U-COMP-002`, replaces Switch widgets).
class UiSegmentedControl<T> extends StatefulWidget {
  /// Creates a [UiSegmentedControl].
  const UiSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.semanticLabel,
  });

  /// Whether the entire segmented control is interactive.
  final bool enabled;

  /// Selection callback invoked when a segment is chosen by tap or arrow key.
  final ValueChanged<T>? onChanged;

  /// Optional accessible group label.
  final String? semanticLabel;

  /// Ordered equal-width segments displayed horizontally.
  final List<UiSegment<T>> segments;

  /// Currently selected segment value.
  final T value;

  @override
  State<UiSegmentedControl<T>> createState() => _UiSegmentedControlState<T>();
}

/// Manages per-segment [FocusNode]s and `ArrowLeft`/`ArrowRight` stepping for [UiSegmentedControl].
class _UiSegmentedControlState<T> extends State<UiSegmentedControl<T>> {
  /// Per-segment focus nodes synchronized with `widget.segments.length`.
  final List<FocusNode> _focusNodes = <FocusNode>[];

  @override
  void initState() {
    super.initState();
    _syncFocusNodes();
  }

  @override
  void didUpdateWidget(covariant UiSegmentedControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segments.length != widget.segments.length) {
      _syncFocusNodes();
    }
  }

  @override
  void dispose() {
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

    final children = <Widget>[];
    for (var i = 0; i < widget.segments.length; i++) {
      if (i > 0) {
        children.add(const SizedBox(width: 4.0));
      }
      final segment = widget.segments[i];
      final isSelected = segment.value == widget.value;
      final segmentEnabled = controlEnabled && segment.enabled;
      children.add(
        Expanded(
          child: _UiSegmentTab(
            label: segment.label,
            icon: segment.icon,
            isSelected: isSelected,
            enabled: segmentEnabled,
            focusNode: _focusNodes[i],
            onTap: segmentEnabled
                ? () {
                    _focusNodes[i].requestFocus();
                    widget.onChanged?.call(segment.value);
                  }
                : null,
            onStepPrevious: segmentEnabled ? () => _stepSelection(i, -1) : null,
            onStepNext: segmentEnabled ? () => _stepSelection(i, 1) : null,
          ),
        ),
      );
    }

    Widget trough = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(tokens.radii.md),
        border: Border.all(color: colors.line, width: tokens.radii.borderWidth),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3.0),
        child: Row(children: children),
      ),
    );

    if (!controlEnabled) {
      trough = Opacity(opacity: tokens.focus.disabledOpacity, child: trough);
    }
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      child: trough,
    );
  }

  /// Steps selection and focus by [delta] (`-1` or `+1`) to the next enabled segment.
  void _stepSelection(int currentIndex, int delta) {
    final count = widget.segments.length;
    if (count == 0) {
      return;
    }
    for (var offset = 1; offset <= count; offset++) {
      final candidateIndex = (currentIndex + delta * offset) % count;
      final normalizedIndex = candidateIndex < 0
          ? candidateIndex + count
          : candidateIndex;
      final candidate = widget.segments[normalizedIndex];
      if (!candidate.enabled) {
        continue;
      }
      _focusNodes[normalizedIndex].requestFocus();
      widget.onChanged?.call(candidate.value);
      return;
    }
  }

  /// Keeps [_focusNodes] length matched to `widget.segments.length` without leaking nodes.
  void _syncFocusNodes() {
    while (_focusNodes.length < widget.segments.length) {
      _focusNodes.add(FocusNode());
    }
    while (_focusNodes.length > widget.segments.length) {
      _focusNodes.removeLast().dispose();
    }
  }
}

/// Private intent triggered by `ArrowLeft` inside [UiSegmentedControl].
class _StepPreviousSegmentIntent extends Intent {
  /// Creates a [_StepPreviousSegmentIntent].
  const _StepPreviousSegmentIntent();
}

/// Private intent triggered by `ArrowRight` inside [UiSegmentedControl].
class _StepNextSegmentIntent extends Intent {
  /// Creates a [_StepNextSegmentIntent].
  const _StepNextSegmentIntent();
}

/// Individual focusable tab cell inside [UiSegmentedControl].
class _UiSegmentTab extends StatefulWidget {
  /// Creates a [_UiSegmentTab].
  const _UiSegmentTab({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.enabled,
    required this.focusNode,
    required this.onTap,
    required this.onStepPrevious,
    required this.onStepNext,
  });

  /// Whether this segment can be interacted with.
  final bool enabled;

  /// Focus node owned by parent [UiSegmentedControl].
  final FocusNode focusNode;

  /// Optional leading icon glyph.
  final IconData? icon;

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
  /// Whether keyboard focus ring is visible.
  bool _showFocusRing = false;

  /// Whether pointer is hovering this tab.
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final foreground = widget.isSelected
        ? colors.accent
        : (_isHovered && widget.enabled ? colors.ink : colors.muted);
    final radius = tokens.radii.tag;

    Widget tab = AnimatedContainer(
      duration: tokens.focus.hoverDuration,
      constraints: BoxConstraints(
        minHeight: tokens.spacing.chromeControlHeight,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: widget.isSelected ? colors.panel : Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: widget.isSelected ? tokens.focus.segmentedShadow : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.icon case final glyph?) ...<Widget>[
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
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.typography.meta.copyWith(
                color: foreground,
                fontWeight: widget.isSelected
                    ? FontWeight.w600
                    : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );

    if (_showFocusRing && widget.enabled) {
      final ringInset = tokens.focus.ringOffset + tokens.focus.ringWidth;
      tab = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          tab,
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
                    color: colors.accent,
                    width: tokens.focus.ringWidth,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (!widget.enabled) {
      tab = Opacity(opacity: tokens.focus.disabledOpacity, child: tab);
    }

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
        actions: <Type, Action<Intent>>{
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
          _StepPreviousSegmentIntent:
              CallbackAction<_StepPreviousSegmentIntent>(
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
        },
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
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: tab,
        ),
      ),
    );
  }
}
