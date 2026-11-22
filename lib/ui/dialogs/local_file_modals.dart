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

import '../../l10n/app_localizations.dart';
import '../../models/app_workspace.dart';
import '../../models/tdf_file_path.dart';
import '../../providers/config_providers.dart';
import '../../providers/settings_draft_providers.dart';
import '../../providers/shell_providers.dart';
import '../../providers/ui_telemetry.dart';
import '../../providers/workspace_providers.dart';
import '../components/ui_dialog_frame.dart';
import '../components/ui_searchable_picker.dart';
import '../primitives/ui_button.dart';
import '../primitives/ui_field.dart';
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
      text: TdfFilePath.extractFileBaseName(widget.currentFileName),
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
      settingsDraftProvider.select((state) => state.isStorageOperationBusy),
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
        onSubmitted: _triggerSubmitFromInput,
      ),
      footer: EntityModalActionFooter(
        cancelKey: const ValueKey<String>('rename_local_file_cancel_button'),
        confirmKey: const ValueKey<String>('rename_local_file_confirm_button'),
        confirmLabel: localizations.actionRenameLocalFile,
        confirmVariant: UiButtonVariant.primary,
        isBusy: isBusy,
        onCancel: widget.onClose,
        onConfirm: _triggerSubmit,
      ),
    );
  }

  /// Clears submission errors and refreshes inline validation when input text changes.
  void _handleInputChanged(String _) {
    setState(() => _submitError = null);
  }

  /// Commits the rename via [SettingsDraftNotifier.renameLocalFile] and closes on success.
  Future<void> _handleSubmit() async {
    final result = await ref
        .read(settingsDraftProvider.notifier)
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

  /// Dispatches async local file rename from synchronous button callbacks.
  void _triggerSubmit() {
    unawaited(_handleSubmit());
  }

  /// Dispatches async local file rename from text submission callbacks.
  void _triggerSubmitFromInput(String _) {
    unawaited(_handleSubmit());
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
    final settingsNotifier = ref.read(settingsDraftProvider.notifier);
    final localFilePath =
        ref.read(webDavConfigProvider).asData?.value.localFilePath ??
        ref.read(activeWorkspaceProvider).asData?.value.config.localFilePath ??
        '';
    final currentFileName = TdfFilePath.extractFileNameFromPath(localFilePath);
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
      settingsDraftProvider.select((state) => state.isStorageOperationBusy),
    );
    final selectedName = _normalizeTdfFileName(_fileNameController.text);

    return UiDialogFrame(
      key: const ValueKey<String>('select_local_file_modal'),
      title: localizations.selectLocalDialogTitle,
      subtitle: localizations.selectLocalDialogDescription,
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

  /// Submits the chosen `.tdf` filename via [SettingsDraftNotifier.selectLocalFile].
  Future<void> _handleSubmit() async {
    final result = await ref
        .read(settingsDraftProvider.notifier)
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

  /// Resolves live client validation or persistence error text.
  String? _resolveErrorText(AppLocalizations localizations) {
    final raw = _fileNameController.text;
    if (raw.isNotEmpty && !_isValidLocalFileName(raw)) {
      return localizations.localFileNameErrorInvalid;
    }
    return _submitError;
  }

  /// Dispatches async local file selection from synchronous callbacks.
  void _triggerSubmit() {
    unawaited(_handleSubmit());
  }

  /// Dispatches async local file selection from text submission callbacks.
  void _triggerSubmitFromInput(String _) {
    unawaited(_handleSubmit());
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

/// Validates that [rawValue] is a safe single local `.tdf` filename without path separators, `..`, or control characters.
bool _isValidLocalFileName(String rawValue) {
  if (AppWorkspace.hasControlCharacters(rawValue)) {
    return false;
  }
  final trimmed = rawValue.trim();
  return TdfFilePath.isValidSingleFileName(trimmed) && !trimmed.contains('..');
}

/// Normalizes a trimmed filename by appending `.tdf` when absent so picker selection highlights consistently.
String _normalizeTdfFileName(String rawValue) {
  final trimmed = rawValue.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return TdfFilePath.ensureTdfExtension(trimmed);
}
