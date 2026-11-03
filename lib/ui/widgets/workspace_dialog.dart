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

import '../../l10n/app_localizations.dart';
import '../../models/app_workspace.dart';
import '../../models/webdav_config.dart';
import '../../providers/workspace_providers.dart';
import '../../repositories/local_file_repository.dart';
import 'clearable_text_field.dart';

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
    final localizations = AppLocalizations.of(context);
    final fileName = _extractDisplayFileName(workspace.config);
    final storageIcon = workspace.config.storageMode.usesWebDav
        ? Icons.cloud_outlined
        : Icons.folder_outlined;

    return Tooltip(
      message: localizations.tooltipManageWorkspaces,
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

/// Tonal pill badge marking the currently active workspace inside [WorkspaceDialog].
class _ActiveWorkspaceBadge extends StatelessWidget {
  /// Creates an [_ActiveWorkspaceBadge].
  const _ActiveWorkspaceBadge({required this.label});

  /// Localized badge text.
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colorScheme.onPrimaryContainer,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
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
    final canSubmit = hasInput && !isBusy;

    return Row(
      children: [
        Icon(
          Icons.create_new_folder_outlined,
          size: 20,
          color: colorScheme.onSurfaceVariant,
        ),
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
            decoration: InputDecoration(
              filled: false,
              hintText: localizations.createWorkspaceHint,
              hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('workspace_create_submit_button'),
          tooltip: localizations.tooltipCreateWorkspace,
          icon: Icon(
            Icons.add_circle_rounded,
            color: canSubmit
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          const _WorkspaceLeadingBadge(icon: Icons.workspaces_outlined),
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
                  style: textTheme.titleMedium?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                _DrawerWorkspaceSubtitle(
                  fileName: fileName,
                  storageIcon: storageIcon,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.unfold_more_rounded,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

/// Monospace `.tdf` filename and storage mode icon row inside [_DrawerWorkspaceCardContent].
class _DrawerWorkspaceSubtitle extends StatelessWidget {
  /// Creates a [_DrawerWorkspaceSubtitle].
  const _DrawerWorkspaceSubtitle({
    required this.fileName,
    required this.storageIcon,
  });

  /// Display `.tdf` filename.
  final String fileName;

  /// Storage mode icon.
  final IconData storageIcon;

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(storageIcon, size: 13, color: mutedColor),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: mutedColor,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

/// Inline confirmation bar shown inside [_WorkspaceRowCard] before deleting a workspace.
class _WorkspaceDeleteConfirmBar extends StatelessWidget {
  /// Creates a [_WorkspaceDeleteConfirmBar].
  const _WorkspaceDeleteConfirmBar({
    required this.isBusy,
    required this.summary,
    required this.onCancel,
    required this.onConfirm,
  });

  /// Whether a workspace operation is currently in progress.
  final bool isBusy;

  /// Callback to cancel deletion.
  final VoidCallback onCancel;

  /// Callback to confirm deletion.
  final VoidCallback onConfirm;

  /// Workspace summary pending deletion.
  final WorkspaceSummary summary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);

    return Container(
      key: ValueKey('workspace_delete_confirm_bar_${summary.id}'),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              localizations.deleteWorkspaceConfirmMessage(summary.name),
              style: TextStyle(
                color: colorScheme.onErrorContainer,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            key: ValueKey('workspace_cancel_delete_button_${summary.id}'),
            onPressed: isBusy ? null : onCancel,
            child: Text(
              localizations.actionCancel,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
          const SizedBox(width: 4),
          FilledButton(
            key: ValueKey('workspace_confirm_delete_button_${summary.id}'),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: isBusy ? null : onConfirm,
            child: Text(localizations.actionDelete),
          ),
        ],
      ),
    );
  }
}

/// Header section of [WorkspaceDialog] displaying the leading badge, title, subtitle, and close button.
class _WorkspaceDialogHeader extends StatelessWidget {
  /// Creates a [_WorkspaceDialogHeader].
  const _WorkspaceDialogHeader({required this.onClose});

  /// Callback invoked when the close button is pressed.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _WorkspaceLeadingBadge(icon: Icons.workspaces_outlined),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                localizations.workspacesDialogTitle,
                style: textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                localizations.workspacesDialogDescription,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('workspace_dialog_close_button'),
          tooltip: localizations.actionClose,
          icon: const Icon(Icons.close_rounded),
          onPressed: onClose,
        ),
      ],
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
    final suggestedFile = AppWorkspace.suggestFileName(_createController.text);
    final error = _errorMessage;

    return Dialog(
      key: const ValueKey('workspace_dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WorkspaceDialogHeader(
                onClose: () => Navigator.of(context).pop(),
              ),
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
                _WorkspaceErrorBanner(
                  message: error,
                  onDismiss: _clearErrorBanner,
                ),
              ],
              const SizedBox(height: 12),
              Flexible(
                child: _buildWorkspaceList(summaries, activeWorkspace.id),
              ),
            ],
          ),
        ),
      ),
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
        return _WorkspaceRowCard(
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
  void _cancelDeleteConfirmation() {
    setState(() {
      _pendingDeleteWorkspaceId = null;
    });
  }

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
    if (_errorMessage == null) {
      return;
    }
    setState(() {
      _errorMessage = null;
    });
  }

  /// Deletes [workspaceId] and refreshes the dialog list.
  Future<void> _confirmDeleteWorkspace(String workspaceId) async {
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(activeWorkspaceProvider.notifier)
          .deleteWorkspace(workspaceId);
      if (!mounted) {
        return;
      }
      setState(() {
        _isBusy = false;
        _pendingDeleteWorkspaceId = null;
      });
    } on WorkspaceException catch (error) {
      _handleWorkspaceException(error);
    }
  }

  /// Creates a new workspace from [_createController], activates it, and closes the dialog.
  Future<void> _createAndActivateWorkspace() async {
    final rawName = _createController.text.trim();
    if (rawName.isEmpty || _isBusy) {
      return;
    }
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(activeWorkspaceProvider.notifier)
          .createWorkspace(rawName, activate: true);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } on WorkspaceException catch (error) {
      _handleWorkspaceException(error);
    }
  }

  /// Rebuilds live `.tdf` filename preview when [_createController] text changes.
  void _handleCreateTextChanged() {
    setState(() {
      _errorMessage = null;
    });
  }

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

  /// Saves the inline renamed workspace title for [workspaceId].
  Future<void> _saveRenameWorkspace(String workspaceId) async {
    final newName = _renameController.text.trim();
    if (_isBusy) {
      return;
    }
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(activeWorkspaceProvider.notifier)
          .renameWorkspace(workspaceId, newName);
      if (!mounted) {
        return;
      }
      setState(() {
        _isBusy = false;
        _renamingWorkspaceId = null;
        _renameController.clear();
      });
    } on WorkspaceException catch (error) {
      _handleWorkspaceException(error);
    }
  }

  /// Switches to [workspaceId] (unloading the previous workspace) and closes the dialog.
  Future<void> _selectWorkspace(String workspaceId) async {
    if (_isBusy) {
      return;
    }
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(activeWorkspaceProvider.notifier)
          .switchWorkspace(workspaceId);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } on WorkspaceException catch (error) {
      _handleWorkspaceException(error);
    }
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
    return Container(
      key: const ValueKey('workspace_error_banner'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: colorScheme.onErrorContainer,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: Icon(
              Icons.close_rounded,
              size: 16,
              color: colorScheme.onErrorContainer,
            ),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// Rounded `36x36` Material 3 `primaryContainer` icon square used in [DrawerWorkspaceCard] and [WorkspaceDialog].
class _WorkspaceLeadingBadge extends StatelessWidget {
  /// Creates a [_WorkspaceLeadingBadge].
  const _WorkspaceLeadingBadge({required this.icon});

  /// Icon rendered inside the tonal square.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 19, color: colorScheme.onPrimaryContainer),
    );
  }
}

/// Inline rename row displayed inside [_WorkspaceRowCard] when a workspace is being renamed.
class _WorkspaceRenameRow extends StatelessWidget {
  /// Creates a [_WorkspaceRenameRow].
  const _WorkspaceRenameRow({
    required this.controller,
    required this.isBusy,
    required this.workspaceId,
    required this.onCancel,
    required this.onSave,
  });

  /// Controller for the workspace rename input.
  final TextEditingController controller;

  /// Whether a save operation is currently running.
  final bool isBusy;

  /// Callback to cancel inline renaming.
  final VoidCallback onCancel;

  /// Callback to save the updated workspace name.
  final VoidCallback onSave;

  /// Identifier of the workspace being renamed.
  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(
        children: [
          const _WorkspaceLeadingBadge(icon: Icons.edit_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: ClearableTextField(
              fieldKey: ValueKey('workspace_rename_input_$workspaceId'),
              controller: controller,
              autofocus: true,
              cursorColor: colorScheme.primary,
              style: TextStyle(color: colorScheme.onSurface, fontSize: 15),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => isBusy ? null : onSave(),
              decoration: const InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          IconButton(
            key: ValueKey('workspace_rename_cancel_button_$workspaceId'),
            tooltip: localizations.actionCancel,
            icon: Icon(
              Icons.close_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
            onPressed: isBusy ? null : onCancel,
          ),
          IconButton(
            key: ValueKey('workspace_rename_save_button_$workspaceId'),
            tooltip: localizations.actionSave,
            icon: Icon(Icons.check_rounded, color: colorScheme.primary),
            onPressed: isBusy ? null : onSave,
          ),
        ],
      ),
    );
  }
}

/// Trailing rename and delete icon buttons on [_WorkspaceRowCard].
class _WorkspaceRowActions extends StatelessWidget {
  /// Creates [_WorkspaceRowActions].
  const _WorkspaceRowActions({
    required this.canDelete,
    required this.isBusy,
    required this.workspaceId,
    required this.onDelete,
    required this.onRename,
  });

  /// Whether deleting this workspace is allowed (`summaries.length > 1`).
  final bool canDelete;

  /// Whether a workspace operation is currently in progress.
  final bool isBusy;

  /// Callback to request deletion of this workspace.
  final VoidCallback onDelete;

  /// Callback to start inline renaming of this workspace.
  final VoidCallback onRename;

  /// Identifier of the workspace.
  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: ValueKey('workspace_rename_button_$workspaceId'),
          visualDensity: VisualDensity.compact,
          tooltip: localizations.tooltipRenameWorkspace,
          icon: Icon(Icons.edit_outlined, size: 19, color: mutedColor),
          onPressed: isBusy ? null : onRename,
        ),
        IconButton(
          key: ValueKey('workspace_delete_button_$workspaceId'),
          visualDensity: VisualDensity.compact,
          tooltip: localizations.tooltipDeleteWorkspace,
          icon: Icon(Icons.delete_outline_rounded, size: 19, color: mutedColor),
          onPressed: (canDelete && !isBusy) ? onDelete : null,
        ),
      ],
    );
  }
}

/// Single workspace card inside [WorkspaceDialog] supporting selection, inline renaming, and confirmed deletion.
class _WorkspaceRowCard extends StatelessWidget {
  /// Creates a [_WorkspaceRowCard].
  const _WorkspaceRowCard({
    super.key,
    required this.canDelete,
    required this.isActive,
    required this.isBusy,
    required this.isConfirmingDelete,
    required this.isRenaming,
    required this.renameController,
    required this.summary,
    required this.onCancelDelete,
    required this.onCancelRename,
    required this.onConfirmDelete,
    required this.onRequestDelete,
    required this.onSaveRename,
    required this.onSelect,
    required this.onStartRename,
  });

  /// Whether deletion is permitted (`summaries.length > 1`).
  final bool canDelete;

  /// Whether [summary] is the currently loaded workspace.
  final bool isActive;

  /// Whether an asynchronous workspace operation is running.
  final bool isBusy;

  /// Whether the inline delete confirmation bar is visible for this row.
  final bool isConfirmingDelete;

  /// Whether this row is in inline rename mode.
  final bool isRenaming;

  /// Callback to cancel inline delete confirmation.
  final VoidCallback onCancelDelete;

  /// Callback to cancel inline rename.
  final VoidCallback onCancelRename;

  /// Callback to confirm deleting this workspace.
  final VoidCallback onConfirmDelete;

  /// Callback to open the inline delete confirmation bar.
  final VoidCallback onRequestDelete;

  /// Callback to save the inline renamed title.
  final VoidCallback onSaveRename;

  /// Callback to switch to this workspace.
  final VoidCallback onSelect;

  /// Callback to enter inline rename mode.
  final VoidCallback onStartRename;

  /// Active text controller when [isRenaming] is `true`.
  final TextEditingController? renameController;

  /// Workspace metadata displayed by this card.
  final WorkspaceSummary summary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fillColor = isActive
        ? colorScheme.secondaryContainer
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);
    final borderColor = isActive
        ? colorScheme.primary
        : colorScheme.outlineVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: fillColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: borderColor, width: isActive ? 1.5 : 1.0),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopRow(),
            if (isConfirmingDelete)
              _WorkspaceDeleteConfirmBar(
                isBusy: isBusy,
                summary: summary,
                onCancel: onCancelDelete,
                onConfirm: onConfirmDelete,
              ),
          ],
        ),
      ),
    );
  }

  /// Builds either the inline rename input or the selectable workspace row.
  Widget _buildTopRow() {
    if (isRenaming) {
      if (renameController case final controller?) {
        return _WorkspaceRenameRow(
          controller: controller,
          isBusy: isBusy,
          workspaceId: summary.id,
          onCancel: onCancelRename,
          onSave: onSaveRename,
        );
      }
    }
    return _WorkspaceRowMainContent(
      canDelete: canDelete,
      isActive: isActive,
      isBusy: isBusy,
      summary: summary,
      onRequestDelete: onRequestDelete,
      onSelect: onSelect,
      onStartRename: onStartRename,
    );
  }
}

/// Selectable main content row inside [_WorkspaceRowCard] with workspace name, `.tdf` file subtitle, active badge, and action buttons.
class _WorkspaceRowMainContent extends StatelessWidget {
  /// Creates a [_WorkspaceRowMainContent].
  const _WorkspaceRowMainContent({
    required this.canDelete,
    required this.isActive,
    required this.isBusy,
    required this.summary,
    required this.onRequestDelete,
    required this.onSelect,
    required this.onStartRename,
  });

  /// Whether deleting this workspace is allowed.
  final bool canDelete;

  /// Whether [summary] is the active workspace.
  final bool isActive;

  /// Whether a workspace mutation is in progress.
  final bool isBusy;

  /// Callback to open delete confirmation.
  final VoidCallback onRequestDelete;

  /// Callback when the workspace row is tapped.
  final VoidCallback onSelect;

  /// Callback to start inline renaming.
  final VoidCallback onStartRename;

  /// Workspace summary displayed in this row.
  final WorkspaceSummary summary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);
    final fileName = LocalFileRepository.extractFileNameFromPath(
      summary.localFilePath,
    );

    return Row(
      children: [
        Expanded(
          child: InkWell(
            key: ValueKey('workspace_select_${summary.id}'),
            onTap: isBusy ? null : onSelect,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  _WorkspaceLeadingBadge(
                    icon: isActive
                        ? Icons.check_circle_rounded
                        : Icons.workspaces_outlined,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTitleColumn(colorScheme, fileName)),
                  if (isActive) ...[
                    const SizedBox(width: 8),
                    _ActiveWorkspaceBadge(
                      label: localizations.workspaceActiveBadge,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        _WorkspaceRowActions(
          canDelete: canDelete,
          isBusy: isBusy,
          workspaceId: summary.id,
          onDelete: onRequestDelete,
          onRename: onStartRename,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  /// Builds the workspace name and `.tdf` filename column.
  Widget _buildTitleColumn(ColorScheme colorScheme, String fileName) {
    final titleColor = isActive
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          summary.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: titleColor,
            fontSize: 15,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      ],
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
