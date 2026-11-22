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
import '../../providers/entity_actions_provider.dart';
import '../../providers/shell_providers.dart';
import '../../providers/ui_telemetry.dart';
import '../../providers/workspace_providers.dart';
import '../components/ui_dialog_frame.dart';
import '../primitives/ui_banner.dart';
import '../primitives/ui_button.dart';
import '../primitives/ui_card.dart';
import '../primitives/ui_field.dart';
import '../primitives/ui_pill.dart';
import '../tokens/ui_theme_tokens.dart';
import '../tokens/ui_typography_tokens.dart';
import '../widgets/entity_card_chrome.dart';

/// Isolated create-workspace button and live suggested `.tdf` filename preview rebuilt per keystroke.
class _WorkspaceCreateContent extends StatelessWidget {
  /// Creates a [_WorkspaceCreateContent].
  const _WorkspaceCreateContent({
    required this.fieldChild,
    required this.rawName,
    required this.canCreateMore,
    required this.isBusy,
    required this.onSubmit,
  });

  /// Whether another workspace may still be created within [AppWorkspace.maxWorkspaces].
  final bool canCreateMore;

  /// Pre-built text input widget preserved across keystrokes.
  final Widget fieldChild;

  /// Whether a workspace mutation is currently executing.
  final bool isBusy;

  /// Callback submitting new workspace creation.
  final VoidCallback onSubmit;

  /// Current raw text inside the create-workspace field.
  final String rawName;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final hasInput = rawName.trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: fieldChild),
            const SizedBox(width: 8.0),
            UiButton(
              key: const ValueKey<String>('workspace_create_button'),
              label: localizations.actionAdd,
              leadingIcon: Icons.add_rounded,
              variant: UiButtonVariant.primary,
              density: UiButtonDensity.standard,
              tooltip: localizations.tooltipCreateWorkspace,
              isLoading: isBusy,
              onPressed: (canCreateMore && !isBusy && hasInput)
                  ? onSubmit
                  : null,
            ),
          ],
        ),
        if (canCreateMore && hasInput) ...<Widget>[
          const SizedBox(height: 6.0),
          _WorkspaceSuggestedFileCaption(rawName: rawName),
        ],
      ],
    );
  }
}

/// Bottom create-workspace form isolating live `.tdf` filename preview rebuilds via [ValueListenableBuilder].
class _WorkspaceCreateSection extends StatelessWidget {
  /// Creates a [_WorkspaceCreateSection].
  const _WorkspaceCreateSection({
    required this.controller,
    required this.canCreateMore,
    required this.isBusy,
    required this.onChanged,
    required this.onSubmit,
  });

  /// Whether another workspace can still be created within [AppWorkspace.maxWorkspaces].
  final bool canCreateMore;

  /// Controller for the new workspace name input.
  final TextEditingController controller;

  /// Whether a workspace mutation is currently executing.
  final bool isBusy;

  /// Callback invoked when input text changes.
  final ValueChanged<String> onChanged;

  /// Callback invoked when submitting creation via button or `Enter`.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final field = UiField(
      key: const ValueKey<String>('workspace_create_field'),
      controller: controller,
      hintText: localizations.createWorkspaceHint,
      maxLength: AppWorkspace.maxNameLength,
      enabled: canCreateMore && !isBusy,
      showClearButton: true,
      clearTooltip: localizations.tooltipClearInput,
      helperText: canCreateMore
          ? null
          : localizations.errorWorkspaceMaxExceeded,
      textInputAction: TextInputAction.done,
      onChanged: onChanged,
      onSubmitted: _handleSubmitted,
    );

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      child: field,
      builder: (context, value, fieldChild) {
        return _WorkspaceCreateContent(
          fieldChild: fieldChild ?? field,
          rawName: value.text,
          canCreateMore: canCreateMore,
          isBusy: isBusy,
          onSubmit: onSubmit,
        );
      },
    );
  }

  /// Submits creation on `Enter` when workspace capacity allows and no mutation is active.
  void _handleSubmitted(String _) {
    if (canCreateMore && !isBusy) {
      onSubmit();
    }
  }
}

/// Inline confirmation banner rendered below a workspace card while confirming deletion.
class _WorkspaceDeleteConfirmBar extends StatelessWidget {
  /// Creates a [_WorkspaceDeleteConfirmBar].
  const _WorkspaceDeleteConfirmBar({
    required this.summary,
    required this.isBusy,
    required this.onCancel,
    required this.onConfirm,
  });

  /// Whether a workspace mutation is executing.
  final bool isBusy;

  /// Callback cancelling delete confirmation.
  final VoidCallback onCancel;

  /// Callback confirming deletion.
  final VoidCallback onConfirm;

  /// Workspace summary being confirmed for deletion.
  final WorkspaceSummary summary;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: UiBanner(
        key: ValueKey<String>('workspace_delete_confirm_${summary.id}'),
        variant: UiBannerVariant.inlineConfirm,
        message: localizations.deleteWorkspaceConfirmMessage(summary.name),
        cancelLabel: localizations.actionCancel,
        onCancel: isBusy ? null : onCancel,
        confirmLabel: localizations.actionDelete,
        onConfirm: isBusy ? null : onConfirm,
      ),
    );
  }
}

/// Optional inline error banner rendered above the workspace creation form.
class _WorkspaceErrorSlot extends StatelessWidget {
  /// Creates a [_WorkspaceErrorSlot].
  const _WorkspaceErrorSlot({
    required this.errorMessage,
    required this.onDismiss,
  });

  /// Optional localized error message.
  final String? errorMessage;

  /// Callback dismissing the banner.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final message = errorMessage;
    if (message == null) {
      return const SizedBox.shrink();
    }
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10.0),
      child: UiBanner(
        key: const ValueKey<String>('workspace_error_banner'),
        variant: UiBannerVariant.status,
        tone: UiBannerTone.danger,
        message: message,
        dismissTooltip: localizations.actionDismiss,
        onDismiss: onDismiss,
      ),
    );
  }
}

/// Inline rename input row replacing the standard workspace row header while editing.
class _WorkspaceInlineRenameRow extends StatelessWidget {
  /// Creates a [_WorkspaceInlineRenameRow].
  const _WorkspaceInlineRenameRow({
    required this.workspaceId,
    required this.controller,
    required this.isBusy,
    required this.onChanged,
    required this.onCancel,
    required this.onSave,
  });

  /// Controller pre-filled with the workspace display name.
  final TextEditingController controller;

  /// Whether a workspace mutation is currently executing.
  final bool isBusy;

  /// Callback cancelling inline rename.
  final VoidCallback onCancel;

  /// Callback notified when rename text changes.
  final ValueChanged<String> onChanged;

  /// Callback committing inline rename.
  final VoidCallback onSave;

  /// Identifier of the workspace being renamed.
  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: UiField(
            key: ValueKey<String>('workspace_rename_field_$workspaceId'),
            controller: controller,
            autofocus: true,
            maxLength: AppWorkspace.maxNameLength,
            enabled: !isBusy,
            showClearButton: true,
            clearTooltip: localizations.tooltipClearInput,
            textInputAction: TextInputAction.done,
            onChanged: onChanged,
            onSubmitted: (_) => onSave(),
          ),
        ),
        const SizedBox(width: 8.0),
        EntityModalActionFooter(
          cancelKey: ValueKey<String>('workspace_rename_cancel_$workspaceId'),
          confirmKey: ValueKey<String>('workspace_rename_save_$workspaceId'),
          confirmLabel: localizations.actionSave,
          confirmVariant: UiButtonVariant.primary,
          isBusy: isBusy,
          onCancel: onCancel,
          onConfirm: onSave,
        ),
      ],
    );
  }
}

/// Lazy vertical list of workspace cards rendered inside [_WorkspaceModalBody].
class _WorkspaceListSection extends StatelessWidget {
  /// Creates a [_WorkspaceListSection].
  const _WorkspaceListSection({
    required this.summaries,
    required this.activeWorkspaceId,
    required this.isBusy,
    required this.renamingWorkspaceId,
    required this.pendingDeleteWorkspaceId,
    required this.renameController,
    required this.onSelectWorkspace,
    required this.onStartRename,
    required this.onCancelRename,
    required this.onSaveRename,
    required this.onRenameChanged,
    required this.onRequestDelete,
    required this.onCancelDelete,
    required this.onConfirmDelete,
  });

  /// Identifier of the currently loaded active workspace.
  final String activeWorkspaceId;

  /// Whether a workspace mutation is currently executing.
  final bool isBusy;

  /// Callback dismissing an active inline delete confirmation.
  final VoidCallback onCancelDelete;

  /// Callback cancelling inline rename mode.
  final VoidCallback onCancelRename;

  /// Callback confirming deletion of a workspace identifier.
  final ValueChanged<String> onConfirmDelete;

  /// Callback notified when inline rename input changes.
  final ValueChanged<String> onRenameChanged;

  /// Callback opening inline delete confirmation for a workspace identifier.
  final ValueChanged<String> onRequestDelete;

  /// Callback committing inline rename for a workspace identifier.
  final ValueChanged<String> onSaveRename;

  /// Callback switching active workspace to an inactive workspace identifier.
  final ValueChanged<String> onSelectWorkspace;

  /// Callback entering inline rename mode for a workspace summary.
  final ValueChanged<WorkspaceSummary> onStartRename;

  /// Identifier of the workspace currently showing inline delete confirmation, if any.
  final String? pendingDeleteWorkspaceId;

  /// Controller for the active inline rename input.
  final TextEditingController renameController;

  /// Identifier of the workspace currently being renamed inline, if any.
  final String? renamingWorkspaceId;

  /// Ordered persisted workspace summaries.
  final List<WorkspaceSummary> summaries;

  @override
  Widget build(BuildContext context) {
    final canDelete = summaries.length > 1;
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: summaries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8.0),
      itemBuilder: (context, index) {
        final summary = summaries[index];
        return _WorkspaceModalRowCard(
          key: ValueKey<String>('workspace_card_${summary.id}'),
          summary: summary,
          isActive: summary.id == activeWorkspaceId,
          canDelete: canDelete,
          isBusy: isBusy,
          isRenaming: renamingWorkspaceId == summary.id,
          isConfirmingDelete: pendingDeleteWorkspaceId == summary.id,
          renameController: renameController,
          onSelect: () => onSelectWorkspace(summary.id),
          onStartRename: () => onStartRename(summary),
          onCancelRename: onCancelRename,
          onSaveRename: () => onSaveRename(summary.id),
          onRenameChanged: onRenameChanged,
          onRequestDelete: () => onRequestDelete(summary.id),
          onCancelDelete: onCancelDelete,
          onConfirmDelete: () => onConfirmDelete(summary.id),
        );
      },
    );
  }
}

/// Loading state banner displayed while workspace metadata initializes.
class _WorkspaceLoadingBanner extends StatelessWidget {
  /// Creates a [_WorkspaceLoadingBanner].
  const _WorkspaceLoadingBanner();

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return UiBanner(
      variant: UiBannerVariant.loadingState,
      message: localizations.loadingBoardSubtitle,
    );
  }
}

/// Scrollable body content of [_WorkspacesModal] composing workspace cards, error readout, and bottom create form.
class _WorkspaceModalBody extends StatelessWidget {
  /// Creates a [_WorkspaceModalBody].
  const _WorkspaceModalBody({
    required this.snapshot,
    required this.isBusy,
    required this.renamingWorkspaceId,
    required this.pendingDeleteWorkspaceId,
    required this.errorMessage,
    required this.createController,
    required this.renameController,
    required this.onSelectWorkspace,
    required this.onStartRename,
    required this.onCancelRename,
    required this.onSaveRename,
    required this.onRenameChanged,
    required this.onRequestDelete,
    required this.onCancelDelete,
    required this.onConfirmDelete,
    required this.onCreateChanged,
    required this.onCreateSubmit,
    required this.onDismissError,
  });

  /// Controller for the bottom create-workspace input.
  final TextEditingController createController;

  /// Optional inline validation or persistence error message.
  final String? errorMessage;

  /// Whether a workspace mutation is currently executing.
  final bool isBusy;

  /// Callback dismissing an active inline delete confirmation.
  final VoidCallback onCancelDelete;

  /// Callback cancelling inline rename mode.
  final VoidCallback onCancelRename;

  /// Callback confirming deletion of a workspace identifier.
  final ValueChanged<String> onConfirmDelete;

  /// Callback notified when create input changes.
  final ValueChanged<String> onCreateChanged;

  /// Callback submitting new workspace creation.
  final VoidCallback onCreateSubmit;

  /// Callback dismissing [errorMessage].
  final VoidCallback onDismissError;

  /// Callback notified when inline rename input changes.
  final ValueChanged<String> onRenameChanged;

  /// Callback opening inline delete confirmation for a workspace identifier.
  final ValueChanged<String> onRequestDelete;

  /// Callback committing inline rename for a workspace identifier.
  final ValueChanged<String> onSaveRename;

  /// Callback switching active workspace to an inactive workspace identifier.
  final ValueChanged<String> onSelectWorkspace;

  /// Callback entering inline rename mode for a workspace summary.
  final ValueChanged<WorkspaceSummary> onStartRename;

  /// Identifier of the workspace currently showing inline delete confirmation, if any.
  final String? pendingDeleteWorkspaceId;

  /// Controller for the active inline rename input.
  final TextEditingController renameController;

  /// Identifier of the workspace currently being renamed inline, if any.
  final String? renamingWorkspaceId;

  /// Resolved live workspace listing snapshot from domain providers.
  final _WorkspaceListSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (snapshot.isLoading) {
      return const _WorkspaceLoadingBanner();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _WorkspaceListSection(
          summaries: snapshot.summaries,
          activeWorkspaceId: snapshot.activeWorkspaceId,
          isBusy: isBusy,
          renamingWorkspaceId: renamingWorkspaceId,
          pendingDeleteWorkspaceId: pendingDeleteWorkspaceId,
          renameController: renameController,
          onSelectWorkspace: onSelectWorkspace,
          onStartRename: onStartRename,
          onCancelRename: onCancelRename,
          onSaveRename: onSaveRename,
          onRenameChanged: onRenameChanged,
          onRequestDelete: onRequestDelete,
          onCancelDelete: onCancelDelete,
          onConfirmDelete: onConfirmDelete,
        ),
        _WorkspaceModalFooter(
          errorMessage: errorMessage,
          onDismissError: onDismissError,
          createController: createController,
          canCreateMore: snapshot.canCreateMore,
          isBusy: isBusy,
          onCreateChanged: onCreateChanged,
          onCreateSubmit: onCreateSubmit,
        ),
      ],
    );
  }
}

/// Error banner slot, divider, and create-workspace section below the workspace list.
class _WorkspaceModalFooter extends StatelessWidget {
  /// Creates a [_WorkspaceModalFooter].
  const _WorkspaceModalFooter({
    required this.errorMessage,
    required this.onDismissError,
    required this.createController,
    required this.canCreateMore,
    required this.isBusy,
    required this.onCreateChanged,
    required this.onCreateSubmit,
  });

  /// Whether the workspace count is below [AppWorkspace.maxWorkspaces].
  final bool canCreateMore;

  /// Controller for the bottom create-workspace input.
  final TextEditingController createController;

  /// Optional inline validation or persistence error message.
  final String? errorMessage;

  /// Whether a workspace mutation is currently executing.
  final bool isBusy;

  /// Callback notified when create input changes.
  final ValueChanged<String> onCreateChanged;

  /// Callback submitting new workspace creation.
  final VoidCallback onCreateSubmit;

  /// Callback dismissing [errorMessage].
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _WorkspaceErrorSlot(
          errorMessage: errorMessage,
          onDismiss: onDismissError,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12.0),
          child: Divider(height: 1.0),
        ),
        _WorkspaceCreateSection(
          controller: createController,
          canCreateMore: canCreateMore,
          isBusy: isBusy,
          onChanged: onCreateChanged,
          onSubmit: onCreateSubmit,
        ),
      ],
    );
  }
}

/// Workspace entry card supporting switch tap, inline rename, and inline delete confirmation.
class _WorkspaceModalRowCard extends StatelessWidget {
  /// Creates a [_WorkspaceModalRowCard].
  const _WorkspaceModalRowCard({
    super.key,
    required this.summary,
    required this.isActive,
    required this.canDelete,
    required this.isBusy,
    required this.isRenaming,
    required this.isConfirmingDelete,
    required this.renameController,
    required this.onSelect,
    required this.onStartRename,
    required this.onCancelRename,
    required this.onSaveRename,
    required this.onRenameChanged,
    required this.onRequestDelete,
    required this.onCancelDelete,
    required this.onConfirmDelete,
  });

  /// Whether deleting this workspace is allowed (requires more than one workspace).
  final bool canDelete;

  /// Whether this workspace is currently active in memory.
  final bool isActive;

  /// Whether any workspace mutation is currently executing.
  final bool isBusy;

  /// Whether inline delete confirmation is open for this card.
  final bool isConfirmingDelete;

  /// Whether inline rename mode is open for this card.
  final bool isRenaming;

  /// Callback cancelling delete confirmation.
  final VoidCallback onCancelDelete;

  /// Callback cancelling inline rename.
  final VoidCallback onCancelRename;

  /// Callback confirming deletion of [summary].
  final VoidCallback onConfirmDelete;

  /// Callback notified when rename input changes.
  final ValueChanged<String> onRenameChanged;

  /// Callback opening inline delete confirmation.
  final VoidCallback onRequestDelete;

  /// Callback saving inline rename.
  final VoidCallback onSaveRename;

  /// Callback switching to [summary] when inactive.
  final VoidCallback onSelect;

  /// Callback opening inline rename mode.
  final VoidCallback onStartRename;

  /// Text controller used when [isRenaming] is true.
  final TextEditingController renameController;

  /// Persisted domain workspace summary.
  final WorkspaceSummary summary;

  @override
  Widget build(BuildContext context) {
    return UiCard.standard(
      isHighlighted: isActive,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (isRenaming)
            _WorkspaceInlineRenameRow(
              workspaceId: summary.id,
              controller: renameController,
              isBusy: isBusy,
              onChanged: onRenameChanged,
              onCancel: onCancelRename,
              onSave: onSaveRename,
            )
          else
            _WorkspaceRowMainContent(
              summary: summary,
              isActive: isActive,
              canDelete: canDelete,
              isBusy: isBusy,
              onSelect: onSelect,
              onStartRename: onStartRename,
              onRequestDelete: onRequestDelete,
            ),
          if (isConfirmingDelete && canDelete)
            _WorkspaceDeleteConfirmBar(
              summary: summary,
              isBusy: isBusy,
              onCancel: onCancelDelete,
              onConfirm: onConfirmDelete,
            ),
        ],
      ),
    );
  }
}

/// Workspace title, active badge, and monospace `.tdf` filename column inside [_WorkspaceRowIdentity].
class _WorkspaceRowDetails extends StatelessWidget {
  /// Creates a [_WorkspaceRowDetails].
  const _WorkspaceRowDetails({required this.summary, required this.isActive});

  /// Whether this workspace is currently active in memory.
  final bool isActive;

  /// Persisted domain workspace summary.
  final WorkspaceSummary summary;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              summary.name,
              style: tokens.typography.control.copyWith(
                color: colors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isActive)
              UiPill(
                label: localizations.workspaceActiveBadge,
                variant: UiPillVariant.badge,
                tone: UiPillTone.accent,
              ),
          ],
        ),
        const SizedBox(height: 2.0),
        Text(
          TdfFilePath.extractFileNameFromPath(summary.localFilePath),
          style: UiTypographyTokens.mono(
            tokens.typography.monoSmall.copyWith(color: colors.muted),
          ),
        ),
      ],
    );
  }
}

/// Workspace icon, display name, active badge, and monospace `.tdf` filename inside [_WorkspaceRowMainContent].
class _WorkspaceRowIdentity extends StatelessWidget {
  /// Creates a [_WorkspaceRowIdentity].
  const _WorkspaceRowIdentity({required this.summary, required this.isActive});

  /// Whether this workspace is currently active in memory.
  final bool isActive;

  /// Persisted domain workspace summary.
  final WorkspaceSummary summary;

  @override
  Widget build(BuildContext context) {
    final tokens = UiThemeTokens.of(context);
    final colors = tokens.colors;

    return Row(
      children: <Widget>[
        ExcludeSemantics(
          child: Icon(
            isActive
                ? Icons.check_circle_outline_rounded
                : Icons.workspaces_outlined,
            size: tokens.spacing.iconSm,
            color: isActive ? colors.accent : colors.muted,
          ),
        ),
        const SizedBox(width: 10.0),
        Expanded(
          child: _WorkspaceRowDetails(summary: summary, isActive: isActive),
        ),
      ],
    );
  }
}

/// Primary workspace row display pairing clickable workspace identity with Rename and Delete icon actions.
class _WorkspaceRowMainContent extends StatelessWidget {
  /// Creates a [_WorkspaceRowMainContent].
  const _WorkspaceRowMainContent({
    required this.summary,
    required this.isActive,
    required this.canDelete,
    required this.isBusy,
    required this.onSelect,
    required this.onStartRename,
    required this.onRequestDelete,
  });

  /// Whether deleting this workspace is allowed.
  final bool canDelete;

  /// Whether this workspace is currently active in memory.
  final bool isActive;

  /// Whether a workspace mutation is currently executing.
  final bool isBusy;

  /// Callback opening inline delete confirmation.
  final VoidCallback onRequestDelete;

  /// Callback switching to [summary] when inactive.
  final VoidCallback onSelect;

  /// Callback opening inline rename mode.
  final VoidCallback onStartRename;

  /// Persisted domain workspace summary.
  final WorkspaceSummary summary;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: _WorkspaceSelectableArea(
            summary: summary,
            isActive: isActive,
            canSwitch: !isActive && !isBusy,
            onSelect: onSelect,
          ),
        ),
        const SizedBox(width: 8.0),
        UiButton(
          key: ValueKey<String>('workspace_rename_button_${summary.id}'),
          leadingIcon: Icons.edit_outlined,
          variant: UiButtonVariant.icon,
          density: UiButtonDensity.compact,
          tooltip: localizations.tooltipRenameWorkspace,
          onPressed: isBusy ? null : onStartRename,
        ),
        const SizedBox(width: 2.0),
        UiButton(
          key: ValueKey<String>('workspace_delete_button_${summary.id}'),
          leadingIcon: Icons.delete_outline_rounded,
          variant: UiButtonVariant.icon,
          density: UiButtonDensity.compact,
          isDangerHover: true,
          tooltip: localizations.tooltipDeleteWorkspace,
          onPressed: (canDelete && !isBusy) ? onRequestDelete : null,
        ),
      ],
    );
  }
}

/// Interactive wrapper enabling pointer and keyboard activation only for inactive workspace rows.
class _WorkspaceSelectableArea extends StatelessWidget {
  /// Creates a [_WorkspaceSelectableArea].
  const _WorkspaceSelectableArea({
    required this.summary,
    required this.isActive,
    required this.canSwitch,
    required this.onSelect,
  });

  /// Whether tapping or activating this area switches workspaces.
  final bool canSwitch;

  /// Whether this workspace is currently active in memory.
  final bool isActive;

  /// Switch callback.
  final VoidCallback onSelect;

  /// Persisted domain workspace summary.
  final WorkspaceSummary summary;

  @override
  Widget build(BuildContext context) {
    final identity = _WorkspaceRowIdentity(
      summary: summary,
      isActive: isActive,
    );
    if (!canSwitch) {
      return KeyedSubtree(
        key: ValueKey<String>('workspace_select_${summary.id}'),
        child: identity,
      );
    }
    return Semantics(
      button: true,
      label: summary.name,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onSelect();
              return null;
            },
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) {
              onSelect();
              return null;
            },
          ),
        },
        child: GestureDetector(
          key: ValueKey<String>('workspace_select_${summary.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: onSelect,
          child: identity,
        ),
      ),
    );
  }
}

/// Monospace suggested `.tdf` filename preview rendered below the create-workspace input.
class _WorkspaceSuggestedFileCaption extends StatelessWidget {
  /// Creates a [_WorkspaceSuggestedFileCaption].
  const _WorkspaceSuggestedFileCaption({required this.rawName});

  /// Raw workspace display name used to derive the suggested `.tdf` filename.
  final String rawName;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = UiThemeTokens.of(context);
    return Text(
      localizations.workspaceSuggestedFileLabel(
        AppWorkspace.suggestFileName(rawName),
      ),
      key: const ValueKey<String>('workspace_suggested_file'),
      style: UiTypographyTokens.mono(
        tokens.typography.monoSmall.copyWith(color: tokens.colors.muted),
      ),
    );
  }
}

/// Centered modal managing isolated workspaces (switch, create, inline rename, and inline delete).
class _WorkspacesModal extends ConsumerStatefulWidget {
  /// Creates a [_WorkspacesModal].
  const _WorkspacesModal({required this.onClose});

  /// Callback closing this modal route.
  final VoidCallback onClose;

  @override
  ConsumerState<_WorkspacesModal> createState() => _WorkspacesModalState();
}

/// State managing inline rename, inline delete confirmation, creation input, and error readout for [_WorkspacesModal].
class _WorkspacesModalState extends ConsumerState<_WorkspacesModal> {
  final TextEditingController _createController = TextEditingController();
  String? _errorMessage;
  String? _pendingDeleteWorkspaceId;
  final TextEditingController _renameController = TextEditingController();
  String? _renamingWorkspaceId;

  @override
  void dispose() {
    _createController.dispose();
    _renameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final snapshot = _resolveWorkspaceSnapshot(
      ref.watch(activeWorkspaceProvider),
      ref.watch(workspaceSummariesProvider),
    );
    final isBusy = ref.watch(
      workspaceActionsProvider.select((state) => state.isBusy),
    );

    return UiDialogFrame(
      key: const ValueKey<String>('workspaces_modal'),
      title: localizations.workspacesDialogTitle,
      subtitle: localizations.workspacesDialogDescription,
      size: UiDialogSize.large,
      closeTooltip: localizations.actionClose,
      onClose: widget.onClose,
      body: _WorkspaceModalBody(
        snapshot: snapshot,
        isBusy: isBusy,
        renamingWorkspaceId: _renamingWorkspaceId,
        pendingDeleteWorkspaceId: _pendingDeleteWorkspaceId,
        errorMessage: _errorMessage,
        createController: _createController,
        renameController: _renameController,
        onSelectWorkspace: _triggerSwitchWorkspace,
        onStartRename: _handleStartRename,
        onCancelRename: _handleCancelRename,
        onSaveRename: _triggerSaveRename,
        onRenameChanged: _handleRenameInputChanged,
        onRequestDelete: _handleRequestDelete,
        onCancelDelete: _handleCancelDelete,
        onConfirmDelete: _triggerConfirmDelete,
        onCreateChanged: _handleCreateInputChanged,
        onCreateSubmit: _triggerCreateWorkspace,
        onDismissError: _clearError,
      ),
    );
  }

  /// Dismisses any visible workspace error banner.
  void _clearError() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  /// Cancels an active inline delete confirmation bar.
  void _handleCancelDelete() {
    setState(() => _pendingDeleteWorkspaceId = null);
  }

  /// Exits inline rename mode without saving.
  void _handleCancelRename() {
    setState(() {
      _renamingWorkspaceId = null;
      _renameController.clear();
    });
  }

  /// Deletes [workspaceId] via [WorkspaceActionsNotifier] and clears confirmation on success.
  Future<void> _handleConfirmDelete(String workspaceId) async {
    _clearError();
    final result = await ref
        .read(workspaceActionsProvider.notifier)
        .deleteWorkspace(workspaceId);
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        setState(() {
          _pendingDeleteWorkspaceId = null;
          if (_renamingWorkspaceId == workspaceId) {
            _renamingWorkspaceId = null;
            _renameController.clear();
          }
        });
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        _showError(message);
    }
  }

  /// Clears any visible error banner when create text changes without rebuilding the workspace list.
  void _handleCreateInputChanged(String _) {
    _clearError();
  }

  /// Creates and activates a workspace from [_createController], closing the modal on success.
  Future<void> _handleCreateWorkspace() async {
    _clearError();
    final result = await ref
        .read(workspaceActionsProvider.notifier)
        .createWorkspace(_createController.text, activate: true);
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        widget.onClose();
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        _showError(message);
    }
  }

  /// Clears errors when inline rename text changes.
  void _handleRenameInputChanged(String _) {
    _clearError();
  }

  /// Opens inline delete confirmation for [workspaceId].
  void _handleRequestDelete(String workspaceId) {
    setState(() {
      _renamingWorkspaceId = null;
      _pendingDeleteWorkspaceId = workspaceId;
      _errorMessage = null;
    });
  }

  /// Saves inline rename for [workspaceId] via [WorkspaceActionsNotifier].
  Future<void> _handleSaveRename(String workspaceId) async {
    _clearError();
    final result = await ref
        .read(workspaceActionsProvider.notifier)
        .renameWorkspace(workspaceId, _renameController.text);
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        setState(() {
          _renamingWorkspaceId = null;
          _renameController.clear();
        });
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        _showError(message);
    }
  }

  /// Opens inline rename mode pre-filled with [summary.name].
  void _handleStartRename(WorkspaceSummary summary) {
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

  /// Switches the active workspace to [workspaceId] and closes the modal on success.
  Future<void> _handleSwitchWorkspace(String workspaceId) async {
    _clearError();
    final result = await ref
        .read(workspaceActionsProvider.notifier)
        .switchWorkspace(workspaceId);
    if (!mounted) {
      return;
    }
    switch (result) {
      case ActionSucceeded():
        widget.onClose();
      case ActionValidationFailed(:final message):
      case ActionPersistFailed(:final message):
        _showError(message);
    }
  }

  /// Displays non-empty validation or persistence error messages inline.
  void _showError(String message) {
    if (message.isNotEmpty) {
      setState(() => _errorMessage = message);
    }
  }

  /// Dispatches async deletion for [workspaceId] from synchronous callbacks.
  void _triggerConfirmDelete(String workspaceId) {
    unawaited(_handleConfirmDelete(workspaceId));
  }

  /// Dispatches async creation from synchronous callbacks.
  void _triggerCreateWorkspace() {
    unawaited(_handleCreateWorkspace());
  }

  /// Dispatches async rename save for [workspaceId] from synchronous callbacks.
  void _triggerSaveRename(String workspaceId) {
    unawaited(_handleSaveRename(workspaceId));
  }

  /// Dispatches async workspace switch for [workspaceId] from synchronous callbacks.
  void _triggerSwitchWorkspace(String workspaceId) {
    unawaited(_handleSwitchWorkspace(workspaceId));
  }
}

/// Immutable per-frame workspace listing snapshot derived from [activeWorkspaceProvider] and [workspaceSummariesProvider].
typedef _WorkspaceListSnapshot = ({
  String activeWorkspaceId,
  bool canCreateMore,
  bool isLoading,
  List<WorkspaceSummary> summaries,
});

/// Presents the isolated workspaces manager modal supporting switching, creation, inline rename, and inline deletion.
Future<void> showWorkspacesModal(BuildContext context) {
  UiTelemetry.logDialogOpened('workspaces');
  final localizations = AppLocalizations.of(context);
  return UiDialogFrame.showModal<void>(
    context: context,
    barrierLabel: localizations.workspacesDialogTitle,
    builder: (modalContext) =>
        _WorkspacesModal(onClose: () => Navigator.of(modalContext).maybePop()),
  );
}

/// Resolves active workspace ID, summary list, capacity flag, and initial loading state from live async providers.
_WorkspaceListSnapshot _resolveWorkspaceSnapshot(
  AsyncValue<AppWorkspace> activeWorkspaceAsync,
  AsyncValue<List<WorkspaceSummary>> summariesAsync,
) {
  final activeWorkspace =
      activeWorkspaceAsync.asData?.value ?? AppWorkspace.defaultWorkspace;
  final summaries =
      summariesAsync.asData?.value ??
      <WorkspaceSummary>[activeWorkspace.summary];
  final isLoading =
      (activeWorkspaceAsync.isLoading && !activeWorkspaceAsync.hasValue) ||
      (summariesAsync.isLoading && !summariesAsync.hasValue);
  return (
    activeWorkspaceId: activeWorkspace.id,
    canCreateMore: summaries.length < AppWorkspace.maxWorkspaces,
    isLoading: isLoading,
    summaries: summaries,
  );
}
