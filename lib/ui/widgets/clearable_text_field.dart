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

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Reusable text input widget wrapping [TextField] or [TextFormField] that displays a right-side clear button when focused.
class ClearableTextField extends StatefulWidget {
  /// Creates a [ClearableTextField].
  const ClearableTextField({
    super.key,
    required this.controller,
    this.autocorrect = true,
    this.autofocus = false,
    this.clearButtonKey,
    this.clearIconColor,
    this.clearIconSize = 18.0,
    this.clearTooltip,
    this.cursorColor,
    this.decoration = const InputDecoration(),
    this.enabled = true,
    this.fieldKey,
    this.keyboardType,
    this.maxLines = 1,
    this.minLines,
    this.obscureText = false,
    this.onChanged,
    this.onCleared,
    this.onSubmitted,
    this.readOnly = false,
    this.showClearWhenUnfocused = false,
    this.style,
    this.textInputAction,
    this.useFormField = false,
    this.validator,
  });

  /// Whether auto-correction is enabled.
  final bool autocorrect;

  /// Whether this text field should focus itself automatically.
  final bool autofocus;

  /// Optional deterministic key for the clear [IconButton].
  final Key? clearButtonKey;

  /// Optional color for the clear icon, defaulting to `onSurfaceVariant`.
  final Color? clearIconColor;

  /// Size of the clear icon in logical pixels.
  final double clearIconSize;

  /// Optional tooltip override for the clear button.
  final String? clearTooltip;

  /// Controller managing the text being edited.
  final TextEditingController controller;

  /// Optional cursor color.
  final Color? cursorColor;

  /// Base [InputDecoration] for the text field.
  final InputDecoration decoration;

  /// Whether the text field is interactive.
  final bool enabled;

  /// Optional key forwarded directly to the inner [TextField] or [TextFormField].
  final Key? fieldKey;

  /// Optional keyboard input type.
  final TextInputType? keyboardType;

  /// Maximum number of lines for the input field.
  final int? maxLines;

  /// Minimum number of lines for the input field.
  final int? minLines;

  /// Whether to obscure the edited text (for example in password fields).
  final bool obscureText;

  /// Optional callback invoked when the input text changes.
  final ValueChanged<String>? onChanged;

  /// Optional callback invoked after the clear button empties [controller].
  final VoidCallback? onCleared;

  /// Optional callback invoked when the user submits the field from the keyboard.
  final ValueChanged<String>? onSubmitted;

  /// Whether the text field is read-only.
  final bool readOnly;

  /// Whether to keep the clear button visible when unfocused if [controller] contains text.
  final bool showClearWhenUnfocused;

  /// Optional text style for the input content.
  final TextStyle? style;

  /// Optional keyboard action button type.
  final TextInputAction? textInputAction;

  /// Whether to render a [TextFormField] instead of a [TextField].
  final bool useFormField;

  /// Optional form validator (automatically renders a [TextFormField] when non-null).
  final FormFieldValidator<String>? validator;

  @override
  State<ClearableTextField> createState() => _ClearableTextFieldState();
}

/// Form-integrated input view rendered when [ClearableTextField] acts as a [TextFormField].
class _ClearableFormField extends StatelessWidget {
  /// Creates a [_ClearableFormField].
  const _ClearableFormField({
    required this.config,
    required this.decoration,
    required this.focusNode,
  });

  /// Parent [ClearableTextField] configuration.
  final ClearableTextField config;

  /// Effective [InputDecoration] including the optional clear button.
  final InputDecoration decoration;

  /// Focus node attached to the input field.
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: config.fieldKey,
      controller: config.controller,
      focusNode: focusNode,
      enabled: config.enabled,
      readOnly: config.readOnly,
      autofocus: config.autofocus,
      obscureText: config.obscureText,
      autocorrect: config.autocorrect,
      keyboardType: config.keyboardType,
      textInputAction: config.textInputAction,
      style: config.style,
      cursorColor: config.cursorColor,
      minLines: config.minLines,
      maxLines: config.maxLines,
      decoration: decoration,
      onChanged: config.onChanged,
      onFieldSubmitted: config.onSubmitted,
      validator: config.validator,
    );
  }
}

/// Trailing suffix widget combining the clear button with an optional custom [trailingIcon].
class _ClearableSuffixIcon extends StatelessWidget {
  /// Creates a [_ClearableSuffixIcon].
  const _ClearableSuffixIcon({
    required this.clearButtonKey,
    required this.iconColor,
    required this.iconSize,
    required this.onClear,
    required this.tooltip,
    required this.trailingIcon,
  });

  /// Optional deterministic key for the clear button.
  final Key? clearButtonKey;

  /// Foreground color of the clear icon.
  final Color iconColor;

  /// Logical pixel size of the clear icon.
  final double iconSize;

  /// Callback invoked when the clear button is pressed.
  final VoidCallback onClear;

  /// Localized tooltip for the clear button.
  final String tooltip;

  /// Optional additional trailing widget from [InputDecoration.suffixIcon].
  final Widget? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final clearButton = IconButton(
      key: clearButtonKey,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      tooltip: tooltip,
      icon: Icon(Icons.close_rounded, size: iconSize, color: iconColor),
      onPressed: onClear,
    );
    final customTrailing = trailingIcon;
    if (customTrailing == null) {
      return clearButton;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [clearButton, customTrailing],
    );
  }
}

/// State for [ClearableTextField].
class _ClearableTextFieldState extends State<ClearableTextField> {
  final FocusNode _focusNode = FocusNode();
  bool _isClearButtonVisible = false;

  /// Whether the clear button should be rendered in the suffix slot.
  bool get _shouldShowClearButton =>
      widget.enabled &&
      !widget.readOnly &&
      (_focusNode.hasFocus ||
          (widget.showClearWhenUnfocused && widget.controller.text.isNotEmpty));

  @override
  void initState() {
    super.initState();
    _isClearButtonVisible = _shouldShowClearButton;
    _focusNode.addListener(_handleStateChange);
    widget.controller.addListener(_handleStateChange);
  }

  @override
  void didUpdateWidget(covariant ClearableTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleStateChange);
      widget.controller.addListener(_handleStateChange);
    }
    _isClearButtonVisible = _shouldShowClearButton;
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleStateChange);
    widget.controller.removeListener(_handleStateChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final decoration = _buildEffectiveDecoration(context);
    if (widget.useFormField || widget.validator != null) {
      return _ClearableFormField(
        config: widget,
        decoration: decoration,
        focusNode: _focusNode,
      );
    }
    return TextField(
      key: widget.fieldKey,
      controller: widget.controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      obscureText: widget.obscureText,
      autocorrect: widget.autocorrect,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      style: widget.style,
      cursorColor: widget.cursorColor,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      decoration: decoration,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );
  }

  /// Merges the clear button into [widget.decoration] when [_isClearButtonVisible] is true.
  InputDecoration _buildEffectiveDecoration(BuildContext context) {
    if (!_isClearButtonVisible) {
      return widget.decoration;
    }
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return widget.decoration.copyWith(
      suffixIcon: _ClearableSuffixIcon(
        clearButtonKey: widget.clearButtonKey,
        iconColor: widget.clearIconColor ?? colorScheme.onSurfaceVariant,
        iconSize: widget.clearIconSize,
        tooltip: widget.clearTooltip ?? localizations.tooltipClearInput,
        trailingIcon: widget.decoration.suffixIcon,
        onClear: _clearText,
      ),
    );
  }

  /// Clears [widget.controller], notifies callbacks, and keeps focus on the input.
  void _clearText() {
    widget.controller.clear();
    widget.onChanged?.call('');
    widget.onCleared?.call();
    _focusNode.requestFocus();
  }

  /// Rebuilds only when clear-button visibility transitions.
  void _handleStateChange() {
    if (!mounted) {
      return;
    }
    final nextVisible = _shouldShowClearButton;
    if (nextVisible != _isClearButtonVisible) {
      setState(() {
        _isClearButtonVisible = nextVisible;
      });
    }
  }
}
