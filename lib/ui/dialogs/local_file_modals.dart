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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../presentation/settings_controller.dart';
import '../../presentation/shell_models.dart';
import '../../presentation/ui_telemetry.dart';
import '../widgets/entity_card_chrome.dart';

/// Body input field for [_RenameLocalFileModal].
class _RenameLocalFileBody extends StatelessWidget {
  /// Creates a [_RenameLocalFileBody].
  const _RenameLocalFileBody({
    required this.controller,
    required this.currentFileName,
    required this.isBusy,
    required this.errorText,
    required this.onChanged,
    required this.onSubmitted,
  });

  /// Pre-filled controller for the target filename.
  final TextEditingController controller;

  /// Current filename displayed as placeholder hint.
  final String currentFileName;

  /// Optional live or persisted error text.
  final String? errorText;

  /// Whether rename persistence is currently executing.
  final bool isBusy;

  /// Callback notified on input changes.
  final ValueChanged<String> onChanged;

  /// Callback submitting rename on `Enter`.
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiField(
      key: const ValueKey<String>('rename_local_file_input'),
      label: localizations.localFileNameInputLabel,
      hintText: currentFileName,
      controller: controller,
      autofocus: true,
      isMonospace: true,
      showClearButton: true,
      clearTooltip: localizations.tooltipClearInput,
      enabled: !isBusy,
      errorText: errorText,
      textInputAction: TextInputAction.done,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

/// Centered modal for renaming the active local `.tdf` file within its current directory.
class _RenameLocalFileModal extends ConsumerStatefulWidget {
  /// Creates a [_RenameLocalFileModal].
  const _RenameLocalFileModal({
    required this.currentFileName,
    required this.onClose,
  });

  /// Current local `.tdf` filename shown in the dialog subtitle.
  final String currentFileName;

  /// Callback closing the modal route.
  final VoidCallback onClose;

  @override
  ConsumerState<_RenameLocalFileModal> createState() =>
      _RenameLocalFileModalState();
}

/// State owning the pre-filled filename controller and validation readout for [_RenameLocalFileModal].
class _RenameLocalFileModalState extends ConsumerState<_RenameLocalFileModal> {
  late final TextEditingController _controller;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _stripTdfExtension(widget.currentFileName),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isBusy = ref.watch(
      settingsControllerProvider.select((state) => state.isBusy),
    );

    return UiDialogFrame(
      key: const ValueKey<String>('rename_local_file_modal'),
      title: localizations.renameLocalDialogTitle,
      subtitle: localizations.renameLocalDialogDescription(
        widget.currentFileName,
      ),
      size: UiDialogSize.small,
      closeTooltip: localizations.actionClose,
      onClose: widget.onClose,
      body: _RenameLocalFileBody(
        controller: _controller,
        currentFileName: widget.currentFileName,
        isBusy: isBusy,
        errorText: _resolveErrorText(localizations),
        onChanged: _handleInputChanged,
        onSubmitted: (_) async {
          await _handleSubmit();
        },
      ),
      footer: EntityModalActionFooter(
        cancelKey: const ValueKey<String>('rename_local_file_cancel_button'),
        confirmKey: const ValueKey<String>('rename_local_file_confirm_button'),
        confirmLabel: localizations.actionRenameLocalFile,
        confirmVariant: UiButtonVariant.primary,
        isBusy: isBusy,
        onCancel: widget.onClose,
        onConfirm: () async {
          await _handleSubmit();
        },
      ),
    );
  }

  /// Clears submission errors and refreshes inline validation when input text changes.
  void _handleInputChanged(String _) {
    setState(() => _submitError = null);
  }

  /// Commits the rename via [SettingsController.renameLocalFile] and closes on success.
  Future<void> _handleSubmit() async {
    final result = await ref
        .read(settingsControllerProvider.notifier)
        .renameLocalFile(_controller.text);
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        widget.onClose();
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        setState(() => _submitError = message);
    }
  }

  /// Resolves live client validation or persistence error text.
  String? _resolveErrorText(AppLocalizations localizations) {
    final raw = _controller.text;
    if (raw.isNotEmpty && !_isValidLocalFileName(raw)) {
      return localizations.localFileNameErrorInvalid;
    }
    return _submitError;
  }
}

/// Body pairing the existing `.tdf` file picker with the manual new-filename field inside [_SelectLocalFileModal].
class _SelectLocalFileBody extends StatelessWidget {
  /// Creates a [_SelectLocalFileBody].
  const _SelectLocalFileBody({
    required this.options,
    required this.selectedIds,
    required this.fileNameController,
    required this.isBusy,
    required this.errorText,
    required this.onPickExisting,
    required this.onInputChanged,
    required this.onSubmitted,
    required this.onRequestClose,
  });

  /// Optional live or persisted validation error text.
  final String? errorText;

  /// Controller for the chosen or newly entered filename.
  final TextEditingController fileNameController;

  /// Whether file selection is currently executing.
  final bool isBusy;

  /// Callback notified on manual filename changes.
  final ValueChanged<String> onInputChanged;

  /// Callback populating the field from a picked file row.
  final ValueChanged<UiPickerOption<String>> onPickExisting;

  /// Callback closing the modal on second `Escape` from search.
  final VoidCallback onRequestClose;

  /// Callback committing selection on `Enter`.
  final ValueChanged<String> onSubmitted;

  /// Monospace file picker rows.
  final List<UiPickerOption<String>> options;

  /// Currently highlighted file identifier set.
  final Set<String> selectedIds;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UiSearchablePicker<String>(
          key: const ValueKey<String>('select_local_file_picker'),
          options: options,
          selectedIds: selectedIds,
          selectionMode: UiPickerSelectionMode.single,
          showSelectedChips: false,
          searchPlaceholder: localizations.localFilePathHint,
          searchClearTooltip: localizations.tooltipClearSearch,
          emptyText: localizations.selectLocalDialogDescription,
          onToggleOption: onPickExisting,
          onRequestClose: onRequestClose,
        ),
        const SizedBox(height: 12.0),
        UiField(
          key: const ValueKey<String>('select_local_file_input'),
          label: localizations.localFileNameInputLabel,
          hintText: localizations.localFilePathHint,
          controller: fileNameController,
          isMonospace: true,
          showClearButton: true,
          clearTooltip: localizations.tooltipClearInput,
          enabled: !isBusy,
          errorText: errorText,
          textInputAction: TextInputAction.done,
          onChanged: onInputChanged,
          onSubmitted: onSubmitted,
        ),
      ],
    );
  }
}

/// Centered modal allowing selection of an existing local `.tdf` file or entry of a new `.tdf` filename.
class _SelectLocalFileModal extends ConsumerStatefulWidget {
  /// Creates a [_SelectLocalFileModal].
  const _SelectLocalFileModal({required this.onClose});

  /// Callback closing the modal route.
  final VoidCallback onClose;

  @override
  ConsumerState<_SelectLocalFileModal> createState() =>
      _SelectLocalFileModalState();
}

/// State owning discovered `.tdf` filenames, manual input controller, and submit validation for [_SelectLocalFileModal].
class _SelectLocalFileModalState extends ConsumerState<_SelectLocalFileModal> {
  late final List<String> _existingFileNames;
  late final TextEditingController _fileNameController;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    final settingsNotifier = ref.read(settingsControllerProvider.notifier);
    final currentFileName = ref.read(settingsControllerProvider).localFileName;
    _existingFileNames = settingsNotifier.listLocalTdfFileNames();
    _fileNameController = TextEditingController(text: currentFileName);
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isBusy = ref.watch(
      settingsControllerProvider.select((state) => state.isBusy),
    );
    final selectedName = _normalizeTdfFileName(_fileNameController.text);

    return UiDialogFrame(
      key: const ValueKey<String>('select_local_file_modal'),
      title: localizations.selectLocalDialogTitle,
      subtitle: localizations.selectLocalDialogDescription,
      size: UiDialogSize.medium,
      closeTooltip: localizations.actionClose,
      onClose: widget.onClose,
      body: _SelectLocalFileBody(
        options: _buildFileOptions(),
        selectedIds: selectedName.isEmpty
            ? const <String>{}
            : <String>{selectedName},
        fileNameController: _fileNameController,
        isBusy: isBusy,
        errorText: _resolveErrorText(localizations),
        onPickExisting: _handlePickExisting,
        onInputChanged: _handleInputChanged,
        onSubmitted: _triggerSubmitFromInput,
        onRequestClose: widget.onClose,
      ),
      footer: EntityModalActionFooter(
        cancelKey: const ValueKey<String>('select_local_file_cancel_button'),
        confirmKey: const ValueKey<String>('select_local_file_confirm_button'),
        confirmLabel: localizations.actionSelectLocalFile,
        confirmVariant: UiButtonVariant.primary,
        isBusy: isBusy,
        onCancel: widget.onClose,
        onConfirm: _triggerSubmit,
      ),
    );
  }

  /// Maps discovered local `.tdf` filenames into monospace picker options.
  List<UiPickerOption<String>> _buildFileOptions() {
    return <UiPickerOption<String>>[
      for (final fileName in _existingFileNames)
        UiPickerOption<String>(
          id: fileName,
          value: fileName,
          label: fileName,
          icon: Icons.description_outlined,
          isMonospace: true,
        ),
    ];
  }

  /// Clears stale submission error and updates selection highlight on manual text input.
  void _handleInputChanged(String _) {
    setState(() => _submitError = null);
  }

  /// Populates the filename field when an existing `.tdf` option is selected.
  void _handlePickExisting(UiPickerOption<String> option) {
    setState(() {
      _submitError = null;
      _fileNameController.value = TextEditingValue(
        text: option.value,
        selection: TextSelection.collapsed(offset: option.value.length),
      );
    });
  }

  /// Submits the chosen `.tdf` filename via [SettingsController.selectLocalFile].
  Future<void> _handleSubmit() async {
    final result = await ref
        .read(settingsControllerProvider.notifier)
        .selectLocalFile(chosenFileName: _fileNameController.text);
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        widget.onClose();
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        setState(() => _submitError = message);
    }
  }

  /// Resolves live client validation or controller error text.
  String? _resolveErrorText(AppLocalizations localizations) {
    final raw = _fileNameController.text;
    if (raw.isNotEmpty && !_isValidLocalFileName(raw)) {
      return localizations.localFileNameErrorInvalid;
    }
    return _submitError;
  }

  /// Dispatches async local file selection from synchronous callbacks.
  void _triggerSubmit() {
    _handleSubmit();
  }

  /// Dispatches async local file selection from text submission callbacks.
  void _triggerSubmitFromInput(String _) {
    _handleSubmit();
  }
}

/// Presents the local `.tdf` file rename modal pre-filled with [currentFileName].
Future<void> showRenameLocalFileModal(
  BuildContext context, {
  required String currentFileName,
}) {
  UiTelemetry.logDialogOpened('rename_local_file');
  final localizations = AppLocalizations.of(context);
  return UiDialogFrame.showModal<void>(
    context: context,
    barrierLabel: localizations.renameLocalDialogTitle,
    builder: (modalContext) => _RenameLocalFileModal(
      currentFileName: currentFileName,
      onClose: () => Navigator.of(modalContext).maybePop(),
    ),
  );
}

/// Presents the local `.tdf` file selection modal combining discovered files and new filename input.
Future<void> showSelectLocalFileModal(BuildContext context) {
  UiTelemetry.logDialogOpened('select_local_file');
  final localizations = AppLocalizations.of(context);
  return UiDialogFrame.showModal<void>(
    context: context,
    barrierLabel: localizations.selectLocalDialogTitle,
    builder: (modalContext) => _SelectLocalFileModal(
      onClose: () => Navigator.of(modalContext).maybePop(),
    ),
  );
}

/// Returns `true` when [value] contains ASCII control characters (`0x00..0x1F`) or `DEL` (`0x7F`).
bool _containsControlCharacters(String value) {
  for (var i = 0; i < value.length; i++) {
    final codeUnit = value.codeUnitAt(i);
    if (codeUnit < 0x20 || codeUnit == 0x7F) {
      return true;
    }
  }
  return false;
}

/// Validates that [rawValue] is a safe single local `.tdf` filename without path separators, `..`, or control characters.
bool _isValidLocalFileName(String rawValue) {
  if (_containsControlCharacters(rawValue)) {
    return false;
  }
  final trimmed = rawValue.trim();
  if (trimmed.isEmpty ||
      trimmed == '.' ||
      trimmed == '..' ||
      trimmed.contains('/') ||
      trimmed.contains(r'\') ||
      trimmed.contains('..')) {
    return false;
  }
  return _stripTdfExtension(trimmed).isNotEmpty;
}

/// Normalizes a trimmed filename by appending `.tdf` when absent so picker selection highlights consistently.
String _normalizeTdfFileName(String rawValue) {
  final trimmed = rawValue.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (trimmed.toLowerCase().endsWith('.tdf')) {
    return trimmed;
  }
  return '$trimmed.tdf';
}

/// Removes a trailing `.tdf` extension case-insensitively when present.
String _stripTdfExtension(String fileName) {
  final trimmed = fileName.trim();
  if (trimmed.length >= 4 && trimmed.toLowerCase().endsWith('.tdf')) {
    return trimmed.substring(0, trimmed.length - 4);
  }
  return trimmed;
}
