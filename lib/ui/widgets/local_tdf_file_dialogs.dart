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

import '../../l10n/app_localizations.dart';
import '../../repositories/local_file_repository.dart';
import '../../services/app_logger.dart';
import 'clearable_text_field.dart';

/// Dialog for renaming the local `.tdf` file within its current directory.
class RenameLocalTdfDialog extends StatefulWidget {
  /// Creates a [RenameLocalTdfDialog].
  const RenameLocalTdfDialog({super.key, required this.currentFileName});

  /// Current display file name (e.g., `tasks.tdf`).
  final String currentFileName;

  @override
  State<RenameLocalTdfDialog> createState() => _RenameLocalTdfDialogState();
}

/// Dialog for selecting an existing `.tdf` file or entering a new `.tdf` file name in the storage directory.
class SelectLocalTdfDialog extends StatefulWidget {
  /// Creates a [SelectLocalTdfDialog].
  const SelectLocalTdfDialog({
    super.key,
    required this.currentFileName,
    required this.existingFileNames,
  });

  /// Currently configured `.tdf` file name.
  final String currentFileName;

  /// Sorted `.tdf` file names discovered in the storage directory.
  final List<String> existingFileNames;

  @override
  State<SelectLocalTdfDialog> createState() => _SelectLocalTdfDialogState();
}

/// Body content of [RenameLocalTdfDialog].
class _RenameDialogBody extends StatelessWidget {
  /// Creates a [_RenameDialogBody].
  const _RenameDialogBody({
    required this.controller,
    required this.currentFileName,
    required this.errorText,
    required this.onChanged,
    required this.onSubmitted,
  });

  /// Text controller for the new file name input.
  final TextEditingController controller;

  /// Current `.tdf` file name displayed in the description.
  final String currentFileName;

  /// Optional validation error message.
  final String? errorText;

  /// Callback invoked when the input text changes.
  final VoidCallback onChanged;

  /// Callback invoked when the user submits the input.
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(localizations.renameLocalDialogDescription(currentFileName)),
          const SizedBox(height: 16),
          ClearableTextField(
            fieldKey: const ValueKey('rename_local_tdf_input'),
            clearButtonKey: const ValueKey(
              'rename_local_tdf_input_clear_button',
            ),
            controller: controller,
            autofocus: true,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onChanged: (_) => onChanged(),
            onCleared: onChanged,
            onSubmitted: (_) => onSubmitted(),
            decoration: InputDecoration(
              labelText: localizations.localFileNameInputLabel,
              hintText: currentFileName,
              errorText: errorText,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

/// State for [RenameLocalTdfDialog].
class _RenameLocalTdfDialogState extends State<RenameLocalTdfDialog> {
  late final TextEditingController _controller;

  /// Validation error message when the user has entered an invalid file name.
  String? get _errorText {
    final raw = _controller.text;
    if (raw.isEmpty || _isValidInput) {
      return null;
    }
    return AppLocalizations.of(context).localFileNameErrorInvalid;
  }

  /// Whether the entered file name is a valid single `.tdf` file name.
  bool get _isValidInput =>
      LocalFileRepository.isValidSingleFileName(_controller.text);

  @override
  void initState() {
    super.initState();
    final baseName = LocalFileRepository.extractFileBaseName(
      widget.currentFileName,
    );
    _controller = TextEditingController(text: baseName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('rename_local_tdf_dialog'),
      title: Text(localizations.renameLocalDialogTitle),
      content: _RenameDialogBody(
        controller: _controller,
        currentFileName: widget.currentFileName,
        errorText: _errorText,
        onChanged: _handleChanged,
        onSubmitted: _handleConfirm,
      ),
      actions: [
        TextButton(
          key: const ValueKey('rename_local_tdf_cancel_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.actionCancel),
        ),
        FilledButton(
          key: const ValueKey('rename_local_tdf_confirm_button'),
          onPressed: _isValidInput ? _handleConfirm : null,
          child: Text(localizations.actionRenameLocalFile),
        ),
      ],
    );
  }

  /// Rebuilds the dialog state when the text input changes.
  void _handleChanged() {
    setState(() {});
  }

  /// Closes the dialog returning the normalized `.tdf` file name.
  void _handleConfirm() {
    if (!_isValidInput) {
      return;
    }
    final normalized = LocalFileRepository.ensureTdfExtension(_controller.text);
    AppLogger.info(
      LogTag.ui,
      'Confirmed rename local TDF dialog from=${widget.currentFileName} to=$normalized',
    );
    Navigator.of(context).pop(normalized);
  }
}

/// Body content of [SelectLocalTdfDialog].
class _SelectDialogBody extends StatelessWidget {
  /// Creates a [_SelectDialogBody].
  const _SelectDialogBody({
    required this.controller,
    required this.errorText,
    required this.existingFileNames,
    required this.onChanged,
    required this.onSelectExisting,
    required this.onSubmitted,
  });

  /// Text controller for the selected or new `.tdf` file name.
  final TextEditingController controller;

  /// Optional validation error text.
  final String? errorText;

  /// Existing `.tdf` file names in the storage directory.
  final List<String> existingFileNames;

  /// Callback invoked when the input text changes.
  final VoidCallback onChanged;

  /// Callback invoked when an existing file tile is tapped.
  final ValueChanged<String> onSelectExisting;

  /// Callback invoked when the user submits the input.
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(localizations.selectLocalDialogDescription),
          if (existingFileNames.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SelectExistingFilesList(
              existingFileNames: existingFileNames,
              selectedText: controller.text,
              onSelectExisting: onSelectExisting,
            ),
          ],
          const SizedBox(height: 14),
          ClearableTextField(
            fieldKey: const ValueKey('select_local_tdf_input'),
            clearButtonKey: const ValueKey(
              'select_local_tdf_input_clear_button',
            ),
            controller: controller,
            autofocus: existingFileNames.isEmpty,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onChanged: (_) => onChanged(),
            onCleared: onChanged,
            onSubmitted: (_) => onSubmitted(),
            decoration: InputDecoration(
              labelText: localizations.localFileNameInputLabel,
              errorText: errorText,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Scrollable list of existing `.tdf` files inside [_SelectDialogBody].
class _SelectExistingFilesList extends StatelessWidget {
  /// Creates a [_SelectExistingFilesList].
  const _SelectExistingFilesList({
    required this.existingFileNames,
    required this.selectedText,
    required this.onSelectExisting,
  });

  /// Sorted `.tdf` file names in the directory.
  final List<String> existingFileNames;

  /// Callback invoked when a file name is tapped.
  final ValueChanged<String> onSelectExisting;

  /// Current text in the input field used to highlight the matching entry.
  final String selectedText;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final normalizedSelected = LocalFileRepository.ensureTdfExtension(
      selectedText,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 180),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: existingFileNames.length,
          itemBuilder: (context, index) {
            final name = existingFileNames[index];
            final isSelected = name == normalizedSelected;
            return ListTile(
              key: ValueKey('select_local_tdf_item_$name'),
              dense: true,
              selected: isSelected,
              leading: const Icon(Icons.insert_drive_file_outlined, size: 18),
              title: Text(
                name,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              onTap: () => onSelectExisting(name),
            );
          },
        ),
      ),
    );
  }
}

/// State for [SelectLocalTdfDialog].
class _SelectLocalTdfDialogState extends State<SelectLocalTdfDialog> {
  late final TextEditingController _controller;

  /// Validation error message when the user has entered an invalid file name.
  String? get _errorText {
    final raw = _controller.text;
    if (raw.isEmpty || _isValidInput) {
      return null;
    }
    return AppLocalizations.of(context).localFileNameErrorInvalid;
  }

  /// Whether the entered file name is a valid single `.tdf` file name.
  bool get _isValidInput =>
      LocalFileRepository.isValidSingleFileName(_controller.text);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentFileName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('select_local_tdf_dialog'),
      title: Text(localizations.selectLocalDialogTitle),
      content: _SelectDialogBody(
        controller: _controller,
        errorText: _errorText,
        existingFileNames: widget.existingFileNames,
        onChanged: _handleChanged,
        onSelectExisting: _handleSelectExisting,
        onSubmitted: _handleConfirm,
      ),
      actions: [
        TextButton(
          key: const ValueKey('select_local_tdf_cancel_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.actionCancel),
        ),
        FilledButton(
          key: const ValueKey('select_local_tdf_confirm_button'),
          onPressed: _isValidInput ? _handleConfirm : null,
          child: Text(localizations.actionSelectLocalFile),
        ),
      ],
    );
  }

  /// Rebuilds the dialog when the input changes.
  void _handleChanged() {
    setState(() {});
  }

  /// Closes the dialog returning the normalized `.tdf` file name.
  void _handleConfirm() {
    if (!_isValidInput) {
      return;
    }
    final normalized = LocalFileRepository.ensureTdfExtension(_controller.text);
    AppLogger.info(
      LogTag.ui,
      'Confirmed select local TDF dialog file=$normalized',
    );
    Navigator.of(context).pop(normalized);
  }

  /// Populates the text field when an existing `.tdf` file is tapped.
  void _handleSelectExisting(String fileName) {
    setState(() {
      _controller.text = fileName;
    });
  }
}

/// Displays [RenameLocalTdfDialog] and returns the normalized `.tdf` file name when confirmed, or `null` when cancelled.
Future<String?> showRenameLocalTdfDialog(
  BuildContext context, {
  required String currentFileName,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) =>
        RenameLocalTdfDialog(currentFileName: currentFileName),
  );
}

/// Displays [SelectLocalTdfDialog] and returns the normalized `.tdf` file name when confirmed, or `null` when cancelled.
Future<String?> showSelectLocalTdfDialog(
  BuildContext context, {
  required String currentFileName,
  required List<String> existingFileNames,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => SelectLocalTdfDialog(
      currentFileName: currentFileName,
      existingFileNames: existingFileNames,
    ),
  );
}
