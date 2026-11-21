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
import '../primitives/ui_pill.dart';
import '../tokens/ui_breakpoints.dart';
import '../tokens/ui_theme_tokens.dart';

/// Shared page header with optional back link, `28px` title, inline active-label filter, count pill, trailing actions, and `58ch` subtitle (`U-LAYOUT-004`).
class UiPageHeader extends StatelessWidget {
  /// Creates a [UiPageHeader].
  const UiPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.countLabel,
    this.activeFilterLabel,
    this.activeFilterTooltip,
    this.onClearActiveFilter,
    this.showInlineFilterOnCompact = false,
    this.backLabel,
    this.onBack,
    this.trailing,
  });

  /// Optional active-label name rendered inline inside the heading row (`U-LAYOUT-004`).
  final String? activeFilterLabel;

  /// Accessible tooltip explaining click-to-clear behavior on [activeFilterLabel].
  final String? activeFilterTooltip;

  /// Optional context-preserving back button copy (e.g. `Back to tasks`).
  final String? backLabel;

  /// Optional right-aligned tabular count capsule (e.g. `2 / 3`).
  final String? countLabel;

  /// Callback invoked when tapping [backLabel].
  final VoidCallback? onBack;

  /// Callback invoked when tapping [activeFilterLabel] to clear the active filter.
  final VoidCallback? onClearActiveFilter;

  /// Shows [activeFilterLabel] inline on `compact` viewports (used by Compact Search view).
  final bool showInlineFilterOnCompact;

  /// Optional muted explanatory subtitle constrained to ~`58ch` (`420px`).
  final String? subtitle;

  /// Primary `28px` view title.
  final String title;

  /// Optional trailing action widget cluster.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final isCompact = UiBreakpoints.isCompact(MediaQuery.sizeOf(context).width);
    final showInlineFilter =
        activeFilterLabel != null && (!isCompact || showInlineFilterOnCompact);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (backLabel != null && onBack != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: UiButton(
                label: backLabel,
                leadingIcon: Icons.arrow_back_rounded,
                variant: UiButtonVariant.text,
                density: UiButtonDensity.dense,
                onPressed: onBack,
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.typography.pageTitle.copyWith(
                        color: colors.ink,
                      ),
                    ),
                  ),
                  if (showInlineFilter) ...<Widget>[
                    const SizedBox(width: 14.0),
                    Flexible(
                      child: _UiInlineFilterButton(
                        label: activeFilterLabel ?? '',
                        tooltip: activeFilterTooltip,
                        onPressed: onClearActiveFilter,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (countLabel != null || trailing != null)
              const SizedBox(width: 10.0),
            if (countLabel case final count?)
              UiPill(label: count, variant: UiPillVariant.count),
            if (countLabel != null && trailing != null)
              const SizedBox(width: 10.0),
            ?trailing,
          ],
        ),
        if (subtitle case final sub?)
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420.0),
              child: Text(
                sub,
                style: tokens.typography.meta.copyWith(color: colors.muted),
              ),
            ),
          ),
      ],
    );
  }
}

/// Clickable ellipsized inline active-label filter rendered inside [UiPageHeader].
class _UiInlineFilterButton extends StatefulWidget {
  /// Creates a [_UiInlineFilterButton].
  const _UiInlineFilterButton({
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  /// Active label name.
  final String label;

  /// Click-to-clear callback.
  final VoidCallback? onPressed;

  /// Accessible tooltip text.
  final String? tooltip;

  @override
  State<_UiInlineFilterButton> createState() => _UiInlineFilterButtonState();
}

/// Manages hover color shift and keyboard focus ring for [_UiInlineFilterButton].
class _UiInlineFilterButtonState extends State<_UiInlineFilterButton> {
  /// Whether the pointer hovers the label text.
  bool _hovered = false;

  /// Whether keyboard focus ring is visible.
  bool _showFocusRing = false;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final enabled = widget.onPressed != null;

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
      child: Text(
        widget.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tokens.typography.brand.copyWith(
          color: _hovered && enabled ? colors.ink : colors.muted,
          letterSpacing: -0.25,
        ),
      ),
    );

    final ringInset = tokens.focus.ringOffset + tokens.focus.ringWidth;
    content = Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: <Widget>[
        content,
        if (_showFocusRing && enabled)
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

    final interactive = Semantics(
      button: enabled,
      label: widget.tooltip ?? widget.label,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (hovered) {
          if (_hovered != hovered) {
            setState(() => _hovered = hovered);
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
          onTap: widget.onPressed,
          child: content,
        ),
      ),
    );

    if (widget.tooltip case final tip?) {
      return Tooltip(message: tip, child: interactive);
    }
    return interactive;
  }
}
