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
import '../../models/app_workspace.dart';
import '../../repositories/local_file_repository.dart';
import 'clearable_text_field.dart';

/// Monospace `.tdf` filename subtitle with an optional leading storage mode icon.
class WorkspaceFileSubtitle extends StatelessWidget {
  /// Creates a [WorkspaceFileSubtitle].
  const WorkspaceFileSubtitle({
    super.key,
    required this.fileName,
    this.storageIcon,
  });

  /// Display `.tdf` filename.
  final String fileName;

  /// Optional storage mode icon rendered before [fileName].
  final IconData? storageIcon;

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final textStyle = TextStyle(
      color: mutedColor,
      fontFamily: 'monospace',
      fontSize: 12,
    );
    final icon = storageIcon;
    if (icon == null) {
      return Text(
        fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textStyle,
      );
    }
    return Row(
      children: [
        Icon(icon, size: 13, color: mutedColor),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
      ],
    );
  }
}

/// Rounded `36x36` Material 3 `primaryContainer` icon square used across workspace cards and headers.
class WorkspaceLeadingBadge extends StatelessWidget {
  /// Creates a [WorkspaceLeadingBadge].
  const WorkspaceLeadingBadge({super.key, required this.icon});

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

/// Single workspace card supporting selection, inline renaming, and confirmed deletion.
class WorkspaceRowCard extends StatelessWidget {
  /// Creates a [WorkspaceRowCard].
  const WorkspaceRowCard({
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

/// Tonal pill badge marking the currently active workspace inside [WorkspaceRowCard].
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

/// Inline confirmation bar shown inside [WorkspaceRowCard] before deleting a workspace.
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
          _WorkspaceDeleteConfirmButtons(
            isBusy: isBusy,
            workspaceId: summary.id,
            onCancel: onCancel,
            onConfirm: onConfirm,
          ),
        ],
      ),
    );
  }
}

/// Cancel and confirm action buttons inside [_WorkspaceDeleteConfirmBar].
class _WorkspaceDeleteConfirmButtons extends StatelessWidget {
  /// Creates [_WorkspaceDeleteConfirmButtons].
  const _WorkspaceDeleteConfirmButtons({
    required this.isBusy,
    required this.workspaceId,
    required this.onCancel,
    required this.onConfirm,
  });

  /// Whether a workspace operation is currently in progress.
  final bool isBusy;

  /// Callback to cancel deletion.
  final VoidCallback onCancel;

  /// Callback to confirm deletion.
  final VoidCallback onConfirm;

  /// Identifier of the workspace pending deletion.
  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          key: ValueKey('workspace_cancel_delete_button_$workspaceId'),
          onPressed: isBusy ? null : onCancel,
          child: Text(
            localizations.actionCancel,
            style: TextStyle(color: colorScheme.onErrorContainer),
          ),
        ),
        const SizedBox(width: 4),
        FilledButton(
          key: ValueKey('workspace_confirm_delete_button_$workspaceId'),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: isBusy ? null : onConfirm,
          child: Text(localizations.actionDelete),
        ),
      ],
    );
  }
}

/// Inline rename row displayed inside [WorkspaceRowCard] when a workspace is being renamed.
class _WorkspaceRenameRow extends StatelessWidget {
  /// Creates a [_WorkspaceRenameRow].
  const _WorkspaceRenameRow({
    required this.controller,
    required this.isBusy,
    required this.workspaceId,
    required this.onCancel,
    required this.onSave,
  });

  /// Borderless input decoration for the inline rename field.
  static const InputDecoration _inputDecoration = InputDecoration(
    filled: false,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    isDense: true,
  );

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
    final mutedColor = colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(
        children: [
          const WorkspaceLeadingBadge(icon: Icons.edit_outlined),
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
              decoration: _inputDecoration,
            ),
          ),
          IconButton(
            key: ValueKey('workspace_rename_cancel_button_$workspaceId'),
            tooltip: localizations.actionCancel,
            icon: Icon(Icons.close_rounded, color: mutedColor),
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

/// Trailing rename and delete icon buttons on [WorkspaceRowCard].
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

/// Selectable main content row inside [WorkspaceRowCard] with workspace name, `.tdf` file subtitle, active badge, and action buttons.
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
    final localizations = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(child: _buildSelectArea(localizations)),
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

  /// Builds the tappable workspace selection area displaying the badge, title, and active pill.
  Widget _buildSelectArea(AppLocalizations localizations) {
    final fileName = LocalFileRepository.extractFileNameFromPath(
      summary.localFilePath,
    );
    return InkWell(
      key: ValueKey('workspace_select_${summary.id}'),
      onTap: isBusy ? null : onSelect,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            WorkspaceLeadingBadge(
              icon: isActive
                  ? Icons.check_circle_rounded
                  : Icons.workspaces_outlined,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _WorkspaceRowTitleColumn(
                fileName: fileName,
                isActive: isActive,
                workspaceName: summary.name,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 8),
              _ActiveWorkspaceBadge(label: localizations.workspaceActiveBadge),
            ],
          ],
        ),
      ),
    );
  }
}

/// Column displaying the workspace title and monospace `.tdf` filename inside [_WorkspaceRowMainContent].
class _WorkspaceRowTitleColumn extends StatelessWidget {
  /// Creates a [_WorkspaceRowTitleColumn].
  const _WorkspaceRowTitleColumn({
    required this.fileName,
    required this.isActive,
    required this.workspaceName,
  });

  /// Short `.tdf` filename of the workspace.
  final String fileName;

  /// Whether this row represents the active workspace.
  final bool isActive;

  /// Display name of the workspace.
  final String workspaceName;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final titleColor = isActive
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          workspaceName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: titleColor,
            fontSize: 15,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        WorkspaceFileSubtitle(fileName: fileName),
      ],
    );
  }
}
