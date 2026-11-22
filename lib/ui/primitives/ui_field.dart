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
import 'ui_button.dart';
import 'ui_segmented_control.dart';

/// Input control role rendered by [UiField] (`U-COMP-002`).
enum UiFieldKind {
  /// Single-line bordered text input.
  text,

  /// Multi-line bordered notes textarea.
  multiline,

  /// Password text input with built-in visibility reveal toggle.
  password,

  /// Flat `1px` bordered combobox select with animated custom popup menu.
  select,

  /// Tap-to-pick bordered date/time display input.
  dateTime,

  /// Composite focus-within search box with leading search glyph and single clear button.
  search,

  /// Flat selectable monospace read-only readout well.
  readOnlyDisplay,
}

/// Immutable option entry for `UiFieldKind.select`.
@immutable
class UiSelectOption {
  /// Creates a [UiSelectOption].
  const UiSelectOption({
    required this.value,
    required this.label,
    this.enabled = true,
  });

  /// Whether this option can be selected.
  final bool enabled;

  /// Caller-supplied display text.
  final String label;

  /// Stable option identifier.
  final String value;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is UiSelectOption &&
        other.value == value &&
        other.label == label &&
        other.enabled == enabled;
  }

  @override
  int get hashCode => Object.hash(value, label, enabled);
}

/// Flat surface-aware input wrapper supporting text, multiline, password, select, date/time, search, and read-only display.
class UiField extends StatefulWidget {
  /// Creates a [UiField].
  const UiField({
    super.key,
    this.kind = UiFieldKind.text,
    this.label,
    this.hintText,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.maxLength,
    this.maxLines,
    this.minLines,
    this.isMonospace = false,
    this.leadingIcon,
    this.trailingAction,
    this.readOnly = false,
    this.enabled = true,
    this.helperText,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.showClearButton = false,
    this.clearTooltip,
    this.onClear,
    this.showPasswordTooltip,
    this.hidePasswordTooltip,
    this.selectValue,
    this.selectOptions = const <UiSelectOption>[],
    this.onSelectChanged,
    this.displayValue,
    this.onTap,
    this.height,
    this.borderRadius,
    this.semanticLabel,
    this.textStyle,
  });

  /// Whether the input requests focus automatically on mount.
  final bool autofocus;

  /// Optional explicit corner radius overriding `tokens.radii.md`.
  final double? borderRadius;

  /// Accessible tooltip for the clear button on `text` and `search` fields.
  final String? clearTooltip;

  /// Optional caller-owned text editing controller.
  final TextEditingController? controller;

  /// Formatted text displayed by `dateTime` and `readOnlyDisplay` fields.
  final String? displayValue;

  /// Whether the control is enabled (`0.48` opacity when false).
  final bool enabled;

  /// Optional inline validation error (`danger` text with live-region semantics).
  final String? errorText;

  /// Optional caller-owned [FocusNode].
  final FocusNode? focusNode;

  /// Optional minimum height override (e.g. `44.0` compact tier select, `36.0` search, `32.0` sidebar filter).
  final double? height;

  /// Optional muted helper guidance below the field.
  final String? helperText;

  /// Tooltip for hiding password text when revealed (`UiFieldKind.password`).
  final String? hidePasswordTooltip;

  /// Placeholder hint text.
  final String? hintText;

  /// Forces monospace typography for URLs, paths, coordinates, and hex values.
  final bool isMonospace;

  /// Optional virtual keyboard input type.
  final TextInputType? keyboardType;

  /// Field structural kind.
  final UiFieldKind kind;

  /// Optional field label displayed above the bordered control.
  final String? label;

  /// Optional leading outline icon glyph.
  final IconData? leadingIcon;

  /// Optional maximum character length (`counterText` suppressed cleanly).
  final int? maxLength;

  /// Optional explicit maximum lines for `multiline`.
  final int? maxLines;

  /// Optional explicit minimum lines for `multiline`.
  final int? minLines;

  /// Change callback for text-based fields.
  final ValueChanged<String>? onChanged;

  /// Callback invoked after tapping the clear button.
  final VoidCallback? onClear;

  /// Selection callback for `UiFieldKind.select`.
  final ValueChanged<String>? onSelectChanged;

  /// Submit callback triggered by `Enter` on single-line inputs.
  final ValueChanged<String>? onSubmitted;

  /// Tap callback for `UiFieldKind.dateTime`.
  final VoidCallback? onTap;

  /// Renders the field read-only at `0.72` opacity (`U-A11Y-004`).
  final bool readOnly;

  /// Available options for `UiFieldKind.select`.
  final List<UiSelectOption> selectOptions;

  /// Currently selected value for `UiFieldKind.select`.
  final String? selectValue;

  /// Optional explicit accessible label.
  final String? semanticLabel;

  /// Enables a trailing clear `x` button when text is non-empty (`text` / `search`).
  final bool showClearButton;

  /// Tooltip for revealing password text (`UiFieldKind.password`).
  final String? showPasswordTooltip;

  /// Keyboard action button hint.
  final TextInputAction? textInputAction;

  /// Optional explicit text style override (e.g. `16px` compact quick-add input).
  final TextStyle? textStyle;

  /// Optional custom trailing widget.
  final Widget? trailingAction;

  @override
  State<UiField> createState() => _UiFieldState();
}

/// Vertical wrapper rendering optional field label, control slot, helper text, and live error text.
class _UiFieldLayoutColumn extends StatelessWidget {
  /// Creates a [_UiFieldLayoutColumn].
  const _UiFieldLayoutColumn({
    required this.label,
    required this.helperText,
    required this.errorText,
    required this.opacity,
    required this.control,
  });

  /// Inner interactive field control.
  final Widget control;

  /// Optional inline validation error text.
  final String? errorText;

  /// Optional muted helper copy beneath the field.
  final String? helperText;

  /// Optional label rendered above the field.
  final String? label;

  /// Effective enabled/readonly opacity applied to [control].
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final error = errorText;
    final hasError = error != null && error.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (label case final fieldLabel?) ...<Widget>[
          Text(
            fieldLabel,
            style: tokens.typography.meta.copyWith(
              color: colors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6.0),
        ],
        Opacity(opacity: opacity, child: control),
        if (helperText case final helper?) ...<Widget>[
          const SizedBox(height: 4.0),
          Text(
            helper,
            style: tokens.typography.eyebrow.copyWith(
              color: colors.muted,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.0,
            ),
          ),
        ],
        if (hasError) ...<Widget>[
          const SizedBox(height: 4.0),
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              style: tokens.typography.meta.copyWith(
                color: colors.danger,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Manages internal controller/focus lifecycles, focus border color, and password reveal state for [UiField].
class _UiFieldState extends State<UiField> {
  final List<ChangeNotifier> _pendingDisposals = <ChangeNotifier>[];

  TextEditingController? _ownedController;
  FocusNode? _ownedFocusNode;
  bool _obscurePassword = true;
  bool _hasText = false;
  bool _isDisposalScheduled = false;
  bool _isFocused = false;

  /// Active text controller (caller-owned or internal).
  TextEditingController get _controller {
    if (widget.controller case final external?) {
      return external;
    }
    return _ownedController ??= TextEditingController();
  }

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
    _attachFocusListener(_focusNode);
    _attachTextListener(_controller);
    _hasText = _controller.text.isNotEmpty;
  }

  @override
  void didUpdateWidget(covariant UiField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      final previousNode = oldWidget.focusNode ?? _ownedFocusNode;
      previousNode?.removeListener(_handleFocusChange);
      if (widget.focusNode != null) {
        if (_ownedFocusNode case final previousOwned?) {
          _ownedFocusNode = null;
          _enqueueDisposal(previousOwned);
        }
      }
      _attachFocusListener(_focusNode);
      _isFocused = _focusNode.hasFocus;
    }
    if (oldWidget.controller != widget.controller) {
      final previousController = oldWidget.controller ?? _ownedController;
      previousController?.removeListener(_handleTextChange);
      if (widget.controller != null) {
        if (_ownedController case final previousOwned?) {
          _ownedController = null;
          _enqueueDisposal(previousOwned);
        }
      }
      _attachTextListener(_controller);
      _hasText = _controller.text.isNotEmpty;
    }
  }

  @override
  void dispose() {
    (widget.focusNode ?? _ownedFocusNode)?.removeListener(_handleFocusChange);
    (widget.controller ?? _ownedController)?.removeListener(_handleTextChange);
    _flushPendingDisposals();
    _ownedFocusNode?.dispose();
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final errorTextValue = widget.errorText;
    final hasError = errorTextValue != null && errorTextValue.isNotEmpty;
    final opacity = widget.readOnly
        ? tokens.focus.readonlyOpacity
        : (widget.enabled ? 1.0 : tokens.focus.disabledOpacity);

    final control = widget.kind == UiFieldKind.select
        ? UiSegmentedControl<String?>(
            mode: UiSegmentedControlMode.vertical,
            segments: <UiSegment<String?>>[
              for (final option in widget.selectOptions)
                UiSegment<String?>(
                  value: option.value,
                  label: option.label,
                  enabled: option.enabled,
                ),
            ],
            value: widget.selectValue,
            onChanged: widget.onSelectChanged != null ? _handleSelect : null,
            enabled: widget.enabled && !widget.readOnly,
            semanticLabel: widget.semanticLabel ?? widget.label,
            focusNode: _focusNode,
            hintText: widget.hintText ?? '',
            leadingIcon: widget.leadingIcon,
            hasError: hasError,
            minHeight: _resolveHeight(tokens),
            borderRadius: widget.borderRadius ?? tokens.radii.md,
            textStyle: _resolveTextStyle(tokens),
            applyDisabledOpacity: false,
          )
        : _UiStandardFieldShell(
            minHeight: _resolveHeight(tokens),
            borderRadius: widget.borderRadius ?? tokens.radii.md,
            hasError: hasError,
            isFocused: _isFocused,
            child: _buildStandardControl(tokens),
          );

    return _UiFieldLayoutColumn(
      label: widget.label,
      helperText: widget.helperText,
      errorText: errorTextValue,
      opacity: opacity,
      control: control,
    );
  }

  /// Attaches focus change monitoring to [node].
  void _attachFocusListener(FocusNode node) {
    node.addListener(_handleFocusChange);
  }

  /// Attaches text change monitoring so the clear button updates reactively.
  void _attachTextListener(TextEditingController controller) {
    controller.addListener(_handleTextChange);
  }

  /// Builds the tap-to-pick bordered date/time display row.
  Widget _buildDateTimeInput(UiThemeTokens tokens) {
    final colors = tokens.colors;
    final rawDisplay = widget.displayValue;
    final hasValue = rawDisplay != null && rawDisplay.isNotEmpty;
    final displayText = hasValue ? rawDisplay : (widget.hintText ?? '');
    final canTap = widget.enabled && !widget.readOnly && widget.onTap != null;

    return Semantics(
      button: canTap,
      label: widget.semanticLabel ?? widget.label ?? displayText,
      child: FocusableActionDetector(
        focusNode: _focusNode,
        enabled: canTap,
        mouseCursor: canTap
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
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
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canTap ? widget.onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 10.0,
              vertical: 8.0,
            ),
            child: Row(
              children: <Widget>[
                ExcludeSemantics(
                  child: Icon(
                    widget.leadingIcon ?? Icons.calendar_today_outlined,
                    size: tokens.spacing.iconSm,
                    color: colors.muted,
                  ),
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(
                    displayText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _resolveTextStyle(tokens)
                        .copyWith(color: hasValue ? colors.ink : colors.muted),
                  ),
                ),
                if (widget.showClearButton &&
                    hasValue &&
                    widget.enabled &&
                    !widget.readOnly &&
                    widget.onClear != null)
                  UiButton(
                    leadingIcon: Icons.close_rounded,
                    variant: UiButtonVariant.icon,
                    density: UiButtonDensity.sidebarDesktop,
                    tooltip: widget.clearTooltip,
                    onPressed: widget.onClear,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds a selectable flat monospace readout well (`UiFieldKind.readOnlyDisplay`).
  Widget _buildReadOnlyDisplay(UiThemeTokens tokens) {
    final colors = tokens.colors;
    final style = UiTypographyTokens.mono(
      tokens.typography.monoSmall.copyWith(color: colors.ink),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 9.0),
      child: SelectableText(widget.displayValue ?? '', style: style),
    );
  }

  /// Builds the interior widget for non-select [UiFieldKind] variants.
  Widget _buildStandardControl(UiThemeTokens tokens) {
    return switch (widget.kind) {
      UiFieldKind.text ||
      UiFieldKind.multiline ||
      UiFieldKind.password ||
      UiFieldKind.search => _buildTextInput(tokens),
      UiFieldKind.dateTime => _buildDateTimeInput(tokens),
      UiFieldKind.readOnlyDisplay => _buildReadOnlyDisplay(tokens),
      UiFieldKind.select => const SizedBox.shrink(),
    };
  }

  /// Builds borderless inner [TextField] with leading icon, password toggle, or clear action.
  Widget _buildTextInput(UiThemeTokens tokens) {
    final colors = tokens.colors;
    final isMultiline = widget.kind == UiFieldKind.multiline;
    final isSearch = widget.kind == UiFieldKind.search;
    final isPassword = widget.kind == UiFieldKind.password;
    final leading =
        widget.leadingIcon ?? (isSearch ? Icons.search_rounded : null);
    final showClear =
        (isSearch || widget.showClearButton) &&
        _controller.text.isNotEmpty &&
        widget.enabled &&
        !widget.readOnly;

    return Row(
      crossAxisAlignment: isMultiline
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: <Widget>[
        if (leading case final icon?) ...<Widget>[
          Padding(
            padding: EdgeInsets.only(left: 10.0, top: isMultiline ? 10.0 : 0.0),
            child: ExcludeSemantics(
              child: Icon(
                icon,
                size: tokens.spacing.iconSm,
                color: colors.muted,
              ),
            ),
          ),
        ],
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            enabled: widget.enabled,
            readOnly: widget.readOnly,
            obscureText: isPassword && _obscurePassword,
            maxLength: widget.maxLength,
            minLines: isMultiline ? (widget.minLines ?? 3) : 1,
            maxLines: isMultiline ? (widget.maxLines ?? 6) : 1,
            keyboardType:
                widget.keyboardType ??
                (isMultiline ? TextInputType.multiline : TextInputType.text),
            textInputAction: widget.textInputAction,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            style: _resolveTextStyle(tokens),
            decoration: InputDecoration(
              filled: false,
              isDense: true,
              counterText: '',
              hintText: widget.hintText,
              hintStyle: _resolveTextStyle(tokens)
                  .copyWith(color: colors.muted),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: leading != null ? 8.0 : 10.0,
                vertical: isMultiline ? 10.0 : 8.0,
              ),
            ),
          ),
        ),
        if (showClear)
          Padding(
            padding: const EdgeInsets.only(right: 4.0),
            child: UiButton(
              leadingIcon: Icons.close_rounded,
              variant: UiButtonVariant.icon,
              density: UiButtonDensity.sidebarDesktop,
              tooltip: widget.clearTooltip,
              onPressed: _handleClear,
            ),
          ),
        if (isPassword)
          Padding(
            padding: const EdgeInsets.only(right: 4.0),
            child: UiButton(
              leadingIcon: _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              variant: UiButtonVariant.icon,
              density: UiButtonDensity.dense,
              tooltip: _obscurePassword
                  ? widget.showPasswordTooltip
                  : widget.hidePasswordTooltip,
              onPressed: widget.enabled
                  ? () => setState(() => _obscurePassword = !_obscurePassword)
                  : null,
            ),
          ),
        if (widget.trailingAction case final trailing?)
          Padding(padding: const EdgeInsets.only(right: 4.0), child: trailing),
      ],
    );
  }

  /// Queues a replaced internal [notifier] for post-frame disposal after children detach.
  void _enqueueDisposal(ChangeNotifier notifier) {
    _pendingDisposals.add(notifier);
    if (_isDisposalScheduled) {
      return;
    }
    _isDisposalScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushPendingDisposals();
    });
  }

  /// Disposes all queued internal controllers and focus nodes after the frame or during unmount.
  void _flushPendingDisposals() {
    _isDisposalScheduled = false;
    if (_pendingDisposals.isEmpty) {
      return;
    }
    final notifiers = List<ChangeNotifier>.of(_pendingDisposals);
    _pendingDisposals.clear();
    for (final notifier in notifiers) {
      notifier.dispose();
    }
  }

  /// Clears the controller text, notifies callbacks, and keeps focus on the input.
  void _handleClear() {
    _controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
    if (widget.enabled && !widget.readOnly) {
      _focusNode.requestFocus();
    }
  }

  /// Synchronizes focus border state with [_focusNode].
  void _handleFocusChange() {
    final nextFocused = _focusNode.hasFocus;
    if (_isFocused != nextFocused && mounted) {
      setState(() => _isFocused = nextFocused);
    }
  }

  /// Forwards non-null combobox selections to [UiField.onSelectChanged].
  void _handleSelect(String? nextValue) {
    if (nextValue != null) {
      widget.onSelectChanged?.call(nextValue);
    }
  }

  /// Rebuilds clear button visibility only when text transitions between empty and non-empty.
  void _handleTextChange() {
    final nextHasText = _controller.text.isNotEmpty;
    if (nextHasText == _hasText) {
      return;
    }
    _hasText = nextHasText;
    if (mounted &&
        (widget.kind == UiFieldKind.search || widget.showClearButton)) {
      setState(() {});
    }
  }

  /// Resolves minimum field height by [UiFieldKind].
  double _resolveHeight(UiThemeTokens tokens) {
    if (widget.height case final explicit?) {
      return explicit;
    }
    return switch (widget.kind) {
      UiFieldKind.multiline => 72.0,
      UiFieldKind.search => tokens.spacing.fieldCompactHeight,
      UiFieldKind.text ||
      UiFieldKind.password ||
      UiFieldKind.select ||
      UiFieldKind.dateTime ||
      UiFieldKind.readOnlyDisplay => tokens.spacing.touchTarget,
    };
  }

  /// Resolves field typography honoring [UiField.isMonospace] and custom overrides.
  TextStyle _resolveTextStyle(UiThemeTokens tokens) {
    final base =
        widget.textStyle ??
        tokens.typography.control.copyWith(
          color: tokens.colors.ink,
          fontWeight: FontWeight.w400,
        );
    return widget.isMonospace ? UiTypographyTokens.mono(base) : base;
  }
}

/// Surface-aware `1px` bordered container shared by non-select [UiFieldKind] controls.
class _UiStandardFieldShell extends StatelessWidget {
  /// Creates a [_UiStandardFieldShell].
  const _UiStandardFieldShell({
    required this.minHeight,
    required this.borderRadius,
    required this.hasError,
    required this.isFocused,
    required this.child,
  });

  /// Corner radius in logical pixels.
  final double borderRadius;

  /// Inner control widget.
  final Widget child;

  /// Highlights border in `danger` when true.
  final bool hasError;

  /// Highlights border in `accent` when focused.
  final bool isFocused;

  /// Minimum height of the bordered container.
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;
    final fillColor = UiSurfaceScope.of(context) == UiSurfaceLevel.insetWell
        ? colors.panel
        : colors.bg;
    final borderColor = hasError
        ? colors.danger
        : (isFocused ? colors.accent : colors.line);

    return AnimatedContainer(
      duration: tokens.focus.hoverDuration,
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor, width: tokens.radii.borderWidth),
      ),
      child: child,
    );
  }
}
