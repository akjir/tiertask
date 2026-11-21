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

/// Centered destructive confirmation modal enforcing the `U-UX-005` typed-filename guard before wiping a `.tdf` file.
class _WipeTdfModal extends ConsumerStatefulWidget {
  /// Creates a [_WipeTdfModal].
  const _WipeTdfModal({
    required this.isRemote,
    required this.fileName,
    required this.baseName,
    required this.onClose,
  });

  /// Required filename without `.tdf` extension unlocking the danger button.
  final String baseName;

  /// Full display `.tdf` filename shown in the modal description.
  final String fileName;

  /// Whether the wipe targets the remote WebDAV file (`true`) or local file (`false`).
  final bool isRemote;

  /// Callback closing this modal route.
  final VoidCallback onClose;

  @override
  ConsumerState<_WipeTdfModal> createState() => _WipeTdfModalState();
}

/// Body pairing the typed-filename confirmation field and default-checked `.bak` toggle inside [_WipeTdfModal].
class _WipeTdfModalBody extends StatelessWidget {
  /// Creates a [_WipeTdfModalBody].
  const _WipeTdfModalBody({
    required this.baseName,
    required this.confirmController,
    required this.createBackup,
    required this.isBusy,
    required this.errorMessage,
    required this.onInputChanged,
    required this.onSubmitted,
    required this.onBackupChanged,
  });

  /// Expected filename without `.tdf` shown as field hint.
  final String baseName;

  /// Controller for typed-filename confirmation input.
  final TextEditingController confirmController;

  /// Whether `.bak` backup creation is currently checked.
  final bool createBackup;

  /// Optional persistence error text.
  final String? errorMessage;

  /// Whether wipe persistence is currently executing.
  final bool isBusy;

  /// Callback toggling backup creation.
  final ValueChanged<bool> onBackupChanged;

  /// Callback notified on confirmation input changes.
  final ValueChanged<String> onInputChanged;

  /// Callback invoked when user submits via `Enter`.
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UiField(
          key: const ValueKey<String>('wipe_tdf_confirm_input'),
          label: localizations.wipeConfirmInputLabel,
          hintText: baseName,
          controller: confirmController,
          autofocus: true,
          isMonospace: true,
          showClearButton: true,
          clearTooltip: localizations.tooltipClearInput,
          enabled: !isBusy,
          errorText: errorMessage,
          textInputAction: TextInputAction.done,
          onChanged: onInputChanged,
          onSubmitted: onSubmitted,
        ),
        const SizedBox(height: 12.0),
        UiToggleRow(
          key: const ValueKey<String>('wipe_tdf_backup_toggle'),
          label: localizations.wipeCreateBackupLabel,
          value: createBackup,
          enabled: !isBusy,
          onChanged: onBackupChanged,
        ),
      ],
    );
  }
}

/// State owning typed confirmation text, default-checked backup toggle, and error reporting for [_WipeTdfModal].
class _WipeTdfModalState extends ConsumerState<_WipeTdfModal> {
  final TextEditingController _confirmController = TextEditingController();
  bool _createBackup = true;
  String? _errorMessage;

  /// Whether trimmed user input exactly matches [widget.baseName].
  bool get _isConfirmEnabled =>
      _confirmController.text.trim() == widget.baseName;

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isBusy = ref.watch(
      settingsControllerProvider.select((state) => state.isBusy),
    );
    return UiDialogFrame(
      key: ValueKey<String>(
        widget.isRemote ? 'wipe_remote_tdf_modal' : 'wipe_local_tdf_modal',
      ),
      title: _resolveTitle(localizations),
      subtitle: _resolveSubtitle(localizations),
      size: UiDialogSize.small,
      closeTooltip: localizations.actionClose,
      onClose: widget.onClose,
      body: _WipeTdfModalBody(
        baseName: widget.baseName,
        confirmController: _confirmController,
        createBackup: _createBackup,
        isBusy: isBusy,
        errorMessage: _errorMessage,
        onInputChanged: _handleInputChanged,
        onSubmitted: (_) => _triggerConfirmIfReady(isBusy: isBusy),
        onBackupChanged: _handleBackupChanged,
      ),
      footer: EntityModalActionFooter(
        cancelKey: const ValueKey<String>('wipe_tdf_cancel_button'),
        confirmKey: const ValueKey<String>('wipe_tdf_confirm_button'),
        confirmLabel: localizations.actionWipeConfirm,
        confirmVariant: UiButtonVariant.danger,
        isBusy: isBusy,
        onCancel: widget.onClose,
        onConfirm: _isConfirmEnabled ? _triggerConfirm : null,
      ),
    );
  }

  /// Toggles `.bak` backup creation before wiping.
  void _handleBackupChanged(bool nextValue) {
    setState(() => _createBackup = nextValue);
  }

  /// Commits local or remote `.tdf` wipe through [SettingsController] and closes on success.
  Future<void> _handleConfirm() async {
    if (!_isConfirmEnabled) {
      return;
    }
    final notifier = ref.read(settingsControllerProvider.notifier);
    final result = widget.isRemote
        ? await notifier.wipeRemoteFile(createBackup: _createBackup)
        : await notifier.wipeLocalFile(createBackup: _createBackup);
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        widget.onClose();
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        setState(() => _errorMessage = message);
    }
  }

  /// Re-evaluates the typed-filename guard whenever the input changes.
  void _handleInputChanged(String _) {
    setState(() => _errorMessage = null);
  }

  /// Resolves the localized subtitle for local or remote `.tdf` wipe confirmation.
  String _resolveSubtitle(AppLocalizations localizations) {
    return widget.isRemote
        ? localizations.wipeRemoteDialogDescription(
            widget.fileName,
            widget.baseName,
          )
        : localizations.wipeLocalDialogDescription(
            widget.fileName,
            widget.baseName,
          );
  }

  /// Resolves the localized heading for local or remote `.tdf` wipe confirmation.
  String _resolveTitle(AppLocalizations localizations) {
    return widget.isRemote
        ? localizations.wipeRemoteDialogTitle
        : localizations.wipeLocalDialogTitle;
  }

  /// Dispatches async wipe confirmation from synchronous button callbacks.
  void _triggerConfirm() {
    _handleConfirm();
  }

  /// Dispatches async wipe confirmation on `Enter` when the guard passes and idle.
  void _triggerConfirmIfReady({required bool isBusy}) {
    if (_isConfirmEnabled && !isBusy) {
      _handleConfirm();
    }
  }
}

/// Presents the typed-filename destructive confirmation modal for wiping a local or remote `.tdf` file (`U-UX-005`).
Future<void> showWipeTdfModal(
  BuildContext context, {
  required bool isRemote,
  required String fileName,
  required String baseName,
}) {
  UiTelemetry.logDialogOpened(isRemote ? 'wipe_remote_tdf' : 'wipe_local_tdf');
  final localizations = AppLocalizations.of(context);
  return UiDialogFrame.showModal<void>(
    context: context,
    barrierLabel: isRemote
        ? localizations.wipeRemoteDialogTitle
        : localizations.wipeLocalDialogTitle,
    builder: (modalContext) => _WipeTdfModal(
      isRemote: isRemote,
      fileName: fileName,
      baseName: baseName,
      onClose: () => Navigator.of(modalContext).maybePop(),
    ),
  );
}
