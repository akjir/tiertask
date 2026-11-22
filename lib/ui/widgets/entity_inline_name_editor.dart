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

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/tdf_error.dart';
import '../../providers/shell_providers.dart';
import '../primitives/ui_button.dart';
import '../primitives/ui_field.dart';
import '../tokens/ui_breakpoints.dart';

/// Adaptive inline title/name editor shared across Task, Label, and Location cards (`U-CARD-001`).
class EntityInlineNameEditor extends StatefulWidget {
  /// Creates an [EntityInlineNameEditor].
  const EntityInlineNameEditor({
    super.key,
    required this.initialValue,
    required this.hintText,
    required this.onSave,
    required this.onCancel,
    this.semanticsLabel,
    this.inputKey,
    this.saveKey,
    this.cancelKey,
    this.isBusy = false,
    this.errorText,
    this.maxLength = maxTdfTextLength,
    this.validator,
    this.autofocus = true,
  });

  /// Requests initial input focus when mounted.
  final bool autofocus;

  /// Optional stable key for the Cancel button.
  final Key? cancelKey;

  /// Optional external validation or persistence error text.
  final String? errorText;

  /// Placeholder hint displayed inside the text input.
  final String hintText;

  /// Initial entity title or name seeding the text field.
  final String initialValue;

  /// Optional stable key for the [UiField] text input.
  final Key? inputKey;

  /// Disables input and actions while a parent mutation is in flight.
  final bool isBusy;

  /// Optional maximum Unicode scalar length (`maxTdfTextLength` by default).
  final int? maxLength;

  /// Callback cancelling inline title/name editing.
  final VoidCallback onCancel;

  /// Async callback validating and persisting the edited title or name.
  final Future<ActionResult> Function(String value) onSave;

  /// Optional stable key for the Save button.
  final Key? saveKey;

  /// Optional accessible label for the text input.
  final String? semanticsLabel;

  /// Optional synchronous pre-submit validator returning localized error text or `null`.
  final String? Function(String value)? validator;

  @override
  State<EntityInlineNameEditor> createState() => _EntityInlineNameEditorState();
}

/// Compact Save and Cancel button row paired with [EntityInlineNameEditor].
class _EntityInlineNameActions extends StatelessWidget {
  /// Creates an [_EntityInlineNameActions].
  const _EntityInlineNameActions({
    required this.saveKey,
    required this.cancelKey,
    required this.isBusy,
    required this.onSave,
    required this.onCancel,
  });

  /// Optional stable key for the Cancel button.
  final Key? cancelKey;

  /// Disables actions and spins Save indicator while true.
  final bool isBusy;

  /// Callback cancelling inline editing.
  final VoidCallback onCancel;

  /// Callback committing the edited value.
  final VoidCallback onSave;

  /// Optional stable key for the Save button.
  final Key? saveKey;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        UiButton(
          key: saveKey,
          label: localizations.actionSave,
          variant: UiButtonVariant.primary,
          density: UiButtonDensity.compact,
          isLoading: isBusy,
          onPressed: isBusy ? null : onSave,
        ),
        const SizedBox(width: 6.0),
        UiButton(
          key: cancelKey,
          label: localizations.actionCancel,
          density: UiButtonDensity.compact,
          onPressed: isBusy ? null : onCancel,
        ),
      ],
    );
  }
}

/// Manages text controller, Escape shortcut, submit safety, and deferred disposal for [EntityInlineNameEditor].
class _EntityInlineNameEditorState extends State<EntityInlineNameEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  bool _isSubmitting = false;
  String? _localErrorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.selection = TextSelection.collapsed(
      offset: widget.initialValue.length,
    );
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    final controller = _controller;
    final focusNode = _focusNode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
      focusNode.dispose();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = UiBreakpoints.isCompact(MediaQuery.sizeOf(context).width);
    final effectiveBusy = widget.isBusy || _isSubmitting;
    final effectiveError = _localErrorText ?? widget.errorText;

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleKeyEvent,
      child: _EntityInlineNameLayout(
        isCompact: isCompact,
        field: UiField(
          key: widget.inputKey,
          controller: _controller,
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          maxLength: widget.maxLength,
          hintText: widget.hintText,
          semanticLabel: widget.semanticsLabel,
          enabled: !effectiveBusy,
          errorText: effectiveError,
          textInputAction: TextInputAction.done,
          onChanged: _handleChanged,
          onSubmitted: (_) => _triggerSave(),
        ),
        actions: _EntityInlineNameActions(
          saveKey: widget.saveKey,
          cancelKey: widget.cancelKey,
          isBusy: effectiveBusy,
          onSave: _triggerSave,
          onCancel: widget.onCancel,
        ),
      ),
    );
  }

  /// Clears local validation error feedback once the user resumes typing.
  void _handleChanged(String _) {
    if (_localErrorText != null) {
      setState(() => _localErrorText = null);
    }
  }

  /// Intercepts `Escape` to cancel inline editing when idle.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (widget.isBusy || _isSubmitting) {
      return KeyEventResult.handled;
    }
    widget.onCancel();
    return KeyEventResult.handled;
  }

  /// Validates and commits the edited text with double-submit guard and `try/finally` recovery.
  Future<void> _handleSave() async {
    if (widget.isBusy || _isSubmitting) {
      return;
    }
    final currentValue = _controller.text;
    if (widget.validator case final validate?) {
      final validationError = validate(currentValue);
      if (validationError != null && validationError.isNotEmpty) {
        setState(() => _localErrorText = validationError);
        return;
      }
    }
    setState(() {
      _isSubmitting = true;
      _localErrorText = null;
    });
    var restoreFocus = false;
    try {
      final result = await widget.onSave(currentValue);
      if (!mounted) {
        return;
      }
      switch (result) {
        case ActionSucceeded():
          break;
        case ActionValidationFailed(:final message):
        case ActionPersistFailed(:final message):
          restoreFocus = true;
          setState(() => _localErrorText = message);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
        if (restoreFocus) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !widget.isBusy && !_isSubmitting) {
              _focusNode.requestFocus();
            }
          });
        }
      }
    }
  }

  /// Dispatches asynchronous save from synchronous input and button callbacks.
  void _triggerSave() => unawaited(_handleSave());
}

/// Arranges the inline input field and action buttons horizontally on desktop and stacked on compact.
class _EntityInlineNameLayout extends StatelessWidget {
  /// Creates an [_EntityInlineNameLayout].
  const _EntityInlineNameLayout({
    required this.isCompact,
    required this.field,
    required this.actions,
  });

  /// Compact Save and Cancel button row.
  final Widget actions;

  /// Inline title/name input field.
  final Widget field;

  /// Stacks [actions] below [field] on compact viewports (`<= 720px`).
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    if (isCompact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          field,
          const SizedBox(height: 6.0),
          Align(alignment: Alignment.centerRight, child: actions),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: field),
        const SizedBox(width: 6.0),
        actions,
      ],
    );
  }
}
