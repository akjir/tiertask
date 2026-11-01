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
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/task_board.dart';
import '../models/tdf_metadata.dart';
import '../providers/task_providers.dart';

const Color _accentMagenta = Color(0xFFEB06FF);
const Color _canvasColor = Color(0xFF344FA1);
const Color _cardColor = Color(0xFF071A52);
const Color _mutedLabelColor = Color(0xFF9BA8E5);

/// Dedicated Google Keep style screen for creating, renaming, and deleting labels while displaying open task counts.
class EditLabelsScreen extends ConsumerStatefulWidget {
  /// Creates an [EditLabelsScreen] widget.
  const EditLabelsScreen({super.key, this.autofocusCreate = false});

  /// Whether the create-label text field should request focus automatically when opened.
  final bool autofocusCreate;

  @override
  ConsumerState<EditLabelsScreen> createState() => _EditLabelsScreenState();
}

/// Top row inside [EditLabelsScreen] for creating a new label.
class _CreateLabelRow extends StatelessWidget {
  /// Creates a [_CreateLabelRow].
  const _CreateLabelRow({
    required this.autofocus,
    required this.controller,
    required this.hasText,
    required this.onClear,
    required this.onSubmit,
  });

  /// Whether the text field requests focus automatically.
  final bool autofocus;

  /// Controller for the new label name input.
  final TextEditingController controller;

  /// Whether the input field currently contains non-whitespace text.
  final bool hasText;

  /// Callback invoked when the leading clear or add icon is pressed.
  final VoidCallback onClear;

  /// Callback invoked when the new label is submitted.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('create_label_clear_button'),
            tooltip: hasText
                ? localizations.actionCancel
                : localizations.actionAdd,
            icon: Icon(
              hasText ? Icons.close_rounded : Icons.add_rounded,
              color: _mutedLabelColor,
            ),
            onPressed: hasText ? onClear : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const ValueKey('create_label_input'),
              controller: controller,
              autofocus: autofocus,
              cursorColor: _accentMagenta,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                hintText: localizations.createNewLabel,
                hintStyle: const TextStyle(color: _mutedLabelColor),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('create_label_submit_button'),
            tooltip: localizations.actionAdd,
            icon: Icon(
              Icons.check_rounded,
              color: hasText ? _accentMagenta : _mutedLabelColor,
            ),
            onPressed: hasText ? onSubmit : null,
          ),
        ],
      ),
    );
  }
}

/// State for [EditLabelsScreen].
class _EditLabelsScreenState extends ConsumerState<EditLabelsScreen> {
  final TextEditingController _createController = TextEditingController();
  String? _editingLabelId;
  final TextEditingController _renameController = TextEditingController();

  bool get _hasCreateText => _createController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _createController.addListener(_handleCreateInputChanged);
  }

  @override
  void dispose() {
    _createController.removeListener(_handleCreateInputChanged);
    _createController.dispose();
    _renameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final board =
        ref.watch(taskNotifierProvider).asData?.value ?? TaskBoard.empty();
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      key: const ValueKey('edit_labels_screen'),
      backgroundColor: _canvasColor,
      appBar: AppBar(
        backgroundColor: _cardColor,
        foregroundColor: Colors.white,
        title: Text(localizations.editLabelsTitle),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: _cardColor,
              child: _CreateLabelRow(
                autofocus: widget.autofocusCreate,
                controller: _createController,
                hasText: _hasCreateText,
                onClear: _clearCreateInput,
                onSubmit: _submitCreateLabel,
              ),
            ),
            const Divider(height: 1, color: _canvasColor),
            Expanded(
              child: board.labels.isEmpty
                  ? _EmptyLabelsView(message: localizations.emptyLabelsHint)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: board.labels.length,
                      itemBuilder: (context, index) {
                        final label = board.labels[index];
                        final isEditing = _editingLabelId == label.id;
                        return _EditableLabelRow(
                          key: ValueKey('edit_label_row_${label.id}'),
                          isEditing: isEditing,
                          label: label,
                          openTaskCount: board.openTaskCountForLabel(label.id),
                          renameController: isEditing
                              ? _renameController
                              : null,
                          onDelete: () => _deleteLabel(label.id),
                          onSaveRename: () => _saveRename(label.id),
                          onStartRename: () => _startRename(label),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Clears the create-label input field.
  void _clearCreateInput() {
    _createController.clear();
  }

  /// Deletes the label with [labelId] and clears edit state if it was being renamed.
  Future<void> _deleteLabel(String labelId) async {
    if (_editingLabelId == labelId) {
      setState(() {
        _editingLabelId = null;
        _renameController.clear();
      });
    }
    await ref.read(taskNotifierProvider.notifier).deleteLabel(labelId);
  }

  /// Rebuilds when the create-label text changes.
  void _handleCreateInputChanged() {
    setState(() {});
  }

  /// Saves the updated name for [labelId] and exits inline rename mode.
  Future<void> _saveRename(String labelId) async {
    final trimmed = _renameController.text.trim();
    setState(() {
      _editingLabelId = null;
      _renameController.clear();
    });
    if (trimmed.isEmpty) {
      return;
    }
    await ref.read(taskNotifierProvider.notifier).renameLabel(labelId, trimmed);
  }

  /// Enters inline rename mode for [label].
  void _startRename(TdfLabel label) {
    setState(() {
      _editingLabelId = label.id;
      _renameController.value = TextEditingValue(
        text: label.name,
        selection: TextSelection.collapsed(offset: label.name.length),
      );
    });
  }

  /// Creates a new label from [_createController] and clears the input field.
  Future<void> _submitCreateLabel() async {
    final trimmed = _createController.text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _createController.clear();
    await ref.read(taskNotifierProvider.notifier).addLabel(trimmed);
  }
}

/// Single existing label row inside [EditLabelsScreen] with icon, title or rename field, task count badge, rename button, and delete button.
class _EditableLabelRow extends StatelessWidget {
  /// Creates an [_EditableLabelRow].
  const _EditableLabelRow({
    super.key,
    required this.isEditing,
    required this.label,
    required this.openTaskCount,
    required this.renameController,
    required this.onDelete,
    required this.onSaveRename,
    required this.onStartRename,
  });

  /// Whether this row is currently in inline rename mode.
  final bool isEditing;

  /// Label displayed by this row.
  final TdfLabel label;

  /// Callback invoked when the delete icon button is tapped.
  final VoidCallback onDelete;

  /// Callback invoked when the inline rename is saved.
  final VoidCallback onSaveRename;

  /// Callback invoked when the edit icon button is tapped.
  final VoidCallback onStartRename;

  /// Number of open tasks referencing [label].
  final int openTaskCount;

  /// Controller used when [isEditing] is true, or `null` otherwise.
  final TextEditingController? renameController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final iconColor = _resolveLabelColor(label.color);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                key: ValueKey('delete_label_button_${label.id}'),
                tooltip: localizations.tooltipDeleteLabel,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: _mutedLabelColor,
                ),
                onPressed: onDelete,
              ),
              Icon(Icons.label_outline_rounded, color: iconColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: _EditableLabelTitle(
                  isEditing: isEditing,
                  label: label,
                  renameController: renameController,
                  onSaveRename: onSaveRename,
                ),
              ),
              const SizedBox(width: 8),
              Badge.count(
                key: ValueKey('edit_label_badge_${label.id}'),
                count: openTaskCount,
              ),
              const SizedBox(width: 4),
              IconButton(
                key: ValueKey('rename_label_button_${label.id}'),
                tooltip: isEditing
                    ? localizations.actionSave
                    : localizations.tooltipRenameLabel,
                icon: Icon(
                  isEditing ? Icons.check_rounded : Icons.edit_outlined,
                  color: isEditing ? _accentMagenta : _mutedLabelColor,
                ),
                onPressed: isEditing ? onSaveRename : onStartRename,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Resolves the optional `#RRGGBB` color of [rawHex] or falls back to [_mutedLabelColor].
  static Color _resolveLabelColor(String? rawHex) {
    final parsed = TdfColor.tryParseArgb(rawHex);
    return parsed != null ? Color(parsed) : _mutedLabelColor;
  }
}

/// Renders either the static label name or an inline [TextField] when renaming inside [_EditableLabelRow].
class _EditableLabelTitle extends StatelessWidget {
  /// Creates an [_EditableLabelTitle].
  const _EditableLabelTitle({
    required this.isEditing,
    required this.label,
    required this.renameController,
    required this.onSaveRename,
  });

  /// Whether inline editing is active.
  final bool isEditing;

  /// Label entry to display.
  final TdfLabel label;

  /// Callback invoked when the user submits the inline text field.
  final VoidCallback onSaveRename;

  /// Active text controller when [isEditing] is true.
  final TextEditingController? renameController;

  @override
  Widget build(BuildContext context) {
    if (isEditing && renameController != null) {
      return TextField(
        key: ValueKey('rename_label_input_${label.id}'),
        controller: renameController,
        autofocus: true,
        cursorColor: _accentMagenta,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => onSaveRename(),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
        ),
      );
    }
    return Text(
      label.name,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// Empty-state message shown in [EditLabelsScreen] when no labels exist.
class _EmptyLabelsView extends StatelessWidget {
  /// Creates an [_EmptyLabelsView].
  const _EmptyLabelsView({required this.message});

  /// Localized empty-state message text.
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          style: const TextStyle(color: _mutedLabelColor, fontSize: 15),
        ),
      ),
    );
  }
}
