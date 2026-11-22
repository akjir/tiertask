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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/tdf_error.dart';
import '../../providers/floating_notice_providers.dart';
import '../../providers/shell_providers.dart';
import '../primitives/ui_button.dart';
import '../primitives/ui_card.dart';
import '../primitives/ui_field.dart';
import '../tokens/ui_theme_tokens.dart';
import 'entity_card_chrome.dart';

/// Shared read-only and inline-editable multi-line Note section for Tasks, Labels, and Locations.
class EntityNoteSection extends ConsumerStatefulWidget {
  /// Creates an [EntityNoteSection].
  const EntityNoteSection({
    super.key,
    required this.note,
    required this.isEditing,
    required this.canEdit,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onSave,
    required this.onClear,
    this.onNoteCopied,
    this.isBusy = false,
  });

  /// Whether this section can enter inline edit mode.
  final bool canEdit;

  /// Whether an asynchronous parent mutation is currently in progress.
  final bool isBusy;

  /// Whether this section is currently in inline edit mode.
  final bool isEditing;

  /// Persisted multi-line note text, or `null` when unset.
  final String? note;

  /// Callback closing inline edit mode without saving.
  final VoidCallback onCancelEdit;

  /// Callback clearing the persisted note text.
  final FutureOr<void> Function() onClear;

  /// Optional callback notified after copying the note to clipboard (e.g. telemetry).
  final VoidCallback? onNoteCopied;

  /// Callback validating and persisting the edited note text.
  final Future<ActionResult> Function(String rawNote) onSave;

  /// Callback opening inline edit mode for this section.
  final VoidCallback onStartEdit;

  @override
  ConsumerState<EntityNoteSection> createState() => _EntityNoteSectionState();
}

/// Renders inline-editing Note inset card with multiline [UiField] and [EntityInlineEditorFooter].
class _EntityNoteEditCard extends StatelessWidget {
  /// Creates an [_EntityNoteEditCard].
  const _EntityNoteEditCard({
    required this.controller,
    required this.hasExistingNote,
    required this.errorText,
    required this.isBusy,
    required this.onChanged,
    required this.onClear,
    required this.onCancel,
    required this.onSave,
  });

  /// Multiline note text controller.
  final TextEditingController controller;

  /// Optional inline validation or persistence error message.
  final String? errorText;

  /// Shows the Clear button only when an existing note is persisted.
  final bool hasExistingNote;

  /// Disables input and footer controls while saving.
  final bool isBusy;

  /// Callback cancelling inline edit mode.
  final VoidCallback onCancel;

  /// Callback invoked when the note text changes.
  final ValueChanged<String> onChanged;

  /// Callback clearing the existing note.
  final VoidCallback onClear;

  /// Callback saving the edited note.
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiCard.inset(
      isEditing: true,
      headerIcon: Icons.description_outlined,
      headerTitle: localizations.taskNoteLabel,
      footer: EntityInlineEditorFooter(
        errorText: errorText,
        clearLabel: hasExistingNote ? localizations.inlineClearAction : null,
        onClear: hasExistingNote ? onClear : null,
        onCancel: onCancel,
        onSave: onSave,
        isBusy: isBusy,
      ),
      child: UiField(
        kind: UiFieldKind.multiline,
        controller: controller,
        hintText: localizations.taskNoteHint,
        maxLength: maxTdfNoteLength,
        autofocus: true,
        enabled: !isBusy,
        onChanged: onChanged,
      ),
    );
  }
}

/// Renders read-only Note inset card with Copy Note trigger, optional Edit pencil, and [SelectableText].
class _EntityNoteReadOnlyCard extends StatelessWidget {
  /// Creates an [_EntityNoteReadOnlyCard].
  const _EntityNoteReadOnlyCard({
    required this.note,
    required this.canEdit,
    required this.isBusy,
    required this.onCopyNote,
    required this.onStartEdit,
  });

  /// Whether the Edit pencil trigger is displayed.
  final bool canEdit;

  /// Disables the Edit pencil while busy.
  final bool isBusy;

  /// Multi-line note body preserving line breaks.
  final String note;

  /// Callback copying [note] to clipboard.
  final VoidCallback onCopyNote;

  /// Callback entering inline edit mode.
  final VoidCallback onStartEdit;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final localizations = AppLocalizations.of(context);

    return UiCard.inset(
      headerIcon: Icons.description_outlined,
      headerTitle: localizations.taskNoteLabel,
      headerTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          UiButton(
            leadingIcon: Icons.copy_outlined,
            variant: UiButtonVariant.icon,
            density: UiButtonDensity.dense,
            tooltip: localizations.tooltipCopyNote,
            onPressed: onCopyNote,
          ),
          if (canEdit) ...<Widget>[
            const SizedBox(width: 4.0),
            UiButton(
              leadingIcon: Icons.edit_outlined,
              variant: UiButtonVariant.icon,
              density: UiButtonDensity.dense,
              tooltip: localizations.actionEdit,
              onPressed: isBusy ? null : onStartEdit,
            ),
          ],
        ],
      ),
      child: SelectableText(
        note,
        style: tokens.typography.control.copyWith(
          color: tokens.colors.ink,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

/// Manages clipboard copy, text controller, and inline save state for [EntityNoteSection].
class _EntityNoteSectionState extends ConsumerState<EntityNoteSection> {
  late final TextEditingController _controller;

  String? _errorText;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.note ?? '');
  }

  @override
  void didUpdateWidget(covariant EntityNoteSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isEditing && widget.isEditing) {
      final seeded = widget.note ?? '';
      _controller.text = seeded;
      _controller.selection = TextSelection.collapsed(offset: seeded.length);
      _errorText = null;
      _isSubmitting = false;
    } else if (oldWidget.isEditing && !widget.isEditing) {
      _errorText = null;
      _isSubmitting = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final persistedNote = widget.note ?? '';
    if (!widget.isEditing) {
      return persistedNote.isNotEmpty
          ? _EntityNoteReadOnlyCard(
              note: persistedNote,
              canEdit: widget.canEdit,
              isBusy: widget.isBusy,
              onCopyNote: _handleCopyNote,
              onStartEdit: widget.onStartEdit,
            )
          : const SizedBox.shrink();
    }

    return _EntityNoteEditCard(
      controller: _controller,
      hasExistingNote: persistedNote.isNotEmpty,
      errorText: _errorText,
      isBusy: widget.isBusy || _isSubmitting,
      onChanged: _handleChanged,
      onClear: _handleClear,
      onCancel: widget.onCancelEdit,
      onSave: _handleSave,
    );
  }

  /// Clears transient inline error text when the user edits the note text.
  void _handleChanged(String value) {
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
  }

  /// Invokes [widget.onClear] while guarding against overlapping submissions.
  Future<void> _handleClear() async {
    if (widget.isBusy || _isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    try {
      await widget.onClear();
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Copies the persisted note to the system clipboard and shows confirmation notice.
  Future<void> _handleCopyNote() async {
    final text = widget.note;
    if (text == null || text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    final localizations = AppLocalizations.of(context);
    ref
        .read(floatingNoticeProvider.notifier)
        .showNotice(localizations.noteCopiedSnackBar);
    widget.onNoteCopied?.call();
  }

  /// Submits the edited note text to [widget.onSave] and displays any returned error inline.
  Future<void> _handleSave() async {
    if (widget.isBusy || _isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    try {
      final result = await widget.onSave(_controller.text);
      if (!mounted) {
        return;
      }
      switch (result) {
        case ActionSucceeded():
          break;
        case ActionValidationFailed(:final message):
        case ActionPersistFailed(:final message):
          setState(() => _errorText = message);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}
