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
import '../../services/app_logger.dart';
import 'clearable_text_field.dart';

/// Confirmation dialog requiring the user to enter the file name without `.tdf` before wiping a local or remote TDF file.
class WipeTdfDialog extends StatefulWidget {
  /// Creates a [WipeTdfDialog].
  const WipeTdfDialog({
    super.key,
    required this.target,
    required this.fileName,
    required this.expectedBaseName,
  });

  /// Expected file name without the `.tdf` extension required to enable confirmation.
  final String expectedBaseName;

  /// Full display file name (e.g., `tasks.tdf`).
  final String fileName;

  /// Target storage location (`local` or `remote`) to wipe.
  final WipeTdfTarget target;

  @override
  State<WipeTdfDialog> createState() => _WipeTdfDialogState();
}

/// Result returned when the user confirms [WipeTdfDialog].
@immutable
class WipeTdfDialogResult {
  /// Creates a [WipeTdfDialogResult].
  const WipeTdfDialogResult({required this.createBackup});

  /// Whether to create a `.bak` (or `.bak.001`+) backup before wiping the file if it exists.
  final bool createBackup;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WipeTdfDialogResult && other.createBackup == createBackup;
  }

  @override
  int get hashCode => createBackup.hashCode;
}

/// Identifies whether a wipe operation targets the local or remote TDF file.
enum WipeTdfTarget {
  /// Targets the local `.tdf` file on the device filesystem.
  local,

  /// Targets the remote `.tdf` file on the WebDAV server.
  remote,
}

/// Checkbox row inside [WipeTdfDialog] for enabling `.bak` backup creation before wiping.
class _WipeBackupCheckboxRow extends StatelessWidget {
  /// Creates a [_WipeBackupCheckboxRow].
  const _WipeBackupCheckboxRow({
    required this.createBackup,
    required this.onChanged,
  });

  /// Whether backup creation is currently checked.
  final bool createBackup;

  /// Callback invoked when the checkbox state changes.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!createBackup),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Checkbox(
              key: const ValueKey('wipe_tdf_backup_checkbox'),
              value: createBackup,
              onChanged: (value) => onChanged(value ?? false),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                localizations.wipeCreateBackupLabel,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Body content of [WipeTdfDialog] containing the description, filename confirmation input, and backup checkbox.
class _WipeDialogBody extends StatelessWidget {
  /// Creates a [_WipeDialogBody].
  const _WipeDialogBody({
    required this.controller,
    required this.createBackup,
    required this.description,
    required this.expectedBaseName,
    required this.onBackupChanged,
    required this.onInputChanged,
  });

  /// Controller for the file name confirmation input field.
  final TextEditingController controller;

  /// Whether `.bak` backup creation is selected.
  final bool createBackup;

  /// Localized dialog instruction text.
  final String description;

  /// Expected base file name without `.tdf`.
  final String expectedBaseName;

  /// Callback invoked when the backup checkbox state changes.
  final ValueChanged<bool> onBackupChanged;

  /// Callback invoked when the confirmation text changes.
  final VoidCallback onInputChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(description),
          const SizedBox(height: 16),
          ClearableTextField(
            fieldKey: const ValueKey('wipe_tdf_confirm_input'),
            controller: controller,
            autofocus: true,
            autocorrect: false,
            onChanged: (_) => onInputChanged(),
            onCleared: onInputChanged,
            decoration: InputDecoration(
              labelText: localizations.wipeConfirmInputLabel,
              hintText: expectedBaseName,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          _WipeBackupCheckboxRow(
            createBackup: createBackup,
            onChanged: onBackupChanged,
          ),
        ],
      ),
    );
  }
}

/// State for [WipeTdfDialog].
class _WipeTdfDialogState extends State<WipeTdfDialog> {
  late final TextEditingController _confirmController;
  bool _createBackup = false;

  /// Whether the entered confirmation text matches [widget.expectedBaseName].
  bool get _isConfirmEnabled =>
      _confirmController.text.trim() == widget.expectedBaseName;

  @override
  void initState() {
    super.initState();
    _confirmController = TextEditingController();
  }

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final title = _resolveTitle(localizations);
    final description = _resolveDescription(localizations);

    return AlertDialog(
      key: const ValueKey('wipe_tdf_dialog'),
      title: Text(title),
      content: _WipeDialogBody(
        controller: _confirmController,
        createBackup: _createBackup,
        description: description,
        expectedBaseName: widget.expectedBaseName,
        onBackupChanged: _handleBackupChanged,
        onInputChanged: _handleInputChanged,
      ),
      actions: [
        TextButton(
          key: const ValueKey('wipe_tdf_cancel_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.actionCancel),
        ),
        FilledButton(
          key: const ValueKey('wipe_tdf_confirm_button'),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: _isConfirmEnabled ? _handleConfirm : null,
          child: Text(localizations.actionWipeConfirm),
        ),
      ],
    );
  }

  /// Updates [_createBackup] when the user toggles the backup checkbox.
  void _handleBackupChanged(bool value) {
    setState(() {
      _createBackup = value;
    });
  }

  /// Closes the dialog returning the confirmed [WipeTdfDialogResult].
  void _handleConfirm() {
    if (!_isConfirmEnabled) {
      return;
    }
    AppLogger.info(
      LogTag.ui,
      'Confirmed wipe TDF dialog target=${widget.target.name} file=${widget.fileName} createBackup=$_createBackup',
    );
    Navigator.of(context).pop(WipeTdfDialogResult(createBackup: _createBackup));
  }

  /// Rebuilds the dialog action buttons when the confirmation input changes.
  void _handleInputChanged() {
    setState(() {});
  }

  /// Resolves the localized instruction text for [widget.target].
  String _resolveDescription(AppLocalizations localizations) {
    return switch (widget.target) {
      WipeTdfTarget.local => localizations.wipeLocalDialogDescription(
        widget.fileName,
        widget.expectedBaseName,
      ),
      WipeTdfTarget.remote => localizations.wipeRemoteDialogDescription(
        widget.fileName,
        widget.expectedBaseName,
      ),
    };
  }

  /// Resolves the localized dialog title for [widget.target].
  String _resolveTitle(AppLocalizations localizations) {
    return switch (widget.target) {
      WipeTdfTarget.local => localizations.wipeLocalDialogTitle,
      WipeTdfTarget.remote => localizations.wipeRemoteDialogTitle,
    };
  }
}

/// Displays [WipeTdfDialog] and returns a [WipeTdfDialogResult] when confirmed, or `null` when cancelled.
Future<WipeTdfDialogResult?> showWipeTdfDialog(
  BuildContext context, {
  required WipeTdfTarget target,
  required String fileName,
  required String expectedBaseName,
}) {
  return showDialog<WipeTdfDialogResult>(
    context: context,
    builder: (dialogContext) => WipeTdfDialog(
      target: target,
      fileName: fileName,
      expectedBaseName: expectedBaseName,
    ),
  );
}
