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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_workspace.dart';
import '../../models/webdav_config.dart';
import '../../providers/workspace_providers.dart';
import '../../repositories/local_file_repository.dart';
import 'clearable_text_field.dart';
import 'workspace_row_card.dart';

/// Tonal interactive workspace switcher card displayed beneath the `TierTask` header in the navigation drawer.
class DrawerWorkspaceCard extends StatelessWidget {
  /// Creates a [DrawerWorkspaceCard].
  const DrawerWorkspaceCard({
    super.key,
    required this.workspace,
    required this.onTap,
  });

  /// Callback invoked when the workspace card is tapped.
  final VoidCallback onTap;

  /// Currently active [AppWorkspace] displayed on the card.
  final AppWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fileName = _extractDisplayFileName(workspace.config);
    final storageIcon = workspace.config.storageMode.usesWebDav
        ? Icons.cloud_outlined
        : Icons.folder_outlined;

    return Tooltip(
      message: AppLocalizations.of(context).tooltipManageWorkspaces,
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('drawer_workspace_switcher'),
          onTap: onTap,
          child: _DrawerWorkspaceCardContent(
            fileName: fileName,
            storageIcon: storageIcon,
            workspaceName: workspace.name,
          ),
        ),
      ),
    );
  }
}

/// Modal dialog for switching, creating, renaming, and deleting workspaces.
class WorkspaceDialog extends ConsumerStatefulWidget {
  /// Creates a [WorkspaceDialog].
  const WorkspaceDialog({super.key});

  @override
  ConsumerState<WorkspaceDialog> createState() => _WorkspaceDialogState();
}

/// Elevated input card at the top of [WorkspaceDialog] for creating a new workspace with a live `.tdf` filename preview.
class _CreateWorkspaceCard extends StatelessWidget {
  /// Creates a [_CreateWorkspaceCard].
  const _CreateWorkspaceCard({
    required this.controller,
    required this.hasInput,
    required this.isBusy,
    required this.suggestedFileName,
    required this.onClear,
    required this.onSubmit,
  });

  /// Text controller for the new workspace name.
  final TextEditingController controller;

  /// Whether the input field contains non-whitespace characters.
  final bool hasInput;

  /// Whether a workspace operation is currently in progress.
  final bool isBusy;

  /// Callback invoked when the input is cleared.
  final VoidCallback onClear;

  /// Callback invoked when the user submits the new workspace name.
  final VoidCallback onSubmit;

  /// Live suggested `.tdf` filename preview derived from the input text.
  final String suggestedFileName;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _CreateWorkspaceInputRow(
            controller: controller,
            hasInput: hasInput,
            isBusy: isBusy,
            onClear: onClear,
            onSubmit: onSubmit,
          ),
          if (hasInput) ...[
            const SizedBox(height: 6),
            Text(
              localizations.workspaceSuggestedFileLabel(suggestedFileName),
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Single-row text input and submit button inside [_CreateWorkspaceCard].
class _CreateWorkspaceInputRow extends StatelessWidget {
  /// Creates a [_CreateWorkspaceInputRow].
  const _CreateWorkspaceInputRow({
    required this.controller,
    required this.hasInput,
    required this.isBusy,
    required this.onClear,
    required this.onSubmit,
  });

  /// Base borderless decoration for the workspace name text field.
  static const InputDecoration _baseDecoration = InputDecoration(
    filled: false,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    isDense: true,
  );

  /// Controller for the new workspace name.
  final TextEditingController controller;

  /// Whether the input contains non-whitespace text.
  final bool hasInput;

  /// Whether a mutation is currently in flight.
  final bool isBusy;

  /// Callback when the input is cleared.
  final VoidCallback onClear;

  /// Callback when the add button or keyboard submit is triggered.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);
    final mutedColor = colorScheme.onSurfaceVariant;
    final canSubmit = hasInput && !isBusy;
    final submitColor = canSubmit ? colorScheme.primary : mutedColor;
    return Row(
      children: [
        Icon(Icons.create_new_folder_outlined, size: 20, color: mutedColor),
        const SizedBox(width: 10),
        Expanded(
          child: ClearableTextField(
            fieldKey: const ValueKey('workspace_create_input'),
            controller: controller,
            cursorColor: colorScheme.primary,
            style: TextStyle(color: colorScheme.onSurface, fontSize: 15),
            textInputAction: TextInputAction.done,
            onCleared: onClear,
            onSubmitted: (_) => canSubmit ? onSubmit() : null,
            decoration: _baseDecoration.copyWith(
              hintText: localizations.createWorkspaceHint,
              hintStyle: TextStyle(color: mutedColor),
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('workspace_create_submit_button'),
          tooltip: localizations.tooltipCreateWorkspace,
          icon: Icon(Icons.add_circle_rounded, color: submitColor),
          onPressed: canSubmit ? onSubmit : null,
        ),
      ],
    );
  }
}

/// Inner row layout of [DrawerWorkspaceCard] displaying the leading badge, name, `.tdf` filename, and chevron icon.
class _DrawerWorkspaceCardContent extends StatelessWidget {
  /// Creates a [_DrawerWorkspaceCardContent].
  const _DrawerWorkspaceCardContent({
    required this.fileName,
    required this.storageIcon,
    required this.workspaceName,
  });

  /// Display `.tdf` filename of the active workspace.
  final String fileName;

  /// Icon representing the active storage mode.
  final IconData storageIcon;

  /// Display name of the active workspace.
  final String workspaceName;

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final titleStyle = Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontSize: 15, fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          const WorkspaceLeadingBadge(icon: Icons.workspaces_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  workspaceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
                const SizedBox(height: 2),
                WorkspaceFileSubtitle(
                  fileName: fileName,
                  storageIcon: storageIcon,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.unfold_more_rounded, size: 20, color: mutedColor),
        ],
      ),
    );
  }
}

/// State for [WorkspaceDialog].
class _WorkspaceDialogState extends ConsumerState<WorkspaceDialog> {
  final TextEditingController _createController = TextEditingController();
  String? _errorMessage;
  bool _isBusy = false;
  String? _pendingDeleteWorkspaceId;
  final TextEditingController _renameController = TextEditingController();
  String? _renamingWorkspaceId;

  /// Whether [_createController] currently contains non-whitespace characters.
  bool get _hasCreateInput => _createController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _createController.addListener(_handleCreateTextChanged);
  }

  @override
  void dispose() {
    _createController.removeListener(_handleCreateTextChanged);
    _createController.dispose();
    _renameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeWorkspace =
        ref.watch(activeWorkspaceProvider).asData?.value ??
        AppWorkspace.defaultWorkspace;
    final summaries =
        ref.watch(workspaceSummariesProvider).asData?.value ??
        <WorkspaceSummary>[activeWorkspace.summary];

    return Dialog(
      key: const ValueKey('workspace_dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: _buildDialogColumn(context, summaries, activeWorkspace.id),
        ),
      ),
    );
  }

  /// Builds the main column of header, create-workspace card, optional error banner, and workspace list.
  Widget _buildDialogColumn(
    BuildContext context,
    List<WorkspaceSummary> summaries,
    String activeWorkspaceId,
  ) {
    final suggestedFile = AppWorkspace.suggestFileName(_createController.text);
    final error = _errorMessage;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDialogHeader(context),
        const SizedBox(height: 14),
        _CreateWorkspaceCard(
          controller: _createController,
          hasInput: _hasCreateInput,
          isBusy: _isBusy,
          suggestedFileName: suggestedFile,
          onClear: _clearCreateInput,
          onSubmit: _createAndActivateWorkspace,
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          _WorkspaceErrorBanner(message: error, onDismiss: _clearErrorBanner),
        ],
        const SizedBox(height: 12),
        Flexible(child: _buildWorkspaceList(summaries, activeWorkspaceId)),
      ],
    );
  }

  /// Builds the header row displaying the leading badge, title, description, and close button.
  Widget _buildDialogHeader(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final subtitleColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WorkspaceLeadingBadge(icon: Icons.workspaces_outlined),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                localizations.workspacesDialogTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                localizations.workspacesDialogDescription,
                style: TextStyle(color: subtitleColor, fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('workspace_dialog_close_button'),
          tooltip: localizations.actionClose,
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  /// Builds the scrollable list of [summaries] highlighting [activeWorkspaceId].
  Widget _buildWorkspaceList(
    List<WorkspaceSummary> summaries,
    String activeWorkspaceId,
  ) {
    final canDelete = summaries.length > 1;
    return ListView.builder(
      shrinkWrap: true,
      itemCount: summaries.length,
      itemBuilder: (context, index) {
        final summary = summaries[index];
        final isRenaming = _renamingWorkspaceId == summary.id;
        return WorkspaceRowCard(
          key: ValueKey('workspace_tile_${summary.id}'),
          canDelete: canDelete,
          isActive: summary.id == activeWorkspaceId,
          isBusy: _isBusy,
          isConfirmingDelete: _pendingDeleteWorkspaceId == summary.id,
          isRenaming: isRenaming,
          renameController: isRenaming ? _renameController : null,
          summary: summary,
          onCancelDelete: _cancelDeleteConfirmation,
          onCancelRename: _cancelRename,
          onConfirmDelete: () => _confirmDeleteWorkspace(summary.id),
          onRequestDelete: () => _requestDeleteConfirmation(summary.id),
          onSaveRename: () => _saveRenameWorkspace(summary.id),
          onSelect: () => _selectWorkspace(summary.id),
          onStartRename: () => _startRename(summary),
        );
      },
    );
  }

  /// Cancels any active inline delete confirmation bar.
  void _cancelDeleteConfirmation() =>
      setState(() => _pendingDeleteWorkspaceId = null);

  /// Exits inline rename mode without saving changes.
  void _cancelRename() {
    setState(() {
      _renamingWorkspaceId = null;
      _renameController.clear();
    });
  }

  /// Clears the create-workspace input field and hides any validation error.
  void _clearCreateInput() {
    _createController.clear();
    _clearErrorBanner();
  }

  /// Dismisses the dialog error banner.
  void _clearErrorBanner() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  /// Deletes [workspaceId] and refreshes the dialog list.
  Future<void> _confirmDeleteWorkspace(String workspaceId) =>
      _runWorkspaceMutation(
        (notifier) => notifier.deleteWorkspace(workspaceId),
        onSuccess: () => setState(() {
          _isBusy = false;
          _pendingDeleteWorkspaceId = null;
        }),
      );

  /// Creates a new workspace from [_createController], activates it, and closes the dialog.
  Future<void> _createAndActivateWorkspace() async {
    final rawName = _createController.text.trim();
    if (rawName.isEmpty || _isBusy) {
      return;
    }
    await _runWorkspaceMutation(
      (notifier) => notifier.createWorkspace(rawName, activate: true),
      onSuccess: () => Navigator.of(context).pop(),
    );
  }

  /// Rebuilds live `.tdf` filename preview when [_createController] text changes.
  void _handleCreateTextChanged() => setState(() => _errorMessage = null);

  /// Maps [error] to a localized message and displays the error banner.
  void _handleWorkspaceException(WorkspaceException error) {
    if (!mounted) {
      return;
    }
    final localizations = AppLocalizations.of(context);
    setState(() {
      _isBusy = false;
      _errorMessage = _localizeWorkspaceError(error, localizations);
    });
  }

  /// Opens the inline delete confirmation bar for [workspaceId].
  void _requestDeleteConfirmation(String workspaceId) {
    setState(() {
      _renamingWorkspaceId = null;
      _pendingDeleteWorkspaceId = workspaceId;
      _errorMessage = null;
    });
  }

  /// Executes [mutation] while managing [_isBusy] and [WorkspaceException] error handling.
  Future<void> _runWorkspaceMutation(
    Future<void> Function(ActiveWorkspaceNotifier notifier) mutation, {
    required VoidCallback onSuccess,
  }) async {
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      await mutation(ref.read(activeWorkspaceProvider.notifier));
      if (!mounted) {
        return;
      }
      onSuccess();
    } on WorkspaceException catch (error) {
      _handleWorkspaceException(error);
    }
  }

  /// Saves the inline renamed workspace title for [workspaceId].
  Future<void> _saveRenameWorkspace(String workspaceId) async {
    if (_isBusy) {
      return;
    }
    final newName = _renameController.text.trim();
    await _runWorkspaceMutation(
      (notifier) => notifier.renameWorkspace(workspaceId, newName),
      onSuccess: () => setState(() {
        _isBusy = false;
        _renamingWorkspaceId = null;
        _renameController.clear();
      }),
    );
  }

  /// Switches to [workspaceId] (unloading the previous workspace) and closes the dialog.
  Future<void> _selectWorkspace(String workspaceId) async {
    if (_isBusy) {
      return;
    }
    await _runWorkspaceMutation(
      (notifier) => notifier.switchWorkspace(workspaceId),
      onSuccess: () => Navigator.of(context).pop(),
    );
  }

  /// Enters inline rename mode for [summary].
  void _startRename(WorkspaceSummary summary) {
    setState(() {
      _pendingDeleteWorkspaceId = null;
      _errorMessage = null;
      _renamingWorkspaceId = summary.id;
      _renameController.value = TextEditingValue(
        text: summary.name,
        selection: TextSelection.collapsed(offset: summary.name.length),
      );
    });
  }
}

/// Dismissible validation error banner displayed inside [WorkspaceDialog].
class _WorkspaceErrorBanner extends StatelessWidget {
  /// Creates a [_WorkspaceErrorBanner].
  const _WorkspaceErrorBanner({required this.message, required this.onDismiss});

  /// Localized error message text.
  final String message;

  /// Callback invoked when the dismiss button is pressed.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = colorScheme.onErrorContainer;
    return Container(
      key: const ValueKey('workspace_error_banner'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: foregroundColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: foregroundColor, fontSize: 13),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: Icon(Icons.close_rounded, size: 16, color: foregroundColor),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// Opens the modal [WorkspaceDialog] for switching and managing workspaces.
Future<void> showWorkspaceDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const WorkspaceDialog(),
  );
}

/// Extracts the short `.tdf` filename displayed for [config].
String _extractDisplayFileName(WebDavConfig config) {
  final rawPath = config.storageMode == StorageMode.webdav
      ? config.filePath
      : config.localFilePath;
  return LocalFileRepository.extractFileNameFromPath(rawPath);
}

/// Maps a [WorkspaceException] to a localized error string from [localizations].
String _localizeWorkspaceError(
  WorkspaceException error,
  AppLocalizations localizations,
) => switch (error.kind) {
  WorkspaceErrorKind.emptyName => localizations.errorWorkspaceNameEmpty,
  WorkspaceErrorKind.duplicateName => localizations.errorWorkspaceNameDuplicate,
  WorkspaceErrorKind.duplicateFilePath =>
    localizations.errorDuplicateWorkspaceFilePath,
  WorkspaceErrorKind.invalidFilePath => localizations.errorInvalidLocalFilePath,
  WorkspaceErrorKind.workspaceNotFound => error.message,
  WorkspaceErrorKind.cannotDeleteLastWorkspace =>
    localizations.errorWorkspaceCannotDeleteLast,
  WorkspaceErrorKind.maxWorkspacesExceeded =>
    localizations.errorWorkspaceMaxExceeded,
  WorkspaceErrorKind.corruptBinaryPayload => error.message,
};
