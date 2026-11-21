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
import '../tokens/ui_typography_tokens.dart';
import 'ui_button.dart';

/// Structural feedback role for [UiBanner] (`U-COMP-002`, `U-UX-004`..`007`).
enum UiBannerVariant {
  /// Top-of-view status, sync, conflict, or limit banner (`0` to `2` action buttons).
  status,

  /// Floating bottom Undo / confirmation toast (`maxWidth: 620px`, `toastShadow`).
  toast,

  /// Compact inline warning notice inside an expanded card section.
  inlineWarning,

  /// Inline destructive confirmation bar (`Keep` / `Yes, delete`).
  inlineConfirm,

  /// Plain-text empty state with zero decorative illustrations.
  emptyState,

  /// Centered initial loading spinner (`32px`, `850ms`, `2.5px` stroke).
  loadingState,

  /// Centered full-screen file-read error view (`34px` hero icon + diagnostics slot).
  fullError,
}

/// Semantic surface tone triple for [UiBanner] (`U-SURFACE-004`).
enum UiBannerTone {
  /// Neutral `panel` / `line` / `ink` surface.
  neutral,

  /// Warning triple (`warningBg` / `warningBorder` / `warning`).
  warning,

  /// Danger triple (`dangerBg` / `dangerBorder` / `danger`).
  danger,

  /// Success triple (`successBg` / `successBorder` / `success`).
  success,
}

/// Unified status banner, floating toast, inline warning/confirm, empty, loading, and full-error primitive.
class UiBanner extends StatelessWidget {
  /// Creates a [UiBanner].
  const UiBanner({
    super.key,
    required this.variant,
    required this.message,
    this.tone = UiBannerTone.neutral,
    this.title,
    this.sublines = const <String>[],
    this.icon,
    this.actions = const <Widget>[],
    this.onDismiss,
    this.dismissTooltip,
    this.actionLabel,
    this.onAction,
    this.kbdHint,
    this.cancelLabel,
    this.onCancel,
    this.confirmLabel,
    this.onConfirm,
    this.isDestructive = true,
    this.detailsChild,
  });

  /// Primary toast action button label (e.g. `Undo`).
  final String? actionLabel;

  /// Optional action buttons for `status` (`0` to `2`) and `fullError`.
  final List<Widget> actions;

  /// Cancel button label for `inlineConfirm`.
  final String? cancelLabel;

  /// Confirm button label for `inlineConfirm`.
  final String? confirmLabel;

  /// Optional structured diagnostics widget rendered inside `fullError`.
  final Widget? detailsChild;

  /// Tooltip for optional dismiss `x` button (`status`, `toast`).
  final String? dismissTooltip;

  /// Optional leading icon glyph overriding the tone default.
  final IconData? icon;

  /// Applies danger styling to `inlineConfirm` when true.
  final bool isDestructive;

  /// Optional monospace keyboard shortcut hint on `toast` (auto-hidden on `compact`).
  final String? kbdHint;

  /// Primary message text.
  final String message;

  /// Callback for [actionLabel] on `toast`.
  final VoidCallback? onAction;

  /// Callback for [cancelLabel] on `inlineConfirm`.
  final VoidCallback? onCancel;

  /// Callback for [confirmLabel] on `inlineConfirm`.
  final VoidCallback? onConfirm;

  /// Optional dismiss callback (`status`, `toast`).
  final VoidCallback? onDismiss;

  /// Optional secondary detail lines rendered inside `status`.
  final List<String> sublines;

  /// Optional bold heading (`status`, `loadingState`, `fullError`).
  final String? title;

  /// Semantic surface tone.
  final UiBannerTone tone;

  /// Structural banner variant.
  final UiBannerVariant variant;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final palette = _resolveTonePalette(tokens, tone);
    return switch (variant) {
      UiBannerVariant.status => _UiStatusBanner(
        title: title,
        message: message,
        sublines: sublines,
        icon: icon ?? _defaultToneIcon(tone),
        palette: palette,
        actions: actions,
        onDismiss: onDismiss,
        dismissTooltip: dismissTooltip,
      ),
      UiBannerVariant.toast => _UiToastBanner(
        message: message,
        icon: icon,
        palette: palette,
        actionLabel: actionLabel,
        onAction: onAction,
        kbdHint: kbdHint,
        onDismiss: onDismiss,
        dismissTooltip: dismissTooltip,
      ),
      UiBannerVariant.inlineWarning => _UiInlineWarningBanner(
        message: message,
        icon: icon ?? Icons.warning_amber_rounded,
        palette: tone == UiBannerTone.neutral
            ? _resolveTonePalette(tokens, UiBannerTone.warning)
            : palette,
      ),
      UiBannerVariant.inlineConfirm => _UiInlineConfirmBanner(
        message: message,
        cancelLabel: cancelLabel,
        onCancel: onCancel,
        confirmLabel: confirmLabel,
        onConfirm: onConfirm,
        isDestructive: isDestructive,
      ),
      UiBannerVariant.emptyState => _UiEmptyStateBanner(message: message),
      UiBannerVariant.loadingState => _UiLoadingStateBanner(
        title: title,
        message: message,
      ),
      UiBannerVariant.fullError => _UiFullErrorBanner(
        title: title,
        message: message,
        icon: icon ?? Icons.cloud_off_outlined,
        detailsChild: detailsChild,
        actions: actions,
      ),
    };
  }

  /// Resolves default leading icon for status banners when caller omits [icon].
  static IconData _defaultToneIcon(UiBannerTone tone) {
    return switch (tone) {
      UiBannerTone.neutral => Icons.info_outline_rounded,
      UiBannerTone.warning => Icons.warning_amber_rounded,
      UiBannerTone.danger => Icons.error_outline_rounded,
      UiBannerTone.success => Icons.check_circle_outline_rounded,
    };
  }

  /// Resolves semantic surface triple for [tone].
  static _UiBannerPalette _resolveTonePalette(
    UiThemeTokens tokens,
    UiBannerTone tone,
  ) {
    final colors = tokens.colors;
    return switch (tone) {
      UiBannerTone.neutral => _UiBannerPalette(
        background: colors.panel,
        border: colors.line,
        foreground: colors.ink,
      ),
      UiBannerTone.warning => _UiBannerPalette(
        background: colors.warningBg,
        border: colors.warningBorder,
        foreground: colors.warning,
      ),
      UiBannerTone.danger => _UiBannerPalette(
        background: colors.dangerBg,
        border: colors.dangerBorder,
        foreground: colors.danger,
      ),
      UiBannerTone.success => _UiBannerPalette(
        background: colors.successBg,
        border: colors.successBorder,
        foreground: colors.success,
      ),
    };
  }
}

/// Resolved semantic surface triple for [UiBanner].
@immutable
class _UiBannerPalette {
  /// Creates a [_UiBannerPalette].
  const _UiBannerPalette({
    required this.background,
    required this.border,
    required this.foreground,
  });

  /// Banner fill color.
  final Color background;

  /// Hairline `1px` border color.
  final Color border;

  /// Icon and text foreground color.
  final Color foreground;
}

/// Top-of-view flat status banner supporting `0..2` actions and sublines.
class _UiStatusBanner extends StatelessWidget {
  /// Creates a [_UiStatusBanner].
  const _UiStatusBanner({
    required this.title,
    required this.message,
    required this.sublines,
    required this.icon,
    required this.palette,
    required this.actions,
    required this.onDismiss,
    required this.dismissTooltip,
  });

  /// Action widgets rendered trailing.
  final List<Widget> actions;

  /// Dismiss button tooltip.
  final String? dismissTooltip;

  /// Leading status icon.
  final IconData icon;

  /// Primary message text.
  final String message;

  /// Optional dismiss callback.
  final VoidCallback? onDismiss;

  /// Tone surface palette.
  final _UiBannerPalette palette;

  /// Secondary detail lines.
  final List<String> sublines;

  /// Optional bold title.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(tokens.radii.row),
          border: Border.all(
            color: palette.border,
            width: tokens.radii.borderWidth,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13.0, vertical: 10.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: ExcludeSemantics(
                  child: Icon(
                    icon,
                    size: tokens.spacing.iconSm,
                    color: palette.foreground,
                  ),
                ),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (title case final heading?)
                      Text(
                        heading,
                        style: tokens.typography.meta.copyWith(
                          color: palette.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    Text(
                      message,
                      style: tokens.typography.meta.copyWith(
                        color: palette.foreground,
                      ),
                    ),
                    for (final line in sublines)
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Text(
                          line,
                          style: tokens.typography.eyebrow.copyWith(
                            color: palette.foreground,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.0,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (actions.isNotEmpty) ...<Widget>[
                const SizedBox(width: 8.0),
                Wrap(spacing: 6.0, runSpacing: 6.0, children: actions),
              ],
              if (onDismiss != null) ...<Widget>[
                const SizedBox(width: 4.0),
                UiButton(
                  leadingIcon: Icons.close_rounded,
                  variant: UiButtonVariant.icon,
                  density: UiButtonDensity.dense,
                  tooltip: dismissTooltip,
                  onPressed: onDismiss,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating bottom Undo / confirmation toast constrained to `620px` max width (`U-UX-004`).
class _UiToastBanner extends StatelessWidget {
  /// Creates a [_UiToastBanner].
  const _UiToastBanner({
    required this.message,
    required this.icon,
    required this.palette,
    required this.actionLabel,
    required this.onAction,
    required this.kbdHint,
    required this.onDismiss,
    required this.dismissTooltip,
  });

  /// Optional toast action label (e.g. `Undo`).
  final String? actionLabel;

  /// Dismiss button tooltip.
  final String? dismissTooltip;

  /// Optional leading icon.
  final IconData? icon;

  /// Optional monospace keyboard shortcut hint (auto-hidden on `compact`).
  final String? kbdHint;

  /// Toast message copy.
  final String message;

  /// Action callback.
  final VoidCallback? onAction;

  /// Dismiss callback.
  final VoidCallback? onDismiss;

  /// Tone surface palette.
  final _UiBannerPalette palette;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final isCompact = UiBreakpoints.isCompact(MediaQuery.sizeOf(context).width);

    return Semantics(
      liveRegion: true,
      container: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(tokens.radii.row),
            border: Border.all(
              color: palette.border,
              width: tokens.radii.borderWidth,
            ),
            boxShadow: tokens.focus.toastShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 13.0,
              vertical: 9.0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon case final glyph?) ...<Widget>[
                  ExcludeSemantics(
                    child: Icon(
                      glyph,
                      size: tokens.spacing.iconSm,
                      color: palette.foreground,
                    ),
                  ),
                  const SizedBox(width: 8.0),
                ],
                Flexible(
                  child: Text(
                    message,
                    style: tokens.typography.meta.copyWith(
                      color: palette.foreground,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (actionLabel != null && onAction != null) ...<Widget>[
                  const SizedBox(width: 10.0),
                  UiButton(
                    label: actionLabel,
                    variant: UiButtonVariant.secondary,
                    density: UiButtonDensity.dense,
                    isActive: true,
                    onPressed: onAction,
                  ),
                  if (!isCompact && kbdHint != null) ...<Widget>[
                    const SizedBox(width: 6.0),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.bg,
                        borderRadius: BorderRadius.circular(tokens.radii.dotLg),
                        border: Border.all(
                          color: colors.line,
                          width: tokens.radii.borderWidth,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6.0,
                          vertical: 2.0,
                        ),
                        child: Text(
                          kbdHint ?? '',
                          style: UiTypographyTokens.mono(
                            tokens.typography.micro.copyWith(
                              color: colors.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
                if (onDismiss != null) ...<Widget>[
                  const SizedBox(width: 6.0),
                  UiButton(
                    leadingIcon: Icons.close_rounded,
                    variant: UiButtonVariant.icon,
                    density: UiButtonDensity.dense,
                    tooltip: dismissTooltip,
                    onPressed: onDismiss,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact inline warning box inside cards.
class _UiInlineWarningBanner extends StatelessWidget {
  /// Creates a [_UiInlineWarningBanner].
  const _UiInlineWarningBanner({
    required this.message,
    required this.icon,
    required this.palette,
  });

  /// Leading warning icon.
  final IconData icon;

  /// Warning text.
  final String message;

  /// Semantic surface triple.
  final _UiBannerPalette palette;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(tokens.radii.md),
        border: Border.all(
          color: palette.border,
          width: tokens.radii.borderWidth,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
        child: Row(
          children: <Widget>[
            ExcludeSemantics(
              child: Icon(
                icon,
                size: tokens.spacing.iconSm,
                color: palette.foreground,
              ),
            ),
            const SizedBox(width: 8.0),
            Expanded(
              child: Text(
                message,
                style: tokens.typography.meta.copyWith(
                  color: palette.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline in-place destructive confirmation bar (`U-UX-005`).
class _UiInlineConfirmBanner extends StatelessWidget {
  /// Creates a [_UiInlineConfirmBanner].
  const _UiInlineConfirmBanner({
    required this.message,
    required this.cancelLabel,
    required this.onCancel,
    required this.confirmLabel,
    required this.onConfirm,
    required this.isDestructive,
  });

  /// Cancel button copy.
  final String? cancelLabel;

  /// Confirm button copy.
  final String? confirmLabel;

  /// Selects danger vs warning styling.
  final bool isDestructive;

  /// Prompt copy.
  final String message;

  /// Cancel callback.
  final VoidCallback? onCancel;

  /// Confirm callback.
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final bg = isDestructive ? colors.dangerBg : colors.warningBg;
    final border = isDestructive ? colors.dangerBorder : colors.warningBorder;
    final fg = isDestructive ? colors.danger : colors.warning;

    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(tokens.radii.md),
          border: Border.all(color: border, width: tokens.radii.borderWidth),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 7.0),
          child: Wrap(
            spacing: 8.0,
            runSpacing: 6.0,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: <Widget>[
              Text(
                message,
                style: tokens.typography.meta.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (cancelLabel case final cancel?)
                    UiButton(
                      label: cancel,
                      variant: UiButtonVariant.secondary,
                      density: UiButtonDensity.compact,
                      onPressed: onCancel,
                    ),
                  if (cancelLabel != null && confirmLabel != null)
                    const SizedBox(width: 6.0),
                  if (confirmLabel case final confirm?)
                    UiButton(
                      label: confirm,
                      variant: isDestructive
                          ? UiButtonVariant.danger
                          : UiButtonVariant.primary,
                      density: UiButtonDensity.compact,
                      onPressed: onConfirm,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Plain-text empty state free of decorative graphics (`U-COMP-002`).
class _UiEmptyStateBanner extends StatelessWidget {
  /// Creates a [_UiEmptyStateBanner].
  const _UiEmptyStateBanner({required this.message});

  /// Muted empty-state message.
  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28.0, horizontal: 16.0),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: tokens.typography.control.copyWith(
            color: tokens.colors.muted,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// Centered initial loading state with `32px` linear spinning ring (`850ms`, `2.5px` stroke).
class _UiLoadingStateBanner extends StatefulWidget {
  /// Creates a [_UiLoadingStateBanner].
  const _UiLoadingStateBanner({required this.title, required this.message});

  /// Loading subtitle.
  final String message;

  /// Optional loading heading.
  final String? title;

  @override
  State<_UiLoadingStateBanner> createState() => _UiLoadingStateBannerState();
}

/// Drives continuous `850ms` linear rotation for [_UiLoadingStateBanner].
class _UiLoadingStateBannerState extends State<_UiLoadingStateBanner>
    with SingleTickerProviderStateMixin {
  /// Linear spin controller disposed in [dispose].
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final targetDuration = UiThemeTokens.of(context).focus.loadingSpinDuration;
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
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              RotationTransition(
                turns: _controller,
                child: SizedBox.square(
                  dimension: 32.0,
                  child: CircularProgressIndicator(
                    value: 0.72,
                    strokeWidth: tokens.radii.spinnerStrokeWidth,
                    color: colors.accent,
                    backgroundColor: colors.line,
                  ),
                ),
              ),
              if (widget.title case final heading?) ...<Widget>[
                SizedBox(height: tokens.spacing.space3),
                Text(
                  heading,
                  textAlign: TextAlign.center,
                  style: tokens.typography.cardTitle.copyWith(
                    color: colors.ink,
                  ),
                ),
              ],
              SizedBox(height: tokens.spacing.space1),
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: tokens.typography.meta.copyWith(color: colors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Centered full-screen file-read error view (`34px` hero icon + diagnostics slot + actions).
class _UiFullErrorBanner extends StatelessWidget {
  /// Creates a [_UiFullErrorBanner].
  const _UiFullErrorBanner({
    required this.title,
    required this.message,
    required this.icon,
    required this.detailsChild,
    required this.actions,
  });

  /// Action buttons (e.g. `Settings`, `Retry`).
  final List<Widget> actions;

  /// Optional structured diagnostics card.
  final Widget? detailsChild;

  /// `34px` hero icon glyph.
  final IconData icon;

  /// Error explanation copy.
  final String message;

  /// Optional heading.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520.0),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ExcludeSemantics(
                  child: Icon(
                    icon,
                    size: tokens.spacing.iconLg,
                    color: colors.danger,
                  ),
                ),
                if (title case final heading?) ...<Widget>[
                  SizedBox(height: tokens.spacing.space3),
                  Text(
                    heading,
                    textAlign: TextAlign.center,
                    style: tokens.typography.brand.copyWith(color: colors.ink),
                  ),
                ],
                SizedBox(height: tokens.spacing.space2),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: tokens.typography.control.copyWith(
                    color: colors.muted,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (detailsChild case final details?) ...<Widget>[
                  SizedBox(height: tokens.spacing.space4),
                  details,
                ],
                if (actions.isNotEmpty) ...<Widget>[
                  SizedBox(height: tokens.spacing.space4),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    alignment: WrapAlignment.center,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
