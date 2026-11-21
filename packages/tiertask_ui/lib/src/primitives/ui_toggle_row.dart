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

/// Labeled checkbox row with optional muted description (`U-COMP-002`; replaces Switch widgets).
class UiToggleRow extends StatefulWidget {
  /// Creates a [UiToggleRow].
  const UiToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
    this.isDense = false,
    this.enabled = true,
    this.focusNode,
    this.semanticLabel,
  });

  /// Optional muted explanatory text rendered below [label].
  final String? description;

  /// Whether the toggle row accepts interaction (`0.48` opacity when false).
  final bool enabled;

  /// Optional caller-owned [FocusNode].
  final FocusNode? focusNode;

  /// Uses compact `30px` row height and `16x16px` checkbox when true.
  final bool isDense;

  /// Primary caller-supplied checkbox label.
  final String label;

  /// Callback invoked with the toggled boolean value.
  final ValueChanged<bool>? onChanged;

  /// Optional explicit accessible name overriding [label].
  final String? semanticLabel;

  /// Current checked state.
  final bool value;

  @override
  State<UiToggleRow> createState() => _UiToggleRowState();
}

/// Manages keyboard focus-ring highlight for [UiToggleRow].
class _UiToggleRowState extends State<UiToggleRow> {
  /// Whether the keyboard focus ring is currently visible.
  bool _showFocusRing = false;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final surfaceLevel = UiSurfaceScope.of(context);
    final isInteractive = widget.enabled && widget.onChanged != null;
    final boxSize = widget.isDense ? 16.0 : 17.0;
    final minHeight = widget.isDense
        ? tokens.spacing.buttonDenseHeight
        : tokens.spacing.touchTarget;
    final uncheckedFill = surfaceLevel == UiSurfaceLevel.insetWell
        ? colors.panel
        : colors.bg;

    Widget row = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: EdgeInsets.symmetric(
        horizontal: 4.0,
        vertical: widget.isDense ? 4.0 : 6.0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2.0),
            child: AnimatedContainer(
              duration: tokens.focus.hoverDuration,
              width: boxSize,
              height: boxSize,
              decoration: BoxDecoration(
                color: widget.value ? colors.accent : uncheckedFill,
                borderRadius: BorderRadius.circular(tokens.radii.dotLg),
                border: Border.all(
                  color: widget.value ? colors.accent : colors.line,
                  width: tokens.radii.borderWidth,
                ),
              ),
              child: widget.value
                  ? Icon(
                      Icons.check_rounded,
                      size: boxSize - 4.0,
                      color: colors.onAccent,
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 9.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  widget.label,
                  style: tokens.typography.control.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (widget.description case final desc?) ...<Widget>[
                  const SizedBox(height: 3.0),
                  Text(
                    desc,
                    style: tokens.typography.meta.copyWith(color: colors.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (_showFocusRing && isInteractive) {
      final ringInset = tokens.focus.ringOffset + tokens.focus.ringWidth;
      row = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          row,
          Positioned.fill(
            left: -ringInset,
            top: -ringInset,
            right: -ringInset,
            bottom: -ringInset,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(tokens.radii.sm),
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

    return Semantics(
      checked: widget.value,
      enabled: isInteractive,
      label: widget.semanticLabel ?? widget.label,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        enabled: isInteractive,
        mouseCursor: isInteractive
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onShowFocusHighlight: (focused) {
          if (_showFocusRing != focused) {
            setState(() => _showFocusRing = focused);
          }
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onChanged?.call(!widget.value);
              return null;
            },
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) {
              widget.onChanged?.call(!widget.value);
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isInteractive
              ? () => widget.onChanged?.call(!widget.value)
              : null,
          child: Opacity(
            opacity: isInteractive ? 1.0 : tokens.focus.disabledOpacity,
            child: row,
          ),
        ),
      ),
    );
  }
}
