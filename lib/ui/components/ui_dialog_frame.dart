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

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../primitives/ui_button.dart';
import '../primitives/ui_pill.dart';
import '../tokens/ui_theme_tokens.dart';

/// Canonical centered modal dialog width presets (`U-COMP-004`).
enum UiDialogSize {
  /// Compact confirmation and color-picker modals (`420px`).
  small,

  /// Standard modals (`520px`).
  medium,

  /// Wide workspace and diagnostic modals (`600px`).
  large,
}

/// Three-part flat modal dialog frame (`header`, scrollable `body`, right-aligned `footer`) and focus-trapped modal/bottom-sheet presenters (`U-COMP-004`, `U-A11Y-003`).
class UiDialogFrame extends StatelessWidget {
  /// Creates a [UiDialogFrame].
  const UiDialogFrame({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.eyebrow,
    this.size = UiDialogSize.medium,
    this.footer,
    this.onClose,
    this.closeTooltip,
    this.bodyPadding = const EdgeInsets.symmetric(
      horizontal: 18.0,
      vertical: 14.0,
    ),
  });

  /// Shared ease-out opacity curve reused across dialog and bottom-sheet transitions without per-frame [CurvedAnimation] allocations.
  static final Animatable<double> _easeOutTween = CurveTween(
    curve: Curves.easeOut,
  );

  /// Shared upward slide-and-ease curve for compact bottom-sheet entrance transitions.
  static final Animatable<Offset> _sheetSlideTween = Tween<Offset>(
    begin: const Offset(0.0, 0.08),
    end: Offset.zero,
  ).chain(CurveTween(curve: Curves.easeOut));

  /// Scrollable dialog body content.
  final Widget body;

  /// Internal padding applied to [body].
  final EdgeInsetsGeometry bodyPadding;

  /// Accessible tooltip for the header close `x` button.
  final String? closeTooltip;

  /// Optional eyebrow metadata row shown above [title].
  final Widget? eyebrow;

  /// Optional right-aligned top-bordered action footer.
  final Widget? footer;

  /// Optional close callback; when omitted, header close button pops the active route.
  final VoidCallback? onClose;

  /// Maximum width preset (`420`, `520`, or `600` logical px).
  final UiDialogSize size;

  /// Optional muted explanatory subtitle shown below [title].
  final String? subtitle;

  /// Primary `17px` dialog heading.
  final String title;

  /// Resolves the maximum width in logical pixels for [size].
  static double maxWidthForSize(UiDialogSize size) {
    return switch (size) {
      UiDialogSize.small => 420.0,
      UiDialogSize.medium => 520.0,
      UiDialogSize.large => 600.0,
    };
  }

  /// Presents a focus-trapped compact bottom sheet capped at `78%` viewport height and restores focus on pop (`U-COMP-004`, `U-A11Y-003`).
  static Future<T?> showBottomSheet<T>({
    required BuildContext context,
    required String title,
    required WidgetBuilder builder,
    IconData? icon,
    String? countLabel,
    String? doneLabel,
    VoidCallback? onDone,
    bool barrierDismissible = true,
    String? barrierLabel,
  }) async {
    final tokens = UiThemeTokens.of(context);
    final previousFocus = FocusManager.instance.primaryFocus;
    try {
      return await showGeneralDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        barrierLabel: barrierLabel ?? title,
        barrierColor: tokens.colors.scrim,
        transitionDuration: tokens.focus.fadeDuration,
        pageBuilder: (sheetContext, _, _) {
          return _UiFocusTrapOverlay(
            onEscape: barrierDismissible
                ? () => Navigator.of(sheetContext).maybePop()
                : null,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _UiBottomSheetShell(
                title: title,
                icon: icon,
                countLabel: countLabel,
                doneLabel: doneLabel,
                onDone: () {
                  onDone?.call();
                  Navigator.of(sheetContext).maybePop();
                },
                child: builder(sheetContext),
              ),
            ),
          );
        },
        transitionBuilder: (_, animation, _, child) {
          final opacity = _easeOutTween.animate(animation);
          final slide = _sheetSlideTween.animate(animation);
          return FadeTransition(
            opacity: opacity,
            child: SlideTransition(position: slide, child: child),
          );
        },
      );
    } finally {
      _restoreFocus(previousFocus);
    }
  }

  /// Presents a focus-trapped centered modal dialog over translucent `scrim` and restores originating focus on pop (`U-COMP-004`, `U-A11Y-003`).
  static Future<T?> showModal<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    String? barrierLabel,
  }) async {
    final tokens = UiThemeTokens.of(context);
    final previousFocus = FocusManager.instance.primaryFocus;
    try {
      return await showGeneralDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        barrierLabel: barrierLabel ?? '',
        barrierColor: tokens.colors.scrim,
        transitionDuration: tokens.focus.fadeDuration,
        pageBuilder: (dialogContext, _, _) {
          final safePadding = MediaQuery.paddingOf(dialogContext);
          final viewInsets = MediaQuery.viewInsetsOf(dialogContext);
          return _UiFocusTrapOverlay(
            onEscape: barrierDismissible
                ? () => Navigator.of(dialogContext).maybePop()
                : null,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16.0 + safePadding.left + viewInsets.left,
                16.0 + safePadding.top + viewInsets.top,
                16.0 + safePadding.right + viewInsets.right,
                16.0 + safePadding.bottom + viewInsets.bottom,
              ),
              child: MediaQuery(
                data: MediaQuery.of(dialogContext)
                    .copyWith(padding: EdgeInsets.zero),
                child: Center(child: builder(dialogContext)),
              ),
            ),
          );
        },
        transitionBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: _easeOutTween.animate(animation),
            child: child,
          );
        },
      );
    } finally {
      _restoreFocus(previousFocus);
    }
  }

  /// Restores focus cleanly to [previousFocus] when it remains mounted and focusable.
  static void _restoreFocus(FocusNode? previousFocus) {
    if (previousFocus == null || !previousFocus.canRequestFocus) {
      return;
    }
    final focusContext = previousFocus.context;
    if (focusContext != null && focusContext.mounted) {
      previousFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = math.min(viewportHeight * 0.86, 720.0);
    final closeAction = onClose ?? () => Navigator.of(context).maybePop();

    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidthForSize(size),
          maxHeight: maxHeight,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.panel,
            borderRadius: BorderRadius.circular(tokens.radii.shell),
            border: Border.all(
              color: colors.line,
              width: tokens.radii.borderWidth,
            ),
            boxShadow: tokens.focus.modalShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radii.shell),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _UiModalHeader(
                  eyebrow: eyebrow,
                  title: title,
                  subtitle: subtitle,
                  closeTooltip: closeTooltip,
                  onClose: closeAction,
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: bodyPadding,
                    child: body,
                  ),
                ),
                if (footer case final footerWidget?)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: colors.line,
                          width: tokens.radii.borderWidth,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18.0,
                        vertical: 12.0,
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: footerWidget,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Header row inside [UiDialogFrame].
class _UiModalHeader extends StatelessWidget {
  /// Creates a [_UiModalHeader].
  const _UiModalHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.closeTooltip,
    required this.onClose,
  });

  /// Tooltip for close button.
  final String? closeTooltip;

  /// Optional eyebrow widget.
  final Widget? eyebrow;

  /// Close callback.
  final VoidCallback onClose;

  /// Optional muted subtitle.
  final String? subtitle;

  /// `17px` heading title.
  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colors.line,
            width: tokens.radii.borderWidth,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18.0, 14.0, 12.0, 12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (eyebrow case final topEyebrow?) ...<Widget>[
                    topEyebrow,
                    const SizedBox(height: 4.0),
                  ],
                  Text(
                    title,
                    style: tokens.typography.modalTitle.copyWith(
                      color: colors.ink,
                    ),
                  ),
                  if (subtitle case final sub?) ...<Widget>[
                    const SizedBox(height: 4.0),
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
            const SizedBox(width: 8.0),
            UiButton(
              leadingIcon: Icons.close_rounded,
              variant: UiButtonVariant.icon,
              density: UiButtonDensity.dense,
              tooltip: closeTooltip,
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact modal bottom sheet surface capped at `78%` viewport height (`U-COMP-004`).
class _UiBottomSheetShell extends StatelessWidget {
  /// Creates a [_UiBottomSheetShell].
  const _UiBottomSheetShell({
    required this.title,
    required this.icon,
    required this.countLabel,
    required this.doneLabel,
    required this.onDone,
    required this.child,
  });

  /// Sheet body content.
  final Widget child;

  /// Optional count pill label.
  final String? countLabel;

  /// Optional `Done` button label.
  final String? doneLabel;

  /// Optional leading icon in sheet header.
  final IconData? icon;

  /// Callback closing the sheet.
  final VoidCallback onDone;

  /// Sheet heading.
  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final safePadding = MediaQuery.paddingOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final availableHeight = math.max(
      0.0,
      viewportHeight - viewInsets.bottom - safePadding.top,
    );
    final maxHeight = math.min(viewportHeight * 0.78, availableHeight);

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Material(
        key: const ValueKey<String>('ui_bottom_sheet'),
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.panel,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(tokens.radii.shell),
              ),
              border: Border(
                top: BorderSide(
                  color: colors.line,
                  width: tokens.radii.borderWidth,
                ),
              ),
              boxShadow: tokens.focus.bottomSheetShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ExcludeSemantics(
                  child: Padding(
                    key: const ValueKey<String>('ui_bottom_sheet_handle'),
                    padding: const EdgeInsets.only(top: 8.0, bottom: 2.0),
                    child: Center(
                      child: Container(
                        width: 36.0,
                        height: 4.0,
                        decoration: BoxDecoration(
                          color: colors.line,
                          borderRadius: BorderRadius.circular(
                            tokens.radii.pill,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: colors.line,
                        width: tokens.radii.borderWidth,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      14.0 + safePadding.left,
                      8.0,
                      14.0 + safePadding.right,
                      10.0,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Row(
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
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tokens.typography.body.copyWith(
                                    color: colors.ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (countLabel case final count?) ...<Widget>[
                                const SizedBox(width: 8.0),
                                UiPill(
                                  label: count,
                                  variant: UiPillVariant.count,
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (doneLabel case final done?) ...<Widget>[
                          const SizedBox(width: 8.0),
                          UiButton(
                            label: done,
                            density: UiButtonDensity.compact,
                            onPressed: onDone,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      14.0 + safePadding.left,
                      12.0,
                      14.0 + safePadding.right,
                      16.0 + safePadding.bottom,
                    ),
                    child: MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(padding: EdgeInsets.zero),
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Private intent for cyclical forward focus stepping inside modals and sheets.
class _TrapNextFocusIntent extends Intent {
  /// Creates a [_TrapNextFocusIntent].
  const _TrapNextFocusIntent();
}

/// Private intent for cyclical backward focus stepping inside modals and sheets.
class _TrapPreviousFocusIntent extends Intent {
  /// Creates a [_TrapPreviousFocusIntent].
  const _TrapPreviousFocusIntent();
}

/// Private intent dismissing a modal or bottom sheet on `Escape`.
class _TrapEscapeIntent extends Intent {
  /// Creates a [_TrapEscapeIntent].
  const _TrapEscapeIntent();
}

/// Cyclically traps `Tab`/`Shift+Tab` inside a modal `FocusScope` and handles `Escape` (`U-A11Y-003`).
class _UiFocusTrapOverlay extends StatefulWidget {
  /// Creates a [_UiFocusTrapOverlay].
  const _UiFocusTrapOverlay({required this.child, this.onEscape});

  /// Modal or bottom-sheet content tree.
  final Widget child;

  /// Optional dismissal callback invoked on `Escape`.
  final VoidCallback? onEscape;

  @override
  State<_UiFocusTrapOverlay> createState() => _UiFocusTrapOverlayState();
}

/// Owns the modal [FocusScopeNode] and cyclical focus-stepping handlers.
class _UiFocusTrapOverlayState extends State<_UiFocusTrapOverlay> {
  /// Dedicated focus scope isolating keyboard traversal within this overlay.
  late final FocusScopeNode _scopeNode;

  @override
  void initState() {
    super.initState();
    _scopeNode = FocusScopeNode(debugLabel: 'UiDialogFrameScope');
  }

  @override
  void dispose() {
    _scopeNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: FocusScope(
        node: _scopeNode,
        autofocus: true,
        child: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.tab): _TrapNextFocusIntent(),
              SingleActivator(LogicalKeyboardKey.tab, shift: true):
                  _TrapPreviousFocusIntent(),
              SingleActivator(LogicalKeyboardKey.escape): _TrapEscapeIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                _TrapNextFocusIntent: CallbackAction<_TrapNextFocusIntent>(
                  onInvoke: (_) {
                    _stepFocus(forward: true);
                    return null;
                  },
                ),
                _TrapPreviousFocusIntent:
                    CallbackAction<_TrapPreviousFocusIntent>(
                      onInvoke: (_) {
                        _stepFocus(forward: false);
                        return null;
                      },
                    ),
                _TrapEscapeIntent: CallbackAction<_TrapEscapeIntent>(
                  onInvoke: (_) {
                    widget.onEscape?.call();
                    return null;
                  },
                ),
              },
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }

  /// Cyclically steps focus across focusable descendants of [_scopeNode].
  void _stepFocus({required bool forward}) {
    final focusable = _scopeNode.traversalDescendants
        .where((node) => node.canRequestFocus && !node.skipTraversal)
        .toList();
    if (focusable.isEmpty) {
      return;
    }
    final current = FocusManager.instance.primaryFocus;
    final currentIndex = current == null ? -1 : focusable.indexOf(current);
    final int nextIndex;
    if (currentIndex < 0) {
      nextIndex = forward ? 0 : focusable.length - 1;
    } else if (forward) {
      nextIndex = (currentIndex + 1) % focusable.length;
    } else {
      nextIndex = (currentIndex - 1 + focusable.length) % focusable.length;
    }
    focusable[nextIndex].requestFocus();
  }
}
